# Drift Follow Camera

A drift-focused chase camera for Assetto Corsa and Custom Shaders Patch. Smooth slide tracking, a stable horizon and adjustable Driving/Cinematic presets.

![Nissan S14 drifting at Brooklyn Park](docs/images/hud-wet-overlay.png)

*Illustrative HUD overlay with sample telemetry.*

## Install

Requires **Assetto Corsa**, **Content Manager** and **CSP with scripted chase cameras**. Tested on CSP **0.3.0-preview649**. Pure is optional.

1. Close the driving session.
2. Copy `extension/` into your Assetto Corsa game folder, merging it with the existing folder.
3. Check that `extension/lua/chaser-camera/drift-follow/camera.lua` exists inside the game folder.
4. In Content Manager, open **Settings → Custom Shaders Patch → Chase Camera**, enable it and select **Drift Follow**.
5. Start a session and select a chase view. Adjust the camera's options on the same CSP settings page.

Start with **Driving**: 6 m distance, 1.8 m height and 50° FOV. Existing camera choices remain available.

## Settings

| Setting | Default | Range | Effect |
| --- | --- | --- | --- |
| Preset | Driving (`0`) | Driving / Cinematic (`1`) | Cinematic rotates more slowly, adds 0.6 m distance and 0.15 m height, and subtracts 4° FOV. |
| Distance | 6 m | 3–12 m | Moves the camera closer to or farther from the car. |
| Height | 1.8 m | 0.7–4 m | Height above the car's origin on level ground. |
| Field of view | 50° | 35–95° | Lower is tighter; higher shows more surroundings. |
| Slide follow | 65% | 0–100% | How strongly the view rotates towards the slide. |
| Maximum slide angle | 60° | 0–85° | Limits the slip angle used for tracking, before slide-follow strength is applied. |
| Smoothing | 1 | 0.35–2.5 | Lower reacts faster; higher moves more slowly. |
| Look-ahead | 1 m | 0–3 m | Aims farther towards the road while moving forwards. |
| Horizon stability | 95% | 0–100% | Higher keeps the horizon more level; lower follows body roll. |
| Slope follow | 100% | 0–100% | Adjusts the camera's height to follow the car's pitch on hills. |

The far chase slot adds **1.5 m distance** and **0.25 m height**. Camera obstruction avoidance is not included.

## Quick fixes

- **Missing from the list?** Check the folder path and reopen Content Manager.
- **Edits not showing?** Restart the session. Saved CSP settings override source defaults.
- **Want to remove it?** Select another chase script, then delete only `extension/lua/chaser-camera/drift-follow/`.

For tuning examples, saved-settings resets, code changes and tests, see the [detailed guide](docs/guide.md).

## License

[PolyForm Noncommercial 1.0.0](LICENSE.md): use, modify and share for noncommercial purposes under its terms. Commercial use needs separate permission. [Third-party notices](NOTICE.md).
