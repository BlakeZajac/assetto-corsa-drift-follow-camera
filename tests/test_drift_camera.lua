-- Run from the repository root: luajit tests/test_drift_camera.lua
-- Executes the real camera with a small CSP API double; it does not render AC.
local cameraPath = 'extension/lua/chaser-camera/drift-follow/camera.lua'
local settingsPath = 'extension/lua/chaser-camera/drift-follow/settings.ini'
local pi = math.pi
local tests = 0

local function near(actual, expected, tolerance, label)
  assert(math.abs(actual - expected) <= (tolerance or 1e-7),
    (label or 'value') .. ': expected ' .. expected .. ', got ' .. actual)
end

local function newCamera(settings)
  local count = 0
  local vector = {}
  vector.__index = vector
  function vector:set(x, y, z)
    if type(x) == 'table' then x, y, z = x.x, x.y, x.z end
    self.x, self.y, self.z = x, y, z
    return self
  end
  local function vec3(x, y, z)
    count = count + 1
    return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, vector)
  end
  local ctx = {
    math = math, type = type, vec3 = vec3, script = {},
    sim = { time = 0, dt = 1 / 60, isPaused = false,
      isReplayActive = false, replayPlaybackRate = 1 },
    car = { index = 0, transform = { position = vec3() },
      velocity = vec3(), look = vec3(0, 0, 1), up = vec3(0, 1, 0) },
    lookInput = 0, slot = 1
  }
  ctx.allocations = function() return count end
  ctx.ac = {
    Camera = {},
    INIConfig = { scriptSettings = function()
      return { mapSection = function(_, section, defaults)
        assert(section == 'SETTINGS')
        ctx.defaults = defaults
        for key, value in pairs(settings or {}) do defaults[key] = value end
        return defaults
      end }
    end },
    getDesiredLookDirection = function() return ctx.lookInput end,
    onReplay = function(callback) ctx.replayEvent = callback end,
    onCarJumped = function(index, callback)
      assert(index == -1)
      ctx.jumpEvent = callback
    end
  }
  setmetatable(ctx.ac, { __index = function(_, key) error('Unmocked CSP API: ' .. key) end })
  local chunk = assert(loadfile(cameraPath))
  setfenv(chunk, ctx)
  chunk()
  return ctx
end

local function pose(ctx, yaw, vx, vz, pitch, roll)
  pitch, roll = pitch or 0, roll or 0
  local sy, cy, sp, cp = math.sin(yaw), math.cos(yaw), math.sin(pitch), math.cos(pitch)
  local sr, cr = math.sin(roll), math.cos(roll)
  ctx.car.look:set(sy * cp, sp, cy * cp)
  ctx.car.up:set(-sy * sp * cr + cy * sr, cp * cr, -cy * sp * cr - sy * sr)
  ctx.car.velocity:set(vx, 0, vz)
end

local function update(ctx, dt)
  dt = dt or 1 / 60
  ctx.sim.time = ctx.sim.time + math.abs(dt) * 1000
  ctx.sim.dt = dt
  ctx.script.update(dt, ctx.slot)
end

local function run(ctx, seconds, fps)
  for _ = 1, math.floor(seconds * fps + 0.5) do update(ctx, 1 / fps) end
end

local function validate(ctx)
  local camera = ctx.ac.Camera
  for _, vector in ipairs({ camera.position, camera.direction, camera.up }) do
    assert(vector, 'Camera output was not written')
    for _, value in ipairs({ vector.x, vector.y, vector.z }) do
      assert(value == value and math.abs(value) < math.huge, 'Non-finite camera output')
    end
  end
  local d, u = camera.direction, camera.up
  near(d.x * d.x + d.y * d.y + d.z * d.z, 1, 1e-6, 'direction length')
  near(u.x * u.x + u.y * u.y + u.z * u.z, 1, 1e-6, 'up length')
  near(d.x * u.x + d.y * u.y + d.z * u.z, 0, 1e-6, 'camera basis')
  assert(camera.fov >= 35 and camera.fov <= 95, 'FOV out of bounds')
end

local function offset(ctx)
  local p, c = ctx.car.transform.position, ctx.ac.Camera.position
  return c.x - p.x, c.y - p.y, c.z - p.z
end

local function yaw(ctx)
  local x, _, z = offset(ctx)
  return math.atan2(-x, -z)
end

local function angleDifference(a, b)
  return (a - b + pi) % (2 * pi) - pi
end

local function samePose(a, b)
  local ax, ay, az = offset(a)
  local bx, by, bz = offset(b)
  near(ax, bx); near(ay, by); near(az, bz)
  for _, key in ipairs({ 'x', 'y', 'z' }) do
    near(a.ac.Camera.direction[key], b.ac.Camera.direction[key])
  end
end

local function test(name, fn)
  fn()
  tests = tests + 1
  print('PASS ' .. name)
end

test('settings file and runtime defaults agree', function()
  local ctx = newCamera()
  local file = assert(io.open(settingsPath))
  local entries = 0
  for line in file:lines() do
    local key, value = line:match('^([A-Z_]+)%s*=%s*([%d%.%-]+)')
    if key then
      assert(ctx.defaults[key] ~= nil, 'Unused setting: ' .. key)
      near(ctx.defaults[key], tonumber(value), 0, key)
      entries = entries + 1
    end
  end
  file:close()
  local defaults = 0
  for _ in pairs(ctx.defaults) do defaults = defaults + 1 end
  near(entries, defaults, 0, 'settings count')
end)

test('stationary initialization stays behind the car', function()
  local ctx = newCamera()
  update(ctx)
  local x, y, z = offset(ctx)
  near(x, 0); near(y, 1.8); near(z, -6)
  validate(ctx)
  run(ctx, 3, 60)
  near(yaw(ctx), 0)
end)

test('left and right slides are mirrored and bounded', function()
  local left, right = newCamera(), newCamera()
  pose(left, 0, -20, 20); pose(right, 0, 20, 20)
  run(left, 2, 60); run(right, 2, 60)
  assert(yaw(left) < 0 and yaw(right) > 0, 'Slide followed in the wrong direction')
  near(yaw(left), -yaw(right))
  assert(math.abs(yaw(left)) <= math.rad(60) * 0.65 + 1e-7)
  validate(left); validate(right)
end)

test('zero slide-follow retains heading-based framing', function()
  local ctx = newCamera({ SLIDE_FOLLOW = 0 })
  pose(ctx, 0, 30, 5)
  run(ctx, 1, 60)
  near(yaw(ctx), 0)
end)

test('transition response is consistent at 30, 60 and 144 FPS', function()
  local outputs = {}
  for _, fps in ipairs({ 30, 60, 144 }) do
    local ctx = newCamera()
    update(ctx)
    pose(ctx, 0, 20, 20)
    run(ctx, 0.5, fps)
    outputs[#outputs + 1] = ctx
    validate(ctx)
  end
  samePose(outputs[1], outputs[2]); samePose(outputs[2], outputs[3])
end)

test('reversing and slow donuts do not orbit toward velocity', function()
  local ctx = newCamera()
  pose(ctx, 0, 2, -15)
  run(ctx, 2, 60)
  near(yaw(ctx), 0)
  pose(ctx, 0, 0.2, 0.1)
  run(ctx, 2, 60)
  near(yaw(ctx), 0)
end)

test('a moving spin remains finite without angle-wrap snaps', function()
  local ctx = newCamera()
  update(ctx)
  local previous = yaw(ctx)
  for i = 1, 360 do
    pose(ctx, i * 2 * pi / 180, 0, 20)
    update(ctx)
    validate(ctx)
    assert(math.abs(angleDifference(yaw(ctx), previous)) < 0.16, 'Camera snapped during spin')
    previous = yaw(ctx)
  end
end)

test('manual look works and equivalent rear-look signs do not sweep around', function()
  local ctx = newCamera()
  update(ctx)
  ctx.lookInput = 0.5
  run(ctx, 3, 60)
  near(yaw(ctx), pi / 2, 1e-6)
  ctx.lookInput = 1
  run(ctx, 3, 60)
  near(math.abs(yaw(ctx)), pi, 1e-6)
  local previous = yaw(ctx)
  ctx.lookInput = -1
  update(ctx)
  assert(math.abs(angleDifference(yaw(ctx), previous)) < 1e-6)
  ctx.lookInput = 0
  run(ctx, 4, 60)
  near(yaw(ctx), 0, 1e-6)
end)

test('teleport callback and distance fallback clear stale motion', function()
  for _, callback in ipairs({ false, true }) do
    local ctx, fresh = newCamera(), newCamera()
    pose(ctx, 0, 20, 20)
    run(ctx, 1, 60)
    ctx.car.transform.position:set(500, 40, -200)
    pose(ctx, 1.8, -10, 12)
    pose(fresh, 1.8, -10, 12)
    if callback then ctx.jumpEvent(ctx.car.index) end
    update(ctx); update(fresh)
    samePose(ctx, fresh); validate(ctx)
  end
end)

test('unrelated car resets do not erase current smoothing', function()
  local a, b = newCamera(), newCamera()
  update(a); update(b)
  pose(a, 0, 20, 20); pose(b, 0, 20, 20)
  a.jumpEvent(99)
  update(a); update(b)
  samePose(a, b)
end)

test('replay seek resets at the same location while paused', function()
  local ctx, fresh = newCamera(), newCamera()
  ctx.sim.isReplayActive = true
  update(ctx)
  ctx.sim.isPaused = true
  pose(ctx, 2, 20, 10); pose(fresh, 2, 20, 10)
  ctx.replayEvent('jump')
  update(ctx, 0); update(fresh)
  samePose(ctx, fresh); validate(ctx)
end)

test('pause and stopped replay freeze camera smoothing', function()
  for _, replay in ipairs({ false, true }) do
    local ctx = newCamera()
    ctx.sim.isReplayActive = replay
    update(ctx)
    ctx.sim.isPaused = not replay
    if replay then ctx.sim.replayPlaybackRate = 0 end
    ctx.lookInput = 1
    run(ctx, 1, 60)
    near(yaw(ctx), 0)
    validate(ctx)
  end
end)

test('car changes and long inactive gaps reset framing', function()
  for _, kind in ipairs({ 'index', 'callback', 'gap', 'clock' }) do
    local ctx, fresh = newCamera(), newCamera()
    update(ctx)
    pose(ctx, 1.5, 0, 20); pose(fresh, 1.5, 0, 20)
    if kind == 'index' then ctx.car.index = 1
    elseif kind == 'callback' then ctx.script.onCarChanged()
    elseif kind == 'gap' then ctx.sim.time = ctx.sim.time + 1000
    else ctx.sim.time = -1000 end
    update(ctx); update(fresh)
    samePose(ctx, fresh)
  end
end)

test('far slot has distinct framing and switching back clears stale history', function()
  local ctx, fresh = newCamera(), newCamera()
  update(ctx)
  ctx.slot = 2
  update(ctx)
  local _, y, z = offset(ctx)
  near(z, -7.5); near(y, 2.05)
  pose(ctx, 2, 20, 20); pose(fresh, 2, 20, 20)
  ctx.slot = 1
  update(ctx); update(fresh)
  samePose(ctx, fresh)
end)

test('slopes follow pitch and full horizon lock removes body roll', function()
  local ctx = newCamera({ HORIZON_LOCK = 1 })
  pose(ctx, 0, 0, 20, math.rad(10), math.rad(40))
  update(ctx)
  local _, y = offset(ctx)
  assert(y < 1.8, 'Camera should sit down-slope behind a climbing car')
  near(ctx.ac.Camera.up.x, 0)
  validate(ctx)
  local flat = newCamera({ SLOPE_FOLLOW = 0 })
  pose(flat, 0, 0, 20, math.rad(10))
  update(flat)
  local _, flatY = offset(flat)
  near(flatY, 1.8)
end)

test('cinematic preset changes framing and responds more slowly', function()
  local driving, cinema = newCamera(), newCamera({ PRESET = 1 })
  update(driving); update(cinema)
  near(cinema.ac.Camera.fov, 46)
  local _, y, z = offset(cinema)
  near(y, 1.95); near(z, -6.6)
  pose(driving, 0, 20, 20); pose(cinema, 0, 20, 20)
  run(driving, 0.1, 60); run(cinema, 0.1, 60)
  assert(yaw(driving) > yaw(cinema) and yaw(cinema) > 0)
end)

test('view-aligned body up uses a valid level fallback', function()
  local ctx = newCamera({ HORIZON_LOCK = 0 })
  update(ctx)
  ctx.car.up:set(ctx.ac.Camera.direction)
  update(ctx)
  validate(ctx)
end)

test('malformed settings, zero vectors and large frame gaps stay finite', function()
  local ctx = newCamera({ DISTANCE = -100, HEIGHT = math.huge, FOV = 0 / 0,
    SMOOTHING = 0, MAX_SLIDE_ANGLE = 1e6, HORIZON_LOCK = 0.5 })
  ctx.car.look:set(0, 1, 0)
  ctx.car.up:set(0, -1, 0)
  update(ctx, 0); validate(ctx)
  update(ctx, 2); validate(ctx)
  ctx.sim.dt = 0 / 0
  ctx.script.update(0, 1); validate(ctx)
end)

test('smoothing does not allocate vectors per frame', function()
  local ctx = newCamera()
  update(ctx)
  local before = ctx.allocations()
  for i = 1, 1000 do
    pose(ctx, math.sin(i / 20) * 0.5, math.sin(i / 15) * 20, 20)
    update(ctx)
  end
  near(ctx.allocations(), before, 0, 'vector allocations')
end)

test('randomized motion, replay direction and reset events preserve camera invariants', function()
  math.randomseed(49217)
  for _, preset in ipairs({ 0, 1 }) do
    local ctx = newCamera({ PRESET = preset, HORIZON_LOCK = 0 })
    for i = 1, 3000 do
      local dt = 1 / (20 + math.random() * 160)
      local heading = math.sin(i / 50) * pi * 2
      pose(ctx, heading, (math.random() - 0.5) * 70, (math.random() - 0.5) * 70,
        math.sin(i / 25) * 1.3, math.sin(i / 30) * pi)
      ctx.car.transform.position.x = ctx.car.transform.position.x + ctx.car.velocity.x * dt
      ctx.car.transform.position.z = ctx.car.transform.position.z + ctx.car.velocity.z * dt
      ctx.lookInput = math.sin(i / 80)
      if i % 300 == 0 then
        ctx.sim.isReplayActive = not ctx.sim.isReplayActive
        ctx.sim.replayPlaybackRate = -ctx.sim.replayPlaybackRate
        ctx.replayEvent('jump')
      end
      if i % 97 == 0 then
        ctx.car.transform.position.x = ctx.car.transform.position.x + 200
        ctx.jumpEvent(ctx.car.index)
      end
      if i % 131 == 0 then ctx.slot = ctx.slot == 1 and 2 or 1 end
      update(ctx, dt)
      validate(ctx)
    end
  end
end)

print(tests .. ' camera checks passed. AC rendering and camera feel still require in-game testing.')
