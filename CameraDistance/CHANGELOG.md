# MODLOG: Camera Distance & Framing Studio (Dragon's Dogma 2)


### 2.9.19 (2026-11-22): release, with DirectPawnControl 0.9.173
### 2.9.19-dev1 (2026-11-21): off-screen markers in each player's chosen colour
- With DirectPawnControl 0.9.173-dev1: DPC_coop.json `colors` ("p<n>" = 0xAABBGGRR) colours the Player 1, Player 2 and players 3+ markers; without it (older DPC) the fixed colours as before.

### 2.9.18 (2026-11-21): release, with DirectPawnControl 0.9.172

### 2.9.18-dev5 (2026-11-21): crane defaults are the tester's own
- the tester: "Whatever I had crane set at is what I want defaults to be" (replaces dev4's 50). From his saved file: `coop_crane_max` 60 (was 25), `coop_crane_view_max` 60, per metre 6, rate 10 (those two already the defaults).

### 2.9.18-dev4 (2026-11-21): crane look-down 50 degrees; old settings start fresh
- the tester: "Increase the crane never look down to 50 degrees for the default". `coop_crane_view_max` 50 (was 60).
- "Make sure the settings someone had from old version of the mod don't mess up the new much much better defaults ... maintain key bindings": `config_version` 4. A file from before (3 or less) keeps only the player's own camera feel and keys (distance, extra distance, height, shoulder, pitch, forward lead, FOV, combat distance, presets, RTS, hotkeys and the zoom / wheel / gamepad switches); every co-op, climbing, crane and other setting starts from the new defaults. The old file is kept as `camera_distance_config.before_2.9.18.json`. Checked in the fake game with the tester's file: distance 1.5 / height 0.2 / combat 3.5 / preset 3 kept, co-op climbing 6, crane 25 / 50.

### 2.9.18-dev3 (2026-11-21): the Rift switch is immediate
- the tester: entering and leaving the Rift worked, but "there was a bit of time when first entering the rift where the camera was pulled back and glitchy before it fixed itself". The Rift check rode on the 1 s co-op poll and the pull-back then eased out at the calm-camera speed. It now runs 10 x a second, drops the co-op pull-back and slide at once on entering, and re-reads DPC's co-op status straight away on leaving.

### 2.9.18-dev2 (2026-11-21): no co-op camera in the Rift
- the tester: "let's get rid of the co-op camera in the rift" (co-op itself stays on through a Rift visit, which he wants). The Rift is the game's "Rim": while `app.FacilityManager.RimStateNow` is anything but None (0) or End (15) the co-op camera, crane and markers are off, as if co-op were off. Read with the 1 s co-op poll. Untested: which RimState values the walk-around Rift uses.

### 2.9.18-dev1 (2026-11-21): edge markers for players 3 and up
- coop-4p-2 (the tester): "P3 is missing a bookmark when off screen". Players 3+ (DPC_coop.json `players`, with `player_names` / `player_nums` from DPC 0.9.172-dev36) get edge markers named after their character: P3 green, P4 magenta, P5 red, then white, the same colours as DPC's target dots.

### 2.9.17-dev1 (2026-11-21): calmer co-op camera, marker colours
- the tester: "both have yellow markers" (draw colours are 0xAABBGGRR; 2.9.16's light blue and gold were both yellow-orange): player 2 is now light blue 0xFFFFC040, player 1 gold 0xFF30C8FF.
- "Cliff code seems to favor P1 so as they run it tilts, but the camera should probably give up and bookmark any player that would cause the camera to suddenly have to move like that ... favor safer more cinematic movements": `coop_calm` (on): the co-op pull-back and sideways slide change by at most `coop_max_pull_speed` / `coop_max_slide_speed` (3 m/s each) after their smoothing; a player who outruns that leaves the frame and gets the edge marker. The crane needs a wall for 0.4 s before it rises and turns at most `coop_crane_rate` (10 deg/s) up, two thirds of that down. Sliders in the Couch co-op block.

### 2.9.16-dev1 (2026-11-21): crane no longer flips the view; player 1 gets an edge marker
- the tester against a tight rock wall: the view went almost straight down and flipped while turning ("I can see almost nothing", before/after screenshots a little rotation apart). The crane's extra pitch now stops at `coop_crane_view_max` (60 deg) of total look-down, judged from the camera's view before the orbit, and `coop_crane_max` is 25 deg (was 35). The readout shows the view's look-down.
- "Camera does not bookmark P1 when out of frame as it should": the edge marker is drawn for player 1 too (gold; player 2 stays light blue), at the camera's anchor (the Arisen, or player 1's pawn when both play pawns); not when player 2 is on the Arisen.

### 2.9.15-dev1 (2026-11-21): co-op crane against walls
- the tester: against a wall "only angling the camera down seems to keep us in view"; trees: live with it. When the player camera controller reports `IsHitTerrain` (a wall pushed it in), the distance it lost (against the distance while unblocked) becomes extra pitch through the native pitch orbit: the camera rises and looks down. `coop_crane` (on, co-op only), `coop_crane_per_m` 6 deg per metre, `coop_crane_max` 35 deg; rises quickly, settles slowly. Readout in the Couch co-op block. Untested: whether IsHitTerrain is the wall push-in is the first thing to check (the readout shows it).

### 2.9.14-dev1 (2026-11-21): game cameras, caves, camera log
- The co-op framing now works on the game cameras agreed with the tester (app.CameraDefine.ControlType; uses inferred from the names): Player, Usually, Combat, Narrow, Climbing, Follow (`CT_FRAME`). The off-screen marker also shows on Notice, Aim, Ballista and Shot (`CT_MARKER`). Everything else (cutscenes, talk, cinematic actions, photo, ...) stays hands off.
- Narrow (likely caves and corridors): the game pushes the camera in at walls, so a full pull-back only fights it. In co-op the Narrow camera takes `coop_narrow_pull` (0.4) of the pull-back and widens the view by `coop_narrow_fov` (8 deg) instead. Sliders in the Couch co-op block, with the current game camera's name. The game's own see-through (app.SeeThroughController) only fades foliage between the camera and the Arisen; walls are handled by camera collision, not transparency.
- Camera log (`camera_log`, on): every change of game camera kind is written to data/camera_types_log.json (kind, seconds, co-op or not, time; totals per kind), to replace the inferred uses with what play shows.

### 2.9.13-dev6 (2026-11-21): climbing distance default 6 m
- coop-climb-2 rerun: player 2 "mostly stays in frame, but can nudge off", and the edge marker shows. `coop_climb_extra` defaults to 6 m (the tester found 6 matched the co-op camera). Saved configs keep their value (the tester's is 4 from the test).

### 2.9.13-dev5 (2026-11-21): climbing distance from the first moment, and the off-screen marker while climbing
- coop-climb-2 (the tester): when the climb started player 2 was off screen with no edge marker; moving "Climbing camera further back" to 6 brought him in, and back to 4 kept him in; later, out of frame again, the marker came back.
- Marker: the off-screen marker was hidden on any non-player camera, the climbing camera included. It now shows while climbing in co-op.
- Distance: the climbing camera appears to take ClimbingCameraSetting._BaseDistance when it starts and re-read it only when it changes, which is why moving the slider helped. The distance is now also set before onStart / onTransition, and on the first 0.3 s of a new climb it alternates +0.05 m so the camera re-reads it. Guess from the report, untested.

### 2.9.13-dev4 (2026-11-21): climbing options next to the co-op camera
- the tester could not find the climbing slider (it was under the suspend options). "Keep both players in view while climbing a monster" and "Climbing camera further back" now sit in the Couch co-op block under the co-op camera choice; the always-on climbing distance stays with the suspend options.

### 2.9.13-dev3 (2026-11-21): no joint offsets while climbing
- the tester: "during climbing, labels are glitchy, jumping around upward. We solved this issue before with the camera." Since dev1 the climbing camera is no longer suspended, so the late hook ran on it. The native offsets live on the player camera controller (updatePog / onUpdate), which does not run while climbing, so the classic co-op pitch fell back to the camera joint, the path that caused the 2.9.1 nametag flicker. While the climbing controller updates (within 0.25 s), the late hook now leaves the joint alone; the climbing camera only gets its distance.

### 2.9.13-dev2 (2026-11-20): climbing camera pulled back
- coop-cam-2: with the climbing camera no longer counted as a cutscene, it still "is too tight" (screenshot: player 1 on a cyclops's back, player 2 out of view). The climbing camera is its own controller (app.ClimbingCameraController), which ignores DistanceOffset and the player controller's _Pog. Its distance is ClimbingCameraSetting._BaseDistance (damped by _DistanceDamper). While climbing in co-op it is now the game's value + `coop_climb_extra` (4 m) + the co-op pull-back; `climb_extra` (0) applies always. The game's value is put back on Reset Scripts. Sliders under the suspend options, with a readout. Untested in game.

### 2.9.13-dev1 (2026-11-20): co-op framing while climbing
- the tester: "climbing with P1 at least makes the camera not try very hard to keep P2 in view". Climbing a monster is camera control type 6 (app.CameraDefine.ControlType.Climbing), which answers get_CurrentPlayerCamera false, so the suspend check treated it as a cutscene camera and the co-op framing let go. In co-op it now counts as a player camera (`coop_frame_climbing`, on; checkbox under the suspend options). Untested in game: whether the game's climbing camera follows the distance it is given is the open question.

### 2.9.12-dev2 (2026-11-20): co-op defaults from the tests
- Defaults now match the settings the tester used in coop-aim-3 ("it seemed to keep us both on screen well"): `coop_style = "classic"`, `coop_classic_pitch = 5.0` (was 38), `coop_classic_height = 1.5` (was 2.0), `coop_aim_zoom_limit = true`. Saved configs keep their own values.

### 2.9.12-dev1 (2026-11-20)
- "Classic" co-op camera (the tester, from the r/DragonsDogma "DD2 couch co op prototype" video): Co-op camera = Follow
  player 1 (as before) / Classic: aimed at the middle of every player (no player off-centre more than the others),
  looks down 38 degrees more, 6 m further back and 2 m higher with everyone together, then pulls back with the
  spread (the frustum solver around the middle, no slide). Sliders for all four. tests/coop_solve.py: classic groups
  all in view with no slide (500 cases).
- _G.CameraDistance_API (get / set a setting, version): TestGuide plans switch settings with it.

### 2.9.11-dev1 (2026-11-20 overnight)
- Co-op framing for any number of players (DPC 0.9.172 lists players 3+ in DPC_coop.json "players"). The frustum
  solver is now coop_solve(rel, o): the smallest pull-back with one sideways slide that keeps every player in view
  (the window of slides that fit everyone; pulls back further if the window is empty). With one other player it is
  the 2.9.10 formula exactly. tests/coop_solve.py: 500 random one-player cases equal to 2.9.10, 500 groups of 3-8
  all in view, adding players never brings the camera in.
- 2.9.10-dev2: pawn index -1 = the Arisen (DPC 0.9.171, player 2 on the Arisen).

### 2.9.10-dev1 (2026-11-20, dev): framing when both co-op players are on pawns
- DirectPawnControl 0.9.171 writes `anchor_idx` in DPC_coop.json when both players are on pawns (the camera follows player 1's pawn); the co-op framing then measures from that pawn instead of the Arisen. -1 (or missing) = the Arisen, as before. Untested in game.

### 2.9.9 (2026-11-19): joseau11's co-op changes
- `coop_ahead_per_m` (0 = off, his setting about 0.35): the frustum fit did not pull back when player 2 ran ahead, since a pawn far down the view line still fits on screen, just small. The camera now also pulls back by this much per metre player 2 is ahead past `coop_start_dist`, up to `coop_fit_cap`. Slider under the fit settings.
- The off-screen player 2 marker is hidden while a menu, shop, talk or a non-player camera is up.
- Tested (`cam-299-1`, Thirteen, 2026-11-19): look-ahead pulls back as intended; the marker hides over the Esc menu. the tester: about 0.1 feels better than 0.35, so 0.1 is the default. His idea for later: when player 2 runs ahead, raising the camera would help more than pulling back.

### 2.9.8 (2026-11-17): the status names aiming as aiming (not tested in game yet)
- **Reported 2026-11-17, walk-through 3, step "bow aim as the Arisen" (screenshot):** the expected status text did not show, and the "Auto-Suspend While Aiming" option could not be found. The status line read `cam = suspended: Non-Player Camera (Event/Talk)`, not "suspended: Aiming".
- From the code: the "not the player camera" check (`MainCameraController.get_CurrentPlayerCamera() == false`) runs before the aim check and returns first. **Assumed, not yet confirmed from the run's recording: the screenshot was taken while aiming**, i.e. the game's aim camera counts as a non-player camera.
- If so, two statements in 2.9.7 were wrong: aiming *was* suspended before 2.9.7, through that check ("Auto-Suspend in Cutscenes & NPC Dialogues"), and unticking "Auto-Suspend While Aiming" does not bring back any other behaviour, because the cutscene check still suspends. Nothing looked different to the player in 2.9.7 for aiming.
- Change: when that check trips and the camera control type is Aim (and "Auto-Suspend While Aiming" is on), the reason is reported as "Aiming". The suspension itself is unchanged.
- Left as is: with "Auto-Suspend While Aiming" off, aiming still suspends through the cutscene check. Whether that option should exist at all is open.
- Where the option is: REFramework menu, Script Generated UI, "Camera Distance & Framing Studio", section "Field of View (FOV) & Cutscene Safeguards".

### 2.9.7 (2026-11-17): names checked against the game's type index (not tested in game yet)
- First pass of `dd2-modkit index check` (every game type, method and field of dd2.exe 4.1.0.0, from REFramework's SDK dump). REFramework answers nil for a method that does not exist, without an error, so these had failed silently:
  - **Aiming was never detected.** `get_IsAim` / `get_IsShootAim` exist on neither `app.Character` nor `app.Human`. So "Auto-Suspend While Aiming" (default on) never suspended, and the "un-aimed FOV" memory could be overwritten while aiming. Now: `MainCameraController.get_CurrentControlType() == 7` (`ControlType.Aim`; the bow aim was seen to be control type 7 in DPC's `archer-aim-1`).
  - **"Weapon drawn" never triggered the combat camera** (trigger rules 1 and 2). `get_IsDrawWeapon`, `get_IsBattle` and `Weapon.get_IsDraw` do not exist; the real getter is `app.Character.get_IsDrawedWeapon`.
  - Dead calls removed, no change in behaviour: `get_DeltaZ` on the mouse device (the wheel comes from `get_Wheel`), `get_IsThinkStop` on enemies in the nearby-enemy scan.
- Each of those misses also cost time every frame: REFramework does not remember a failed lookup, it walks every method of the type and its parents twice, building a signature string for each.
- **What may look different, to check live:** (1) with a bow or magick bow, the camera now really hands back to vanilla while aiming and eases to the custom distance afterwards; unticking "Auto-Suspend While Aiming" gives the 2.9.6 behaviour. (2) Drawing a weapon with no enemy near now switches to the combat distance (rule 1 or 2). (3) The co-op bow zoom limit runs in its own hook and should be unchanged; confirm with `coop-aimzoom-5`.

### 2.9.6 (2026-11-16): world guard while the game loads (not tested in game yet)
- Log review for release: on 2026-11-16, during a save load, REFramework caught 77 access violations in one second (`via.Component.get_GameObject` on destroyed objects). The log does not say which script; several mods were loaded.
- Precaution: `camera_tick` does nothing while `MainFlowManager.IsInGamePhase` is false, and for 1 s after. (The load icon and `SaveDataManager.IsBusy` were left out on purpose: they may also be up during an ordinary autosave.) Smoothing restarts from scratch afterwards.

### 2.9.5 (2026-11-16): nothing on until the player turns it on (not tested in game yet)
- Direction: default to the most vanilla-like behaviour and let players turn on the modes they prefer; it must perform at its best in co-op..
- New defaults: number-pad camera keys **off**, Alt + mouse wheel zoom **off**, 16:9 framing on ultrawide **off** (was "auto"). Style stays Vanilla (2.9.4). Co-op framing and the player 2 edge marker stay **on**; they only act while DirectPawnControl co-op runs.
- Settings files from before 2.9.5 (config_version < 3) get the keys and wheel turned off once, then saved as version 3. `safe_169` is left as saved (the tester's file keeps "auto" for recording).
- Settings window: an "Optional extras" block (wheel zoom, number-pad keys, controller buttons) and the two co-op switches sit right under the style buttons. The old co-op section is now "Couch co-op fine tuning"; the hotkey section holds only step size, modifier and rebinding. Status line says when the camera is the game's own.

### 2.9.4 (2026-11-15): vanilla by default, styles up front (not tested in game yet)
- A fresh install now starts on the Vanilla preset (distance 0, no combat distance, no height offset) so nothing changes until the player picks a style. Existing configs are untouched.
- The six built-in styles are one-click buttons at the top of the mod's menu, always visible; the old "Quick Presets" section now only holds custom presets.

### 2.9.3 (2026-11-15): 16:9 framing on ultrawide; dev status only for developers (not tested in game yet)
- `safe_169` ("auto" on screens wider than 16:9): co-op framing solves for the middle 16:9 and the off-screen marker sits on that area's edge, so a 16:9 recording of an ultrawide screen shows both players. Checkbox in the co-op section.
- `dev_status/CameraDistance.json` is only written when `data/DPC_dev.json` has `{"dev": true}`.

### 2.9.2 (2026-11-14): RTS tilt hook actually runs
- 2.9.1 live: still flickered; the HUD said `pitch 38 joint`.
- Bridge: `PlayerCameraControllerRoot.onUpdate` is called every frame (order: `onUpdate > updatePog > calcBasisPog > updateRotation > updatePosition`, then `MainCameraController.lateUpdate`). The object is an `app.UsuallyCameraController` (role 0), so 2.9.1's type-name check rejected every call.
- Check removed; the role check stays.
- **Verified live:** result: the RTS view looks great (no flicker, tilt unchanged). Every preset is now flicker-free.

### 2.9.1 (2026-11-14): RTS tilt without nametag flicker (not tested in game yet)
- The tester: after 2.9.0 only the RTS preset still flickered. Its downward tilt (`pitch_deg`) was the last thing still set on the camera joint after `lateUpdate`.
- The tilt now runs in a post-hook on `PlayerCameraControllerRoot.onUpdate`, the same method used for the bow-aim fix (2.8.0):
  - the hook orbits `_Position` up around `_Pog` and post-multiplies `_Rotation` by local X (-pitch), using the same maths as the old joint path;
  - `MainCameraController` then copies one consistent pose to the joint;
  - the next `onUpdate` pre-hook restores the controller's own fields, so nothing accumulates.
- If the hook stops running (nothing for 0.5 s), the joint path takes over again.
- The Dev HUD shows `pitch 32 native` or `pitch 32 joint`.
- The method name comes from a 2026-10 reflection dump of `CameraControllerBase` (game closed). It isn't verified that `PlayerCameraControllerRoot` routes through `onUpdate`; the HUD will show it.

### 2.9.0 (2026-11-14): preset offsets without nametag flicker (not tested in game yet)
- The tester: the co-op nametag flicker fix holds in his preset, but the other presets still glitch.
- Cause: shoulder, height, forward lead and extra distance were still moved on the camera joint after `lateUpdate` and restored before `update`, the same pattern that flickered in co-op (2.2-2.5). The tester's own preset (Vanilla, distance 4.5) uses only the native `DistanceOffset`, so it never showed it.
- New `native_offsets` (default on):
  - Shoulder (camera right), forward lead (camera forward) and height (world up) are added to `_Pog` in the `updatePog` post-hook, the native slide verified for co-op in 2.5.0.
  - Extra distance is added to `set_DistanceOffset`.
- Only the RTS pitch (camera tilt) still uses the joint, so the RTS preset may still flicker.
- TestGuide `cam-presets-1` (by eye, one preset per step).
- **Verified live:** the tester: no flicker in any preset except RTS (its tilt still uses the joint, as expected).

### 2.8.2 (2026-11-13): dev status (not tested in game yet)
- Writes `data/dev_status/CameraDistance.json` once a second: version, error count, last error, whether the last config save worked. TestGuide 2.0 shows it on the Dev HUD (red when a save fails, which would have caught the Nov 12 evening when the config stopped saving).
- Marker and camera-tick errors are counted there. No camera behaviour changed.

### 2.2.0 live test (2026-11-12, TestGuide `coop-frame-4`, sampled after the camera update)
- Pull-back: DistanceOffset +0 m up to 4 m apart, then +0.45 per metre, capped at +10 m at about 26 m apart. Camera-to-Arisen distance went from 5.7 m to 14.9 m.
- Shift toward the midpoint works. The main pawn was on screen in 195 of 201 samples while running sideways and circling at up to 25 m.
- But at 20 m+ the Arisen drifts off the edge of the 7680x2160 view (x -190 to 8190, y up to 2500). The framing needs to fit both characters, not just follow the midpoint.
- Samples taken in `LateUpdateBehavior` (`coop-frame-2`/`-3`) see the pose from before the joint offset, so they show no shift. Use on_frame sampling for camera probes.
- Open: in co-op, the nametags over all pawns flicker constantly (not with plain possession). Suspects: the joint offset applied in lateUpdate and restored in update, which is non-zero at any separation in co-op, or DPC's co-op input filters. Test `coop-flicker-1`.
- **Flicker cause found** (`coop-flicker-2`/`-3`, the tester judging by eye):
  - Turning DPC's co-op filters off didn't stop it; turning co-op framing off did.
  - Within the framing, Max shift = 0 stops it and pull-back alone doesn't flicker.
  - So the culprit is the co-op joint shift, which is applied in `lateUpdate` and restored in `update` and is never zero in co-op.
  - Next: move the shift into the game's own camera pipeline (`MainCameraController.<BaseOffset>`, currently (0, 1.5, -0.05)) so the GUI sees one consistent pose. Experiment `cam-baseoffset-1`.
- `cam-baseoffset-1`:
  - Writing `<BaseOffset>` x/z (+3 m) every frame doesn't move the camera sideways: camera-to-Arisen stays (-0.33, *, -5.5) and the Arisen stays at screen x ≈ 3840. Only the height changes slightly. So BaseOffset is not a usable shift.

### 2.2.1 (2026-11-12): flicker experiment
- New `joint_restore` option (default true = 2.2.0 behaviour). With it off, the pre-`update` hook stops putting the joint back. The offset then stays between frames, and each `lateUpdate` rebuilds it from the controller's `_Position`.
- Theory: nametags are placed while the joint is restored, so they jump between the shifted and unshifted pose.
- `cam-flicker-4` results:
  - With the option unticked, the tester saw no flicker.
  - The camera held steady: distance 6.5 m standing still, 5.8–6.6 m while running, no drift.

### 2.3.0 (2026-11-12): fit-both framing, flicker fix on by default
- `joint_restore` now defaults to **false**, which fixes the co-op nametag flicker.
- New `coop_fit` (default on). It splits the separation into a sideways part (screen x) and an along-view part.
  - Pull-back is the larger of two values minus `coop_base_dist` 5.7:
    - sideways: `(|side|/2 + margin 2) / (tan(vfov/2) * aspect)`, from the camera FOV and the main view size
    - along-view: `|depth| * 0.6`
  - The cap is `coop_fit_max_extra` 20.
  - Shift: `coop_center` 0.5 sideways, but only `coop_center_depth` 0.25 along the view.
  - The menu shows the live calculation.
- The 2.2 per-metre pull-back is kept for when `coop_fit` is unticked.
- `coop-frame-5` result: bad. The Arisen stayed at screen centre the whole run, so the sideways shift never reached the screen with `joint_restore` off. The 2.2.1 "flicker fix" had only removed the shift. Pawn off screen in 256 of 520 samples. Pull-back for a pawn ahead was unnecessary, and too small for a pawn behind the camera.

### 2.4.0 (2026-11-12): frustum solver, no joint shift in co-op
- Facts measured: primary camera `get_FOV` is the **vertical** FOV (36 deg at 7680x2160; the Arisen's screen y matches). Controller `BaseDistance` 5.5. Camera pitch about 2.4 deg down at rest.
- The joint offset set after `lateUpdate` reaches the screen only on some frames (with restore) or never (without). `joint_restore` is removed; the pose is always restored as in 2.2.0, so shoulder/height presets behave as before.
- Co-op now uses the pull-back only (`set_DistanceOffset`, native, no flicker). The view direction stays player 1's. Solver, per tick:
  - `side`/`depth` = pawn offset from the Arisen across / along the view.
  - Horizontal: camera must be `|side| / (tan(vfov/2) * aspect * fill)` behind the pawn.
  - Vertical: pawn must be at least `cam_height / tan(pitch + atan(tan(vfov/2) * fill))` ahead of the camera so his feet are in frame (3 fixed-point iterations, because camera height grows with pull-back).
  - Pull-back = the larger requirement minus the normal distance, capped by `coop_fit_cap` 30. `coop_fill` 0.8.
  - A pawn ahead near the centre line needs no pull-back.
- Bridge note: field experiments on the camera do nothing while the game window is unfocused (simulation paused). Use TestGuide `each_frame`.
- Candidates for a native sideways shift later: `CameraControllerBase` `EnvironmentalOffsetParam` / `ActionOffsetParam` (`app.CameraOffsetParam`: `_Position`, `_POG`, `_Distance`), `PlayerCameraControllerRoot.calcBasisPog/updatePog`.
- `coop-frame-6` result: the tester called it much better.
  - Pawn off screen 0 samples in the right / left / circle steps, 2 of 132 running ahead (to 40 m, no pull-back, as intended).
  - Behind the camera with the tester also turning the mouse: 73 of 267 off screen. Two causes:
    - Lag when the view swings (smoothing speed 6).
    - The camera distance stuck at exactly 12.0 m for ~10 s while DistanceOffset asked for up to 16: the game's camera collision capped it, so the pawn sat just past the left edge.

### 2.4.1 (2026-11-12)
- Co-op pull-back is asymmetric: out at `coop_out_speed` 14, back in at `coop_in_speed` 2.5.
- Not solved: a collision-capped camera can't pull back. A native sideways shift would help there.

## Environment
- **Source Project:** `<projects>\CameraDistance`
- **Game Install:** `<game folder>`
- **Deployed Script:** `<game folder>\reframework\autorun\camera_distance.lua`
- **Config File:** `reframework/data/camera_distance_config.json`
- **SDK Dump File:** `reframework/data/camera_distance_sdk_dump.json`
- **Backup:** `<home>\.universal-modder\backups\dd2-camera-distance-orig\20261017-161701.zip`
- **Status:** v2.1.0 verified working in-game by user. v2.2.0 (couch co-op framing, game-thread cleanup) built 2026-11-11, not yet tested in-game. Source now also in the dd2-mods repo (`CameraDistance/`).

## Architecture & Engine Findings
1. **Dual-Stage Camera Pipeline**:
   - **Stage 1 (`app.CameraManager:set_DistanceOffset`)**: Drives native spring-arm follow distance while preserving built-in wall/terrain collision. Fixed v1 bug where disabling the mod left `DistanceOffset` dirty instead of resetting to `0.0`.
   - **Stage 2 (`app.MainCameraController:update` Pre-Hook + `lateUpdate` Post-Hook on `_CameraJoint`)**:
     - Pre-hook on `MainCameraController:update` restores `_CameraJoint` to its unmodified `_Position` and `_Rotation` before the engine updates the camera, preventing frame-to-frame feedback or accumulation.
     - Post-hook on `MainCameraController:lateUpdate` applies Over-the-Shoulder (`+Right`), Height (`+World Y`), Extra Distance (`+Back`), Forward Battlefield Lead, and RTS Orbital Pitch Rotation directly to `_CameraJoint`.
2. **SDK Dump Findings (`camera_distance_sdk_dump.json`) & v2.1 Bugfixes**:
   - **Gotcha 1 (Coordinate Space Mismatch)**: `MainCameraController:get_TargetPositionPrev()` returns a 64-bit Universal `via.Position` (thousands of meters away from `_Position`), whereas `MainCameraController:get_TargetPosition()` and `CameraControllerBase:get_Pog()` return a local 32-bit `via.vec3` in the same space as `_Position`. Subtracting `get_TargetPositionPrev()` from `_Position` swung the camera miles away as yaw changed. Fixed in v2.1 by using `get_Pog()` / `get_TargetPosition()` with a `< 50m` sanity check.
   - **Gotcha 2 (REFramework / GLM `Quaternion.new` Constructor Order)**: `Quaternion.new(w, x, y, z)` in REFramework's GLM binding takes scalar `w` FIRST, whereas passing `(x, y, z, w)` sets `z ≈ 1.0` (a 180° roll around Z that flips the camera upside-down). Fixed in v2.1 by mutating `.x`, `.y`, `.z`, `.w` explicitly by field name on the `via.Quaternion` returned by `joint:call("get_Rotation")`.
   - **Gotcha 3 (Standard Presets Pitch)**: Kept `pitch_deg = 0.0` on all standard 3rd-person presets (`Vanilla`, `Over-the-Shoulder`, `Classic RPG`, `Monster Hunter`, `Panoramic`) so mouse/gamepad pitch behaves 100% natively unless RTS Bird's-Eye mode or manual pitch is used.
   - **Native State Helpers Discovered in SDK Dump**:
     - `MainCameraController:get_CurrentPlayerCamera()` returns `false` whenever a cutscene, dialogue, or non-player camera is active.
     - `MainCameraController:get_IsBattleMode()` reports when the camera controller itself is in battle mode.


## v2.2.0 (2026-11-11): couch co-op framing
- Works with DirectPawnControl v0.9 couch co-op, where player 2 plays a pawn on a controller and player 1 plays the Arisen.
- **Link:** DPC writes `reframework/data/DPC_coop.json` (`active`, `pawn_idx`, `pawn_name`). This mod polls it once a second, backing off to every 30 s if the file is missing.
- **While co-op is active:**
  - **Pull back:** the native `DistanceOffset` grows with the Arisen-to-pawn distance (`coop_zoom_per_m` per metre past `coop_start_dist`, capped at `coop_max_extra`). This uses the spring arm, so the game's wall collision still applies.
  - **Shift:** the camera joint moves toward the pawn by `coop_center` (0.5 = midpoint), capped at `coop_max_shift`, in the existing `lateUpdate` post-hook. This shift does not get the game's wall collision.
- **Suspend states still apply:** menus, cutscenes and aiming.
- **UI:** new "Couch Co-op Framing (DirectPawnControl)" section with sliders and a live readout.

## v2.2.0 cleanup (2026-11-11)
- **Threading:** the per-frame camera logic moved from `re.on_frame` (render thread) to `re.on_pre_application_entry("LateUpdateBehavior")` (game thread). v2.1 called `GuiManager`, `EnemyManager`, `CameraManager.set_DistanceOffset` and the primary camera's FOV from the render thread. It now runs before `MainCameraController.lateUpdate` reads `DistanceOffset` and the joint offsets. Errors are caught, logged once, and shown in the status line.
- **Combat check:** the nearby-enemy scan runs 4 times a second instead of every frame, with the result cached.
- **Co-op:** the L1+R1 gamepad zoom combos are ignored while DPC co-op is active, because that controller belongs to player 2.
- **UI:** the panel title shows the name and version. The co-op section says when DirectPawnControl isn't detected.
- **Release:** `CameraDistance_v2.2.0_Fluffy.zip`, with the same layout as v2.1.0.

### 2.5.0 (2026-11-12): native sideways slide
- Experiments (TestGuide `cam-shift-1`/`-2`, +3 m world x):
  - Writing `EnvironmentalOffsetParam` / `ActionOffsetParam` / `MixedOffsetParam` or the controllers' `_Pog` / `_Position` from UpdateBehavior or LateUpdateBehavior: no effect (the game recomputes them inside its camera update). Pre-hook on `applyOffsetParam` was never called.
  - **Post-hook on `PlayerCameraControllerRoot.updatePog`, adding to `_Pog`: camera moves exactly +3.00 m, same view direction, stable, no accumulation.** Same result from a pre-hook on `updatePosition`.
  - Adding to `_Position` after `updatePosition` only changes the look-at (camera turns), not useful.
- The co-op slide now uses the `updatePog` post-hook (role 0 only). The joint offset is no longer used for co-op.
- Solver extended: the camera may slide by `cs` across the view.
  - The Arisen may go off-centre up to `coop_arisen_fill` 0.45 of the half-screen; the pawn up to `coop_fill` 0.8.
  - Pull-back needed: `max(normal, min_front - depth, (|side| - k*depth) / (kA + k))`.
  - `cs` is the least slide that still fits the pawn, capped at `kA * need`.
  - Example: pawn 15 m to the side needs 10.4 m behind the Arisen instead of 16.2.
- Slide smoothing `coop_shift_speed` 8.
- `coop-frame-7` result: pawn and Arisen off screen in 0 samples across right / left / ahead / behind / circle; the tester saw no nametag flicker. Remaining case: while the Arisen aims a bow the mod is suspended (`suspend_when_aiming`), so the aim zoom can leave the pawn off screen.

### 2.6.0 (2026-11-12): off-screen marker
- `coop_marker` (default on): in co-op, while the pawn is outside the view, `re.on_frame` draws a dot and arrow on the screen edge toward him with his name and distance. The direction comes from the camera's yaw basis, so it also works when he is behind the camera.
- Result: the bookmark works well..

### 2.7.0 (2026-11-12): optional bow zoom limit
- `coop_aim_zoom_limit` (default **off**, checkbox under Couch Co-op Framing).
- While the Arisen aims in co-op, a second post-hook on `MainCameraController.lateUpdate` reads the FOV the game set and widens it just enough to fit the pawn: `2*atan(max(|side|/aspect, |up|+1) / ahead / coop_fill)`, never wider than the un-aimed FOV (`state.normal_fov`, 36 measured). Smoothed.
- Nothing happens when the pawn is behind the camera (the marker covers that).
- Unknowns to confirm live: whether `set_FOV` after `lateUpdate` sticks for the aim camera, and whether the game rewrites the FOV every frame (handled either way by comparing with the last value set).
- `coop-aimzoom-1` result: no effect. The bow aim does not change the FOV (36 before and during). It moves the camera from 5.7 m to 3.5 m and puts the Arisen at about screen x 3030, y 1640 of 7680x2160. With the cap at the normal FOV there was nothing to widen. `get_IsAim` / `get_IsShootAim` on the character read false throughout.

### 2.7.1 (2026-11-12)
- Zoom limit widens past the normal FOV, up to `coop_aim_max_fov` 60 (slider).
- Aiming is also recognised by the camera sitting under 4.6 m from the Arisen on a controller other than `UsuallyCameraController`.
- On leaving the aim the FOV is handed back if the game didn't rewrite it.
- `coop-aimzoom-2` result: still no effect; the FOV read 36 on every sample (`set_FOV` after `lateUpdate` is overwritten). The aim uses `app.AimCameraController` (parent `RotateCameraControllerBase`, not `PlayerCameraControllerRoot`), so the `updatePog` / `updatePosition` hooks never run for it (`aim-zoom-exp-1`: zero calls).

### 2.8.0 (2026-11-12): bow zoom limit that works
- `aim-zoom-exp-2`, post-hook on `AimCameraController.onUpdate` (the tester: all three changed the view):
  - `_Position` moved 3 m back along Pog->Position: camera 3.5 m -> 6.3 m from the Arisen, no turn.
  - `_Fov` = 90: real FOV 54 (controller units x 0.6; normal 60 -> 36).
  - Position and Pog moved together: same as the first.
- Aim settings read live: `AimSetting._PosOffset` (0.70, 0, 3.00), `_POGOffset` (0.70, 0, -1.00), `_Distance` 0; `AimCameraSetting._FOV` 60, `_NarrowingRate` 0.8. Pog is 4.0 m ahead of the camera.
- The zoom limit now runs in that hook: pull back along the sightline up to `coop_aim_back_max` 4 m, then widen up to `coop_aim_fov_max` 50 deg. Eased (out 10, in 4). Nothing when the pawn is behind the camera.
- The 2.7 `lateUpdate` FOV hook is removed. No collision check on the pull-back.
- `coop-aimzoom-3` ran on 2.7.1 by mistake (no script reset): jitter from the late FOV write, no framing.

### 2.8.1 (2026-11-12)
- `save_config` logs failures. The config file had not updated between about [time] and [time]; it saved correctly in this run (no failure logged), so the earlier gap is unexplained.
- **Verified live** (`coop-aimzoom-5`, zoom limit ticked; result: everything works now.). While aiming:

  | Step | Pawn off screen | Aim camera distance | Real FOV |
  |---|---|---|---|
  | Near the aim line | 0 of 98 | 3.3–6.7 m | 36 |
  | 5–10 m to one side | 0 of 76 | 3.4–7.1 m | 36–50 |
  | Running across | 0 of 80 | 3.2–6.8 m | 36 |
  | Behind the camera | 28 of 28 (marker case, by design) | 3.2–5.5 m | 36 |
