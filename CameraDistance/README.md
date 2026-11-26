# Camera Distance & Framing Studio for Dragon's Dogma 2

An REFramework Lua mod for **Dragon's Dogma 2** that provides complete control over camera distance, contextual Exploration vs. Combat zoom, Over-the-Shoulder (OTS) 3rd-person framing, RTS / Tactical Bird's-Eye orbital camera mode, Field of View (FOV), and on-the-fly hotkeys.

**Nothing changes until you choose it.** A fresh install uses the game's own camera, with the camera keys, mouse-wheel zoom and controller buttons switched off. Open the REFramework menu (Insert), find **Camera Distance & Framing**, and click a camera style or tick an extra. The only things on from the start are the two couch co-op helpers, which do nothing outside DirectPawnControl co-op.

---

## Features

- **Contextual Distance Offsets (Exploration vs. Combat)**:
  - Set independent camera distances for normal exploration and active combat (triggered when your weapon is drawn and/or when hostile enemies are nearby).
  - Configurable post-combat hold timer and smooth exponential transitions so the camera glides naturally without jarring snaps.
- **Over-the-Shoulder (OTS) & 3rd-Person Framing**:
  - **Horizontal Shoulder Offset (`X`)**: Frame your character over the left or right shoulder (RE4 / God of War style) with an instant **Swap Shoulder** button & hotkey.
  - **Vertical Height Offset (`Y`)**: Raise or lower the camera relative to your character.
  - **Camera Downward Pitch Angle**: Orbit the camera higher above your character and angle the view downward.
  - **Forward Battlefield Lead**: Shift the camera pivot ahead along your look vector to see more of the battlefield in front of you.
- **RTS / Tactical Bird's-Eye Mode**:
  - Toggleable high-altitude orbital camera that lifts the camera above the battlefield and angles it down (`35°–65°`) while keeping full 360° camera rotation and character movement. Ideal for large-scale fights or testing encounters with *Encounter Director*.
- **6 Built-in Camera Styles + Custom Presets**:
  1. `Vanilla (Default)` — Unmodified game camera.
  2. `Over-the-Shoulder (Action 3rd Person)` — Close, immersive over-the-shoulder view that pulls out slightly in combat.
  3. `Classic RPG (Balanced)` — Comfortable wider exploration view (`+1.5m`) that zooms out to `+3.5m` in combat.
  4. `Monster Hunter / Wide Combat` — Wide awareness (`+2.5m` / `+6.0m`) ideal for climbing and fighting large bosses.
  5. `Panoramic (Ultra Wide)` — Far pulled-back camera (`+5.5m` / `+9.0m`) for scenic views and multi-boss battles.
  6. `RTS / Tactical Bird's-Eye` — High-altitude overhead tactical camera.
  - Save and manage your own custom named presets directly in the UI.
- **Field of View (FOV) Control**:
  - Optional base FOV override (`35°–110°`) with an optional dynamic **Combat FOV Boost**, automatically restoring vanilla FOV when disabled or during cutscenes.
  - **Ultrawide lens vignette fix** (2.9.20, on by default): the game darkens the screen edges by angle from the view centre, which on a 21:9 or 32:9 screen becomes a dark circle closing in. The fix scales it to the screen's width so the edges look as they do on 16:9. Also: the game's own, or off.
- **Smart Auto-Suspend Safeguards**:
  - Automatically suspends camera overrides and smoothly blends back to vanilla framing during Pause/Fullscreen Menus, Cutscenes, NPC Dialogues, and Bow/Magick Bow Aiming.
- **Quick-Zoom Hotkeys, Mouse Wheel & Gamepad Support** (all off by default; tick them under "Optional extras" in the settings):
  - **Keyboard Hotkeys** (rebindable in the UI):
    - `Numpad +` / `Numpad -`: Zoom In / Zoom Out
    - `Numpad /`: Swap Left/Right Shoulder
    - `Numpad 0`: Toggle RTS / Tactical Bird's-Eye Mode
    - `Numpad *`: Cycle Built-in Presets
  - **Modifier + Mouse Wheel**: Hold `Alt` (or `Ctrl` / `Shift`) and scroll the mouse wheel to zoom in/out on the fly.
  - **Gamepad Combo** (optional): Hold `L1 + R1` + `D-Pad Up/Down` to zoom in/out, `D-Pad Left` to swap shoulder, `D-Pad Right` to toggle RTS mode.

- **Couch Co-op Framing (with DirectPawnControl)**:
  - When DirectPawnControl's couch co-op is running (any number of players), the "Classic" co-op camera aims at the middle of everyone and pulls back as players drift apart, so all stay on screen. It moves calmly: it slides and pulls back at a steady pace, and a player who runs too far gets an edge marker (player 1 gold, 2 light blue, 3 green, 4 magenta) instead of the camera whipping round.
  - Climbing: the climbing camera pulls back so both players stay in view. Caves and tight spaces: it pulls back less and widens the view a little. Against a wall or cliff it cranes up and looks down, never tipping over. In the Rift the normal camera returns.
  - Bow aiming widens to keep player 2 in view. Everything is tunable under "Couch co-op" in the menu.
  - The `L1 + R1` gamepad zoom combo is ignored during co-op, because the controllers belong to the players.
  - Upgrading from before 2.9.18: your own camera settings (distance, height, shoulder, field of view, combat distance, presets, hotkeys) are kept; the co-op settings start from the new defaults.

---

## Installation

Copy `camera_distance.lua` to:
```
<Dragon's Dogma 2 Install Directory>/reframework/autorun/camera_distance.lua
```
Settings are automatically saved to `reframework/data/camera_distance_config.json`.


---

## Version history

- **2.8.1** (co-op with DirectPawnControl; details and measurements in `MODLOG.md`):
  - Framing works out the smallest pull-back that fits both players, with a sideways slide; the Arisen stays near the centre.
  - Off-screen marker: dot and arrow on the screen edge with player 2's name and distance.
  - Optional bow zoom limit: while aiming, pulls the aim camera back, then widens the view, to keep player 2 in frame.
  - Fixed the nametag flicker in co-op.
- **2.2.0:**
  - Couch co-op framing with DirectPawnControl.
  - All game calls moved off the render thread: the camera logic now runs on the game thread before the camera's late update.
  - The nearby-enemy check runs 4 times a second instead of every frame.
  - The panel title shows the version.
- **2.1.0:** coordinate-space and quaternion fixes for Over-the-Shoulder and RTS mode; standard presets keep native pitch.
