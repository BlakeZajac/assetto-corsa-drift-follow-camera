-- Drift Follow. Distances are metres, angles inside the script are radians.
-- Yaw follows a blend of body heading and forward travel, with per-slot state.
local cfg = ac.INIConfig.scriptSettings():mapSection('SETTINGS', {
  PRESET = 0,
  DISTANCE = 6,
  HEIGHT = 1.8,
  FOV = 50,
  SLIDE_FOLLOW = 0.65,
  MAX_SLIDE_ANGLE = 60,
  SMOOTHING = 1,
  LOOK_AHEAD = 1,
  HORIZON_LOCK = 0.95,
  SLOPE_FOLLOW = 1
})

local pi = math.pi
local tau = 2 * pi
local function clamp(v, low, high)
  return math.max(low, math.min(high, v))
end

local function number(v, fallback)
  if type(v) ~= 'number' or v ~= v or v == math.huge or v == -math.huge then
    return fallback
  end
  return v
end

local cinematic = number(cfg.PRESET, 0) >= 0.5
local distance = clamp(number(cfg.DISTANCE, 6), 3, 12) + (cinematic and 0.6 or 0)
local height = clamp(number(cfg.HEIGHT, 1.8), 0.7, 4) + (cinematic and 0.15 or 0)
local fov = clamp(number(cfg.FOV, 50) - (cinematic and 4 or 0), 35, 95)
local slideFollow = clamp(number(cfg.SLIDE_FOLLOW, 0.65), 0, 1)
local maxSlide = math.rad(clamp(number(cfg.MAX_SLIDE_ANGLE, 60), 0, 85))
local smoothing = clamp(number(cfg.SMOOTHING, 1), 0.35, 2.5)
local yawTime = (cinematic and 0.30 or 0.14) * smoothing
local slopeTime = (cinematic and 0.30 or 0.18) * smoothing
local lookAhead = clamp(number(cfg.LOOK_AHEAD, 1), 0, 3)
local horizonLock = clamp(number(cfg.HORIZON_LOCK, 0.95), 0, 1)
local slopeFollow = clamp(number(cfg.SLOPE_FOLLOW, 1), 0, 1)

local function wrap(angle)
  return (angle + pi) % tau - pi
end

local function smoothAngle(value, target, blend)
  return wrap(value + wrap(target - value) * blend)
end

local function smoothstep(low, high, value)
  local t = clamp((value - low) / (high - low), 0, 1)
  return t * t * (3 - 2 * t)
end

local function newState()
  return { generation = -1, position = vec3() }
end

-- Separate history prevents the two chase slots from sharing old motion.
local states = { newState(), newState() }
local generation = 0
local activeIndex
local function reset()
  generation = generation + 1
end

ac.onReplay(reset)
ac.onCarJumped(-1, function(index)
  if car and car.index == index then reset() end
end)

function script.onCarChanged()
  reset()
end

-- Reuse output vectors; the per-frame callback does not create Lua tables/vectors.
local cameraPosition = vec3()
local cameraDirection = vec3()
local cameraUp = vec3()

function script.update(dt, cameraIndex)
  if not car then return end

  local index = cameraIndex == 2 and 2 or 1
  local state = states[index]
  local clock = number(sim.time, 0)
  local step = number(sim.dt, number(dt, 0))
  local replay = sim.isReplayActive
  local replayRate = number(sim.replayPlaybackRate, 1)
  if sim.isPaused or (replay and replayRate == 0) then step = 0 end
  step = math.abs(step)
  local replayDirection = replayRate < 0 and -1 or 1

  local position = car.transform.position
  local vx, vz = car.velocity.x, car.velocity.z
  local speed = math.sqrt(vx * vx + vz * vz)
  local lx, lz = car.look.x, car.look.z
  local horizontalLength = math.sqrt(lx * lx + lz * lz)
  local heading = state.heading or 0
  if horizontalLength > 0.001 then
    lx, lz = lx / horizontalLength, lz / horizontalLength
    heading = math.atan2(lx, lz)
  else
    lx, lz = math.sin(heading), math.cos(heading)
  end

  -- Fade slide tracking out at walking speed and when travelling backwards.
  -- This avoids the +/-180-degree velocity flip during spins and reversing.
  local forward = vx * lx + vz * lz
  local sideways = vx * lz - vz * lx
  local forwardWeight = smoothstep(0, 0.35, forward / math.max(speed, 0.001))
  local motionWeight = smoothstep(1, 5, speed) * forwardWeight
  local slip = clamp(math.atan2(sideways, forward), -maxSlide, maxSlide)
  local manualLook = clamp(number(ac.getDesiredLookDirection(), 0), -1, 1)
  local slide = slip * slideFollow * motionWeight * (1 - math.abs(manualLook))
  local targetYaw = wrap(heading + slide + manualLook * pi)
  local targetPathYaw = wrap(heading + slip * motionWeight * 0.5)
  local targetAhead = lookAhead * motionWeight * (1 - math.abs(manualLook))

  local resetState = activeIndex ~= index or state.generation ~= generation or state.carIndex ~= car.index
    or state.replay ~= replay or state.replayDirection ~= replayDirection or step > 0.25
  if state.lastClock then
    -- sim.time is milliseconds; step is seconds. The distance threshold scales
    -- with speed so normal fast travel is not mistaken for a teleport.
    local dx = position.x - state.position.x
    local dy = position.y - state.position.y
    local dz = position.z - state.position.z
    local jumpDistance = 12 + speed * math.min(step, 0.25) * 3
    resetState = resetState or clock < state.lastClock or clock - state.lastClock > 500
      or dx * dx + dy * dy + dz * dz > jumpDistance * jumpDistance
  end

  if resetState then
    state.yaw, state.pathYaw, state.ahead = targetYaw, targetPathYaw, targetAhead
  elseif step > 0 then
    -- Exponential response keeps the time constant consistent at different FPS.
    local blend = 1 - math.exp(-step / yawTime)
    state.yaw = smoothAngle(state.yaw, targetYaw, blend)
    state.pathYaw = smoothAngle(state.pathYaw, targetPathYaw, blend)
    state.ahead = state.ahead + (targetAhead - state.ahead) * blend
  end

  local radius = distance + (index == 2 and 1.5 or 0)
  local cameraHeight = height + (index == 2 and 0.25 or 0)
  local slope = clamp(car.look.y / math.max(horizontalLength, 0.001), -0.6, 0.6)
  local targetSlope = -radius * slope * math.cos(state.yaw - heading) * slopeFollow
  if resetState then
    state.slope = targetSlope
  elseif step > 0 then
    state.slope = state.slope + (targetSlope - state.slope) * (1 - math.exp(-step / slopeTime))
  end

  cameraPosition:set(position.x - math.sin(state.yaw) * radius,
    position.y + cameraHeight + state.slope,
    position.z - math.cos(state.yaw) * radius)

  -- Aim near the body with a small, smoothed roadward offset.
  local dx = position.x + math.sin(state.pathYaw) * state.ahead - cameraPosition.x
  local dy = position.y + 0.65 - cameraPosition.y
  local dz = position.z + math.cos(state.pathYaw) * state.ahead - cameraPosition.z
  local length = math.sqrt(dx * dx + dy * dy + dz * dz)
  if length < 0.001 then
    dx, dy, dz, length = math.sin(state.yaw), 0, math.cos(state.yaw), 1
  end
  dx, dy, dz = dx / length, dy / length, dz / length
  cameraDirection:set(dx, dy, dz)

  -- Project the chosen up vector off the view direction for a valid camera basis.
  local ux = car.up.x * (1 - horizonLock)
  local uy = car.up.y * (1 - horizonLock) + horizonLock
  local uz = car.up.z * (1 - horizonLock)
  local projection = ux * dx + uy * dy + uz * dz
  ux, uy, uz = ux - projection * dx, uy - projection * dy, uz - projection * dz
  local upLength = math.sqrt(ux * ux + uy * uy + uz * uz)
  if upLength < 0.001 then
    -- A rolled car can align its up vector with the camera; use a level fallback.
    ux, uy, uz = -dy * dx, 1 - dy * dy, -dy * dz
    upLength = math.sqrt(ux * ux + uy * uy + uz * uz)
    if upLength < 0.001 then
      ux, uy, uz = 1 - dx * dx, -dx * dy, -dx * dz
      upLength = math.sqrt(ux * ux + uy * uy + uz * uz)
    end
  end
  cameraUp:set(ux / upLength, uy / upLength, uz / upLength)

  ac.Camera.position = cameraPosition
  ac.Camera.direction = cameraDirection
  ac.Camera.up = cameraUp
  ac.Camera.fov = fov

  state.generation, state.carIndex = generation, car.index
  state.replay, state.replayDirection = replay, replayDirection
  state.heading, state.lastClock = heading, clock
  state.position:set(position)
  activeIndex = index
end
