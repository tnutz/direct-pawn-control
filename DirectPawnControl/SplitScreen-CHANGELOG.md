# MODLOG: DPC Split Screen

## 0.2.0 (2026-11-26): early release inside Direct Pawn Control 0.9.177, off by default

## 0.2.0-dev24 (2026-11-26): off by default for the 0.9.177 release
- `enabled` defaults to false (early release; saved configs keep their own value). Ships inside the DPC zip (`tools/build_release.py`, `release.py` ALLOWED, `make_public.py`). README rewritten for 2-4 players and the known limits.

## 0.2.0-dev23 (2026-11-26): crash in photo mode while split
- DEVICE_HUNG again, in photo mode with the screen split (first since dev7). Two suspects: (1) photo mode counts as a
  pause, so `menus_keep` kept the split and the camera-controller check was skipped under the photo camera; (2)
  dev19's ToneMapping / ColorCorrect on players 3-4's own cameras (the component kind that caused the earlier hangs).
  Both handled: a photo camera controller ends the split even during a "menu"; `own_pfx_light` off again (once,
  `pfx_light_23`) until tested on its own. Players 3-4 are brighter again until then.
- Checked live after the restart: the scene's one `via.gui.GUICamera` (aspect 1.66, region full, all 73 GUIs target
  id 0) does not lay out the 2D HUD: aspect set to player 1's view (1.19) held but changed nothing; put back. No
  game option or app code widens the 16:9 band (GuiDefine.BaseAspectRatio, CameraDefine.MaxAspectRatio 2.33 are
  constants). A/B plan `hud-ab-1` asks which is better: squeezed full size, or fitted at a third.

## 0.2.0-dev22 (2026-11-26): no HUD fit while a menu is open
- The pause menu (map and items) was squashed by the fit: menus draw full screen. While `S.menu_open`, everything
  is put back; fitted again after. Also learned (live, then undone): the view's Scale grows the pieces but not the
  distance between their anchor points, so above ~1/3 size in three across they overlap; bigger needs the game to
  spread its HUD wider than its middle 16:9 band.

## 0.2.0-dev21 (2026-11-26): HUD fit, the version that looked right
- Back to the live try from [time] (the tester: "we were close"): ScreenSize height / r, width unchanged, Position y + the
  extra height. Round, along the bottom of player 1's view, in the same middle band as on the full screen; smaller
  (r of full size: one third in three across, a half side by side on 32:9). Every try that also changed the width
  scattered the parts, so this one doesn't. On once (`fit_hud_21`). Size: next, tried live with the view's Scale.

## 0.2.0-dev20 (2026-11-26): HUD fit off; the scaling route is closed
- dev18 in game, three across: the HUD kept its shape but sat in the wrong places: the minimap moved from the bottom
  left to the middle right, on top of the button hints; the interact prompt drawn twice. Different GUIs anchor
  differently, so no single ScreenSize / Position per GUI puts them all right. Four tries, four different wrong
  results: stop guessing with this.
- Next idea (untested): don't reshape the HUD at all. Let it draw into a box with the screen's own shape (32:9) at
  the bottom of player 1's view: its own RenderOutput region (like quad view, which looks right). Needs a render
  output that draws the GUI without drawing the scene again.

## 0.2.0-dev19 (2026-11-26): players 3-4 brightness; shadows steady
- "Why the large difference in brightness with the 3rd pane much brighter?": since dev7 the cameras this script makes
  get no post effects (the full set crashed), so no tone mapping / exposure / colour grading. `own_pfx_light` (on):
  they get only `via.render.ToneMapping` and `via.render.ColorCorrect` (if the main camera has it), made once, values
  copied like player 2's. Watch for crashes (dev7's cause was the full set of 19).
- "Shadows are popping in and out": `PerRenderOutputShadowCast` was set every 5 s and the game clears it in between.
  Lights found every 5 s, flag checked every 0.2 s (`shadows.resets` counts how often the game cleared it).

## 0.2.0-dev18 (2026-11-26): HUD fit from a model that matches all four tries
- Fitted to the four results (view 2560x2160 on 7680x2160): size = view height / ScreenSize.h per design unit both
  ways; layout width = ScreenSize.w x (screen aspect / 16:9), stretched over the view, the 16:9 band centred by the
  game; Position in design units. It predicts each: width / 3 -> full size, band wider than the view (off the
  sides); height x 3 -> one third, round, top third; + Position y 2160 -> bottom; dev16 -> 0.64, but its extra
  left shift put the band at -540..1920 px (minimap off the left edge, seen). dev18: no x shift, only GUIs on output
  1 alone. On once (`fit_hud_18`).

## 0.2.0-dev17 (2026-11-25, midnight): HUD fit off again
- dev16 in game (player 1's view 2560x2160 on 7680x2160, r 1/3, k 0.52): the HUD came out far too big, the minimap
  off the left edge, the button hints running into player 2's view, and lines across player 2's view (the 27 GUIs
  on outputs 1 + 4 draw in both views, so reshaping them shows there too). The plain-scale model (dev15) predicted
  ~0.64 of full size centred, so Position and / or ScreenSize do not work the way assumed once both change.
- Off by default, labelled an experiment. Live leftovers from the tries were put back (all 69 views 1920x1080 at
  0,0; the 4096 one 4096x4096).
- Next time, measure instead of guessing from screenshots: read a known control's `get_GlobalPosition` (the minimap
  panel, a button hint) for a few ScreenSize / Position values, fit the mapping, then set it. Only touch GUIs on output
  1 alone (not 1 + 4). Note: GUI view changes survive Reset Scripts; restore before reloading.

## 0.2.0-dev16 (2026-11-25): HUD fit, scale and move
- the tester on the height x3 try: "not squished just positioned wrong", too small. The view also has a Position
  (`via.gui.TransformObject`), so: ScreenSize (w k, h k / r) keeps the shape; Position moves it down by the extra
  height (bottom edge on the view's bottom) and left so the HUD band (the middle 16:9 on a wider screen) is centred.
  k = the smallest that fits the band in 96 % of the view (at least r, at most 1). Three across on 32:9: about 0.64
  of full size; side by side (16:9 views on 32:9): full size. Views wider than the screen left alone. On by default
  again (once, `fit_hud_16`). Not yet seen in game.

## 0.2.0-dev15 (2026-11-25): HUD fit off; what was learned
- dev14 in game (three across on 7680x2160, view 2560x2160, r = 1/3): the minimap was round but everything was 3x too
  big and pushed out to the right. Live, height x3 instead (width as is): round, one third the size, but squeezed
  into the top third and still in the middle band. So `via.gui.View.ScreenSize` is a plain linear scale about the
  top-left corner: width x k draws everything 1/k as wide from the left edge, height x k 1/k as tall from the top.
- Why it can't be fixed with that alone: on a 32:9 screen the game keeps its HUD in the middle 16:9 band (x ~0.27 to
  0.68 of the screen). Undoing the squeeze means 3x wider, which no longer fits; it would also need the HUD moved
  left, and ScreenSize has no offset. GUISystem `SafeAreaRect` reads {0,0,0,0} and `SafeAreaRatio` 1.0.
- Next: find where the game picks the 16:9 band on wide screens (an option or the app GUI code), so the HUD can be
  laid out for the view's own shape instead. `fit_hud` now off by default and labelled an experiment.

## 0.2.0-dev14 (2026-11-25): the game's HUD fits player 1's view
- Reported: the minimap and the game's text in player 1's view were squeezed whenever that view's shape differs from
  the screen (quad on 32:9 looked right: same shape). The game lays out every GUI for the whole screen and draws the
  ones on RenderOutputID bit 1 into player 1's view. Measured live: scaling a GUI view's `ScreenSize` width by r draws
  it r times as wide (x0.25 left on a full screen stretched names 4x, the "bad state" after Ctrl+F6, put back by
  hand). Now each GUI on output 1 gets width x (view aspect / screen aspect) while split; back to its own size when
  the split ends or pauses. Rescan once a second for GUIs that menus create (every 5 s if a scan takes > 2 ms).
  `fit_hud`. Not seen in game yet; the enemy health bar's wrong place may share this cause.

## 0.2.0-dev13 (2026-11-25): players 2-4 can use Camera Distance presets
- `cfg.pcam["p2".."p4"]` = an index into `CameraDistance_API.presets()` (0 = this mod's Distance / Height). The preset
  adds its distance (its combat distance while the player's weapon is drawn or Camera Distance says combat), height,
  shoulder offset, downward tilt and forward lead (RTS: its extra distance) to the base orbit. Distance changes ease
  in (4 / s). Field of view stays the split's. Choosers here and in DPC's main choices.

## 0.2.0-dev12 (2026-11-25): sound heard from the middle of the players
- New `sound_from` (1 player 1's view, 2 the middle of the players, default). The move itself is DPC's listener code
  (0.9.177-dev50), which reads this setting while `S.active`. The second listener at player 2's camera is labelled
  experimental: it was never confirmed heard.

## 0.2.0-dev11 (2026-11-25): faces stay on in every view
- split-6 (four views at render scale 0.7, then 1.0; pause menu, hard mouse swings, Steam F12, third and fourth
  player joining): no crash, no split-screen errors. Frames over 40 ms only when a view was added and when the
  pause menu opened.
- The solo stutter (dev10) was not this script: TestGuide's once-a-second `fs.glob` calls (~40 ms each; it walks all
  of reframework/data). Fixed in TestGuide 2.7.6.
- Reported: player 4's mage had no face in her own view, hair dithered. `app.CharacterFade` fades a character when
  the camera is within ~0.4-1.0 m (`CharacterFadeUniform` inner / outer radius), and it measures from MainCamera
  only (read live: `get_Camera()` = MainCamera for every party member), so player 1's camera passing close to her
  faded her in every view. While the split is on, the players' characters get `set_Fade(1)` (Disable); back to 0
  (Default) when the split ends, pauses, the scripts reset or the character leaves. Setting `no_near_fade`.

## 0.2.0-dev10 (2026-11-25): solo stutter tests
- Reported: playing solo (one view), a stutter every half second turning the camera with the mouse. One view runs
  only the mirroring of hidden cameras onto the main one (dev5): it now writes FOV / aspect / vertical only when
  they change (pose every frame), has its own switch (`mirror`), and "Split the screen" off now means the script
  does nothing at all.

## 0.2.0-dev9 (2026-11-25): one view gets the screen's aspect
- Reported after a Reset Scripts: everything stretched wide. Live: the main camera's aspect was 1.78 (a split half)
  on a 3.56 screen; the aspect saved when the script found the main camera was the split's, because the earlier
  load left it so. Fixed live through the bridge, and one view now always gets the screen's aspect (display
  size), on stop / pause and when the script loads; the saved one is a fallback.

## 0.2.0-dev8 (2026-11-25): no hitch every half second
- dev7 held with three players in the grid + overview (no crash; views 3 / ov with 0 post effects, live).
  GPU memory stays ~19 GB of 24 as players join (Task Manager), so memory is not the crash.
- Reported: slow right-stick turning hitched about every second in four views. The post-effect copy ran for every
  view every 0.5 s in a single frame, each property looked up by name, and the sun lights were searched scene-wide
  each time. Now the getter / setter method objects are kept, one component of one view is copied per frame, and
  the lights are refreshed every 5 s.
- Scene cameras listed live (for hosting players 3-4 on the game's own cameras later): children of
  CameraControllers: WatchCamera, PhotoCamera, InsertViewCamera, NoticeCamera, RequirementCamera, UserEditCamera,
  ClimbingCamera, CinematicActionCamera, FollowCamera, CutSceneFPSCamera, CutSceneCamera, TalkCamera, ShotCamera,
  BallistaCamera, AimCamera, AirShipCamera, NarrowCamera, CombatCamera, UsuallyCamera; MainCamera; BgCamera (UI),
  three MockupCameras (UI).

## 0.2.0-dev7 (2026-11-25): no post effects on cameras the script makes
- Fourth crash ([time]), DLSS off (screen 5120x1440): 6 s after player 3 joined and views 3 and ov were made
  (render scale 0.70, 19 post effects each). Same DEVICE_HUNG. GPU load was not saturated before it (Task Manager).
- Every crash came after the script made its own cameras (views 3 / 4 / ov) and built 19 post-effect components on
  them; player 2's view, on the game's UserEditCamera, never crashed. Cameras the script makes now get no post
  effects (`own_pfx`, off). Next: host players 3-4 on cameras the game already has (list the scene's cameras).

## 2026-11-25: four-view crash, third time: the GPU hangs
- Four views, render scale 0.7, after shaking the mouse camera hard. The game's crash box: `Fatal D3D error (24,
  DXGI_ERROR_DEVICE_REMOVED, 0x887a0005) DeviceRemovedReason(0x887a0006)` = **DXGI_ERROR_DEVICE_HUNG**: the GPU got
  stuck on a frame and Windows reset it (not out of memory; GPU memory is about the same split or not, ~18.7 GB of
  24; GPU load ~76%). A full-scale four-view run with F12 screenshots survived a few minutes before.
- Suspect: DLSS super resolution with several RenderOutputs. `via.render.UpscalingInterface` has a static
  `get_OnlyApplyOnMainCamera` (no setter) and `set_EnableUpscaling` / `setUpscalingAlgorithm`. Next test: four views
  with upscaling off, shaking the camera.

## 0.2.0-dev6 (2026-11-25): four-view crash, second time
- Nameplates gone in split (DPC dev43, confirmed by the tester).
- Crash again with four views: three players in the 2 x 2 grid plus the overview quarter (view 3 at [time], the
  overview at [time], `Present failed: -7785fffb` at [time]). No swap-chain resize right before it this time;
  the tester had taken a screenshot earlier and was about to take another. Earlier resizes (alt-tab / screenshots at
  [time]-11) with two views were survived. Both crashes so far: four views. Working guess: four full outputs
  at 7680x2160 push the GPU over (a device removal, like a timeout), screenshots adding load.
- `view_scale` setting: the extra views' RenderOutput `ImageQuality` (a float render scale) times this, from the
  next start of a view; main's and each view's value are logged.

## 0.2.0-dev5 (2026-11-25): hidden cameras follow the main camera
- Reported with a screenshot (one view, scripts reset): the game's nameplates and DPC's P1 / P2 bars were far off
  their characters. Checked live: DPC's per-view projection matches the main camera's own View and Projection
  matrices exactly (P1 at 1891,882 both ways), so the split's projection is right. The off placement is from the
  game's primary camera, which stays one of the hidden extra cameras when the split is off (UserEditCamera,
  BgCamera seen) and has no setter (`via.SceneView` only has `get_PrimaryCamera`). The game's nameplates and
  `draw.world_to_screen` follow it.
- While one view is shown, every hidden extra camera (kept views, and ones left by an earlier load) is put on the
  main camera's pose, FOV, aspect and vertical flag each frame at BeginRendering, so whichever is primary projects
  like the main camera. Counter `st.mirrored`.

## 0.2.0-dev4 (2026-11-25): clearer layout settings
- the tester could not find the 2 x 2 grid setting while running split-3: the combos are now "Layout with 2 / 3 / 4
  players" (Script Generated UI > DPC Split Screen). Plan split-4 names the full path.
- Bleed across the line (screenshot): the game's own pawn nameplate (`app.ui022601`), placed with player 1's camera
  but drawn over the whole screen, stretched into player 2's view. DPC 0.9.177-dev41 hides the game's nameplates
  while the split is on (their GameObject's `DrawSelf`; restored after).
- Confirmed in game (the tester, [time]): three across and the four-player 2 x 2 grid looked very good.

## 0.2.0-dev3 (2026-11-25): no lines over menus
- With the split kept through menus, the lines between the views were drawn over the menu (Items screen). They and
  the blank quarter are not drawn while a menu is open (`S.menu_open`).
- Player 2's view got "0 post effects" once ([time]; views 3 / 4 got 19 seconds later): an empty list is built
  again on the 0.5 s copy pass.
- **Crash, four views, coming back from a menu ([time]):** the log shows `Event 8004`, then the game's swap chain
  resized (same 7680x2160) and REFramework reset, then `Present failed: -7785fffb` (device removed) 5 s later.
  Two views survived menus earlier. Not fixed yet: cause unknown (four full-size outputs during a swap-chain
  resize is the working guess).

## 0.2.0-dev2 (2026-11-25): stuck split, co-op detection
- Reported: the split stayed on regardless of co-op; controls wrong after Ctrl+F6 (Home recording [time]).
- **Stuck split:** `via.render.RenderOutput` has no `set_Enabled` (read live: `get_Enabled` gives nil), so hiding a
  view did nothing and player 2's output kept drawing on the right half after co-op ended. Now a real setter if the
  type has one, else the camera GameObject's `DrawSelf` (guitarguy1104's fallback; `S.hide_method`). On load, views
  left by an earlier load are hidden and the main view gets the whole screen back.
- **Co-op detection:** from `api.players()` (two or more players with a character), not `state().coop.active`, which
  is false while both players are on pawns (the log: P1 took the second Archer pawn, then a hired pawn; the split ended).
- **Controls:** two controllers were connected, so Ctrl+F6 started two-controller co-op, which waits for player 2's
  L3 + R3. Until then his stick reaches nobody (recording: stick pushed, the main pawn still, DPC "stick 0.00"); DPC
  0.9.177-dev40's `view_axes(2)` no longer falls back to the merged pad then (his view turned while he could not move).
- DPC dev40: `R.primary_cam()` (the main camera while a view list is set): the game's primary camera was
  UserEditCamera / BgCamera (the "1245.0 m from a hired pawn" camera line).

## 0.2.0-dev1 (2026-11-25): three and four players, frame generation, menus (not run in game)
- From the tester's checks: dynamic resolution and DLSS super resolution are fine; **DLSS frame generation** makes the
  other views black. The split now waits while `via.render.UpscalingInterface.get_UsingFrameGeneration()` (static,
  read once a second) is true, with a note on screen and in the settings.
- Menus: coming back from the pause menu went one view, then split (jarring). The menu checks (GuiManager,
  PauseManager) no longer switch to one view (`menus_keep`, on); talks, cutscenes, special cameras and loading still
  do. Resume delay 0.4 -> 0.2 s.
- **Players 3 and 4** (DPC co-op with players 3+): each gets an orbit camera on their right stick (`view_axes(p)`)
  and a camera object this script makes (`DPCSplit_View_3/4` in the MainCamera folder, kept for the session).
  Output ids: player 2 Tertiary 4, player 3 Secondary 2, player 4 Quinary 16 (unknown if 2 / 16 draw: test).
  Layouts: two players side by side / top and bottom; three across (auto on 2.4:1 and wider) or a 2 x 2 grid whose
  fourth quarter is blank or **the party from above** (an overview camera following player 1's view direction,
  pulled back to fit everyone); four in a 2 x 2 grid or four across. FOV per cell: full-height cells keep the
  vertical angle, full-width cells the horizontal one, grid cells keep both.
- **DPC's bars and cards** (DPC 0.9.177-dev39, `set_view_list`): every view's rectangle, pose and FOV go to DPC,
  which projects the world bars into each view that sees the character (clipped to it) and puts each player's
  card at the bottom of their own view.
- Culling: any extra view keeps characters drawn.

## 2026-11-25: IT WORKS with the graphics passes off
- With dev3 (19 post effects copied) the right half was still black, and returning from the pause menu lost the
  graphics device again (`Present failed: -7785fffb`, DXGI device removed), as in the first test.
- the tester turned off upscaling (DLSS), frame generation and ray tracing: **player 2's half draws the world.** Which of
  the three is needed is not narrowed down yet. Working idea: those passes are built for one camera (the primary),
  so the second RenderOutput gets no image, and switching it on and off under them loses the device.
  guitarguy1104's native DLL changes the primary camera and TAA settings, which fits.
- To do: narrow down which setting; show a warning in the settings when it is on; stop switching player 2's view
  on and off for menus (both device losses happened around that).

## 0.1.0-dev3 (2026-11-24): black half found
- split-2: still black, no crash. Read live: `via.Component[]:get_elements()` returns a userdata list, not a Lua
  table; dev2's `elems()` required a table and fell back to get_size / get_element, which gave nothing. So no post
  effects were built: player 2's camera had no ToneMapping (or any other post effect) and drew black. dev1 had the
  same black half for another reason (its RenderOutput was destroyed and remade each error).
- Also read live: `UserEditCamera` is a child of `CameraControllers`, in the MainCamera folder, with its own
  `PostEffectUpdater` and `UserEditCameraController`; the added RenderOutput starts on id 1 (Primary) like the main
  one; `BgCamera` uses id 4 full screen and `MockupCamera` id 8; `sdk.get_primary_camera()` returned
  UserEditCamera while split (the game's primary camera changes: to watch).
- `elems()` copies any list `get_elements` gives into a plain table; the number of post effects copied is logged.

## 0.1.0-dev2 (2026-11-24): fixes from the first test (split-1)
Reported: black right half; player 2's right stick turned both cameras; then the game crashed.
- **Crash:** the log ends with `Present failed: -7785fffb` (0x887A0005, DXGI device removed). Before it, the frame
  errored every ~8-18 s (below); each error destroyed the added RenderOutput and post-effect components and the next
  frame created them again. The device was lost right after the third cycle. Now nothing added to the camera is
  destroyed while the game runs (switched off and reused), and one error halts the split until it is switched on
  again.
- **The error:** `findComponents(via.render.DirectionalLight)` returned an object without `get_elements` (line 256,
  the shadow pass every 0.5 s). Arrays now go through `elems()` (get_elements, else get_size / get_element); the
  type is resolved once.
- **Black half (not confirmed fixed):** `UserEditCamera` had no RenderOutput in this scene; the one added had none
  of the main one's settings. dev2 copies ImageQuality, HorizontalScreenScale, ManualAspectUse, Interleave,
  DistortionType, BackgroundColor, ForceUseClearBackgroundColor, UseCustomSceneLayer, Cutscene, and sets
  RenderOutputID to Tertiary (4): `via.render.RenderOutputID` is a mask (Primary 1, Secondary 2, Tertiary 4,
  Quateary 8, Quinary 16, All 31), and guitarguy1104's GUI ids (5 full screen, 1 player 1) say player 2's view was
  Tertiary. Both outputs' values are logged at start; a test-only slider sets another id.
- **Camera stick:** DPC 0.9.177-dev38 clears player 2's share of the main camera's AxisR while the split is on
  (`set_view_turn` takes `active`).

## 0.1.0-dev1 (2026-11-24): first build (not run in game)
- Source studied: guitarguy1104's DD2CouchCoop pre-alpha 1.0 build 12 (`docs/contrib/guitarguy1104-2026-11-20/`).
  Its split is plain Lua; the native DLL only adds Wwise listener routing, TAA settings, a "primary camera" switch
  (off by default there), GUI edge and native character hooks. None of it is used here.
- Player 2's view: the scene's `UserEditCamera` GameObject (it has a `via.Camera`) gets a `via.render.RenderOutput`
  (created if missing, destroyed on stop). Regions: side by side {0,0,.5,1} / {.5,0,1,1}, top and bottom
  {0,0,1,.5} / {0,.5,1,1}. Both cameras get the region's aspect.
- FOV: the game's value is for the full screen. Side by side keeps the vertical angle, top and bottom the
  horizontal one (both conventions, by `VerticalEnable`). The value written is remembered so it is not compounded
  when the game does not write it again.
- Pose: orbit camera (yaw, elevation from player 2's right stick through `DPC_API.view_axes(2)`), written into the
  Transform at +0x80 (world matrix), +0x30 / +0x40 (local position / rotation) at BeginRendering. The layout is
  checked against `get_WorldMatrix` once; if it differs the split stays off. Which way a camera faces along Z is
  measured at start from where player 1 stands (guitarguy1104's `cam.fwd`).
- Stick: `DPC_API.set_view_turn` returns `(view yaw - main yaw)` for player 2's character (flip setting for testing).
  `getCameraAngleRad` keeps the main camera's angle for player 1 while split.
- Suspend checks: GuiManager / PauseManager / EventManager / CutSceneManager / TalkEventManager getters that exist,
  DPC's world_loading event, and the main camera controller type (one of the gameplay controllers or one view).
- Post effects copied every 0.5 s (a property that throws is dropped); directional lights get
  `PerRenderOutputShadowCast`; second `soundlib.SoundListener` (index 1) and `app.SeeThroughController` on player 2's
  camera; `app.InCameraChecker.isInCamera` post-hook keeps characters player 2 sees.
- Errors: the frame runs in pcall; an error stops the split; three in a row switch it off.
- Not yet: player 2 on the game's own camera controllers (guitarguy1104's cloned MainCameraController rig: combat,
  aim, climbing cameras, collision), camera collision, player 2's aim / lock-on from his view, DPC's cards and bars
  in each player's half (world bars project with the main camera), menus keeping the world split, players 3 and 4.
- Tests: `tools/fakegame/split.py` (load, API, stick turn, view axes, layout and FOV math). Hand plan `split-1`.
