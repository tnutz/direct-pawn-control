-- DirectPawnControl.lua
-- REFramework mod for Dragon's Dogma 2:
-- Allows the player to take direct control of their Main Pawn (or hired party pawns)
-- with native MainCameraController attachment, AI suppression, vocation-accurate controls,
-- two-phase spell casting completion, full-speed sprinting, and dynamic skill UI labels.
--
-- v0.5.0 Fixes & Enhancements:
--   1. Issue 1 (Skill UI Labels):
--      - Hooks app.HumanSkillContext:getSkillID and app.JobContext:get_Job on the Arisen while
--        possessing a pawn so native UI queries see the possessed pawn's vocation & equipped skills.
--      - Adds a toggleable bottom-right ImGui Skill Palette HUD overlay displaying the possessed
--        pawn's 4 equipped skills, vocation action ("Defend", "Quickspell", "Swift Step", "Aim"),
--        and live cast/guard state.
--   2. Issue 2 (Fighter "Defend" & Vocation-Accurate Controls):
--      - Removed hardcoded raw LMB/RMB overrides that conflicted with user bindings and forced
--        Right Mouse / Left Trigger (JobSpecialAction) into requestSubNormalAttack (Heavy Attack).
--      - Routes AttackS -> Light Attack, AttackL -> Heavy Attack, and JobSpecialAction per vocation:
--        * Fighter (Job 1): Hold-to-Defend (Job01_Guard @ all layers / Job01_GuardEnd @ layer 1) with guard-walk support.
--        * Archer (Job 2) / Magick Archer (Job 8): Hold-to-Aim (requestAimAction) + Shoot (requestShoot).
--        * Mage (Job 3) / Sorcerer (Job 6): Hold while chanting for Quickspell (Concentrate), or Vocation Action.
--        * Thief (Job 4): Swift Step (DodgeOfRing).
--   3. Issue 3 (Mage & Sorcerer Spell Casting Completion):
--      - Spells started via requestCustomSkill enter a chanting loop waiting for requestRelease().
--      - Tracks active spell casts, binds LockOnController target to the possessed pawn, checks
--        CurrentSelector:isReadySpellAction(), and calls requestRelease() / requestShoot() automatically
--        when the chant completes (unless the player holds the skill button to store the cast, or cancels
--        with Jump/Sheathe).
--   4. Issue 4 (Full-Speed Pawn Sprinting / Dash):
--      - Uses the true app.LocomotionSpeedTypeEnum values (Idle=0, Walk=1, Run=2, Dash=3).
--      - Latches sprinting state (state.is_sprinting) when Dash/KeepDash/Shift is pressed while moving,
--        and calls requestLocomotionImpl(3, false) (2nd arg is is_strafe!) plus the player dash stack.
--
-- v0.6.0 Stability pass (2026-11-06):
--   * Arisen auto-warp: persistence delay + cooldown (was re-firing every frame while far away / falling).
--   * Arisen auto-follow: requestLocomotionImpl 2nd arg is is_strafe -> pass false (was strafing at 3.5 m/s).
--   * Skill/spell release fires once (with spaced retries), not every frame after 0.35 s.
--   * Cast slot is looked up from the pawn's equipped skills instead of resetting to slot 1.
--   * No per-frame exception storms: locomotion signature and skill-context getter are resolved once
--     and cached; job/skills refreshed every 0.5 s instead of every frame.
--   * Native HUD hooks compare raw pointers (no to_managed_object/pcall on the hot path).
--   * re.on_frame / ImGui only read a cache filled on the game thread (no SDK calls off-thread,
--     no races on the in_internal_query flag).
--   * Key edge detection snapshots every tracked key once per frame (no stale edges after early returns).
--
-- v0.6.1 (2026-11-08, found with the live agent bridge):
--   * ROOT CAUSE of the "far from Arisen" CTD: PawnManager:safeWarp(app.Character, via.Position) was given
--     transform:get_Position() (a float vec3). via.Position is the double-precision UNIVERSAL position, so the
--     engine read garbage and put the Arisen at x=7.3e12; the game crashed ~2 s later. Now passes
--     transform:get_UniversalPosition(), and every warp is verified 0.3 s later (falls back to a local
--     warp next to the pawn if the Arisen ended up somewhere absurd).
--   * Wait / Come pawn commands now control the Arisen while possessing: Wait = stay, Come = follow.
--
-- v0.6.2 (2026-11-08, native HUD acts as if the pawn were the Arisen):
--   * HP / stamina gauge (ui020901), player gauge (ui020401) and minimap (ui020301) are rebound to the
--     possessed pawn on possess / switch and restored to the Arisen on release; re-asserted every 0.5 s.
--   * Native button guide (ui010201) shows the pawn's 4 custom skills while the skill-shift button is held
--     (hook on isInputCustomSkillShift; pawns never receive the player's shift input otherwise).
--   * Fixed setupPlChara post-hook: it used `args` inside the post function (always nil), so it never ran.
--   * Skill names are the localized in-game names at the skill's current level (GUIBase.getCustomSkillName),
--     e.g. "Burst Strike" instead of the internal enum "BlinkStrike", "High Flagration" instead of "Firestorm".
--   * Skill slots 5 and 6 (Skill5 / Skill6 actions, keys 5 / 6) are read and castable (e.g. Full Moon Slash,
--     Riotous Fury); the overlay lists them when equipped.
--   * Mashing light attack chains the combo instead of restarting it: a press during a swing is held until
--     the combo window opens (HumanActionSelector.NextComboAction non-empty, max 0.45 s) and then sent.
--     app.Character.isIdle() is false even while standing, so "mid-swing" is read from the FSM layer-0 node.
--   * Keyboard skill keys (Ctrl, 1-6) work while the REFramework menu is open; mouse buttons stay gated.
--   * Walking (W / stick) during an attack no longer cancels it: locomotion/idle requests are skipped while
--     the pawn's layer-0 FSM node is not Locomotion.*; the stick still steers the swing.
--   * cfg.debug_input logs inputs / attack frames to data/DPC_input_log.json for live tuning.
--
-- v0.7.0 (2026-11-08, "native Arisen controls", experimental, cfg.native_controls):
--   * The possessed pawn runs its OWN app.PlayerInputProcessor (the Arisen's input -> action layer with
--     every vocation's combo / cancel / skill rules, Job01..Job09InputProcessor), driven from DPC each frame
--     right after your buttons are mirrored into the pawn's CharacterInput. DPC's hand-built movement and
--     combat are skipped while it runs. Verified live on a Fighter: walk/sprint, combos, dash attack, guard,
--     Burst Strike, Flawless Guard, Full Moon Slash, Launchboard, Riotous Fury, jump.
--   * Built with sdk.create_instance + setup + selectProcessor; Param gets the pawn's Chara/Human/Track and a
--     new app.LockOnController (setup(pawn, Arisen's LockOnRangeParameterList)); every Detail shares Param.
--   * NEVER attached with Character:setInputProcessor: the engine then calls update() itself and crashes in
--     LockOnController.clearLockOnIfNeeded (Param.Player is nil for a pawn). Driving it ourselves is stable.
--   * Pawn idle "LivSitOnTheGround" requests (~every 3 s while standing) are blocked while possessed.
--   * 5 update errors -> falls back to the Mode 2 puppeteer for the rest of the possession.
--   * Keys 1-6 (row / numpad) are fed to the native processor as SkillN + Shift1 + Shift2 input.
-- v0.7.1: PlayerInputProcessor.setup is setup(Character, PlayerTrack); the bare setup() call never ran.
-- v0.7.2: the native processor shares the Arisen's LockOnController (already rebound to the pawn and kept
--   updated by app.Player) instead of a hand-built orphan one. Suspect for the Thief worker-thread crashes.
-- v0.7.3: still crashed in Thief combat (3rd site: via.effect ObjectEffectManager2.start -> findChildrenRecursively
--   -> List<GameObject>.InsertRange). Different site each time = memory corruption. Thief pawns now default to
--   the Mode 2 puppeteer (cfg.native_skip_thief) until the cause is found.
-- v0.7.4: Thief fallback was uncontrollable because the experiment left "Enable ... Movement" and "Enable Combat"
--   unticked. Both are re-enabled once on load and are forced on whenever native controls are enabled.
-- v0.7.5: native crashes (Fighter too, 4 sites, all engine code) vs none in a Mode 2 ogre fight -> suspect timing.
--   The pawn's PlayerInputProcessor now updates inside the Arisen's app.Player.update (pre-hook), the slot where
--   the game runs player input, instead of at pre-UpdateBehavior. Self-check: if that hook never fires or never
--   sees the mirrored input, it falls back to the old pre-UpdateBehavior call (cfg.native_drive = "player"|"pre").
-- v0.7.6: return-to-title while possessed crashed (scene teardown with shared state still pointing at the pawn).
--   onDestroy hooks on the possessed pawn / Arisen (Character + Human) and on PawnManager / CharacterManager now
--   release possession first; the release skips action requests when it is a teardown.
--   Native release no longer calls :release() on the processor / lock-on objects.

local VERSION = "0.9.173"

-- v0.9.7 Dev HUD status (TestGuide 2.0 shows it): errors that used to be swallowed by pcall, and whether the
-- settings file saved. Written to data/dev_status/DirectPawnControl.json once a second.
local dev = { errors = 0, last_error = nil, last_error_t = nil, save_ok = nil, next = 0, seen_brain_errs = 0 }
-- v0.9.7 robot player (for unattended tests; driven by the "robot" command, usually from a TestGuide step):
--   pad:    fakes player 2's controller as DPC sees it (co-op input, DPC pad combos). Not the game's own pad read.
--   arisen: drives the Arisen through the brain's input injection (stick + action flags), bypassing the brain's rules.
-- Each entry expires on its own (secs), so a lost command can never leave a button held.
local robot = { pad = nil, arisen = nil, uses = 0 }
local function dev_error(where, err)
    dev.errors = dev.errors + 1
    dev.last_error, dev.last_error_t = where .. ": " .. tostring(err), os.clock()
end
local CONFIG_PATH = "DirectPawnControl.json"
local TRACE_PATH = "DPC_trace.json"

-- ----------------------------------------------------------------------------
-- Configuration & State
-- ----------------------------------------------------------------------------
local cfg = {
    version_tag = "v5",
    window_open = true,
    hud_safe_169 = false,           -- v0.9.16: keep DPC's overlays inside the middle 16:9 of the screen. 0.9.172-dev17: off by default (the tester: "mainly for my own recordings"; was "auto")
                                    -- ("auto" = only on screens wider than 16:9, true, false)
    hud_overlay = false,            -- v0.9.114: the top-left status panel is a diagnostics panel; off for new players
    skill_hud_overlay = false,      -- Bottom-right skill palette while possessing (off since 0.9.27: the native HUD shows it; kept for debugging)
    native_hud_skill_hook = true,   -- Redirect Arisen SkillContext/JobContext queries to possessed pawn
    possess_stop_navi = true,       -- v0.9.131: stop the played pawn's own path-following (catching up with the party)
    possess_stop_move = true,       -- v0.9.132: end the move command (Approach, ...) the played pawn's action executor is still running
    hud_dash_slot = false,          -- v0.9.134 experiment (write the Arisen's Dash slot into a played pawn's guide); did not make the label show, off since 0.9.135
    hud_cling_grey = true,          -- v0.9.119: while the played pawn climbs on a monster, the game greys out the skills it replaces
    native_hud_gauges = true,       -- Rebind native HP/stamina gauge + minimap to the possessed pawn
    localized_skill_names = true,   -- Show in-game (localized, level-aware) skill names instead of enum names
    native_controls = true,         -- v0.7: pawn uses its own PlayerInputProcessor (Arisen controls); off = Mode 2 puppeteer
    native_drive = "player",        -- v0.7.5: "player" = inside app.Player.update (game's slot); "pre" = pre-UpdateBehavior
    coop_aim_keep_range = 30.0,
    coop_cam_turn = "shared",       -- 0.9.172-dev22: "shared" by default (coop-cam-2: "Mode 2 seems the only good candidate"). 0.9.172-dev20: co-op camera turn with two controllers: "p1" | "shared" | "auto" (see R.cam_turn)
    coop_aim_p1_flick = true,       -- 0.9.172-dev20: player 1 switches target with quick right-stick flicks too
    coop_cam_p1_steer = false,      -- 0.9.172-dev22: "p1" mode: the camera turns toward player 1's target by itself (coop-cam-2: "keeps rotating the camera and not stop at the target"; off)
    coop_cam_auto_speed = 0.5,      -- 0.9.172-dev20: stick strength of the camera's own turning ("auto", and "p1" with a kept target)
    coop_cam_deadband = 8.0,        -- 0.9.172-dev20: degrees off before the camera turns by itself     -- 0.9.172-dev15: m; a kept / flicked co-op target stays until this far (was the lock-on range x 1.5)
    coop_cam_from = {},              -- 0.9.172-dev36: ["p<player>"] = false: that player's right stick doesn't turn the co-op camera (all do by default)
    coop_p1_kb = false,             -- 0.9.172-dev36, no longer read (dev46: player 1's device is worked out, see R.p1_pick)
    coop_leave_glow = "Berserker",  -- 0.9.172-dev38: the game's rim light on a character whose player leaves co-op ("" = none; the tester asked for a red one)
    coop_join_glow = true,          -- 0.9.172-dev40: a co-op player's character glows in their colour when they join or change character
    coop_glow_keep = true,          -- 0.9.172-dev40: ... and keeps glowing while they play it (who is who at a glance). dev45: on by default (the tester)
    coop_colors = {},               -- 0.9.173-dev1: ["p<n>"] = colour number (R.ta_colors) for players 3+; players 1 and 2 use coop_aim_p1_color / coop_aim_p2_color
    coop_glow_keep_p = {},          -- dev45: ["p<n>"] = false: that player's glow is not kept (each player's tick under "keep glowing")
    coop_join_hold_s = 0.6,         -- dev50: seconds of L3 + R3 to join co-op / claim a controller (leaving stays 3 s)
    settings_gen = 2,               -- 0.9.172: settings saved before this release (no settings_gen) start from the new defaults; keys kept
    coop_block_ptw = true,          -- 0.9.172-dev35: in co-op, Pawn Tactical Wheel (another mod) does not open from controllers
    down_alert = false,             -- 0.9.172-dev32: off by default (the tester prefers the game's own chime and flash, which do play). 0.9.172-dev30: while a pawn is played or in co-op, name any downed party member at the top of the screen
    free_arrows_give = true,        -- 0.9.172-dev29: with free arrows on, a played Archer with none of a special arrow gets one (weightless)
    native_dash_opt = true,         -- 0.9.172-dev13: give a played pawn's CharacterInput the Arisen's Dash option (hold / toggle) handle
    native_dash_keep = true,        -- 0.9.172-dev14: add KeepDash to a played pawn's input while Dash is held (pawn-dash-3: keeps the sprint, 8.1 m/s like the Arisen's 8.2)
    native_dash_to_req = false,     -- 0.9.172: true = old behaviour (force the pawn's IsEnableDashToRequestedMoveSpeedOfNormalLocomotion on at possession; suspected of capping a played pawn's sprint at run speed after the first moment)
    native_skip_thief = false,      -- v0.8.11: Thief on native controls again (crashed 3x before the v0.7.5 timing fix)
    native_own_lockon = false,
    migrated_074 = false,      -- v0.7.2: false = share the Arisen's (rebound) LockOnController; true = v0.7.0 orphan one
    raw_mouse_fallback = false,     -- Off by default so user's DD2 bindings (e.g. RMB = Defend) are respected
    -- 2 = ActionSelector Puppeteer (Angle C - Default, Crash-Safe)
    -- 1 = Native InputProcessor Swap (Angle B - Experimental)
    -- 3 = Hybrid (Native InputProcessor + ActionSelector Assist - Experimental)
    control_mode = 2,
    selected_pawn_idx = 0,          -- 0 = MainPawn, 1 = SubPawn01, 2 = SubPawn02
    arisen_auto_follow = false,     -- Off by default for stability
    arisen_follow_dist = 7.0,
    arisen_warp_dist_wait = 120.0,  -- v0.9.28: while the Arisen waits, he only warps to you past this distance
    arisen_warp_dist = 35.0,        -- Auto-warp Arisen if > 35m away to prevent party leash snap (0 = off)
    arisen_warp_delay = 1.0,        -- Condition must hold this long (s) before warping (ignores jumps/falls/climbs)
    arisen_warp_cooldown = 4.0,     -- Minimum seconds between automatic warps
    spell_release_fallback = 2.5,   -- If isReadySpellAction never reports ready, release a spell after this long (s)
    skill_retry_window = 0.60,      -- PawnCommander pattern: keep submitting skill during weapon draw
    attack_retry_window = 0.30,     -- Keep submitting attack during weapon draw / locomotion transition
    combo_buffer_window = 0.45,     -- Light attack pressed mid-swing: wait at most this long for the combo window (s)
    debug_input = false,            -- Dev: log input/action events ([DPC-dbg] lines + data/DPC_input_log.json)
    -- v0.8 Arisen combat brain: while you possess a pawn, the Arisen fights with his own player controls
    arisen_brain = true,
    arisen_brain_any_job = false,   -- true = try the ranged rules on any vocation not covered below
    arisen_brain_skill_max = 4.0,   -- v0.9.54: s in one custom-skill action before he lets go (0 = off)
    arisen_brain_caster = true,     -- v0.9.59: caster rules for Mage and Sorcerer
    arisen_brain_quickspell = true, --   hold Quickspell while incanting (above 45 % stamina, until 20 %)
    arisen_brain_cast_gap = 4.0,    --   s of magick bolts between the end of one spell and the next (2.5 before 0.9.62)
    arisen_brain_heal = true,       -- v0.9.62: heals (equipped heal spell, or the Mage's Anodyne)
    arisen_brain_heal_pawn = 0.65,  --   the possessed pawn below this share of health
    arisen_brain_heal_other = 0.5,  --   anyone else, himself included
    arisen_brain_heal_cd = 10.0,
    arisen_brain_topup_on = true,   -- v0.9.64: after the fight, heal anyone below arisen_brain_topup
    arisen_brain_topup = 0.85,
    arisen_brain_cure = true,       --   cast the cure spell (id 35) when someone has a debilitation
    arisen_brain_cure_cd = 12.0,
    arisen_brain_heal_reach = 2.5,  --   m he gets within before healing
    arisen_brain_anodyne_hold = 3.5,
    arisen_brain_buff_every = 75.0, --   s before a buff spell is cast again
    arisen_brain_caster_keep_min = 4.0,    --   s between the end of one spell and the next
    arisen_brain_cast_max = 25.0,   --   s in one spell before the watchdog lets go (melee / ranged use arisen_brain_skill_max)
    arisen_brain_ma_remedy_assist = true, -- v0.9.108: Magick Archer's Remedy Arrow revives the downed pawn (the mod completes it)
    arisen_brain_hybrid = true,     -- v0.9.65: Magick Archer, Trickster (ranged rules), Warfarer (rules of the weapon in hand)
    arisen_brain_melee = true,      -- v0.9.51: melee rules for Fighter, Thief, Warrior, Mystic Spearhand
    arisen_brain_melee_reach = 2.3, -- m (centre to centre) at which he starts swinging; Warrior +0.4
    arisen_brain_melee_cd = 0.42,   -- s between attack presses (Warrior x1.9)
    arisen_brain_melee_skill_cd = 6.0,
    arisen_brain_melee_face_tol = 25.0,
    arisen_brain_melee_dash = 7.0,  -- sprint when farther than this
    arisen_brain_follow = true,     -- brain follows the possessed pawn when there is nothing to fight
    arisen_brain_skills = true,     -- use equipped core skills (slots 1-4) on a cooldown
    arisen_brain_battle_only = true,     -- v0.9.18: fight only while the game itself is in battle (not at wildlife nearby)
    arisen_brain_engage_r = 30.0,
    arisen_brain_keep_min = 7.0,    -- archer band: back off inside this, approach beyond keep_max
    arisen_brain_keep_max = 20.0,
    arisen_brain_shot_cd = 0.9,
    arisen_brain_shot_hold = 0.12,
    arisen_brain_face_tol = 6.0,    -- degrees off target before he turns instead of shooting
    arisen_brain_turn_mag = 0.15,
    arisen_brain_skill_cd = 7.0,
    arisen_brain_ma_skill_gap = 1.2, -- v0.9.116 Magick Archer: s of plain shots between the end of one skill and the next (0 = the 7 s rule above)
    arisen_brain_ma_stamina = 0.2,   --   no skill below this share of his stamina
    arisen_brain_ma_charge_s = 2.0,  -- v0.9.117 Hailstone Bolt (id 83): s the skill button is held so it charges (0 = the normal short press)
    arisen_brain_ma_vim_hp = 0.8,    --   Vimtaking Arrow (id 86, a heal by targets hit): only below this share of his health ...
    arisen_brain_ma_vim_group = 3,   --   ... or, with this many enemies near, whenever he is hurt at all (below 97 %)
    arisen_brain_skill_hold = 0.5,
    arisen_brain_rearm = true,      -- v0.9.146 Warfarer Arisen: swaps weapons (Rearmament) while he fights
    arisen_brain_rearm_every = 20,  -- seconds between his weapon swaps (5 at the least)
    arisen_brain_lock = true,
    switch_cine = true,               -- v0.9.169: camera transition when control changes hands (look at the new character, then glide behind them)
    switch_cine_profile = 2,          -- v0.9.169: 1 Instant, 2 Establish, 3 Bird's-eye, 4 Custom (the sliders below)
    switch_cine_hold_s = 0.15,        -- custom: seconds to hold the establishing view before gliding in
    switch_cine_look_s = 0.45,        -- seconds: turn to look at who you are about to play (while pulling out, if on)
    switch_cine_pull = true,          -- v0.9.169: first pull back and up so both characters are in view (less turning)
    switch_cine_pull_m = 2.0,         -- extra metres back for the pull-out
    switch_cine_rise_m = 1.2,         -- metres up for the pull-out
    switch_cine_glide_s = 0.80,       -- seconds: glide from there to the game's camera behind them
    switch_cine_speed_back_s = 0.95,  -- v0.9.169: full game speed is back this long before the camera lands (control feels yours sooner)
    switch_cine_speed_ramp_s = 0.5,   -- v0.9.169: and eases up from the slow-down over this long before that
    switch_cine_slowmo = 0.40,        -- game speed during the transition (1.0 = no slow-down); eases back to normal while gliding
    switch_glow = "RimLightPawnLift", -- v0.9.169: the game's own rim light on who you take over ("" = none). Pawn lift reads best in every light (the tester)
    switch_cine_glow_s = 1.8,         -- seconds the glow stays on (0.9.172-dev19: 1.8, the tester; was 1.4)
    -- v0.9.170 (dev, untested): whoever you play is treated as the player. Each part is its own switch so a test can
    -- turn them on one at a time; all off = exactly as 0.9.169. Only while one player plays a pawn alone (not co-op).
    -- dev4: the three sound parts are on by default (tested 2026-11-19, sound-as-player-2/-3: B sounded right, the
    -- ambience followed the pawn; camera vs pawn distance could not be told apart, so the simpler camera one).
    pf_sound_voice = true,            -- the played pawn gets the player's sound settings (Wwise category / RTPC), the Arisen a pawn's
    pf_sound_listener = 1,            -- loudness by distance from: 0 the Arisen (game), 1 the camera, 2 the played pawn
    pf_sound_coop_ear = true,         -- 0.9.171: co-op, "the camera": loudness from a point a normal camera distance from the two players
    pf_sound_ear_dist = 5.0,          -- 0.9.171: that distance (m)
    coop_listener_move = true,
    coop_listener_loudness = true,    -- 0.9.172: ... and loudness is worked out from that same point (not from the Arisen)        -- 0.9.172: co-op: the sound listener (normally at the camera) moves toward the players, so a pulled-back camera does not cut sounds off
    pf_sound_space = true,            -- the place's acoustics (reverb, ambience zone) follow the played pawn
    pf_defaults_v = 0,                -- (which of these defaults a saved config has been brought up to)
    pf_hitstop = false,               -- hit-stop (the short freeze on a hit) as if the played pawn were the player
    pf_world_slow = false,            -- the slow-motion on a big kill as if the played pawn were the player
    pf_skill_slow = true,             -- dev5: skills' own slow motion (e.g. Riotous Fury) for the played pawn, not the Arisen (see R.pf_slow_hook)
    pf_scope_log = true,              -- count how often each of these runs (shown in the settings, written to the session log)
    possess_no_climb_cam = true,      -- v0.9.143: the Arisen's climbing camera is not switched to while a pawn is played
    possess_no_cinematic_cam = true,  -- v0.9.139: the game's cinematic action camera is not started while a pawn is played
    arisen_own_lockon = true,         -- v0.9.168: while a pawn is played the Arisen gets a lock-on of his own; the game's one is the played pawn's alone
    arisen_lock_guard = true,         -- v0.9.138: the Arisen's own input step never touches the played pawn's lock-on target
    arisen_brain_puppeteer = false,      -- run the brain while the pawn uses the Mode 2 puppeteer (crashed twice)
    arisen_brain_lock_puppeteer = false,
    arisen_brain_lock_thief = false,     -- swap the lock-on while a Thief is possessed (untested; Thief crash family) -- also swap the lock-on while the pawn runs on the Mode 2 puppeteer (crashed)
    arisen_brain_clear_axis_r = false, -- true = zero his right stick (froze the camera in v0.8.2)
    arisen_brain_stuck_s = 6.0,     -- no damage on the target this long while engaged -> sidestep for a clear shot       -- lock his LockOnController on the brain's target while his processor runs
    arisen_brain_keep_hud_redirect = false, -- true = keep the v0.7 HUD job/skill redirect while the brain runs
    -- v0.9.6 line of sight. The lock-on system ray-casts every candidate target for walls: the target's
    -- LockOnTargetWork has isWall / isWallPL ("from the player") / isWallCam ("from the camera") and IsRayCasted.
    -- The brain reads them for its target every tick (always in the telemetry). With arisen_brain_los on he holds
    -- his shots while the line is blocked and flanks toward the target until it clears (pawn-style).
    arisen_brain_los = true,             -- on since 0.9.9: flags and hold-fire verified live (brain-los-1c / -1d)
    arisen_brain_los_field = "isWallPL", -- which flag means "blocked": isWallPL, isWall or isWallCam
    arisen_brain_los_delay = 0.4,        -- blocked this long before he reacts (s)
    arisen_brain_los_angle = 50.0,       -- flank angle off the direct line to the target (deg)
    arisen_brain_los_swap = 2.5,         -- still blocked after this long -> try the other side (s)
    arisen_brain_telemetry = true,  -- data/DPC_arisen_brain.json, twice a second
    -- v0.9 couch co-op: player 2 drives a pawn with a controller while player 1 plays the Arisen on mouse+keyboard
    coop_pad_deadzone = 0.15,
    -- v0.9.170-dev3: joseau11's co-op additions (credit in the MODLOG), all off by default
    coop_auto_resume = false,         -- co-op starts again by itself after cutscenes, loading or a downed pawn
    coop_start_bring = false,         -- dev7: when co-op starts, player 2's pawn is brought next to the Arisen if it is more than 6 m away
    coop_p2_rumble = true,            -- player 2's controller rumbles (two controllers only). 0.9.172-dev18: on by default
    coop_p2_rumble_power = 1.0,
    coop_rb_dealt = true,
    coop_rb_skill = true,
    coop_rb_status = true,
    coop_aim = true,                  -- 0.9.172-dev16: on by default (coop-aim-3 passed). Target markers for both players; player 2 R3 keep / free, right stick flick, hold R3 = player 1's
    coop_aim_markers = true,
    coop_aim_flick = "deliberate",    -- 0.9.172: player 2 switches target with a quick out-and-back flick ("quick" = any push past 70 %)
    coop_aim_p1 = true,
    coop_aim_p1_assist = true,
    coop_aim_p1_color = 2,            -- 0.9.173: Cyan (R.ta_colors numbers; the menu shows them in R.COLOR_ORDER)
    coop_aim_p2_color = 6,            -- 0.9.173: White
    coop_aim_size = 1.0,
    coop_zero_pad_for_arisen = true,  -- feed the Arisen's processButton an empty pad (auto-off if it kills the keyboard)
    coop_mask_p2_flags = false,       -- v0.9.5: also strip player 2's actions from the Arisen's buttons (blocks shared actions)
    -- v0.9.170 (dev, untested): two controllers, after joseau11's 0.9.165 changes (credit in the MODLOG). Player 2 holds
    -- L1 + L3 on their controller to claim it; the other controller is player 1's and drives the Arisen.
    coop_two_pads = true,             -- 0.9.172-dev18: on by default (two controllers work; the tester)
    coop_pad_join = true,
    robot_frees_pad = true,           -- dev14 (developer): with the robot as player 2 in co-op, the controller plays the Arisen
    pad_active_follow = true,         -- dev13: the controller in use drives the Arisen (the game keeps one "active" controller and does not switch by itself)
    pad_mode_fix = false,             -- dev10 (off in dev11: it switched the mode but the Arisen still got nothing, so not the cause): if a controller is used but the game stays in keyboard/mouse mode (the Arisen gets nothing), switch it back             -- dev9: a second controller starts co-op by holding L3 + R3 (both stick clicks) for 1.5 s; held 3 s in co-op, it ends it
    coop_two_pads_buttons = 1,        -- the Arisen's buttons: 1 take out only what player 2 presses, 2 leave them to the game (joseau11), 3 player 1's pad only (opened the menu for joseau11)
    coop_two_pads_cam = 1,            -- while player 2 moves their right stick: 1 the camera follows player 1's right stick, 2 the camera holds still (as with keyboard)
    coop_block_p2_stick = true,       -- v0.9.2: player 2's left stick doesn't walk the Arisen (his WASD still does)
    coop_block_p2_camera = true,      -- v0.9.2: player 2's right stick doesn't turn player 1's camera
    coop_stamina_bar = true,          -- v0.9.42: thin yellow stamina bar under player 2's pawn's health bar
    arisen_bars = true,               -- v0.9.57: the Arisen's health + stamina while a pawn is possessed
    arisen_bars_overhead = true,      --   over his head (false = always the fixed pair at the bottom)
    coop_bars_thick = 4.0,            -- v0.9.50: bar thickness in px at 2160 p
    coop_bars_alpha = 0.65,           -- v0.9.50: opacity of the pair
    coop_health_bar = true,           -- v0.9.49: health bar above player 2's stamina bar (fixed HUD pair)
    coop_stamina_attach = false,      -- v0.9.48: false = fixed HUD bar (default); true = follow the pawn's head (drifts)
    coop_skill_palette = true,        -- v0.9.70: player 2's skill list with controller buttons, in co-op
    coop_palette_left = 0.60,         --   left edge and bottom edge, as fractions of the HUD area (0.9.71)
    coop_palette_bottom = 0.93,
    coop_stamina_hud_x = 0.5,         -- fixed bar: centre, as a fraction of the HUD area width
    coop_stamina_hud_y = 0.9,         -- fixed bar: top, as a fraction of the HUD area height
    coop_stamina_head_up = 0.44,      -- m above the pawn's Head joint (where the game's health bar sits)
    coop_stamina_dx = -9.0,           -- px (at 2160 p) right (from the tester's screenshot of 0.9.43)
    coop_stamina_dy = 10.0,           -- px (at 2160 p) down
    coop_stamina_frames = 0,          -- show the position this many frames back (negative: ahead)
    coop_stamina_width = 1.0,
    coop_warp_p2 = true,              -- v0.9.41: the party warp key also brings player 2's pawn in co-op
    coop_no_gyro = true,              -- v0.9.39: in co-op the controller's motion sensor does not aim the Arisen
    possess_interrupt_ai = true,      -- v0.9.38: end the pawn's running AI action when taking control
    pawn_interact = true,             -- v0.9.26: the possessed pawn gathers / loots himself (own prompt + Interact button)
    pawn_interact_range = 2.2,        -- m
    cycle_switches_now = false,       -- v0.9.90: F7 while possessing switches pawn at once (the old behaviour) instead of selecting
    show_legacy = false,              -- v0.9.82: the advanced / test / legacy bin of the settings window
    pawn_aim_skills = true,           -- v0.9.87: bow pawns: L2 + face button = the aimed skill, whatever the Arisen's vocation
    pawn_hip_skill_aim = true,        -- v0.9.167: an Archer pawn's skill used from the hip keeps its aim up until it fires
    pad_hold_select = true,           -- v0.9.96: hold a D-pad direction: left / right select, up switch, down back to the Arisen
    pad_hold_s = 0.5,
    quick_skill_hold_ai = true,       -- v0.9.151: an ordered pawn skill is kept: the pawn's own AI waits until it is over
    quick_skill_no_target = true,     -- v0.9.151: an ordered attack skill with no enemy about is performed on the spot
    coop_p2_switch = true,            -- v0.9.153: in co-op player 2 changes pawn with the take-control combination
    coop_any_drive = "auto",
    coop_max_players = 8,
    coop_np_palette = true,           -- 0.9.172: players 3+ get a skill list above their bars             -- 0.9.172: players 3+ join with L3 + R3 on another controller; the most players at once
    coop_any_p2_arisen = "brain",     -- 0.9.171: player 2 on the Arisen (two controllers): "brain" = player 1 keeps the camera, player 2's controller drives the Arisen; "classic" = the Arisen takes player 2's controller and the camera
    coop_any_p1_route = "game",       -- v0.9.171 (dev): both on pawns, two controllers: player 1's pawn reads the Arisen's game input ("game") or player 1's controller directly ("pad")          -- v0.9.171 (dev): where player 2's second pawn's processor runs: "auto" | "player" | "pre"
    coop_any = true,                  -- v0.9.171 (dev): in co-op each player's take-control combination (F6 = player 1) goes to their next character, the Arisen included; both players can be on pawns (the Arisen on AI)
    cycle_skip_arisen = false,        -- v0.9.150: the take-control combination skips the Arisen (pawns only; hold D-pad down goes back)
    hint_controls = true,             -- v0.9.149: one line on screen that says which button takes control of whom
    hint_y = 0.925,                   -- its height on the screen (share of the height; it sits over the selection label)
    pad_l1_stick_select = false,      -- v0.9.97 (retired in 0.9.98)
    pad_l1_l3_possess = true,         -- v0.9.98: L1 + left stick click = take control of the selection (or possess / go back)
    pawn_quick_lantern = true,        -- v0.9.79 / 0.9.80: the lantern shortcut works the Arisen's lantern while possessing
    arisen_no_death = true,           -- v0.9.80: the Arisen cannot die while a pawn is possessed (not in co-op)
    coop_p2_arisen_no_death = true,   -- 0.9.171: ... also while player 2 plays him (co-op, player 1 on a pawn)
    pawn_arrow_counts = true,         -- v0.9.160: the skill list shows the played pawn's own special-arrow counts
    cheat_free_arrows = true,        -- v0.9.154 cheat: special arrows are not used up while a pawn is played 0.9.172-dev28: on by default (the tester: without it the bow skills look broken to most players)
    cheat_free_arrows_nobag = false,  -- v0.9.159 experimental, off: ... and are not needed in the bag at all. The game crashed once with this on
    party_heal_key = false,           -- v0.9.80: Numpad . heals / revives the party (a cheat; off by default since 0.9.114)
    party_heal_arisen = true,         --   ... and the Arisen
    coop_pad_names = 1,               -- v0.9.80: button names in player 2's skill list: 1 auto, 2 PlayStation, 3 Xbox
    pawn_quick_item = true,           -- v0.9.77: the quick-use recovery item goes to the pawn you control
    pawn_quick_item_labels = true,    -- v0.9.148: the quick-item cross names the played pawn's own item and count
    possess_danger_pawn = true,       -- v0.9.75: red screen edge / flash follow the possessed pawn, not the Arisen
    pawn_interact_dead_people = false, -- v0.9.109: false = the played pawn leaves dead NPCs alone (a Wakestone revive is the Arisen's)
    pawn_revive = true,               -- v0.9.68: Interact next to a downed party pawn revives him
    pawn_revive_hold = 3.8,           -- v0.9.69: s the Interact button must be held (0 = single press)
    pawn_revive_health = 0.5,         --   share of his current maximum health he comes back with
    pawn_wake = true,                 -- v0.9.63: Interact next to a sleeping companion or the Arisen wakes them
    pawn_aim_camera = true,           -- v0.9.29: possessed Archer gets the bow aim camera and turns with it
    pawn_aim_reticle = true,          -- v0.9.30: and the bow reticle
    pawn_aim_point = true,            -- v0.9.34: on (the corrected write, verified by the tester in archer-aim-6)
    pawn_aim_ray = true,              -- v0.9.35: aim at what the camera's centre line hits (ray cast), like the Arisen
    pawn_aim_point_dist = 30.0,       -- m along the camera's view when the ray hits nothing (sky)
    interact_bring = false,           -- v0.9.24 experiment, off since 0.9.25 (Interact shares Triangle with dash: stray warps)
    interact_bring_dist = 2.0,        -- m
    number_row_skills = false,        -- v0.9.23: keys 1-6 on the number row also fire the possessed pawn's skills
    quick_skills = true,              -- v0.9.14: Numpad 1-6 = the selected pawn (F6/F7 pawn) uses skill 1-6, while not possessing
    coop_kbm_glyphs = true,           -- v0.9.13: keep the HUD on keyboard/mouse prompts (player 1) while player 2 uses the pad
    coop_chord_skills = true,         -- v0.9.13: L1 + Square+Cross = skill 5, L1 + Triangle+Circle = skill 6 (0.9.20; was Cross+Circle)
    coop_chord_window = 0.16,         -- s: a chord's first face button waits this long for its partner
    coop_auto_target = true,          -- v0.9.12: player 2's pawn locks the best enemy in front of it (skills and shots aim at it)
    coop_target_range = 15.0,         -- m
    coop_target_game_ranges = true,   -- v0.9.140: range from the game's own lock-on table for the pawn's vocation and skills (read once, kept)
    coop_target_cone = 75.0,          -- half-angle in front of the pawn (deg); anything within 5 m counts from any side
    coop_target_thief = false,        -- also for a Thief (the Thief crash family ran in lock-on worker code)
    coop_map_source = "builtin",      -- (old, unused since 0.9.124)
    coop_map_assign = true,           -- v0.9.124: player 2's buttons follow the game's controller assignment (off = the default layout)
    coop_layout_file = false,         -- v0.9.124: also apply data/DPC_coop_layout.json (hand-made overrides)
    cmd_file = true,                -- dev: data/DPC_cmd.json commands (possess/release/spawn/...), see MODLOG
    -- v0.8.1 test bench
    test_hotkeys = true,            -- (developer mode only since 0.9.114) F9 spawn selected test (Shift+F9 = mark), F10 despawn, F11 brain on/off
    test_keys = { spawn = 0x78, despawn = 0x79, toggle_brain = 0x7A },
    test_preset = 1,                -- 0 = custom spawn
    test_custom = { enemy = 1, count = 1, dist = 14.0, angle = 0, still = true, around = "arisen" },
    migrated_081 = false,
    migrated_0811 = false,
    -- Subsystem toggles for Mode 2 (all safe, can be toggled live):
    sub_camera_attach = true,       -- Attach MainCameraController to Pawn
    sub_disable_arisen_pip = true,  -- Block Arisen PlayerInputProcessor:update() while possessing
    sub_suppress_ai = true,         -- Set DecisionModule.IsSkipThink & DisableNavi on Pawn
    sub_puppeteer_move = true,      -- Drive Pawn camera-relative locomotion via stick / WASD
    sub_puppeteer_combat = true,    -- Drive Pawn attacks, skills, jump, defend, draw/sheathe
    sub_mirror_input_flags = true,  -- Mirror button bitflags & float stick axes to pawn_input
    -- Granular experimental toggles for Mode 1 / Mode 3 (isolated for crash diagnosis):
    exp_rebind_lockon = true,
    exp_swap_inputs = true,
    exp_call_select_proc = false,
    exp_add_player_sel = false,
    swap_player_comp_refs = false,
    swap_manual_player = false,
    set_human_is_arisen = false,
    hotkeys_on = true,              -- 0.9.173: master switch for every DPC keyboard shortcut (controller combinations stay)
    keys = {
        toggle_possess = 0x75,      -- F6
        party_heal     = 0x6E,      -- Numpad . : heal / revive every pawn (v0.9.15, from PawnCommander)
        party_warp     = 0x67,      -- Numpad 7 : warp every pawn to you (v0.9.15, from PawnCommander)
        cycle_pawn     = 0x76,      -- F7
        warp_arisen    = 0x77,      -- F8
        coop           = 0x75,      -- Ctrl+F6: start/stop couch co-op with the selected pawn
        coop_ctrl      = true,      -- v0.9.150: the co-op key needs Ctrl held (set when the key is chosen)
        skill1 = 0x61, skill2 = 0x62, skill3 = 0x63, skill4 = 0x64, skill5 = 0x65, skill6 = 0x66, -- v0.9.150: skill orders (Numpad 1-6)
        -- 0.9.172: go straight to a character (Ctrl + F1 the Arisen, Ctrl + F2-F4 pawns 1-3; pawns 4-8 for mods with
        -- a bigger party, unset). In co-op these are player 1's.
        jump_arisen = 0x70, jump_arisen_ctrl = true,
        jump_pawn1 = 0x71, jump_pawn1_ctrl = true,
        jump_pawn2 = 0x72, jump_pawn2_ctrl = true,
        jump_pawn3 = 0x73, jump_pawn3_ctrl = true,
        jump_pawn4 = 0, jump_pawn5 = 0, jump_pawn6 = 0, jump_pawn7 = 0, jump_pawn8 = 0,
    },
    pad = {
        toggle_possess = 0,
        take = 0,                   -- v0.9.149: button combination "take control / next pawn"; 0 = L1 + left stick click
        back = 0,                   -- v0.9.149: button combination "back to the Arisen"; 0 = none (hold D-pad down does it)
        coop = 0,                   -- v0.9.150: button combination "start / stop couch co-op"; 0 = none
    },
}

-- v0.9.1: the controller state lives here (filled by poll_pad further down). In v0.9.0 these locals were declared
-- after coop.pad_input, so co-op read undefined globals and player 2's controller did nothing.
local pad_buttons, pad_prev = 0, 0
local pad_stick_x, pad_stick_y = 0.0, 0.0
local pad_stick_rx, pad_stick_ry = 0.0, 0.0
local is_key_down_safe -- v0.9.1: forward declaration; coop.filter called it as an undefined global
local pad_device_ok = nil -- nil = not polled yet, false = no controller device, true = reading it

local coop_saved_for_cfg = nil -- set while co-op overrides are applied (see coop_apply_overrides)
local function save_cfg()
    cfg.version_tag = "v5"
    if json and json.dump_file then
        local cur = nil
        if coop_saved_for_cfg then
            cur = {}
            for k, v in pairs(coop_saved_for_cfg) do cur[k] = cfg[k]; cfg[k] = v end
        end
        local ov = {} -- v0.9.170: settings another mod overrides for this session (DPC_API.override) are not saved
        if dev.api_overrides then -- (R is declared below this function; the API puts its table here)
            for k, reg in pairs(dev.api_overrides) do
                if cfg[k] ~= reg.value then reg.saved, reg.value = cfg[k], cfg[k] end -- the player changed it since
                ov[k] = cfg[k]; cfg[k] = reg.saved
            end
        end
        local oks, res = pcall(json.dump_file, CONFIG_PATH, cfg, 2)
        for k, v in pairs(ov) do cfg[k] = v end
        dev.save_ok = oks and res ~= false
        if not dev.save_ok then dev_error("save_cfg", res) end
        if cur then for k, v in pairs(cur) do cfg[k] = v end end
    end
end

local function load_cfg()
    if not (json and json.load_file) then return end
    -- 0.9.172-dev18: data/DPC_reset.json with {"reset": true} starts from the defaults once (the old settings are
    -- left in DirectPawnControl.before_reset.json). A running DPC saves its settings whenever one changes, so an
    -- edited settings file could be overwritten before the next script reset; this flag cannot be.
    local okr, rf = pcall(json.load_file, "DPC_reset.json")
    if okr and type(rf) == "table" and rf.reset == true then
        local okd, old = pcall(json.load_file, CONFIG_PATH)
        if okd and type(old) == "table" then pcall(json.dump_file, "DirectPawnControl.before_reset.json", old, 2) end
        pcall(json.dump_file, "DPC_reset.json", { reset = false, done = os.time() })
        save_cfg()
        return
    end
    local ok, d = pcall(json.load_file, CONFIG_PATH)
    if not ok or type(d) ~= "table" then return end
    if d.version_tag ~= "v5" then
        save_cfg()
        return
    end
    -- 0.9.172 (the tester: "I don't want their bad old settings to stealth-ruin gameplay for early adopters ... maintain
    -- key bindings where they're applicable but come in fresh with most settings"). A file from before 0.9.172 keeps
    -- only the key and controller bindings (and the window positions); everything else starts from the new defaults.
    -- The old file stays as DirectPawnControl.before_0.9.172.json.
    if (tonumber(d.settings_gen) or 1) < 2 then
        pcall(json.dump_file, "DirectPawnControl.before_0.9.172.json", d, 2)
        local kept = { version_tag = d.version_tag }
        for k, v in pairs(d) do
            if k == "keys" or k == "pad" or k == "test_keys" then kept[k] = v end
        end
        d = kept
        cfg.fresh_from_old = true
    end
    for k, v in pairs(d) do
        if type(v) == "table" and type(cfg[k]) == "table" then
            for k2, v2 in pairs(v) do cfg[k][k2] = v2 end
        elseif cfg[k] ~= nil then
            cfg[k] = v
        end
    end
end
load_cfg()
if (cfg.pf_defaults_v or 0) < 1 then -- dev4: a config saved before the sound defaults changed gets them once
    cfg.pf_sound_voice, cfg.pf_sound_listener, cfg.pf_sound_space, cfg.pf_defaults_v = true, 1, true, 1
    save_cfg()
end
-- 0.9.173: new default colours (player 1 Cyan, player 2 White). A config still on the old default pair (Gold, Cyan)
-- moves to the new one once; any other pick is the player's own and stays.
if (cfg.colors_v or 0) < 1 then
    if cfg.coop_aim_p1_color == 1 and cfg.coop_aim_p2_color == 2 then cfg.coop_aim_p1_color, cfg.coop_aim_p2_color = 2, 6 end
    cfg.colors_v = 1
    save_cfg()
end
-- v0.9.16 release hygiene: the developer tooling (command file, robot player, test spawner commands, telemetry
-- files written every second) only runs when data/DPC_dev.json exists with {"dev": true}. A released copy
-- writes nothing but its config and the small session file below.
local R = { dev = false, note = nil } -- one table: the main chunk is at Lua's 200-local limit
if cfg.fresh_from_old then -- 0.9.172: written once with the new defaults and the kept bindings
    cfg.fresh_from_old = nil
    cfg.settings_gen = 2
    save_cfg()
    R.fresh_note = true
end
R.cr = { want = false }
R.CR_USER = { ["co-op off"] = true, ["UI button"] = true, ["hotkey toggle"] = true, ["cmd file"] = true,
              ["mode change"] = true, ["script reset"] = true, ["starting co-op"] = true, ["co-op change"] = true }
do
    local ok, d = pcall(json.load_file, "DPC_dev.json")
    R.dev = ok and type(d) == "table" and d.dev == true
end
function R.dump(path, t, indent)
    if R.dev then return pcall(json.dump_file, path, t, indent) end
end

-- v0.9.16 session sentinel. DPC_session.json says whether a pawn is possessed right now. If the game starts and
-- the file still says "possessing", the last session ended in the middle of a possession (a crash, or quitting
-- while possessing). Two such endings on a natively controlled Thief switch Thief pawns to the puppeteer
-- (every Thief crash so far happened on native controls), with a note in the DPC window.
function R.session_write(active, job, pawn)
    pcall(json.dump_file, "DPC_session.json", { active = active and true or false, job = job or 0, pawn = pawn or "",
        native = (active and cfg.native_controls and not (cfg.native_skip_thief and job == 4)) and true or false,
        version = VERSION, at = os.time() })
end
-- v0.7.4: the native-controls experiment had players untick these two dev boxes, which leaves the Mode 2
-- puppeteer (still used for Thief pawns and as the native fallback) with no movement or combat. Re-enable once.
if cfg.coop_chord_window == 0.09 then -- v0.9.19: 90 ms was too tight to press two buttons "together"
    cfg.coop_chord_window = 0.16
    save_cfg()
end
if not cfg.migrated_0946 then -- undo the false self-check trip that left the controller driving the Arisen in co-op
    cfg.coop_zero_pad_for_arisen = true
    cfg.migrated_0946 = true
    save_cfg()
end
if not cfg.migrated_0945 then -- head anchor: the old feet-based offsets no longer apply
    cfg.coop_stamina_dx, cfg.coop_stamina_dy, cfg.coop_stamina_head_up, cfg.coop_stamina_frames = -9.0, 10.0, 0.44, 0
    cfg.migrated_0944, cfg.migrated_0945 = true, true
    save_cfg()
end
if not cfg.migrated_glow_keep then -- 0.9.172-dev45: kept glows on by default
    cfg.coop_glow_keep = true
    cfg.migrated_glow_keep = true
end
if not cfg.migrated_down_alert then -- 0.9.172-dev32: the alert is off by default now
    cfg.down_alert = false
    cfg.migrated_down_alert = true
    save_cfg()
end
if not cfg.migrated_free_arrows then -- 0.9.172-dev28: on by default; the reset left it saved as false
    cfg.cheat_free_arrows = true
    cfg.migrated_free_arrows = true
    save_cfg()
end
if not cfg.migrated_cam_shared then -- 0.9.172-dev22: the camera tests left coop_cam_turn saved as "auto"
    cfg.coop_cam_turn = "shared"
    cfg.migrated_cam_shared = true
    save_cfg()
end
if not cfg.migrated_coop_aim then -- 0.9.172-dev16: co-op aiming on by default; the aim tests left it saved as false
    cfg.coop_aim = true
    cfg.migrated_coop_aim = true
    save_cfg()
end
if not cfg.migrated_dash_keep then -- 0.9.172-dev14: the pawn-dash tests left native_dash_keep saved as false
    cfg.native_dash_keep = true
    cfg.migrated_dash_keep = true
    save_cfg()
end
if not cfg.migrated_0944 then -- stamina bar defaults measured from the 0.9.43 screenshot
    if cfg.coop_stamina_dx == 0 and cfg.coop_stamina_dy == 0 then cfg.coop_stamina_dx, cfg.coop_stamina_dy = -9.0, 24.0 end
    cfg.migrated_0944 = true
    save_cfg()
end
if not cfg.migrated_0934 then -- steering fixed in 0.9.33, on from 0.9.34
    cfg.pawn_aim_point, cfg.pawn_aim_point_dist = true, 25.0
    cfg.migrated_0931, cfg.migrated_0934 = true, true
    save_cfg()
end
if not cfg.migrated_0931 then -- the aim point was on by default in 0.9.30
    cfg.pawn_aim_point = false
    cfg.migrated_0931 = true
    save_cfg()
end
if not cfg.migrated_0927 then -- the palette was on by default before 0.9.27
    cfg.skill_hud_overlay = false
    cfg.migrated_0927 = true
    save_cfg()
end
if not cfg.migrated_0925 then -- the interact helper was on by default in 0.9.24 only
    cfg.interact_bring = false
    cfg.migrated_0925 = true
    save_cfg()
end
if not cfg.migrated_0983 then
    -- v0.9.83: the game's own revive takes 3.8 s (the tester); move a saved 2.0 (the 0.9.69 guess) to it
    if cfg.pawn_revive_hold == 2.0 then cfg.pawn_revive_hold = 3.8 end
    cfg.migrated_0983 = true
    save_cfg()
end
if not cfg.migrated_0114 then
    -- v0.9.114: the status panel became opt-in. A settings file from before carries the old "on"; switch it off
    -- once (it can be ticked again under Screen). The heal cheat is left as the file has it.
    cfg.hud_overlay = false
    cfg.show_legacy = false
    cfg.migrated_0114 = true
    save_cfg()
end
if not cfg.migrated_0974 then
    -- v0.9.74: undo anything the retired automatic Thief fallback may have set
    cfg.native_skip_thief = false
    cfg.thief_unclean = nil
    cfg.migrated_0974 = true
    save_cfg()
end
if not cfg.migrated_0811 then
    -- v0.8.11: Thief gets native controls (retest under the v0.7.5 app.Player.update timing)
    cfg.native_skip_thief = false
    cfg.migrated_0811 = true
    save_cfg()
end
if not cfg.migrated_081 then
    -- v0.8.1: one "Arisen follows you" switch drives both the brain's follow and the classic tether
    cfg.arisen_auto_follow = cfg.arisen_brain_follow
    cfg.migrated_081 = true
    save_cfg()
end
if not cfg.migrated_074 then
    cfg.sub_puppeteer_move = true
    cfg.sub_puppeteer_combat = true
    cfg.migrated_074 = true
    save_cfg()
end

-- ----------------------------------------------------------------------------
-- Logging, Synchronous Crash Breadcrumb Trace & Safe SDK Helpers
-- ----------------------------------------------------------------------------
local logs = {}
local MAX_LOGS = 80
local trace_steps = {}

local function write_trace(step_name, extra)
    table.insert(trace_steps, string.format("[%.3f] %s%s",
        os.clock(), tostring(step_name), extra and (" | " .. tostring(extra)) or ""))
    while #trace_steps > 50 do table.remove(trace_steps, 1) end
    if json and json.dump_file then
        R.dump(TRACE_PATH, {
            version = VERSION,
            last_step = step_name,
            control_mode = cfg.control_mode,
            steps = trace_steps,
        }, 2)
    end
end

local function log_msg(msg)
    local line = string.format("[%.2f] %s", os.clock(), tostring(msg))
    table.insert(logs, line)
    if #logs > MAX_LOGS then table.remove(logs, 1) end
    write_trace("LOG: " .. tostring(msg))
    pcall(log.info, "[DirectPawnControl] " .. tostring(msg))
end

local function same_obj(a, b)
    if not a or not b then return false end
    local ok_a, addr_a = pcall(a.get_address, a)
    local ok_b, addr_b = pcall(b.get_address, b)
    return ok_a and ok_b and addr_a ~= nil and addr_a ~= 0 and addr_a == addr_b
end

local function call(obj, method, ...)
    if not obj then return nil end
    local ok, res = pcall(obj.call, obj, method, ...)
    if ok then return res end
    return nil
end

local function field(obj, name)
    if not obj then return nil end
    local ok, res = pcall(obj.get_field, obj, name)
    if ok then return res end
    return nil
end

local function set_field(obj, name, val)
    if not obj then return false end
    local ok = pcall(obj.set_field, obj, name, val)
    return ok
end

-- Multi-signature robust locomotion caller:
-- sel:requestLocomotionImpl(app.LocomotionSpeedTypeEnum speed_type, System.Boolean is_strafe)
--   speed_type: 0=Idle, 1=Walk, 2=Run, 3=Dash
--   is_strafe:  false=NormalLocomotion (forward sprint/run/walk), true=Strafe (combat sidestep)
-- The first form that succeeds is cached, so we never retry failing signatures every frame
-- (repeated caught engine exceptions are a known delayed-crash cause in DD2).
local LOCO_FORMS = {
    "requestLocomotionImpl(app.LocomotionSpeedTypeEnum, System.Boolean)",
    "requestLocomotionImpl",
    "requestLocomotionImpl(System.UInt32, System.Boolean)",
    "requestLocomotion",
}
local loco_form_idx = nil
local loco_probe_fail_until = 0.0
local function safe_request_locomotion(sel, speed_type, is_strafe)
    if not sel then return false end
    is_strafe = (is_strafe == true)
    if loco_form_idx then
        local ok = pcall(sel.call, sel, LOCO_FORMS[loco_form_idx], speed_type, is_strafe)
        if ok then return true end
        loco_form_idx = nil -- re-probe once if the cached form stopped working
    end
    if os.clock() < loco_probe_fail_until then return false end
    for i, form in ipairs(LOCO_FORMS) do
        if pcall(sel.call, sel, form, speed_type, is_strafe) then
            loco_form_idx = i
            return true
        end
    end
    loco_probe_fail_until = os.clock() + 5.0 -- all forms failed: back off instead of throwing every frame
    return false
end

-- ----------------------------------------------------------------------------
-- Game-Thread Action Queue (Prevents calling game SDK methods from re.on_frame)
-- ----------------------------------------------------------------------------
local main_thread_queue = {}

local function enqueue_game_thread(desc, fn)
    table.insert(main_thread_queue, { desc = desc, fn = fn })
end

-- ----------------------------------------------------------------------------
-- Enums & Static Methods (Loaded Lazily from Runtime Reflection)
-- ----------------------------------------------------------------------------
local SKILL_NAMES = {}
local ACTION_ENUM = {}
local ACTION_FLAGS = {}
local PAD_BUTTONS = {}
local JOB_NAMES = {
    [1] = "Fighter", [2] = "Archer", [3] = "Mage", [4] = "Thief",
    [5] = "Warrior", [6] = "Sorcerer", [7] = "Mystic Spearhand",
    [8] = "Magick Archer", [9] = "Trickster", [10] = "Warfarer",
}
local VOCATION_ACTION_NAMES = {
    [1] = "Defend (Shield Guard)",
    [2] = "Steady Shot (Aim)",
    [3] = "Quickspell / Anodyne",
    [4] = "Swift Step (Dodge)",
    [5] = "Barge",
    [6] = "Quickspell / Galvanize",
    [7] = "Redoubted Bolt",
    [8] = "Magickal Bow Aim",
    [9] = "Invoke Effigy",
    [10] = "Vocation Action",
}
-- app.LocomotionSpeedTypeEnum verified values:
local SPEED_IDLE = 0
local SPEED_WALK = 1
local SPEED_RUN  = 2
local SPEED_DASH = 3

local enums_loaded = false
local get_cam_angle_rad_method = nil
local in_internal_query = false

local function read_enum(type_name)
    local by_val, by_name, list = {}, {}, {}
    local td = sdk.find_type_definition(type_name)
    if not td then return by_val, by_name, list end
    for _, f in ipairs(td:get_fields()) do
        if f:is_static() then
            local ok, v = pcall(f.get_data, f, nil)
            local name = f:get_name()
            if ok and type(v) == "number" and name ~= "value__" then
                by_val[v] = name
                by_name[name] = v
                table.insert(list, { name = name, value = v })
            end
        end
    end
    table.sort(list, function(a, b) return a.value < b.value end)
    return by_val, by_name, list
end

local function ensure_enums()
    if enums_loaded then return end
    local sk_val = read_enum("app.HumanCustomSkillID")
    local _, act_name = read_enum("app.CharacterInput.Action")
    local _, _, pad_list = read_enum("via.hid.GamePadButton")
    local pip_detail_td = sdk.find_type_definition("app.PlayerInputProcessorDetail")
    if pip_detail_td then
        get_cam_angle_rad_method = pip_detail_td:get_method("getCameraAngleRad")
    end
    local ci_td = sdk.find_type_definition("app.CharacterInput")
    local get_flag_m = ci_td and ci_td:get_method("getInputFlag")
    if next(sk_val) and next(act_name) then
        SKILL_NAMES = sk_val
        ACTION_ENUM = act_name
        PAD_BUTTONS = pad_list
        ACTION_FLAGS = {}
        for name, id in pairs(act_name) do
            if type(id) == "number" and id >= 0 and id < 63 then
                local flag = (1 << id)
                if get_flag_m then
                    local ok, fval = pcall(get_flag_m.call, get_flag_m, nil, id)
                    if ok and type(fval) == "number" and fval > 0 then
                        flag = fval
                    end
                end
                ACTION_FLAGS[name] = flag
            end
        end
        enums_loaded = true
        log_msg("Loaded runtime enums & CharacterInput bitflags")
    end
end

-- Localized names are resolved on the game thread (get_skills) and only read here, so skill_name()
-- is safe to call from the render thread.
local LOC_NAMES = {}   -- HumanCustomSkillID -> localized name at its current level
local LOC_LEVEL = {}   -- HumanCustomSkillID -> level the cached name was resolved at
local gui_name_job, gui_name_plain, gui_name_tried = nil, nil, false

local function valid_name(v)
    return type(v) == "string" and v ~= "" and not v:find("^<REF")
end

local function localize_skill(sc, job, id)
    if not cfg.localized_skill_names or type(id) ~= "number" or id == 0 or not sc then return end
    local lv = call(sc, "getCustomSkillLevel", id)
    if type(lv) ~= "number" or lv < 1 then lv = 1 end
    if LOC_LEVEL[id] == lv then return end
    LOC_LEVEL[id] = lv
    if not gui_name_tried then
        gui_name_tried = true
        local td = sdk.find_type_definition("app.GUIBase")
        if td then
            gui_name_job = td:get_method("getCustomSkillName(app.Character.JobEnum, app.HumanCustomSkillID, app.HumanCustomSkillLevelNo)")
            gui_name_plain = td:get_method("getCustomSkillName(app.HumanCustomSkillID, app.HumanCustomSkillLevelNo)")
        end
    end
    -- The job-qualified overload resolves names the plain one misses (e.g. High Flagration -> "<REF ...>").
    local tries = {}
    if gui_name_job then tries[#tries + 1] = function(l) return gui_name_job:call(nil, job, id, l) end end
    if gui_name_plain then tries[#tries + 1] = function(l) return gui_name_plain:call(nil, id, l) end end
    for _, l in ipairs({ lv, 1 }) do
        for _, f in ipairs(tries) do
            local ok, v = pcall(f, l)
            if ok and valid_name(v) then
                LOC_NAMES[id] = v
                return
            end
        end
    end
end

local function skill_name(id)
    if not id or id == 0 then return "(empty)" end
    if cfg.localized_skill_names and LOC_NAMES[id] then return LOC_NAMES[id] end
    local n = SKILL_NAMES[id]
    if n then return (n:gsub("^Job%d%d_", "")) end
    return "Skill#" .. tostring(id)
end

-- ----------------------------------------------------------------------------
-- Live Party Discovery (from PawnCommander patterns)
-- ----------------------------------------------------------------------------
local function get_pawn_component(chara, idx)
    local pm = sdk.get_managed_singleton("app.PawnManager")
    if not pm then return nil end
    if idx == 0 then
        local mp = field(pm, "_MainPawn") or call(pm, "get_MainPawn")
        if mp then return mp end
    end
    local party_list = call(pm, "get_PartyPawnList")
    if party_list then
        local count = call(party_list, "get_Count") or 0
        for i = 0, count - 1 do
            local p = call(party_list, "get_Item", i)
            if p then
                local c = call(p, "get_CachedCharacter")
                if same_obj(c, chara) then return p end
            end
        end
    end
    return nil
end

local function get_job(human, chara)
    in_internal_query = true
    local jc = human and call(human, "get_JobContext")
    local j = jc and (call(jc, "get_Job") or field(jc, "CurrentJob"))
    if type(j) ~= "number" or j <= 0 then
        j = chara and (call(chara, "getWeaponJob") or field(chara, "WeaponJob"))
    end
    in_internal_query = false
    if type(j) == "number" and j > 0 then return j end
    return 1
end

-- Docs and working code disagree on the getter name (get_SkillContext vs get_HumanCustomSkillContext);
-- probe both once and cache whichever returns a context that answers getSkillID.
local SKILL_CTX_GETTERS = { "get_SkillContext", "get_HumanCustomSkillContext" }
local skill_ctx_getter = nil
local function get_skill_ctx(human)
    if not human then return nil end
    if skill_ctx_getter then return call(human, skill_ctx_getter) end
    for _, g in ipairs(SKILL_CTX_GETTERS) do
        local sc = call(human, g)
        if sc then
            skill_ctx_getter = g
            log_msg("Skill context getter resolved: " .. g)
            return sc
        end
    end
    return nil
end

local function get_skills(human, job)
    local s = { 0, 0, 0, 0, 0, 0 }
    if not human or not job or job == 0 then return s end
    in_internal_query = true
    local sc = get_skill_ctx(human)
    if sc then
        for slot = 0, 5 do -- slots 5/6 = the extra Skill5 / Skill6 palette
            local id = call(sc, "getSkillID", job, slot)
            if type(id) == "number" then
                s[slot + 1] = id
                localize_skill(sc, job, id)
            end
        end
    end
    in_internal_query = false
    return s
end

local function get_party()
    local out = {}
    local pm = sdk.get_managed_singleton("app.PawnManager")
    if not pm then return out end
    local list = call(pm, "get_PawnCharacterList")
    if not list then return out end
    local n = call(list, "get_Count") or 0
    for i = 0, n - 1 do
        local chara = call(list, "get_Item", i)
        if chara then
            local human = call(chara, "get_Human")
            local pdc = human and call(human, "get_PawnDataContext")
            local name = pdc and call(pdc, "get_Name")
            -- v0.9.110: a name the overlay font cannot draw (non-Latin) -> the pawn's moniker, which is what the
            -- game's own name plate shows for it (read live: a Name in non-Latin characters, a Nickname in Latin ones)
            if name and tostring(name):find("[\128-\255]") then
                local nick = pdc and call(pdc, "get_Nickname")
                if nick and nick ~= "" then name = nick end
            end
            local job = get_job(human, chara)
            table.insert(out, {
                idx = i,
                chara = chara,
                human = human,
                pawn = get_pawn_component(chara, i),
                name = (name and name ~= "") and name or (i == 0 and "Main Pawn" or ("Hired Pawn " .. i)),
                job = job,
                job_name = JOB_NAMES[job] or ("Job#" .. tostring(job)),
                skills = get_skills(human, job),
            })
        end
    end
    return out
end

-- ----------------------------------------------------------------------------
-- Possession State & Saved Original References
-- ----------------------------------------------------------------------------
local state = {
    active = false,
    frames_since_start = 0,
    pawn_idx = 0,
    pawn_name = "",
    pawn_job = 1,
    pawn_skills = { 0, 0, 0, 0, 0, 0 },
    -- Saved Arisen objects for 100% clean restoration
    arisen_chara = nil,
    arisen_human = nil,
    arisen_go = nil,
    arisen_input = nil,
    arisen_pip = nil,
    arisen_track = nil,
    arisen_player_comp = nil,
    arisen_lockon_ctrl = nil,
    arisen_skill_ctx = nil,
    arisen_job_ctx = nil,
    orig_keyguide = nil,            -- Cached native KeyGuide widget pointers while possessing
    hud_shift_held = false,         -- Skill-shift modifier held this frame (drives the native skill guide)
    next_hud_check_t = 0.0,
    -- Saved Pawn objects
    pawn_chara = nil,
    pawn_human = nil,
    pawn_go = nil,
    pawn_input = nil,
    pawn_obj = nil,
    pawn_orig_is_player = false,
    pawn_orig_is_arisen = false,
    -- Track which pawn addresses already had addPlayerSelectors() called
    added_player_selectors = {},
    -- PawnCommander retry windows (ensures skills & attacks fire cleanly even if weapon was sheathed)
    pending_skill = nil,            -- { id, slot, speed_type, until_t, tries }
    pending_attack = nil,           -- { heavy, speed_type, until_t, tries }
    combo_buffer = nil,             -- { speed_type, until_t, next_t, tries } light-attack combo continuation
    input_log = {},                 -- cfg.debug_input ring buffer (see dbg_event), flushed to data/DPC_input_log.json
    input_log_dirty = false,
    next_input_log_flush = 0.0,
    atk_trace_until = 0.0,
    atk_trace_last = "",
    active_cast = nil,              -- { id, slot, start_t, released, is_ready }
    suppress_loco_until = 0.0,      -- Brief window after attack/skill/jump so locomotion doesn't cancel startup
    -- Movement, Sprint & Guard state
    was_moving = false,
    is_sprinting = false,
    is_guarding = false,
    is_aiming = false,
    is_quickspelling = false,
    arisen_was_following = false,
    -- Diagnostics
    live_speed_mps = 0.0,
    last_speed_time = 0.0,
    last_pawn_pos = nil,
    arisen_pip_blocked_count = 0,
    last_trg_flags = 0,
    last_on_flags = 0,
    last_action_str = "Idle",
    last_move_deg = 0.0,
    last_stick_mag = 0.0,
    last_cam_deg = 0.0,
    -- Raw native addresses for allocation-free hot-hook comparisons
    arisen_chara_addr = 0,
    arisen_skill_ctx_addr = 0,
    arisen_job_ctx_addr = 0,
    arisen_pip_addr = 0,
    pawn_sel_addr = 0,              -- possessed pawn's HumanActionSelector (sit-request filter)
    -- Throttles & warp bookkeeping
    next_skill_refresh_t = 0.0,
    far_since_t = nil,
    next_auto_warp_t = 0.0,
    last_tick_err_t = 0.0,
    arisen_stay = false,      -- Wait command: Arisen holds position (auto-warp still applies past arisen_warp_dist)
    warp_check = nil,         -- { t = os.clock() deadline, pawn_pos = Vector3f } pending post-warp verification
}

-- Snapshot read by re.on_frame / ImGui. Only the game thread (UpdateBehavior) writes it,
-- so the render thread never calls into the SDK or toggles in_internal_query.
local ui_cache = {
    party = {},
    next_party_t = 0.0,
    hp = 0, max_hp = 1,
    active_sk = 0,
    weapon_drawn = false,
    cam_id = "nil",
}

local function addr_of(obj)
    if not obj then return 0 end
    local ok, a = pcall(obj.get_address, obj)
    if ok and type(a) == "number" then return a end
    return 0
end

-- Hook args are raw void* userdata; to_int64 is allocation-free (unlike to_managed_object)
local function arg_addr(arg)
    return arg and sdk.to_int64(arg) or 0
end

-- ----------------------------------------------------------------------------
-- v0.8: Arisen combat brain ("fights like a pawn of his vocation" while you possess a pawn)
--
-- How it works (all verified live on an Archer Arisen, unpossessed, 2026-11-10):
--   * The Arisen keeps running his OWN app.PlayerInputProcessor (the game's player controls) instead of having it
--     blocked. In the pre-hook of that update the brain REPLACES his CharacterInput with synthetic input:
--     button bitflags (On/Trigger/Release) and the left stick (setAxisL + set_AxisMagnitudeL).
--     -> movement is camera-relative stick, attacks are AttackS presses, skills are SkillN + Shift1 + Shift2 holds.
--   * Everything the game does for a real player then happens natively: weapon draw, Job02 shots with real arrows
--     (ShellManager shells, enemy HP drops), stamina, combos.
--   * Single-precision args MUST be Lua floats: set_AxisMagnitudeL(1) (integer) arrives as ~0 and nothing moves.
--   * Facing: the "shoot without aim" shot flies straight ahead of the character, so the brain turns him with a
--     small stick push until he faces the target (face_tol) before pressing attack. Set_AimTargetPosition is
--     cleared by the processor every frame and does not steer these shots.
--   * The without-aim target finder is camera based (LockOnController.findTargetBasedOnCamera); while you possess a
--     pawn the camera is yours, so arrows home on what you are looking at. Targets 1 m+ above him with nothing
--     found by the camera can be missed (seen live). DO NOT hook LockOnController finders: an exception inside one
--     (run under FindTargetMutex) hung the game.
-- ----------------------------------------------------------------------------
local BRAIN_LOG_PATH = "DPC_arisen_brain.json"
local brain = {
    on = false,             -- brain driving the Arisen this frame
    solo = false,           -- dev: drive the Arisen even when nothing is possessed (cmd file / UI)
    ar = nil, ar_human = nil, ar_input = nil, pip_addr = 0,
    job = 0, skills = { 0, 0, 0, 0 }, next_job_t = 0,
    target = nil, target_id = "-", next_scan = 0,
    mode = "off", dist = 0, off = 0,
    want = 0, ax = 0.0, ay = 0.0, mag = 0.0, prev = 0,
    hw_prev_on = 0,         -- previous frame's hardware ButtonOnFlags (DPC recomputes triggers for the pawn)
    presses = 0, skill_uses = 0, inj = 0, err = nil, errs = 0,
    skill_slot = 0, skill_until = 0, skill_bits = 0, next_skill = 0, no_shot_until = 0,
    following = false,
    events = {}, next_dump = 0,
}

-- v0.9 couch co-op state (functions are attached further down, after the pad and possession helpers)
local coop = {
    active = false, starting = false, pawn_idx = 0, saved = nil,
    map = nil, map_src = "none", prev_on = 0, last_btn = 0, last_flags = 0,
    pb_zeroed = 0, kb_dead = 0, axis_dead = 0, ar_input_addr = 0, err = nil, events = {},
}
local COOP_OVERRIDES = {
    sub_camera_attach = false,      -- camera stays on the Arisen (player 1)
    exp_rebind_lockon = false,      -- player 1 keeps his own lock-on
    native_own_lockon = true,       -- player 2's pawn gets a lock-on of its own
    sub_disable_arisen_pip = false, -- player 1's Arisen is not blocked
    native_hud_skill_hook = false,  -- the game HUD stays player 1's
    native_hud_gauges = false,
    arisen_auto_follow = false,
}
local function coop_event(s)
    local ev = coop.events
    ev[#ev + 1] = string.format("%.2f %s", os.clock(), s)
    if #ev > 30 then table.remove(ev, 1) end
end

local function brain_event(s)
    local ev = brain.events
    ev[#ev + 1] = string.format("%.2f %s", os.clock(), s)
    if #ev > 40 then table.remove(ev, 1) end
end

local function brain_flag(name) return ACTION_FLAGS[name] or 0 end

local function brain_pos(ch)
    local xf = ch and call(ch, "get_Transform")
    local p = xf and call(xf, "get_Position")
    if not p then return nil end
    return p.x, p.y, p.z
end

local function brain_facing(ch)
    local xf = call(ch, "get_Transform")
    local r = xf and call(xf, "get_Rotation")
    if not r then return 0.0 end
    local f = r * Vector3f.new(0, 0, 1)
    return math.atan(f.x, f.z)
end

local function brain_angdiff(a, b) return (a - b + math.pi) % (2 * math.pi) - math.pi end

local function brain_alive(ch)
    if not ch then return false end
    local ok, dead = pcall(ch.call, ch, "get_IsDead")
    return ok and dead == false
end

-- world yaw (rad, atan(dx, dz)) -> left stick relative to the camera (inverse of compute_camera_move_angle_deg)
local function brain_stick_for(yaw)
    local cam = 0.0
    if get_cam_angle_rad_method then
        local ok, r = pcall(get_cam_angle_rad_method.call, get_cam_angle_rad_method, nil)
        if ok and type(r) == "number" then cam = r end
    end
    local s = yaw - cam
    return -math.sin(s) + 0.0, math.cos(s) + 0.0
end

local function brain_job_ok(job)
    if cfg.arisen_brain_any_job then return job and job > 0 end
    if job == 2 then return true end -- Archer: verified
    if cfg.arisen_brain_caster and (job == 3 or job == 6) then return true end
    if cfg.arisen_brain_hybrid and (job == 8 or job == 9 or job == 10) then return true end -- v0.9.65 -- v0.9.59 caster style (Mage, Sorcerer)
    return cfg.arisen_brain_melee and brain.MELEE[job] == true -- v0.9.51 melee style (Fighter, Thief, Warrior, Mystic Spearhand)
end

-- v0.9.51 melee style. Same machinery as the Archer brain (his own player controls: stick + attack / skill flags,
-- his own lock-on), different rules: close to reach, face the target, light-attack chains with a heavy mixed in,
-- core skills on a cooldown. The Arisen has none of the AI parts pawns and human enemies run on (no
-- AIBlackBoardController / ActionInterface / AIDecisionMaker on his GameObject, compared 2026-11-15), so their brains
-- cannot simply be switched on for him; this drives him the way a player would.
brain.MELEE = { [1] = true, [4] = true, [5] = true, [7] = true }
brain.CASTER = { [3] = true, [6] = true } -- v0.9.59 Mage, Sorcerer
-- v0.9.62 what each Mage / Sorcerer weapon skill is for (app.HumanCustomSkillID). Anything not listed (Spellhold 27,
-- 35, 36, 37, 107) is never pressed by the brain.
brain.SPELL = {
    [24] = "attack", [25] = "attack", [26] = "attack", [32] = "attack", [106] = "attack",
    [62] = "attack", [63] = "attack", [64] = "attack", [65] = "attack", [66] = "attack", [67] = "attack",
    [68] = "attack", [69] = "attack", [112] = "attack", [113] = "attack",
    [28] = "buff", [29] = "buff", [30] = "buff", [31] = "buff", [34] = "buff",
    [33] = "heal",
    [35] = "cure", -- v0.9.64 (FullRecover): cast when someone has a debilitation
}
brain.buff_t = {}
-- v0.9.65 the remaining vocations. Magick Archer (8) and Trickster (9) run the ranged rules; the Warfarer (10) runs
-- the rules of whatever weapon he holds (app.Character.getWeaponJob) and only presses skills that belong to it.
brain.decoy = {}
brain.fjob = 0 -- the vocation he fights as: his job, or for a Warfarer the job of the weapon in hand
function brain.style_for(job)
    if brain.MELEE[job] then return "melee" end
    if brain.CASTER[job] then return "caster" end
    return "ranged"
end
-- never pressed by the brain: 87 LifeReturn (needs a chosen ally), 91 SpiritArrow (spends his own health),
-- 100 the Warfarer's weapon swap
-- v0.9.73: 43 Job04_HollowOut (Gut and Run / Draw and Quarter) only works while clinging to or pinning a foe,
-- which the brain never does
-- v0.9.86: 42 AbsoluteAvoidance, 44 FlameBlade, 48 Stealth are Thief toggles that drain stamina for as long as they
-- are on. The brain switched them on in its rotation (slots 5 / 6 since 0.9.55) and never off: stamina never came
-- back, also after the player took the Arisen over (HumanStaminaController.DisableRecoverStamina = 32 "Consume",
-- read live). Not pressed any more.
brain.NEVER = { [42] = true, [43] = true, [44] = true, [48] = true, [87] = true, [91] = true, [100] = true }
function brain.skill_job(id)
    if id <= 0 then return 0 end
    if id <= 12 or id == 102 or id == 103 then return 1 end
    if id <= 23 or id == 104 or id == 105 then return 2 end
    if id <= 37 or id == 106 or id == 107 then return 3 end
    if id <= 49 or id == 101 or id == 108 or id == 109 then return 4 end
    if id <= 61 or id == 110 or id == 111 then return 5 end
    if id <= 69 or id == 112 or id == 113 then return 6 end
    if id <= 79 or id == 114 or id == 115 then return 7 end
    if id <= 91 or id == 116 or id == 117 then return 8 end
    if id <= 99 or (id >= 118 and id <= 120) then return 9 end
    return 10
end
-- v0.9.145 Warfarer: press Rearmament (skill 100) so he moves on to his next weapon. It goes out through the
-- ordered-skill path (the same one the numpad order uses). Returns false when no slot holds Rearmament.
brain.rearms = 0
function brain.rearm(now, why)
    if brain.job ~= 10 then return false, "the Arisen is not a Warfarer" end
    local slot
    for i = 1, 6 do if brain.skills and brain.skills[i] == 100 then slot = i; break end end
    if not slot then return false, "no skill slot holds Rearmament" end
    brain.order_slot, brain.order_until = slot, now + (cfg.arisen_brain_skill_hold or 0.5)
    brain.order_bits = brain_flag("Skill" .. slot) | brain_flag("Shift1") | brain_flag("Shift2")
    brain.rearms = brain.rearms + 1
    brain.rearm_next = now + math.max(5, tonumber(cfg.arisen_brain_rearm_every) or 20)
    -- v0.9.146: one press is not enough. In the first run two of three presses did nothing (he was in the middle
    -- of an attack). The attempt now stays open until the weapon in his hands has changed: no attack input in
    -- between and a new press every 1.2 s, for 8 s at the most.
    if not brain.rearm_try then
        brain.rearm_try = { from = brain.fjob, t0 = now, till = now + 8.0, n = 0, slot = slot, why = why }
        brain_event(string.format("Warfarer: Rearmament (slot %d, %s), was on weapon of job %s", slot, tostring(why), tostring(brain.fjob)))
    end
    brain.rearm_try.n = brain.rearm_try.n + 1
    brain.rearm_try.next = now + (cfg.arisen_brain_skill_hold or 0.5) + 0.7
    brain.wj_next = 0
    return true
end
brain.rearm_ok, brain.rearm_fail = 0, 0
function brain.slot_ok(slot, now)
    local id = brain.skills[slot] or 0
    if id <= 0 or brain.NEVER[id] then return false end
    if brain.job == 10 and brain.skill_job(id) ~= brain.fjob then return false end
    if brain.style == "caster" then return brain.caster_ok(slot, now) end
    if id == 86 and cfg.arisen_brain_ma ~= false then return brain.ma_vim_ok() end
    return true
end
-- May the rotation press this slot now? Attack spells always; buffs when not cast in the last arisen_brain_buff_every s.
function brain.caster_ok(slot, now)
    local c = brain.SPELL[brain.skills[slot] or 0]
    if c == "attack" then return true end
    if c == "buff" then return now - (brain.buff_t[slot] or -1e9) > (cfg.arisen_brain_buff_every or 75.0) end
    return false
end
-- A buff that is due goes before the attack rotation ("buffs early"): returns its slot.
function brain.caster_buff(now)
    for slot = 1, 6 do
        if brain.SPELL[brain.skills[slot] or 0] == "buff" and brain.caster_ok(slot, now) then return slot end
    end
end
-- Who needs what (2 Hz). v0.9.64: heal (below threshold; the possessed pawn from a higher one), top-up (no enemy:
-- anyone below arisen_brain_topup), help (the Help order: the possessed pawn, whatever his health), cure (someone has
-- a debilitation and the cure spell, id 35, is equipped). Result in brain.heal_who = { chara, who, frac, me, kind }.
brain.BAD_STATUS = (1 << 1) | (1 << 2) | (1 << 7) | (1 << 8) | (1 << 9) | (1 << 10) | (1 << 11) | (1 << 12) | (1 << 23)
function brain.caster_hurt(ar, now, topup, can_cure)
    if now < (brain.hurt_next or 0) then return end
    brain.hurt_next = now + 0.5
    brain.heal_who = nil
    local best, sick
    local pa = state.pawn_chara and state.pawn_chara:get_address()
    local help = now < (brain.help_until or 0)
    local function look(chara, who, thr)
        pcall(function()
            local hit = chara:call("get_Hit")
            local hp = hit:call("get_Hp") or 0
            local mx = hit:call("get_ReducedMaxHp")
            if type(mx) ~= "number" or mx <= 0 then mx = hit:call("get_OriginalMaxHp") or 0 end
            if hp <= 0 or mx <= 0 then return end
            local fr = hp / mx
            local me = (who == "himself")
            if help and pa and chara:get_address() == pa then
                best = -10.0
                brain.heal_who = { chara = chara, who = who, frac = fr, me = me, kind = "help" }
            elseif fr < thr and (not best or fr - thr < best) then
                best = fr - thr
                brain.heal_who = { chara = chara, who = who, frac = fr, me = me, kind = topup and "top-up" or "heal" }
            end
            if can_cure and not sick then
                local sc = chara:call("get_StatusConditionCtrl")
                local fl = sc and sc:call("get_ActiveStatusConditionFlagProp")
                if type(fl) == "number" and (fl & brain.BAD_STATUS) ~= 0 then
                    sick = { chara = chara, who = who, frac = fr, me = me, kind = "cure", flags = fl }
                end
            end
        end)
    end
    local t_p, t_o = cfg.arisen_brain_heal_pawn or 0.65, cfg.arisen_brain_heal_other or 0.5
    if topup then t_p = cfg.arisen_brain_topup or 0.85; t_o = t_p end
    look(ar, "himself", t_o)
    for _, e in ipairs(get_party()) do
        look(e.chara, tostring(e.name), (pa and e.chara:get_address() == pa) and t_p or t_o)
    end
    if not brain.heal_who and sick and now >= (brain.cure_next or 0) then brain.heal_who = sick end
end
-- The whole healing step, with or without an enemy. Returns handled, stick x, stick y, magnitude, buttons.
function brain.caster_heal(ar, now, ax, az, stay, topup, casting)
    if not (brain.style == "caster" and cfg.arisen_brain_heal) or casting or now < brain.skill_until
       or now < (brain.heal_hold_until or 0) then return false end
    local help = now < (brain.help_until or 0)
    if not help and now < (brain.heal_next or 0) then return false end
    if topup and not help and not cfg.arisen_brain_topup_on then return false end
    local hslot, cslot
    for k = 1, 6 do
        local c = brain.SPELL[brain.skills[k] or 0]
        if c == "heal" and not hslot then hslot = k end
        if c == "cure" and not cslot then cslot = k end
    end
    if not (hslot or cslot or brain.fjob == 3) then return false end
    brain.caster_hurt(ar, now, topup, cslot ~= nil and cfg.arisen_brain_cure)
    local h = brain.heal_who
    if not h then return false end
    if h.kind ~= "cure" and not (hslot or brain.fjob == 3) then return false end
    local hx, _, hz = brain_pos(h.chara)
    local hd = (h.me or not hx) and 0.0 or math.sqrt((hx - ax) ^ 2 + (hz - az) ^ 2)
    if hd > (cfg.arisen_brain_heal_reach or 2.5) and not stay then
        brain.mode = h.kind .. " (going to " .. h.who .. ")"
        local sx, sy = brain_stick_for(math.atan(hx - ax, hz - az))
        return true, sx, sy, 1.0, (hd > 8.0) and brain_flag("Dash") or 0
    end
    local want
    brain.hurt_next = 0
    brain.help_until = nil
    local slot = (h.kind == "cure") and cslot or hslot
    if h.kind == "cure" then brain.cure_next = now + (cfg.arisen_brain_cure_cd or 12.0)
    else brain.heal_next = now + (cfg.arisen_brain_heal_cd or 10.0) end
    if slot then
        brain.skill_slot = slot
        brain.skill_bits = brain_flag("Skill" .. slot) | brain_flag("Shift1") | brain_flag("Shift2")
        brain.skill_until = now + (cfg.arisen_brain_skill_hold or 0.5)
        want = brain.skill_bits
    else
        brain.heal_hold_until = now + (cfg.arisen_brain_anodyne_hold or 3.5)
        want = brain_flag("AttackL")
    end
    brain.skill_uses = brain.skill_uses + 1
    brain_event(string.format("%s for %s at %.0f%% health (%s)%s", h.kind, h.who, h.frac * 100,
        slot and ("slot " .. slot) or "Anodyne", h.flags and string.format(" status 0x%X", h.flags) or ""))
    return true, 0.0, 0.0, 0.0, want
end
-- True while the brain owns the Arisen's input this frame (read by the pip / sequence-buffer / redirect hooks).
local function brain_active()
    return brain.on
end

-- v0.9.18: is the party in a fight? The game's own answers: BattleManager.IsBattleMode, or any party pawn's
-- Pawn.isBattle(). Checked 4x a second, held 2 s after it ends. The tester: the Arisen shot at (probably) wildlife
-- just because something targetable was in range.
function brain.in_battle()
    local now = os.clock()
    if now < (brain.battle_next or 0) then return brain.battle_state end
    brain.battle_next = now + 0.25
    local on, why = false, nil
    pcall(function()
        local bm = sdk.get_managed_singleton("app.BattleManager")
        if bm and bm:call("get_IsBattleMode") == true then on, why = true, "battle mode" end
    end)
    if not on then
        for _, e in ipairs(get_party()) do
            local ok, b = pcall(function() return e.pawn and e.pawn:call("isBattle") end)
            if ok and b == true then on, why = true, "pawn in battle"; break end
        end
    end
    if on then brain.battle_until = now + 2.0 end
    local state_now = on or now < (brain.battle_until or 0)
    if state_now ~= brain.battle_state then brain_event(state_now and ("battle: " .. tostring(why)) or "battle over -> stand down") end
    brain.battle_state, brain.battle_why = state_now, why
    return state_now
end

local function brain_pick(ax, az, px, pz)
    local r = cfg.arisen_brain_engage_r or 30.0
    if cfg.arisen_brain_battle_only and not robot.arisen and not brain.in_battle() then return nil end
    if brain.target and brain_alive(brain.target) then
        local tx, _, tz = brain_pos(brain.target)
        if tx and math.sqrt((tx - ax) ^ 2 + (tz - az) ^ 2) <= r * 1.2 then return brain.target end
    end
    local em = sdk.get_managed_singleton("app.EnemyManager")
    local arr = em and call(em, "getAllEnemies")
    if not arr then return nil end
    local best, bd = nil, nil
    local n = call(arr, "get_Count") or 0
    for i = 0, n - 1 do
        local ok, e = pcall(function() return arr[i]:get_field("_Chara") end)
        if ok and e and brain_alive(e) then
            local ex, _, ez = brain_pos(e)
            if ex then
                local d = math.sqrt((ex - ax) ^ 2 + (ez - az) ^ 2)
                -- stay with the party: the enemy must also be near the possessed pawn (when there is one)
                local dp = px and math.sqrt((ex - px) ^ 2 + (ez - pz) ^ 2) or 0
                if d <= r and dp <= r * 1.5 and (not bd or d < bd) then best, bd = e, d end
            end
        end
    end
    if best and not same_obj(best, brain.target) then
        brain_event(string.format("target %s %.1fm", tostring(call(best, "get_CharaIDString")), bd))
    end
    return best
end

-- Decide this frame's synthetic input. Runs in pre-UpdateBehavior (DPC main tick); the pip hook applies it.
-- v0.9.60 (telemetry only): while the Arisen is a caster, log every change of his action nodes (both layers) and of
-- any party pawn of the same vocation, to learn the incantation sequence from a pawn that casts properly.
brain.watch_log, brain.watch_last = {}, {}
function brain.watch(ar, now)
    if not cfg.arisen_brain_telemetry or now < (brain.watch_next or 0) then return end
    brain.watch_next = now + 0.1
    if not brain.watch_list or now >= (brain.watch_refresh or 0) then
        brain.watch_refresh = now + 5.0
        local l = { { who = "ARISEN", chara = ar } }
        for _, e in ipairs(get_party()) do
            if e.job == brain.job then l[#l + 1] = { who = tostring(e.name), chara = e.chara } end
        end
        brain.watch_list = l
    end
    for _, w in ipairs(brain.watch_list) do
        pcall(function()
            local fsm = w.chara:call("get_ActionManager"):get_field("Fsm")
            local n = tostring(fsm:call("getCurrentNodeName(System.UInt32)", 0)) .. " | " .. tostring(fsm:call("getCurrentNodeName(System.UInt32)", 1))
            if brain.watch_last[w.who] ~= n then
                brain.watch_last[w.who] = n
                local lg = brain.watch_log
                lg[#lg + 1] = string.format("%.2f %s: %s", now, w.who, n)
                if #lg > 160 then table.remove(lg, 1) end
            end
        end)
    end
end

local function brain_tick()
    local was_on = brain.on
    brain.on = false
    local rb = robot.arisen
    if rb and os.clock() >= rb.until_t then robot.arisen = nil; rb = nil end
    -- 0.9.171: co-op, player 2 on the Arisen: his input is player 2's controller (R.ar2_tick), the camera stays
    -- player 1's (this path leaves his right stick alone)
    if not rb and R.ar2_src and os.clock() < (R.ar2_src.until_t or 0) then rb = R.ar2_src end
    if not rb then
        if not cfg.arisen_brain then brain.mode = "off"; return end
        if not (state.active or brain.solo) then brain.mode = "off"; return end
        if coop.active then brain.mode = "off (co-op)"; return end
    end
    -- v0.8.8: no brain while the possessed pawn runs on DPC's puppeteer (Thief, or native controls failed).
    -- Two crashes ([time] and [time], both ~7 s after possessing the hired Thief pawn with the brain on, worker AV in
    -- via.vec3.op_Subtraction DD2.exe+0x524aa97/+0x524aa9d); the v0.8.7 lock-swap skip did not prevent the second.
    -- Native-controlled pawns with the brain on ran clean.
    -- v0.8.10: the flag is refreshed by the pawn mirror; during the first frames of a possession it can be stale
    -- (the [time] the hired Thief pawn crash followed 25 brain frames, lock swaps included, right at the main pawn -> the hired Thief pawn switch).
    -- Wait 60 frames after any possession starts before the brain may run.
    if state.active and (state.frames_since_start or 0) < 60 then
        brain.mode = "waiting (possession just started)"
        return
    end
    if state.active and not brain.pawn_native and not cfg.arisen_brain_puppeteer then
        if was_on then brain_event("OFF: possessed pawn runs on the puppeteer") end
        brain.mode = "off (pawn on puppeteer)"
        return
    end
    local cm = sdk.get_managed_singleton("app.CharacterManager")
    local ar = cm and call(cm, "get_ManualPlayer")
    if not ar then return end
    local now = os.clock()
    if not same_obj(ar, brain.ar) or now >= brain.next_job_t then
        brain.ar = ar
        brain.ar_human = call(ar, "get_Human")
        brain.ar_input = call(ar, "get_Input")
        local pip = call(ar, "get_InputProcessor")
        brain.pip_addr = addr_of(pip)
        brain.job = get_job(brain.ar_human, ar)          -- raw (in_internal_query bypasses the HUD redirect)
        if brain.job ~= 10 or brain.fjob < 1 or brain.fjob > 9 then brain.fjob = brain.job end -- v0.9.146: a Warfarer keeps the weapon job he was found with (this block runs every 2 s)
        -- v0.9.72: this block runs every 2 s (skill refresh). Clearing the simulacrum state here made him forget
        -- it was out and press the toggle again: out, back, out, back through the whole fight. Only a change of
        -- vocation clears it now.
        if brain.decoy_job ~= brain.job then brain.decoy, brain.decoy_job = {}, brain.job end
        brain.style = brain.style_for(brain.fjob)
        brain.wj_next = 0
        brain.lock = nil
        pcall(function()
            local pl = ar:get_GameObject():call("getComponent(System.Type)", sdk.typeof("app.Player"))
            brain.lock = pl and pl:call("get_LockOnCtrl")
        end)
        local sk = get_skills(brain.ar_human, brain.job)
        brain.skills = { sk[1], sk[2], sk[3], sk[4], sk[5], sk[6] } -- v0.9.55: all six weapon skill slots (5 / 6 = the Skill5 / Skill6 flags)
        brain.next_job_t = now + 2.0
    end
    if not rb and not brain_job_ok(brain.job) then brain.mode = "job " .. tostring(brain.job) .. " (not handled)"; return end
    if brain.pip_addr == 0 or not brain.ar_input then brain.mode = "no input processor"; return end
    if call(ar, "get_IsDead") then brain.mode = "dead"; return end
    brain.on = true
    if not was_on then
        brain_event("ON (job " .. tostring(brain.job) .. ")")
        brain.prev, brain.next_skill = 0, now + 2.0
    end

    if rb then
        -- scripted input: no target, no lock-on, no rules
        brain.mode = rb.label or "robot"
        brain.target, brain.lock_work = nil, nil
        local sx, sy, mag = rb.sx or 0.0, rb.sy or 0.0, rb.mag or 0.0
        if rb.yaw then sx, sy = brain_stick_for(rb.yaw); mag = rb.mag or 1.0 end
        brain.want, brain.ax, brain.ay, brain.mag = rb.want or 0, (sx * mag) + 0.0, (sy * mag) + 0.0, mag + 0.0
        return
    end
    local ax, _, az = brain_pos(ar)
    if not ax then return end
    local pawn = state.active and state.pawn_chara or nil
    local px, _, pz = nil, nil, nil
    if pawn then px, _, pz = brain_pos(pawn) end

    if now >= brain.next_scan then
        brain.next_scan = now + 0.3
        brain.target = brain_pick(ax, az, px, pz)
        brain.target_id = brain.target and tostring(call(brain.target, "get_CharaIDString")) or "-"
        brain.lock_work = nil
        if brain.target then
            pcall(function() brain.lock_work = brain.target:call("get_LockOnTarget"):call("get_work") end)
        end
    end

    -- line-of-sight flags from the lock-on system's own wall rays (telemetry even when the feature is off)
    brain.los = nil
    if brain.lock_work then
        pcall(function()
            local w = brain.lock_work
            -- auto-properties: the fields are <isWall>k__BackingField etc., so use the getters (0.9.8)
            brain.los = { wall = w:call("get_isWall"), pl = w:call("get_isWallPL"), cam = w:call("get_isWallCam"),
                          casted = w:get_field("IsRayCasted"), valid = w:call("get_isValid") }
        end)
    end
    local los_blocked = false
    if brain.los then   -- IsRayCasted is only true on the frames a ray lands; the flags hold the last result
        los_blocked = brain.los[({ isWallPL = "pl", isWall = "wall", isWallCam = "cam" })[cfg.arisen_brain_los_field] or "pl"] == true
    end
    if los_blocked then brain.los_since = brain.los_since or now else brain.los_since = nil end
    brain.los_blocked = los_blocked

    -- v0.9.65 Warfarer: follow the weapon in his hands (checked once a second)
    if brain.job == 10 and now >= (brain.wj_next or 0) then
        brain.wj_next = now + 1.0
        local okw, w = pcall(ar.call, ar, "getWeaponJob()")
        if not okw then okw, w = pcall(ar.call, ar, "calcWeaponJob") end
        if okw and type(w) == "number" and w >= 1 and w <= 9 and w ~= brain.fjob then
            brain.fjob = w
            brain.style = brain.style_for(w)
            brain_event(string.format("Warfarer: weapon of job %d -> %s rules", w, brain.style))
        end
    end
    if brain.job == 3 or brain.job == 6 or brain.job >= 8 then brain.watch(ar, now) end
    -- v0.9.67 Trickster: is the simulacrum out? Known only from his own actions: a summon action sets it, an
    -- unsummon action clears it (then he summons again); after 60 s without either it counts as unknown and he
    -- taps once (if that took it back, the next tap brings it out again).
    if brain.fjob == 9 then
        local d = brain.decoy
        pcall(function()
            local fsm = ar:call("get_ActionManager"):get_field("Fsm")
            local n = tostring(fsm:call("getCurrentNodeName(System.UInt32)", 0)) .. tostring(fsm:call("getCurrentNodeName(System.UInt32)", 1))
            local su, un = n:find("SummonDecoy", 1, true) ~= nil and n:find("Unsummon", 1, true) == nil, n:find("Unsummon", 1, true) ~= nil
            if su and not d.in_su then d.out, d.t = true, now; brain_event("Trickster: simulacrum out") end
            if un and not d.in_un then d.out, d.t = false, now; d.next = now + 1.5; brain_event("Trickster: simulacrum taken back") end
            d.in_su, d.in_un = su, un
        end)
        if d.out and now - (d.t or now) > 60.0 then d.out = false end
    end

    local want, sx, sy, mag = 0, 0.0, 0.0, 0.0
    local stay = state.arisen_stay
    local t = brain.target
    local tx, _, tz = nil, nil, nil
    if t then tx, _, tz = brain_pos(t) end
    brain.target_hp = t and call(t, "get_Hp") or nil
    -- progress tracking: arrows that hit terrain/walls do nothing, so a pawn-like archer moves for a clear shot
    if not same_obj(t, brain.prog_target) or (brain.target_hp or 0) < (brain.prog_hp or 0) - 0.5 then
        brain.prog_target, brain.prog_hp, brain.prog_t = t, brain.target_hp, now
    end
    if t and tx then
        local dx, dz = tx - ax, tz - az
        local d = math.sqrt(dx * dx + dz * dz)
        local yaw = math.atan(dx, dz)
        brain.dist = d
        brain.off = math.deg(brain_angdiff(yaw, brain_facing(ar)))
        local kmin, kmax = cfg.arisen_brain_keep_min or 7.0, cfg.arisen_brain_keep_max or 20.0
        if brain.style == "caster" then kmin = math.min(kmin, cfg.arisen_brain_caster_keep_min or 4.0) end
        if brain.fjob == 9 then kmin, kmax = 3.0, 9.0 end -- v0.9.65 Trickster: his censer smoke is short-ranged -- v0.9.62: he spent fights backing off instead of casting
        local turn_since = brain.turn_since; brain.turn_since = nil   -- kept only while the turn branch runs
        -- v0.9.59 caster style (Mage, Sorcerer): the ranged rules, plus: while he is incanting (his action is in a
        -- custom-skill node) he stands still and sends nothing that would break the spell, and holds Quickspell
        -- (the job's special action) while he has stamina to spare. Spells are pressed 2.5 s apart, not 7.
        local casting = false
        if brain.style == "caster" then
            pcall(function()
                local fsm = ar:call("get_ActionManager"):get_field("Fsm")
                local n0 = tostring(fsm:call("getCurrentNodeName(System.UInt32)", 0))
                casting = n0:find("SkillAttack", 1, true) ~= nil or n0:find("_CS%d") ~= nil
                if not casting then -- v0.9.60: spells he can walk with sit on the upper-body layer
                    local n1 = tostring(fsm:call("getCurrentNodeName(System.UInt32)", 1))
                    if n1:find("SkillAttack", 1, true) ~= nil or n1:find("_CS%d") ~= nil then casting, n0 = true, n1 end
                end
                if casting and brain.cast_node ~= n0 then
                    brain.cast_node = n0
                    brain_event("casting: " .. n0)
                end
            end)
            if not casting then brain.cast_node = nil end
        end
        -- v0.9.62 / 0.9.64 healing: see brain.caster_heal. Heals work around the caster, so he walks to the hurt one.
        local healing = false
        do
            local hh, hsx, hsy, hmag, hwant = brain.caster_heal(ar, now, ax, az, stay, false, casting)
            if hh then healing, sx, sy, mag, want = true, hsx, hsy, hmag, want | hwant end
        end
        if now < (brain.heal_hold_until or 0) then
            brain.mode = "heal (Anodyne)"
            brain.prog_t = now
            want = brain_flag("AttackL")
        elseif healing then
            brain.prog_t = now
        elseif brain.style == "caster" and now < brain.skill_until then
            -- v0.9.64: the press of a heal / cure spell must not be lost to the back-off or approach rules below
            brain.mode = "skill " .. brain.skill_slot
            want = brain.skill_bits
        elseif casting and now >= brain.skill_until then
            brain.mode = "cast"
            brain.prog_t = now
            brain.next_skill = math.max(brain.next_skill or 0, now + (cfg.arisen_brain_cast_gap or 4.0))
            brain.no_shot_until = math.max(brain.no_shot_until or 0, now + 0.6)
            -- v0.9.61: only during the incantation itself (node "...Prepare<Spell>"). Held through Cast / End it
            -- carried into the next free frame and raised his magick barrier for a second after every spell.
            if cfg.arisen_brain_quickspell and tostring(brain.cast_node):find("Prepare", 1, true) then
                local okq, fr = pcall(function()
                    local sm = ar:call("get_StaminaManager")
                    return sm:call("get_RemainingAmount") / math.max(1.0, sm:call("get_MaxValue"))
                end)
                -- hysteresis: start above 45 %, stop below 20 %
                if okq and type(fr) == "number" then
                    if fr > 0.45 then brain.qs = true elseif fr < 0.20 then brain.qs = false end
                    if brain.qs then want = brain_flag("JobSpecialAction") end
                end
            end
        elseif brain.style == "melee" then
            local reach = (cfg.arisen_brain_melee_reach or 2.3) + ((brain.fjob == 5) and 0.4 or 0.0)
            -- a big target's body stops him short of its centre: no progress while close counts as "in reach"
            local in_reach = d <= reach or (now < (brain.contact_until or 0) and d <= (brain.contact_d or 0))
            if not in_reach then
                if stay then
                    brain.mode = "wait (out of reach)"
                else
                    brain.mode = "approach"; sx, sy = brain_stick_for(yaw); mag = 1.0
                    if d > (cfg.arisen_brain_melee_dash or 7.0) then want = want | brain_flag("Dash") end
                    -- v0.9.52: only while he is free to move. In the first real fight (Warrior) this fired at 3.3 -
                    -- 7.5 m from goblins: he was standing in an attack's recovery, not pressed against anything,
                    -- and then swung at air for 3 s. Samples taken outside locomotion restart the window, and the
                    -- rule only applies within reach + 2.5 m.
                    local c = brain.contact or {}
                    brain.contact = c
                    local free = false
                    pcall(function()
                        local fsm = ar:call("get_ActionManager"):get_field("Fsm")
                        free = tostring(fsm:call("getCurrentNodeName(System.UInt32)", 0)):find("Locomotion", 1, true) ~= nil
                    end)
                    if not free then c.t0 = nil end
                    if free and not c.t0 then c.t0, c.x0, c.z0 = now, ax, az end
                    if free and now - c.t0 >= 0.5 then
                        local moved = math.sqrt((ax - c.x0) ^ 2 + (az - c.z0) ^ 2)
                        if moved < 0.35 and d < reach + 2.5 then
                            brain.contact_until, brain.contact_d = now + 3.0, d + 0.6
                            brain_event(string.format("blocked %.1f m from %s -> attacking from here", d, brain.target_id))
                        end
                        c.t0, c.x0, c.z0 = now, ax, az
                    end
                end
            else
                if brain.contact then brain.contact.t0 = nil end
                if now < brain.skill_until then
                    brain.mode = "skill " .. brain.skill_slot
                    want = brain.skill_bits
                elseif math.abs(brain.off) > (cfg.arisen_brain_melee_face_tol or 25.0) then
                    brain.mode = "turn"; sx, sy = brain_stick_for(yaw); mag = cfg.arisen_brain_turn_mag or 0.15
                    pcall(ar.call, ar, "set_TargetFrontAngleDeg(System.Single)", math.deg(yaw) + 0.0)
                else
                    brain.mode = "engage"
                    -- lean on the stick toward him so the attacks step in and track
                    sx, sy = brain_stick_for(yaw); mag = (d > reach * 0.7) and 0.5 or 0.2
                    if cfg.arisen_brain_skills and now >= brain.next_skill then
                        for k = 1, 6 do
                            local slot = (brain.skill_slot % 6) + 1
                            brain.skill_slot = slot
                            if (brain.skills[slot] or 0) > 0 and now >= ((brain.skill_block or {})[slot] or 0) and brain.slot_ok(slot, now) then
                                brain.skill_bits = brain_flag("Skill" .. slot) | brain_flag("Shift1") | brain_flag("Shift2")
                                brain.skill_until = now + (cfg.arisen_brain_skill_hold or 0.5)
                                brain.next_skill = now + (cfg.arisen_brain_melee_skill_cd or 6.0)
                                brain.no_shot_until = brain.skill_until + 0.6
                                brain.skill_uses = brain.skill_uses + 1
                                brain_event(string.format("skill slot %d (id %d)", slot, brain.skills[slot]))
                                want = brain.skill_bits
                                break
                            end
                        end
                    end
                    if want == 0 and now >= brain.no_shot_until then
                        local cd = (cfg.arisen_brain_melee_cd or 0.42) * ((brain.fjob == 5) and 1.9 or 1.0)
                        if (now % cd) < 0.1 then
                            -- every fifth press is the heavy attack
                            want = (math.floor(now / cd) % 5 == 4) and brain_flag("AttackL") or brain_flag("AttackS")
                        end
                    end
                end
            end
        elseif not stay and d > kmax then
            brain.mode = "approach"; sx, sy = brain_stick_for(yaw); mag = 1.0
        elseif not stay and d < kmin and now >= (brain.no_backoff_until or 0) then
            brain.mode = "backoff"; sx, sy = brain_stick_for(yaw + math.pi); mag = 1.0
            -- v0.9.62: a caster keeps throwing magick bolts while he backs away (they can be cast on the move)
            if brain.style == "caster" and (now % (cfg.arisen_brain_shot_cd or 0.9)) < (cfg.arisen_brain_shot_hold or 0.12) then want = brain_flag("AttackS") end
        elseif cfg.arisen_brain_los and not stay and brain.los_since
               and now - brain.los_since > (cfg.arisen_brain_los_delay or 0.4) and now >= brain.skill_until then
            -- no line of sight: no shots, flank toward the target; swap sides if it stays blocked
            if not brain.los_flank_t or now - brain.los_flank_t > (cfg.arisen_brain_los_swap or 2.5) then
                if brain.los_flank_t then brain.los_side = -(brain.los_side or 1) end
                brain.los_flank_t = now
                brain_event(string.format("no line of sight to %s -> flank %s", brain.target_id, (brain.los_side or 1) > 0 and "right" or "left"))
            end
            brain.mode = "no line of sight"
            -- far away: mostly toward him; close: mostly sideways
            local ang = math.rad(cfg.arisen_brain_los_angle or 50.0) * ((d < kmin + 3.0) and 1.7 or 1.0)
            sx, sy = brain_stick_for(yaw + (brain.los_side or 1) * ang); mag = 1.0
            brain.prog_t = now          -- don't also trigger the "no damage" sidestep
        elseif now < (brain.repos_until or 0) then
            brain.mode = "reposition"
            sx, sy = brain_stick_for(yaw + (brain.repos_side or 1) * math.rad(65)); mag = 1.0
        elseif brain.fjob == 8 and brain.ma_try_remedy(now, ar, ax, az) then
            brain.mode = "revive (Remedy Arrow)"
            want = brain.ma_want
            if brain.ma then brain.ma.phase, brain.ma.until_t = "rest", now + 0.5 end
        elseif now < brain.skill_until then
            brain.mode = "skill " .. brain.skill_slot
            want = brain.skill_bits
        elseif math.abs(brain.off) > (cfg.arisen_brain_face_tol or 6.0) then
            -- the small stick push alone sits inside the dead zone; TargetFrontAngleDeg is what turns him
            -- (verified 2026-11-10: 98 deg off stayed 98 deg for 12 s with the stick alone)
            brain.mode = "turn"; sx, sy = brain_stick_for(yaw); mag = cfg.arisen_brain_turn_mag or 0.15
            pcall(ar.call, ar, "set_TargetFrontAngleDeg(System.Single)", math.deg(yaw) + 0.0)
            -- watchdog (0.9.10): brain-los-1e sat in "turn" for 23 s without firing. If the turn hasn't finished
            -- after 1.5 s, take a half-second step toward the target at full stick, which turns him by moving.
            brain.turn_since = turn_since or now
            local stuck = now - brain.turn_since
            if not stay and stuck > 1.5 then
                brain.mode = "turn (step)"; mag = 1.0
                if stuck > 2.0 then
                    brain_event(string.format("turn stuck at %.0f deg off -> stepped toward the target", brain.off or 0))
                    brain.turn_since = now
                end
            end
        elseif not stay and (cfg.arisen_brain_stuck_s or 0) > 0 and now - (brain.prog_t or now) > cfg.arisen_brain_stuck_s then
            -- engaged this long without hurting the target: sidestep (alternating sides) for a clear line of fire
            brain.repos_side = -(brain.repos_side or 1)
            brain.repos_until = now + 1.5
            brain.prog_t = now + 1.5
            brain_event(string.format("no damage for %.0fs -> reposition %s", cfg.arisen_brain_stuck_s, brain.repos_side > 0 and "right" or "left"))
            brain.mode = "reposition"
            sx, sy = brain_stick_for(yaw + brain.repos_side * math.rad(65)); mag = 1.0
        else
            brain.mode = "engage"
            -- skill: next equipped core slot on its cooldown
            -- v0.9.104 Magick Archer: shots and skills WITHOUT aiming (the generic rules below: light-attack taps and
            -- shift + skill, which go to the lock-on target the brain sets). The 0.9.101 aim-and-release routine
            -- shot where the PLAYER's camera pointed (the aim reticle is the camera's), i.e. into the ground, and
            -- drew his reticle over the player's screen; it stays behind arisen_brain_ma_aim. Conversion still runs.
            local ma_w = nil
            if brain.fjob == 8 and cfg.arisen_brain_ma ~= false then
                if cfg.arisen_brain_ma_aim then ma_w = brain.ma_tick(now, ar) else ma_w = brain.ma_conv_tick(now, ar) end
            end
            if ma_w then
                want = ma_w
                brain.no_shot_until = now + 0.4
            elseif cfg.arisen_brain_skills and now >= brain.next_skill then
                if brain.style == "caster" then -- v0.9.62: a due buff goes first
                    local b = brain.caster_buff(now)
                    if b then brain.skill_slot = b - 1 end
                end
                for k = 1, 6 do
                    local slot = (brain.skill_slot % 6) + 1
                    brain.skill_slot = slot
                    if (brain.skills[slot] or 0) > 0 and now >= ((brain.skill_block or {})[slot] or 0)
                       and brain.slot_ok(slot, now) then
                        if brain.style == "caster" and brain.SPELL[brain.skills[slot]] == "buff" then brain.buff_t[slot] = now end
                        brain.skill_bits = brain_flag("Skill" .. slot) | brain_flag("Shift1") | brain_flag("Shift2")
                        brain.skill_until = now + (cfg.arisen_brain_skill_hold or 0.5)
                        if brain.fjob == 8 and brain.skills[slot] == 83 and (cfg.arisen_brain_ma_charge_s or 0) > 0 then
                            brain.skill_until = now + cfg.arisen_brain_ma_charge_s -- v0.9.117: Hailstone Bolt charges while held
                        end
                        brain.next_skill = now + (cfg.arisen_brain_skill_cd or 7.0)
                        brain.no_shot_until = brain.skill_until + 0.8
                        brain.skill_uses = brain.skill_uses + 1
                        local ma_note = ""
                        if brain.fjob == 8 and (cfg.arisen_brain_ma_skill_gap or 0) > 0 then
                            -- v0.9.116: see brain.ma_cadence (the wait is set from the skill's own end, not a flat 7 s)
                            local st = brain.ma_stamina(ar)
                            if st and st < (cfg.arisen_brain_ma_stamina or 0.2) then
                                -- too tired for a skill: plain shots for a second, same slot again afterwards
                                brain.skill_slot = slot - 1
                                brain.skill_uses = brain.skill_uses - 1
                                brain.next_skill, brain.skill_until, brain.no_shot_until = now + 1.0, 0, 0
                                if now >= (brain.ma_tired_log or 0) then
                                    brain.ma_tired_log = now + 10.0
                                    brain_event(string.format("stamina %.0f%% -> plain shots until it is back", st * 100))
                                end
                                break
                            end
                            brain.next_skill = math.max(now + 3.0, brain.skill_until + 1.0)
                            brain.ma_press = { t = now, slot = slot, started = false }
                            ma_note = st and string.format(", stamina %.0f%%", st * 100) or ""
                        end
                        brain_event(string.format("skill slot %d (id %d)%s", slot, brain.skills[slot], ma_note))
                        want = brain.skill_bits
                        break
                    end
                end
            end
            if want == 0 and now >= brain.no_shot_until and brain.fjob == 9 then
                -- v0.9.67 Trickster, from the tester's own demonstration (DPC_demo.json, 2026-11-15): a tap of the
                -- heavy attack summons the simulacrum (Job09_SummonDecoy) and a second tap takes it back
                -- (Job09_UnsummonUpperBody); a tap of the light attack is the censer swing (Short/MoveSmokeAttack);
                -- the light attack held about 1.1 s and released throws the smoke (PrepareMoveThrowSmoke ->
                -- ThrowSmoke). So: simulacrum first, then a throw every 6 s with swings in between.
                local d = brain.decoy
                if not d.out and now >= (d.next or 0) then
                    d.next = now + 2.5
                    d.press_until = now + 0.15
                    brain_event("Trickster: summon the simulacrum")
                end
                if now < (d.press_until or 0) then
                    want = brain_flag("AttackL")
                elseif d.out then
                    local ph = now % 6.0
                    if ph < 1.3 then want = brain_flag("AttackS")              -- hold, then release = throw
                    elseif ph > 1.8 and (now % 1.1) < 0.12 then want = brain_flag("AttackS") end
                end
            elseif want == 0 and now >= brain.no_shot_until then
                local cd = cfg.arisen_brain_shot_cd or 0.9
                if (now % cd) < (cfg.arisen_brain_shot_hold or 0.12) then want = brain_flag("AttackS") end
            end
        end
        if brain.mode ~= "no line of sight" then brain.los_flank_t = nil end
        brain.following = false
    else
        brain.target = nil
        brain.mode = stay and "wait" or "idle"
        -- v0.9.64 no enemy: a caster tops the party up, answers the Help order and cures debilitations
        local tending = false
        if brain.fjob == 8 and brain.ma_try_remedy(now, ar, ax, az) then
            tending = true; brain.mode = "revive (Remedy Arrow)"; want = brain.ma_want
        end
        if brain.style == "caster" then
            if now < (brain.heal_hold_until or 0) then
                tending = true; brain.mode = "heal (Anodyne)"; want = brain_flag("AttackL")
            elseif now < brain.skill_until then
                tending = true; brain.mode = "skill " .. brain.skill_slot; want = brain.skill_bits
            else
                local hh, hsx, hsy, hmag, hwant = brain.caster_heal(ar, now, ax, az, stay, true, false)
                if hh then tending, sx, sy, mag, want = true, hsx, hsy, hmag, want | hwant end
            end
        end
        -- follow the possessed pawn (pawn-style), with hysteresis
        if tending then
            brain.following = false
        elseif pawn and px and not stay and cfg.arisen_brain_follow then
            local dx, dz = px - ax, pz - az
            local d = math.sqrt(dx * dx + dz * dz)
            local fd = cfg.arisen_follow_dist or 7.0
            if d > fd or (brain.following and d > fd - 2.0) then
                brain.following = true
                brain.mode = "follow"
                sx, sy = brain_stick_for(math.atan(dx, dz))
                mag = 1.0
                if d > 14.0 then want = want | brain_flag("Dash") end
            else
                brain.following = false
            end
        end
    end
    -- Unstick (0.9.11): any full-stick move is checked for progress. The tester: backing off into a wall, he kept
    -- running at it. No progress for 0.6 s -> steer 70 deg to one side for 1.2 s; still stuck -> the other side,
    -- wider. Three failures in a row while backing off -> stand and fight for 4 s instead.
    if mag >= 0.9 then
        local u = brain.unstick or { n = 0, side = 1 }
        brain.unstick = u
        if u.mode ~= brain.mode then u.n = 0 end
        u.mode = brain.mode
        -- v0.9.53: only while he is free to move. In the Warrior fights this fired during attack recoveries
        -- (5 times in 30 s) and sent him sideways for 1.2 s each time when the way was clear.
        local free_u = true
        pcall(function()
            local fsm = ar:call("get_ActionManager"):get_field("Fsm")
            free_u = tostring(fsm:call("getCurrentNodeName(System.UInt32)", 0)):find("Locomotion", 1, true) ~= nil
        end)
        -- v0.9.54: and only while game time runs. With the game window unfocused the simulation stands still but
        -- this tick does not, and it logged "stuck while follow (moved 0.0 m)" every 0.6 s, flushing the fight's
        -- events. His animation frame not advancing between two ticks = frozen.
        pcall(function()
            local mo = ar:get_GameObject():call("getComponent(System.Type)", sdk.typeof("via.motion.Motion"))
            local fr = mo and mo:call("getLayer", 0):call("get_Frame")
            if fr ~= nil then
                if brain.last_frame ~= nil and fr == brain.last_frame then free_u = false end
                brain.last_frame = fr
            end
        end)
        if not free_u then u.t0 = nil end
        if free_u and not u.t0 then u.t0, u.x0, u.z0 = now, ax, az end
        if free_u and now - u.t0 >= 0.6 then
            local moved = math.sqrt((ax - u.x0) ^ 2 + (az - u.z0) ^ 2)
            if moved < 0.6 then
                u.n = u.n + 1
                u.side = -u.side
                u.ang = math.rad(math.min(70 + (u.n - 1) * 25, 150))
                u.until_t = now + 1.2
                brain_event(string.format("stuck while %s (moved %.1f m) -> steer %s %d deg", brain.mode, moved,
                    u.side > 0 and "right" or "left", math.floor(math.deg(u.ang))))
                if u.n >= 3 and brain.mode == "backoff" then
                    brain.no_backoff_until = now + 4.0
                    u.n = 0
                    brain_event("cornered -> stand and fight for 4 s")
                end
            elseif moved > 1.5 and not (u.until_t and now < u.until_t) then
                u.n = 0
            end
            u.t0, u.x0, u.z0 = now, ax, az
        end
        if u.until_t and now < u.until_t then
            local c, sn = math.cos(u.ang * u.side), math.sin(u.ang * u.side)
            sx, sy = sx * c - sy * sn, sx * sn + sy * c
            brain.mode = brain.mode .. " (unstick)"
        end
    elseif brain.unstick then
        brain.unstick.t0 = nil
    end
    -- v0.9.54 skill watchdog. The tester (Thief Arisen): he held Ensnare so long it looked like the whole fight. The
    -- timed attack presses keep a held / channelled skill going. If his action stays in a custom-skill node longer
    -- than arisen_brain_skill_max, send no attack or skill input for 1.5 s so it ends, and delay the next skill.
    local in_skill = false
    pcall(function()
        local fsm = ar:call("get_ActionManager"):get_field("Fsm")
        local n0 = tostring(fsm:call("getCurrentNodeName(System.UInt32)", 0))
        local n1 = tostring(fsm:call("getCurrentNodeName(System.UInt32)", 1))
        in_skill = n0:find("SkillAttack", 1, true) ~= nil or n0:find("_CS%d") ~= nil
            or n1:find("SkillAttack", 1, true) ~= nil or n1:find("_CS%d") ~= nil
        if in_skill then brain.skill_node = (n0:find("_CS%d") or n0:find("SkillAttack", 1, true)) and n0 or n1 end
    end)
    if in_skill then brain.skill_node_t = brain.skill_node_t or now else brain.skill_node_t, brain.letgo_n = nil, nil end
    if brain.fjob == 8 then
        brain.ma_cadence(now, in_skill)
        if now >= (brain.ma_hp_next or 0) then -- 2 Hz: the lowest health share in the party, for the Vimtaking Arrow rule
            brain.ma_hp_next = now + 0.5
            pcall(function()
                local function share(ch)
                    local hit = ch:call("get_Hit")
                    return (hit:call("get_Hp") or 0) / math.max(1.0, hit:call("get_ReducedMaxHp") or 1.0)
                end
                local low = share(ar)
                -- v0.9.118, reported: Vimtaking Arrow seems to heal the whole party: the pawns count too
                for _, e in ipairs(get_party()) do
                    local okp, v = pcall(share, e.chara)
                    if okp and v > 0 and v < low then low = v end
                end
                brain.ma_hp = low
            end)
        end
    end
    local smax = cfg.arisen_brain_skill_max or 4.0
    if brain.style == "caster" and smax > 0 then smax = cfg.arisen_brain_cast_max or 25.0 end -- v0.9.59: incantations are long
    -- v0.9.56: releasing the inputs is not enough for a stance that waits to be hit (Fighter skill 10,
    -- Job01_ShieldCounterStart: he stood in it for over two minutes, through 30+ "letting go" pauses and after the
    -- battle). Each try now also taps a button a player would break the stance with, a different one each time
    -- (jump, attack, guard, sheathe), from the third try also asks the action selector to end the action, retries
    -- every 2 s while it lasts, and keeps that skill slot out of the rotation for two minutes.
    local wait_s = brain.letgo_n and 2.0 or smax
    if smax > 0 and brain.skill_node_t and now - brain.skill_node_t > wait_s and now >= (brain.letgo_until or 0) then
        brain.letgo_n = (brain.letgo_n or 0) + 1
        local names = { "Jump", "AttackS", "JobSpecialAction", "Sheathe" }
        local nm = names[((brain.letgo_n - 1) % #names) + 1]
        brain.letgo_bits = brain_flag(nm)
        brain.letgo_tap_until = now + 0.15
        brain.letgo_until = now + 1.0
        brain.skill_node_t = now
        brain.next_skill = math.max(brain.next_skill or 0, now + 5.0)
        brain.skill_block = brain.skill_block or {}
        if brain.letgo_n == 1 and brain.skill_slot then brain.skill_block[brain.skill_slot] = now + 120.0 end
        if brain.letgo_n >= 3 then
            pcall(function() ar:call("get_HumanActionSelector"):call("requestEndAction") end)
        end
        if brain.letgo_n <= 6 or brain.letgo_n % 10 == 0 then
            brain_event(string.format("in %s for %.0f s -> letting go (try %d: %s)", tostring(brain.skill_node), now - (brain.skill_since or now), brain.letgo_n, nm))
        end
    end
    if in_skill then brain.skill_since = brain.skill_since or now else brain.skill_since = nil end
    if now < (brain.letgo_until or 0) then
        want = (now < (brain.letgo_tap_until or 0)) and (brain.letgo_bits or 0) or 0
        brain.mode = tostring(brain.mode) .. " (letting go)"
    end
    -- v0.9.145 Warfarer: every arisen_brain_rearm_every seconds of fighting he swaps to his next weapon
    if brain.job == 10 then
        local every = math.max(5, tonumber(cfg.arisen_brain_rearm_every) or 20)
        local ordering = brain.order_until and now < brain.order_until
        local tr = brain.rearm_try
        if tr then
            brain.wj_next = math.min(brain.wj_next or 0, now + 0.25) -- look at his weapon four times a second meanwhile
            if brain.fjob ~= tr.from then
                brain.rearm_ok = brain.rearm_ok + 1
                brain_event(string.format("Warfarer: swapped to the weapon of job %s after %d press(es), %.1f s", tostring(brain.fjob), tr.n, now - tr.t0))
                brain.rearm_try = nil
                brain.next_skill = math.max(brain.next_skill or 0, now + 1.5)
            elseif now >= tr.till then
                brain.rearm_fail = brain.rearm_fail + 1
                brain_event(string.format("Warfarer: Rearmament did not change his weapon (%d presses in %.0f s)", tr.n, now - tr.t0))
                brain.rearm_try = nil
            elseif not ordering and not in_skill and now >= (tr.next or 0) then
                brain.rearm(now, tr.why)
            end
        elseif cfg.arisen_brain_rearm == false or not brain.target then
            brain.rearm_next = now + every
        elseif now >= (brain.rearm_next or (now + every)) and not in_skill and now >= (brain.letgo_until or 0) and not ordering then
            brain.rearm(now, "timer")
        elseif not brain.rearm_next then
            brain.rearm_next = now + every
        end
        if brain.rearm_try and not (brain.order_until and now < brain.order_until) then
            want = 0 -- between presses: no attack input, so the next press finds him free
            brain.mode = "swapping weapon"
        end
    end
    -- v0.9.90: a skill ordered with the numpad goes out whatever he was doing
    if brain.order_until and now < brain.order_until then
        want = brain.order_bits or 0
        brain.mode = "ordered skill " .. tostring(brain.order_slot)
        brain.next_skill = math.max(brain.next_skill or 0, now + 3.0)
        if not brain.order_logged then brain.order_logged = true; brain.skill_uses = brain.skill_uses + 1; brain_event("order: skill slot " .. tostring(brain.order_slot)) end
    else
        brain.order_logged = nil
    end
    brain.want, brain.ax, brain.ay, brain.mag = want, (sx * mag) + 0.0, (sy * mag) + 0.0, mag + 0.0
end

-- Lock-on for his shots and skills. "Shoot without aim" and archer skills pick their target from the lock-on
-- controller / camera; with nothing locked (and the camera looking elsewhere) arrows miss and skills don't fire.
-- Verified live 2026-11-10: with setTarget on a dummy, one shot took it 1000 -> 119 and Whirling Arrow fired;
-- without it, 13 shots in 15 s did nothing. While a pawn is possessed this controller is shared with the pawn
-- (Chara rebound to the pawn), so the swap only lasts for app.Player.update and is undone in its post-hook.
-- Setting it inside his processor's update window was not enough; around app.Player.update it is (verified A/B:
-- same dummy, lock off 0 damage in 15 s, lock on dead in 3 shots).
-- v0.9.101 Magick Archer, from the tester's own demonstration (DPC_demo.json, 2026-11-16, job 8):
--  * the basic attack is HOLD aim (L2: Job08_StartAim on the upper-body layer, locking on) and RELEASE
--    (Job08_ShootNormalArrow); he held 0.4 - 3 s. There is no attack-button shot.
--  * a skill: while aim is held, a tap of SkillN WITHOUT the shift flags -> Job08_CustomSkill.*.Prepare... (about
--    1.1 s) -> ...Ready... ; releasing aim then shoots it (...Shoot...).
--  * Skill taps that start nothing (Remedy Arrow with no one to cure, an empty slot) leave him in StartAim.
-- The generic ranged rules (tap the light attack, shift + skill) did nothing for him.
-- v0.9.102 Remedy Arrow (LifeReturn, 87). Remedy Arrow only revives pawns, so it is used only when a pawn is known to be down. It stays out of the rotation (brain.NEVER); this runs only while a party
-- pawn is down within 25 m: turn to him, aim, tap the skill, hold until it reads Ready, release. Returns the
-- buttons to hold, or nil when there is nothing to do.
brain.ma_try_remedy = function(now, ar, ax, az)
    if not (cfg.arisen_brain_ma ~= false and cfg.arisen_brain_skills and ax) then return false end
    if cfg.arisen_brain_ma_remedy_assist == false and not cfg.arisen_brain_ma_aim then return false end
    local w = brain.ma_remedy(now, ar, ax, az)
    brain.ma_want = w or 0
    return w ~= nil
end
brain.ma_remedy = function(now, ar, ax, az)
    local r = brain.ma_r or { scan = 0, wait = 0 }
    brain.ma_r = r
    if now >= r.scan then
        r.scan = now + 0.5
        r.slot, r.chara, r.name = nil, nil, nil
        for s = 1, 6 do if brain.skills[s] == 87 then r.slot = s end end
        if r.slot then
            pcall(function()
                for _, e in ipairs(get_party()) do
                    if e.chara and e.chara:call("get_IsDead") == true then
                        local x, _, z = brain_pos(e.chara)
                        if x and math.sqrt((x - ax) ^ 2 + (z - az) ^ 2) <= 25.0 then
                            r.chara, r.name, r.x, r.z = e.chara, e.name, x, z
                            r.work = nil
                            -- v0.9.106: a pawn's get_work() is nil; his one lock-on point is Works[0] / getNearestWork
                            pcall(function()
                                local lt = e.chara:call("get_LockOnTarget")
                                r.work = lt:call("get_work")
                                if not r.work then r.work = lt:call("getNearestWork(via.vec3)", Vector3f.new(ax, 0.0, az)) end
                                if not r.work then r.work = lt:call("get_Works"):call("get_Item", 0) end
                            end)
                        end
                    end
                end
            end)
        end
    end
    if not (r.slot and r.chara) or now < r.wait then r.phase = nil; return nil end
    local yaw = math.atan(r.x - ax, r.z - az)
    pcall(ar.call, ar, "set_TargetFrontAngleDeg(System.Single)", math.deg(yaw) + 0.0)
    local AIM = brain_flag("AimHold") | brain_flag("JobSpecialAction") | brain_flag("GimmickAction")
        | brain_flag("Shift1OnlySpecificJob") | brain_flag("ShootRelease") | brain_flag("ThrowRelease")
    if not r.phase then
        -- v0.9.106: never start a new try while the last arrow's action is still playing
        local busy = false
        pcall(function() busy = tostring(ar:call("get_ActionManager"):get_field("Fsm"):call("getCurrentNodeName(System.UInt32)", 1)):find("LifeReturn", 1, true) ~= nil end)
        if busy then return 0 end
        r.phase, r.t, r.ready_t = "turn", now, nil
        r.seen = false
        -- v0.9.108: the 0.9.105 - 0.9.107 lock-on hand-over and lock-point switch are gone (they could not make a
        -- no-aim arrow revive: see the MODLOG). r.lock_until is never set, so brain_lock_apply ignores this.
        brain_event("Remedy Arrow for " .. tostring(r.name) .. " (down)")
        -- out of a fight his bow is put away and the press did nothing (seen 2026-11-16): draw it first
        pcall(function() ar:call("get_HumanActionSelector"):call("requestDrawWeapon") end)
    end
    local el = now - r.t
    if not cfg.arisen_brain_ma_aim then
        -- v0.9.104 without aiming (the game has Job08_LifeReturnWithoutAim): face him, then shift + the skill
        -- v0.9.108 assisted Remedy Arrow (decision: try option 2, drop it if that fails). A real revive needs an
        -- aimed, fully charged arrow that hits, and aiming is the on-screen camera's, which is the player's while
        -- a pawn is played. So: he faces the pawn, draws, plays the no-aim Remedy Arrow (button held 1.6 s), and
        -- when that action has played and ended the mod revives the pawn with the game's own revive call (the one
        -- the hold-to-revive feature uses). arisen_brain_ma_remedy_assist = false -> he never uses the skill.
        local n1 = ""
        pcall(function() n1 = tostring(ar:call("get_ActionManager"):get_field("Fsm"):call("getCurrentNodeName(System.UInt32)", 1)) end)
        local playing = n1:find("LifeReturn", 1, true) ~= nil
        if playing then r.seen = true end
        if r.phase == "turn" then
            if el >= 1.2 then r.phase, r.t = "press", now end -- time to turn and to get the bow out
            return 0
        elseif r.phase == "press" then
            if el < 1.6 then return brain_flag("Skill" .. r.slot) | brain_flag("Shift1") | brain_flag("Shift2") end
            r.phase, r.t = "fly", now
            return 0
        end
        -- "fly": wait for the action to finish
        if (r.seen and not playing) or el > 5.0 then
            local who, ch = r.name, r.chara
            if r.seen then
                local okv, errv = pcall(function()
                    if ch:call("get_IsDead") ~= true then return end
                    local pm = sdk.get_managed_singleton("app.PawnManager")
                    local pw = pm and pm:call("getPartyPawn(app.Character, System.Boolean)", ch, false)
                    if not pw then error("no app.Pawn for the downed character") end
                    local hit = ch:call("get_Hit")
                    local mx = hit:call("get_ReducedMaxHp")
                    if type(mx) ~= "number" or mx <= 0 then mx = hit:call("get_OriginalMaxHp") or 100 end
                    local hp = mx * (cfg.pawn_revive_health or 0.5)
                    pw:call("setPawnRevive(System.Single, System.Boolean, System.Boolean)", hp, false, false)
                    if (hit:call("get_Hp") or 0) < hp * 0.9 then hit:call("setHpValue(System.Single, System.Boolean)", hp, false) end
                    brain.remedy_revives = (brain.remedy_revives or 0) + 1
                    brain_event("Remedy Arrow: " .. tostring(who) .. " revived (assisted)")
                end)
                if not okv then dev_error("remedy assist", errv) end
                brain.skill_uses = brain.skill_uses + 1
            else
                brain_event("Remedy Arrow did not play -> try again in 10 s")
            end
            r.phase, r.wait = nil, now + 10.0
        end
        return 0
    end
    if r.phase == "turn" then
        if el >= 0.7 then r.phase, r.t = "aim", now end
        return 0
    elseif r.phase == "aim" then
        if el >= 0.6 then r.phase, r.t = "press", now end
        return AIM
    elseif r.phase == "press" then
        if el >= 0.15 then r.phase, r.t = "charge", now end
        return AIM | brain_flag("Skill" .. r.slot)
    else
        local n1 = ""
        pcall(function() n1 = tostring(ar:call("get_ActionManager"):get_field("Fsm"):call("getCurrentNodeName(System.UInt32)", 1)) end)
        local on = n1:find("LifeReturn", 1, true) ~= nil or n1:find("CustomSkill", 1, true) ~= nil
        if on and not r.ready_t and n1:find("Ready", 1, true) then r.ready_t = now end
        if not on and el > 1.0 then
            brain_event("Remedy Arrow did not start -> try again in 20 s")
            r.phase, r.wait = nil, now + 20.0
            return 0
        end
        if (r.ready_t and now - r.ready_t >= 1.0) or el > 4.5 then
            brain.skill_uses = brain.skill_uses + 1
            r.phase, r.wait = nil, now + 6.0
            return 0 -- release = the arrow flies
        end
        return AIM
    end
end
-- v0.9.116 Magick Archer skill cadence. Reported in a Griffin fight: the Magick Archer Arisen fired only quick shots, over and over. Brain log of that fight (0.9.115): one skill every 7 s
-- (arisen_brain_skill_cd), each about 2.6 s long, plain shots the other 4.4 s; and from the second round on the
-- presses for slots 2, 4 and 6 started no skill at all (no custom-skill node followed), so 14 s passed between
-- two skills. Now the wait runs from the skill's own end (arisen_brain_ma_skill_gap, 1.2 s of plain shots), a
-- press that starts nothing is noticed after 1.5 s and the next slot is tried at once, and no skill is pressed
-- on low stamina. Why those presses failed is not known yet; the events now carry his stamina to find out.
-- v0.9.117, reported: Vimtaking Arrow heals by the number of targets it hits. So it is kept for when he is
-- hurt (v0.9.118: he or any pawn): below arisen_brain_ma_vim_hp of health, or hurt at all with a group around him (count from the
-- Conversion check, at most 8 s old). At full health the slot is skipped.
function brain.ma_vim_ok()
    local hp = brain.ma_hp
    if type(hp) ~= "number" then return true end
    if hp < (cfg.arisen_brain_ma_vim_hp or 0.8) then return true end
    local near = (brain.ma and brain.ma.near) or 0
    return hp < 0.97 and near >= (cfg.arisen_brain_ma_vim_group or 3)
end

function brain.ma_stamina(ar)
    local ok, v = pcall(function()
        local sm = ar:call("get_StaminaManager")
        return sm:call("get_RemainingAmount") / math.max(1.0, sm:call("get_MaxValue"))
    end)
    return (ok and type(v) == "number") and v or nil
end

function brain.ma_cadence(now, in_skill)
    local gap = cfg.arisen_brain_ma_skill_gap or 0
    if gap <= 0 then brain.ma_press = nil; return end
    local p = brain.ma_press
    if in_skill then
        if p then p.started = true end
        brain.next_skill = math.max(brain.next_skill or 0, now + gap)
    elseif p and p.started then
        brain.ma_press = nil
    elseif p and now - p.t > 1.5 then
        brain.ma_press = nil
        brain.ma_fail = (brain.ma_fail or 0) + 1
        brain.next_skill = math.min(brain.next_skill or now, now + 0.4)
        if brain.ma_fail <= 12 or brain.ma_fail % 10 == 0 then
            brain_event(string.format("skill slot %d did not start -> next slot (%d so far)", p.slot, brain.ma_fail))
        end
    end
end

-- v0.9.103 Conversion (the R2 mode switch). The mode is Job08ActionController.ArrowType
-- (ChangeArrowTypeEnum: Multiple = 0, Multiplex = 1; read live 2026-11-16: 1). The tester's rule: the single-target
-- mode against one or two enemies or a large monster, the multi-target mode against three or more. Checked at
-- most every 8 s, only between shots; after two presses that changed nothing it stops trying for a minute.
brain.ma_conv = function(now, ar)
    local m = brain.ma
    if cfg.arisen_brain_ma_convert == false or now < (m.conv_next or 0) then return false end
    m.conv_next = now + 8.0
    local want, cur, n = nil, nil, 0
    pcall(function()
        cur = ar:call("get_Human"):call("get_Job08ActionCtrl"):call("get_ArrowType")
        local ax, _, az = brain_pos(ar)
        local em = sdk.get_managed_singleton("app.EnemyManager")
        local arr = em and call(em, "getAllEnemies")
        local cnt = arr and call(arr, "get_Count") or 0
        for i = 0, cnt - 1 do
            local ok, e = pcall(function() return arr[i]:get_field("_Chara") end)
            if ok and e and brain_alive(e) then
                local ex, _, ez = brain_pos(e)
                if ex and math.sqrt((ex - ax) ^ 2 + (ez - az) ^ 2) <= 25.0 then n = n + 1 end
            end
        end
    end)
    m.near = n -- v0.9.117: also for the Vimtaking Arrow rule
    if cur == nil then return false end
    local large = tostring(brain.target_id or ""):find("^ch25") ~= nil
    local multi, single = cfg.arisen_brain_ma_multi or 0, cfg.arisen_brain_ma_single or 1
    want = (n >= 3 and not large) and multi or single
    if m.conv_asked ~= nil and m.conv_asked == cur then m.conv_fail = (m.conv_fail or 0) + 1 else m.conv_fail = 0 end
    m.conv_asked = nil
    if cur == want then return false end
    if (m.conv_fail or 0) >= 2 then
        m.conv_next, m.conv_fail = now + 60.0, 0
        brain_event("Conversion: two presses changed nothing -> not trying for 60 s")
        return false
    end
    m.conv_asked = cur
    brain_event(string.format("Conversion: %d enemies%s -> %s mode", n, large and ", large target" or "", want == multi and "multi-target" or "single-target"))
    return true
end
-- v0.9.104 only the Conversion press, for the no-aim routine: the buttons while converting (0 while he waits for
-- the animation), nil when there is nothing to do and the generic rules should run.
brain.ma_conv_tick = function(now, ar)
    local m = brain.ma or { phase = "rest", until_t = 0 }
    brain.ma = m
    if m.phase == "convert" then
        if now - m.t < 0.2 then
            return brain_flag("AttackL") | brain_flag("SkillAdditional") | brain_flag("GimmickSpecial1") | brain_flag("GliderAscent")
        end
        m.phase, m.until_t = "rest", now + 1.8
        return 0
    end
    m.phase = "rest"
    if now < (m.until_t or 0) then return 0 end
    if brain.ma_conv(now, ar) then m.phase, m.t = "convert", now; return 0 end
    return nil
end
brain.ma_tick = function(now, ar)
    local m = brain.ma or { phase = "rest", until_t = 0 }
    brain.ma = m
    if m.phase == "convert" then
        if now - m.t < 0.2 then
            return brain_flag("AttackL") | brain_flag("SkillAdditional") | brain_flag("GimmickSpecial1") | brain_flag("GliderAscent")
        end
        m.phase, m.until_t = "rest", now + 1.8
        return 0
    end
    local AIM = brain_flag("AimHold") | brain_flag("JobSpecialAction") | brain_flag("GimmickAction")
        | brain_flag("Shift1OnlySpecificJob") | brain_flag("ShootRelease") | brain_flag("ThrowRelease")
    if m.phase == "rest" then
        if now < m.until_t then return 0 end
        if brain.ma_conv(now, ar) then m.phase, m.t = "convert", now; return 0 end
        m.slot, m.ready_t = nil, nil
        if cfg.arisen_brain_skills and now >= brain.next_skill then
            for _ = 1, 6 do
                local slot = (brain.skill_slot % 6) + 1
                brain.skill_slot = slot
                if (brain.skills[slot] or 0) > 0 and now >= ((brain.skill_block or {})[slot] or 0) and brain.slot_ok(slot, now) then
                    m.slot = slot
                    break
                end
            end
        end
        m.phase, m.t = "aim", now
        return AIM
    elseif m.phase == "aim" then
        if now - m.t >= (m.slot and 0.5 or (cfg.arisen_brain_ma_lock or 1.8)) then
            if m.slot then
                m.phase, m.t = "press", now
                brain.next_skill = now + (cfg.arisen_brain_skill_cd or 7.0)
                brain.skill_uses = brain.skill_uses + 1
                brain_event(string.format("skill slot %d (id %d), aimed", m.slot, brain.skills[m.slot]))
            else
                m.phase, m.until_t = "rest", now + 0.9
                brain.presses = brain.presses + 1
                return 0 -- release = the arrows fly
            end
        end
        return AIM
    elseif m.phase == "press" then
        if now - m.t >= 0.15 then m.phase, m.t = "charge", now end
        return AIM | brain_flag("Skill" .. m.slot)
    else -- charge: keep aiming until the skill reads Ready, a little longer, then release
        local n1 = ""
        pcall(function() n1 = tostring(ar:call("get_ActionManager"):get_field("Fsm"):call("getCurrentNodeName(System.UInt32)", 1)) end)
        local el = now - m.t
        local cs = n1:find("CustomSkill", 1, true) ~= nil
        if cs and not m.ready_t and n1:find("Ready", 1, true) then m.ready_t = now end
        if not cs and el > 1.0 then
            brain.skill_block = brain.skill_block or {}
            brain.skill_block[m.slot] = now + 120.0
            brain_event(string.format("skill slot %d did not start while aiming -> skipped for 120 s", m.slot))
            m.phase, m.until_t = "rest", now + 0.9
            return 0
        end
        if (m.ready_t and now - m.ready_t >= 0.8) or el > 4.0 then
            m.phase, m.until_t = "rest", now + 1.2
            return 0
        end
        return AIM
    end
end

local SET_TARGET_SIG = "setTarget(app.LockOnTargetWork, System.Boolean, System.Boolean)"
local REMOVE_TARGET_SIG = "removeTarget(app.LockOnTargetWork)"

-- v0.9.168 the Arisen gets his own lock-on while a pawn is played. Until now the game's lock-on controller (the
-- one app.Player keeps updating, the one that finds what a shot "from the hip" homes in on) was shared: rebound to
-- the played pawn, and lent to the Arisen for his input step every frame (his brain's target set on it, or, with
-- no target, the 0.9.138 guard swap). Measured (archer-loose-2 / -3, Archer pawn, hip shots at ~13 - 25 m): with
-- the lending on, her lock held in 3 of ~150 shooting frames and she turned away from the monster; with it off,
-- 122 of 142. Even a lend that changed nothing broke it (archer-loose-3: guard kept the target 951 times, fixed 0,
-- lock still gone). Shots only worked once the Arisen engaged the SAME monster, because his target was written in.
-- Now: the played pawn keeps the game's controller untouched (she is the player), and the Arisen's input processor
-- gets a controller of its own (Param.LockOnCtrl), which DPC fills with the brain's target. Nothing updates it but
-- DPC: the same arrangement co-op has used for player 2's pawn since 0.9.12 (no finder runs on it). Off: the old
-- sharing (cfg.arisen_own_lockon).
R.ar_lock_want = function()
    return cfg.arisen_own_lockon and state.active and not coop.active and cfg.control_mode == 2 and brain.ar ~= nil
end
R.ar_lock_remove = function(why)
    if not R.ar_lock then return end
    local param, shared = R.ar_lock_param, R.ar_lock_shared
    pcall(function()
        if param and shared then param:set_field("LockOnCtrl", shared) end
    end)
    pcall(function() R.ar_lock:call("clearLockOn") end)
    R.ar_lock, R.ar_lock_param, R.ar_lock_shared = nil, nil, nil
    R.ar_lock_removed = (R.ar_lock_removed or 0) + 1
    if why then log_msg("Arisen's own lock-on removed (" .. tostring(why) .. ")") end
end
R.ar_lock_get = function()
    if not R.ar_lock_want() or R.ar_lock_failed then
        if R.ar_lock then R.ar_lock_remove("not wanted") end
        return nil
    end
    if R.ar_lock then
        -- keep it in place: if anything put the game's controller back into his processor, put his own back
        local okc, cur = pcall(R.ar_lock_param.get_field, R.ar_lock_param, "LockOnCtrl")
        if okc and not same_obj(cur, R.ar_lock) then
            pcall(R.ar_lock_param.set_field, R.ar_lock_param, "LockOnCtrl", R.ar_lock)
            R.ar_lock_resets = (R.ar_lock_resets or 0) + 1
        end
        return R.ar_lock
    end
    local ok, err = pcall(function()
        local pip = call(brain.ar, "get_InputProcessor")
        local param = pip and pip:get_field("Param")
        if not param then error("no input processor") end
        if not same_obj(param:get_field("Chara"), brain.ar) then error("processor is not the Arisen's") end
        local shared = param:get_field("LockOnCtrl")
        if not shared then error("no lock-on in his processor") end
        local own = sdk.create_instance("app.LockOnController"):add_ref()
        own:call("setup", brain.ar, shared:get_field("<ParamList>k__BackingField"))
        param:set_field("LockOnCtrl", own)
        R.ar_lock, R.ar_lock_param, R.ar_lock_shared = own, param, shared
    end)
    if not ok then
        R.ar_lock_failed = true
        log_msg("Arisen's own lock-on could not be set up (" .. tostring(err) .. "); sharing the game's as before")
        return nil
    end
    R.ar_lock_made = (R.ar_lock_made or 0) + 1
    log_msg("Arisen has his own lock-on while the pawn is played")
    return R.ar_lock
end
R.ar_lock_apply = function(own)
    -- the brain's target (or the Remedy Arrow's downed pawn); none: an empty lock-on
    local rw = brain.fjob == 8 and brain.ma_r and os.clock() < (brain.ma_r.lock_until or 0) and brain.ma_r.work or nil
    local work = rw
    if not work and cfg.arisen_brain_lock and brain.lock_work and brain.target then
        local m = brain.mode or ""
        if m == "engage" or m:find("^turn") or m:find("^skill") then work = brain.lock_work end
    end
    pcall(function()
        if work then
            own:call(SET_TARGET_SIG, work, false, false)
            if rw then own:call("setAimTargetInfoToCharacter") end
            brain.lock_sets = (brain.lock_sets or 0) + 1
        elseif own:call("get_Target") ~= nil then
            own:call("clearLockOn")
        end
    end)
end
local function brain_lock_apply()
    if cfg.arisen_own_lockon then -- v0.9.168
        local own = R.ar_lock_get()
        if own then R.ar_lock_apply(own); return end
    elseif R.ar_lock then
        R.ar_lock_remove("switched off")
    end
    -- v0.9.105 Remedy Arrow: the lock-on goes to the downed pawn while he shoots it (in or out of a fight)
    local rw = brain.fjob == 8 and brain.ma_r and os.clock() < (brain.ma_r.lock_until or 0) and brain.ma_r.work or nil
    if rw and state.active and ((not brain.pawn_native and not cfg.arisen_brain_lock_puppeteer)
       or (state.pawn_job == 4 and not cfg.arisen_brain_lock_thief)) then rw = nil end -- same crash guards as below
    if rw and cfg.arisen_brain_lock and brain.lock then
        local lk = brain.lock
        pcall(function()
            brain.lock_shared = state.active and true or false
            if brain.lock_shared and not brain.lock_swapped then
                brain.saved_chara = lk:get_field("Chara")
                brain.saved_tgt = lk:call("get_Target")
                lk:set_field("Chara", brain.ar)
            end
            brain.lock_swapped = true
            brain.lock_used = rw
            lk:call(SET_TARGET_SIG, rw, false, false)
            lk:call("setAimTargetInfoToCharacter") -- v0.9.107: hand the aim point to the shooter (co-op does the same)
            brain.remedy_locks = (brain.remedy_locks or 0) + 1
        end)
        return
    end
    -- v0.9.138 guard swap. The lock-on controller is shared: it belongs to the played pawn, and the Arisen's input
    -- processor uses the same one. When the brain has a target, the swap below hands it to the Arisen for his
    -- step and gives it back after. When it has none (approaching, idle, backing off), his step ran on the pawn's
    -- controller as it stood, asking with HIS vocation's ranges from the PAWN's position: read live with a Mystic
    -- Spearhand Arisen and an Archer pawn, his last request was Job 7 (ranges 2.3 - 12.5 m), hers Job 2 skill 13
    -- (to 30 m), both on the same controller. Reported: an Archer pawn's skill, used without aiming, did not auto-target at range; it only worked very close up. Now the same hand-over is done on
    -- those frames too, with no target set, and whatever his step locked is cleared before hers is put back.
    local function guard()
        if not (cfg.arisen_lock_guard and cfg.arisen_brain_lock and brain.lock and brain.ar and state.active and not coop.active) then return end
        if not brain.pawn_native and not cfg.arisen_brain_lock_puppeteer then return end -- same crash guards as the swap
        if state.pawn_job == 4 and not cfg.arisen_brain_lock_thief then return end
        if brain.lock_swapped then return end
        local lk = brain.lock
        pcall(function()
            brain.lock_shared = true
            brain.saved_chara = lk:get_field("Chara")
            brain.saved_tgt = lk:call("get_Target")
            lk:set_field("Chara", brain.ar)
            brain.lock_swapped, brain.lock_guard, brain.lock_used = true, true, nil
            brain.lock_guards = (brain.lock_guards or 0) + 1
        end)
    end
    if not (cfg.arisen_brain_lock and brain.lock and brain.lock_work and brain.target) then guard(); return end
    -- v0.8.7: no swap on the shared controller while the possessed pawn runs on DPC's puppeteer (Thief /
    -- native failed). Crash 2026-11-10: 6 s after possessing the hired Thief pawn with the brain on, worker-thread AV in
    -- via.vec3.op_Subtraction (DD2.exe+0x524aa97, same family as the Thief and return-to-title crashes).
    -- Lead: swapping LockOnController.Chara races the controller's async target search.
    if state.active and not brain.pawn_native and not cfg.arisen_brain_lock_puppeteer then return end
    -- v0.8.11: and not while a Thief is possessed (every Thief crash so far was in the worker code that the
    -- shared controller's target search runs in); the Arisen still fights, his shots use the camera's target
    if state.active and state.pawn_job == 4 and not cfg.arisen_brain_lock_thief then return end
    local m = brain.mode
    if m ~= "engage" and not m:find("^turn") and not m:find("^skill") then guard(); return end
    local lk = brain.lock
    local ok, err = pcall(function()
        brain.lock_shared = state.active and true or false
        if brain.lock_shared and not brain.lock_swapped then
            -- v0.9.95: never save while a swap is still open (the saved character would be the Arisen himself)
            brain.saved_chara = lk:get_field("Chara")
            brain.saved_tgt = lk:call("get_Target")
            lk:set_field("Chara", brain.ar)
        end
        brain.lock_swapped = true -- before the call below: if it throws, the restore still runs
        brain.lock_used = brain.lock_work
        lk:call(SET_TARGET_SIG, brain.lock_work, false, false)
        brain.lock_sets = (brain.lock_sets or 0) + 1
    end)
    if not ok then
        brain.errs = brain.errs + 1
        brain.err = "lock: " .. tostring(err)
    end
end

local function brain_lock_restore()
    if not brain.lock_swapped then return end
    brain.lock_swapped = false
    if not brain.lock_shared then return end -- unpossessed: it's his own lock-on, leave it
    local lk = brain.lock
    pcall(function()
        if brain.lock_guard then
            -- guard swap: nothing of ours was set; drop whatever his step locked on to
            -- v0.9.168: but only if his step changed it. Measured (archer-loose-2, Archer pawn, shots from the hip at
            -- 22 m): clearing and re-setting her target on every frame left her lock-on in place in 3 of ~150
            -- shooting frames (the game locks her on for one frame, then she turned away and shot at nothing); with
            -- the guard off it held in 122 of 142. When the target is still hers, leave it alone.
            local cur = lk:call("get_Target")
            local sv = brain.saved_tgt
            local same = (cur == nil and sv == nil)
            if cur ~= nil and sv ~= nil then
                local oka, a1 = pcall(cur.get_address, cur)
                local okb, a2 = pcall(sv.get_address, sv)
                same = oka and okb and a1 == a2
            end
            if same then
                brain.lock_guard_kept = (brain.lock_guard_kept or 0) + 1
            else
                brain.lock_guard_fixed = (brain.lock_guard_fixed or 0) + 1
                if cur ~= nil then lk:call("clearLockOn") end
                if sv then lk:call(SET_TARGET_SIG, sv, false, false) end
            end
        else
            lk:call(REMOVE_TARGET_SIG, brain.lock_used or brain.lock_work)
            if brain.saved_tgt then lk:call(SET_TARGET_SIG, brain.saved_tgt, false, false) end
        end
    end)
    brain.lock_guard = false
    -- v0.9.95: while a pawn is played (not co-op) the shared lock-on belongs to that pawn, whatever was saved
    local back = (state.active and not coop.active and cfg.exp_rebind_lockon and state.pawn_chara) or brain.saved_chara
    pcall(function() if back then lk:set_field("Chara", back) end end)
    brain.saved_tgt, brain.saved_chara = nil, nil
end

-- Put your real input back into the Arisen's CharacterInput (end of app.Player.update)
local function brain_restore_input()
    if not brain.hw_saved or brain.hw_restored then return end
    brain.hw_restored = true
    local inp = brain.ar_input
    if not inp then return end
    pcall(function()
        inp:set_field("ButtonOnFlags", brain.hw_on or 0)
        inp:set_field("ButtonTriggerFlags", brain.hw_trg or 0)
        inp:set_field("ButtonReleaseFlags", brain.hw_rel or 0)
        inp:call("setAxisL(System.Single, System.Single)", (brain.hw_ax or 0.0) + 0.0, (brain.hw_ay or 0.0) + 0.0)
        inp:call("set_AxisMagnitudeL(System.Single)", (brain.hw_mag or 0.0) + 0.0)
    end)
end

-- Called from the PlayerInputProcessor.update pre-hook when it runs for the Arisen and the brain is on.
local function brain_inject()
    local inp = brain.ar_input
    if not inp then return end
    local want = brain.want
    local trg, rel = want & ~brain.prev, brain.prev & ~want
    brain.prev = want
    -- v0.8.4: remember your real input so it can be put back after app.Player.update (brain_restore_input).
    -- DPC mirrors this same CharacterInput onto the possessed pawn at the start of the next frame; left holding
    -- the brain's buttons, the pawn got the brain's buttons instead of yours and could not attack.
    if not brain.hw_saved then
        pcall(function()
            brain.hw_snap_t = os.clock()
            brain.hw_on = inp:get_field("ButtonOnFlags")
            brain.hw_trg = inp:get_field("ButtonTriggerFlags")
            brain.hw_rel = inp:get_field("ButtonReleaseFlags")
            local v = inp:get_field("_AxisL")
            brain.hw_ax, brain.hw_ay = v and v.x or 0.0, v and v.y or 0.0
            brain.hw_mag = inp:get_field("<AxisMagnitudeL>k__BackingField") or 0.0
            brain.hw_saved = true
        end)
    end
    local ok, err = pcall(function()
        inp:set_field("ButtonOnFlags", want)
        inp:set_field("ButtonTriggerFlags", trg)
        inp:set_field("ButtonReleaseFlags", rel)
        inp:call("setAxisL(System.Single, System.Single)", brain.ax, brain.ay)
        inp:call("set_AxisMagnitudeL(System.Single)", brain.mag)
    end)
    -- v0.8.3: leave his right stick alone by default. His processor runs after the pawn's and also feeds the
    -- camera; zeroing his AxisR froze the camera while possessing (user report 2026-11-10).
    if ok and cfg.arisen_brain_clear_axis_r and brain.axisr_ok ~= false then
        local ok_r = pcall(function()
            local z = Vector2f.new(0.0, 0.0)
            inp:set_field("<AxisR>k__BackingField", z)
            inp:set_field("KeyboardMouseAxisR", z)
        end)
        if not ok_r then brain.axisr_ok = false; log_msg("Arisen brain: AxisR clear failed, disabled") end
    end
    brain.inj = brain.inj + 1
    if (trg & brain_flag("AttackS")) ~= 0 then brain.presses = brain.presses + 1 end
    if not ok then
        brain.errs = brain.errs + 1
        brain.err = tostring(err)
        if brain.errs == 1 or brain.errs % 300 == 0 then log_msg("Arisen brain inject error: " .. brain.err) end
    end
end

local function brain_dump()
    if not cfg.arisen_brain_telemetry then return end
    -- (v0.8.11: also the possession black box: written while possessing even with the brain off)
    local now = os.clock()
    if now < brain.next_dump then return end
    brain.next_dump = now + 0.5
    local node = "-"
    pcall(function()
        local fsm = brain.ar:call("get_ActionManager"):get_field("Fsm")
        node = fsm:call("getCurrentNodeName(System.UInt32)", 0) .. " | " .. fsm:call("getCurrentNodeName(System.UInt32)", 1)
    end)
    local thp = brain.target and call(brain.target, "get_Hp")
    R.dump(BRAIN_LOG_PATH, {
        version = VERSION, t = now, on = brain.on, solo = brain.solo, possessing = state.active,
        job = brain.job, fjob = brain.fjob, style = brain.style, rearms = brain.rearms, rearm_ok = brain.rearm_ok, rearm_fail = brain.rearm_fail, skills = brain.skills, mode = brain.mode, stay = state.arisen_stay,
        target = brain.target_id, target_hp = thp, dist = brain.dist, off_deg = brain.off,
        los = brain.los, los_blocked = brain.los_blocked, los_feature = cfg.arisen_brain_los,
        want = string.format("0x%X", brain.want), stick = { brain.ax, brain.ay, brain.mag },
        presses = brain.presses, skill_uses = brain.skill_uses, injected_frames = brain.inj, lock_sets = brain.lock_sets, lock_guards = brain.lock_guards, cine_blocked = R.cine_blocked, cam_refused = R.cam_refused, driven_frames = brain.driven, your_buttons = string.format("0x%X", brain.hw_on or 0), pawn_mirror_on = string.format("0x%X", state.last_on_flags or 0),
        errors = brain.errs, last_error = brain.err, arisen_nodes = node, events = brain.events, watch = (brain.job == 3 or brain.job == 6 or (brain.job or 0) >= 8) and brain.watch_log or nil,
        coop = {
            active = coop.active, map = coop.map_src, pad_buttons = string.format("0x%X", coop.last_btn or 0),
            p2_flags = string.format("0x%X", coop.last_flags or 0), pad_zeroed = coop.pb_zeroed,
            pad_device = pad_device_ok, pad_stick = coop.last_stick,
            zero_pad = cfg.coop_zero_pad_for_arisen, block_stick = cfg.coop_block_p2_stick, stick_fixes = coop.stick_fixes,
            block_cam = cfg.coop_block_p2_camera, cam_fixes = coop.cam_fixes, driven = coop.driven, err = coop.err, events = coop.events,
        },
        pawn = state.active and {
            name = state.pawn_name, job = state.pawn_job, native = brain.pawn_native,
            nodes = (function()
                local ok, r = pcall(function()
                    local f = state.pawn_chara:call("get_ActionManager"):get_field("Fsm")
                    return f:call("getCurrentNodeName(System.UInt32)", 0) .. " | " .. f:call("getCurrentNodeName(System.UInt32)", 1)
                end)
                return ok and r or "?"
            end)(),
            hp = call(state.pawn_chara, "get_Hp"),
            lock_chara = (function()
                local ok, r = pcall(function()
                    local c = state.arisen_lockon_ctrl:get_field("Chara")
                    return c and c:call("get_CharaIDString") or "nil"
                end)
                return ok and r or "?"
            end)(),
            lock_has_target = (function()
                local ok, r = pcall(function() return state.arisen_lockon_ctrl:call("get_Target") ~= nil end)
                return ok and r or false
            end)(),
            last_action = state.last_action_str,
        } or nil,
    }, 2)
end

-- ----------------------------------------------------------------------------
-- Hooks:
--   1. Block Arisen PlayerInputProcessor & SequenceBuffer While Possessing
--   2. Redirect Arisen HumanSkillContext:getSkillID & JobContext:get_Job to Pawn
--      so native DD2 HUD skill labels reflect the possessed pawn's skills!
-- ----------------------------------------------------------------------------
local hooks_installed = false
local hook_last_slot = nil

local function install_hooks()
    if hooks_installed then return end

    -- 1a. Block Arisen PlayerInputProcessor:update
    local pip_td = sdk.find_type_definition("app.PlayerInputProcessor")
    if pip_td then
        local upd_m = pip_td:get_method("update")
        if upd_m then
            sdk.hook(
                upd_m,
                function(args)
                    -- v0.9 co-op: player 1's Arisen runs normally; strip player 2's controller out of his input
                    if coop.active and state.arisen_pip_addr ~= 0 and arg_addr(args[2]) == state.arisen_pip_addr then
                        if not brain.self_driving then brain.game_pip_t = os.clock() end
                        if coop.filter then
                            local okf, ferr = pcall(coop.filter)
                            if not okf then dev_error("coop.filter", ferr) end
                        end
                        return
                    end
                    -- v0.8: the Arisen combat brain lets his processor run on synthetic input instead
                    if brain.on and brain.pip_addr ~= 0 and arg_addr(args[2]) == brain.pip_addr then
                        if not brain.self_driving then brain.game_pip_t = os.clock() end
                        brain_inject()
                        return
                    end
                    if state.active and cfg.control_mode == 2 and cfg.sub_disable_arisen_pip then
                        if state.arisen_pip_addr ~= 0 and arg_addr(args[2]) == state.arisen_pip_addr then
                            state.arisen_pip_blocked_count = state.arisen_pip_blocked_count + 1
                            return sdk.PreHookResult.SKIP_ORIGINAL
                        end
                    end
                end,
                function(retval) return retval end
            )
        end
    end

    -- 1a-coop. app.UserInput.processButton(UInt64, via.hid.GamePadButton) is the pad path of the game's input
    -- update (processKeyboardMouse is the keyboard/mouse path). During co-op, give the Arisen's input an empty
    -- pad so player 2's controller never drives him. Unverified live: auto-disabled if it kills player 1's keys.
    do
        local ui_td = sdk.find_type_definition("app.UserInput")
        local pb = ui_td and ui_td:get_method("processButton")
        if pb then
            sdk.hook(pb, function(args)
                if R.kb_wait and R.kb_wait() and coop.ar_input_addr ~= 0 and arg_addr(args[2]) == coop.ar_input_addr then
                    args[4] = sdk.to_ptr(0) -- dev44: waiting for player 2, player 1 on keyboard: no controller drives him
                    return
                end
                if coop.active and coop.ar_input_addr ~= 0 and arg_addr(args[2]) == coop.ar_input_addr
                   and R.tp_on and R.tp_on() then
                    -- v0.9.170 (dev): two controllers. Player 1's pad drives the Arisen; only player 2's buttons
                    -- are taken out (see R.tp_arisen_buttons for the three ways tried).
                    local okb, v = pcall(R.tp_arisen_buttons, args[4])
                    if okb and v ~= nil then args[4] = sdk.to_ptr(v) end
                    return
                end
                if ((coop.active and not (R.robot_p2 and R.robot_p2())) or (R.cp_pawns and R.cp_pawns() and R.cp.kb))
                   and cfg.coop_zero_pad_for_arisen and not coop.zero_off and coop.ar_input_addr ~= 0
                   and arg_addr(args[2]) == coop.ar_input_addr then -- v0.9.171: both on pawns, one controller: the controller is player 2's
                    args[4] = sdk.to_ptr(0)
                    coop.pb_zeroed = coop.pb_zeroed + 1
                end
            end, function(retval) return retval end)
        end
    end

    -- 1a2. Pawns get periodic idle "LivSitOnTheGround" requests (~every 3 s while standing) that the Arisen
    -- never gets. Drop them for the possessed pawn. Address check first: requestAction runs for everyone.
    local sel_td = sdk.find_type_definition("app.HumanActionSelector")
    local req_m = sel_td and sel_td:get_method("requestAction(System.String, System.UInt32)")
    if req_m then
        sdk.hook(
            req_m,
            function(args)
                local a_sel = arg_addr(args[2])
                if not ((state.active and state.pawn_sel_addr ~= 0 and a_sel == state.pawn_sel_addr)
                    or (R.s2 and R.s2.active and a_sel == (R.s2.sel_addr or -1))
                    or (R.np_sel and R.np_sel(a_sel))) then return end -- v0.9.171: and player 2's second pawn; 0.9.172 players 3+
                local ok, name = pcall(function()
                    local so = sdk.to_managed_object(args[3])
                    return so and so:call("ToString")
                end)
                if ok and type(name) == "string" and name:find("^LivSit") then
                    return sdk.PreHookResult.SKIP_ORIGINAL
                end
            end,
            function(retval) return retval end
        )
    end

    -- 1b. Block Arisen Player:updateSequenceBuffer
    local pl_td = sdk.find_type_definition("app.Player")
    if pl_td then
        local seq_m = pl_td:get_method("updateSequenceBuffer")
        if seq_m then
            sdk.hook(
                seq_m,
                function(args)
                    if brain.on then return end -- v0.8: the brain's synthetic input drives the Arisen
                    if state.active and cfg.control_mode == 2 and cfg.sub_disable_arisen_pip then
                        return sdk.PreHookResult.SKIP_ORIGINAL
                    end
                end,
                function(retval) return retval end
            )
        end
    end

    -- 2a. Hook app.HumanSkillContext:getSkillID(job, slot) for native HUD Skill Labels
    local sc_td = sdk.find_type_definition("app.HumanSkillContext")
    if sc_td then
        local get_sk_m = sc_td:get_method("getSkillID")
        if get_sk_m then
            sdk.hook(
                get_sk_m,
                function(args)
                    local hs = thread.get_hook_storage()
                    hs.slot = nil
                    if state.active and cfg.native_hud_skill_hook and not in_internal_query and not (brain.on and not cfg.arisen_brain_keep_hud_redirect) and state.arisen_skill_ctx_addr ~= 0 then
                        if arg_addr(args[2]) == state.arisen_skill_ctx_addr then
                            local slot_int = sdk.to_int64(args[4]) & 0xFFFFFFFF
                            if slot_int >= 0 and slot_int <= 3 then
                                hs.slot = slot_int
                            end
                        end
                    end
                end,
                function(retval)
                    local hs = thread.get_hook_storage()
                    if hs.slot ~= nil and state.active and state.pawn_skills then
                        local p_skill = state.pawn_skills[hs.slot + 1] or 0
                        return sdk.to_ptr(p_skill)
                    end
                    return retval
                end
            )
        end
    end

    -- 2b. Hook app.JobContext:get_Job() so the native HUD displays the possessed pawn's vocation
    local jc_td = sdk.find_type_definition("app.JobContext")
    if jc_td then
        local get_job_m = jc_td:get_method("get_Job")
        if get_job_m then
            sdk.hook(
                get_job_m,
                function(args)
                    local hs = thread.get_hook_storage()
                    hs.is_arisen_jc = false
                    if state.active and cfg.native_hud_skill_hook and not in_internal_query and not (brain.on and not cfg.arisen_brain_keep_hud_redirect) and state.arisen_job_ctx_addr ~= 0 then
                        if arg_addr(args[2]) == state.arisen_job_ctx_addr then
                            hs.is_arisen_jc = true
                        end
                    end
                end,
                function(retval)
                    local hs = thread.get_hook_storage()
                    if hs.is_arisen_jc and state.active and state.pawn_job then
                        return sdk.to_ptr(state.pawn_job)
                    end
                    return retval
                end
            )
        end
    end

    -- 2c. Hook app.Character:getWeaponJob() so the HUD gets the possessed pawn's weapon vocation
    local chara_td = sdk.find_type_definition("app.Character")
    if chara_td then
        local gwj_m = chara_td:get_method("getWeaponJob")
        if gwj_m then
            sdk.hook(
                gwj_m,
                function(args)
                    local hs = thread.get_hook_storage()
                    hs.is_arisen_chara = false
                    if state.active and cfg.native_hud_skill_hook and not in_internal_query and not (brain.on and not cfg.arisen_brain_keep_hud_redirect) and state.arisen_chara_addr ~= 0 then
                        if arg_addr(args[2]) == state.arisen_chara_addr then
                            hs.is_arisen_chara = true
                        end
                    end
                end,
                function(retval)
                    local hs = thread.get_hook_storage()
                    if hs.is_arisen_chara and state.active and state.pawn_job then
                        return sdk.to_ptr(state.pawn_job)
                    end
                    return retval
                end
            )
        end
    end

    -- 2d. Hook app.ui010201:isDisableCustomSkill so possessed pawn skills are never grayed out in native HUD
    local ui_td = sdk.find_type_definition("app.ui010201")
    if ui_td then
        local dis_m = ui_td:get_method("isDisableCustomSkill")
        if dis_m then
            sdk.hook(
                dis_m,
                function(args) end,
                function(retval)
                    if state.active and cfg.native_hud_skill_hook then
                        if R.cling and cfg.hud_cling_grey ~= false then -- v0.9.119: on a monster the game decides
                            if R.cling_grey and (sdk.to_int64(retval) & 1) == 1 then R.cling_grey = R.cling_grey + 1 end
                            return retval
                        end
                        return sdk.to_ptr(0) -- false: never grayed out while possessing!
                    end
                    return retval
                end
            )
        end

        -- setupPlChara rebinds the guide to the Arisen; re-point it at the pawn afterwards.
        -- (Post-hooks only receive retval, so `this` is carried over in hook storage.)
        local setup_pl_m = ui_td:get_method("setupPlChara")
        if setup_pl_m then
            sdk.hook(
                setup_pl_m,
                function(args)
                    thread.get_hook_storage()["this"] = args[2]
                end,
                function(retval)
                    if state.active and cfg.native_hud_skill_hook and state.pawn_chara and state.pawn_human then
                        local this_ptr = thread.get_hook_storage()["this"]
                        local this_ui = this_ptr and sdk.to_managed_object(this_ptr)
                        if this_ui then
                            local pawn_sc = get_skill_ctx(state.pawn_human)
                            local pawn_job = state.pawn_job or 1
                            local pawn_input = call(state.pawn_chara, "get_Input")
                            this_ui:set_field("PlChara", state.pawn_chara)
                            this_ui:set_field("PlHuman", state.pawn_human)
                            if pawn_sc then this_ui:set_field("SkillContext", pawn_sc) end
                            this_ui:set_field("Job", pawn_job)
                            this_ui:set_field("WeaponJob", pawn_job)
                            if pawn_input then this_ui:set_field("PlInput", pawn_input) end
                        end
                    end
                    return retval
                end
            )
        end

        -- v0.9.129 the "Dash" label. Reported 2026-11-17: the played pawn's guide lacks the second Dash label on Circle that the Arisen's has; dashing itself works. The game blanks that
        -- label for a played pawn (ui010201.setBtnDashTextEmpty) although its own isDisableDash / isRestrictedDash
        -- say false; why is not known. So: remember what the game writes there while the Arisen is played
        -- (setBtnDashText), and during a normal possession skip the blanking while dashing is allowed and the
        -- pawn is not on a monster (R.dash_ok, worked out twice a second in maintain_native_hud).
        -- v0.9.130: 0.9.129 assumed the blanking went through setBtnDashTextEmpty. Counters after one minute:
        -- setBtnDashText 3120 calls, setBtnDashTextEmpty 0. So the game calls setBtnDashText every frame and its
        -- arguments decide what shows. The skip / write-once of 0.9.129 is removed; this only records, per played
        -- character, which argument combinations arrive (dev status aim.dash_label.seen), to learn the rule.
        local dash_set_m = ui_td:get_method("setBtnDashText(System.Guid, System.Boolean, System.Boolean)")
        if dash_set_m and R.dev then
            R.dash_seen = {}
            sdk.hook(dash_set_m, function(args)
                R.dash_n_text = (R.dash_n_text or 0) + 1
                local a, b = sdk.to_int64(args[4]) & 1, sdk.to_int64(args[5]) & 1
                local key = (coop.active and "coop" or (state.active and "pawn" or "arisen")) .. " " .. a .. b
                if not R.dash_seen[key] then
                    local g = "?"
                    pcall(function()
                        local vt = sdk.to_valuetype(args[3], "System.Guid")
                        g = string.format("%08x", (vt:get_field("mData1") or 0) & 0xFFFFFFFF)
                    end)
                    R.dash_seen[key] = { n = 0, guid = g }
                end
                local e = R.dash_seen[key]
                e.n, e.last = e.n + 1, os.clock()
            end, function(retval) return retval end)
        end

        -- The guide only lists the 4 custom skills while the skill-shift button is held. It reads that from
        -- PlInput (the pawn's AI-driven input), so feed it the player's modifier state instead.
        local shift_m = ui_td:get_method("isInputCustomSkillShift(System.Boolean)")
        if shift_m then
            sdk.hook(
                shift_m,
                function(args) end,
                function(retval)
                    if state.active and cfg.native_hud_skill_hook and state.hud_shift_held then
                        return sdk.to_ptr(1)
                    end
                    return retval
                end
            )
        end
    end

    -- v0.9.139 the game's cinematic action camera (camera control type 10, app.CinematicActionCameraController).
    -- Reported twice, playing an Archer pawn against a Cyclops: the camera was pulled away from the played pawn.
    -- The 0.9.137 camera watch at that moment: "Camera: Combat (2) -> CinematicAction (10), player camera false".
    -- Any action with such a track asks for it through the static requestPlay; the game places that camera itself,
    -- not by the camera's target object, so it left the played pawn. While a pawn is played (possession or co-op)
    -- the request is dropped (switch: possess_no_cinematic_cam).
    pcall(function()
        local ctd = sdk.find_type_definition("app.CinematicActionCameraController")
        local m = ctd and ctd:get_method("requestPlay(System.UInt32, System.Nullable`1<System.UInt32>)")
        if not m then log_msg("Cinematic camera hook: requestPlay not found"); return end
        sdk.hook(m, function(args)
            if state.active and cfg.possess_no_cinematic_cam then
                R.cine_blocked = (R.cine_blocked or 0) + 1
                return sdk.PreHookResult.SKIP_ORIGINAL
            end
        end, function(retval) return retval end)
    end)

    hooks_installed = true
    log_msg("Installed Arisen input suppression & SkillContext UI hooks")
end
pcall(install_hooks)

-- ----------------------------------------------------------------------------
-- Soft-Only Pawn AI Suppression (No via.Behavior:set_Enabled(false)!)
-- ----------------------------------------------------------------------------
local function set_pawn_ai_suppressed(chara, pawn_obj, suppress, first_time)
    if not chara then return end

    -- 1. AIDecisionMaker -> DecisionModule.IsSkipThink (Soft boolean flag only)
    local aidm = call(chara, "get_AIDecisionMaker") or field(chara, "<AIDecisionMaker>k__BackingField")
    if aidm then
        local dm = call(aidm, "get_DecisionModule") or field(aidm, "<DecisionModule>k__BackingField")
        if dm then
            call(dm, "set_IsSkipThink(System.Boolean)", suppress)
        end
    end

    -- 2. PawnNavigationController -> IsRequestDisableNavi (Soft boolean flag only)
    local nav = call(chara, "get_NavigationController") or field(chara, "<NavigationController>k__BackingField")
    if nav then
        call(nav, "set_IsRequestDisableNavi(System.Boolean)", suppress)
    end

    -- 3. Clear active AI orders once on initial possession
    if pawn_obj and suppress and first_time then
        set_field(pawn_obj, "_NextOrder", 0)
    end
end

-- ----------------------------------------------------------------------------
-- Camera Attachment (MainCameraController)
-- ----------------------------------------------------------------------------
local function attach_camera_to(go)
    if not go then return false end
    if R.api_claimed and R.api_claimed("camera.follow") then return true end -- v0.9.170: another mod places the views
    local cam_mgr = sdk.get_managed_singleton("app.CameraManager")
    if not cam_mgr then return false end
    local mcc = call(cam_mgr, "getMainCameraController", 0)
    if not mcc then return false end

    local cur_target = call(mcc, "get_TargetObject")
    if not same_obj(cur_target, go) then
        write_trace("attach_camera_to: registerTargetObject + onWarpTarget")
        call(mcc, "registerTargetObject(via.GameObject)", go)
        call(mcc, "onWarpTarget()")
    end
    return true
end

-- ----------------------------------------------------------------------------
-- Sync Native HUD Skill Palette (Mirrors Pawn's Skills onto Native KeyGuide)
-- NEVER calls setSkill on Arisen's HumanSkillContext to prevent save corruption!
-- ----------------------------------------------------------------------------
-- v0.9.134 "Dash" on the guide for a played pawn. Read in a fresh session (probe dash9): with the guide on the
-- Arisen ui010201.BtnDash = 5 (the Circle slot) and IsBtnAssigned = true; with the guide on a played pawn
-- BtnDash = -1 and IsBtnAssigned = false, while setBtnDashText gets the same arguments for both. So the game's
-- own button assignment does not complete for a pawn and the label has no slot to go to. The Arisen's two dash
-- slots are remembered at take-over and written back whenever they read -1 while the guide is on the pawn
-- (switch: hud_dash_slot).
R.dash_slots_keep = function(kg)
    local a, b = kg:get_field("BtnDash"), kg:get_field("BtnDash2")
    if type(a) == "number" and a >= 0 then R.dash_slots = { a, type(b) == "number" and b or -1 } end
end
R.dash_slots_put = function(kg)
    if cfg.hud_dash_slot ~= true or not R.dash_slots then return end
    local ok, err = pcall(function()
        if kg:get_field("BtnDash") == -1 then
            kg:set_field("BtnDash", R.dash_slots[1])
            if R.dash_slots[2] >= 0 and kg:get_field("BtnDash2") == -1 then kg:set_field("BtnDash2", R.dash_slots[2]) end
            R.dash_puts = (R.dash_puts or 0) + 1
        end
    end)
    if not ok then dev_error("dash slots", err) end
end

local function apply_native_hud_skills(enable)
    local gm = sdk.get_managed_singleton("app.GuiManager")
    if not gm then return end
    local kg = gm:get_field("KeyGuide")
    if not kg then return end

    -- v0.9.133: what "give the guide back" means is always the Arisen. Until now the guide's fields were saved as
    -- found at take-over; after Reset Scripts during a possession (or any take-over while the guide still pointed
    -- at a pawn) that saved the pawn, and releasing "restored" the guide to the pawn: bridge probe hud4 with nobody
    -- possessed read PlChara = the main pawn, and it was reported that the Arisen showed no skill list with L1
    -- pressed". Saved now only when the guide really is on the Arisen; otherwise built from the Arisen himself.
    local arisen_job = nil
    if enable and not state.orig_keyguide and state.arisen_chara and state.arisen_human then
        arisen_job = get_job(state.arisen_human, state.arisen_chara)
    end

    in_internal_query = true

    if enable and cfg.native_hud_skill_hook and state.pawn_chara and state.pawn_human then
        if not state.orig_keyguide and state.arisen_chara and state.arisen_human then
            local cur = kg:get_field("PlChara")
            if cur and addr_of(cur) == addr_of(state.arisen_chara) then
                R.dash_slots_keep(kg)
                state.orig_keyguide = {
                    PlChara = cur,
                    PlHuman = kg:get_field("PlHuman") or state.arisen_human,
                    SkillContext = kg:get_field("SkillContext") or state.arisen_skill_ctx,
                    Job = kg:get_field("Job"),
                    WeaponJob = kg:get_field("WeaponJob"),
                    PlInput = kg:get_field("PlInput") or state.arisen_input,
                }
            else
                state.orig_keyguide = {
                    PlChara = state.arisen_chara,
                    PlHuman = state.arisen_human,
                    SkillContext = state.arisen_skill_ctx or get_skill_ctx(state.arisen_human),
                    Job = arisen_job or kg:get_field("Job"),
                    WeaponJob = arisen_job or kg:get_field("WeaponJob"),
                    PlInput = state.arisen_input or call(state.arisen_chara, "get_Input"),
                }
                log_msg("Key guide was not on the Arisen at take-over; it will be handed back to the Arisen on release")
            end
        end
        local pawn_sc = get_skill_ctx(state.pawn_human)
        local pawn_job = state.pawn_job or 1
        local pawn_input = call(state.pawn_chara, "get_Input")

        kg:set_field("PlChara", state.pawn_chara)
        kg:set_field("PlHuman", state.pawn_human)
        if pawn_sc then kg:set_field("SkillContext", pawn_sc) end
        kg:set_field("Job", pawn_job)
        kg:set_field("WeaponJob", pawn_job)
        if pawn_input then kg:set_field("PlInput", pawn_input) end

        pcall(kg.call, kg, "setupCustomSkillMsgId")
        pcall(kg.call, kg, "setupCustomSkillButton", true)
        pcall(gm.call, gm, "setupKeyGuideCustomSkill")
        R.dash_slots_put(kg)
    elseif not enable and state.orig_keyguide then
        local orig = state.orig_keyguide
        kg:set_field("PlChara", orig.PlChara)
        kg:set_field("PlHuman", orig.PlHuman)
        kg:set_field("SkillContext", orig.SkillContext)
        kg:set_field("Job", orig.Job)
        kg:set_field("WeaponJob", orig.WeaponJob)
        kg:set_field("PlInput", orig.PlInput)

        pcall(kg.call, kg, "setupCustomSkillMsgId")
        pcall(kg.call, kg, "setupCustomSkillButton", true)
        pcall(gm.call, gm, "setupKeyGuideCustomSkill")
        state.orig_keyguide = nil
    end

    in_internal_query = false
end

-- ----------------------------------------------------------------------------
-- Native HUD gauges: HP / stamina (ui020901), player gauge (ui020401), minimap (ui020301)
-- Each widget caches PlChara/PlHuman; pointing them at the pawn and re-running their setup makes the
-- native HUD track the possessed pawn. Verified live 2026-11-08 via the agent bridge.
-- ----------------------------------------------------------------------------
local HUD_GAUGES = {
    { type = "app.ui020901", setup = { "setupHpGauge", "setupStGauge", "setupStatusIcon" } },
    { type = "app.ui020401", setup = { "setupAction" } },
    { type = "app.ui020301", force_field = "NeedForceUpdate" },
}
local hud_widgets = {} -- type name -> component (re-found when missing or destroyed)

local function find_component(type_name)
    local sm = sdk.get_native_singleton("via.SceneManager")
    if not sm then return nil end
    local scene = sdk.call_native_func(sm, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
    if not scene then return nil end
    local ok, arr = pcall(scene.call, scene, "findComponents(System.Type)", sdk.typeof(type_name))
    if not ok or not arr then return nil end
    local n = call(arr, "get_Count") or call(arr, "get_Length") or 0
    if n <= 0 then return nil end
    return arr[0]
end

local function get_hud_widget(type_name)
    local w = hud_widgets[type_name]
    if w and call(w, "get_GameObject") then return w end
    w = find_component(type_name)
    hud_widgets[type_name] = w
    return w
end

local function bind_hud_gauges(chara, human, force)
    if not chara or not human then return end
    local target = addr_of(chara)
    for _, g in ipairs(HUD_GAUGES) do
        local w = get_hud_widget(g.type)
        if w then
            local cur = field(w, "PlChara")
            if force or addr_of(cur) ~= target then
                set_field(w, "PlChara", chara)
                set_field(w, "PlHuman", human)
                if g.setup then
                    for _, m in ipairs(g.setup) do pcall(w.call, w, m) end
                end
                if g.force_field then set_field(w, g.force_field, true) end
            end
        end
    end
end

local function apply_native_hud_gauges(enable)
    if enable then
        if cfg.native_hud_gauges and state.pawn_chara then
            bind_hud_gauges(state.pawn_chara, state.pawn_human, true)
        end
    elseif state.arisen_chara then
        bind_hud_gauges(state.arisen_chara, state.arisen_human, true)
    end
end

-- Re-assert every 0.5 s: menus, area loads and the game's own setupPlChara calls rebind to the Arisen.
local function maintain_native_hud()
    local now = os.clock()
    if now < state.next_hud_check_t then return end
    state.next_hud_check_t = now + 0.5
    if cfg.native_hud_gauges then
        bind_hud_gauges(state.pawn_chara, state.pawn_human, false)
    end
    if cfg.native_hud_skill_hook and state.pawn_chara then
        local kg = get_hud_widget("app.ui010201")
        if kg and addr_of(field(kg, "PlChara")) ~= addr_of(state.pawn_chara) then
            pcall(apply_native_hud_skills, true)
            R.hud_repoints = (R.hud_repoints or 0) + 1
        elseif kg then
            R.dash_slots_put(kg)
        end
    end
end

-- ----------------------------------------------------------------------------
-- Native Arisen controls (v0.7.0): a per-pawn app.PlayerInputProcessor driven from DPC
-- ----------------------------------------------------------------------------
local native = { pip = nil, param = nil, lock = nil, job = nil, errors = 0, failed = false, frames = 0,
    drive = "player", hook_frames = 0, hook_input_frames = 0, mirror_input_frames = 0, t_start = 0 }

local function native_release()
    -- Just drop the references. (o:release() logged "not managed by our Lua state" warnings.)
    native.pip, native.lock = nil, nil
    native.param, native.job, native.errors, native.failed, native.frames = nil, nil, 0, false, 0
    native.hook_frames, native.hook_input_frames, native.mirror_input_frames = 0, 0, 0
end

local function native_build()
    native_release()
    if not cfg.native_controls then return false end
    if cfg.native_skip_thief and state.pawn_job == 4 then
        log_msg("Native controls skipped for Thief (native_skip_thief) -> Mode 2 puppeteer")
        return false
    end
    local pw, hu, apip = state.pawn_chara, state.pawn_human, state.arisen_pip
    if not (pw and hu and apip) then return false end
    local ok, err = pcall(function()
        local pip = sdk.create_instance("app.PlayerInputProcessor"):add_ref()
        local track = hu:get_field("Track")
        pip:call("set_Chara", pw)
        pip:call("set_Human", hu)
        pip:call("set_PlayerTrack", track)
        pip:set_field("Camera", apip:get_field("Camera"))
        -- setup takes (Character, PlayerTrack). A bare setup() is rejected by REFramework ("Invalid number of
        -- arguments") and silently skipped, leaving the processor half-initialised (suspected Thief crash).
        pip:call("setup(app.Character, app.PlayerTrack)", pw, track)
        if not pip:get_field("Camera") then pip:set_field("Camera", apip:get_field("Camera")) end
        pip:call("selectProcessor")
        -- Lock-on: by default use the Arisen's own LockOnController, which DPC already rebinds to the pawn
        -- (Chara = pawn) at possession and which app.Player keeps updating. v0.7.0/0.7.1 built an orphan
        -- controller nobody else updates; LockOnController does async target finding (FindTargetMutex), and
        -- both Thief crashes were on engine worker threads during target-seeking skills.
        local alock = apip:get_field("Param"):get_field("LockOnCtrl")
        local lock = alock
        if cfg.native_own_lockon or not alock then
            lock = sdk.create_instance("app.LockOnController"):add_ref()
            lock:call("setup", pw, alock and alock:get_field("<ParamList>k__BackingField"))
        end
        local param = pip:get_field("Param")
        param:set_field("Chara", pw)
        param:set_field("Human", hu)
        param:set_field("PlayerTrack", track)
        param:set_field("LockOnCtrl", lock)
        -- The Arisen's Details all share pip.Param; a fresh pip leaves theirs nil.
        local di = pip:get_field("DetailInstances")
        for i = 0, di:get_Length() - 1 do
            local d = di[i]
            if d then d:set_field("Param", param) end
        end
        native.pip, native.param, native.lock = pip, param, lock
    end)
    if not ok then
        log_msg("Native controls: build failed (" .. tostring(err) .. ") -> using Mode 2 puppeteer")
        native_release()
        native.failed = true
        return false
    end
    native.job = state.pawn_job
    native.drive = cfg.native_drive or "player"
    native.t_start = os.clock()
    log_msg("Native controls ON for " .. tostring(state.pawn_name) .. " (" .. tostring(native.pip:get_field("Detail") and native.pip:get_field("Detail"):get_type_definition():get_name()) .. ")")
    return true
end

-- 0.9.172-dev13 played pawn sprint. pawn-dash-2 (2026-11-20): Dash held on the pawn's input, the pawn's processor
-- set DashSwitch + IsDash on the press with DashTriggerKeepTime 30, and dropped both when that ran out although
-- Dash was still held; the Arisen kept sprinting on the same held Dash. app.CharacterInput has DashOptionHandle (an
-- EnumOptionHandle<app.OptionTriggerType>: Trigger 0 / Hold 1, the game's Dash option) and isConvertDashToKeepDash;
-- the pawn's own CharacterInput carries no such handle from the player's options. Give it the Arisen's.
R.dash_opt_take = function(inp)
    if not (cfg.native_dash_opt and inp and state.arisen_input) then return nil end
    local orig
    local ok, err = pcall(function()
        orig = inp:get_field("DashOptionHandle")
        local h = state.arisen_input:get_field("DashOptionHandle")
        if h then inp:set_field("DashOptionHandle", h) end
    end)
    if not ok then dev_error("dash option", err) end
    return { v = orig }
end
R.dash_opt_put = function(inp, saved)
    if not (inp and type(saved) == "table") then return end
    pcall(function() inp:set_field("DashOptionHandle", saved.v) end)
end
-- v0.9.167 hip bow skills (see the main-loop block): hold the aim flags while a played Archer's skill is in its
-- Prepare / Ready / charge stage. st keeps whether it was holding (counted once per hold).
R.hip_main = {}
R.hip_aim_hold = function(inp, chara, st)
    local _, up = R.node_names(chara) -- node_names is defined further down
    up = up or ""
    local hold = up:find("Job02_SkillAttack", 1, true) ~= nil and up:find("Cancel", 1, true) == nil
        and (up:find("Prepare", 1, true) or up:find("Ready", 1, true) or up:find("Charge", 1, true)) ~= nil
    local AIMF = (ACTION_FLAGS["AimHold"] or 0) | (ACTION_FLAGS["JobSpecialAction"] or 0)
    if hold and AIMF ~= 0 then
        local on0 = field(inp, "ButtonOnFlags") or 0
        if (on0 & AIMF) ~= AIMF then
            set_field(inp, "ButtonOnFlags", on0 | AIMF)
            if not st.on then R.hip_aim_n = (R.hip_aim_n or 0) + 1 end
        end
        st.on = true
    else
        st.on = false
    end
end
-- right before an extra played pawn's processor update (player 2's R.s2, players 3+)
R.s2_pre = function(s)
    R.dash_keep(s.input)
    if cfg.pawn_hip_skill_aim and s.job == 2 and s.input and s.chara then
        s.hip = s.hip or {}
        pcall(R.hip_aim_hold, s.input, s.chara, s.hip)
    end
end
R.dash_keep = function(inp)
    if not (cfg.native_dash_keep and inp) then return end
    local fd, fk = ACTION_FLAGS.Dash or 0, ACTION_FLAGS.KeepDash or 0
    if fd == 0 or fk == 0 then return end
    pcall(function()
        local on = inp:get_field("ButtonOnFlags") or 0
        if (on & fd) ~= 0 then inp:set_field("ButtonOnFlags", on | fk) end
    end)
end

local coop_target_tick -- v0.9.12, defined below (after native_release / native_build)
-- Returns true when the native processor handled this frame (DPC's puppeteer is then skipped).
local function native_tick()
    local pip = native.pip
    if not (cfg.native_controls and pip and not native.failed) then return false end
    if native.job ~= state.pawn_job then
        native.job = state.pawn_job
        if cfg.native_skip_thief and state.pawn_job == 4 then
            native_release()
            return false
        end
        pcall(pip.call, pip, "selectProcessor") -- vocation changed: pick that job's Detail
    end
    -- Self-check for the app.Player.update slot (see native_player_hook): fall back if it never fires or never
    -- sees the input DPC mirrored this frame.
    if native.drive == "player" then
        local age = os.clock() - native.t_start
        if age > 1.0 and native.hook_frames == 0 then
            native.drive = "pre"
            log_msg("Native controls: app.Player.update slot never fired -> driving at pre-UpdateBehavior")
        elseif native.mirror_input_frames > 120 and native.hook_input_frames == 0 then
            native.drive = "pre"
            log_msg("Native controls: input already cleared at app.Player.update -> driving at pre-UpdateBehavior")
        else
            return true -- the hook runs pip:update() this frame
        end
    end
    coop_target_tick()
    R.dash_keep(state.pawn_input)
    local ok, err = pcall(pip.call, pip, "update")
    native.frames = native.frames + 1
    if R.aim_point then R.aim_point() end
    if ok then return true end
    return false
end


-- v0.9.12 co-op auto-target. In co-op player 2's pawn gets a LockOnController of its own (so it can't steal player 1's
-- lock-on), but nothing updates that controller, so it never had a target: skills like Burst Strike and pawn shots
-- went straight ahead with no homing. Each frame, right before the pawn's processor runs, pick the best enemy
-- (nearest, weighted by how far off the pawn's facing it is) and set it as that controller's target, the same call
-- the Arisen brain uses on his own lock-on (verified live 2026-11-10). No finder is called or hooked.
-- v0.9.140 the game's own lock-on ranges, read once per vocation and kept (requested: read the ranges from the game once and keep them). app.LockOnRangeParameterList (the lock-on
-- controller's ParamList): per vocation a list of entries (Default, NormalAttack, SubNormalAttack, CustomSkill per
-- skill, Special), each with distance / angle tiers. Kept as plain numbers: the longest distance of the vocation's
-- Default and attack entries, and the longest per skill. Read live 2026-11-17: Archer default 30 m (Meteor Shot 40),
-- Mystic Spearhand default 5 m, attacks 7 - 12.5 m. Normal possession needs no number at all (the game's own search
-- runs for the pawn with these ranges); co-op's auto-target uses them in place of the fixed 15 m.
R.lock_ranges = function(job)
    R.lock_range_cache = R.lock_range_cache or {}
    local c = R.lock_range_cache[job]
    if c ~= nil then return c or nil end
    R.lock_range_cache[job] = false -- one attempt per vocation, whatever happens
    local ok, err = pcall(function()
        local lk = native.lock or state.arisen_lockon_ctrl
        local pl = lk and lk:call("get_ParamList")
        local arr = pl and pl:get_field("Parameters")
        if not arr then return end
        local function longest(tp)
            local m, rs = 0, tp:get_field("Ranges")
            if rs then
                for i = 0, rs:call("get_Length") - 1 do
                    local rg = rs:call("Get", i)
                    local d = rg:get_field("Distance")
                    if rg:get_field("IsDisable") ~= true and type(d) == "number" and d > m then m = d end
                end
            end
            return m
        end
        for i = 0, arr:call("get_Length") - 1 do
            local jp = arr:call("Get", i)
            if jp:get_field("Job") == job then
                local out = { base = 0, skill = {}, n = 0 }
                local tps = jp:get_field("Parameters")
                for k = 0, tps:call("get_Length") - 1 do
                    local tp = tps:call("Get", k)
                    if tp:get_field("IsDisable") ~= true then
                        local at, d = tp:get_field("ActionType"), longest(tp)
                        out.n = out.n + 1
                        if at == 3 then
                            local id = tp:get_field("CustomSkillID")
                            if type(id) == "number" and d > (out.skill[id] or 0) then out.skill[id] = d end
                        elseif at ~= 4 and d > out.base then
                            out.base = d
                        end
                    end
                end
                if out.base > 0 then
                    R.lock_range_cache[job] = out
                    log_msg(string.format("Lock-on ranges from the game for %s: %.1f m (%d entries)", JOB_NAMES[job] or ("job " .. tostring(job)), out.base, out.n))
                end
                return
            end
        end
    end)
    if not ok then dev_error("lock ranges", err) end
    return R.lock_range_cache[job] or nil
end
-- the longest range the played pawn can use right now: its vocation's own, or a longer one of an equipped skill
R.lock_range_now = function()
    local c = state.pawn_job and R.lock_ranges(state.pawn_job)
    if not c then return nil end
    local r = c.base
    for _, id in ipairs(state.pawn_skills or {}) do
        local d = c.skill[id]
        if d and d > r then r = d end
    end
    return r
end

R.OVERLAY_CAMS = { [0] = true, [1] = true, [2] = true, [3] = true, [5] = true, [6] = true, [7] = true, [8] = true, [9] = true, [15] = true }

-- 0.9.172-dev24: an enemy's body radius (its character controller's, capped at 8 m), cached per object
R.radius_cache = setmetatable({}, { __mode = "k" })
R.body_radius = function(e)
    local v = R.radius_cache[e]
    if v == nil then
        local ok, r = pcall(function() return e:call("get_OriginalCharaControllerRadius") end)
        v = (ok and type(r) == "number" and r > 0) and math.min(r, 8.0) or 0.0
        R.radius_cache[e] = v
    end
    return v
end

R.ta_colors = { { "Gold", 0x20B0FF }, { "Cyan", 0xFFD040 }, { "Green", 0x50E050 }, { "Magenta", 0xF050E0 },
                 { "Red", 0x4040FF }, { "White", 0xF0F0F0 } }
R.ta = { pin = nil, r3_t = nil, flick = 0, req = nil }
-- 0.9.173 (the tester: "Gold is probably the weakest one. Let's make them in order of Cyan, White, Green, Magenta, Red,
-- Gold"): the default per player and the menu order. The numbers in R.ta_colors stay as they were, because saved
-- settings store them; only the order shown and the defaults change.
R.COLOR_ORDER = { 2, 6, 3, 4, 5, 1 }
R.np_color = function(n) return R.COLOR_ORDER[n] or 1 end -- index into R.ta_colors
-- 0.9.173-dev1 (the tester: "let them each choose a color there and match it to their target circle/bookmark"): one colour
-- per player drives their target dot, their join / kept glow and Camera Distance's off-screen marker. Players 1 and 2
-- keep the marker-colour settings they already had; players 3+ are in cfg.coop_colors["p<n>"].
R.player_color = function(n)
    local v
    if n == 1 then v = cfg.coop_aim_p1_color elseif n == 2 then v = cfg.coop_aim_p2_color
    else v = (cfg.coop_colors or {})["p" .. n] end
    v = math.tointeger(tonumber(v) or 0)
    if not v or not R.ta_colors[v] then v = R.np_color(n) end
    return v
end
R.set_player_color = function(n, v)
    if n == 1 then cfg.coop_aim_p1_color = v elseif n == 2 then cfg.coop_aim_p2_color = v
    else cfg.coop_colors = cfg.coop_colors or {}; cfg.coop_colors["p" .. n] = v end
end
R.player_abgr = function(n) return 0xFF000000 | R.ta_colors[R.player_color(n)][2] end
-- The game's rim lights come in fixed colours: each marker colour gets the closest one. White: Counterslash, "a perfect
-- white" and steady (the tester, white-glow-2, 2026-11-22). Tried before: AstralBody (not white), RimLightInteractGimmic
-- (white but flashing, too much for co-op). The Preview button in the settings shows each one.
R.COLOR_GLOWS = { [1] = "RimLightInteractLarge", [2] = "AstralPlayer", [3] = "ChRecovery", [4] = "RimLightSummon",
                  [5] = "Berserker", [6] = "Counterslash" }
R.player_glow = function(n) return R.COLOR_GLOWS[R.player_color(n)] or "AstralPlayer" end
R.ta_note = function(text) R.note = { text = text, t_end = os.clock() + 1.5 } end
R.ta_p1_target = function()
    local c = nil
    pcall(function()
        local t = state.arisen_lockon_ctrl and state.arisen_lockon_ctrl:call("get_Target")
        c = t and t:call("get_Character")
    end)
    if c and brain_alive(c) then return c end
    return nil
end
R.ta_p2_input = function(btn, pv)
    local a = R.ta
    local r3 = pv.RStickPush or 0x2000
    local now = os.clock()
    if (btn & r3) ~= 0 then
        if not a.r3_t then a.r3_t, a.r3_long = now, false end
        if not a.r3_long and now - a.r3_t >= 0.6 then a.r3_long = true; a.req = "p1" end
    elseif a.r3_t then
        if not a.r3_long then a.req = "toggle" end
        a.r3_t = nil
    end
    local rx, ry = pad_stick_rx or 0.0, pad_stick_ry or 0.0
    if cfg.coop_aim_flick == "quick" then
        if a.flick == 0 then
            if not state.is_aiming and math.abs(rx) > 0.7 and math.abs(rx) > math.abs(ry) * 1.2 then
                a.flick = rx > 0 and 1 or -1
                a.req = a.flick > 0 and "right" or "left"
            end
        elseif math.abs(rx) < 0.3 then
            a.flick = 0
        end
        return btn & ~r3
    end
    -- 0.9.172 (the tester: "the ring didn't seem to prevent changing target with right stick"): a deliberate flick only.
    -- From rest, the stick reaches near-full sideways within 0.2 s, then comes back to rest within 0.5 s; the switch
    -- happens on the way back. Resting a thumb on the stick, a slow push or holding it out does nothing.
    -- dev11: coop-aim-2 counted flicks in pairs 0.2 - 0.4 s apart: the stick springs back past centre and the
    -- rebound read as a second flick. A new flick now needs the stick at rest for 0.12 s first, and none starts
    -- within 0.3 s of the last one.
    local d = R.flick_step(a, rx, ry, now)
    if d and not state.is_aiming then a.req = d > 0 and "right" or "left" end
    return btn & ~r3
end
-- 0.9.172-dev20: the deliberate-flick detector (was inline for player 2), shared with player 1. State a; returns
-- 1 / -1 on the frame a flick completes (stick back at rest), else nil.
R.flick_step = function(a, rx, ry, now)
    local m = math.sqrt(rx * rx + ry * ry)
    local out = nil
    if m < 0.3 then
        if a.fl_t0 and a.fl_hit and now - (a.fl_hit_t or 0) <= 0.5 then
            out = a.fl_dir
            a.flick_n = (a.flick_n or 0) + 1
            a.fl_last = now
        end
        if a.fl_t0 or not a.fl_rest then a.fl_rest = now end
        a.fl_t0, a.fl_hit, a.fl_dir = nil, false, 0
    else
        local ready = a.fl_rest and now - a.fl_rest >= 0.12 and now - (a.fl_last or -10) >= 0.3
        if not a.fl_t0 then a.fl_t0, a.fl_hit, a.fl_dir, a.fl_ok = now, false, 0, ready end
        if not a.fl_ok then a.fl_rest = nil end
        if a.fl_ok and not a.fl_hit and math.abs(rx) >= 0.85 and math.abs(rx) > math.abs(ry) * 1.5 then
            if now - a.fl_t0 <= 0.2 then
                a.fl_hit, a.fl_hit_t, a.fl_dir = true, now, (rx > 0) and 1 or -1
            end
        end
        if a.fl_hit and (rx > 0 and 1 or -1) ~= a.fl_dir and math.abs(rx) > 0.5 then a.fl_hit = false end -- swung through
    end
    return out
end
-- 0.9.172-dev20: camera share of a right stick when flicks are targeting: nothing for the first 0.12 s after it
-- leaves rest, and nothing at all for a push that reaches full sideways within 0.2 s (a flick) until it is back at
-- rest. A slow push turns the camera after that short delay.
R.cam_gate = function(g, rx, ry, now)
    if math.sqrt(rx * rx + ry * ry) < 0.3 then g.t0, g.fl = nil, false; return 0.0, 0.0 end
    if not g.t0 then g.t0, g.fl = now, false end
    if not g.fl and math.abs(rx) >= 0.85 and now - g.t0 <= 0.2 then g.fl = true end
    if g.fl or now - g.t0 < 0.12 then return 0.0, 0.0 end
    return rx, ry
end
R.ta_sx = function(c)
    local ok, sp = pcall(draw.world_to_screen, Vector3f.new(c.x, c.y + 1.2, c.z))
    if ok and sp then return sp.x end
    return nil
end
R.ta_resolve = function(req, best, bd, cands)
    local a = R.ta
    local function find(ch)
        for _, c in ipairs(cands) do if same_obj(c.e, ch) then return c end end
        return nil
    end
    if req == "toggle" then
        if a.pin then
            a.pin = nil
            R.ta_note("Player 2: automatic target")
        else
            a.pin = coop.tgt or best
            if a.pin then R.ta_note("Player 2: target kept") end
        end
    elseif req == "p1" then
        local t = R.ta.p1 or R.ta_p1_target()
        if t and find(t) then
            a.pin = t
            R.ta_note("Player 2: same target as player 1")
        else
            R.ta_note("Player 1 has no target in range")
        end
    elseif req == "left" or req == "right" then
        local cur = find(a.pin or coop.tgt)
        local ds = imgui.get_display_size()
        local cx = (cur and R.ta_sx(cur)) or (ds and ds.x * 0.5) or 960
        local pick, gap = nil, nil
        for _, c in ipairs(cands) do
            if not (cur and same_obj(c.e, cur.e)) then
                local sx = R.ta_sx(c)
                if sx then
                    local dx = sx - cx
                    if (req == "right" and dx > 1) or (req == "left" and dx < -1) then
                        if not gap or math.abs(dx) < gap then pick, gap = c, math.abs(dx) end
                    end
                end
            end
        end
        if pick then a.pin = pick.e end
    end
    if a.pin then
        local c = find(a.pin)
        if c and brain_alive(a.pin) then return a.pin, c.d end
        a.pin = nil
    end
    return best, bd
end
R.ta_bones = { "Spine_2", "Spine_1", "Spine_0", "Hip" }
R.ta_joints, R.ta_last = {}, {}
R.ta_screen = function(ch)
    local okad, a = pcall(ch.get_address, ch)
    if not okad then return nil end
    local now = os.clock()
    local x, y
    pcall(function()
        local tf = ch:call("get_Transform")
        local body = tf:call("get_Position")
        if not body then return end
        local j = R.ta_joints[a]
        if j == nil then
            j = false
            for _, bn in ipairs(R.ta_bones) do
                local okj, jj = pcall(tf.call, tf, "getJointByName(System.String)", bn)
                if okj and jj then j = jj; break end
            end
            R.ta_joints[a] = j
        end
        local px, py, pz = body.x, body.y + 1.2, body.z
        if j then
            local okp, jp = pcall(j.call, j, "get_Position")
            if okp and jp then
                local dx, dy, dz = jp.x - body.x, jp.y - body.y, jp.z - body.z
                if dx * dx + dy * dy + dz * dz < 144 then px, py, pz = jp.x, jp.y, jp.z else R.ta_joints[a] = nil end
            end
        end
        local sp = draw.world_to_screen(Vector3f.new(px, py, pz))
        if sp then x, y = sp.x, sp.y end
    end)
    if x then
        R.ta_last[a] = { x = x, y = y, t = now }
        return x, y
    end
    local l = R.ta_last[a]
    if l and now - l.t < 0.4 then return l.x, l.y end
    return nil
end
R.ta_calc = function() end
R.ta_draw = function(hh)
    R.ta_dbg = nil
    if not (cfg.coop_aim and cfg.coop_aim_markers and coop.active and state.active) then return end
    local t1 = R.ta.p1 or R.ta_p1_target()
    local t2 = coop.tgt
    if t2 and not brain_alive(t2) then t2 = nil end
    local same = t1 and t2 and same_obj(t1, t2)
    local k = hh / 2160.0 * (cfg.coop_aim_size or 1.0)
    local r = 13.0 * k
    local drawn = 0
    local function dot(ch, colix, dx, pin)
        local x, y = R.ta_screen(ch)
        if not x then return end
        local c = (R.ta_colors[colix or 1] or R.ta_colors[1])[2]
        x, y = x + dx * k, y - 70.0 * k
        draw.filled_circle(x, y, r + 3.0 * k, 0xD0000000, 20)
        draw.filled_circle(x, y, r, 0xF0000000 | c, 20)
        draw.filled_circle(x, y, r * 0.35, 0xF0FFFFFF, 12)
        if pin then
            draw.outline_circle(x, y, r + 7.0 * k, 0xD0000000, 24)
            draw.outline_circle(x, y, r + 6.0 * k, 0xF0000000 | c, 24)
        end
        drawn = drawn + 1
    end
    -- 0.9.172-dev36: players 3+ get their dots too (P3 green, P4 magenta, P5 red, then white); dots on the same
    -- enemy sit side by side
    local list = {}
    if t1 then list[#list + 1] = { t1, R.player_color(1), false } end
    if t2 then list[#list + 1] = { t2, R.player_color(R.s2 and R.s2.active and R.s2.player or 2), R.ta.pin ~= nil } end
    for n, sl in pairs(R.np and R.np.slots or {}) do
        if sl.active and sl.tgt and brain_alive(sl.tgt) then list[#list + 1] = { sl.tgt, R.player_color(n), sl.pin ~= nil } end
    end
    local per = {}
    for _, it in ipairs(list) do
        local a = it[1]:get_address()
        per[a] = (per[a] or 0) + 1
        it[4] = per[a]
    end
    for _, it in ipairs(list) do
        local cnt = per[it[1]:get_address()]
        dot(it[1], it[2], (it[4] - (cnt + 1) * 0.5) * 36, it[3])
    end
    R.ta_dbg = string.format("aim: P1 %s | P2 %s%s | dots %d", t1 and "locked" or "none",
        t2 and tostring(coop.tgt_name or "?") or "none", R.ta.pin and " (kept)" or "", drawn)
end

R.ta_p1_pick = function()
    local ds = imgui.get_display_size()
    local cx, cy = (ds and ds.x or 1920) * 0.5, (ds and ds.y or 1080) * 0.5
    local ax, _, az = brain_pos(state.arisen_chara)
    if not ax then return nil end
    local best, bs, cur_sc = nil, nil, nil
    local em = sdk.get_managed_singleton("app.EnemyManager")
    local arr = em and call(em, "getAllEnemies")
    local n = arr and call(arr, "get_Count") or 0
    for i = 0, n - 1 do
        local ok, e = pcall(function() return arr[i]:get_field("_Chara") end)
        if ok and e and brain_alive(e) then
            local ex, ey, ez = brain_pos(e)
            if ex and (ex - ax) ^ 2 + (ez - az) ^ 2 <= 45.0 ^ 2 then
                local oks, sp = pcall(draw.world_to_screen, Vector3f.new(ex, ey + 1.2, ez))
                if oks and sp and sp.x > 0 and sp.y > 0 and sp.x < cx * 2 and sp.y < cy * 2 then
                    local sc = (sp.x - cx) ^ 2 + (sp.y - cy) ^ 2
                    if R.ta.p1 and same_obj(e, R.ta.p1) then cur_sc = sc end
                    if not bs or sc < bs then best, bs = e, sc end
                end
            end
        end
    end
    -- 0.9.172-dev11: R3 "on the same goblin" picked its neighbour in coop-aim-2 (goblins 2.5 m apart), so the target
    -- never released. The current target counts as picked when it is nearly as central as the best one, or within
    -- 12 % of the screen height of the centre.
    if cur_sc and bs and (cur_sc <= bs * 2.25 or cur_sc <= (cy * 0.24) ^ 2) then return R.ta.p1 end
    return best
end
R.ta_p1_side = function(dir)
    local ds = imgui.get_display_size()
    local w = ds and ds.x or 1920
    local ax, _, az = brain_pos(state.arisen_chara)
    if not ax then return nil end
    local cx = w * 0.5
    if R.ta.p1 then
        local x, y, z = brain_pos(R.ta.p1)
        local sx = x and R.ta_sx({ x = x, y = y, z = z })
        if sx then cx = sx end
    end
    local best, gap = nil, nil
    local em = sdk.get_managed_singleton("app.EnemyManager")
    local arr = em and call(em, "getAllEnemies")
    local n = arr and call(arr, "get_Count") or 0
    for i = 0, n - 1 do
        local ok, e = pcall(function() return arr[i]:get_field("_Chara") end)
        if ok and e and brain_alive(e) and not (R.ta.p1 and same_obj(e, R.ta.p1)) then
            local ex, ey, ez = brain_pos(e)
            if ex and (ex - ax) ^ 2 + (ez - az) ^ 2 <= 45.0 ^ 2 then
                local sx = R.ta_sx({ x = ex, y = ey, z = ez })
                if sx and sx > 0 and sx < w then
                    local dx = sx - cx
                    if (dir > 0 and dx > 1) or (dir < 0 and dx < -1) then
                        if not gap or math.abs(dx) < gap then best, gap = e, math.abs(dx) end
                    end
                end
            end
        end
    end
    return best
end
R.ta_p1_release = function()
    local t = R.ta
    if t.p1_set and state.arisen_lockon_ctrl then
        pcall(function()
            if t.p1_work then state.arisen_lockon_ctrl:call(REMOVE_TARGET_SIG, t.p1_work) end
            state.arisen_lockon_ctrl:call("clearLockOn")
        end)
    end
    t.p1, t.p1_work, t.p1_set = nil, nil, false
end
R.ta_p1_tick = function()
    local t = R.ta
    if not (coop.active and cfg.coop_aim and cfg.coop_aim_p1 and state.arisen_chara) then
        if t.p1 or t.p1_set then R.ta_p1_release() end
        return
    end
    if t.p1_frame == os.clock() then return end
    t.p1_frame = os.clock()
    local pv = (R.pad_values and R.pad_values() or {})
    local r3 = pv.RStickPush or 0x2000
    local down = R.tp_on() and (R.tp_p1().b & r3) ~= 0 or false
    if not down then down = is_key_down_safe(0x04) == true end
    local edge = down and not t.p1_was
    t.p1_was = down
    if t.p1 and not brain_alive(t.p1) then R.ta_p1_release() end
    if t.p1 then
        local ax, _, az = brain_pos(state.arisen_chara)
        local ex, _, ez = brain_pos(t.p1)
        if not (ax and ex) or (ex - ax) ^ 2 + (ez - az) ^ 2 > 60.0 ^ 2 then R.ta_p1_release() end
    end
    -- 0.9.172-dev20: player 1 flicks like player 2 (next enemy on that side of his current target, or of the screen
    -- centre). With coop_cam_turn "p1" only while he has a target (his stick is the camera otherwise).
    if R.tp_on() and cfg.coop_aim_p1_flick ~= false then
        local p = R.tp_p1()
        t.f1 = t.f1 or {}
        local d = R.flick_step(t.f1, p.rx or 0.0, p.ry or 0.0, os.clock())
        if d and ((cfg.coop_cam_turn or "p1") ~= "p1" or t.p1) then
            local pick = R.ta_p1_side(d)
            if pick then
                R.ta_p1_release()
                t.p1 = pick
                pcall(function() t.p1_work = pick:call("get_LockOnTarget"):call("get_work") end)
                R.ta_note("Player 1: next target")
            end
        end
    end
    if edge then
        local pick = R.ta_p1_pick()
        if not pick or (t.p1 and same_obj(pick, t.p1)) then
            local had = t.p1 ~= nil
            R.ta_p1_release()
            if had then R.ta_note("Player 1: target released") end
        else
            R.ta_p1_release()
            t.p1 = pick
            pcall(function() t.p1_work = pick:call("get_LockOnTarget"):call("get_work") end)
            R.ta_note("Player 1: target")
        end
    end
    -- 0.9.172: the Arisen's lock-on only while player 1 fights (a button other than sprint, or a mouse button,
    -- within the last second). Held all the time, the game's lock-on turned "up" into "toward the target": in
    -- coop-aim-1 the Arisen walked off screen toward a goblin while the tester pushed up. The marker stays regardless.
    local fighting = false
    pcall(function()
        local b = (R.tp_on() and R.tp_p1().b) or pad_buttons or 0
        -- 0.9.172-dev11: face buttons and shoulders / triggers only. coop-aim-2 showed the lock-on held while only
        -- walking: the merged pad word also carries the stick as Emu* direction bits (EmuLup 0x100000 ...) and the d-pad.
        b = b & ((pv.RUp or 0x10) | (pv.RDown or 0x20) | (pv.RLeft or 0x40) | (pv.RRight or 0x80)
            | (pv.LTrigTop or 0x100) | (pv.LTrigBottom or 0x200) | (pv.RTrigTop or 0x400) | (pv.RTrigBottom or 0x800))
        if b ~= 0 or is_key_down_safe(0x01) or is_key_down_safe(0x02) then t.p1_fight_t = os.clock() end
        fighting = os.clock() - (t.p1_fight_t or -10) < (cfg.coop_aim_p1_assist_secs or 1.0)
    end)
    if t.p1 and t.p1_work and cfg.coop_aim_p1_assist and state.arisen_lockon_ctrl and (fighting or cfg.coop_aim_p1_assist_always) then
        local ok = pcall(function()
            state.arisen_lockon_ctrl:call(SET_TARGET_SIG, t.p1_work, false, false)
            state.arisen_lockon_ctrl:call("setAimTargetInfoToCharacter")
        end)
        t.p1_set = ok
    elseif t.p1_set and state.arisen_lockon_ctrl then
        pcall(function()
            if t.p1_work then state.arisen_lockon_ctrl:call(REMOVE_TARGET_SIG, t.p1_work) end
            state.arisen_lockon_ctrl:call("clearLockOn")
        end)
        t.p1_set = false
    end
end

coop_target_tick = function()
    pcall(R.ta_p1_tick)
    if not (coop.active and cfg.coop_auto_target and native.lock and state.pawn_chara) then return end
    if state.pawn_job == 4 and not cfg.coop_target_thief then return end
    local lk, pw = native.lock, state.pawn_chara
    if state.arisen_lockon_ctrl and same_obj(lk, state.arisen_lockon_ctrl) then return end -- never player 1's
    local now = os.clock()
    local areq = cfg.coop_aim and R.ta.req
    if areq then R.ta.req = nil; coop.tgt_next = 0 end
    if now >= (coop.tgt_next or 0) then
        coop.tgt_next = now + 0.1
        local px, _, pz = brain_pos(pw)
        if not px then return end
        local face = brain_facing(pw)
        local r, cone = cfg.coop_target_range or 15.0, math.rad(cfg.coop_target_cone or 75.0)
        if cfg.coop_target_game_ranges then r = R.lock_range_now() or r end
        coop.tgt_range = r
        local best, bs, bd = nil, nil, nil
        local cands = {}
        local em = sdk.get_managed_singleton("app.EnemyManager")
        local arr = em and call(em, "getAllEnemies")
        local n = arr and call(arr, "get_Count") or 0
        for i = 0, n - 1 do
            local ok, e = pcall(function() return arr[i]:get_field("_Chara") end)
            if ok and e and brain_alive(e) then
                local ex, ey, ez = brain_pos(e)
                if ex then
                    -- 0.9.172-dev24: measured to the body's edge, not its centre: coop-climb-2 had no automatic target
                    -- on a cyclops right next to player 2 (its centre is metres inside it) until he was very close
                    local dc = math.sqrt((ex - px) ^ 2 + (ez - pz) ^ 2)
                    local rad = R.body_radius(e)
                    local d = math.max(0.0, dc - rad)
                    -- 0.9.172-dev15: kept / flick targets come from this list. At r * 1.5 a short-range vocation (5 m
                    -- lock-on) lost its kept goblin 9 - 13 m away the moment it moved (coop-aim-3: the ring jumped to
                    -- the nearest enemy). Kept and flicked targets may be up to coop_aim_keep_range away.
                    local cr = r * 1.5
                    if cfg.coop_aim then cr = math.max(cr, cfg.coop_aim_keep_range or 30.0) end
                    if d <= cr then cands[#cands + 1] = { e = e, x = ex, y = ey, z = ez, d = d } end
                    local off = math.abs(brain_angdiff(math.atan(ex - px, ez - pz), face))
                    -- dev25: a big body fills more of the view: the cone counts from its nearest edge
                    if rad > 0.0 then off = math.max(0.0, off - math.atan(rad, math.max(dc, 0.1))) end
                    local keep = same_obj(e, coop.tgt) and 0.7 or 1.0 -- stickiness: don't flick between two enemies
                    if d <= r and (off <= cone or d <= 5.0) then
                        local score = d * (1.0 + off / math.pi * 2.0) * keep
                        if not bs or score < bs then best, bs, bd = e, score, d end
                    end
                end
            end
        end
        -- 0.9.172: the automatic target stays a moment after leaving the pawn's view cone (it turned to attack): the
        -- marker blinked off and on in coop-aim-1 (0.1-0.2 s gaps)
        if not best and coop.tgt and brain_alive(coop.tgt) then
            local held = nil
            for _, c in ipairs(cands) do if same_obj(c.e, coop.tgt) then held = c end end
            if held and held.d <= r * 1.2 then
                -- dev25: the markers "popped in and out" on a cyclops (coop-climb-2): the automatic target was dropped
                -- 0.6 s after the archer turned away to shoot or move. It now stays while it is in range and not
                -- behind her (within 150 degrees of where she faces), and coop_target_grace (1.5 s) more when behind.
                local off = math.abs(brain_angdiff(math.atan(held.x - px, held.z - pz), face))
                if off <= math.rad(150) then
                    best, bd = coop.tgt, held.d
                    coop.tgt_miss_t = nil
                else
                    coop.tgt_miss_t = coop.tgt_miss_t or now
                    if now - coop.tgt_miss_t < (cfg.coop_target_grace or 1.5) then best, bd = coop.tgt, held.d end
                end
            end
        else
            coop.tgt_miss_t = nil
        end
        if cfg.coop_aim then best, bd = R.ta_resolve(areq, best, bd, cands) end
        if not same_obj(best, coop.tgt) then
            coop.tgt, coop.tgt_work = best, nil
            if best then pcall(function() coop.tgt_work = best:call("get_LockOnTarget"):call("get_work") end) end
            coop.tgt_name = best and tostring(call(best, "get_CharaIDString")) or nil
            coop.tgt_dist = bd
            if coop.tgt_set and not best then
                pcall(lk.call, lk, "clearLockOn")
                coop.tgt_set = false
            end
        end
        coop.tgt_dist = bd
        if now >= (coop.tgt_status_t or 0) then coop.tgt_status_t = now + 0.5; coop.tgt_status_due = true end
    end
    if coop.tgt_work then
        local ok, err = pcall(function()
            lk:call(SET_TARGET_SIG, coop.tgt_work, false, false)
            lk:call("setAimTargetInfoToCharacter")
        end)
        if ok then
            coop.tgt_set = true
            coop.tgt_sets = (coop.tgt_sets or 0) + 1
        else
            coop.tgt_errs = (coop.tgt_errs or 0) + 1
            dev_error("co-op target", err)
            if coop.tgt_errs >= 20 then cfg.coop_auto_target = false; dev_error("co-op target", "20 errors -> off") end
        end
    end
end

-- v0.9.14 quick skills: Numpad 1-6 make the selected pawn (the one F6 would possess) use skill slot 1-6 while
-- nobody is possessed. HumanActionSelector.requestCustomSkill does nothing on an AI pawn (bridge test
-- 2026-11-14: 1.5 s of requests, AI off, no change), so this hands the pawn's AI the skill's own action pack
-- with a target (bridge test: Blink Strike started 0.47 s after the request). Ordering a pawn skill this way is
-- the idea of the mod Pawn Tactical Wheel, whose table got this feature started; it is credited in the README.
-- v0.9.115: that borrowed table is gone. Which action pack belongs to which skill is read from the game itself
-- (quick.game_table below), so nothing about it ships with the mod.
local quick = { packs = {}, n = 0, last = nil, holds = {} }

-- v0.9.115 the game's own skill table. Every pawn's AI planner (app.goalplanning.AIGoalPlanning) points at the
-- same game asset, AppSystem/AI/GoalPlanning/CustomSkillDecisionRefData.user: one entry per weapon skill
-- (82, all six pawn vocations), each a list of decision packs whose decisions carry the skill ids they are for
-- (_HumanCustomSkillIDs), the action pack (_ActInterPack) and the kind of target (_Target, AITargetFlag: My 1,
-- Player 2, Enemy 4, Gimmick 16, Party 64). Found and read with the bridge on 2026-11-17 (dev/bridge/skills/
-- hv8, hv9). A skill usually has several packs (on a ledge, while climbing, charged, for one quest NPC ...);
-- the plain one is taken: file name contains the skill's own enum name, no situational marker, shortest name.
quick.SITUATIONAL = { "_npc", "_ch%d", "_gm%d", "cnt%d", "quest", "climb", "_spot", "_air", "_break", "_tired",
    "combo", "_multiple", "_concentrate", "_charged", "keepdistance", "_release", "_ground", "_around", "jumpatt",
    "gimmick", "_ex$", "_ex_", "_lv2", "_lvex", "_nrd", "neutral", "^common/", "^grimoire/", "^npc/", "^ch%d" }

function quick.elems(x)
    if not x then return {} end
    local ok, e = pcall(x.get_elements, x)
    return (ok and e) or {}
end

-- reads the asset once: quick.rows[skill id] = { { rel, file, flag, named, obj }, ... }
function quick.game_rows()
    if quick.rows then return quick.rows end
    local now = os.clock()
    if quick.rows_try_t and now - quick.rows_try_t < 5.0 then return nil end
    quick.rows_try_t = now
    local rows, n = {}, 0
    local ok, err = pcall(function()
        local gp_t = sdk.typeof("app.goalplanning.AIGoalPlanning")
        local cs = nil
        for _, e in ipairs(get_party()) do
            local go = e.chara and e.chara:call("get_GameObject")
            local gp = go and go:call("getComponent(System.Type)", gp_t)
            local gd = gp and gp:get_field("_AIGoalData")
            cs = gd and gd:get_field("_CSDecisions")
            if cs then break end
        end
        if not cs then return end
        for _, set in ipairs(quick.elems(cs:get_field("_CustomSkillDecisions"))) do
            local sid = set:get_field("_SKillID")
            if type(sid) == "number" then
                local list = rows[sid] or {}
                rows[sid] = list
                for _, pack in ipairs(quick.elems(set:get_field("_DecisionPackList"))) do
                    for _, d in ipairs(quick.elems(pack and pack:get_field("_Decisions"))) do
                        local ap = d:get_field("_ActInterPack")
                        local path = ap and ap:call("get_Path")
                        if path then
                            path = tostring(path)
                            local named = false
                            for _, v in ipairs(quick.elems(d:get_field("_HumanCustomSkillIDs"))) do
                                local x = (type(v) == "userdata") and v:get_field("value__") or v
                                if x == sid then named = true end
                            end
                            local rel = path:lower():gsub("\\", "/"):gsub("^.*actinterpackdata/", ""):gsub("%.user$", "")
                            list[#list + 1] = { path = path, rel = rel, file = rel:match("([^/]+)$") or rel,
                                flag = tonumber(d:get_field("_Target")) or 0, named = named, obj = ap }
                            n = n + 1
                        end
                    end
                end
            end
        end
    end)
    if not ok then dev_error("quick skill table", err); return nil end
    if n == 0 then return nil end
    quick.rows, quick.defs = rows, {}
    log_msg(string.format("Quick skills: read the game's skill table (%d action packs)", n))
    if R.dev then
        local out = {}
        for id in pairs(rows) do
            local d = quick.table_def(id)
            out[tostring(id)] = d and { name = SKILL_NAMES[id], pack = d.path, kind = d.kind, alt = d.alt, flag = d.flag, how = d.how } or { name = SKILL_NAMES[id], pack = false }
        end
        R.dump("DPC_skill_table.json", { note = "Read from the game: CustomSkillDecisionRefData.user", rows = n, skills = out }, 2)
    end
    return rows
end

function quick.situational(rel)
    for _, pat in ipairs(quick.SITUATIONAL) do if rel:find(pat) then return true end end
    return false
end

-- the plain action pack of one skill: { path, obj, flag, kind, alt, how } or nil
function quick.table_def(id)
    local rows = quick.game_rows()
    if not rows then return nil end
    if quick.defs[id] ~= nil then return quick.defs[id] or nil end
    local set = rows[id] or {}
    local name = SKILL_NAMES and SKILL_NAMES[id]
    name = (type(name) == "string" and name ~= "") and name:lower() or nil
    local cand, how = {}, "name"
    if name then for _, r in ipairs(set) do if r.file:find(name, 1, true) then cand[#cand + 1] = r end end end
    if #cand == 0 then how = "named"; for _, r in ipairs(set) do if r.named then cand[#cand + 1] = r end end end
    if #cand == 0 and name then
        how = "other entry"
        for _, s2 in pairs(rows) do for _, r in ipairs(s2) do if r.file:find(name, 1, true) then cand[#cand + 1] = r end end end
    end
    if #cand == 0 then
        local distinct, k = {}, 0
        for _, r in ipairs(set) do if not distinct[r.rel] then distinct[r.rel] = true; k = k + 1 end end
        if k >= 1 and k <= 6 then how = "only packs"; cand = set end
    end
    if #cand == 0 then quick.defs[id] = false; return nil end
    local plain = {}
    for _, r in ipairs(cand) do if not quick.situational(r.rel) then plain[#plain + 1] = r end end
    if #plain > 0 then cand = plain end
    local best = nil
    for _, r in ipairs(cand) do
        if not best or #r.rel < #best.rel or (#r.rel == #best.rel and r.rel < best.rel) then best = r end
    end
    local f = 0
    for _, r in ipairs(cand) do if r.rel == best.rel then f = f | r.flag end end
    local d = { path = best.path, obj = best.obj, flag = f, how = how }
    if (f & 4) ~= 0 or (f & 67) == 0 then
        d.kind = "enemy"
        -- the game also uses it without an enemy: on the pawn itself, or on an ally
        if (f & 1) ~= 0 then d.alt = "self" elseif (f & 66) ~= 0 then d.alt = "player" end
    elseif (f & 66) ~= 0 then d.kind = "player" else d.kind = "self" end
    quick.defs[id] = d
    return d
end

local function quick_arisen()
    local cm = sdk.get_managed_singleton("app.CharacterManager")
    return cm and call(cm, "get_ManualPlayer")
end

-- The enemy the player means: the Arisen's lock-on target, else the enemy nearest the middle of the screen
-- (within 35 deg and 45 m of the camera), else the enemy nearest the pawn within 25 m.
local function quick_pick_enemy(pawn)
    local ar = quick_arisen()
    local okl, locked = pcall(function()
        local pl = ar:get_GameObject():call("getComponent(System.Type)", sdk.typeof("app.Player"))
        local t = pl and pl:call("get_LockOnCtrl"):call("get_Target")
        return t and t:call("get_Character")
    end)
    if okl and locked and brain_alive(locked) then return locked, "lock-on" end
    local em = sdk.get_managed_singleton("app.EnemyManager")
    local arr = em and call(em, "getAllEnemies")
    local n = arr and call(arr, "get_Count") or 0
    local cx, cy, cz, fx, fy, fz
    pcall(function()
        local tr = sdk.get_primary_camera():call("get_GameObject"):call("get_Transform")
        local p, q = tr:call("get_Position"), tr:call("get_Rotation")
        cx, cy, cz = p.x, p.y, p.z
        fx, fy, fz = -2.0 * (q.x * q.z + q.w * q.y), -2.0 * (q.y * q.z - q.w * q.x), -(1.0 - 2.0 * (q.x * q.x + q.y * q.y))
    end)
    local px, _, pz = brain_pos(pawn)
    local best, bs, near, nd = nil, nil, nil, nil
    for i = 0, n - 1 do
        local ok, e = pcall(function() return arr[i]:get_field("_Chara") end)
        if ok and e and brain_alive(e) then
            local ex, ey, ez = brain_pos(e)
            if ex and cx then
                local vx, vy, vz = ex - cx, (ey + 1.0) - cy, ez - cz
                local d = math.sqrt(vx * vx + vy * vy + vz * vz)
                if d > 0.1 and d < 45.0 then
                    local c = (vx * fx + vy * fy + vz * fz) / d
                    local off = math.deg(math.acos(math.max(-1.0, math.min(1.0, c))))
                    if off < 35.0 then
                        local score = off + d * 0.5
                        if not bs or score < bs then best, bs = e, score end
                    end
                end
            end
            if ex and px then
                local dp = math.sqrt((ex - px) ^ 2 + (ez - pz) ^ 2)
                if dp < 25.0 and (not nd or dp < nd) then near, nd = e, dp end
            end
        end
    end
    if best then return best, "screen" end
    if near then return near, "nearest" end
    return nil, nil
end

-- The pawn's own blackboard entry for the target (it carries weak points / body parts), else a fresh one.
local function quick_ai_target(pawn, tgt)
    local found = nil
    pcall(function()
        local bb = call(pawn, "get_AIBlackBoardController")
        local list = bb and bb:call("getTargetsOfType(app.AIDecisionDefine.AITargetFlag, app.ActionTargetUniqueTypeFlag, app.AIDecisionDefine.AIPositionFlag)", 8, 0, 0)
        local cnt = list and (tonumber(list:call("get_Count")) or 0) or 0
        local by = -1e9
        for i = 0, cnt - 1 do
            local at = list:call("get_Item", i)
            local oc = at and (at:get_field("<OwnerCharacter>k__BackingField") or at:get_field("<Character>k__BackingField"))
            if oc and same_obj(oc, tgt) then
                local y = 0
                pcall(function() y = at:get_field("<Transform>k__BackingField"):call("get_Position").y end)
                if not found or y > by then found, by = at, y end
            end
        end
    end)
    if found then return found end
    local at = sdk.create_instance("app.AITargetGameObject", true)
    if not at then return nil end
    at["<GameObject>k__BackingField"] = tgt:get_GameObject()
    at["<Character>k__BackingField"] = tgt
    at["<Owner>k__BackingField"] = tgt:get_GameObject()
    at["<OwnerCharacter>k__BackingField"] = tgt
    at["<ContextHolder>k__BackingField"] = tgt:get_Context()
    at["<Transform>k__BackingField"] = tgt:get_Transform()
    return at
end

-- v0.9.17: ask the pawn's own AI first. In battle it holds, for each equipped skill, decisions that name the
-- skill (AIDecision.HumanCustomSkillIDs), its action pack and the kind of target. Verified live 2026-11-15 on a
-- Fighter, a Thief and a Mage. Out of battle (or for a skill with no such decision) the game's table above is used.
function quick.game_def(pw, id)
    local best = nil
    pcall(function()
        local dm = pw:get_field("<AIDecisionMaker>k__BackingField")
        local list = dm:call("get_DecisionModule"):get_field("<MainDecisions>k__BackingField")
        local n = list:call("get_Count")
        for i = 0, n - 1 do
            local d = list:call("get_Item", i)
            local ids = d and d:get_field("<HumanCustomSkillIDs>k__BackingField")
            local hit = false
            if ids then
                for _, v in ipairs(ids:get_elements()) do
                    local x = (type(v) == "userdata") and v:get_field("value__") or v
                    if x == id then hit = true end
                end
            end
            if hit then
                local ap = d:get_field("<ActionPack>k__BackingField")
                local path = ap and tostring(ap:call("get_Path"))
                -- several variants can exist (e.g. _Ex, _COMEPL, _02): take the plainest (shortest) name
                if path and (not best or #path < #best.path) then
                    best = { obj = ap, path = path, flag = d:get_field("<Target>k__BackingField") or 0 }
                end
            end
        end
    end)
    if not best then return nil end
    local f = best.flag
    best.kind = ((f & 4) ~= 0) and "enemy" or ((((f & 2) ~= 0) or ((f & 64) ~= 0)) and "player" or "self")
    return best
end

-- v0.9.151 an ordered skill is kept. The order (blackboard values + ReqMainActInterPackData) was only a request:
-- the pawn's own decision maker stayed on and replaced it at its next evaluation, so a Fighter's Launchboard was
-- dropped almost at once. Pawn Tactical Wheel gives the same order and holds far longer; read in its script
-- (ai_engine.lua, fire_order): after the order it switches the pawn's AIDecisionMaker off (set_Enabled(false)) until
-- the action is over. The same is done here: decision maker off after the order, on again when the pawn's action
-- nodes are back at plain locomotion, when the action never started (2.5 s), at a time limit (8 s; 20 s for the
-- launch stances, skills 5 and 60), when the pawn goes down, is taken over, co-op starts, or scripts are reset.
-- Ordering a launch stance again while it is held ends it.
quick.STANCE = { [5] = true, [60] = true }
function quick.nodes(pw)
    local a, b = "", ""
    pcall(function()
        local fsm = pw:call("get_ActionManager"):get_field("Fsm")
        a = tostring(fsm:call("getCurrentNodeName(System.UInt32)", 0))
        b = tostring(fsm:call("getCurrentNodeName(System.UInt32)", 1))
    end)
    return a, b
end
function quick.hold_end(addr, why)
    local h = quick.holds[addr]
    if not h then return end
    quick.holds[addr] = nil
    pcall(function() h.dm:call("set_Enabled", true) end)
    log_msg(string.format("Quick skill: %s's own AI back on after %.1f s (%s)", tostring(h.name), os.clock() - h.t0, tostring(why)))
end
function quick.hold_start(pw, id, name)
    if not cfg.quick_skill_hold_ai then return end
    local addr = pw:get_address()
    quick.hold_end(addr, "new order")
    local dm = pw:get_field("<AIDecisionMaker>k__BackingField")
    if not dm then return end
    local n0, n1 = quick.nodes(pw)
    dm:call("set_Enabled", false)
    quick.holds[addr] = { pw = pw, dm = dm, id = id, name = name, t0 = os.clock(), n0 = n0, n1 = n1 }
end
function quick.hold_tick()
    if not next(quick.holds) then return end
    local now = os.clock()
    for addr, h in pairs(quick.holds) do
        local why
        if coop.active then why = "co-op"
        elseif state.active and state.pawn_chara and state.pawn_chara:get_address() == addr then why = "taken over"
        elseif call(h.pw, "get_IsDead") or call(h.pw, "get_IsDown") then why = "pawn down"
        else
            local a, b = quick.nodes(h.pw)
            local idle = a:find("Locomotion", 1, true) ~= nil and (b == "" or b:find("UpperBodyDefault", 1, true) ~= nil or b:find("Locomotion", 1, true) ~= nil)
            if not h.started then
                if not idle and (a ~= h.n0 or b ~= h.n1) then h.started = now
                elseif now - h.t0 > 2.5 then why = "the action did not start" end
            elseif idle then why = "action over"
            elseif now - h.t0 > (quick.STANCE[h.id] and 20.0 or 8.0) then why = "time limit" end
        end
        if why then quick.hold_end(addr, why); break end
    end
end
function quick.hold_end_all(why)
    for addr in pairs(quick.holds) do quick.hold_end(addr, why); if not next(quick.holds) then break end end
    for addr in pairs(quick.holds) do quick.hold_end(addr, why) end
end

local function quick_write(info)
    quick.last = info
    R.dump("DPC_quick.json", { n = quick.n, t = os.clock(), slot = info.slot, skill = info.skill,
        name = info.name, pawn = info.pawn, target = info.target, how = info.how, result = info.result, source = info.source })
end

local function quick_skill(slot, idx)
    -- v0.9.90: idx = an explicit party pawn (the selected one while another pawn is possessed)
    if coop.active or (state.active and idx == nil) then return end
    local party = get_party()
    local entry = nil
    for _, e in ipairs(party) do if e.idx == (idx or cfg.selected_pawn_idx) then entry = e end end
    if idx == nil then entry = entry or party[1] end
    if not entry then log_msg("Quick skill: no pawn"); return end
    local info = { slot = slot, pawn = entry.name }
    local pw = entry.chara
    if call(pw, "get_IsDead") or call(pw, "get_IsDown") then
        info.result = "pawn is down"; quick_write(info); log_msg("Quick skill: " .. entry.name .. " is down"); return
    end
    local id = entry.skills[slot] or 0
    info.skill = id
    info.name = (SKILL_NAMES and SKILL_NAMES[id]) or tostring(id)
    if id == 0 then info.result = "slot empty"; quick_write(info); log_msg("Quick skill: " .. entry.name .. " has nothing in slot " .. slot); return end
    local held = quick.holds[pw:get_address()]
    if held and held.id == id and quick.STANCE[id] then -- the stance is ordered again: end it
        quick.hold_end(pw:get_address(), "ordered again")
        pcall(function()
            local ex = pw:call("get_AIDecisionMaker"):call("get_DecisionModule"):call("get_ActionInterface"):call("get_Executor")
            ex:call("forceEndAction")
        end)
        info.result = "stance ended"; quick_write(info); log_msg("Quick skill: " .. entry.name .. " leaves " .. info.name); return
    end
    local live = quick.game_def(pw, id)
    local def, pack_obj, pack_path, alt = nil, nil, nil, nil
    if live then
        def, pack_obj, pack_path, info.source = { live.path, live.kind }, live.obj, live.path, "game (live)"
    else
        local g = quick.table_def(id)
        if g then def, pack_obj, pack_path, alt, info.source = { g.path, g.kind }, g.obj, g.path, g.alt, "game (table)" end
    end
    if not def then info.result = "no pack for skill " .. id; quick_write(info); log_msg("Quick skill: no action pack known for skill " .. tostring(id)); return end
    local tgt, how
    if def[2] == "enemy" then
        tgt, how = quick_pick_enemy(pw)
        if not tgt and alt == "self" then tgt, how = pw, "self (no enemy)"
        elseif not tgt and alt == "player" then tgt, how = quick_arisen(), "Arisen (no enemy)" end
        -- v0.9.151 requested: with no enemy about the skill is still performed, on the spot (target = the pawn himself)
        if not tgt and cfg.quick_skill_no_target then tgt, how = pw, "self (no enemy about)" end
        if not tgt then info.result = "no enemy"; quick_write(info); log_msg("Quick skill: no enemy in view or near " .. entry.name); return end
    elseif def[2] == "self" then
        tgt, how = pw, "self"
    else
        tgt, how = quick_arisen(), "Arisen"
    end
    info.how = how
    info.target = tgt and tostring(call(tgt, "get_CharaIDString")) or "?"
    local ok, err = pcall(function()
        quick.exec = quick.exec or sdk.find_type_definition("app.AIBlackBoardExtensions"):get_method(
            "setBBValuesToExecuteActInter(app.AIBlackBoardController, app.ActInterPackData, app.AITarget)")
        local path = pack_path
        local u = pack_obj or quick.packs[path]
        if not u then u = sdk.create_userdata("app.ActInterPackData", path); quick.packs[path] = u end
        local bb = call(pw, "get_AIBlackBoardController")
        local at = quick_ai_target(pw, tgt)
        if not (u and bb and at) then error("pack/blackboard/target missing") end
        quick.exec:call(nil, bb, u, at)
        bb:call("set_ReqMainActInterPackData(app.ActInterPackData)", u)
        quick.last_addr, quick.last_t = pw:get_address(), os.clock()
        quick.hold_start(pw, id, entry.name)
    end)
    quick.n = quick.n + 1
    info.result = ok and "ordered" or ("error: " .. tostring(err))
    if not ok then dev_error("quick skill", err) end
    quick_write(info)
    log_msg(string.format("Quick skill %d: %s -> %s (%s, %s, %s)", slot, entry.name, info.name, info.target, info.result, tostring(info.source)))
end

-- v0.9.15 heal / revive and warp-to-me for the party, moved over from PawnCommander (its v2.4 code, which
-- which was played with). Every pawn; while a pawn is possessed, "me" is the possessed pawn and he isn't moved.
local function party_heal()
    local n = 0
    for _, e in ipairs(get_party()) do
        local ok = pcall(function()
            e.chara:call("recoverAll")
            if e.human then e.human:set_field("IsStartRecoverHpAndMaxHpCompletely", true) end
            local sm = e.chara:call("get_StaminaManager")
            if sm then sm:call("recoverAll") end
            if e.pawn then
                e.pawn:call("setPawnRevive", 0.0, false, false)
                e.pawn:call("cureAllScar")
            end
        end)
        if ok then n = n + 1 end
    end
    -- v0.9.80: the Arisen too (reported: it should heal the Arisen too and does not), unless switched off
    local ar_done = false
    if cfg.party_heal_arisen then
        ar_done = pcall(function()
            local ar = sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer")
            ar:call("recoverAll")
            local hu = ar:call("get_Human")
            if hu then hu:set_field("IsStartRecoverHpAndMaxHpCompletely", true) end
            local sm = ar:call("get_StaminaManager")
            if sm then sm:call("recoverAll") end
        end)
    end
    log_msg("Healed / revived " .. n .. " pawn" .. (n == 1 and "" or "s") .. (ar_done and " and the Arisen" or ""))
end

local WARP_RING = { { 1.8, 0.5, 0.0 }, { -1.8, 0.5, 0.0 }, { 0.0, 0.5, -2.0 }, { 0.0, 0.5, 2.0 } }
local warp_checks = {}

local function warp_ring(e, pos, slot)
    pcall(e.chara.call, e.chara, "warp(via.vec3, app.CharacterWarpOption)",
        Vector3f.new(pos.x + slot[1], pos.y + slot[2], pos.z + slot[3]), nil)
end

local function party_warp_to_me()
    -- v0.9.40: it is a keyboard command, so "me" is whoever the keyboard drives: the possessed pawn in normal
    -- possession, the Arisen in co-op. v0.9.41: in co-op player 2's pawn comes too (coop_warp_p2, default on).
    local me = (state.active and not coop.active and state.pawn_chara) or quick_arisen()
    local xf = me and call(me, "get_Transform")
    local pos = xf and call(xf, "get_Position")
    if not pos then log_msg("Warp: no position for you"); return end
    -- safeWarp wants the universal (double) position; get_Position() sent pawns to garbage coordinates (PawnCommander)
    local upos = call(xf, "get_UniversalPosition")
    local pm = sdk.get_managed_singleton("app.PawnManager")
    local i = 0
    for _, e in ipairs(get_party()) do
        if not (state.active and same_obj(e.chara, state.pawn_chara) and not (coop.active and cfg.coop_warp_p2)) then
            i = i + 1
            local slot = WARP_RING[(i - 1) % #WARP_RING + 1]
            local ok = upos and pm and pcall(pm.call, pm, "safeWarp(app.Character, via.Position)", e.chara, upos)
            if not ok then warp_ring(e, pos, slot) end
            warp_checks[#warp_checks + 1] = { e = e, t = os.clock() + 0.3, pos = Vector3f.new(pos.x, pos.y, pos.z), slot = slot }
        end
    end
    log_msg("Warped " .. i .. " pawn" .. (i == 1 and "" or "s") .. " to you")
end

local function verify_warps()
    if #warp_checks == 0 then return end
    local now, keep = os.clock(), {}
    for _, w in ipairs(warp_checks) do
        if now < w.t then
            keep[#keep + 1] = w
        else
            local p = brain_pos(w.e.chara) and Vector3f.new(brain_pos(w.e.chara))
            local d = p and math.sqrt((p.x - w.pos.x) ^ 2 + (p.y - w.pos.y) ^ 2 + (p.z - w.pos.z) ^ 2)
            if not d or d ~= d or d > 60.0 then
                log_msg("Warp check failed for " .. tostring(w.e.name) .. " -> ring warp")
                warp_ring(w.e, w.pos, w.slot)
            end
        end
    end
    warp_checks = keep
end

-- v0.7.5: run the possessed pawn's PlayerInputProcessor inside the Arisen's app.Player.update, the point in the
-- frame where the game normally processes player input. (Defined after `native`; installed once at load.)
local function install_native_hook()
    local player_td = sdk.find_type_definition("app.Player")
    local player_upd = player_td and player_td:get_method("update")
    if player_upd then
        sdk.hook(
            player_upd,
            function(args)
                local pip = native.pip
                if not (state.active and pip and not native.failed and native.drive == "player") then return end
                native.hook_frames = native.hook_frames + 1
                if state.pawn_input and (field(state.pawn_input, "ButtonOnFlags") or 0) ~= 0 then
                    native.hook_input_frames = native.hook_input_frames + 1
                end
                coop_target_tick()
                R.dash_keep(state.pawn_input)
                local ok, err = pcall(pip.call, pip, "update")
                native.frames = native.frames + 1
                if R.aim_point then R.aim_point() end
                if not ok then
                    native.errors = native.errors + 1
                    if native.errors >= 5 then native.failed = true end
                end
            end,
            function(retval) return retval end
        )
    end

end
install_native_hook()

-- v0.8.2: the brain's app.Player.update hook (registered after the native hook, so the possessed pawn's processor
-- has already run this frame when it fires):
--   * lock his lock-on onto the brain's target for the duration of app.Player.update (restored in the post-hook)
--   * while a pawn is possessed, run his PlayerInputProcessor ourselves: app.Player.update stops calling it during
--     possession (verified: 0 calls in 584 frames even with IsEnable true). Skipped if the game itself ran it in
--     the last 0.25 s, so it can never double-update.
local function install_brain_player_hook()
    local player_td = sdk.find_type_definition("app.Player")
    local player_upd = player_td and player_td:get_method("update")
    if not player_upd then return end
    sdk.hook(
        player_upd,
        function(args)
            if coop.active and state.arisen_chara then
                -- co-op: player 1's Arisen must keep his own controls even if app.Player.update skips his
                -- processor while a pawn is possessed (seen with the brain)
                if os.clock() - (brain.game_pip_t or 0) < 0.25 then return end
                local pip = state.arisen_pip
                if pip then
                    brain.self_driving = true
                    local ok, err = pcall(pip.call, pip, "update")
                    brain.self_driving = false
                    coop.driven = (coop.driven or 0) + 1
                    if not ok then coop.err = "drive: " .. tostring(err); dev_error("coop.drive", err) end
                end
                return
            end
            if not brain.on then return end
            brain_lock_apply()
            if state.active and brain.ar then
                if os.clock() - (brain.game_pip_t or 0) < 0.25 then return end
                local pip = call(brain.ar, "get_InputProcessor")
                if pip then
                    brain.self_driving = true
                    local ok, err = pcall(pip.call, pip, "update")
                    brain.self_driving = false
                    brain.driven = (brain.driven or 0) + 1
                    if not ok then
                        brain.errs = brain.errs + 1
                        brain.err = "drive: " .. tostring(err)
                    end
                end
            end
        end,
        function(retval)
            if brain.lock_swapped then brain_lock_restore() end
            if state.active then brain_restore_input() end
            return retval
        end
    )
end
install_brain_player_hook()

-- ----------------------------------------------------------------------------
-- InputProcessor Rebinding Helpers (Angle B - Experimental Mode 1 / Mode 3)
-- ----------------------------------------------------------------------------
local function apply_native_processor_binding(bind_to_pawn)
    local pip = state.arisen_pip
    if not pip then return end

    local param = field(pip, "Param")
    if bind_to_pawn and state.pawn_chara and state.pawn_human then
        write_trace("apply_native_processor_binding(true) begin")

        if cfg.exp_swap_inputs and state.arisen_input and state.pawn_input then
            write_trace("Step 1: swap CharacterInput")
            call(state.pawn_chara, "set_Input", state.arisen_input)
            call(state.arisen_chara, "set_Input", state.pawn_input)
            call(state.pawn_input, "resetAllInputsCore")
            call(state.pawn_input, "resetAxisL")
            call(state.pawn_input, "resetAxisR")
        end

        write_trace("Step 2: set IsPlayer on HumanCommonActionCtrl")
        local hcac = call(state.pawn_human, "get_HumanCommonActionCtrl") or field(state.pawn_human, "<HumanCommonActionCtrl>k__BackingField")
        if hcac then
            set_field(hcac, "IsPlayer", true)
        end
        if cfg.set_human_is_arisen then
            write_trace("Step 2b: set Pawn Human.IsArisen = true")
            set_field(state.pawn_human, "IsArisen", true)
        end

        if cfg.exp_rebind_lockon and state.arisen_lockon_ctrl then
            write_trace("Step 4: rebind LockOnCtrl.Chara to Pawn")
            set_field(state.arisen_lockon_ctrl, "Chara", state.pawn_chara)
            call(state.arisen_lockon_ctrl, "clearLockOn")
        end

        write_trace("Step 5: rebind PlayerInputProcessor & Param")
        local pawn_track = field(state.pawn_human, "Track")
        call(pip, "set_IsEnable", true)
        call(pip, "set_Chara", state.pawn_chara)
        call(pip, "set_Human", state.pawn_human)
        if pawn_track then call(pip, "set_PlayerTrack", pawn_track) end

        if param then
            set_field(param, "Chara", state.pawn_chara)
            set_field(param, "Human", state.pawn_human)
            if pawn_track then set_field(param, "PlayerTrack", pawn_track) end
            call(param, "updateIsMultiButtonSkill")
        end

        if cfg.exp_call_select_proc then
            write_trace("Step 6: pip:selectProcessor()")
            call(pip, "selectProcessor")
        end

        write_trace("Step 7: setInputProcessor on Pawn")
        call(state.arisen_chara, "setInputProcessor", nil)
        call(state.pawn_chara, "setInputProcessor", pip)

        if cfg.swap_player_comp_refs and state.arisen_player_comp then
            write_trace("Step 8: swap app.Player.Chara/Human")
            set_field(state.arisen_player_comp, "Chara", state.pawn_chara)
            set_field(state.arisen_player_comp, "Human", state.pawn_human)
        end
        if cfg.swap_manual_player then
            write_trace("Step 9: CharacterManager:setManualPlayer(pawn)")
            local cm = sdk.get_managed_singleton("app.CharacterManager")
            if cm then
                call(cm, "setManualPlayer", state.pawn_chara)
            end
        end
        write_trace("apply_native_processor_binding(true) complete")
    else
        write_trace("apply_native_processor_binding(false) begin")
        if state.arisen_chara and state.arisen_input then
            call(state.arisen_chara, "set_Input", state.arisen_input)
        end
        if state.pawn_chara and state.pawn_input then
            call(state.pawn_chara, "set_Input", state.pawn_input)
        end

        if state.pawn_human then
            local hcac = call(state.pawn_human, "get_HumanCommonActionCtrl") or field(state.pawn_human, "<HumanCommonActionCtrl>k__BackingField")
            if hcac then
                set_field(hcac, "IsPlayer", state.pawn_orig_is_player or false)
            end
            set_field(state.pawn_human, "IsArisen", state.pawn_orig_is_arisen or false)
        end
        if state.pawn_chara then
            call(state.pawn_chara, "setInputProcessor", nil)
            if cfg.exp_add_player_sel then
                local sel = call(state.pawn_chara, "get_HumanActionSelector")
                if sel then call(sel, "updateCurrentSelector") end
            end
        end

        if state.arisen_lockon_ctrl and state.arisen_chara then
            set_field(state.arisen_lockon_ctrl, "Chara", state.arisen_chara)
            call(state.arisen_lockon_ctrl, "clearLockOn")
        end

        if state.arisen_chara and state.arisen_human then
            call(pip, "set_Chara", state.arisen_chara)
            call(pip, "set_Human", state.arisen_human)
            if state.arisen_track then call(pip, "set_PlayerTrack", state.arisen_track) end
            if param then
                set_field(param, "Chara", state.arisen_chara)
                set_field(param, "Human", state.arisen_human)
                if state.arisen_track then set_field(param, "PlayerTrack", state.arisen_track) end
                call(param, "updateIsMultiButtonSkill")
            end
            if cfg.exp_call_select_proc then
                call(pip, "selectProcessor")
            end
            call(pip, "set_IsEnable", true)
            call(state.arisen_chara, "setInputProcessor", pip)
        end

        if state.arisen_player_comp and state.arisen_chara and state.arisen_human then
            set_field(state.arisen_player_comp, "Chara", state.arisen_chara)
            set_field(state.arisen_player_comp, "Human", state.arisen_human)
        end
        if cfg.swap_manual_player then
            local cm = sdk.get_managed_singleton("app.CharacterManager")
            if cm and state.arisen_chara then
                call(cm, "setManualPlayer", state.arisen_chara)
            end
        end
        write_trace("apply_native_processor_binding(false) complete")
    end
end

-- ----------------------------------------------------------------------------
-- Start / Stop Pawn Possession
-- ----------------------------------------------------------------------------
-- v0.9.169 switch transition (requested: "establish the pawn we're about to control, maybe a bit of a slowdown, and a
-- nice transition to them ... highlight the pawn ... something that matches the native game's aesthetic").
-- Until now the camera was retargeted with registerTargetObject + onWarpTarget: an instant cut. Now, when control
-- changes hands, the camera first turns (from where it is) to look at the character you are about to play, then
-- glides to wherever the game's own camera wants to be behind them, while the game runs slowed and eases back to
-- full speed. The game's camera is retargeted at once as before; DPC only overrides the drawn camera pose for the
-- length of the transition (on the camera joint, in a post-hook on MainCameraController.lateUpdate), so
-- when it ends the game's camera is simply where it already was. Timings run on real time, not game time.
-- Glow: the game's own rim lights (app.MIRimLightHash, e.g. PawnRimStone) requested on each of the character's
-- MaterialInterpolationRimLight parts and finished after switch_cine_glow_s. Slow-down: each object's app.WorkRate (see R.cine_timescale).
-- Never in co-op, never on a load / teardown release; anything left (time scale, glow) is undone on release,
-- world loading and Reset Scripts.
R.CINE_GLOWS = {
    { "", "No glow" },
    { "RimLightRevival", "Revival (sky blue / pale gold)", 0xFFFFC828, 0xFFA0FFE6 },
    { "RimLightInteractLarge", "Can interact (amber / blue, subtle)", 0xFF64B4FF, 0xFFF08C3C },
    { "PawnRimStone", "Riftstone (blue / cyan)", 0xFFFF7850, 0xFFFFFF78 },
    { "RimLightSummon", "Summon (violet)", 0xFFFF1E50, 0xFFFF3C64 },
    { "ChRecovery", "Healing (green)", 0xFF328069, 0xFF64FFD2 },
    { "AstralPlayer", "Astral (soft blue)", 0xFFFF463C, 0xFFFF6E64 },
    { "RimLightPawnLift", "Pawn lift (green / deep blue)", 0xFF20FF40, 0xFFB44000 },
}
R.CINE_PROFILES = { "Instant (cut)", "Establish (pull back, then in)", "Bird's-eye (up into the sky, then down)", "Custom" }
R.cine_params = function()
    local pr = cfg.switch_cine_profile or 2
    if pr == 2 then return { look = 0.75, hold = 0.20, glide = 0.95, pull = 3.0, rise = 2.0, slow = cfg.switch_cine_slowmo or 0.4 } end
    if pr == 3 then return { look = 1.10, hold = 0.35, glide = 1.30, pull = 4.0, rise = 14.0, slow = cfg.switch_cine_slowmo or 0.4 } end
    return { look = cfg.switch_cine_look_s or 0.45, hold = cfg.switch_cine_hold_s or 0.15, glide = cfg.switch_cine_glide_s or 0.8,
             pull = cfg.switch_cine_pull and (cfg.switch_cine_pull_m or 2.0) or nil, rise = cfg.switch_cine_rise_m or 1.2, slow = cfg.switch_cine_slowmo or 0.4 }
end
R.cine_ease = function(x) x = math.max(0, math.min(1, x)); return x * x * (3 - 2 * x) end
R.cine_slerp = function(a, b, t)
    local ax, ay, az, aw = a[1], a[2], a[3], a[4]
    local bx, by, bz, bw = b[1], b[2], b[3], b[4]
    local d = ax * bx + ay * by + az * bz + aw * bw
    if d < 0 then bx, by, bz, bw, d = -bx, -by, -bz, -bw, -d end
    local k0, k1
    if d > 0.9995 then k0, k1 = 1 - t, t
    else
        local th = math.acos(d); local sn = math.sin(th)
        k0, k1 = math.sin((1 - t) * th) / sn, math.sin(t * th) / sn
    end
    local x, y, z, w = ax * k0 + bx * k1, ay * k0 + by * k1, az * k0 + bz * k1, aw * k0 + bw * k1
    local n = math.sqrt(x * x + y * y + z * z + w * w)
    return { x / n, y / n, z / n, w / n }
end
-- rotation of a camera at p looking at q (the engine's cameras look along their -Z axis)
R.cine_look = function(p, q)
    local dx, dy, dz = q[1] - p[1], q[2] - p[2], q[3] - p[3]
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if len < 0.01 then return nil end
    dx, dy, dz = dx / len, dy / len, dz / len
    local yaw = math.atan(-dx, -dz)
    local pitch = math.asin(math.max(-1, math.min(1, dy)))
    local sy, cy = math.sin(yaw / 2), math.cos(yaw / 2)
    local sx, cx = math.sin(pitch / 2), math.cos(pitch / 2)
    return { cy * sx, sy * cx, -sy * sx, cy * cx }
end
-- v0.9.169b: the pose comes from MainCameraController._Position / _Rotation and goes to its _CameraJoint, inside
-- a post-hook on its lateUpdate (the way Camera Distance does it). 0.9.169 wrote the camera GameObject's own
-- transform at BeginRendering: that transform is not rewritten by the game, can read ~2 km off (a different
-- coordinate frame, seen in the logs before this feature), and after a few switches the camera and the nametags
-- came apart (the tester, [time]). The joint is rewritten by the controller every frame, so nothing can stick.
R.cine_mcc = function()
    local cm = sdk.get_managed_singleton("app.CameraManager")
    return cm and cm:call("getMainCameraController", 0)
end
-- Game speed while switching. v0.9.169 first used app.TimeManager.setTimeScale: that is the speed of the in-game
-- day clock, not of the action (the tester caught it). The real slow motion is each object's app.WorkRate
-- (NextRateValue / NextApplyRate), the way Pawn Tactical Wheel does it: the player, the party, every enemy and every
-- shell (arrows, spells), the list gathered again every 0.15 s and written every frame while it lasts.
R.cine_rates_gather = function()
    local out, seen = {}, {}
    local function add_chara(c)
        if not c then return end
        local ok, a = pcall(c.get_address, c)
        if not ok or not a or seen[a] then return end
        seen[a] = true
        local okw, wr = pcall(c.get_field, c, "<WorkRate>k__BackingField")
        if okw and wr then out[#out + 1] = wr end
    end
    pcall(function() add_chara(sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer")) end)
    pcall(function() add_chara(state.arisen_chara) end)
    pcall(function()
        local l = sdk.get_managed_singleton("app.PawnManager"):call("get_PawnCharacterList")
        for i = 0, l:call("get_Count") - 1 do add_chara(l:call("get_Item", i)) end
    end)
    pcall(function()
        local arr = sdk.get_managed_singleton("app.EnemyManager"):call("getAllEnemies")
        for i = 0, arr:call("get_Count") - 1 do
            local e = arr:call("get_Item", i)
            add_chara(e and e:get_field("_Chara"))
        end
    end)
    pcall(function()
        local list = sdk.get_managed_singleton("app.ShellManager"):get_field("ShellList")
        local items, size = list:get_field("_items"), list:get_field("_size") or 0
        local wt = sdk.typeof("app.WorkRate")
        for i = 0, size - 1 do
            local sh = items:get_element(i)
            local okw, wr = pcall(function() return sh and sh:call("get_GameObject"):call("getComponent(System.Type)", wt) end)
            if okw and wr then out[#out + 1] = wr end
        end
    end)
    return out
end
R.cine_rates_write = function(v)
    local r = math.max(0.005, v)
    for _, wr in ipairs(R.cine_rates or {}) do
        pcall(function() wr:set_field("NextRateValue", r); wr:set_field("NextApplyRate", r) end)
    end
end
R.cine_timescale = function(v)
    if v == nil then
        if R.cine_ts_set then R.cine_rates_write(1.0) end
        R.cine_ts_set, R.cine_rates, R.cine_rates_t = false, nil, nil
        return
    end
    local now = os.clock()
    if not R.cine_rates or now - (R.cine_rates_t or 0) >= 0.15 then
        R.cine_rates, R.cine_rates_t = R.cine_rates_gather(), now
    end
    R.cine_ts_set = true
    R.cine_rates_write(v)
end
R.cine_glow = function(chara, name, on)
    if not chara or not name or name == "" then return end
    pcall(function()
        local f = sdk.find_type_definition("app.MIRimLightHash"):get_field(name)
        if not f then return end
        local h = f:get_data(nil)
        local rm = chara:call("get_GameObject"):call("getComponent(System.Type)", sdk.typeof("app.MaterialInterpolationRequestManager"))
        if not rm then return end
        -- as the game calls it (logged 2026-11-19): category RimLight (8), then -1, -1 = all materials. 0, 0 drew nothing.
        local sig = on and "requestMaterialMode(System.UInt32, app.MaterialInterpolationRequestManager.RequestListCategory, System.Int32, System.Int32)"
            or "finishMaterialMode(System.UInt32, app.MaterialInterpolationRequestManager.RequestListCategory, System.Int32, System.Int32)"
        rm:call(sig, h, 8, -1, -1)
    end)
end
-- 0.9.172-dev38: timed glows besides the switch glow (a player leaving co-op), each finished after switch_cine_glow_s
R.glows_timed = {}
R.glow_for = function(chara, name, secs)
    if not chara or not name or name == "" then return end
    R.cine_glow(chara, name, true)
    R.glows_timed[#R.glows_timed + 1] = { chara = chara, name = name, t_end = os.clock() + (secs or cfg.switch_cine_glow_s or 1.8) }
end
-- 0.9.172-dev40 (the tester: "use one of the brighter highlights like astral for when a co-op player joins. Bonus points if
-- we can color a highlight the color of their character target reticles/bookmarks (and maybe even leave that on)").
-- The game's rim lights come in fixed colours, so each player gets the one closest to their marker colour: player 2
-- light blue (Astral), 3 green (Healing), 4 magenta / violet (Summon), 5 red (Berserker), 6+ Astral.
-- dev42: player 1 (the tester: "make arisen glow his orange when co-op starts") gets the amber "can interact" light
R.PLAYER_GLOWS = { [1] = "RimLightInteractLarge", [2] = "AstralPlayer", [3] = "ChRecovery", [4] = "RimLightSummon", [5] = "Berserker" }
R.pglow = {}
-- dev45: the kept glow per player: the "keep glowing" tick for everyone, then each player's own tick under it
R.glow_keep_for = function(n)
    return cfg.coop_glow_keep == true and (cfg.coop_glow_keep_p or {})["p" .. n] ~= false
end
R.pglow_now = function()
    local cur = {}
    if coop.active and state.arisen_chara and not (R.cp and R.cp.ar2) then cur[1] = state.arisen_chara end -- dev42: player 1's Arisen
    if R.s2 and R.s2.active and R.s2.chara then cur[R.s2.player or 2] = R.s2.chara
    elseif coop.active and state.active and state.pawn_chara and not (R.tp.start_kb and not R.tp.p2) then
        cur[2] = state.pawn_chara -- dev48: not while Ctrl + F6 waits for player 2's L3 + R3; dev49: lit the moment the controller is claimed, not on release (the tester: "it wasn't clear when they actually joined")
    end
    -- dev52: player 1 on a pawn (both-pawns arrangement, or player 2 on the Arisen)
    if R.cp and R.cp.on and R.cp.mode == "pawns" and state.active and state.pawn_chara then
        cur[1] = state.pawn_chara
        if R.cp.ar2 and state.arisen_chara then cur[2] = state.arisen_chara end
    end
    for n, sl in pairs(R.np and R.np.slots or {}) do if sl.active and sl.chara then cur[n] = sl.chara end end
    return cur
end
R.pglow_tick = function()
    local now = os.clock()
    if now < (R.pglow_next or 0) then return end
    R.pglow_next = now + 0.25
    local cur = (cfg.coop_join_glow ~= false) and R.pglow_now() or {}
    for n, g in pairs(R.pglow) do
        local c = cur[n]
        if not c or c:get_address() ~= g.addr then
            if g.kept then pcall(R.cine_glow, g.chara, g.name, false) end
            R.pglow[n] = nil
        elseif g.kept and not R.glow_keep_for(n) then -- unticked: out, no fresh join glow
            pcall(R.cine_glow, g.chara, g.name, false)
            g.kept = false
        end
    end
    for n, c in pairs(cur) do
        -- dev41 (the tester: the kept glow "needs to come back on if the checkbox is turned on while already playing"):
        -- a player with only the short join glow gets the kept one as soon as the box is ticked
        local g0 = R.pglow[n]
        -- 0.9.173-dev1: a new colour picked mid-play: the old light goes out and the new one comes on
        if g0 and g0.name ~= R.player_glow(n) then
            if g0.kept then pcall(R.cine_glow, g0.chara, g0.name, false) end
        end
        if g0 and (g0.name ~= R.player_glow(n) or (R.glow_keep_for(n) and not g0.kept)) then
            local recolour = g0.name ~= R.player_glow(n)
            for i = #R.glows_timed, 1, -1 do
                local t = R.glows_timed[i]
                if t.name == g0.name and t.chara:get_address() == g0.addr then
                    table.remove(R.glows_timed, i)
                    if recolour then pcall(R.cine_glow, t.chara, t.name, false) end
                end
            end
            R.pglow[n] = nil
        end
        if not R.pglow[n] then
            local name = R.player_glow(n)
            if R.glow_keep_for(n) then
                pcall(R.cine_glow, c, name, true)
                R.pglow[n] = { chara = c, addr = c:get_address(), name = name, kept = true }
            else
                pcall(R.glow_for, c, name, math.max(cfg.switch_cine_glow_s or 1.8, 2.5))
                R.pglow[n] = { chara = c, addr = c:get_address(), name = name }
            end
        end
    end
end
re.on_frame(function() pcall(R.pglow_tick) end)
re.on_script_reset(function() for _, g in pairs(R.pglow) do if g.kept then pcall(R.cine_glow, g.chara, g.name, false) end end end)
-- 0.9.173-dev1: the Preview button beside each player's colour. Not on a character already lit in that light (the
-- preview's end would put the kept glow out too).
R.color_preview = function(n)
    local cur = R.pglow_now()
    -- dev4: state.arisen_chara is only set while a pawn is played, so with nobody taken over there was nothing to light
    local ch = cur[n] or (state.active and state.pawn_chara) or state.arisen_chara or R.real_player()
    if not ch then return end
    local name = R.player_glow(n)
    for _, g in pairs(R.pglow) do
        if g.name == name and g.addr == ch:get_address() then R.ta_note("Already glowing in that colour"); return end
    end
    R.glow_for(ch, name, 2.5)
end
R.leave_glow = function(chara)
    if cfg.coop_leave_glow and cfg.coop_leave_glow ~= "" then pcall(R.glow_for, chara, cfg.coop_leave_glow) end
end
re.on_frame(function()
    local now = os.clock()
    for i = #R.glows_timed, 1, -1 do
        local g = R.glows_timed[i]
        if now >= g.t_end then table.remove(R.glows_timed, i); R.cine_glow(g.chara, g.name, false) end
    end
end)
re.on_script_reset(function() for _, g in ipairs(R.glows_timed) do R.cine_glow(g.chara, g.name, false) end end)
R.cine_glow_off = function()
    local g = R.cine_glowing
    if g then R.cine_glowing = nil; R.cine_glow(g.chara, g.name, false) end
end
R.cine_stop = function(why)
    if R.cine and R.api_fire then pcall(R.api_fire, "transition_end", { to_name = state.active and state.pawn_name or "Arisen" }) end
    R.cine = nil
    R.cine_timescale(nil)
    if why ~= "keep glow" then R.cine_glow_off() end
end
R.cine_begin = function(chara)
    if coop.active or not chara then return end
    if R.api_claimed and R.api_claimed("camera.transition") then return end -- v0.9.170: another mod does the transition
    -- 0.9.173: a mod that holds camera.follow places the camera itself, so the transition does not move it either
    -- (only the glow plays). Seen as a question from a mod author: holding follow alone left DPC's glide fighting his camera.
    local follow_claimed = R.api_claimed and R.api_claimed("camera.follow")
    if follow_claimed or not cfg.switch_cine or (cfg.switch_cine_profile or 2) == 1 then -- no camera move; the glow still plays
        if cfg.switch_glow and cfg.switch_glow ~= "" then
            R.cine_glow_off()
            R.cine_glow(chara, cfg.switch_glow, true)
            R.cine_glowing = { chara = chara, name = cfg.switch_glow, t_end = os.clock() + (cfg.switch_cine_glow_s or 1.4) }
        end
        return
    end
    local P = R.cine_params()
    local ok, err = pcall(function()
        local mcc = R.cine_mcc()
        local joint = mcc and mcc:get_field("_CameraJoint")
        if not joint then return end
        local p, r = joint:call("get_Position"), joint:call("get_Rotation")
        R.cine_install()
        R.cine_glow_off()
        if R.api_fire then
            -- dev6: a switch during a running transition ends that one first (api-1: starts without ends)
            if R.cine then pcall(R.api_fire, "transition_end", { to_name = state.active and state.pawn_name or "Arisen", interrupted = true }) end
            pcall(R.api_fire, "transition_start", { style = cfg.switch_cine_profile, chara = chara })
        end
        R.cine = { t0 = os.clock(), chara = chara, p0 = { p.x, p.y, p.z }, q0 = { r.x, r.y, r.z, r.w }, P = P }
        -- pull-out point: back and up from the midpoint between who the camera follows now and who comes next
        pcall(function()
            if not P.pull then return end
            local c = R.cine
            local og = mcc:call("get_TargetObject")
            local a = og and og:call("get_Transform"):call("get_Position")
            local b = chara:call("get_GameObject"):call("get_Transform"):call("get_Position")
            if not (a and b) then return end
            local A, B = { a.x, a.y + 1.2, a.z }, { b.x, b.y + 1.2, b.z }
            -- skip it when the new character is already near the middle of the view
            local fx, fy, fz = -2 * (r.x * r.z + r.w * r.y), -2 * (r.y * r.z - r.w * r.x), -(1 - 2 * (r.x * r.x + r.y * r.y))
            local dx, dy, dz = B[1] - p.x, B[2] - p.y, B[3] - p.z
            local dl = math.sqrt(dx * dx + dy * dy + dz * dz)
            if P.rise < 5 and dl > 0.1 and (fx * dx + fy * dy + fz * dz) / dl > math.cos(math.rad(20)) then return end
            local M = { (A[1] + B[1]) / 2, (A[2] + B[2]) / 2, (A[3] + B[3]) / 2 }
            local vx, vz = p.x - M[1], p.z - M[3]
            local vl = math.sqrt(vx * vx + vz * vz)
            if vl < 0.5 then vx, vz, vl = -fx, -fz, math.sqrt(fx * fx + fz * fz) end
            if vl < 0.01 then return end
            vx, vz = vx / vl, vz / vl
            local sep = math.sqrt((A[1] - B[1]) ^ 2 + (A[3] - B[3]) ^ 2)
            local rad = math.max(vl, sep * 0.6 + 3.0) + P.pull
            c.pp = { M[1] + vx * rad, math.max(p.y, M[2]) + P.rise, M[3] + vz * rad }
        end)
        R.cine_n = (R.cine_n or 0) + 1
        if (P.slow or 1) < 0.99 then R.cine_timescale(math.max(0.05, P.slow)) end
        if cfg.switch_glow and cfg.switch_glow ~= "" then
            R.cine_glow(chara, cfg.switch_glow, true)
            local whole = (P.look or 0) + (P.hold or 0) + (P.glide or 0) + 0.3 -- v0.9.169: on for the whole transition
            R.cine_glowing = { chara = chara, name = cfg.switch_glow, t_end = os.clock() + math.max(cfg.switch_cine_glow_s or 1.4, whole) }
        end
    end)
    if not ok then R.cine_stop(); dev_error("switch transition", err) end
end
R.cine_frame = function(mcc)
    local c = R.cine
    if not c then return end
    local ok, err = pcall(function()
        local now = os.clock()
        local P = c.P or R.cine_params()
        local look_s = math.max(0.0, P.look or 0.35)
        local hold_s = math.max(0.0, P.hold or 0.0)
        local glide_s = math.max(0.05, P.glide or 0.8)
        local t = now - c.t0
        if t >= look_s + hold_s + glide_s or coop.active then R.cine_stop("keep glow"); return end
        local joint = mcc and mcc:get_field("_CameraJoint")
        if not joint then R.cine_stop("keep glow"); return end
        -- where the game's camera is this frame (its final pose, incl. Camera Distance when its hook ran first)
        local gp, gr = joint:call("get_Position"), joint:call("get_Rotation")
        local pg, qg = { gp.x, gp.y, gp.z }, { gr.x, gr.y, gr.z, gr.w }
        -- the look-at point: the new character's chest
        local tp
        pcall(function()
            local cp = c.chara:call("get_GameObject"):call("get_Transform"):call("get_Position")
            tp = { cp.x, cp.y + 1.4, cp.z }
        end)
        -- game speed: slow, then eased back to full speed_back_s before the camera lands (the tester: it felt sluggish;
        -- the move is still going but it is good enough to take control)
        if R.cine_ts_set then
            local total = look_s + hold_s + glide_s
            local t_full = math.max(0, total - (cfg.switch_cine_speed_back_s or 0.95))
            local t_ramp = math.max(0, t_full - math.max(0.01, cfg.switch_cine_speed_ramp_s or 0.5))
            local s0 = math.max(0.05, P.slow or 1)
            if t >= t_full then R.cine_timescale(nil) -- full speed: let go of the game's rates
            elseif t >= t_ramp then R.cine_timescale(s0 + (1 - s0) * R.cine_ease((t - t_ramp) / math.max(0.01, t_full - t_ramp)))
            else R.cine_timescale(s0) end
        end
        local pp = c.pp or c.p0 -- where the look phase ends (the pull-out point, or where the camera was)
        local pos, rot
        if t < look_s then
            local e = R.cine_ease(t / math.max(look_s, 0.001))
            pos = { c.p0[1] + (pp[1] - c.p0[1]) * e, c.p0[2] + (pp[2] - c.p0[2]) * e, c.p0[3] + (pp[3] - c.p0[3]) * e }
            local qn = (tp and R.cine_look(pos, tp)) or qg
            rot = R.cine_slerp(c.q0, qn, e)
        elseif t < look_s + hold_s then
            pos = pp
            rot = (tp and R.cine_look(pp, tp)) or qg
        else
            local ql = (tp and R.cine_look(pp, tp)) or qg
            local u = R.cine_ease((t - look_s - hold_s) / glide_s)
            pos = { pp[1] + (pg[1] - pp[1]) * u, pp[2] + (pg[2] - pp[2]) * u, pp[3] + (pg[3] - pp[3]) * u }
            rot = R.cine_slerp(ql, qg, u)
        end
        gp.x, gp.y, gp.z = pos[1], pos[2], pos[3]
        joint:call("set_Position", gp)
        gr.x, gr.y, gr.z, gr.w = rot[1], rot[2], rot[3], rot[4]
        joint:call("set_Rotation", gr)
        c.frames = (c.frames or 0) + 1
        R.cine_last = { t = t, frames = c.frames }
    end)
    if not ok then R.cine_stop(); R.cine_err = tostring(err); dev_error("switch transition", err) end
end
-- installed at the first switch, so it is registered after Camera Distance's own lateUpdate hook and runs after it
R.cine_install = function()
    if R.cine_hooked then return end
    R.cine_hooked = true
    local td = sdk.find_type_definition("app.MainCameraController")
    local m = td and td:get_method("lateUpdate")
    if not m then return end
    sdk.hook(m, function(args)
        if R.cine then thread.get_hook_storage().cine_mcc = sdk.to_managed_object(args[2]) end
    end, function(retval)
        if R.cine then
            local mcc = thread.get_hook_storage().cine_mcc
            if mcc then R.cine_frame(mcc) end
        end
        return retval
    end)
end
re.on_frame(function() local g = R.cine_glowing; if g and os.clock() >= g.t_end then R.cine_glow_off() end end)

local function release_possession(reason)
    if not state.active then return end
    R.cp_last_rel = reason -- v0.9.171: why the main played pawn was let go (co-op, both on pawns)
    write_trace("release_possession begin", reason)
    log_msg("Releasing possession (" .. tostring(reason or "manual") .. ") -> Returning to Arisen")
    R.note = { text = "Back to the Arisen", t_end = os.clock() + 3.0 }
    if R.aim_stop then pcall(R.aim_stop) end -- v0.9.29: hand the aim camera back
    if R.ar_lock then pcall(R.ar_lock_remove, "release") end -- v0.9.168: the Arisen takes the game's lock-on back
    R.ar_lock_failed = nil
    -- v0.9.81: the brain sprints (a toggle) when its target is far. Handing the Arisen back with the sprint state
    -- still set left him unable to regain stamina until he ran dry (the tester, 2026-11-16). Clear it.
    pcall(function()
        local hu = state.arisen_chara and state.arisen_chara:call("get_Human")
        if hu and hu:call("get_IsDash") then
            hu:call("set_IsDash", false)
            hu:call("set_IsPrevDash", false)
            log_msg("Release: cleared the Arisen's sprint state")
        end
    end)

    local teardown = type(reason) == "string" and reason:find("^teardown") ~= nil
    if R.pf_restore_all then pcall(R.pf_restore_all, reason) end -- v0.9.170: sound settings etc. back to the Arisen
    if R.api_fire then -- v0.9.170 mod API
        local was_coop = coop.active
        pcall(R.api_fire, "release", { player = was_coop and 2 or 1, name = state.pawn_name, reason = tostring(reason or "manual") })
        if reason == "switching pawn" then R.api_switch_from = state.pawn_name end
        if was_coop and reason ~= "switching pawn" then R.api_coop_stop = true end
    end
    if coop.active and reason ~= "switching pawn" and coop.on_release then pcall(coop.on_release, reason) end
    if not brain.solo then brain.on = false; brain.target = nil end -- v0.8: hand the Arisen's input back now
    brain.pawn_native = false -- v0.8.10: never carry the previous pawn's control path into the next possession
    -- 0. End any active guard / aim / sprint on the pawn before releasing (skipped while the scene is unloading)
    if state.pawn_chara and not teardown then
        local sel = call(state.pawn_chara, "get_HumanActionSelector")
        if sel and (state.is_guarding or state.is_aiming or state.is_quickspelling) then
            if state.is_guarding then
                call(sel, "requestAction(System.String, System.UInt32)", "Job01_GuardEnd", 1)
            end
            call(sel, "requestEndAction()")
        end
        call(state.pawn_chara, "setLocomotionSpeed(app.LocomotionSpeedTypeEnum)", 0)
        call(state.pawn_chara, "set_DiscreteLocomotionSpeedType(app.LocomotionSpeedTypeEnum)", 0)
    end
    if state.pawn_human then
        call(state.pawn_human, "set_IsDash(System.Boolean)", false)
        call(state.pawn_human, "set_IsPrevDash(System.Boolean)", false)
        -- 0.9.172: the puppeteer (Thief fallback) turns dash-to-requested-speed on every frame; put back what the game had
        if type(state.pawn_orig_dash_req) == "boolean" then
            pcall(function()
                local hcac = call(state.pawn_human, "get_HumanCommonActionCtrl")
                if hcac then call(hcac, "set_IsEnableDashToRequestedMoveSpeedOfNormalLocomotion(System.Boolean)", state.pawn_orig_dash_req) end
            end)
        end
        state.pawn_orig_dash_req = nil
    end
    R.dash_opt_put(state.pawn_input, state.pawn_dash_opt0)
    state.pawn_dash_opt0 = nil

    -- 1. Restore Native HUD Skills, gauges, minimap & LockOnCtrl
    pcall(apply_native_hud_skills, false)
    pcall(apply_native_hud_gauges, false)
    pcall(native_release)
    state.pawn_sel_addr = 0
    state.hud_shift_held = false
    if state.arisen_lockon_ctrl and state.arisen_chara then
        set_field(state.arisen_lockon_ctrl, "Chara", state.arisen_chara)
        call(state.arisen_lockon_ctrl, "clearLockOn")
    end

    -- 2. Restore InputProcessor & CharacterInput bindings
    if cfg.control_mode == 1 or cfg.control_mode == 3 then
        apply_native_processor_binding(false)
    elseif state.arisen_pip then
        call(state.arisen_pip, "set_IsEnable(System.Boolean)", true)
    end

    -- 3. Re-enable Pawn AI
    set_pawn_ai_suppressed(state.pawn_chara, state.pawn_obj, false, true)

    -- 4. Re-attach MainCameraController to Arisen (not if the Arisen / managers are the ones being destroyed)
    if state.arisen_go and not (teardown and (reason:find("arisen") or reason:find("Manager"))) then
        if not teardown and reason ~= "loading" and reason ~= "script reset" then R.cine_begin(state.arisen_chara) else R.cine_stop() end -- v0.9.169
        attach_camera_to(state.arisen_go)
    end

    state.active = false
    R.session_write(false)
    if R.api_coop_stop then R.api_coop_stop = nil; pcall(R.api_fire, "coop_stop", {}) end
    state.frames_since_start = 0
    state.arisen_chara_addr = 0
    state.arisen_skill_ctx_addr = 0
    state.arisen_job_ctx_addr = 0
    state.arisen_pip_addr = 0
    state.far_since_t = nil
    state.pawn_chara = nil
    state.pawn_human = nil
    state.pawn_go = nil
    state.pawn_input = nil
    state.pawn_obj = nil
    state.pending_skill = nil
    state.pending_attack = nil
    state.combo_buffer = nil
    state.active_cast = nil
    state.suppress_loco_until = 0.0
    state.was_moving = false
    state.is_sprinting = false
    state.is_guarding = false
    state.is_aiming = false
    state.is_quickspelling = false
    state.arisen_was_following = false
    state.last_action_str = "Returned to Arisen"
    write_trace("release_possession complete")
end

-- v0.7.6: release BEFORE the scene tears down. Returning to title while possessed crashed twice
-- (DD2.exe+0x5246c38, worker thread): the pawn was destroyed while the camera, the Arisen's LockOnController,
-- HUD widgets and the Arisen's disabled PlayerInputProcessor still pointed at it. The first onDestroy of the
-- possessed pawn, the Arisen, or the Character/Pawn managers now releases possession and restores those.
local function install_teardown_hooks()
    local function chara_hook(type_name, field_names)
        local td = sdk.find_type_definition(type_name)
        local m = td and td:get_method("onDestroy")
        if not m then return end
        sdk.hook(m, function(args)
            if R.s2 and R.s2.active then -- v0.9.171: the second played pawn lets go before it is destroyed
                local a2 = arg_addr(args[2])
                if a2 == R.s2.chara_addr or a2 == R.s2.human_addr then pcall(R.s2_stop, "teardown: " .. type_name .. ".onDestroy") end
            end
            if R.np then -- 0.9.172: players 3+
                for _, sl in pairs(R.np.slots) do
                    if sl.active and (a2 == sl.chara_addr or a2 == sl.human_addr) then pcall(R.s2_stop, "teardown: " .. type_name .. ".onDestroy", sl) end
                end
            end
            if not state.active then return end
            local a = arg_addr(args[2])
            for _, f in ipairs(field_names) do
                local o = state[f]
                if o and addr_of(o) == a then
                    pcall(release_possession, "teardown: " .. type_name .. ".onDestroy (" .. f .. ")")
                    return
                end
            end
        end, function(r) return r end)
    end
    chara_hook("app.Character", { "pawn_chara", "arisen_chara" })
    chara_hook("app.Human", { "pawn_human", "arisen_human" })
    for _, mgr in ipairs({ "app.PawnManager", "app.CharacterManager" }) do
        local td = sdk.find_type_definition(mgr)
        local m = td and td:get_method("onDestroy")
        if m then
            sdk.hook(m, function(args)
                if R.s2 and R.s2.active then pcall(R.s2_stop, "teardown: " .. mgr .. ".onDestroy") end -- v0.9.171
                if R.np then for _, sl in pairs(R.np.slots) do if sl.active then pcall(R.s2_stop, "teardown: " .. mgr .. ".onDestroy", sl) end end end
                if state.active then pcall(release_possession, "teardown: " .. mgr .. ".onDestroy") end
            end, function(r) return r end)
        end
    end
end
install_teardown_hooks()

local function start_possession(target_pawn_idx)
    write_trace("start_possession begin", tostring(target_pawn_idx))
    ensure_enums()
    R.kbind_next = 0 -- v0.9.125: read the game's key table again (see R.kbind_read)
    local party = get_party()
    if #party == 0 then
        log_msg("Cannot possess: No party pawns found.")
        return false
    end

    -- Find requested pawn entry (or fallback to first available pawn)
    local entry = nil
    for _, e in ipairs(party) do
        if e.idx == target_pawn_idx then
            entry = e
            break
        end
    end
    if not entry then entry = party[1] end
    if R.s2 and R.s2.active and entry.idx == R.s2.idx then -- v0.9.171: player 2 plays that pawn
        log_msg("Cannot possess " .. tostring(entry.name) .. ": player 2 plays it")
        R.note = { text = tostring(entry.name) .. " is player 2's", t_end = os.clock() + 2.0 }
        return false
    end
    if R.np then -- 0.9.172: players 3+
        for n, sl in pairs(R.np.slots) do
            if sl.active and sl.idx == entry.idx then
                log_msg("Cannot possess " .. tostring(entry.name) .. ": player " .. n .. " plays it")
                R.note = { text = tostring(entry.name) .. " is player " .. n .. "'s", t_end = os.clock() + 2.0 }
                return false
            end
        end
    end

    if call(entry.chara, "get_IsDead") or call(entry.chara, "get_IsDown") then
        log_msg("Cannot possess " .. entry.name .. ": Pawn is currently downed/dead.")
        return false
    end

    -- If already possessing a pawn, cleanly release first
    if state.active then
        release_possession("switching pawn")
    end

    local cm = sdk.get_managed_singleton("app.CharacterManager")
    if not cm then return false end
    local arisen = call(cm, "get_ManualPlayer")
    if not arisen then return false end
    local arisen_human = call(arisen, "get_Human")
    local arisen_go = call(arisen, "get_GameObject")
    local arisen_pip = call(arisen, "get_InputProcessor")
    local arisen_input = call(arisen, "get_Input")
    local arisen_player_comp = call(cm, "get_ManualPlayerPlayer")
    local arisen_lockon_ctrl = arisen_player_comp and (call(arisen_player_comp, "get_LockOnCtrl") or field(arisen_player_comp, "<LockOnCtrl>k__BackingField"))

    local pawn_chara = entry.chara
    local pawn_human = entry.human
    local pawn_go = call(pawn_chara, "get_GameObject")
    local pawn_input = call(pawn_chara, "get_Input")

    if not (arisen_human and arisen_go and arisen_pip and pawn_human and pawn_go) then
        log_msg("Cannot possess: Missing required Character/Human/InputProcessor components.")
        return false
    end

    -- Snapshot original references
    state.arisen_chara = arisen
    state.arisen_human = arisen_human
    state.arisen_go = arisen_go
    state.arisen_input = arisen_input
    state.arisen_pip = arisen_pip
    state.arisen_track = field(arisen_human, "Track")
    state.arisen_player_comp = arisen_player_comp
    state.arisen_lockon_ctrl = arisen_lockon_ctrl
    state.arisen_skill_ctx = get_skill_ctx(arisen_human)
    state.arisen_job_ctx = call(arisen_human, "get_JobContext")
    state.arisen_chara_addr = addr_of(arisen)
    state.arisen_skill_ctx_addr = addr_of(state.arisen_skill_ctx)
    state.arisen_job_ctx_addr = addr_of(state.arisen_job_ctx)
    state.arisen_pip_addr = addr_of(arisen_pip)
    state.far_since_t = nil
    state.next_auto_warp_t = os.clock() + (cfg.arisen_warp_cooldown or 4.0)
    state.arisen_stay = false
    state.warp_check = nil
    state.next_skill_refresh_t = 0.0

    state.pawn_idx = entry.idx
    state.pawn_name = entry.name
    state.pawn_job = entry.job
    state.pawn_skills = entry.skills
    state.pawn_chara = pawn_chara
    state.pawn_human = pawn_human
    state.pawn_go = pawn_go
    state.pawn_input = pawn_input
    state.pawn_dash_opt0 = R.dash_opt_take(pawn_input)
    state.pawn_obj = entry.pawn
    state.pending_skill = nil
    state.pending_attack = nil
    state.combo_buffer = nil
    state.active_cast = nil
    state.suppress_loco_until = 0.0
    state.was_moving = false
    state.is_sprinting = false
    state.is_guarding = false
    state.is_aiming = false
    state.is_quickspelling = false
    state.arisen_was_following = false
    state.frames_since_start = 0
    state.arisen_pip_blocked_count = 0

    local hcac = call(pawn_human, "get_HumanCommonActionCtrl") or field(pawn_human, "<HumanCommonActionCtrl>k__BackingField")
    state.pawn_orig_is_player = hcac and field(hcac, "IsPlayer") or false
    state.pawn_orig_is_arisen = field(pawn_human, "IsArisen") or false

    -- Dash-to-requested-move-speed: v0.6 forced it on for the puppeteer (which also requests the speed every frame).
    -- 0.9.172: reported 2026-11-20, a played pawn's sprint drops back to run speed after a moment while the Arisen's
    -- doesn't; with this on, the dash follows RequestedMoveSpeedOfNormalLocomotion, which nothing sets under native
    -- controls. Left as the game has it unless cfg.native_dash_to_req; restored at release.
    state.pawn_orig_dash_req = hcac and call(hcac, "get_IsEnableDashToRequestedMoveSpeedOfNormalLocomotion")
    if hcac and cfg.native_dash_to_req then
        call(hcac, "set_IsEnableDashToRequestedMoveSpeedOfNormalLocomotion(System.Boolean)", true)
    end

    -- Rebind LockOnCtrl.Chara to Pawn so spells & ranged attacks lock onto enemies from the Pawn's perspective
    -- (not in co-op: player 1 keeps his lock-on; the pawn's native processor gets its own)
    if arisen_lockon_ctrl and not coop.active then
        set_field(arisen_lockon_ctrl, "Chara", pawn_chara)
        call(arisen_lockon_ctrl, "clearLockOn")
    end

    -- 1. Suppress Pawn AI & Navigation (soft flags only)
    if cfg.sub_suppress_ai then
        write_trace("start_possession: set_pawn_ai_suppressed")
        set_pawn_ai_suppressed(pawn_chara, entry.pawn, true, true)
    end
    -- v0.9.38: the flags above only stop NEW thinking; whatever the pawn's AI was already doing (running to a
    -- spot, an order) kept playing and fought the player's input for a while. End the decision in progress and,
    -- when the game allows it, drop him to idle. Each step is the game's own call and is skipped on error.
    R.ping = nil -- v0.9.112: the selection arrow goes the moment a character is taken over
    if R.dev then R.tk = { t0 = os.clock(), next = 0, log = {} } end
    if cfg.possess_interrupt_ai then R.guide_t0 = nil; R.guide_stop(pawn_chara, entry.name); R.interrupt_ai(pawn_chara, entry.name, true) end

    -- 2. Apply selected Control Mode
    write_trace("start_possession: apply control_mode", tostring(cfg.control_mode))
    if cfg.control_mode == 1 or cfg.control_mode == 3 then
        apply_native_processor_binding(true)
    elseif cfg.sub_disable_arisen_pip then
        -- v0.8.5: not disabled any more (that cut your buttons off from the pawn); hooks 1a/1b block him instead
        call(arisen_pip, "set_IsEnable(System.Boolean)", true)
        -- Ensure Arisen stops walking if they were moving when F6 was pressed
        local ar_sel = call(arisen, "get_HumanActionSelector")
        if ar_sel and call(ar_sel, "isEnableRequestIdle") then
            call(ar_sel, "requestIdleImpl(System.Boolean)", false)
        end
    end

    -- 3. Attach Camera to Pawn
    if cfg.sub_camera_attach then
        write_trace("start_possession: attach_camera_to")
        R.cine_begin(pawn_chara) -- v0.9.169: look at them, then glide behind them
        attach_camera_to(pawn_go)
    end

    for k in pairs(hud_widgets) do hud_widgets[k] = nil end
    state.pawn_sel_addr = addr_of(call(pawn_chara, "get_HumanActionSelector"))
    state.active = true
    R.session_write(true, state.pawn_job, state.pawn_name)
    pcall(native_build)
    pcall(apply_native_hud_skills, true)
    pcall(apply_native_hud_gauges, true)
    state.next_hud_check_t = os.clock() + 0.5
    state.last_action_str = "Possessed " .. entry.name .. " (" .. entry.job_name .. ")"
    log_msg(string.format("NOW CONTROLLING: %s (%s) [Mode %d]", entry.name, entry.job_name, cfg.control_mode))
    R.note = { text = "Playing as " .. tostring(entry.name), t_end = os.clock() + 3.0 }
    if R.api_fire then -- v0.9.170 mod API
        pcall(R.api_fire, "possess", { player = coop.active and 2 or 1, name = entry.name, job = entry.job, chara = pawn_chara, from_name = R.api_switch_from })
        if R.api_switch_from then pcall(R.api_fire, "switch", { player = coop.active and 2 or 1, from_name = R.api_switch_from, to_name = entry.name }) end
        R.api_switch_from = nil
    end
    write_trace("start_possession complete")
    return true
end

-- ----------------------------------------------------------------------------
-- v0.9 Couch co-op: player 2 plays a pawn on a controller, player 1 plays the Arisen on mouse+keyboard.
-- Built without a live test (2026-11-11 night); every guess below self-checks and reports in the telemetry
-- (data/DPC_arisen_brain.json -> "coop") and the log.
--   * Pawn: DPC's native controls, fed only from the pad (via.hid.GamePad merged device). Pad buttons become
--     CharacterInput actions through the game's own pad assignment (UserInput.getButton(action) on the Arisen's
--     input), else a built-in DualSense layout.
--   * Arisen: runs normally. processButton (the pad path) gets an empty pad for his input; his move stick is
--     replaced by the keyboard axis (UserInput.KeyboardMouseAxisL); any pad-derived actions left in his
--     buttons are masked out.
--   * Camera stays on the Arisen; DPC writes data/DPC_coop.json for CameraDistance's co-op framing.
-- ----------------------------------------------------------------------------
local COOP_SKILLS = { "Skill1", "Skill2", "Skill3", "Skill4" }
-- v0.9.124: player 2's buttons follow the game's own controller assignment (R.bind.list, every binding the options
-- menu shows), whatever the player has remapped. Until 0.9.123 the fixed table here was the layout measured on the
-- user's controller on 2026-11-12, which turned out to be his own remap (R1 / R2 attacks, L2 vocation action,
-- Triangle dash, Circle sheathe), so with the game's default layout player 2 got the wrong action on most buttons.
-- The table below is only the fallback when the game's list cannot be read, and it is now the game's DEFAULT
-- layout (read from the running game on 2026-11-17, the tester's notes):
--   Square light, Triangle heavy, Cross jump, Circle interact / dash, L3 dash, R2 grab, L2 sheathe / draw / cancel,
--   R1 vocation action / aim, L1 skill shift, R3 lock-on, L1 + Square / Triangle / Cross / Circle = skills 1 - 4.
local COOP_SHIFT_L1, COOP_SHIFT_L2 = "LTrigTop", "RTrigTop"
local COOP_BUILTIN = {
    { act = { "AttackS", "Present", "GimmickSpecial2", "GliderDescent" }, pad = { "RLeft" } },
    { act = { "AttackL", "GimmickSpecial1", "GliderAscent", "Job09AstralUp" }, pad = { "RUp" } },
    { act = { "Jump", "GimmickCancel", "Job09AstralDown" }, pad = { "RDown" } },
    { act = { "Interact", "Dash", "Job01GuardLockOnChange" }, pad = { "RRight" } },
    { act = { "Dash" }, pad = { "LStickPush" } },
    { act = { "Grab" }, pad = { "RTrigBottom" } },
    { act = { "ActCancel", "Sheathe", "Draw" }, pad = { "LTrigBottom" } },
    { act = { "AimHold", "JobSpecialAction", "ShootRelease", "ThrowRelease", "Shift1OnlySpecificJob", "GimmickAction" }, pad = { "RTrigTop" } },
    { act = { "Shift1", "Shift2" }, pad = { "LTrigTop" } },
    { act = { "SwitchLockOn", "CameraReset", "SwitchSkill" }, pad = { "RStickPush" } },
    { act = { "Skill1" }, pad = { "RLeft" }, shift = true },
    { act = { "Skill2" }, pad = { "RUp" }, shift = true },
    { act = { "Skill3" }, pad = { "RDown" }, shift = true },
    { act = { "Skill4" }, pad = { "RRight" }, shift = true },
}
-- Not for player 2's pawn: pawn orders and the item shortcuts (the mod handles his D-pad itself), and Skill5 / 6
-- (the chord logic in coop.pad_input adds those).
local COOP_NOT_P2 = { Come = true, Go = true, Help = true, Wait = true, ItemMenu = true, Lantern = true,
    RecoverHpItem = true, RecoverStaminaItem = true, Skill5 = true, Skill6 = true }

local coop_pad_cache = nil
local function coop_pad_values()
    if coop_pad_cache then return coop_pad_cache end
    local _, by_name = read_enum("via.hid.GamePadButton")
    if by_name and next(by_name) then coop_pad_cache = by_name end
    return by_name or {}
end
R.pad_values = coop_pad_values

-- Try the game's own assignment: UserInput.getButton(actionFlag) -> pad button(s) bound to that action.
local function coop_build_game_map()
    local inp = state.arisen_input
    if not (inp and ACTION_FLAGS) then return nil end
    local all_pad = 0
    for _, v in pairs(coop_pad_values()) do if type(v) == "number" and v > 0 then all_pad = all_pad | v end end
    local map, n = {}, 0
    for name, flag in pairs(ACTION_FLAGS) do
        local ok, b = pcall(inp.call, inp, "getButton(System.UInt64)", flag)
        if ok and type(b) == "number" and b > 0 and (all_pad == 0 or (b & ~all_pad) == 0) then
            map[#map + 1] = { flag = flag, name = name, pad = b }
            n = n + 1
        end
    end
    if n < 6 then return nil, n end
    return map, n
end

-- v0.9.124: the map from the game's assignment list. An entry with `pre` only counts while that shift is held.
local function coop_build_assign_map()
    local l = R.bind and R.bind.list
    if not l or #l < 10 then return nil, l and #l or 0 end
    local map = {}
    for _, e in ipairs(l) do
        if not COOP_NOT_P2[e.name] and e.pad ~= 0 and e.flag and e.flag ~= 0 then
            map[#map + 1] = { flag = e.flag, name = e.name, pad = e.pad, shift = e.pre ~= nil, pre = e.pre }
        end
    end
    return map, #map
end

local function coop_build_builtin_map()
    local pv = coop_pad_values()
    local map = {}
    for _, e in ipairs(COOP_BUILTIN) do
        local pad = 0
        for _, pn in ipairs(e.pad) do pad = pad | (pv[pn] or 0) end
        if pad ~= 0 then
            for _, an in ipairs(e.act) do
                if ACTION_FLAGS[an] then map[#map + 1] = { flag = ACTION_FLAGS[an], name = an, pad = pad, shift = e.shift } end
            end
        end
    end
    return map
end

local function coop_ensure_map()
    if coop.map then return end
    ensure_enums()
    if cfg.coop_map_assign ~= false then
        pcall(function() R.bind_next = 0; R.bind_read() end)
        local m, n = coop_build_assign_map()
        if m then
            coop.map, coop.map_src = m, "game assignment (" .. n .. " bindings)"
        else
            coop_event("the game's controller assignment could not be read (" .. tostring(n) .. " bindings) -> default layout")
        end
    end
    if not coop.map then
        coop.map = coop_build_builtin_map()
        coop.map_src = "default layout (" .. #coop.map .. " actions)"
    end
    -- v0.9.4: optional overrides in data/DPC_coop_layout.json, read at each co-op start (no script reset needed):
    -- { "map": [ { "pad": "RLeft", "flags": ["0x4000"], "name": "Grab" }, { "pad": "RUp", "act": ["Dash"] } ] }
    -- An entry replaces the built-in non-skill entries for the same button; skill entries (L1/L2 + face) stay.
    -- v0.9.124: off unless coop_layout_file is switched on. The file that shipped until 0.9.123 held three entries
    -- measured on the tester's remapped controller (Grab on Square, Dash on Triangle); with the map now read from
    -- the game it would put those on the wrong buttons for everybody else.
    local okl, lay = false, nil
    if cfg.coop_layout_file then okl, lay = pcall(json.load_file, "DPC_coop_layout.json") end
    if okl and type(lay) == "table" and type(lay.map) == "table" then
        local pv, added = coop_pad_values(), 0
        local is_skill = {}
        for _, sk in ipairs(COOP_SKILLS) do is_skill[sk] = true end
        for _, le in ipairs(lay.map) do
            local pad = type(le.pad) == "number" and le.pad or pv[le.pad] or tonumber(tostring(le.pad or ""))
            if pad and pad ~= 0 then
                local keep = {}
                for _, e in ipairs(coop.map) do
                    if e.pad ~= pad or is_skill[e.name] then keep[#keep + 1] = e end
                end
                coop.map = keep
                for _, f in ipairs(le.flags or {}) do
                    local fv = type(f) == "number" and f or tonumber(tostring(f))
                    if fv and fv ~= 0 then coop.map[#coop.map + 1] = { flag = fv, name = le.name or "custom", pad = pad }; added = added + 1 end
                end
                for _, an in ipairs(le.act or {}) do
                    if ACTION_FLAGS[an] then coop.map[#coop.map + 1] = { flag = ACTION_FLAGS[an], name = an, pad = pad }; added = added + 1 end
                end
            end
        end
        coop.map_src = coop.map_src .. " + layout file (" .. added .. ")"
    end
    local parts = {}
    for _, e in ipairs(coop.map) do parts[#parts + 1] = string.format("%s=%X", e.name, e.pad) end
    table.sort(parts)
    log_msg("Co-op pad map " .. coop.map_src .. ": " .. table.concat(parts, " "))
end

-- Player 2's input: pad buttons -> action flags, pad left stick (dead zone). Called on the game thread.
coop.pad_input = function()
    coop_ensure_map()
    local btn = pad_buttons or 0
    coop.last_btn = btn
    local pv = coop_pad_values()
    if cfg.coop_aim and cfg.coop_auto_target then btn = R.ta_p2_input(btn, pv) end
    -- v0.9.124: the shift buttons come from the game's assignment (Shift1; and Shift1OnlySpecificJob, the vocation
    -- action button, which the game treats as a skill shift for the bow vocations only: see the 0.9.87 note)
    local l1, l2 = pv[COOP_SHIFT_L1] or 0x100, pv[COOP_SHIFT_L2] or 0x400
    local bow = state.pawn_job == 2 or state.pawn_job == 8
    local shift1_held = R.bind_held("Shift1", btn, l1)
    local shift2_held = R.bind_held("Shift2", btn, l1)
    local shift_held = shift1_held or (bow and R.bind_held("Shift1OnlySpecificJob", btn, l2))
    -- v0.9.13 chord skills: shift + two face buttons together fire Skill5 / Skill6 (the tester's layout). Both
    -- buttons rarely land on the same frame, so a face button that belongs to a chord waits coop_chord_window
    -- for its partner before it counts as its own skill. A chord stays latched until both buttons are up, so
    -- letting go of one doesn't fire the single skill.
    local chord_on, pulsing = 0, false
    -- v0.9.22: with a skill in slot 5 or 6 the game moves skills 3 and 4 to L1 + R1 / R2 (the tester's HUD
    -- screenshot, 2026-11-15) and Circle / Cross keep sheathe / jump (they are the chord partners).
    local six = state.pawn_skills and ((state.pawn_skills[5] or 0) ~= 0 or (state.pawn_skills[6] or 0) ~= 0)
    do
        local now = os.clock()
        coop.face_t, coop.face_sh, coop.face_out = coop.face_t or {}, coop.face_sh or {}, coop.face_out or {}
        local sq, cr, ci, tri = pv.RLeft or 0x40, pv.RDown or 0x20, pv.RRight or 0x80, pv.RUp or 0x10
        local faces = { sq, cr, ci, tri }
        -- v0.9.124: "face" buttons = every single button that is (part of) a skill binding in the game's list
        if R.bind and next(R.bind.pad) then
            local seen, fl = {}, {}
            for sl = 1, 6 do
                local m = R.bind.pad[sl] or 0
                for bit = 0, 15 do
                    local one = 1 << bit
                    if (m & one) ~= 0 and not seen[one] then seen[one] = true; fl[#fl + 1] = one end
                end
            end
            if #fl > 0 then faces = fl end
        end
        -- v0.9.76 (co-op Thief, 2026-11-16: "L1 skills do not seem to work"; recording: L1 held, a quick Square
        -- tap gave no Skill flag at all, and Grab for a few frames when L1 came up first):
        --  * the wait for a chord partner (coop_chord_window, 0.16 s) ate every tap shorter than that. It now
        --    only applies when a chord is possible (a skill in slot 5 or 6), and a button released during the
        --    wait still fires its skill (a 0.1 s pulse).
        --  * a face button pressed under L1 never turns into its own action (grab, jump, ...) when L1 is let
        --    go first; it is ignored until released.
        for _, b in ipairs(faces) do
            if (btn & b) ~= 0 then
                if not coop.face_t[b] then coop.face_t[b], coop.face_sh[b], coop.face_out[b] = now, shift_held, false end
            else
                if coop.face_t[b] and coop.face_sh[b] and not coop.face_out[b] then
                    coop.pulse_pad, coop.pulse_until = b, now + 0.10
                    coop.pulses = (coop.pulses or 0) + 1
                end
                coop.face_t[b], coop.face_sh[b], coop.face_out[b] = nil, nil, nil
            end
        end
        local bp = R.bind and R.bind.pad or {}
        local chords = { { bp[6] or (sq | cr), "Skill6" }, { bp[5] or (tri | ci), "Skill5" } } -- 0.9.100: from the game's assignment
        local latch = coop.chord_latch
        if latch and (btn & latch.pads) == 0 then coop.chord_latch, latch = nil, nil end
        if cfg.coop_chord_skills and six and not latch and shift_held then
            for _, c in ipairs(chords) do
                if (btn & c[1]) == c[1] and ACTION_FLAGS[c[2]] then
                    latch = { pads = c[1], flag = ACTION_FLAGS[c[2]], name = c[2] }
                    coop.chord_latch = latch
                    coop.chords = (coop.chords or 0) + 1
                    coop_event("chord " .. c[2])
                    break
                end
            end
        end
        if latch then
            for _, b in ipairs(faces) do if (latch.pads & b) ~= 0 then coop.face_out[b] = true end end
            btn = btn & ~latch.pads
            if shift_held then chord_on = latch.flag | (ACTION_FLAGS.Shift1 or 0) | (ACTION_FLAGS.Shift2 or 0) end
        elseif shift_held and cfg.coop_chord_skills and six then
            -- hold back a lone chord button for a moment
            for _, b in ipairs(faces) do
                if (btn & b) ~= 0 and now - (coop.face_t[b] or now) < (cfg.coop_chord_window or 0.09) then
                    btn = btn & ~b
                end
            end
        end
        for _, b in ipairs(faces) do
            if (btn & b) ~= 0 and coop.face_sh[b] then
                if shift_held then coop.face_out[b] = true else btn = btn & ~b end
            end
        end
        if coop.pulse_until and now < coop.pulse_until then
            btn = btn | coop.pulse_pad
            shift_held = true
            pulsing = true
        end
    end
    local is_skill = {}
    for _, sk in ipairs(COOP_SKILLS) do is_skill[sk] = true end
    local on, skill_pads = 0, 0
    for _, e in ipairs(coop.map) do
        local epad = e.pad
        local sn = tonumber(tostring(e.name):match("^Skill(%d)$") or "")
        local gb = sn and R.bind and R.bind.pad[sn]
        if gb then epad = gb end -- 0.9.100: the game's own button for this slot
        -- (0.9.124: the old "skills 3 / 4 move to R1 / R2 with a chord slot in use" rule is gone; that was the
        -- user's remap, not something the game does)
        if epad ~= 0 and (btn & epad) == epad then
            if is_skill[e.name] then
                if shift_held then on = on | e.flag; skill_pads = skill_pads | epad end
            elseif e.pre == 15 then
                if shift2_held then on = on | e.flag; skill_pads = skill_pads | epad end
            elseif e.pre then
                if shift1_held then on = on | e.flag; skill_pads = skill_pads | epad end
            else
                on = on | e.flag
            end
        end
    end
    if skill_pads ~= 0 then
        -- shift + face button is a skill only, not also that button's own action (jump, sheathe, ...)
        for _, e in ipairs(coop.map) do
            if not is_skill[e.name] and not e.pre and (e.pad & skill_pads) ~= 0 then on = on & ~e.flag end
        end
    end
    if pulsing and skill_pads ~= 0 then on = on | (ACTION_FLAGS.Shift1 or 0) | (ACTION_FLAGS.Shift2 or 0) end -- L1 may already be up
    on = on | chord_on
    coop.last_flags = on
    coop.last_stick = { pad_stick_x or 0.0, pad_stick_y or 0.0 }
    local ax, ay = pad_stick_x or 0.0, pad_stick_y or 0.0
    local mag = math.sqrt(ax * ax + ay * ay)
    if mag < (cfg.coop_pad_deadzone or 0.15) then ax, ay, mag = 0.0, 0.0, 0.0 end
    if mag > 1.0 then ax, ay, mag = ax / mag, ay / mag, 1.0 end
    return on, ax + 0.0, ay + 0.0, mag + 0.0
end

-- 0.9.172-dev20 co-op camera turn (two controllers, co-op aiming on). cfg.coop_cam_turn:
--   "p1"     player 1's right stick turns the camera as before; while he has a kept target, his flicks switch it
--            and, with his stick at rest, the camera turns toward him and that target
--   "shared" a slow push on either right stick turns the camera (both add up); quick flicks only switch targets
--   "auto"   right sticks only target; the camera turns by itself toward the players' targets, or the way the
--            group is moving
-- Written into the Arisen's AxisR (what the game's camera reads) in his processor's pre-hook.
R.cct = { g1 = {}, g2 = {}, sign = 1, wrote = false }
R.cam_yaw = function()
    local cm = sdk.get_managed_singleton("app.CharacterManager")
    local cf = cm and field(cm, "<CameraFront>k__BackingField")
    if cf and (cf.x ~= 0 or cf.z ~= 0) then return math.atan(cf.x, cf.z) end
    return nil
end
R.cam_steer = function(want, now)
    local c = R.cct
    local yaw = R.cam_yaw()
    if not (yaw and want) then return 0.0 end
    local err = brain_angdiff(want, yaw)
    -- which way a positive stick turns depends on the player's camera options: learn it from the result
    if c.st_t and now - c.st_t > 0.5 then
        if math.abs(err) > math.abs(c.st_err) + math.rad(5) and math.abs(c.st_x) > 0.2 then
            c.sign = -c.sign
            c.flips = (c.flips or 0) + 1
        end
        c.st_t = nil
    end
    if math.abs(err) < math.rad(cfg.coop_cam_deadband or 8.0) then return 0.0 end
    local x = math.max(-1.0, math.min(1.0, err / math.rad(45.0))) * (cfg.coop_cam_auto_speed or 0.5) * c.sign
    if not c.st_t then c.st_t, c.st_err, c.st_x = now, err, x end
    return x
end
-- dev38: while a controller turns the camera with player 1 on keyboard and mouse, the rotating cameras read stick
-- speed, not mouse speed (app.RotateCameraControllerBase / Root.get_IsMouseInputEnv answers false that frame)
R.cam_env_hooked = false
R.cam_env_hook = function()
    if R.cam_env_hooked then return end
    R.cam_env_hooked = true
    for _, tn in ipairs({ "app.RotateCameraControllerBase", "app.RotateCameraControllerRoot" }) do
        local td = sdk.find_type_definition(tn)
        local m = td and td:get_method("get_IsMouseInputEnv")
        if m then
            sdk.hook(m, function() end, function(r)
                local c = R.cct
                if c and c.pad_now and os.clock() - c.pad_now < 0.1 and R.tp_kb() then
                    R.cam_env_n = (R.cam_env_n or 0) + 1
                    return sdk.to_ptr(0)
                end
                return r
            end)
        end
    end
end
R.cam_turn = function(inp)
    local c = R.cct
    c.wrote = false
    local mode = cfg.coop_cam_turn or "p1"
    local now = os.clock()
    local p1 = R.tp_p1()
    local rx1, ry1 = p1.rx or 0.0, p1.ry or 0.0
    local rx2, ry2 = pad_stick_rx or 0.0, pad_stick_ry or 0.0
    -- 0.9.172-dev36: player 1 on keyboard and mouse: a frame where the mouse moved keeps the game's own camera input
    -- dev37 (the tester: "the camera seems very very rough" with player 1 on keyboard and mouse): the game smooths the
    -- mouse over the frames after it moves, and those frames were overwritten with the controllers' (zero) share.
    -- Now the game's own camera input is left alone unless some controller's right stick is actually pushed.
    if R.tp_kb() and mode ~= "p1" then
        -- dev44: the get_IsMouseInputEnv hook (dev38) is no longer installed. It never answered once (counter 0), and
        -- the camera getters may run on the game's worker threads, where a Lua hook is a crash risk; the game crashed
        -- in a worker thread (light / haze update, c0000005) at [time] with it installed. The controller-mode switch
        -- (dev39) is what made the sticks work.
        local pushed = math.sqrt(rx2 * rx2 + ry2 * ry2) >= 0.3
        for _, sl in pairs(R.np and R.np.slots or {}) do
            local q = sl.active and sl.pad_cam
            if q and math.sqrt((q.rx or 0) ^ 2 + (q.ry or 0) ^ 2) >= 0.3 then pushed = true end
        end
        c.kb_frames = (c.kb_frames or 0) + 1
        -- dev42 diagnostics (the tester: "P2 camera sometimes doesn't work ... when I do P3 camera, afterwards P2 camera
        -- will work"): the last 60 frames where player 2's stick was pushed, for a bridge read
        -- dev44: 60 frames was half a second ("too short for me to get back here"): now 10 samples a second over
        -- the last 60 s, every player's stick and gate
        if now >= (c.ring_next or 0) then
            local parts = {}
            local function add(n, x, y, g)
                if math.sqrt(x * x + y * y) >= 0.3 then
                    parts[#parts + 1] = string.format("P%d %.2f fl=%s", n, x, tostring(g and g.fl))
                end
            end
            add(2, rx2, ry2, c.g2)
            for n, sl in pairs(R.np and R.np.slots or {}) do
                local q = sl.pad_cam
                if q then add(n, q.rx or 0, q.ry or 0, c.gn and c.gn[n]) end
            end
            if #parts > 0 then
                c.ring_next = now + 0.1
                local hm, mv = nil, nil
                pcall(function() hm = sdk.get_managed_singleton("app.UserInputManager"):call("get_HIDInputMode") end)
                pcall(function() mv = inp:get_field("<IsMouseMovedInFrame>k__BackingField") end)
                local ring = c.p2ring or {}; c.p2ring = ring
                ring[#ring + 1] = { t = now, s = string.format("%.1f %s hid=%s mouse=%s wrote=%.2f", now, table.concat(parts, " "), tostring(hm), tostring(mv), c.last_x or 0) }
                while #ring > 0 and now - ring[1].t > 60.0 do table.remove(ring, 1) end
            end
        end
        if not pushed then
            -- dev43, found with the bridge (player 4's gate stuck in "flick" while his stick was at rest): the gates
            -- only see a stick when R.cam_turn gets past this point, i.e. while some stick is pushed. A flick latches
            -- the gate until it sees the stick back at rest, and with nobody pushing it never did: that player's
            -- next slow push read as the same flick and was ignored, until someone else's push let the gate see the
            -- rest ("when I do P3 camera, afterwards P2 camera will work"). Every gate now sees every frame.
            R.cam_gate(c.g1, rx1, ry1, now)
            R.cam_gate(c.g2, rx2, ry2, now)
            c.gn = c.gn or {}
            for n, sl in pairs(R.np and R.np.slots or {}) do
                local q = sl.pad_cam
                if q then c.gn[n] = c.gn[n] or {}; R.cam_gate(c.gn[n], q.rx or 0.0, q.ry or 0.0, now) end
            end
            c.wrote = true
            return
        end
        c.kb_pushed = (c.kb_pushed or 0) + 1
        -- dev38 (the tester: "slow right stick pushes do nothing to the camera when M+KB is P1"): the game is in mouse mode,
        -- so the camera turned the stick's AxisR at the mouse's rate (next to nothing). Say it is a stick frame.
        -- dev39 ("Camera does not move at all with any right stick movement in this m+kb mode"; no frame reached the
        -- hook below): a pushed controller stick now wins over the mouse that frame, and the game is put in controller
        -- mode (UserInputManager.HIDInputMode 0, what it does itself when a controller is touched; the mouse puts it
        -- back). At most every 0.25 s.
        c.pad_now = now
        pcall(function()
            inp:set_field("<IsPadAxisRMovedInFrame>k__BackingField", true)
            inp:set_field("<IsMouseMovedInFrame>k__BackingField", false)
        end)
        if now >= (c.hid_next or 0) then
            c.hid_next = now + 0.25
            pcall(function()
                local mgr = sdk.get_managed_singleton("app.UserInputManager")
                if mgr and mgr:call("get_HIDInputMode") == 1 then
                    mgr:call("set_HIDInputMode", 0)
                    c.hid_sets = (c.hid_sets or 0) + 1
                end
            end)
        end
    end
    -- 0.9.172-dev36: each player's stick can be left out (cfg.coop_cam_from), and players 3+ turn it too
    local from = cfg.coop_cam_from or {}
    if from.p1 == false then rx1, ry1 = 0.0, 0.0 end
    if from.p2 == false then rx2, ry2 = 0.0, 0.0 end
    local function more(x, y)
        c.gn = c.gn or {}
        for n, sl in pairs(R.np and R.np.slots or {}) do
            local q = sl.pad_cam
            if sl.active and q and from["p" .. n] ~= false then
                c.gn[n] = c.gn[n] or {}
                local a, b = R.cam_gate(c.gn[n], q.rx or 0.0, q.ry or 0.0, now)
                x, y = x + a, y + b
                -- dev40 diagnostics: per player, the largest raw right stick seen and how often it reached the camera
                local d = c.np_dbg or {}; c.np_dbg = d
                local e = d[n] or { raw = 0, used = 0, seen = 0 }; d[n] = e
                local m = math.max(math.abs(q.rx or 0), math.abs(q.ry or 0))
                if m > e.raw then e.raw = m end
                if m >= 0.3 then e.seen = e.seen + 1 end
                if a ~= 0.0 or b ~= 0.0 then e.used = e.used + 1 end
            end
        end
        return x, y
    end
    local ax, _, az = brain_pos(state.arisen_chara)
    local function toward(e)
        local ex, _, ez = brain_pos(e)
        if not (ax and ex) then return nil end
        return math.atan(ex - ax, ez - az)
    end
    local x, y
    if mode == "shared" then
        local x1, y1 = R.cam_gate(c.g1, rx1, ry1, now)
        local x2, y2 = R.cam_gate(c.g2, rx2, ry2, now)
        local sx, sy = more(x1 + x2, y1 + y2)
        x, y = math.max(-1.0, math.min(1.0, sx)), math.max(-1.0, math.min(1.0, sy))
    elseif mode == "auto" then
        local want
        local t1, t2 = R.ta.p1, coop.tgt
        local px, _, pz = brain_pos(state.pawn_chara)
        if t1 or t2 then
            local sx, sz, n = 0.0, 0.0, 0
            for _, e in ipairs({ t1, t2 }) do
                local ex, _, ez = brain_pos(e)
                if ex then sx, sz, n = sx + ex, sz + ez, n + 1 end
            end
            local gx, gz = ax, az
            if px and ax then gx, gz = (ax + px) * 0.5, (az + pz) * 0.5 end
            if n > 0 and gx then want = math.atan(sx / n - gx, sz / n - gz) end
        else
            -- the way the group is moving (both characters' displacement over ~0.5 s)
            if ax then
                c.hist = c.hist or {}
                local h = c.hist
                h[#h + 1] = { t = now, ax = ax, az = az, px = px or ax, pz = pz or az }
                while #h > 2 and now - h[1].t > 0.5 do table.remove(h, 1) end
                local o = h[1]
                local dx = ((ax - o.ax) + ((px or ax) - o.px)) * 0.5
                local dz = ((az - o.az) + ((pz or az) - o.pz)) * 0.5
                if dx * dx + dz * dz > 0.5 ^ 2 then want = math.atan(dx, dz) end
            end
        end
        -- dev22: a slow push on either stick still turns the camera ("not enough camera control"); the camera's own
        -- turning waits 1.5 s after the last push
        local x1, y1 = R.cam_gate(c.g1, rx1, ry1, now)
        local x2, y2 = R.cam_gate(c.g2, rx2, ry2, now)
        local sx, sy = more(x1 + x2, y1 + y2)
        if sx ~= 0.0 or sy ~= 0.0 then
            c.push_t = now
            x, y = math.max(-1.0, math.min(1.0, sx)), math.max(-1.0, math.min(1.0, sy))
        else
            if want == nil or now - (c.push_t or -10) < 1.5 then
                inp:set_field("<AxisR>k__BackingField", Vector2f.new(0.0, 0.0))
                c.wrote = true
                c.st_t = nil
                return
            end
            x, y = R.cam_steer(want, now), 0.0
        end
    else -- "p1"
        if not R.ta.p1 then return end -- as before (the old block below handles player 2's stick)
        x, y = R.cam_gate(c.g1, rx1, ry1, now)
        if cfg.coop_cam_p1_steer and x == 0.0 and y == 0.0 and math.sqrt(rx1 * rx1 + ry1 * ry1) < 0.3 then
            x = R.cam_steer(toward(R.ta.p1), now)
        end
    end
    inp:set_field("<AxisR>k__BackingField", Vector2f.new(x + 0.0, y + 0.0))
    c.wrote = true
    c.n = (c.n or 0) + 1
    c.last_x, c.last_y = x, y -- dev42 diagnostics
end

-- Player 1's Arisen, in his processor's pre-hook: keyboard stick only, and no pad-derived buttons.
coop.filter = function()
    local inp = state.arisen_input
    if not inp then return end
    if R.robot_p2 and R.robot_p2() then return end -- dev14: robot is player 2; the controller is player 1's
    -- camera: the camera reads this input's AxisR after this point. v0.9.2: KeyboardMouseAxisR is only filled on
    -- some frames, so copying it (v0.9.0) froze the camera; now AxisR is only cleared on frames where player 2's
    -- right stick is pushed and the mouse did not move.
    local two = R.tp_on()
    if two and cfg.coop_aim and pcall(R.cam_turn, inp) and R.cct.wrote then
        -- 0.9.172-dev20: the co-op camera turn mode wrote AxisR this frame
    elseif R.kb_wait and R.kb_wait() then
        -- dev44: waiting for player 2 with player 1 on keyboard: controllers don't turn the camera yet
        local any = false
        for _, d in ipairs(R.tp_devs()) do
            local v = R.tp_read(d)
            if math.abs(v.rx) + math.abs(v.ry) > 0.25 then any = true break end
        end
        if any then
            pcall(function()
                if not inp:get_field("<IsMouseMovedInFrame>k__BackingField") then inp:set_field("<AxisR>k__BackingField", Vector2f.new(0.0, 0.0)) end
            end)
        end
    elseif two and R.tp_kb() then
        -- 0.9.172-dev36: player 1 on keyboard and mouse: only clear the controllers' share when the mouse didn't move
        if math.abs(pad_stick_rx) + math.abs(pad_stick_ry) > 0.25 then
            pcall(function()
                if not inp:get_field("<IsMouseMovedInFrame>k__BackingField") then inp:set_field("<AxisR>k__BackingField", Vector2f.new(0.0, 0.0)) end
            end)
        end
    elseif two and math.abs(pad_stick_rx) + math.abs(pad_stick_ry) > 0.25 and (cfg.coop_two_pads_cam or 1) == 1 then
        -- v0.9.170 (dev): two controllers. The game's camera input mixes both right sticks; player 1's alone instead.
        local p1 = R.tp_p1()
        local okr = pcall(inp.set_field, inp, "<AxisR>k__BackingField", Vector2f.new(p1.rx + 0.0, p1.ry + 0.0))
        if okr then R.tp.cam_fixes = (R.tp.cam_fixes or 0) + 1 else cfg.coop_two_pads_cam = 2; coop_event("two controllers: camera write failed -> hold still") end
    elseif cfg.coop_block_p2_camera and math.abs(pad_stick_rx) + math.abs(pad_stick_ry) > 0.25 then
        local okr = pcall(function()
            if not inp:get_field("<IsMouseMovedInFrame>k__BackingField") then
                inp:set_field("<AxisR>k__BackingField", Vector2f.new(0.0, 0.0))
                coop.cam_fixes = (coop.cam_fixes or 0) + 1
            end
        end)
        if not okr then cfg.coop_block_p2_camera = false; coop_event("camera block write failed -> off") end
    end
    -- buttons: mask what player 2 is pressing (second layer behind the processButton pad zeroing)
    local mask = coop.last_flags or 0
    local on = inp:get_field("ButtonOnFlags") or 0
    -- v0.9.5: off by default. The mask also removed actions player 1 pressed himself: while player 2 held L2
    -- (guard = AimHold bit) the Arisen could not aim with the right mouse button. The processButton pad zeroing
    -- already keeps the controller off the Arisen.
    if mask ~= 0 and cfg.coop_mask_p2_flags then
        inp:set_field("ButtonOnFlags", on & ~mask)
        inp:set_field("ButtonTriggerFlags", (inp:get_field("ButtonTriggerFlags") or 0) & ~mask)
    end
    -- self-check: player 1 holding a mouse button or Space while the Arisen sees no buttons at all means the
    -- pad zeroing also ate the keyboard -> switch it off
    -- v0.9.46: this check switched the zeroing off for good on 2026-11-15 while the tester dragged sliders in the
    -- REFramework window (mouse held, the game sees no buttons), and player 2's L2 then aimed the Arisen's bow. Now it
    -- only runs in the first 20 s of a co-op session, never while the REFramework UI is open, and only switches the
    -- zeroing off for that session (the setting itself is not touched).
    if not two and cfg.coop_zero_pad_for_arisen and not coop.zero_off and os.clock() - (coop.t_start or 0) < 20.0 then
        local ui_open = false
        pcall(function() ui_open = reframework:is_drawing_ui() == true end)
        local p1_btn = not ui_open and (is_key_down_safe(0x01) or is_key_down_safe(0x02) or is_key_down_safe(0x20))
        if p1_btn and on == 0 then coop.kb_dead = coop.kb_dead + 1 else coop.kb_dead = 0 end
        if coop.kb_dead > 45 then
            coop.zero_off = true
            coop_event("pad zeroing also blocked player 1's keys -> off for this session")
            log_msg("Co-op: processButton pad zeroing blocked keyboard/mouse too; off for this co-op session")
        end
    end
    -- stick (v0.9.2): only acts on frames where player 2's left stick is pushed, since otherwise the game's own
    -- input is untouched. v0.9.0 copied KeyboardMouseAxisL every frame, but that field is zero on most frames, so
    -- the Arisen crawled at ~0.5 m/s. Now player 1's direction comes straight from WASD (zero -> stand still).
    -- 0.9.172-dev36: players 3+'s left sticks reach the Arisen through the game's merged controller too
    local other_l = pad_stick_x * pad_stick_x + pad_stick_y * pad_stick_y > 0.04
    local kbw = R.kb_wait and R.kb_wait()
    if kbw and not other_l then -- dev44: any controller's left stick, while waiting for player 2 with player 1 on keyboard
        for _, d in ipairs(R.tp_devs()) do
            local v = R.tp_read(d)
            if v.lx * v.lx + v.ly * v.ly > 0.04 then other_l = true break end
        end
    end
    if (two or kbw) and not other_l then
        for _, sl in pairs(R.np and R.np.slots or {}) do
            local q = sl.pad_cam -- dev41: sl.pad is consumed by R.s2_tick before this runs
            if q and (q.lx or 0) ^ 2 + (q.ly or 0) ^ 2 > 0.04 then other_l = true break end
        end
    end
    if (two or kbw) and other_l then
        -- v0.9.170 (dev): two controllers. Player 2's stick is pushed; give the Arisen player 1's stick (plus WASD).
        local p1 = R.tp_p1()
        local kx, ky = p1.lx or 0.0, p1.ly or 0.0
        if R.key_held("MoveForward", 0x57) then ky = ky + 1.0 end
        if R.key_held("MoveBackward", 0x53) then ky = ky - 1.0 end
        if R.key_held("MoveRightward", 0x44) then kx = kx + 1.0 end
        if R.key_held("MoveLeftward", 0x41) then kx = kx - 1.0 end
        local km = math.sqrt(kx * kx + ky * ky)
        if km < (cfg.coop_pad_deadzone or 0.15) then kx, ky, km = 0.0, 0.0, 0.0 end
        if km > 1.0 then kx, ky, km = kx / km, ky / km, 1.0 end
        local ok = pcall(function()
            inp:call("setAxisL(System.Single, System.Single)", kx + 0.0, ky + 0.0)
            inp:call("set_AxisMagnitudeL(System.Single)", km + 0.0)
        end)
        if ok then R.tp.stick_fixes = (R.tp.stick_fixes or 0) + 1 end
    elseif cfg.coop_block_p2_stick and pad_stick_x * pad_stick_x + pad_stick_y * pad_stick_y > 0.04 then
        local kx, ky = 0.0, 0.0
        -- v0.9.124: the keys the game has the four directions on (default W / S / D / A)
        if R.key_held("MoveForward", 0x57) then ky = ky + 1.0 end
        if R.key_held("MoveBackward", 0x53) then ky = ky - 1.0 end
        if R.key_held("MoveRightward", 0x44) then kx = kx + 1.0 end
        if R.key_held("MoveLeftward", 0x41) then kx = kx - 1.0 end
        local km = math.sqrt(kx * kx + ky * ky)
        if km > 0 then kx, ky, km = kx / km, ky / km, 1.0 end
        local ok = pcall(function()
            inp:call("setAxisL(System.Single, System.Single)", kx + 0.0, ky + 0.0)
            inp:call("set_AxisMagnitudeL(System.Single)", km + 0.0)
        end)
        if ok then coop.stick_fixes = (coop.stick_fixes or 0) + 1
        else cfg.coop_block_p2_stick = false; coop_event("stick block write failed -> off") end
    end
end

-- v0.9.152 two faults, found when the camera did not keep player 2's Archer in frame:
-- (1) pawn_idx was the pawn co-op STARTED with. Switching player 2 to another pawn (the select key in co-op) changed
--     the name in this file but not the index, so Camera Distance went on framing the first pawn. The index is now
--     the pawn being played.
-- (2) the file was written with R.dump, which only writes in developer mode. A released copy never wrote it, so
--     Camera Distance never learned that co-op was on. It is now always written, but outside developer mode only
--     when co-op starts, stops or changes pawn (three short fields).
local function coop_write_status()
    local idx = (coop.active and state.active and state.pawn_idx) or coop.pawn_idx
    local name = state.active and state.pawn_name or ""
    -- v0.9.171: both players on pawns: Camera Distance frames player 1's pawn (the camera follows it, anchor_idx)
    -- and player 2's (pawn_idx); -1 = the Arisen is the anchor, as before
    local on, anchor = coop.active, -1
    if R.cp and R.cp.on and R.cp.mode == "pawns" and R.s2 and R.s2.active and state.active then
        on, idx, name, anchor = true, R.s2.idx, tostring(R.s2.name or ""), state.pawn_idx
    end
    -- 0.9.171: player 2 on the Arisen: the camera's pawn is player 1's, the other player is the Arisen (pawn_idx -1)
    if R.cp and R.cp.on and R.cp.ar2 and state.active then
        on, idx, name, anchor = true, -1, "the Arisen", state.pawn_idx
    end
    -- 0.9.172: players 3+ (pawn indices) for Camera Distance's framing
    local extra, extra_names, extra_n = {}, {}, {}
    if R.np_charas then for _, e in ipairs(R.np_charas()) do extra[#extra + 1] = e.idx; extra_names[#extra_names + 1] = tostring(e.name or ""); extra_n[#extra_n + 1] = e.player end end
    if #extra > 0 and R.cp and R.cp.on then on = true end
    -- 0.9.173-dev1: each player's colour (0xAABBGGRR) for Camera Distance's off-screen markers
    local colors, ckey = {}, {}
    for n = 1, 6 do colors["p" .. n] = R.player_abgr(n); ckey[n] = R.player_color(n) end
    if R.dev then
        R.dump("DPC_coop.json", {
            active = on, pawn_idx = idx, pawn_name = name, anchor_idx = anchor, players = extra, player_names = extra_names, player_nums = extra_n,
            colors = colors,
            np = R.np and { n = R.np_count(), log = R.np.log, err = R.np.err } or nil,
            cp = R.cp and { on = R.cp.on, mode = R.cp.mode, kb = R.cp.kb, p1 = R.cp.char[1], p2 = R.cp.char[2], arisen_side = R.cp.arisen_side, applies = R.cp.applies, log = R.cp.log } or nil,
            s2 = R.s2 and { active = R.s2.active, idx = R.s2.idx, frames = R.s2.frames, errors = R.s2.errors, err = R.s2.err, in_err = R.s2.in_err, on = R.s2.last_on, mag = R.s2.last_mag, tgt_sets = R.s2.tgt_sets } or nil,
            target = coop.tgt_name, target_dist = coop.tgt_dist, target_sets = coop.tgt_sets or 0,
            chords = coop.chords or 0, glyph_skips = coop.glyph_skips or 0,
            t = os.clock(), version = VERSION,
        })
        return
    end
    local key = tostring(on) .. ":" .. tostring(idx) .. ":" .. tostring(anchor) .. ":" .. table.concat(extra, ",") .. ":" .. table.concat(ckey, ",")
    if key == coop.status_key then return end
    coop.status_key = key
    pcall(json.dump_file, "DPC_coop.json", { active = on, pawn_idx = idx, pawn_name = name, anchor_idx = anchor, players = extra, player_names = extra_names, player_nums = extra_n, colors = colors, version = VERSION })
end

local function coop_apply_overrides()
    if coop.saved then return end
    coop.saved = {}
    for k, v in pairs(COOP_OVERRIDES) do coop.saved[k] = cfg[k]; cfg[k] = v end
    coop_saved_for_cfg = coop.saved
end

local function coop_restore_overrides()
    if not coop.saved then return end
    for k, v in pairs(coop.saved) do cfg[k] = v end
    coop.saved = nil
    coop_saved_for_cfg = nil
end

-- called from release_possession (unless it is a pawn switch inside co-op)
coop.on_release = function(reason)
    pcall(function() local d = R.rb_dev(); if d and R.rb.power > 0 then R.rb_set(d, 0.0) end; R.rb.power = 0 end)
    local c = R.cr
    if cfg.coop_auto_resume and not R.CR_USER[tostring(reason)] then
        c.want, c.name, c.idx, c.reason = true, state.pawn_name, state.pawn_idx or coop.pawn_idx, tostring(reason)
        c.p1, c.p2 = R.tp and R.tp.p1, R.tp and R.tp.p2
        c.ok_since, c.tries, c.next, c.noted = nil, 0, os.clock() + 1.0, false
        c.down = tostring(reason):find("downed", 1, true) and state.pawn_chara or nil
    else
        c.want, c.down = false, nil
        -- dev47 (coop-start-1 step 6): ended by a player, so the controller roles end too. They lived on after
        -- co-op (R.tp_tick only runs during co-op), and the next Ctrl + F6 took the old pair at once instead of
        -- waiting for L3 + R3. The auto-resume above keeps its own copy (c.p1 / c.p2).
        if R.tp_reset then
            R.tp_reset()
            R.tp.keep, R.tp.restored, R.tp.snap = nil, true, nil
            pcall(json.dump_file, "DPC_two_pads.json", {})
        end
    end
    -- dev50 (the tester: player 1 solo on a controller, a friend's L3 + R3 "is triggering as Player 1 is M and KB"): the
    -- Ctrl + F6 start flag was only cleared in R.tp_tick, which doesn't run once co-op is off, so after one
    -- keyboard start every later L3 + R3 join gave player 1 the keyboard. It ends with the session now.
    if R.tp then R.tp.start_kb, R.tp.start_t = nil, nil end
    coop.active = false
    coop_restore_overrides()
    coop_event("co-op ended (" .. tostring(reason) .. ")")
    if R.cp and R.cp.on and not R.cp.busy then pcall(R.cp_end, reason) end -- v0.9.171 (not while rearranging players)
    coop_write_status()
end

-- v0.9.13: the HUD switches its button prompts to the pad the moment player 2 touches the controller
-- (app.UserInputManager.switchingGamePadKeyboardMouse sets HIDInputMode: GamePad 0 / KeyboardMouse 1).
-- In co-op player 1 owns the HUD, so skip that switch and keep it on keyboard/mouse.
local glyph_hooked = false
local function coop_install_glyph_hook()
    if glyph_hooked then return end
    glyph_hooked = true
    local td = sdk.find_type_definition("app.UserInputManager")
    local m = td and td:get_method("switchingGamePadKeyboardMouse")
    if not m then coop_event("glyph hook: method not found"); return end
    local ok, err = pcall(sdk.hook, m, function(args)
        if not ((coop.active or (R.cp and R.cp.on and R.cp.kb)) and cfg.coop_kbm_glyphs) or cfg.coop_two_pads then return end -- v0.9.171: both on pawns with one controller too
        local okm = pcall(function()
            local mgr = sdk.to_managed_object(args[2])
            if mgr and mgr:call("get_HIDInputMode") ~= 1 then mgr:call("set_HIDInputMode", 1) end
        end)
        if not okm then return end
        coop.glyph_skips = (coop.glyph_skips or 0) + 1
        return sdk.PreHookResult.SKIP_ORIGINAL
    end, nil)
    if not ok then dev_error("glyph hook", err) end
end

local function coop_force_kbm_glyphs()
    if not cfg.coop_kbm_glyphs or cfg.coop_two_pads then return end -- v0.9.170: with two controllers player 1 uses a pad
    pcall(function()
        local mgr = sdk.get_managed_singleton("app.UserInputManager")
        if mgr and mgr:call("get_HIDInputMode") ~= 1 then
            mgr:call("set_HIDInputMode", 1)
            coop_event("HUD prompts switched back to keyboard/mouse")
        end
    end)
end

local function coop_start(idx)
    if state.active then release_possession("starting co-op") end
    ensure_enums()
    coop_apply_overrides()
    coop.active, coop.pawn_idx = true, idx or cfg.selected_pawn_idx or 0
    coop.map, coop.prev_on, coop.kb_dead, coop.axis_dead, coop.err = nil, 0, 0, 0, nil
    coop.zero_off, coop.t_start = false, os.clock()
    R.ta.pin, R.ta.req, R.ta.r3_t = nil, nil, nil
    coop.ar_input_addr = 0
    if cfg.coop_start_bring then -- dev7 (the tester): start player 2 right next to player 1's character
        pcall(function()
            local ar = quick_arisen()
            local apos = ar and ar:call("get_Transform"):call("get_Position")
            if not apos then return end
            for _, e in ipairs(get_party()) do
                if e.idx == coop.pawn_idx and e.chara then
                    local p = e.chara:call("get_Transform"):call("get_Position")
                    local dx, dz = p.x - apos.x, p.z - apos.z
                    if dx * dx + dz * dz > 36 then
                        local fwd = ar:call("get_Transform"):call("get_AxisZ") -- (the Arisen's right side: across his facing)
                        local rx, rz = 1.8, 0.0
                        if fwd then
                            local l = math.sqrt(fwd.x * fwd.x + fwd.z * fwd.z)
                            if l > 0.01 then rx, rz = fwd.z / l * 1.8, -fwd.x / l * 1.8 end
                        end
                        e.chara:call("warp(via.vec3, app.CharacterWarpOption)", Vector3f.new(apos.x + rx, apos.y + 0.3, apos.z + rz), nil)
                        log_msg(string.format("Co-op: brought %s over (%.0f m away)", tostring(e.name), math.sqrt(dx * dx + dz * dz)))
                    end
                    break
                end
            end
        end)
    end
    local ok = start_possession(coop.pawn_idx)
    if ok == false or not state.active then
        coop.active = false
        coop_restore_overrides()
        log_msg("Co-op: could not take the pawn")
        coop_write_status()
        return false
    end
    coop.ar_input_addr = addr_of(state.arisen_input)
    coop.chord_latch, coop.face_t = nil, nil
    coop_install_glyph_hook()
    coop_force_kbm_glyphs()
    coop_ensure_map()
    coop_event("co-op ON: player 2 -> " .. tostring(state.pawn_name) .. " (native " .. tostring(native.pip ~= nil and not native.failed) .. ")")
    log_msg("CO-OP: player 2 (controller) plays " .. tostring(state.pawn_name) .. "; player 1 keeps the Arisen")
    R.note = { text = "Co-op: player 2 plays " .. tostring(state.pawn_name), t_end = os.clock() + 4.0 }
    coop_write_status()
    if R.api_fire then pcall(R.api_fire, "coop_start", { players = { [1] = "Arisen", [2] = state.pawn_name } }) end -- v0.9.170
    if R.cp_begin then pcall(R.cp_begin) end -- v0.9.171 co-op players model
    return true
end

local function coop_stop()
    -- dev38: player 2's character glows as they leave (players 3+ glow in R.np_leave)
    for n, g in pairs(R.pglow) do if g.kept then pcall(R.cine_glow, g.chara, g.name, false) end; R.pglow[n] = nil end -- dev40
    if R.s2 and R.s2.active then R.leave_glow(R.s2.chara) elseif coop.active and state.active then R.leave_glow(state.pawn_chara) end
    if R.cp and R.cp.on and R.cp.mode == "pawns" then R.cp_end("co-op off"); return end -- v0.9.171
    if coop.active then release_possession("co-op off") end
end

local function coop_toggle()
    if coop.active or (R.cp and R.cp.on) then coop_stop() else coop_start(cfg.selected_pawn_idx) end
end

R.cr_ok = function(ch)
    if not ch then return false end
    local ok, good = pcall(function()
        if ch:call("get_IsDead") == true then return false end
        if ch:call("get_IsCutSceneMode") == true then return false end
        if ch:call("get_IsDown") == true and (ch:call("get_Hp") or 1) <= 0 then return false end
        return (ch:call("get_Hp") or 1) > 0
    end)
    return ok and good == true
end
R.rb = { until_t = 0, power = 0, last_hp = nil, beat_t = 0, shape = nil, err = nil }
R.rb_dev = function()
    if not (R.tp_on and R.tp_on()) then return nil end
    for _, d in ipairs(R.tp_devs()) do
        if d:get_address() == R.tp.p2 then return d end
    end
    return nil
end
R.rb_set = function(d, power)
    local r = R.rb
    local p = math.max(0.0, math.min(1.0, power)) + 0.0
    local function try(shape)
        if shape == "two" then
            d:call("setMotorPower", 0, p)
            d:call("setMotorPower", 1, p)
        else
            d:call("setMotorPower", p)
        end
    end
    if r.shape then
        local ok = pcall(try, r.shape)
        if not ok then r.shape = nil end
        return ok
    end
    for _, shape in ipairs({ "two", "one" }) do
        local ok, err = pcall(try, shape)
        if ok then r.shape = shape; r.err = nil; return true end
        r.err = tostring(err)
    end
    return false
end
R.rb_pulse = function(power, dur)
    local r = R.rb
    local now = os.clock()
    power = power * (cfg.coop_p2_rumble_power or 1.0)
    if now < r.until_t and power <= r.power then return end
    r.power, r.until_t = power, now + dur
    local d = R.rb_dev()
    if d then R.rb_set(d, power) end
end
R.rb_tick = function()
    local r = R.rb
    local now = os.clock()
    if r.power > 0 and now >= r.until_t then
        r.power = 0
        local d = R.rb_dev()
        if d then R.rb_set(d, 0.0) end
    end
    if not (cfg.coop_p2_rumble and coop.active and state.pawn_chara and R.tp_on and R.tp_on()) then
        r.last_hp = nil
        return
    end
    local hp, mx = nil, nil
    pcall(function()
        local hit = state.pawn_chara:call("get_Hit")
        mx = hit and hit:call("get_OriginalMaxHp") or nil
        hp = hit and hit:call("get_Hp") or nil
    end)
    if not (hp and mx and mx > 0) then return end
    local ratio = hp / mx
    if r.last_hp and hp < r.last_hp - 0.5 then
        local bite = (r.last_hp - hp) / mx
        if hp <= 0 then
            R.rb_pulse(1.0, 0.7)
        else
            R.rb_pulse(math.min(1.0, 0.35 + bite * 4.0), math.min(0.45, 0.12 + bite * 1.5))
        end
    end
    if cfg.coop_rb_status and r.last_hp and hp > r.last_hp + mx * 0.08 then
        R.rb_pulse(r.last_hp <= 0 and 0.5 or 0.2, r.last_hp <= 0 and 0.35 or 0.15)
    end
    r.last_hp = hp
    if ratio > 0 and ratio < 0.25 and now >= r.beat_t then
        r.beat_t = now + 1.1
        R.rb_pulse(0.25, 0.08)
        r.beat2 = now + 0.18
    elseif r.beat2 and now >= r.beat2 then
        r.beat2 = nil
        R.rb_pulse(0.18, 0.06)
    end
    if cfg.coop_rb_status then
        local st = nil
        pcall(function()
            local sm = state.pawn_chara:call("get_StaminaManager")
            local smx = sm and sm:call("get_MaxValue") or 0
            if smx > 0 then st = (sm:call("get_RemainingAmount") or 0) / smx end
        end)
        if st then
            if st <= 0.01 and (r.last_st or 1) > 0.01 then R.rb_pulse(0.35, 0.12); r.beat2 = now + 0.2 end
            r.last_st = st
        end
    end
    if (cfg.coop_rb_skill or cfg.coop_rb_status) and R.node_names then
        local okn, n0, n1 = pcall(R.node_names, state.pawn_chara)
        if okn then
            local nodes = tostring(n0) .. "|" .. tostring(n1)
            if nodes ~= r.last_nodes then
                local prev = r.last_nodes or ""
                r.last_nodes = nodes
                local function has(str, w) return str:find(w, 1, true) ~= nil end
                local skill = has(nodes, "Skill") and not has(nodes, "Cancel")
                local knocked = (has(nodes, "Blown") or has(nodes, "Down") or has(nodes, "Knock")) and not has(nodes, "Cancel")
                local was_skill = has(prev, "Skill") and not has(prev, "Cancel")
                local was_knocked = has(prev, "Blown") or has(prev, "Down") or has(prev, "Knock")
                if cfg.coop_rb_skill and skill and not was_skill then R.rb_pulse(0.22, 0.07) end
                if cfg.coop_rb_status and knocked and not was_knocked then R.rb_pulse(0.6, 0.3) end
                r.nodes_seen = nodes
            end
        end
    end
end

R.rb_hook = function()
    local td = sdk.find_type_definition("app.HitController")
    local m = td and td:get_method("updateDamage")
    if not m then return end
    sdk.hook(m, function(args)
        local st = thread.get_hook_storage()
        st.dpc_rb_di, st.dpc_rb_hc = nil, nil
        if cfg.coop_p2_rumble and coop.active and state.pawn_chara and R.tp_on and R.tp_on() then
            st.dpc_rb_di, st.dpc_rb_hc = args[3], args[2]
        end
    end, function(retval)
        local st = thread.get_hook_storage()
        local p, hcp = st.dpc_rb_di, st.dpc_rb_hc
        st.dpc_rb_di, st.dpc_rb_hc = nil, nil
        if p then
            pcall(function()
                local di = sdk.to_managed_object(p)
                local dmg = di and di.Damage
                if not dmg then return end
                local pgo = state.pawn_chara:call("get_GameObject")
                if not pgo then return end
                local pa = pgo:get_address()
                local owner = di["<AttackOwnerObject>k__BackingField"]
                local hc = hcp and sdk.to_managed_object(hcp)
                local tgo = hc and hc:call("get_GameObject")
                if cfg.coop_rb_dealt and owner and owner:get_address() == pa and tgo and tgo:get_address() ~= pa and dmg > 0 then
                    local mx = hc:call("get_OriginalMaxHp") or 0
                    local hpn = hc:call("get_Hp") or 1
                    if hpn <= 0 then
                        R.rb_pulse(0.85, 0.25)
                    else
                        local frac = mx > 0 and dmg / mx or 0.02
                        R.rb_pulse(math.min(0.75, 0.28 + frac * 6.0), math.min(0.18, 0.06 + frac * 2.0))
                    end
                elseif cfg.coop_rb_status and tgo and tgo:get_address() == pa and dmg <= 0 and owner and owner:get_address() ~= pa then
                    R.rb_pulse(0.4, 0.1)
                end
            end)
        end
        return retval
    end)
end
pcall(R.rb_hook)

R.cr_tick = function()
    local c = R.cr
    if not c.want then return end
    if coop.active or not cfg.coop_auto_resume then c.want, c.down = false, nil; return end
    local now = os.clock()
    if now < (c.next or 0) then return end
    c.next = now + 0.25
    if R.world ~= true then c.ok_since = nil; return end
    local ar = nil
    pcall(function() ar = sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer") end)
    local entry = nil
    for _, e in ipairs(get_party()) do
        if c.name and c.name ~= "" and e.name == c.name then entry = e; break end
    end
    if not entry then
        for _, e in ipairs(get_party()) do if e.idx == c.idx then entry = e; break end end
    end
    if entry and c.down == nil then
        local okd, downed = pcall(function() return entry.chara:call("get_IsDown") == true and (entry.chara:call("get_Hp") or 1) <= 0 end)
        if okd and downed then c.down = entry.chara end
    end
    if not (entry and R.cr_ok(ar) and R.cr_ok(entry.chara)) then
        c.ok_since = nil
        if not c.noted then
            c.noted = true
            R.note = { text = "Co-op resumes when " .. tostring(c.name or "the pawn") .. " is back", t_end = now + 3.0 }
        end
        return
    end
    c.down = nil
    c.ok_since = c.ok_since or now
    if now - c.ok_since < 2.0 then return end
    c.ok_since = nil
    local ok, started = pcall(coop_start, entry.idx)
    if ok and started ~= false and coop.active then
        c.want = false
        local p1, p2 = c.p1, c.p2
        if p1 and p2 and R.tp then
            local have1, have2 = false, false
            for _, d in ipairs(R.tp_devs()) do
                local a = d:get_address()
                if a == p1 then have1 = true elseif a == p2 then have2 = true end
            end
            if p1 == R.KB_ADDR then have1 = true end
            if have1 and have2 then R.tp.p1, R.tp.p2, R.tp.wait_release, R.tp.p1v = p1, p2, nil, nil end
        end
        R.note = { text = "Co-op resumed: player 2 plays " .. tostring(state.pawn_name), t_end = now + 3.0 }
        coop_event("co-op resumed (" .. tostring(c.reason) .. ")")
    else
        c.tries = (c.tries or 0) + 1
        c.next = now + 5.0
        if c.tries >= 5 then
            c.want = false
            R.note = { text = "Co-op could not resume - start it again (Ctrl+F6)", t_end = now + 5.0 }
        end
    end
end

local function toggle_possession()
    if state.active then
        release_possession("hotkey toggle")
    else
        start_possession(cfg.selected_pawn_idx)
    end
end

local function switch_control_mode(new_mode)
    if state.active then
        local idx = state.pawn_idx
        release_possession("mode change")
        cfg.control_mode = new_mode
        save_cfg()
        start_possession(idx)
    else
        cfg.control_mode = new_mode
        save_cfg()
    end
end

-- ----------------------------------------------------------------------------
-- Keyboard & Gamepad Polling (Hotkeys + Safe Stick & Button Input)
-- ----------------------------------------------------------------------------
local prev_keys = {}
is_key_down_safe = function(vk) -- forward-declared near the top (co-op filter uses it)
    if not vk or vk == 0 then return false end
    local ok, down = pcall(reframework.is_key_down, reframework, vk)
    return ok and down == true or false
end

-- Edge detection uses one snapshot per frame for every key we have ever queried (poll_keys runs at
-- the top of UpdateBehavior). Previously prev_keys only updated when key_pressed() was reached, so
-- early returns left stale edges that fired a frame or more later.
local key_now = {}
local function poll_keys()
    for vk, down in pairs(key_now) do
        prev_keys[vk] = down
        key_now[vk] = is_key_down_safe(vk)
    end
end

local function key_pressed(vk)
    if not vk or vk == 0 then return false end
    if R.cap or os.clock() < (R.cap_quiet or 0) then return false end -- v0.9.149: a key is being chosen in the settings window
    if key_now[vk] == nil then
        -- First query: start tracking; never report an edge on the first frame
        local d = is_key_down_safe(vk)
        key_now[vk] = d
        prev_keys[vk] = d
        return false
    end
    return key_now[vk] and not prev_keys[vk]
end

-- v0.9.23: the number row is the game's own (pawn orders: Go, Wait, ...) again while possessing. The numpad
-- keeps the skills. number_row_skills = true brings the old behaviour back.
function R.row_down(vk) return cfg.number_row_skills and is_key_down_safe(vk) or false end
function R.row_pressed(vk) return cfg.number_row_skills and key_pressed(vk) or false end

local function is_ui_open()
    local ok, drawing = pcall(reframework.is_drawing_ui, reframework)
    return ok and drawing == true or false
end

local gp_single, gp_td = nil, nil

-- v0.9.170 (dev, untested): two controllers in couch co-op. Built on joseau11's 0.9.165 changes (R.tp_*; credit
-- in the MODLOG): via.hid.GamePad.get_ConnectingDevices lists each controller on its own (he saw two devices next to
-- the merged one). Player 2 claims a controller by holding L1 + L3 for half a second once co-op is on; the other one
-- is player 1's. Player 2's pawn then reads only that controller (poll_pad); the Arisen gets player 1's buttons
-- (R.tp_arisen_buttons, in the processButton hook) and player 1's sticks (coop.filter).
R.tp = { n = 0, hold = {} }
R.tp_devs = function()
    gp_single = gp_single or sdk.get_native_singleton("via.hid.GamePad")
    gp_td = gp_td or sdk.find_type_definition("via.hid.GamePad")
    local out = {}
    if not (gp_single and gp_td) then return out end
    local ok, arr = pcall(sdk.call_native_func, gp_single, gp_td, "get_ConnectingDevices")
    if not ok or not arr then return out end
    local n = 0
    pcall(function() n = arr:call("get_Count") or 0 end)
    if n == 0 then pcall(function() n = arr:call("get_Length") or 0 end) end
    for i = 0, n - 1 do
        local okd, d = pcall(arr.call, arr, "get_Item", i)
        if okd and d then out[#out + 1] = d end
    end
    return out
end
-- 0.9.172-dev36: player 1 on keyboard and mouse (cfg.coop_p1_kb). Player 1's "controller" is this stand-in, with a
-- fake address (R.KB_ADDR) that reads as nothing pressed, so every real controller is free for players 2, 3, ...
R.KB_ADDR = 1
R.kb_dev = { get_address = function() return 1 end }
-- dev46 (agreed with the tester [time]): the keyboard and mouse are always player 1's, plus whichever controller the Arisen
-- was being played on, if any. No setting: R.tp.p1 == R.KB_ADDR means player 1 has no controller this session.
R.tp_kb = function() return R.tp.p1 == R.KB_ADDR or (R.tp.start_kb == true and not R.tp.p1) end
-- player 1's devices, from what drove the Arisen before someone started holding L3 + R3: the keyboard counts while the
-- game is in keyboard / mouse mode (UserInputManager.HIDInputMode 1), a controller when it was used (R.tp.act).
-- Input while the REFramework menu is open does not count.
R.p1_track = function(now)
    local t = R.tp
    local ui = false
    pcall(function() ui = reframework:is_drawing_ui() == true end)
    if ui then return end
    pcall(function()
        local mgr = sdk.get_managed_singleton("app.UserInputManager")
        if mgr and mgr:call("get_HIDInputMode") == 1 then t.kb_t = now end
    end)
end
-- a snapshot when a controller starts holding L3 + R3 (its own presses flip the game to controller mode)
R.p1_snap = function(now)
    local t = R.tp
    if t.snap and now - t.snap.t < 5.0 then return end
    local act = {}
    for a, v in pairs(t.act or {}) do act[a] = v end
    t.snap = { t = now, kb_t = t.kb_t or -1e9, act = act }
    pcall(function() -- dev50: the Arisen's controller and the input mode at that moment
        t.snap.hid = sdk.get_managed_singleton("app.UserInputManager"):call("get_HIDInputMode")
        t.snap.active = sdk.get_managed_singleton("app.UserPadManager"):call("get_ActiveUserPad"):call("getDevice"):get_address()
    end)
end
-- the device player 1 keeps when `joiner` becomes player 2: the most recently used of the keyboard and the other
-- controllers, as of the snapshot. Returns a device (a controller, or R.kb_dev).
-- dev52: who player 2 gets on joining: a character player 1 picked with the selection arrow in the last 10 s (not
-- the one he plays), else the Arisen when player 1 is playing a pawn, else nil (the selected pawn, as before)
R.join_target = function()
    local lp = R.last_pick
    if lp and lp.chara and os.clock() - (lp.t or 0) < 10.0 then
        local addr = lp.chara:get_address()
        if state.arisen_chara and addr == state.arisen_chara:get_address() then
            if state.active then return "arisen" end
        else
            for _, e in ipairs(get_party()) do
                if e.chara:get_address() == addr and not (state.active and state.pawn_idx == e.idx) then return e.idx end
            end
        end
    end
    if state.active then return "arisen" end
    return nil
end
R.p1_pick = function(devs, joiner)
    local t = R.tp
    if t.start_kb then return R.kb_dev end -- co-op started from the keyboard (Ctrl + F6)
    local sn = t.snap or { kb_t = t.kb_t or -1e9, act = t.act or {} }
    local best, bt = nil, sn.kb_t or -1e9
    for _, d in ipairs(devs) do
        local a = d:get_address()
        if a ~= joiner and not (R.np_claimed and R.np_claimed(a)) then
            local at = sn.act[a]
            if at and at > bt then best, bt = d, at end
        end
    end
    t.snap = nil
    return best or R.kb_dev
end
-- dev44 (the tester: "ctrl+f6 when out of co-op starts co-op and changes the camera but everyone is just controlling the
-- Arisen. It's in some half-done state"): co-op is on but no controller has claimed player 2 yet. With player 1 on
-- keyboard and mouse no controller is his, so none drives the Arisen while co-op waits for player 2's L3 + R3.
R.kb_wait = function() return R.tp.start_kb == true and coop.active and not (R.tp_on and R.tp_on()) end
R.tp_read = function(d)
    local v = { b = 0, lx = 0.0, ly = 0.0, rx = 0.0, ry = 0.0 }
    if not d or d == R.kb_dev then return v end
    pcall(function()
        v.b = d:call("get_Button") or 0
        local pad = d -- a via.hid.GamePadDevice (read only; never handed to a setter)
        local okl, l = pcall(pad.call, pad, "get_AxisL")
        if okl and l then v.lx, v.ly = l.x + 0.0, l.y + 0.0 end
        local okr, r = pcall(pad.call, pad, "get_AxisR")
        if okr and r then v.rx, v.ry = r.x + 0.0, r.y + 0.0 end
    end)
    return v
end
R.tp_on = function()
    local t = R.tp
    return coop.active and cfg.coop_two_pads and t.p1 ~= nil and t.p2 ~= nil and not t.wait_release
end
R.tp_p1 = function() return R.tp.p1v or { b = 0, lx = 0.0, ly = 0.0, rx = 0.0, ry = 0.0 } end
R.tp_p2 = function() return R.tp.p2v or { b = 0, lx = 0.0, ly = 0.0, rx = 0.0, ry = 0.0 } end
R.tp_reset = function()
    local t = R.tp
    t.p1, t.p2, t.hold, t.wait_release, t.p1v, t.p2v = nil, nil, {}, nil, nil, nil
end
R.tp_swap = function()
    local t = R.tp
    if t.p1 and t.p2 then
        t.p1, t.p2, t.p1v, t.p2v = t.p2, t.p1, t.p2v, t.p1v
        pcall(json.dump_file, "DPC_two_pads.json", { p1 = t.p1, p2 = t.p2 })
    end
end
-- once a frame from poll_pad. Returns player 2's values, false while waiting for player 2 to claim a controller,
-- nil when not in two-controller mode (poll_pad then reads the merged device as before).
R.tp_tick = function()
    local t = R.tp
    if not ((coop.active or (R.cp_pawns and R.cp_pawns())) and cfg.coop_two_pads) then
        if t.p2 then R.tp_reset() end
        t.keep = nil
        t.start_kb = nil -- dev46: the keyboard start belongs to that co-op session
        return nil
    end
    local devs = R.tp_devs()
    t.n = #devs
    if #devs < 1 then -- dev46: one controller is enough (player 1 can be on the keyboard)
        if t.p2 then
            R.note = { text = "Co-op: a controller was disconnected", t_end = os.clock() + 4.0 }
            -- 0.9.171: remembered, so the pair comes back by itself when the controller does (below)
            t.keep = { p1 = t.p1, p2 = t.p2, t = os.clock() }
            coop_event("two controllers: a controller went away")
        end
        R.tp_reset()
        if (t.warn_t or 0) + 8.0 < os.clock() then
            t.warn_t = os.clock()
            R.note = { text = "Co-op, two controllers: only " .. #devs .. " controller(s) found", t_end = os.clock() + 4.0 }
        end
        return nil
    end
    local p2d, p1d
    for _, d in ipairs(devs) do
        local a = d:get_address()
        if a == t.p2 then p2d = d elseif a == t.p1 then p1d = d end
    end
    if t.p1 == R.KB_ADDR then p1d = R.kb_dev end
    if t.p2 and not (p2d and p1d) then
        -- 0.9.171: a controller that sleeps / reconnects comes back under a new address (seen 2026-11-20: the
        -- pair was lost mid-test). Remember the pair; the one still here keeps its role (below).
        t.keep = { p1 = t.p1, p2 = t.p2, t = os.clock() }
        coop_event("two controllers: a controller changed")
        R.tp_reset()
        p2d, p1d = nil, nil
    end
    local now = os.clock()
    -- 0.9.171: after a controller went away: the one still here keeps its role, the other role goes to the first
    -- other controller that is used (a button, or a stick pushed past half). No need to hold L3 + R3 again.
    if not t.p2 and t.keep and now - (t.keep.t or 0) < 600 then
        local k1, k2
        for _, d in ipairs(devs) do
            local a = d:get_address()
            if a == t.keep.p1 then k1 = d elseif a == t.keep.p2 then k2 = d end
        end
        if t.keep.p1 == R.KB_ADDR then k1 = R.kb_dev end
        if k1 and k2 then
            t.p1, t.p2, p1d, p2d = t.keep.p1, t.keep.p2, k1, k2
            t.keep, t.wait_release = nil, true
            coop_event("two controllers: both back")
        elseif k1 or k2 then
            local kept = k1 or k2
            local ka = kept:get_address()
            local other
            for _, d in ipairs(devs) do
                local a = d:get_address()
                if a ~= ka and not (R.np_claimed and R.np_claimed(a)) then
                    local okr, v = pcall(R.tp_read, d)
                    if okr and v and R.tp_used(v) then other = d break end
                end
            end
            if other then
                if k1 then t.p1, t.p2, p1d, p2d = ka, other:get_address(), kept, other
                else t.p1, t.p2, p1d, p2d = other:get_address(), ka, other, kept end
                t.keep, t.wait_release = nil, true
                pcall(json.dump_file, "DPC_two_pads.json", { p1 = t.p1, p2 = t.p2 })
                R.note = { text = "Co-op: the controller is back", t_end = now + 3.0 }
                coop_event(string.format("two controllers: back, %X / %X", t.p1 & 0xFFFFFF, t.p2 & 0xFFFFFF))
            elseif not t.keep_hint or now - t.keep_hint > 5.0 then
                t.keep_hint = now
                R.note = { text = "Co-op: a controller reconnected - press a button on it", t_end = now + 4.0 }
            end
        end
    end
    if not t.p2 and not t.restored then
        -- dev8: the claim survives Reset Scripts (the controllers keep their addresses while the game runs)
        t.restored = true
        local okf, f = pcall(json.load_file, "DPC_two_pads.json")
        if okf and type(f) == "table" and f.p1 and f.p2 then
            local h1, h2
            for _, d in ipairs(devs) do
                local a = d:get_address()
                if a == f.p1 then h1 = d elseif a == f.p2 then h2 = d end
            end
            if h1 and h2 then
                t.p1, t.p2, p1d, p2d = f.p1, f.p2, h1, h2
                R.note = { text = "Co-op: player 2's controller is still set", t_end = now + 3.0 }
                coop_event("two controllers: claim kept from before")
            end
        end
    end
    -- dev46 (the tester: "ctrl+F6 should be the one that starts co-op as M+KB and then if there is one controller it is
    -- assigned to P2"): started from the keyboard with exactly one controller connected, it is player 2's at once,
    -- unless it was used in the 5 s before Ctrl + F6 (then it may be the one player 1 is holding: L3 + R3 decides)
    if not t.p2 and t.start_kb and #devs == 1 and now - (t.start_t or 0) > 0.3 then
        local d = devs[1]
        local a = d:get_address()
        if not ((t.act or {})[a] and (t.act[a] > (t.start_t or 0) - 5.0) and t.act[a] <= (t.start_t or 0)) then
            t.p2, p2d, p1d, t.p1 = a, d, R.kb_dev, R.KB_ADDR
            t.wait_release, t.keep = true, nil
            R.note = { text = "Co-op: player 1 on keyboard and mouse, player 2 on the controller (Ctrl + F6 ends)", t_end = now + 4.0 }
            coop_event(string.format("two controllers: one controller -> player 2 (%X), player 1 on keyboard", a & 0xFFFFFF))
        end
    end
    if not t.p2 then
        local pv = coop_pad_values()
        -- dev9: L3 + R3 (was L1 + L3, which is also DPC's take-control combination)
        local combo = (pv.LStickPush or 0x1000) | (pv.RStickPush or 0x2000)
        for _, d in ipairs(devs) do
            local a = d:get_address()
            local b = R.tp_read(d).b
            if (b & combo) == combo then
                if not t.hold[a] then R.p1_snap(now) end
                t.hold[a] = t.hold[a] or now
                if now - t.hold[a] >= (cfg.coop_join_hold_s or 0.6) then -- dev50: was 1.0 s (the tester: shorter to claim; leaving stays 3 s)
                    t.p2, p2d = a, d
                    p1d = R.p1_pick(devs, a)
                    t.p1 = p1d and p1d:get_address() or nil
                    t.wait_release, t.keep = true, nil
                    -- 0.9.171: R.tp.p1 is the Arisen side's controller: with player 2 on the Arisen, the
                    -- controller held (player 2's) is that one
                    if R.cp and R.cp.on and R.cp.mode == "classic" and R.cp.arisen_side == 2 and t.p1 and t.p1 ~= R.KB_ADDR then
                        t.p1, t.p2, p1d, p2d = t.p2, t.p1, p2d, p1d
                    end
                    pcall(json.dump_file, "DPC_two_pads.json", { p1 = t.p1, p2 = t.p2 })
                    R.note = { text = "Co-op: player 2's controller is set" .. (t.p1 == R.KB_ADDR and " (player 1 on keyboard and mouse; Ctrl + F6 ends)" or " (player 1 keeps theirs; hold L3 + R3 for 3 s to end)"), t_end = now + 4.0 }
                    coop_event(string.format("two controllers: player 2 = %X, player 1 = %X (%d found)", a, t.p1 or 0, #devs))
                    break
                end
            else
                t.hold[a] = nil
            end
        end
        if not t.p2 then
            if not t.hint_t or now - t.hint_t > 6.0 then
                t.hint_t = now
                R.note = { text = "Co-op, two controllers: player 2, hold L3 + R3 (both stick clicks) on your controller", t_end = now + 5.0 }
            end
            return false
        end
    end
    t.p1_prevb = t.p1v and t.p1v.b or 0 -- dev12: for player 1's co-op combination (pad_combo_pressed reads player 2)
    t.p1v, t.p2v = R.tp_read(p1d), R.tp_read(p2d)
    if t.wait_release then
        if t.p2v.b ~= 0 then return false end
        t.wait_release = nil
    end
    return t.p2v
end
-- The Arisen's pad buttons (processButton's value) while two controllers are on. Which of the three is right depends
-- on what the game hands processButton (the merged pad, or one controller), which is not known yet:
--   1 (default) take out only the buttons player 2 holds and player 1 does not. Right in both cases.
--   2 leave them to the game (joseau11: "the game already reads only one pad for the Arisen").
--   3 player 1's controller only (opened the main menu again and again for joseau11; here to compare).
R.tp_arisen_buttons = function(arg)
    local v = sdk.to_int64(arg) or 0
    local mode = cfg.coop_two_pads_buttons or 1
    local p1, p2 = R.tp_p1().b or 0, R.tp_p2().b or 0
    R.tp.game_b, R.tp.pb_in = v, v & 0xFFFFFFFF
    R.tp.pb = (R.tp.pb or 0) + 1
    -- 0.9.172-dev36: players 3+ press buttons too; theirs come out the same way as player 2's
    local others = p2
    for _, sl in pairs(R.np and R.np.slots or {}) do if sl.pad_cam then others = others | (sl.pad_cam.b or 0) end end -- dev41
    local out = v
    if R.tp_kb() then out = 0 -- player 1 on keyboard and mouse: no controller is his
    elseif mode == 3 then out = p1
    elseif mode == 1 then out = v & ~(others & ~p1) end
    if out ~= v and mode == 1 then R.tp.masked = (R.tp.masked or 0) + 1 end
    -- joseau11: player 1's R3 is only the game's camera reset; with the aiming on it picks his target instead
    if cfg.coop_aim and cfg.coop_aim_p1 then
        local r3 = (coop_pad_values().RStickPush) or 0x2000
        out = out & ~r3
    end
    if out == v then return nil end
    return out
end

-- dev9: the second controller starts co-op itself. Every frame (cheap: two or three device reads) each controller's
-- last activity is noted. With co-op off, a controller held at L3 + R3 for 1.5 s starts co-op as player 2 when another
-- controller was used in the last 2 minutes (so one player on one controller never starts it by accident; the
-- game also lists controllers nobody touches). Player 1 is the controller used most recently besides it. In co-op,
-- player 2 holding L3 + R3 for 3 s ends it.
R.tp_other = function(devs, not_a)
    local t, best, bt = R.tp, nil, -1
    for _, o in ipairs(devs) do
        local a = o:get_address()
        if a ~= not_a then
            local la = (t.act and t.act[a]) or 0
            if la > bt then best, bt = o, la end
        end
    end
    return best
end
-- dev10: seen on Thirteen after controllers were swapped / turned off: the controllers' input reached the game
-- (via.hid devices showed it) but the game stayed in keyboard/mouse mode (UserInputManager.HIDInputMode 1) and the
-- Arisen got no buttons and no stick; the keyboard still worked. When a controller has been in use for 0.3 s with no
-- co-op running, the input mode is still keyboard/mouse and the Arisen's input shows nothing, set the game's mode to
-- controller (0), what the game does itself when a controller is touched. At most every 3 s; counted.
R.pad_mode_tick = function(any_pad, now)
    local t = R.tp
    if not cfg.pad_mode_fix or coop.active or state.active then t.pm_since = nil; return end
    if not any_pad then t.pm_since = nil; return end
    t.pm_since = t.pm_since or now
    if now - t.pm_since < 0.3 or now < (t.pm_next or 0) then return end
    local mgr = sdk.get_managed_singleton("app.UserInputManager")
    if not mgr or mgr:call("get_HIDInputMode") ~= 1 then return end
    local cm = sdk.get_managed_singleton("app.CharacterManager")
    local ar = cm and cm:call("get_ManualPlayer")
    local inp = ar and ar:call("get_Input")
    if not inp then return end
    if (inp:get_field("ButtonOnFlags") or 0) ~= 0 or (inp:call("get_AxisMagnitudeL") or 0) > 0.05 then return end
    t.pm_next = now + 3.0
    mgr:call("set_HIDInputMode", 0)
    t.pm_fixes = (t.pm_fixes or 0) + 1
    log_msg("Controller in use but the game was in keyboard/mouse mode: switched it to controller (" .. t.pm_fixes .. ")")
end
-- dev13: the game feeds the Arisen from ONE controller, app.UserPadManager's active pad (mixed-pads-1: with a PS5
-- and an Xbox pad the Arisen took only the PS5's stick, even while the Xbox was the "last input device"). It does
-- not move to another controller that is used, so a controller that went off or a second one left the Arisen deaf
-- to the pad in hand. pad_active_follow: when the active controller has been idle 1.5 s and another one is used,
-- make that one active (the game's own changeActiveUserPad). Two-controller co-op: keep it on player 1's controller.
R.pad_active_tick = function(devs, now, force)
    -- v0.9.171: in co-op with two controllers the active controller decides who drives the Arisen's input (and,
    -- with both players on pawns, player 1's pawn): kept right even with the follow switch off
    local coop2 = cfg.coop_two_pads and (coop.active or (R.cp_pawns and R.cp_pawns()))
    if not (cfg.pad_active_follow or force or coop2) then return end
    local t = R.tp
    t.act = t.act or {}
    if not force and (t.pa_next or 0) > now then return end
    t.pa_next = now + 0.25
    local m = sdk.get_managed_singleton("app.UserPadManager")
    if not m then return end
    local aa = nil
    pcall(function()
        local ap = m:call("get_ActiveUserPad")
        local ad = ap and ap:call("getDevice")
        aa = ad and ad:get_address() or nil
    end)
    t.pa_active = aa
    local want = nil
    if (coop.active or (R.cp_pawns and R.cp_pawns())) and cfg.coop_two_pads and t.p1 and t.p2 and not t.wait_release then
        want = t.p1 -- classic co-op: the Arisen side's controller; both on pawns: player 1's (his pawn reads the Arisen's input)
    else
        local best, bt = nil, -1
        for _, d in ipairs(devs) do
            local a = d:get_address()
            local at = t.act[a]
            if at and at > bt then best, bt = a, at end
        end
        local idle = (not aa) or (not t.act[aa]) or (now - t.act[aa] > 1.5)
        if best and best ~= aa and (force or (now - bt < 0.5 and idle)) then want = best end
    end
    if not want or want == aa then return end
    for _, d in ipairs(devs) do
        if d:get_address() == want then
            local ok = pcall(m.call, m, "changeActiveUserPad", d)
            t.pa_n = (t.pa_n or 0) + 1
            log_msg(string.format("Controllers: the game's active controller %X -> %X (%s)", (aa or 0) & 0xFFFFFF, want & 0xFFFFFF, ok and "ok" or "failed"))
            return
        end
    end
end
R.pad_reset = function() -- settings button: forget both controllers' roles and let the game take whatever is pressed
    R.tp_reset()
    R.tp.restored = true
    pcall(json.dump_file, "DPC_two_pads.json", {})
    R.tp.pm_next = 0
    pcall(function()
        local mgr = sdk.get_managed_singleton("app.UserInputManager")
        if mgr then mgr:call("set_HIDInputMode", 0) end
    end)
    pcall(R.pad_active_tick, R.tp_devs(), os.clock(), true) -- dev13: the most recently used controller drives the Arisen
    R.note = { text = "Controllers reset", t_end = os.clock() + 3.0 }
end
-- dev13b: "in use" = a button, or a stick pushed past half way. A resting stick that drifts (a paired PS5 nobody
-- held read -0.25) must not count, or it takes the active controller away from the one in your hands.
R.tp_used = function(v)
    return v.b ~= 0 or math.max(math.abs(v.lx), math.abs(v.ly), math.abs(v.rx), math.abs(v.ry)) > 0.5
end
R.tp_join_tick = function()
    local t = R.tp
    t.act = t.act or {}
    local now = os.clock()
    local devs = R.tp_devs()
    local any_pad = false
    for _, d in ipairs(devs) do
        local v = R.tp_read(d)
        if v.b ~= 0 or math.abs(v.lx) + math.abs(v.ly) > 0.3 then any_pad = true end
        if R.tp_used(v) then t.act[d:get_address()] = now end
    end
    if not (coop.active or (R.cp and R.cp.on)) then pcall(R.p1_track, now) end -- dev46
    pcall(R.pad_mode_tick, any_pad, now)
    local okpa, epa = pcall(R.pad_active_tick, devs, now)
    if not okpa then t.pa_err = tostring(epa) end
    if #devs < 1 then return end -- dev46: one controller is enough (player 1 on the keyboard)
    local pv = coop_pad_values()
    local combo = (pv.LStickPush or 0x1000) | (pv.RStickPush or 0x2000)
    t.jhold = t.jhold or {}
    for _, d in ipairs(devs) do
        local a = d:get_address()
        local v = R.tp_read(d)
        if R.tp_used(v) then t.act[a] = now end
        if coop.active or (R.cp and R.cp.on) then -- v0.9.171: the both-pawns arrangement is co-op too
            -- 0.9.172: a third (fourth, ...) controller holding L3 + R3 joins as the next player
            if cfg.coop_any and R.cp and R.cp.on and R.np and t.p1 and t.p2 and a ~= t.p1 and a ~= t.p2
               and not R.np_claimed(a) and not t.keep then
                if (v.b & combo) == combo then
                    t.jhold[a] = t.jhold[a] or now
                    if now - t.jhold[a] >= (cfg.coop_join_hold_s or 0.6) then -- dev50: was 1.5 s
                        t.jhold[a] = nil
                        pcall(R.np_join, d)
                    end
                else
                    t.jhold[a] = nil
                end
            elseif (a == t.p2 or a == t.p1) and (v.b & combo) == combo and not t.wait_release then
                -- dev49: not the same hold that just claimed the controller (the tester: they kept holding, "then it
                -- turns red and undoes it"); counting starts after the buttons were let go once
                t.jhold[a] = t.jhold[a] or now
                if now - t.jhold[a] >= 3.0 then
                    t.jhold[a] = nil
                    local who = (a == t.p1) and "player 1" or "player 2"
                    R.note = { text = (a == t.p1) and "Co-op ended by player 1" or "Co-op: player 2 left", t_end = now + 3.0 }
                    coop_event("two controllers: " .. who .. " held L3 + R3 -> co-op off")
                    pcall(coop_stop)
                    return
                end
            else
                t.jhold[a] = nil
            end
        elseif cfg.coop_pad_join and (v.b & combo) == combo then
            if not t.jhold[a] then R.p1_snap(now) end -- dev46: what player 1 was using before this hold
            t.jhold[a] = t.jhold[a] or now
            -- dev50: a short hold joins; but the controller the Arisen was just being played on needs the old 1.5 s,
            -- so a solo player's own L3 + R3 (sprint + camera) doesn't start co-op by accident
            local own = t.snap and t.snap.active == a and t.snap.hid == 0 -- the game's own controller for the Arisen
            if now - t.jhold[a] >= (own and 1.5 or (cfg.coop_join_hold_s or 0.6)) then -- dev50: was 1.5 s
                t.jhold[a] = nil
                -- dev46: player 1 keeps what the Arisen was being played on (keyboard and mouse, or a controller)
                local other = R.p1_pick(devs, a)
                local oa = other and other:get_address()
                if not oa then
                    if (t.join_warn_t or 0) + 5.0 < now then
                        t.join_warn_t = now
                        R.note = { text = "Co-op: player 1, press something on your controller first, then player 2 hold L3 + R3 again", t_end = now + 4.0 }
                    end
                else
                    cfg.coop_two_pads = true
                    save_cfg()
                    -- dev52 (the tester: "Co-op should probably jump in to whatever character is next ... if the solo player
                    -- had selected a character (yellow arrow) recently, then the co-op player should jump into them"):
                    -- player 2 takes a character player 1 picked with the selection arrow in the last 10 s; else, if
                    -- player 1 is playing a pawn, the Arisen; else the selected pawn as before.
                    local tg = R.join_target()
                    if state.active and tg ~= nil and cfg.coop_any then
                        local X = state.pawn_idx
                        R.tp_reset()
                        t.p1, t.p2, t.restored, t.wait_release = oa, a, true, true
                        pcall(json.dump_file, "DPC_two_pads.json", { p1 = oa, p2 = a })
                        R.cp.on = false
                        local okb = pcall(R.cp_begin)
                        local oka, applied = pcall(R.cp_apply, { [1] = X, [2] = tg }, "player 2 joined")
                        if not (okb and oka and applied) then
                            pcall(R.cp_end, "could not set up")
                            R.tp_reset()
                            R.note = { text = "Co-op: could not give player 2 " .. tostring(tg), t_end = now + 4.0 }
                        else
                            coop_event(string.format("two controllers: player 2 joined with L3 + R3 (%X) on %s, player 1 keeps %s", a, tostring(tg), tostring(X)))
                        end
                        return
                    end
                    local ok, started = pcall(coop_start, type(tg) == "number" and tg or cfg.selected_pawn_idx)
                    if ok and started ~= false and coop.active then
                        R.tp_reset()
                        t.p1, t.p2, t.restored, t.wait_release = oa, a, true, true
                        pcall(json.dump_file, "DPC_two_pads.json", { p1 = oa, p2 = a })
                        R.note = { text = "Co-op: player 2 joined on their controller" .. (oa == R.KB_ADDR and " (player 1 on keyboard and mouse; Ctrl + F6 ends)" or " (player 1 keeps theirs)"), t_end = now + 4.0 }
                        coop_event(string.format("two controllers: player 2 joined with L3 + R3 (%X), player 1 = %X", a, oa))
                    end
                    return
                end
            end
        else
            t.jhold[a] = nil
        end
    end
end

-- dev14: the robot (developer, capture shots / tests) is player 2 in one-controller co-op: then the real controller
-- is player 1's, like a second controller. DPC ignores it for player 2 and leaves it to the Arisen (no pad zeroing,
-- no stick / camera filter), so the Arisen can be played on the controller instead of keyboard and mouse.
R.robot_p2 = function()
    return cfg.robot_frees_pad ~= false and coop.active and robot.pad ~= nil and os.clock() < (robot.pad.until_t or 0)
        and not (R.tp_on and R.tp_on())
end
local function poll_pad()
    pad_prev = pad_buttons
    pad_buttons = 0
    pad_stick_x, pad_stick_y = 0.0, 0.0
    pad_stick_rx, pad_stick_ry = 0.0, 0.0
    gp_single = gp_single or sdk.get_native_singleton("via.hid.GamePad")
    gp_td = gp_td or sdk.find_type_definition("via.hid.GamePad")
    if not gp_single or not gp_td then return end
    -- v0.9.1: the merged device is the property get_MergedDevice(); "getMergedDevice(0)" returned nil, so DPC never
    -- read the controller at all (pad sticks were always 0 -> no pad movement while the Arisen brain was on).
    local tpv = nil
    if cfg.coop_pad_join or cfg.pad_mode_fix or cfg.pad_active_follow or (cfg.coop_two_pads and (coop.active or (R.cp_pawns and R.cp_pawns()))) then
        local okj, ej = pcall(R.tp_join_tick)
        if not okj then R.tp.err = "join: " .. tostring(ej) end
    end
    if cfg.coop_two_pads and (coop.active or (R.cp_pawns and R.cp_pawns())) then
        local okt, v = pcall(R.tp_tick)
        if okt then tpv = v else R.tp.err = tostring(v) end
    end
    if tpv ~= nil then -- v0.9.170 (dev): two controllers; player 2 reads only their own (nothing while claiming)
        pad_device_ok = true
        if tpv then
            pad_buttons = tpv.b or 0
            pad_stick_x, pad_stick_y, pad_stick_rx, pad_stick_ry = tpv.lx, tpv.ly, tpv.rx, tpv.ry
        end
    end
    local ok, pad = false, nil
    if tpv == nil then ok, pad = pcall(sdk.call_native_func, gp_single, gp_td, "get_MergedDevice") end
    if tpv == nil then pad_device_ok = (ok and pad ~= nil) and true or false end
    if ok and pad then
        local b = call(pad, "get_Button")
        if type(b) == "number" then pad_buttons = b end
        local ok_ax, ax_vec = pcall(pad.call, pad, "get_AxisL")
        if ok_ax and ax_vec then
            local ok_x, vx = pcall(function() return ax_vec.x end)
            local ok_y, vy = pcall(function() return ax_vec.y end)
            if ok_x and type(vx) == "number" then pad_stick_x = vx end
            if ok_y and type(vy) == "number" then pad_stick_y = vy end
        end
        local ok_r, r = pcall(pad.call, pad, "get_AxisR")
        if ok_r and r then
            pcall(function() pad_stick_rx, pad_stick_ry = r.x + 0.0, r.y + 0.0 end)
        end
    end
    if R.cp_pad_route then pcall(R.cp_pad_route) end -- v0.9.171: both players on pawns: each controller to its own pawn
    local rp = robot.pad
    if rp and R.cp_pawns and R.cp_pawns() and os.clock() < rp.until_t then
        pcall(R.s2_robot, rp) -- v0.9.171 (developer): the robot is player 2 on the second pawn
        rp = nil
    end
    if rp then
        if os.clock() >= rp.until_t then
            robot.pad = nil
        else
            if R.robot_p2() then -- dev14: the real controller is player 1's
                pad_buttons, pad_stick_x, pad_stick_y, pad_stick_rx, pad_stick_ry = 0, 0.0, 0.0, 0.0, 0.0
            end
            pad_buttons = pad_buttons | (rp.btn or 0)
            if rp.lx then pad_stick_x, pad_stick_y = rp.lx, rp.ly end
            if rp.rx then pad_stick_rx, pad_stick_ry = rp.rx, rp.ry end
            -- v0.9.164 (developer): {"cmd":"robot","who":"pad","secs":25,"fight":true}. A fixed stick direction sent
            -- player 2's pawn running off in co-op shots (reported). In fight mode the robot looks for the nearest
            -- enemy to the played pawn, steers at it (camera-relative, like a real stick) and, within 3 m, taps the
            -- light attack with a heavy one every sixth beat.
            -- v0.9.165 (developer): {"cmd":"robot","who":"pad","secs":20,"antics":true}. Requested for the co-op
            -- shots: a second player who fights looks just like a pawn on its own AI, so the robot can also do what
            -- only a person would: run rings round the Arisen (3 m out) and jump every 0.9 s.
            if rp.antics and state.active and state.pawn_chara and state.arisen_chara then
                pcall(function()
                    local now = os.clock()
                    local px, _, pz = brain_pos(state.pawn_chara)
                    local ax, _, az = brain_pos(state.arisen_chara)
                    if not (px and ax) then return end
                    local rx, rz = px - ax, pz - az
                    local d = math.sqrt(rx * rx + rz * rz)
                    if d < 0.05 then rx, rz, d = 1.0, 0.0, 1.0 end
                    rx, rz = rx / d, rz / d
                    local pull = math.max(-1.0, math.min(1.0, (3.0 - d) * 0.8)) -- out when too close, in when too far
                    local dx, dz = -rz + rx * pull, rx + rz * pull
                    pad_stick_x, pad_stick_y = brain_stick_for(math.atan(dx, dz))
                    local m = R.bind_mask("Jump")
                    if m and ((now * 1000) % 900) < 160 then pad_buttons = pad_buttons | m end
                end)
            end
            if rp.fight and state.active and state.pawn_chara then
                pcall(function()
                    local now = os.clock()
                    if now >= (rp.next_t or 0) then
                        rp.next_t = now + 0.4
                        local okp, t = pcall(quick_pick_enemy, state.pawn_chara)
                        rp.tgt = okp and t or nil
                    end
                    local px, _, pz = brain_pos(state.pawn_chara)
                    local tx, tz
                    if rp.tgt then tx, _, tz = brain_pos(rp.tgt) end
                    if not (px and tx) then pad_stick_x, pad_stick_y = 0.0, 0.0; return end
                    local dx, dz = tx - px, tz - pz
                    local d = math.sqrt(dx * dx + dz * dz)
                    local sx, sy = brain_stick_for(math.atan(dx, dz))
                    local k = (d > 2.2) and 1.0 or 0.3 -- close in, then only keep facing it
                    pad_stick_x, pad_stick_y = sx * k, sy * k
                    if d <= 3.0 then
                        local heavy = (math.floor(now / 0.6) % 6) == 5
                        local m = R.bind_mask(heavy and "AttackL" or "AttackS")
                        if m and ((now * 1000) % 600) < 180 then pad_buttons = pad_buttons | m end
                    end
                end)
            end
        end
    end
end

-- dev12: with two controllers DPC's own combinations come from player 2's controller; player 1's controller
-- counts only for starting / stopping co-op (each player cycles their own character).
R.p1_combo_pressed = function(mask)
    if not mask or mask == 0 or not R.tp_on() then return false end
    if R.cap or os.clock() < (R.cap_quiet or 0) then return false end
    local b = (R.tp.p1v and R.tp.p1v.b) or 0
    local pb = R.tp.p1_prevb or 0
    return (b & mask) == mask and (pb & mask) ~= mask
end
local function pad_combo_pressed(mask)
    if not mask or mask == 0 then return false end
    if R.cap or os.clock() < (R.cap_quiet or 0) then return false end
    local now_down = (pad_buttons & mask) == mask
    local was_down = (pad_prev & mask) == mask
    return now_down and not was_down
end
-- v0.9.151: every key of the mod can carry Ctrl (cfg.keys.<id>_ctrl, taken from whether Ctrl was held when the key
-- was chosen). A key without Ctrl does nothing while Ctrl is held, and the other way round.
R.key_hit = function(id)
    if cfg.hotkeys_on == false then return false end -- 0.9.173: master switch (a player keeps DPC controller-only)
    local vk = cfg.keys[id]
    if not vk or vk == 0 or not key_pressed(vk) then return false end
    return is_key_down_safe(0x11) == (cfg.keys[id .. "_ctrl"] == true)
end
R.key_label = function(id)
    local vk = cfg.keys[id]
    if not vk or vk == 0 then return "none" end
    return ((cfg.keys[id .. "_ctrl"] == true) and "Ctrl + " or "") .. R.vk_name(vk)
end

-- Read left-stick / WASD movement vector as pure Lua numbers (NEVER calls app.CharacterInput:get_AxisL()!)
local function read_safe_move_stick(live_input)
    local ax, ay = pad_stick_x, pad_stick_y
    local mag = math.sqrt(ax * ax + ay * ay)

    -- Keyboard WASD fallback (W=0x57, S=0x53, A=0x41, D=0x44)
    if mag < 0.08 then
        local kx, ky = 0.0, 0.0
        if R.key_held("MoveForward", 0x57) then ky = ky + 1.0 end   -- v0.9.124: the game's own direction keys
        if R.key_held("MoveBackward", 0x53) then ky = ky - 1.0 end
        if R.key_held("MoveRightward", 0x44) then kx = kx + 1.0 end
        if R.key_held("MoveLeftward", 0x41) then kx = kx - 1.0 end
        if kx ~= 0.0 or ky ~= 0.0 then
            local kmag = math.sqrt(kx * kx + ky * ky)
            ax, ay, mag = kx / kmag, ky / kmag, 1.0
        end
    end

    -- Primitive float fallback from app.UserInput (get_AxisMagnitudeL & get_AngleRadL return System.Single!)
    -- (skipped while the v0.8 brain writes its own stick into this same CharacterInput)
    if mag < 0.08 and live_input and not (brain.on or brain.was_on_last) then
        local umag = call(live_input, "get_AxisMagnitudeL")
        local uang = call(live_input, "get_AngleRadL")
        if type(umag) == "number" and umag > 0.08 and type(uang) == "number" then
            mag = umag
            ax = -math.sin(uang) * umag
            ay = math.cos(uang) * umag
        end
    end

    return ax, ay, mag
end

-- ----------------------------------------------------------------------------
-- Arisen Follow / Tether & Warp Helpers
-- ----------------------------------------------------------------------------
local function local_warp_arisen_near(pawn_pos)
    local offset_pos = Vector3f.new(pawn_pos.x + 1.5, pawn_pos.y + 0.5, pawn_pos.z + 1.5)
    pcall(state.arisen_chara.call, state.arisen_chara, "warp(via.vec3, app.CharacterWarpOption)", offset_pos, nil)
end

local function warp_arisen_to_pawn()
    if not (state.active and state.arisen_chara and state.pawn_chara) then return end
    local pawn_xf = call(state.pawn_chara, "get_Transform")
    local pawn_pos = pawn_xf and call(pawn_xf, "get_Position")
    if not pawn_pos then return end
    -- safeWarp takes a via.Position = UNIVERSAL (double) position. Passing get_Position() (float vec3)
    -- is silently reinterpreted and sends the Arisen to x~7e12 -> crash (v0.6.0 CTD).
    local pawn_upos = call(pawn_xf, "get_UniversalPosition")

    local pm = sdk.get_managed_singleton("app.PawnManager")
    local ok = false
    if pm and pawn_upos then
        ok = pcall(pm.call, pm, "safeWarp(app.Character, via.Position)", state.arisen_chara, pawn_upos)
    end
    if ok then
        log_msg("Warped Arisen to " .. state.pawn_name .. " (safeWarp)")
    else
        local_warp_arisen_near(pawn_pos)
        log_msg("Warped Arisen near " .. state.pawn_name .. " (local warp)")
    end
    state.warp_check = { t = os.clock() + 0.3, pawn_pos = Vector3f.new(pawn_pos.x, pawn_pos.y, pawn_pos.z) }
end

-- Runs 0.3 s after a warp: if the Arisen landed somewhere absurd, put it next to the pawn instead.
local function verify_last_warp()
    local wc = state.warp_check
    if not wc or os.clock() < wc.t then return end
    state.warp_check = nil
    local axf = call(state.arisen_chara, "get_Transform")
    local apos = axf and call(axf, "get_Position")
    local bad = (not apos)
    if apos then
        local dx, dy, dz = apos.x - wc.pawn_pos.x, apos.y - wc.pawn_pos.y, apos.z - wc.pawn_pos.z
        local d = math.sqrt(dx * dx + dy * dy + dz * dz)
        bad = (d ~= d) or d > 60.0 -- NaN or nowhere near the pawn
        if bad then log_msg(string.format("ERROR: warp check failed (Arisen %.0fm from target) - correcting", d)) end
    end
    if bad then local_warp_arisen_near(wc.pawn_pos) end
end

-- Wait / Come pawn-command inputs control the Arisen while possessing (names resolved once from the enum)
local CMD_FLAG_CACHE = nil
local function cmd_flags()
    if CMD_FLAG_CACHE then return CMD_FLAG_CACHE end
    if not next(ACTION_FLAGS) then return nil end
    local c = {}
    for name, flag in pairs(ACTION_FLAGS) do
        local n = string.lower(name)
        if n == "wait" or n == "pawnwait" or n == "order_wait" then c.wait = flag end
        if n == "come" or n == "pawncome" or n == "order_come" then c.come = flag end
        if n == "help" or n == "pawnhelp" or n == "order_help" then c.help = flag end
    end
    log_msg(string.format("Pawn command flags: wait=%s come=%s help=%s", tostring(c.wait), tostring(c.come), tostring(c.help)))
    CMD_FLAG_CACHE = c
    return c
end

local function update_arisen_stay()
    local c = cmd_flags()
    local trg = state.last_trg_flags or 0
    if not c then return end
    -- v0.9.98: while a D-pad direction the mod owns is held, keep the order's press back; a tap gets it on release
    if cfg.pad_hold_select and not coop.active then
        local mask = (c.wait or 0) | (c.come or 0) | (c.help or 0)
        if R.dpad_dir(pad_buttons or 0) or (R.dh and R.dh.fired) then
            R.dh_cmd = (R.dh_cmd or 0) | (trg & mask)
            trg = trg & ~mask
        end
        if R.cmd_replay then trg, R.cmd_replay = trg | R.cmd_replay, nil end
    end
    if trg == 0 then return end
    -- v0.9.64: the Help order asks a caster Arisen to come and heal the possessed pawn now
    if c.help and (trg & c.help) ~= 0 and brain.style == "caster" and cfg.arisen_brain_heal then
        brain.help_until = os.clock() + 20.0
        brain.hurt_next = 0
        brain_event("Help order -> heal the possessed pawn")
    end
    if c.wait and (trg & c.wait) ~= 0 and not state.arisen_stay then
        state.arisen_stay = true
        log_msg("Arisen: WAIT (stays here; Come to resume following)")
        local sel = call(state.arisen_chara, "get_HumanActionSelector")
        if state.arisen_human then
            call(state.arisen_human, "set_IsDash(System.Boolean)", false)
            call(state.arisen_human, "set_IsPrevDash(System.Boolean)", false)
        end
        if sel and call(sel, "isEnableRequestIdle") then call(sel, "requestIdleImpl(System.Boolean)", false) end
        state.arisen_was_following = false
    elseif c.come and (trg & c.come) ~= 0 and state.arisen_stay then
        state.arisen_stay = false
        log_msg("Arisen: COME (following again)")
    end
end

local function update_arisen_tether()
    if not (state.active and state.arisen_chara and state.pawn_chara) then return end
    if coop.active then return end -- player 1 drives the Arisen
    verify_last_warp()
    update_arisen_stay()
    local axf = call(state.arisen_chara, "get_Transform")
    local pxf = call(state.pawn_chara, "get_Transform")
    local apos = axf and call(axf, "get_Position")
    local ppos = pxf and call(pxf, "get_Position")
    if not (apos and ppos) then return end

    local ok_dist, dist_xz, dy, dx, dz = pcall(function()
        local _dx = ppos.x - apos.x
        local _dy = ppos.y - apos.y
        local _dz = ppos.z - apos.z
        return math.sqrt(_dx * _dx + _dz * _dz), _dy, _dx, _dz
    end)
    if not ok_dist then return end

    -- Prevent party distance-leash from snapping the controlled pawn back to Arisen.
    -- v0.6.0: the condition must persist for arisen_warp_delay (so jumps, falls and monster climbs
    -- don't trigger it) and automatic warps are rate-limited. Previously this re-warped every frame
    -- until the warp settled - the prime suspect for the "far from Arisen" CTD.
    local now = os.clock()
    -- v0.9.28: while the Arisen was told to Wait he stays put; the auto-warp only fires past arisen_warp_dist_wait
    -- (beta-check-1: 60 m apart with the warp off, the game never pulled the possessed pawn back).
    local warp_d = cfg.arisen_warp_dist
    if state.arisen_stay and warp_d > 0 then warp_d = math.max(warp_d, cfg.arisen_warp_dist_wait or 120.0) end
    local too_far = warp_d > 0 and (dist_xz > warp_d or (math.abs(dy) > 25.0 and not state.arisen_stay))
    if too_far then
        state.far_since_t = state.far_since_t or now
        if (now - state.far_since_t) >= (cfg.arisen_warp_delay or 1.0) and now >= state.next_auto_warp_t then
            state.next_auto_warp_t = now + (cfg.arisen_warp_cooldown or 4.0)
            state.far_since_t = nil
            log_msg(string.format("Auto-warping Arisen (dist %.1fm, dy %.1fm)", dist_xz, dy))
            warp_arisen_to_pawn()
        end
        return
    end
    state.far_since_t = nil

    if brain.on then return end -- v0.8: the brain follows with the stick (pawn-style)
    if not cfg.arisen_auto_follow or state.arisen_stay then return end
    local arisen_sel = call(state.arisen_chara, "get_HumanActionSelector")
    if not arisen_sel then return end

    if dist_xz > cfg.arisen_follow_dist then
        local angle_rad = math.atan(dx, dz)
        local angle_deg = math.deg(angle_rad)
        call(state.arisen_chara, "set_TargetMoveAngleDeg(System.Single)", angle_deg)
        call(state.arisen_chara, "set_TargetFrontAngleDeg(System.Single)", angle_deg)
        local is_dash = (dist_xz > 14.0)
        local speed_type = is_dash and SPEED_DASH or SPEED_RUN
        -- 2nd arg is is_strafe (NOT is_dash): true would cap the Arisen at strafe speed (~3.5 m/s)
        if is_dash and state.arisen_human then
            call(state.arisen_human, "set_IsDash(System.Boolean)", true)
            call(state.arisen_human, "set_IsPrevDash(System.Boolean)", true)
            call(state.arisen_human, "notifyKeepDash")
        end
        safe_request_locomotion(arisen_sel, speed_type, false)
        state.arisen_was_following = true
    elseif state.arisen_was_following and dist_xz < (cfg.arisen_follow_dist - 1.5) then
        state.arisen_was_following = false
        if state.arisen_human then
            call(state.arisen_human, "set_IsDash(System.Boolean)", false)
            call(state.arisen_human, "set_IsPrevDash(System.Boolean)", false)
        end
        if call(arisen_sel, "isEnableRequestIdle") then
            call(arisen_sel, "requestIdleImpl(System.Boolean)", false)
        end
    end
end

-- ----------------------------------------------------------------------------
-- Pawn Action Helpers (PawnCommander Verified Signatures & Vocation Actions)
-- ----------------------------------------------------------------------------
local function compute_camera_move_angle_deg(axis_x, axis_y)
    -- 1. Primary: Static primitive method app.PlayerInputProcessorDetail.getCameraAngleRad() -> System.Single
    local cam_yaw = nil
    if get_cam_angle_rad_method then
        local ok, rad = pcall(get_cam_angle_rad_method.call, get_cam_angle_rad_method, nil)
        if ok and type(rad) == "number" then
            cam_yaw = rad
        end
    end

    -- 2. Fallback: Read <CameraFront>k__BackingField directly
    if not cam_yaw then
        local cm = sdk.get_managed_singleton("app.CharacterManager")
        local cf = cm and field(cm, "<CameraFront>k__BackingField")
        if cf then
            local ok_cf, yaw = pcall(function()
                if cf.x ~= 0 or cf.z ~= 0 then
                    return math.atan(cf.x, cf.z)
                end
                return 0.0
            end)
            if ok_cf and type(yaw) == "number" then
                cam_yaw = yaw
            end
        end
    end

    cam_yaw = cam_yaw or 0.0
    state.last_cam_deg = math.deg(cam_yaw)

    -- Stick: +y is forward (along cam_yaw), +x is right (cam_yaw - pi/2 in RH Y-up)
    local stick_angle = math.atan(-axis_x, axis_y)
    return math.deg(cam_yaw + stick_angle)
end

local function update_pawn_lockon_target()
    local loc = state.arisen_lockon_ctrl
    if not (loc and state.pawn_chara) then return end
    if coop.active then return end -- co-op: that is player 1's lock-on
    set_field(loc, "Chara", state.pawn_chara)
    -- v0.9.126: two calls removed here (updateTargetWhenUnlock, updateSpellTarget). No type in the game has
    -- them (type index, dd2.exe 4.1.0.0), so they never ran; pointing Chara at the pawn is what does the work.
end

local function pawn_do_draw(pawn_chara, sel)
    pawn_chara = pawn_chara or state.pawn_chara
    sel = sel or (pawn_chara and call(pawn_chara, "get_HumanActionSelector"))
    if not sel then return false end
    call(sel, "requestDrawWeapon()")
    state.suppress_loco_until = math.max(state.suppress_loco_until, os.clock() + 0.25)
    state.last_action_str = "Draw Weapon"
    return true
end

local function pawn_do_sheathe(pawn_chara, sel)
    pawn_chara = pawn_chara or state.pawn_chara
    sel = sel or (pawn_chara and call(pawn_chara, "get_HumanActionSelector"))
    if not sel then return false end
    state.pending_skill = nil
    state.pending_attack = nil
    state.active_cast = nil
    state.is_sprinting = false
    call(sel, "requestEndAction()")
    call(sel, "requestSheatheWeapon(System.Boolean)", false)
    state.suppress_loco_until = math.max(state.suppress_loco_until, os.clock() + 0.25)
    state.last_action_str = "Sheathe Weapon"
    return true
end

-- Dev diagnostics: ring buffer of input / action events, readable through the agent bridge as
-- _G.DPC.state.input_log. Cheap (string building only when an event happens).
local function node_names(chara)
    local am = chara and call(chara, "get_ActionManager")
    local fsm = am and field(am, "Fsm")
    if not fsm then return "?", "?" end
    return tostring(call(fsm, "getCurrentNodeName(System.UInt32)", 0) or ""), tostring(call(fsm, "getCurrentNodeName(System.UInt32)", 1) or "")
end
R.node_names = node_names

-- v0.9.29 bow aim for the possessed Archer. Measured 2026-11-15 (archer-aim-1 / -2): the game enters the aim camera
-- with MainCameraController.switchCamera(7, interp, nil, 0) and leaves with switchCamera(0, ...), but only for the
-- player character. A possessed Archer does go into Job02_StartAim, nothing asks for the camera, and when DPC asks,
-- the game switches back to type 0 on the next frame (about 50 calls a second). So while the pawn aims DPC requests
-- type 7 and skips the game's switch-back in a pre-hook (verified: aim camera held in every sample), and turns the
-- pawn to the camera yaw each frame (verified: body-to-camera angle 22 deg -> 0.5 deg). The block only applies
-- while aim_until is fresh, so a stopped script can never leave the Arisen's own aim camera stuck.
R.aim_sig = "switchCamera(app.CameraDefine.ControlType, app.CameraSwitchInterpParam, app.PostEffectSetting, app.CameraDefine.ToPlayerCameraOption)"
R.aim_on_aim = function(mcc)
    local cur = field(mcc, "_CurrentCameraController")
    local on = false
    if cur then pcall(function() on = cur:get_type_definition():get_name() == "AimCameraController" end) end
    return on
end
R.aim_mcc = function()
    local cm = sdk.get_managed_singleton("app.CameraManager")
    if not cm then return nil end
    return call(cm, "getMainCameraController", 0)
end
R.aim_interp = function(which) -- the game's own transition object once the Arisen has aimed, else a built-in preset
    local e = (which == "exit") and R.aim_exit or R.aim_enter
    if e then return e end
    if R.aim_preset == nil then
        R.aim_preset = false
        pcall(function()
            local v = sdk.find_type_definition("app.CameraSwitchInterpParam"):get_field("Smooth"):get_data(nil)
            if v then R.aim_preset = v:add_ref() end
        end)
    end
    return R.aim_preset or nil
end
R.aim_install = function()
    if R.aim_hooked then return end
    R.aim_hooked = true
    local td = sdk.find_type_definition("app.MainCameraController")
    local m = td and td:get_method(R.aim_sig)
    if not m then log_msg("Aim camera: switchCamera not found; feature off"); R.aim_off = true; return end
    local ok, err = pcall(sdk.hook, m, function(args)
        local okh, res = pcall(function()
            if R.aim_mine then return nil end
            local ct = sdk.to_int64(args[3]) & 0xFFFFFFFF
            -- v0.9.143 reported while playing the main pawn: the camera was being pulled away. Camera watch:
            -- "Combat (2) -> Climbing (6), player camera false", target object still the pawn; the Arisen (Mystic
            -- Spearhand, on his own) was on a Griffin. The climbing camera is the game's camera for the PLAYER
            -- character clinging to a monster, so it went to the Arisen. Not switched to while a pawn is played
            -- (normal possession; in co-op player 1 is the Arisen). A played pawn that climbs never got this
            -- camera anyway. The cinematic action camera (10) is refused here too, behind 0.9.139's block.
            if state.active and not coop.active and ((ct == 6 and cfg.possess_no_climb_cam) or (ct == 10 and cfg.possess_no_cinematic_cam)) then
                R.cam_refused = (R.cam_refused or 0) + 1
                R.cam_refused_last = ct
                return sdk.PreHookResult.SKIP_ORIGINAL
            end
            if R.aim_hold and ct ~= 7 and os.clock() < (R.aim_until or 0) then
                R.aim_blocked = (R.aim_blocked or 0) + 1
                return sdk.PreHookResult.SKIP_ORIGINAL
            end
            local io = sdk.to_managed_object(args[4]) -- learn the game's own transitions from the Arisen's aim
            if io then
                if ct == 7 then
                    if not R.aim_enter then R.aim_enter = io:add_ref() end
                    R.aim_seen7 = true
                elseif ct == 0 and R.aim_seen7 then
                    if not R.aim_exit then R.aim_exit = io:add_ref() end
                    R.aim_seen7 = false
                end
            end
            return nil
        end)
        if okh and res then return res end
    end, function(retval) return retval end)
    if not ok then log_msg("Aim camera: hook failed (" .. tostring(err) .. "); feature off"); R.aim_off = true end
end
R.aim_rsig = "requestDraw(via.Point, System.Single, System.Boolean)"
-- Reticle for the possessed Archer: app.ui020801 (GuiManager.Aim), driven every frame by requestDraw(point, scale,
-- flag). Measured (archer-aim-3 / -5): the point is in real screen pixels. The Arisen's reticle sits at the UI's
-- DrawPos 960,540 (centre of its 1920x1080 canvas); a request at 1920,540 on a 7680x2160 screen gave DrawPos 480,270
-- and one at 960,540 gave a reticle further left, i.e. DrawPos = point * (1920 / width, 1080 / height). So the centre
-- of the real screen is the right point on any aspect ratio.
-- v0.9.166: not on every PC. On a 5120x1440 screen with Windows display scaling at 150 %, REFramework reported the
-- display as 7680x2160, the request went to 3840,1080 and the reticle was drawn at DrawPos 1440,810: three quarters
-- of the way right and down, i.e. the game's own screen is the unscaled 5120x1440. So the point now corrects itself:
-- after each request the widget's DrawPos is read back, and the point is scaled until DrawPos is 960,540.
R.aim_reticle = function()
    if not cfg.pawn_aim_reticle or R.aim_ret_fail then return end
    local ok, err = pcall(function()
        local gm = sdk.get_managed_singleton("app.GuiManager")
        local ui = gm and gm:get_field("Aim")
        if not ui then return end
        local okd, ds = pcall(imgui.get_display_size)
        if okd and ds and ds.x and ds.x > 0 then R.aim_disp_x, R.aim_disp_y = ds.x, ds.y end
        if not R.aim_disp_x then return end
        local x = math.floor(R.aim_disp_x * 0.5 * (R.aim_fix_x or 1.0) + 0.5)
        local y = math.floor(R.aim_disp_y * 0.5 * (R.aim_fix_y or 1.0) + 0.5)
        if not R.aim_pt or R.aim_pt_x ~= x or R.aim_pt_y ~= y then
            local pt = ValueType.new(sdk.find_type_definition("via.Point"))
            pcall(function() pt:set_field("x", x); pt:set_field("y", y) end)
            local okr, rx = pcall(pt.get_field, pt, "x")
            if not (okr and rx == x) then pt:write_dword(0, x); pt:write_dword(4, y) end
            R.aim_pt, R.aim_pt_x, R.aim_pt_y = pt, x, y
        end
        R.aim_mine = true
        local okc, e2 = pcall(ui.call, ui, R.aim_rsig, R.aim_pt, 1.0, false)
        R.aim_mine = false
        if not okc then error(e2) end
        -- read back where the widget put it (UI canvas 1920x1080; centre 960,540) and correct the point
        local okp, dp = pcall(ui.get_field, ui, "DrawPos")
        if okp and dp and dp.x and dp.y and dp.x > 1 and dp.y > 1 then
            R.aim_dp_x, R.aim_dp_y = dp.x, dp.y
            if math.abs(dp.x - 960) > 2 or math.abs(dp.y - 540) > 2 then
                R.aim_fix_x = math.max(0.1, math.min(4.0, (R.aim_fix_x or 1.0) * 960 / dp.x))
                R.aim_fix_y = math.max(0.1, math.min(4.0, (R.aim_fix_y or 1.0) * 540 / dp.y))
                R.aim_fixes = (R.aim_fixes or 0) + 1
            end
        end
    end)
    if not ok then R.aim_mine = false; R.aim_ret_fail = true; dev_error("aim reticle", err) end
end
-- Where the arrow goes. Measured (archer-aim-6): while the Arisen aims, his Character.AimTargetPosition has a value
-- exactly on the camera's centre line (0.00 m off) at the distance of what he looks at (12.6 - 13.6 m facing a
-- wall); the possessed pawn's has none, so his arrows had the right heading but no elevation. DPC writes a point on
-- the centre line right after the pawn's input processor ran, at the distance R.aim_ray finds (0.9.35; a fixed
-- distance made near shots land left, because the pawn stands left of the camera line).
-- v0.9.35 distance to what the camera's centre line hits, the way the game picks the Arisen's aim point. A ray on
-- filter layer 0 returns everything near-sorted (probes ray1-5, 2026-11-15): sensors, markers, the party's own bodies,
-- then the world. Take the first hit that is world geometry (collidable layer 1 or 22: EnvRoot / GroundCol) or a
-- character that is not the Arisen or a pawn. No result pool growth with either castRay form (132/138/354 unchanged).
R.aim_ray = function(p, z)
    if R.aim_ray_off then return nil end
    local ok, d = pcall(function()
        if not R.aim_q then
            R.aim_q = sdk.create_instance("via.physics.CastRayQuery"):add_ref()
            R.aim_res = sdk.create_instance("via.physics.CastRayResult"):add_ref()
            R.aim_q:call("clearOptions"); R.aim_q:call("enableAllHits"); R.aim_q:call("enableNearSort")
            R.aim_phys_td = sdk.find_type_definition("via.physics.System")
            R.aim_scene_td = sdk.find_type_definition("via.SceneManager")
        end
        local q, res = R.aim_q, R.aim_res
        q:call("setRay(via.vec3, via.vec3)", Vector3f.new(p.x, p.y, p.z), Vector3f.new(p.x - z.x * 150.0, p.y - z.y * 150.0, p.z - z.z * 150.0))
        local scene = sdk.call_native_func(sdk.get_native_singleton("via.SceneManager"), R.aim_scene_td, "get_CurrentScene()")
        sdk.call_native_func(sdk.get_native_singleton("via.physics.System"), R.aim_phys_td,
            "castRay(via.Scene, via.physics.CastRayQuery, via.physics.CastRayResult)", scene, q, res)
        local n = res:call("get_NumContactPoints") or 0
        local found
        for i = 0, n - 1 do
            local c = res:call("getContactCollidable(System.UInt32)", i)
            local layer = c:call("get_FilterInfo"):call("get_Layer")
            local solid = (layer == 1 or layer == 22)
            if not solid then
                local go = c:call("get_GameObject")
                local tag = tostring(go:call("get_Tag") or "")
                if tag:find("Character", 1, true) then
                    local folder = go:call("get_Folder")
                    local fname = folder and tostring(folder:call("get_Name")) or ""
                    solid = fname ~= "Player" and fname ~= "Pawn"
                end
            end
            if solid then
                local pos = res:call("getContactPoint(System.UInt32)", i):get_field("Position")
                local dd = math.sqrt((pos.x - p.x) ^ 2 + (pos.y - p.y) ^ 2 + (pos.z - p.z) ^ 2)
                if dd > 1.0 then found = dd; break end
            end
        end
        res:call("clear")
        return found
    end)
    if not ok then
        R.aim_ray_errs = (R.aim_ray_errs or 0) + 1
        if R.aim_ray_errs >= 5 then R.aim_ray_off = true; dev_error("aim ray", d) end
        return nil
    end
    return d
end
R.aim_point = function()
    if not (R.aim_hold and state.pawn_chara) then return end
    -- v0.9.36: face the camera again AFTER his processor ran. With a move input the processor turned him to the
    -- move direction (he turned round when backing up); the Arisen keeps facing the target and backpedals.
    if get_cam_angle_rad_method then
        local okr, rad = pcall(get_cam_angle_rad_method.call, get_cam_angle_rad_method, nil)
        if okr and type(rad) == "number" then
            call(state.pawn_chara, "set_TargetFrontAngleDeg(System.Single)", math.deg(rad) + 0.0)
        end
    end
    if not cfg.pawn_aim_point then return end
    pcall(function()
        local tr = sdk.get_primary_camera():call("get_GameObject"):call("get_Transform")
        local p, z = tr:call("get_Position"), tr:call("get_WorldMatrix")[2]
        local d = (cfg.pawn_aim_ray and R.aim_ray(p, z)) or cfg.pawn_aim_point_dist or 30.0
        R.aim_last_d = d
        -- v0.9.33: the setter takes System.Nullable<via.vec3> (32 bytes: _HasValue at 0, _Value at 16). 0.9.30 passed
        -- a bare vector, which is what made the bow circle.
        if not R.aim_nv then R.aim_nv = ValueType.new(sdk.find_type_definition("System.Nullable`1<via.vec3>")) end
        local nv = R.aim_nv
        nv:write_byte(0, 1)
        nv:write_float(16, p.x - z.x * d); nv:write_float(20, p.y - z.y * d); nv:write_float(24, p.z - z.z * d)
        state.pawn_chara:call("set_AimTargetPosition", nv)
        R.aim_pts = (R.aim_pts or 0) + 1
    end)
end
R.aim_stop = function()
    if not R.aim_hold then return end
    R.aim_hold, R.aim_until, R.aim_t = false, 0, nil
    R.aim_pick_idx = nil
    local mcc = R.aim_mcc()
    if not (mcc and R.aim_on_aim(mcc)) then return end
    local ip = R.aim_interp("exit")
    if not ip then return end
    R.aim_mine = true
    pcall(mcc.call, mcc, R.aim_sig, 0, ip, nil, 0)
    R.aim_mine = false
end
-- v0.9.85 the aim camera needs an aim setting. app.AimCameraController takes its rotation speeds, zoom (FOV) and
-- gyro from an AimSetting that the game picks with AimCameraSetting.evaluate(player GameObject) when the PLAYER
-- starts to aim, and keeps afterwards. With an Archer Arisen who had aimed earlier in the session a setting was
-- already there, so the pawn's aim worked (2026-11-15). With a Thief Arisen it was nil: reticle, but no turning
-- and no zoom (the tester, 2026-11-16). So pick the setting for the pawn: evaluate(pawn GameObject) while he aims,
-- else the first enabled non-throwing setting with a zoom, and hand it to the controller with setupAim.
R.AIM_BY_NODE = { { "FullBend", 4 }, { "BodyBinder", 5 }, { "MeteorShot", 6 }, { "RandomShot", 8 }, { "FullBlast", 9 }, { "HeavyRain", 10 } }
R.aim_setup = function(mcc)
    local now = os.clock()
    if now < (R.aim_setup_next or 0) then return end
    R.aim_setup_next = now + 0.1
    local ok, err = pcall(function()
        local ac = mcc:get_field("<CameraControllers>k__BackingField"):call("get_Item", 7)
        if not ac then R.aim_set = "no controller"; return end
        local asset = ac:get_field("_AimCameraSetting")
        local arr = asset and asset:get_field("_AimSettings")
        if not arr then R.aim_set = "no settings"; return end
        -- v0.9.86: every setting's condition is a player condition (app.gc.pl.*), so evaluate() never answers
        -- for a pawn, and 0.9.85's "first with a zoom" picked the Meteor Shot sniper view (index 6: 15 deg/s,
        -- FOV 15). The list, read live: 11 = DrawBow (the normal bow aim: 100 / 90 deg/s, gyro), 4 FullBend,
        -- 5 BodyBinder, 6 MeteorShot, 8 RandomShot, 9 FullBlast, 10 HeavyRain. Pick by the pawn's own action.
        local _, up = node_names(state.pawn_chara)
        local idx = 11
        for _, m in ipairs(R.AIM_BY_NODE) do if up:find(m[1], 1, true) then idx = m[2]; break end end
        if idx >= arr:get_size() then idx = 11 end
        local s = arr:get_element(idx)
        -- sanity: the index must still be a bow setting on this game version
        local cn = ""
        pcall(function() cn = s:get_field("_Condition"):get_field("_Conditions"):get_element(0):get_type_definition():get_full_name() end)
        if idx == 11 and not cn:find("DrawBow", 1, true) then
            for i = 0, arr:get_size() - 1 do
                local okc, n2 = pcall(function() return arr:get_element(i):get_field("_Condition"):get_field("_Conditions"):get_element(0):get_type_definition():get_full_name() end)
                if okc and n2 == "app.gc.pl.DrawBow" then s, idx = arr:get_element(i), i; break end
            end
        end
        R.aim_pick, R.aim_set = s, "index " .. idx
        R.aim_asset_addr = asset:get_address()
        -- the controller asks AimCameraSetting.evaluate(player) for its setting; answer for the pawn while he aims
        -- v0.9.168 crash fix (AptPupil 2026-11-19, DD2.exe+0x52590e4 inside setupAim during switchCamera: the engine
        -- read the header of an already freed object, 0x700000000). The answer was a bare pointer with no reference
        -- of its own; the game keeps and later releases what evaluate returns, so each answer cost the setting one
        -- reference until it was freed under the camera. Now each answer carries its own reference (a small, harmless
        -- leak on an asset that lives all session), only the live asset is answered for, and the cache is dropped
        -- when the world loads.
        if not R.aim_eval_hooked then
            R.aim_eval_hooked = true
            sdk.hook(asset:get_type_definition():get_method("evaluate"), function(args)
                R.aim_eval_this = sdk.to_int64(args[2])
            end, function(retval)
                local pick = R.aim_pick
                if R.aim_hold and pick and R.aim_eval_this == R.aim_asset_addr and os.clock() < (R.aim_until or 0) then
                    local okr = pcall(pick.add_ref, pick)
                    if okr then
                        R.aim_evals = (R.aim_evals or 0) + 1
                        return sdk.to_ptr(pick:get_address())
                    end
                end
                return retval
            end)
        end
        if R.aim_pick_idx ~= idx then
            R.aim_pick_idx = idx
            ac:call("setupAim(app.AimCameraSetting.AimSetting)", s)
            R.aim_setups = (R.aim_setups or 0) + 1
        end
    end)
    if not ok and not R.aim_setup_err then R.aim_setup_err = true; dev_error("aim setup", err) end
end
R.aim_tick = function()
    if not cfg.pawn_aim_camera or R.aim_off then
        if R.aim_hold then R.aim_stop() end
        return
    end
    local now = os.clock()
    local want = false
    if state.active and not coop.active and state.pawn_chara and state.pawn_job == 2 and native.pip and not native.failed then
        local _, up = node_names(state.pawn_chara)
        if up:find("Job02_StartAim", 1, true)
            or (R.aim_hold and up:find("Job02", 1, true) and not up:find("AimCancel", 1, true) and not up:find("WithoutAim", 1, true)) then
            R.aim_t = now
        end
        want = R.aim_t ~= nil and (now - R.aim_t) < 0.25
    end
    if not want then
        if R.aim_hold then R.aim_stop() end
        return
    end
    R.aim_install()
    if R.aim_off then return end
    local mcc = R.aim_mcc()
    if not mcc then return end
    R.aim_hold, R.aim_until = true, now + 0.5
    R.aim_setup(mcc)
    if not R.aim_on_aim(mcc) and now >= (R.aim_req_t or 0) then
        R.aim_req_t = now + 0.5
        local ip = R.aim_interp("enter")
        if ip then
            R.aim_mine = true
            local ok, err = pcall(mcc.call, mcc, R.aim_sig, 7, ip, nil, 0)
            R.aim_mine = false
            R.aim_reqs = (R.aim_reqs or 0) + 1
            if not ok and not R.aim_err then R.aim_err = true; dev_error("aim camera", err) end
        end
    end
    if get_cam_angle_rad_method then -- body turns with the camera, as it does for the Arisen
        local okr, rad = pcall(get_cam_angle_rad_method.call, get_cam_angle_rad_method, nil)
        if okr and type(rad) == "number" then
            call(state.pawn_chara, "set_TargetFrontAngleDeg(System.Single)", math.deg(rad) + 0.0)
        end
    end
    R.aim_reticle()
end
-- v0.9.39 co-op gyro. The DualSense's motion sensor aims the Arisen's bow camera (RotateCameraControllerBase has
-- GyroEnable / GyroSensitivity / _GyroAngle; app.UserPadManager.isMotionSensorEnable() is the game's own option
-- check), and in co-op that controller is in player 2's hands. While co-op is on: the option check answers false, and
-- the camera controller in use has its GyroEnable cleared each frame. Both stop the moment co-op ends.
-- v0.9.80 the Arisen cannot die while a pawn is possessed (normal possession; in co-op player 1 plays him).
-- HitController.IsNoDie is the game's own flag: he still takes damage and drops to his last sliver of health, but
-- does not go down, so a mistake by the brain is not a game over. Cleared on release, in co-op and on script reset.
R.guard_tick = function()
    local want = (state.active and not coop.active and cfg.arisen_no_death) and true or false
    if want and R.cp and R.cp.on and R.cp.ar2 and not cfg.coop_p2_arisen_no_death then want = false end -- 0.9.171
    local now = os.clock()
    if want == (R.nodie_on or false) and now < (R.nodie_next or 0) then return end
    if not want and not R.nodie_on then return end
    R.nodie_next = now + 1.0
    local ok = pcall(function()
        local ar = sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer")
        ar:call("get_Hit"):call("set_IsNoDie", want)
    end)
    if ok and want ~= (R.nodie_on or false) then
        log_msg("Arisen death protection " .. (want and "ON" or "off"))
    end
    if ok then R.nodie_on = want end
end
-- v0.9.80 which button names to show player 2: "ps" or "xbox", from the controller that last gave input
-- (via.hid.GamePad.get_LastInputDevice().get_DeviceKindDetails()), unless coop_pad_names forces one.
R.pad_style = function()
    if cfg.coop_pad_names == 2 then return "ps" elseif cfg.coop_pad_names == 3 then return "xbox" end
    local now = os.clock()
    if R.pad_style_v and now < (R.pad_style_next or 0) then return R.pad_style_v end
    R.pad_style_next = now + 1.0
    local v = R.pad_style_v or "ps"
    pcall(function()
        local gp = sdk.get_native_singleton("via.hid.GamePad")
        local td = sdk.find_type_definition("via.hid.GamePad")
        local dev = sdk.call_native_func(gp, td, "get_LastInputDevice")
        local k = dev and dev:call("get_DeviceKindDetails")
        R.pad_kind = k
        if k == 5 or k == 6 or k == 8 or k == 9 then v = "ps"
        elseif k and k >= 11 and k <= 23 then v = "xbox" end
    end)
    R.pad_style_v = v
    return v
end
-- v0.9.100 the game's own controller assignment: UserInputManager.getCurrentCharacterPadAssign().AssignList, one
-- Info per binding (Action index, GamePadButton mask, PreInput = the shift action that must be held). Read live
-- 2026-11-16: Skill1 = L1+Square, Skill2 = L1+Triangle, Skill3 = L1+R1, Skill4 = L1+R2, Skill5 = L1+Triangle+Circle,
-- Skill6 = L1+Square+Cross (the game moves 3 / 4 off Circle / Cross when chord slots are in use). The skill buttons
-- for co-op, for aimed skills and for the labels all come from here now; the old fixed tables are the fallback.
R.bind_read = function()
    local now = os.clock()
    if now < (R.bind_next or 0) then return end
    R.bind_next = now + 2.0
    local ok, err = pcall(function()
        local uim = sdk.get_managed_singleton("app.UserInputManager")
        local pa = uim and uim:call("getCurrentCharacterPadAssign")
        local list = pa and pa:get_field("AssignList")
        local n = list and list:call("get_Count") or 0
        if n == 0 then return end
        local idx = {}
        for s = 1, 6 do
            local f = ACTION_FLAGS["Skill" .. s]
            if f and f ~= 0 then for b = 0, 63 do if f == (1 << b) then idx[b] = s end end end
        end
        local pad, pre, sig = {}, {}, ""
        for i = 0, n - 1 do
            local it = list:call("get_Item", i)
            local a, b, p = it:get_field("Action"), it:get_field("Button"), it:get_field("PreInput")
            local s = idx[a]
            if s and b and b ~= 0 and not pad[s] then pad[s], pre[s] = b, p or 0; sig = sig .. s .. ":" .. b .. " " end
        end
        -- v0.9.124: every binding, not only the skills (R.bind.by[action name] = { button masks }, R.bind.list for
        -- the co-op map). Action index a <-> input flag 1 << a; PreInput 14 / 15 = Shift1 / Shift2 must be held.
        local names = {}
        for nm, v in pairs(ACTION_ENUM or {}) do if type(v) == "number" then names[v] = names[v] or {}; table.insert(names[v], nm) end end
        local all, by, sig_all = {}, {}, ""
        for i = 0, n - 1 do
            local it = list:call("get_Item", i)
            local a, b, p = it:get_field("Action"), it:get_field("Button"), it:get_field("PreInput")
            if type(a) == "number" and type(b) == "number" and b ~= 0 then
                local ign = it:get_field("IsIgnorePreInput") == true
                local prei = (type(p) == "number" and p ~= 0 and not ign) and p or nil
                for _, nm in ipairs(names[a] or { "Action" .. a }) do
                    all[#all + 1] = { a = a, name = nm, flag = ACTION_FLAGS[nm] or (1 << a), pad = b, pre = prei }
                    by[nm] = by[nm] or {}
                    table.insert(by[nm], b)
                end
                sig_all = sig_all .. a .. ":" .. b .. ":" .. tostring(prei or 0) .. " "
            end
        end
        if next(pad) then
            if R.bind and R.bind.sig ~= sig then log_msg("Controller skill buttons changed: " .. sig) end
            if not R.bind then log_msg("Controller skill buttons (from the game): " .. sig) end
            if R.bind and R.bind.sig_all ~= sig_all then
                log_msg("Controller layout changed in the game's options: the co-op button map is rebuilt")
                coop.map = nil
            end
            R.bind = { pad = pad, pre = pre, sig = sig, list = all, by = by, sig_all = sig_all }
            if not R.bind_logged then
                R.bind_logged = true
                local function nm(a) return R.btn_text(R.bind_mask(a)) or "-" end
                log_msg(string.format("Controller layout (from the game): light %s, heavy %s, jump %s, dash %s, grab %s, vocation action %s, sheathe %s, skill shift %s",
                    nm("AttackS"), nm("AttackL"), nm("Jump"), nm("Dash"), nm("Grab"), nm("JobSpecialAction"), nm("Sheathe"), nm("Shift1")))
            end
        end
    end)
    if not ok then R.bind_err = tostring(err) end
end
R.BTN_NAMES = { { "RLeft", "Square" }, { "RUp", "Triangle" }, { "RRight", "Circle" }, { "RDown", "Cross" },
                { "RTrigTop", "R1" }, { "RTrigBottom", "R2" }, { "LTrigTop", "L1" }, { "LTrigBottom", "L2" },
                { "LStickPush", "L3" }, { "RStickPush", "R3" },
                { "LUp", "D-pad up" }, { "LDown", "D-pad down" }, { "LLeft", "D-pad left" }, { "LRight", "D-pad right" } }
-- v0.9.124 the game's keyboard / mouse bindings: UserInputManager.KeyBindController.getCurrentKeyBindSettingTable(),
-- 101 app.KeyBindSettingItem (found with bridge probe kb3, 2026-11-17): _CharacterCommand = the same Action index
-- as the pad list, _PrimaryKey / _SecondaryKey / _ThirdKey = via.hid.KeyboardKey, which are Windows virtual-key
-- codes (W 87, Space 32, left mouse 1, right mouse 2, left Ctrl 162). Read into R.kbind[action index].
R.kbind_read = function()
    -- v0.9.125: not on a timer any more. The game crashed 17 s into a co-op session on 0.9.124 (access violation
    -- in its own HUD code, ui020901.update -> setupStatusIcon -> GUIBase.ConditionIconRef.setup, on a worker
    -- thread; cause not established). Walking the game's key table every 6 s from the script thread was the one
    -- new thing that touched game data continuously, so as a precaution it is read once after loading and again
    -- only when a possession or co-op session starts (R.kbind_next = 0 asks for a read).
    local now = os.clock()
    if now < (R.kbind_next or 0) then return end
    R.kbind_next = math.huge
    local ok, err = pcall(function()
        local uim = sdk.get_managed_singleton("app.UserInputManager")
        local kb = uim and uim:get_field("<KeyBindController>k__BackingField")
        local tbl = kb and kb:call("getCurrentKeyBindSettingTable")
        if not tbl then return end
        local t, sig, n = {}, "", 0
        local en = tbl:call("GetEnumerator")
        while en:call("MoveNext") and n < 400 do
            n = n + 1
            local v = en:call("get_Current"):get_field("value")
            if v and v:get_field("_IsSystemInput") ~= true and v:get_field("_DisableBind") ~= true then
                local a = v:get_field("_CharacterCommand")
                if type(a) == "number" and a > 0 then
                    local ks = t[a] or {}
                    for _, fn in ipairs({ "_PrimaryKey", "_SecondaryKey", "_ThirdKey" }) do
                        local k = v:get_field(fn)
                        if type(k) == "number" and k > 0 and k < 256 then ks[#ks + 1] = k end
                    end
                    if #ks > 0 then t[a] = ks; sig = sig .. a .. ":" .. table.concat(ks, ",") .. " " end
                end
            end
        end
        if next(t) then
            if R.kbind and R.kbind_sig ~= sig then log_msg("Keyboard layout changed in the game's options") end
            if not R.kbind then
                local function k(a) return table.concat(t[a] or {}, "/") end
                log_msg(string.format("Keyboard layout (from the game, key codes): forward %s, back %s, left %s, right %s, skill modifier %s, dash %s, jump %s",
                    k(44), k(45), k(46), k(47), k(14), k(4), k(3)))
            end
            R.kbind, R.kbind_sig = t, sig
        end
    end)
    if not ok then R.kbind_err = tostring(err) end
end
-- is a key the game has that action on held? (fallback key when the game's table is not read)
R.key_held = function(action, fallback_vk)
    local a = ACTION_ENUM and ACTION_ENUM[action]
    local ks = a and R.kbind and R.kbind[a]
    if not ks then return fallback_vk ~= nil and is_key_down_safe(fallback_vk) end
    for _, k in ipairs(ks) do if is_key_down_safe(k) then return true end end
    return false
end
-- the mod's own keys that the game also uses for something (shown in the settings window, logged once)
R.key_clashes = function()
    local out = {}
    if not R.kbind then return out end
    local names = {}
    for nm, v in pairs(ACTION_ENUM or {}) do if type(v) == "number" and not names[v] then names[v] = nm end end
    for label, vk in pairs(cfg.keys or {}) do
        if type(vk) == "number" and vk ~= 0 and cfg.keys[tostring(label) .. "_ctrl"] ~= true then
            for a, ks in pairs(R.kbind) do
                for _, k in ipairs(ks) do
                    if k == vk then out[#out + 1] = string.format("%s (key code %d) is also the game's %s", tostring(label), vk, tostring(names[a] or a)) end
                end
            end
        end
    end
    table.sort(out)
    return out
end

-- v0.9.124 the button (mask) the game has an action on; the first one when there are several. nil = not read.
R.bind_mask = function(action)
    local l = R.bind and R.bind.by and R.bind.by[action]
    return l and l[1] or nil
end
-- is that action's button held in this pad state? (any of its buttons; fallback mask when the game's list is not read)
R.bind_held = function(action, btn, fallback)
    local l = R.bind and R.bind.by and R.bind.by[action]
    if not l then return fallback ~= nil and fallback ~= 0 and (btn & fallback) == fallback end
    for _, m in ipairs(l) do if (btn & m) == m then return true end end
    return false
end
R.btn_text = function(mask)
    if not mask or mask == 0 then return nil end
    local pv, parts = coop_pad_values(), {}
    for _, m in ipairs(R.BTN_NAMES) do if pv[m[1]] and (mask & pv[m[1]]) ~= 0 then parts[#parts + 1] = m[2] end end
    if #parts == 0 then return nil end
    return table.concat(parts, "+")
end
R.bind_label = function(slot)
    local t = R.btn_text(R.bind and R.bind.pad[slot])
    if not t then return nil end
    return (R.btn_text(R.bind_mask("Shift1")) or "L1") .. "+" .. t
end
R.PAD_XBOX = { { "Square", "X" }, { "Triangle", "Y" }, { "Circle", "B" }, { "Cross", "A" },
               { "L1", "LB" }, { "R1", "RB" }, { "L2", "LT" }, { "R2", "RT" } }
-- 0.9.172-dev38 (the tester: the skill lists flipped between Xbox and PlayStation names "for everyone not just the
-- applicable controlled pawn"): each player's list follows their own controller. dev_addr = that controller's address
-- (R.tp.p2, a slot's dev); its kind is read once a second per controller. nil / unknown: the last-used controller.
R.dev_style_c = {}
R.dev_style = function(dev_addr)
    if cfg.coop_pad_names == 2 then return "ps" elseif cfg.coop_pad_names == 3 then return "xbox" end
    if not dev_addr or dev_addr == R.KB_ADDR then return R.pad_style() end
    local now = os.clock()
    local c = R.dev_style_c[dev_addr]
    if c and now < c.t then return c.v end
    local v = c and c.v or nil
    pcall(function()
        for _, d in ipairs(R.tp_devs()) do
            if d:get_address() == dev_addr then
                local k = d:call("get_DeviceKindDetails")
                if k == 5 or k == 6 or k == 8 or k == 9 then v = "ps" elseif k and k >= 11 and k <= 23 then v = "xbox" end
            end
        end
    end)
    R.dev_style_c[dev_addr] = { v = v, t = now + 1.0 }
    return v or R.pad_style()
end
R.pad_label = function(lbl, style)
    if (style or R.pad_style()) ~= "xbox" then return lbl end
    for _, m in ipairs(R.PAD_XBOX) do lbl = lbl:gsub(m[1], m[2]) end
    return lbl
end
-- v0.9.38 / 0.9.88 end whatever the pawn's AI is doing. At possession start, and (0.9.88) again whenever a decision is
-- found running while he is possessed: a pawn order given during possession (Go, Come, Help, Wait reach every pawn)
-- started a new one and the possessed pawn ran off on it (reported: a possessed Archer pawn was still running around from an earlier order).
R.interrupt_ai = function(chara, name, with_idle)
    local did = {}
    pcall(function()
        local aidm = call(chara, "get_AIDecisionMaker") or field(chara, "<AIDecisionMaker>k__BackingField")
        local dm = aidm and (call(aidm, "get_DecisionModule") or field(aidm, "<DecisionModule>k__BackingField"))
        local ex = dm and dm:call("get_DecisionExecutor")
        if ex and ex:call("get_ExecutingDecision") ~= nil then
            ex:call("forceEndDecision")
            did[#did + 1] = "decision ended"
        end
    end)
    if with_idle or #did > 0 then
        pcall(function()
            local sel = call(chara, "get_HumanActionSelector")
            if with_idle and sel and sel:call("isEnableRequestIdle") then
                sel:call("requestIdleImpl(System.Boolean)", false)
                did[#did + 1] = "idle requested"
            end
        end)
    end
    if #did > 0 then
        R.ai_ends = (R.ai_ends or 0) + 1
        local now = os.clock()
        if with_idle or now >= (R.ai_log_next or 0) then
            R.ai_log_next = now + 5.0
            log_msg("Interrupted " .. tostring(name) .. "'s AI action: " .. table.concat(did, ", "))
        end
    end
    return #did > 0
end
-- v0.9.93 the pawn being played stops guiding. A pawn that "knows the way" to a quest runs ahead as the party's guide
-- (PawnManager.PawnConcierge, an app.Concierge with _ConciergeCharacter = that pawn). That is not a decision, so
-- ending decisions did not stop it: the played pawn kept being steered toward the destination and fought the
-- player's input. Ask the game to end the guidance (the same request a "Come" order makes); if it is still
-- guiding 1.5 s later, end the navigation outright.
R.guide_stop = function(chara, name)
    local ok, err = pcall(function()
        local pm = sdk.get_managed_singleton("app.PawnManager")
        local con = pm and pm:call("get_PawnConcierge")
        if not con or con:call("get_IsConcierge") ~= true then R.guide_t0 = nil; return end
        local cc = con:call("get_ConciergeCharacter")
        if not (cc and same_obj(cc, chara)) then R.guide_t0 = nil; return end
        local now = os.clock()
        if not R.guide_t0 then
            R.guide_t0 = now
            con:call("requestEndGuidancePawn")
            R.guide_stops = (R.guide_stops or 0) + 1
            log_msg("Guide: " .. tostring(name) .. " was leading the way to a quest; asked the game to end the guidance")
        elseif now - R.guide_t0 > 1.5 then
            R.guide_t0 = now
            con:call("endNavigation")
            R.guide_forced = (R.guide_forced or 0) + 1
            log_msg("Guide: " .. tostring(name) .. " was still guiding after 1.5 s; navigation ended")
        end
    end)
    if not ok then dev_error("guide stop", err) end
end
-- v0.9.94 dev only: the first 15 s of every possession, 10 samples a second, to data/DPC_takeover.json: where the
-- pawn is, how hard the player pushes the stick, the pawn's action nodes, the decision being executed, the guide
-- (Concierge) state and the navigation state. Shows what moves a pawn the player is not moving.
-- v0.9.149 controls the player can change, and the on-screen hint that names them.
R.VK = { [0x08] = "Backspace", [0x09] = "Tab", [0x0D] = "Enter", [0x13] = "Pause", [0x14] = "Caps Lock", [0x20] = "Space", [0x21] = "Page Up",
         [0x22] = "Page Down", [0x23] = "End", [0x24] = "Home", [0x25] = "Left", [0x26] = "Up", [0x27] = "Right", [0x28] = "Down",
         [0x2D] = "Insert", [0x2E] = "Delete", [0x6A] = "Numpad *", [0x6B] = "Numpad +", [0x6D] = "Numpad -", [0x6E] = "Numpad .",
         [0x6F] = "Numpad /", [0x90] = "Num Lock", [0x91] = "Scroll Lock", [0xBA] = ";", [0xBB] = "=", [0xBC] = ",", [0xBD] = "-",
         [0xBE] = ".", [0xBF] = "/", [0xC0] = "`", [0xDB] = "[", [0xDC] = "\\", [0xDD] = "]", [0xDE] = "'" }
R.vk_name = function(vk)
    if not vk or vk == 0 then return "none" end
    if R.VK[vk] then return R.VK[vk] end
    if (vk >= 0x30 and vk <= 0x39) or (vk >= 0x41 and vk <= 0x5A) then return string.char(vk) end
    if vk >= 0x60 and vk <= 0x69 then return "Numpad " .. (vk - 0x60) end
    if vk >= 0x70 and vk <= 0x87 then return "F" .. (vk - 0x6F) end
    return "key " .. vk
end
R.KEY_DEFAULTS = { toggle_possess = 0x75, cycle_pawn = 0x76, warp_arisen = 0x77, party_heal = 0x6E, party_warp = 0x67, coop = 0x75, coop_ctrl = true,
                   skill1 = 0x61, skill2 = 0x62, skill3 = 0x63, skill4 = 0x64, skill5 = 0x65, skill6 = 0x66,
                   jump_arisen = 0x70, jump_arisen_ctrl = true, jump_pawn1 = 0x71, jump_pawn1_ctrl = true,
                   jump_pawn2 = 0x72, jump_pawn2_ctrl = true, jump_pawn3 = 0x73, jump_pawn3_ctrl = true,
                   jump_pawn4 = 0, jump_pawn5 = 0, jump_pawn6 = 0, jump_pawn7 = 0, jump_pawn8 = 0 }
-- 0.9.172: go straight to a character. Pawn n = the n-th party member in party order (pawn 1 = the main pawn).
R.JUMP_MAX = 8
R.jump_names = {}
R.jump_party = function()
    local party = get_party()
    table.sort(party, function(a, b) return a.idx < b.idx end)
    return party
end
R.jump_to = function(want, label)
    local note = function(t) R.note = { text = t, t_end = os.clock() + 2.5 } end
    if want == nil then note("No " .. tostring(label) .. " in the party"); return false end
    -- co-op, any combination: this is player 1's choice
    if cfg.coop_any and R.cp and R.cp.on then
        local c = R.cp
        if want == c.char[1] then return false end
        if want == c.char[2] then note(tostring(label) .. " is player 2's"); return false end
        if type(want) == "number" and R.held_by and R.held_by(want) and R.held_by(want) >= 3 then
            note(tostring(label) .. " is player " .. R.held_by(want) .. "'s"); return false
        end
        if not R.cp_quiet_ok() then return false end
        return R.cp_apply({ [1] = want, [2] = c.char[2] }, "player 1's key") ~= false
    end
    if coop.active then note("In co-op without 'Any combination', use the take-control key"); return false end
    if want == "arisen" then
        if state.active then release_possession("key: the Arisen") end
        return true
    end
    if state.active and state.pawn_idx == want then return false end
    cfg.selected_pawn_idx = want
    save_cfg()
    start_possession(want)
    return true
end
R.jump_tick = function()
    if R.cap then return end
    local now = os.clock()
    if now - (R.jump_names_t or 0) > 1.0 then -- names for the settings window (read here, on the game thread)
        R.jump_names_t = now
        local t = {}
        for i, e in ipairs(R.jump_party()) do t[i] = tostring(e.name) end
        R.jump_names = t
    end
    if R.key_hit("jump_arisen") then R.jump_to("arisen", "the Arisen") return end
    for k = 1, R.JUMP_MAX do
        if R.key_hit("jump_pawn" .. k) then
            local e = R.jump_party()[k]
            R.jump_to(e and e.idx or nil, e and tostring(e.name) or ("pawn " .. k))
            return
        end
    end
end
-- the controller combination for "take control / next pawn" (0 in the settings = L1 + left stick click)
R.take_mask = function()
    local m = tonumber(cfg.pad.take) or 0
    if m ~= 0 then return m end
    local pv = coop_pad_values()
    return (pv.LTrigTop or 0x100) | (pv.LStickPush or 0)
end
R.combo_name = function(mask)
    local t = R.btn_text(mask)
    if not t then return nil end
    local ok, x = pcall(R.pad_label, t)
    return (ok and type(x) == "string") and x or t
end
-- the pawn L1 + left stick click goes to while a pawn is played: the next one in party order, wrapping round
-- v0.9.150: (1) a character picked with the arrows a moment ago comes first: while the selection arrow is still up
-- (R.ping, 3 s) the combination goes to that pick, pawn or Arisen. (2) Otherwise the next pawn in party order, and
-- after the last pawn the Arisen ("arisen"), so one button walks the whole party round. With cycle_skip_arisen the
-- round is pawns only (0.9.148's behaviour). nil = nobody to go to.
R.next_pawn = function(party)
    if R.ping and os.clock() < (R.ping.t_end or 0) then
        if R.sel_kind == "arisen" then return "arisen", true end
        if R.sel_kind == "pawn" and R.sel_idx ~= nil and R.sel_idx ~= state.pawn_idx then
            for _, e in ipairs(party) do if e.idx == R.sel_idx then return e, true end end
        end
    end
    local nxt
    for _, e in ipairs(party) do if e.idx > state.pawn_idx and (not nxt or e.idx < nxt.idx) then nxt = e end end
    if nxt then return nxt end
    if not cfg.cycle_skip_arisen then return "arisen" end
    for _, e in ipairs(party) do if e.idx ~= state.pawn_idx and (not nxt or e.idx < nxt.idx) then nxt = e end end
    return nxt
end
-- v0.9.154 cheat, off by default: special arrows are free while a pawn is played (possession or co-op). Requested:
-- an Archer pawn needs Explosive / Blighting / Tarring / Drenching Arrows in its bag for the matching skills and
-- uses them up. Read live: the four items are ids 169 / 166 / 168 / 167, and ItemManager keeps running counts of
-- the PLAYER's (_ExplosiveArrowNum was 11 = the Arisen's 11 Explosive Arrows, the pawns held none).
-- (1) Not used up: every ItemManager call that removes items by id (deleteItem / deleteItemNoLock / deletePartyItem
--     and their overloads with an item id) is skipped for those four ids, and so is a negative addArrowNum.
-- (2) Not needed (cheat_free_arrows_nobag): the four arrow counters and getHaveNum for those ids answer at least 1.
-- What the game really asks before a special-arrow skill, and which call takes the arrow away, is not known from
-- names alone, so every hook counts what it saw (R.arrows.n, in the developer status file) for the first test.
R.arrows = { ids = { [166] = true, [167] = true, [168] = true, [169] = true }, n = {},
             KIND = { [17] = "Bomb", [18] = "Water", [19] = "Oil", [20] = "Poison" } } -- HumanCustomSkillID Job02_SpecialAllow*
R.arrow_on = function() return cfg.cheat_free_arrows and state.active end
-- v0.9.162: the "not needed in the bag" half is switched off for good in this build. With it on the game crashed twice
-- (2026-11-17 and 2026-11-18 about [time]): the forced with-arrow action works for a shot or two, then fires
-- plain arrows, then the game goes down. The code stays for a later look with the decompile; the setting is forced
-- off here whatever the config file says, and the menu line is gone.
cfg.cheat_free_arrows_nobag = false
R.arrow_hook = function()
    local A = R.arrows
    if A.hooked ~= nil or not cfg.cheat_free_arrows then return end
    A.hooked = false
    local ok, err = pcall(function()
        local im = sdk.find_type_definition("app.ItemManager")
        local function bump(k) A.n[k] = (A.n[k] or 0) + 1 end
        for _, sig in ipairs({ "deleteItem(System.Int32, System.Int32, app.CharacterID)", "deleteItem(System.Int32, System.Int32, app.Character)",
                               "deleteItemNoLock(System.Int32, System.Int32, app.CharacterID)", "deleteItemNoLock(System.Int32, System.Int32, app.CharacterID, System.Int32)",
                               "deletePartyItem(System.Int32, System.Int32)", "deletePartyItemNoLock(System.Int32, System.Int32, System.Boolean, System.Boolean)" }) do
            local m = im:get_method(sig)
            if m then
                local key = "kept " .. sig:match("^(%w+)") .. (sig:find("Character%)") and " (chara)" or "")
                local owner_kind = sig:find("app.CharacterID", 1, true) and "id" or (sig:find("app.Character%)") and "chara" or nil)
                sdk.hook(m, function(args)
                    if not cfg.cheat_free_arrows then return end
                    local id = sdk.to_int64(args[3]) & 0xFFFFFFFF
                    if not A.ids[id] then return end
                    -- v0.9.163: also while nobody is played, for arrows that are not the Arisen's (the point of the
                    -- cheat, in the requester's words: if the pawns use their arrows up on their own there is nothing
                    -- left to fire when you take one over). The Arisen's own arrows are spared only while a pawn is played.
                    local mine = state.active
                    if not mine and owner_kind == "id" and A.ar_id then mine = (sdk.to_int64(args[5]) & 0xFFFFFFFF) ~= A.ar_id end
                    if not mine and owner_kind == "chara" and A.ar_addr then mine = sdk.to_int64(args[5]) ~= A.ar_addr end
                    if mine then
                        bump(key)
                        if not A.logged then A.logged = true; log_msg("Free arrows: a special arrow (item " .. id .. ") was not used up") end
                        return sdk.PreHookResult.SKIP_ORIGINAL
                    end
                end, function(r) return r end)
            else A.n["missing " .. sig] = 1 end
        end
        for _, sig in ipairs({ "deleteItem(app.ItemDefine.StorageData, System.Int32)", "deleteItemNoLock(app.ItemDefine.StorageData, System.Int32, System.Boolean)" }) do
            local m = im:get_method(sig) -- by stored-item record: only counted, the id is not readable here
            if m then sdk.hook(m, function(args) if R.arrow_on() then bump("seen by-record " .. sig:match("^(%w+)")) end end, function(r) return r end) end
        end
        local an = im:get_method("addArrowNum(app.CharacterID, System.Int32, System.Int32)")
        if an then
            sdk.hook(an, function(args)
                if not cfg.cheat_free_arrows then return end
                if not state.active and not (A.ar_id and (sdk.to_int64(args[3]) & 0xFFFFFFFF) ~= A.ar_id) then return end
                local v = sdk.to_int64(args[5]) & 0xFFFFFFFF
                bump("addArrowNum " .. ((v >= 0x80000000) and "minus" or "plus"))
                if v >= 0x80000000 then return sdk.PreHookResult.SKIP_ORIGINAL end
            end, function(r) return r end)
        end
        for _, g in ipairs({ "get_PoisonArrowNum", "get_WaterArrowNum", "get_OilArrowNum", "get_ExplosiveArrowNum" }) do
            local m = im:get_method(g)
            if m then
                sdk.hook(m, function(args) end, function(r)
                    if not (R.arrow_on() and cfg.cheat_free_arrows_nobag) then return r end
                    bump(g)
                    if (sdk.to_int64(r) & 0xFFFFFFFF) < 1 then bump("raised " .. g); return sdk.to_ptr(1) end
                    return r
                end)
            end
        end
        for _, sig in ipairs({ "getHaveNum(System.Int32, app.CharacterID)", "getHaveNum(System.Int32, app.Character)" }) do
            local m = im:get_method(sig)
            if m then
                sdk.hook(m, function(args)
                    thread.get_hook_storage().dpc_arrow = (R.arrow_on() and cfg.cheat_free_arrows_nobag and A.ids[sdk.to_int64(args[3]) & 0xFFFFFFFF]) or false
                end, function(r)
                    if thread.get_hook_storage().dpc_arrow then
                        bump("asked getHaveNum")
                        if (sdk.to_int64(r) & 0xFFFFFFFF) < 1 then bump("raised getHaveNum"); return sdk.to_ptr(1) end
                    end
                    return r
                end)
            end
        end
        -- v0.9.155: 0.9.154's "not needed" did not work: with no arrows the Archer pawn played the missing-arrow action
        -- although getHaveNum had been raised to 1 ten times (the counter getters were never asked). The action is
        -- chosen by Job02ActionSelector.getSpecialArrowAction(Boolean, HumanCustomSkillID, String), which hands back
        -- "Job02_NoSpecialArrow" / "Job02_NoClimbingSpecialArrow" when there is no arrow. Assumption, to be shown by
        -- the first test: the String argument is the action it would have returned with an arrow. When the answer is
        -- one of the two "no arrow" actions, that argument is returned instead. Both strings are kept for the status
        -- file (arrows.last_action) so a wrong assumption shows at once.
        local sm = sdk.find_type_definition("app.Job02ActionSelector"):get_method("getSpecialArrowAction(System.Boolean, app.HumanCustomSkillID, System.String)")
        if sm then
            sdk.hook(sm, function(args)
                local hs = thread.get_hook_storage()
                hs.dpc_arrow_arg = (R.arrow_on() and cfg.cheat_free_arrows_nobag) and args[5] or nil
                hs.dpc_arrow_flag = sdk.to_int64(args[3]) & 1
            end, function(r)
                local hs = thread.get_hook_storage()
                local arg = hs.dpc_arrow_arg
                if not arg then return r end
                local out = r
                pcall(function()
                    local rs = sdk.to_managed_object(r)
                    local as = sdk.to_managed_object(arg)
                    local rt = rs and tostring(rs:call("ToString")) or "nil"
                    local at = as and tostring(as:call("ToString")) or "nil"
                    bump("asked getSpecialArrowAction")
                    A.n.last_action = string.format("flag %s, argument '%s', answer '%s'", tostring(hs.dpc_arrow_flag), at, rt)
                    if rt:find("NoSpecialArrow", 1, true) or rt:find("NoClimbingSpecialArrow", 1, true) then
                        if as and at ~= "" and at ~= "nil" and not at:find("NoSpecialArrow", 1, true) then
                            bump("swapped no-arrow action")
                            out = arg
                        else
                            bump("no-arrow action, nothing to swap in")
                        end
                    end
                end)
                return out
            end)
        else A.n["missing getSpecialArrowAction"] = 1 end
        -- v0.9.156 diagnostics: the action the Archer's selector hands back for a weapon skill
        local cm = sdk.find_type_definition("app.Job02ActionSelector"):get_method("getCustomSkillAction(app.HumanCustomSkillID, app.LocomotionSpeedTypeEnum)")
        if cm then
            sdk.hook(cm, function(args) thread.get_hook_storage().dpc_arrow_skill = R.arrow_on() and (sdk.to_int64(args[3]) & 0xFFFFFFFF) or nil end, function(r)
                local id = thread.get_hook_storage().dpc_arrow_skill
                local out = r
                if id then pcall(function()
                    local rs = sdk.to_managed_object(r)
                    local rt = rs and tostring(rs:call("ToString")) or "nil"
                    bump("asked getCustomSkillAction")
                    A.n.last_skill_action = string.format("skill %d -> '%s'", id, rt)
                    -- v0.9.157: this is where the no-arrow action comes from (read live on 0.9.156: skill 19, the oil
                    -- arrow, -> 'Job02_NoSpecialArrow' with every count raised). The answer is replaced by the action
                    -- of the same skill with an arrow, by name: aiming -> Job02_PrepareSpecialArrow<Kind>, not aiming
                    -- -> Job02_SpecialArrow<Kind>WithoutAim, climbing -> Job02_ClimbingSpecialArrow<Kind> (names from
                    -- the game's action enums; which one the game itself returns with an arrow has not been seen).
                    -- The bow carries the four arrow props whether or not the bag holds arrows (read live).
                    local kind = A.KIND[id]
                    if kind and cfg.cheat_free_arrows_nobag then
                        local want
                        if rt == "Job02_NoSpecialArrow" then want = "Job02_PrepareSpecialArrow" .. kind
                        elseif rt == "Job02_NoSpecialArrowWithoutAim" then want = "Job02_SpecialArrow" .. kind .. "WithoutAim"
                        elseif rt == "Job02_NoClimbingSpecialArrow" then want = "Job02_ClimbingSpecialArrow" .. kind end
                        if want then
                            A.str = A.str or {}
                            if not A.str[want] then local ms = sdk.create_managed_string(want); A.str[want] = ms and ms:add_ref() end
                            if A.str[want] then
                                out = sdk.to_ptr(A.str[want]:get_address())
                                bump("swapped to " .. want)
                            end
                        end
                    end
                end) end
                return out
            end)
        end
        A.hooked = true
        log_msg("Free arrows: hooks installed")
    end)
    if not ok then dev_error("free arrows hook", err) end
end
-- v0.9.156 third try at "not needed". On 0.9.155 neither getHaveNum nor getSpecialArrowAction was called when the
-- skill was pressed (all counters empty after a minute of trying), so the choice is made inside native code. What
-- is left to read there: ItemManager's four counters, read as fields. They hold the PLAYER's arrows (11 with the
-- Arisen's 11 Explosive Arrows) and a played pawn goes through the player's input, so the guess is that the game
-- looks at these for whoever the player is driving. While the cheat is on and a pawn is played, each counter that
-- is below 1 is held at 1; when the pawn is released or the cheat goes off, a counter this code raised and that
-- still reads 1 goes back to 0. A negative addArrowNum is skipped (0.9.154), so a shot does not take it below 1.
R.arrow_tick = function()
    if cfg.cheat_free_arrows and os.clock() >= (R.arrows.ar_next or 0) then -- v0.9.163: who the Arisen is, for the hooks
        R.arrows.ar_next = os.clock() + 3.0
        pcall(function()
            local ar = sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer")
            local cid = ar and ar:call("get_CharaID")
            if type(cid) == "userdata" then cid = cid:get_field("value__") end
            R.arrows.ar_id = type(cid) == "number" and (cid & 0xFFFFFFFF) or nil
            R.arrows.ar_addr = ar and ar:get_address() or nil
        end)
    end
    -- v0.9.160: the four counters are what the skill list prints in front of a special-arrow skill ("00 Incendiary
    -- Shot"). They count the Arisen's arrows, so a played Archer pawn carrying five of each read 00 (screenshots).
    -- While a pawn is played (not co-op, where the HUD is the Arisen's) they are set to the played pawn's own
    -- counts twice a second, and to the Arisen's again on release. With the experimental no-bag cheat on, a count
    -- of 0 is shown as 1. Display only: the game's own check for the skill does not read these (0.9.156).
    local A = R.arrows
    local on = cfg.pawn_arrow_counts and state.active and not coop.active and state.pawn_chara ~= nil
    if not on and not A.shown then return end
    local now = os.clock()
    if on and now < (A.next or 0) then return end
    A.next = now + 0.5
    pcall(function()
        local im = sdk.get_managed_singleton("app.ItemManager")
        if not im then return end
        local who = on and state.pawn_chara or sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer")
        if not who then return end
        for f, id in pairs({ _PoisonArrowNum = 166, _WaterArrowNum = 167, _OilArrowNum = 168, _ExplosiveArrowNum = 169 }) do
            local n = im:call("getHaveNum(System.Int32, app.Character)", id, who)
            if type(n) == "number" then
                if on and n < 1 and R.arrow_on() and cfg.cheat_free_arrows_nobag then n = 1 end
                if im:get_field(f) ~= n then
                    im:set_field(f, n)
                    A.n["set " .. f] = (A.n["set " .. f] or 0) + 1
                end
            end
        end
        A.shown = on or nil
    end)
end
-- 0.9.172-dev29 (the tester's idea after the "not needed in the bag" crashes): give a played Archer one real special arrow
-- of each kind it has none of, through the game's own ItemManager.getItem, so the skill finds it the normal way.
-- With free arrows on it is never used up; with it off, the next check gives another. The four arrow items weigh
-- nothing while this is on (ItemCommonParam._Weight 0, the game's value put back when it goes off), so a pawn's
-- weight class never flips back and forth. Every 2 s, for each played character (player 1's pawn, player 2's,
-- players 3+), Archers only.
R.arrow_give = { given = 0, w0 = nil, last = nil }
R.arrow_give_tick = function()
    local G = R.arrow_give
    local on = cfg.cheat_free_arrows and cfg.free_arrows_give ~= false
    local im = sdk.get_managed_singleton("app.ItemManager")
    if not im then return end
    local now = os.clock()
    -- dev32: no longer weightless for everyone (the tester: "that made all arrows no weight"); the item weights the dev29
    -- build changed are put back, and only the arrows DPC gave are taken off their carrier's weight (R.arrow_weight).
    if G.w0 then
        for id, w in pairs(G.w0) do
            pcall(function() local d = im:call("getItemData(System.Int32)", id); if d and w then d:set_field("_Weight", w) end end)
        end
        G.w0 = nil
    end
    if not on or now < (G.next or 0) then return end
    pcall(R.arrow_weight_update, im)
    G.next = now + 2.0
    local who = {}
    if state.active and state.pawn_chara and state.pawn_job == 2 then who[#who + 1] = state.pawn_chara end
    if R.s2 and R.s2.active and R.s2.chara and R.s2.job == 2 then who[#who + 1] = R.s2.chara end
    if R.np then for _, sl in pairs(R.np.slots) do if sl.active and sl.chara and sl.job == 2 then who[#who + 1] = sl.chara end end end
    for _, ch in ipairs(who) do
        for id in pairs(R.arrows.ids) do
            pcall(function()
                local n = im:call("getHaveNum(System.Int32, app.Character)", id, ch)
                if type(n) == "number" and n < 1 then
                    -- dev31: without the "obtained" popup (the tester saw one per arrow): GetItemOption.Default with IsNotice
                    -- (and the log / new-mark flags) off; the plain call if that overload refuses
                    local okq = pcall(function()
                        local td = sdk.find_type_definition("app.ItemDefine.GetItemOption")
                        local opt = td:get_field("Default"):get_data(nil)
                        opt:set_field("IsNotice", false)
                        opt:set_field("IsHistory", false)
                        opt:set_field("IsNewMark", false)
                        opt:set_field("IsRecord", false)
                        im:call("getItem(System.Int32, System.Int32, app.Character, app.ItemDefine.GetItemOption)", id, 1, ch, opt)
                    end)
                    if not okq then im:call("getItem(System.Int32, System.Int32, app.Character)", id, 1, ch); G.loud = (G.loud or 0) + 1 end
                    -- remember who got it (by character id) so its weight can be taken off that character only
                    local cid = ch:call("get_CharaID")
                    if type(cid) == "userdata" then cid = cid:get_field("value__") end
                    if type(cid) == "number" then
                        cid = cid & 0xFFFFFFFF
                        G.owed = G.owed or {}
                        G.owed[cid] = G.owed[cid] or { chara = ch, ids = {} }
                        G.owed[cid].ids[id] = (G.owed[cid].ids[id] or 0) + 1
                        G.owed[cid].chara = ch
                    end
                    G.given = G.given + 1
                    G.last = string.format("%d to %s", id, tostring(call(ch, "get_CharaIDString")))
                    R.arrows.n["given"] = (R.arrows.n["given"] or 0) + 1
                end
            end)
        end
    end
end

-- 0.9.172-dev30 downed-party alert (the tester lost two pawns to the Rift without noticing they were down while playing a
-- pawn in co-op with the camera pulled back). While a pawn is played or co-op runs, every party member that is down
-- (get_IsDead: down and waiting for a revive) is named at the top of the screen with how far and which way from the
-- character you play, and for how long it has been down. cfg.down_alert.
R.down = { t0 = {} }
R.down_list = function()
    local out = {}
    if not (cfg.down_alert ~= false and (state.active or coop.active)) then R.down.t0 = {}; return out end
    local me = state.pawn_chara or state.arisen_chara
    local mx, _, mz = brain_pos(me)
    local yaw = R.cam_yaw and R.cam_yaw() or nil
    local now = os.clock()
    local seen = {}
    local who = {}
    for _, e in ipairs(R.party_all() or {}) do who[#who + 1] = { chara = e.chara, name = e.name } end
    if state.active and state.arisen_chara then who[#who + 1] = { chara = state.arisen_chara, name = "the Arisen" } end
    for _, w in ipairs(who) do
        local ok, dead = pcall(function() return w.chara:call("get_IsDead") == true end)
        if ok and dead then
            local key = w.chara:get_address()
            seen[key] = true
            R.down.t0[key] = R.down.t0[key] or now
            local x, _, z = brain_pos(w.chara)
            local where = ""
            if x and mx then
                local d = math.sqrt((x - mx) ^ 2 + (z - mz) ^ 2)
                local dir = ""
                if yaw then
                    local a = math.deg(brain_angdiff(math.atan(x - mx, z - mz), yaw))
                    if math.abs(a) <= 35 then dir = "ahead" elseif math.abs(a) >= 145 then dir = "behind you"
                    elseif a > 0 then dir = "to the right" else dir = "to the left" end
                end
                where = string.format("%.0f m %s", d, dir)
            end
            out[#out + 1] = { name = w.name, where = where, secs = now - R.down.t0[key] }
        end
    end
    for k in pairs(R.down.t0) do if not seen[k] then R.down.t0[k] = nil end end
    return out
end
re.on_frame(function()
    local ok, err = pcall(function()
        if R.hud_hidden() then return end
        local list = R.down_list()
        if #list == 0 then return end
        local hx, hy, hw, hh = R.hud_rect()
        imgui.set_next_window_pos(Vector2f.new(hx + hw * 0.5 - 220, hy + hh * 0.09), 1)
        imgui.begin_window("DirectPawnControl_Down", nil, (1 << 0) | (1 << 1) | (1 << 3) | (1 << 6))
        local blink = (math.floor(os.clock() * 2) % 2 == 0) and 0xFF4040FF or 0xFF6060E0
        for _, d in ipairs(list) do
            imgui.text_colored(string.format("%s is DOWN - %s - revive them (%d s)", tostring(d.name), d.where, math.floor(d.secs)), blink)
        end
        imgui.end_window()
    end)
    if not ok then dev_error("down alert", err) end
end)

-- dev32: the arrows DPC gave weigh nothing for the character carrying them, and nothing else changes. Like a weight
-- bonus, but exact: ItemManager.getStorageWeight (both overloads, kg) and getStorageWeightInt (the same in the game's
-- integer unit, scale read from the two) answer less by the weight of the given arrows that character still holds
-- (at most what DPC gave, so arrows it bought or found still count). Recomputed every 2 s; G.kg[charaId] = kg.
R.arrow_weight_update = function(im)
    local G = R.arrow_give
    G.kg = {}
    for cid, o in pairs(G.owed or {}) do
        local kg = 0.0
        for id, n in pairs(o.ids) do
            local have = 0
            pcall(function() have = im:call("getHaveNum(System.Int32, app.Character)", id, o.chara) or 0 end)
            local d = im:call("getItemData(System.Int32)", id)
            local w = d and d:call("get_WeightF") or 0.0
            if have < n then o.ids[id] = have; n = have end
            kg = kg + math.max(0, n) * (tonumber(w) or 0.0)
        end
        if kg > 0 then G.kg[cid] = kg end
    end
    if G.hooked == nil then
        G.hooked = false
        local td = sdk.find_type_definition("app.ItemManager")
        -- by_obj: the argument is an app.Character; otherwise an app.CharacterID (an enum value, never a pointer)
        local function cid_of(a, by_obj)
            local ok, v = pcall(function()
                if by_obj then
                    local o = sdk.to_managed_object(a)
                    local x = o and o:call("get_CharaID")
                    if type(x) == "userdata" then x = x:get_field("value__") end
                    return x
                end
                return sdk.to_int64(a)
            end)
            return ok and type(v) == "number" and (v & 0xFFFFFFFF) or nil
        end
        local function hook(sig, is_int, by_obj)
            local m = td and td:get_method(sig)
            if not m then return end
            sdk.hook(m, function(args)
                local st = thread.get_hook_storage()
                st.aw_cid = (G.kg and next(G.kg)) and cid_of(args[3], by_obj) or nil
            end, function(r)
                local kg = G.kg and G.kg[thread.get_hook_storage().aw_cid or -1]
                if not kg then return r end
                if is_int then
                    local v = sdk.to_int64(r) & 0xFFFFFFFF
                    if v >= 0x80000000 then v = v - 0x100000000 end
                    local scale = G.int_scale or 100.0
                    return sdk.to_ptr(math.max(0, v - math.floor(kg * scale + 0.5)))
                end
                local f = sdk.to_float(r)
                return sdk.float_to_ptr(math.max(0.0, f - kg))
            end)
        end
        hook("getStorageWeight(app.Character)", false, true)
        hook("getStorageWeight(app.CharacterID)", false, false)
        hook("getStorageWeightInt(app.CharacterID)", true, false)
        G.hooked = true
    end
    -- the integer unit, from one character's two readings (before our change: compare raw values with no debt)
    pcall(function()
        local cm = sdk.get_managed_singleton("app.CharacterManager")
        if not cm then return end
        local ar = cm:call("get_ManualPlayer")
        if not ar then return end
        local cid = ar:call("get_CharaID")
        local cn = type(cid) == "userdata" and cid:get_field("value__") or cid
        if type(cn) == "number" and G.kg and (G.kg[cn & 0xFFFFFFFF] or 0) > 0 then return end  -- our own subtraction would skew it
        local f = im:call("getStorageWeight(app.Character)", ar)
        local i = im:call("getStorageWeightInt(app.CharacterID)", cid)
        if type(f) == "number" and f > 1.0 and type(i) == "number" and i > 0 then G.int_scale = i / f end
    end)
end

-- 0.9.172-dev35: Pawn Tactical Wheel (another mod, Lua) opens on L1 + R3 read from the game's merged controller, so in
-- co-op player 2's L1 + R3 (or player 1's R3 target key with L1 held) opened it. All REFramework scripts share one Lua
-- state, so while co-op runs we blank its pad trigger in its loaded input module (IN.BINDS.pad_open_trig = 0; its own
-- check treats 0 as unbound) and put it back after. Its saved config is a separate table and is never touched.
R.ptw = { saved = nil }
R.ptw_tick = function()
    local IN = package.loaded["PawnTacticalWheel.input"]
    if type(IN) ~= "table" or type(IN.BINDS) ~= "table" then return end
    local want = cfg.coop_block_ptw ~= false and (coop.active or (R.cp and R.cp.on)) and true or false
    if want and R.ptw.saved == nil and (IN.BINDS.pad_open_trig or 0) ~= 0 then
        R.ptw.saved = IN.BINDS.pad_open_trig
        IN.BINDS.pad_open_trig = 0
        if IN.W then IN.W.pad_mod_held = false end
    elseif not want and R.ptw.saved ~= nil then
        if (IN.BINDS.pad_open_trig or 0) == 0 then IN.BINDS.pad_open_trig = R.ptw.saved end -- unless the player rebound it meanwhile
        R.ptw.saved = nil
    end
end
re.on_frame(function() pcall(R.ptw_tick) end)
re.on_script_reset(function()
    local IN = package.loaded["PawnTacticalWheel.input"]
    if R.ptw.saved ~= nil and type(IN) == "table" and IN.BINDS and (IN.BINDS.pad_open_trig or 0) == 0 then IN.BINDS.pad_open_trig = R.ptw.saved end
end)

re.on_script_reset(function()
    local G = R.arrow_give
    if not (G and G.w0) then return end
    pcall(function()
        local im = sdk.get_managed_singleton("app.ItemManager")
        for id, w in pairs(G.w0) do local d = im:call("getItemData(System.Int32)", id); if d and w then d:set_field("_Weight", w) end end
    end)
end)

-- v0.9.153 co-op: the next pawn for player 2, pawns only (the Arisen is player 1's), wrapping round
R.next_pawn_only = function(party)
    -- 0.9.172: pawns played by players 3+ are not offered
    local free = {}
    for _, e in ipairs(party) do
        local held = false
        if R.np then for _, sl in pairs(R.np.slots) do if sl.active and sl.idx == e.idx then held = true end end end
        if not held then free[#free + 1] = e end
    end
    party = free
    local nxt
    for _, e in ipairs(party) do if e.idx > state.pawn_idx and (not nxt or e.idx < nxt.idx) then nxt = e end end
    if nxt then return nxt end
    for _, e in ipairs(party) do if e.idx ~= state.pawn_idx and (not nxt or e.idx < nxt.idx) then nxt = e end end
    return nxt
end
-- choosing a key or a button combination in the settings window. R.cap = { kind = "key" | "pad", id = <name in
-- cfg.keys / cfg.pad>, t0 }. Keys: the first key that goes down after everything was let go (Esc cancels).
-- Controller: at least two buttons held together for 0.8 s (one button alone would take a button from the game).
R.cap_tick = function()
    local c = R.cap
    if not c then return end
    local now = os.clock()
    if now - c.t0 > 8.0 or is_key_down_safe(0x1B) then R.cap, R.cap_quiet, R.cap_msg = nil, now + 0.5, "cancelled"; return end
    if c.kind == "key" then
        local down
        for vk = 0x08, 0xDE do
            if vk ~= 0x10 and vk ~= 0x11 and vk ~= 0x12 and vk ~= 0x1B and not (vk >= 0x5B and vk <= 0x5D) and not (vk >= 0xA0 and vk <= 0xB7) then
                if is_key_down_safe(vk) then down = vk; break end
            end
        end
        if not c.armed then
            if not down and now - c.t0 > 0.2 then c.armed = true end
        elseif down then
            cfg.keys[c.id] = down
            cfg.keys[c.id .. "_ctrl"] = is_key_down_safe(0x11)
            save_cfg()
            R.clash_logged = nil
            R.cap, R.cap_quiet, R.cap_msg = nil, now + 0.6, "set to " .. R.vk_name(down)
        end
    else
        local b = pad_buttons or 0
        local n, x = 0, b
        while x ~= 0 do n = n + (x & 1); x = x >> 1 end
        if n >= 2 and b == c.last then
            if now - (c.since or now) >= 0.8 then
                cfg.pad[c.id] = b
                save_cfg()
                R.cap, R.cap_quiet, R.cap_msg = nil, now + 1.0, "set to " .. tostring(R.combo_name(b) or b)
            end
        else
            c.last, c.since = b, now
        end
    end
end
-- the hint line: what the take-control button does right now, with the name of who it goes to. Built twice a
-- second here (game thread), drawn in on_frame. Controller wording while the controller was the last thing used,
-- keyboard wording otherwise.
R.hint_tick = function()
    local now = os.clock()
    if (pad_buttons or 0) ~= 0 or math.abs(pad_stick_x or 0) + math.abs(pad_stick_y or 0) > 0.5 then R.last_dev = "pad"
    elseif is_key_down_safe(0x57) or is_key_down_safe(0x41) or is_key_down_safe(0x53) or is_key_down_safe(0x44)
        or is_key_down_safe(cfg.keys.toggle_possess) or is_key_down_safe(cfg.keys.cycle_pawn) then R.last_dev = "kbm" end
    if now < (R.hint_next or 0) then return end
    R.hint_next = now + 0.2
    R.hint = nil
    if not cfg.hint_controls then return end
    local party = get_party()
    if #party == 0 then return end
    if coop.active then -- v0.9.153: player 2's one control
        local nxt = cfg.coop_p2_switch and cfg.pad_l1_l3_possess and state.active and R.next_pawn_only(party) or nil
        local take = nxt and R.combo_name(R.take_mask())
        if take then R.hint = "Player 2   " .. take .. ":  Control " .. tostring(nxt.name) end
        return
    end
    local pad = (R.last_dev or (pad_device_ok and "pad" or "kbm")) == "pad"
    local parts = {}
    local take = pad and (cfg.pad_l1_l3_possess and R.combo_name(R.take_mask()) or nil) or (cfg.keys.toggle_possess ~= 0 and R.key_label("toggle_possess") or nil)
    if state.active then
        if pad then
            local nxt = R.next_pawn(party)
            if take and nxt then parts[#parts + 1] = take .. ":  Control " .. (nxt == "arisen" and "Arisen" or tostring(nxt.name)) end
            local back = (tonumber(cfg.pad.back) or 0) ~= 0 and R.combo_name(cfg.pad.back) or (cfg.pad_hold_select and "Hold D-pad down" or nil)
            if back and nxt ~= "arisen" then parts[#parts + 1] = back .. ":  Control Arisen" end
        else
            local to = (R.sel_kind == "pawn" and R.sel_name) or "Arisen"
            if take then parts[#parts + 1] = take .. ":  Control " .. tostring(to) end
            if cfg.keys.cycle_pawn ~= 0 and #party > 1 then parts[#parts + 1] = R.key_label("cycle_pawn") .. ":  Select" end
        end
    else
        local sel = party[1]
        for _, e in ipairs(party) do if e.idx == cfg.selected_pawn_idx then sel = e end end
        if take then parts[#parts + 1] = take .. ":  Control " .. tostring(sel.name) end
        if #party > 1 then
            if pad then if cfg.pad_hold_select then parts[#parts + 1] = "Hold D-pad left / right:  Select" end
            elseif cfg.keys.cycle_pawn ~= 0 then parts[#parts + 1] = R.key_label("cycle_pawn") .. ":  Select" end
        end
    end
    if #parts > 0 then R.hint = table.concat(parts, "      ") end
end
-- v0.9.96 / 0.9.97 controller D-pad hold. R.dpad_dir: the one D-pad direction held with no shoulder button or trigger.
R.dpad_dir = function(b)
    local pv = coop_pad_values()
    local mods = (pv.LTrigTop or 0) | (pv.LTrigBottom or 0) | (pv.RTrigTop or 0) | (pv.RTrigBottom or 0)
    if (b & mods) ~= 0 then return nil end
    local dir, n = nil, 0
    if (b & (pv.LUp or 0x1)) ~= 0 then dir, n = "up", n + 1 end
    if (b & (pv.LDown or 0x2)) ~= 0 then dir, n = "down", n + 1 end
    if (b & (pv.LLeft or 0x4)) ~= 0 then dir, n = "left", n + 1 end
    if (b & (pv.LRight or 0x8)) ~= 0 then dir, n = "right", n + 1 end
    if n ~= 1 then return nil end
    -- v0.9.98: the mod owns left and right always, down only while a pawn is played (so the game's own hold on
    -- To Me = High Five still works as the Arisen), and never up (Go / hold = Explore stay the game's)
    if dir == "up" or (dir == "down" and not state.active) then return nil end
    return dir
end
-- v0.9.97 a hold must not give the pawn order, a tap must. The game turns the D-pad into an order in
-- app.PawnOrderController (tryGetOrderInput -> tryUpdatePawnOrder(order)). While a D-pad direction is held on the
-- controller, tryUpdatePawnOrder is skipped and the order kept; the tick above gives it on release if the hold
-- time was not reached, and drops it if the hold fired. The pad is read live in the hook (the mod's own poll can
-- be a frame behind on the press). Orders from the keyboard pass untouched.
-- v0.9.110 the Magick Archer's lock-on ring (GuiManager.MagicBowReticle, app.ui020804) is drawn for the Arisen's
-- skills even while a pawn is played (reported: the ring popped up when the Arisen fired a skill). After its update, switch its drawing off while a pawn is played
-- (not co-op: there player 1 is the Arisen and needs it).
R.ring_hook = function()
    if R.ring_hooked then return end
    R.ring_hooked = true
    local td = sdk.find_type_definition("app.ui020804")
    local m = td and td:get_method("update")
    if not m then return end
    sdk.hook(m, function(args)
        thread.get_hook_storage().dpc_ring = args[2]
    end, function(retval)
        if state.active and not coop.active and cfg.hide_arisen_ring ~= false then
            pcall(function()
                local u = sdk.to_managed_object(thread.get_hook_storage().dpc_ring)
                local go = u and u:call("get_GameObject")
                if go and go:call("get_DrawSelf") == true then
                    go:call("set_DrawSelf", false)
                    R.ring_hides = (R.ring_hides or 0) + 1
                    R.ring_off = true
                end
            end)
        elseif R.ring_off then
            -- v0.9.120: back as the Arisen, the ring is switched on again (it was only ever switched off before;
            -- whether the game turned it back on by itself was never checked)
            R.ring_off = false
            pcall(function()
                local u = sdk.to_managed_object(thread.get_hook_storage().dpc_ring)
                local go = u and u:call("get_GameObject")
                if go and go:call("get_DrawSelf") == false then
                    go:call("set_DrawSelf", true)
                    log_msg("Magick bow ring: shown again for the Arisen")
                end
            end)
        end
        return retval
    end)
end
R.order_hook = function()
    if R.order_hooked then return end
    R.order_hooked = true
    local td = sdk.find_type_definition("app.PawnOrderController")
    local m = td and td:get_method("tryUpdatePawnOrder(app.PawnOrderController.PawnOrder)")
    if not m then log_msg("Order hook: tryUpdatePawnOrder not found; D-pad holds will also give the order"); return end
    sdk.hook(m, function(args)
        local skip = false
        pcall(function()
            if R.ord_bypass or coop.active or not cfg.pad_hold_select then return end
            local order = sdk.to_int64(args[3]) & 0xFFFFFFFF
            if order == 0 then return end
            -- v0.9.98: the game can give the order on RELEASE (its own hold timing); after a hold that did the
            -- mod's action, swallow that too (reported: after the hold took control, the pawn still got the Go order; the hold must swallow it)
            if R.dh and R.dh.fired then R.ord_block_raw = true end
            if R.ord_block_raw then
                -- stays shut until the D-pad is physically released, then 0.4 s more
                local raw = 0
                local gs = sdk.get_native_singleton("via.hid.GamePad")
                local gt = sdk.find_type_definition("via.hid.GamePad")
                local pad = gs and gt and sdk.call_native_func(gs, gt, "get_MergedDevice")
                if pad then raw = pad:call("get_Button") or 0 end
                local pv = coop_pad_values()
                if (raw & ((pv.LUp or 0x1) | (pv.LDown or 0x2) | (pv.LLeft or 0x4) | (pv.LRight or 0x8))) == 0 then
                    R.ord_block_raw = false
                    R.ord_block_until = os.clock() + 0.4
                end
            end
            if R.ord_block_raw or os.clock() < (R.ord_block_until or 0) then
                R.ord_skips = (R.ord_skips or 0) + 1
                skip = true
                return
            end
            local b = 0
            local gs = sdk.get_native_singleton("via.hid.GamePad")
            local gt = sdk.find_type_definition("via.hid.GamePad")
            local pad = gs and gt and sdk.call_native_func(gs, gt, "get_MergedDevice")
            if pad then b = pad:call("get_Button") or 0 end
            if not R.dpad_dir(b) then return end
            local dh = R.dh
            if dh then
                if not dh.fired and not dh.order then dh.order, dh.pc = order, sdk.to_managed_object(args[2]) end
            else
                R.dh = { order = order, pc = sdk.to_managed_object(args[2]) }
            end
            R.ord_skips = (R.ord_skips or 0) + 1
            skip = true
        end)
        thread.get_hook_storage().dpc_skip = skip
        if skip then return sdk.PreHookResult.SKIP_ORIGINAL end
    end, function(retval)
        if thread.get_hook_storage().dpc_skip then return sdk.to_ptr(0) end
        return retval
    end)
end
R.takeover_rec = function()
    local tk = R.tk
    if not (R.dev and tk and state.active and state.pawn_chara) then return end
    local now = os.clock()
    if now < tk.next then return end
    tk.next = now + 0.1
    local e = { t = math.floor((now - tk.t0) * 100) / 100, stick = math.floor((state.last_stick_mag or 0) * 100) / 100 }
    pcall(function()
        local ch = state.pawn_chara
        local p = ch:call("get_GameObject"):call("get_Transform"):call("get_Position")
        e.x, e.y, e.z = math.floor(p.x * 100) / 100, math.floor(p.y * 100) / 100, math.floor(p.z * 100) / 100
        if tk.px then e.moved = math.floor(math.sqrt((p.x - tk.px) ^ 2 + (p.z - tk.pz) ^ 2) * 100) / 100 end
        tk.px, tk.pz = p.x, p.z
        local n0, n1 = node_names(ch)
        e.node = n0 .. " | " .. n1
        local dm = ch:call("get_AIDecisionMaker"):call("get_DecisionModule")
        local d = dm:call("get_DecisionExecutor"):call("get_ExecutingDecision")
        if d then
            e.decision = d:get_type_definition():get_full_name()
            pcall(function() e.decision = e.decision .. " " .. tostring(d:call("ToString")) end)
        end
        local con = sdk.get_managed_singleton("app.PawnManager"):call("get_PawnConcierge")
        if con then
            local cc = con:call("get_ConciergeCharacter")
            local cs = con:get_field("CurrentState")
            e.guide = (con:call("get_IsConcierge") == true and "on" or "off") .. (cc and same_obj(cc, ch) and " me " or " other ")
                .. tostring(cs and cs:get_type_definition():get_name())
        end
        local nav = ch:call("get_NavigationController")
        if nav then e.nav_move_t = math.floor((nav:get_field("_ConciergeMoveTime") or 0) * 100) / 100 end
        local nai = state.pawn_obj and state.pawn_obj:call("get_CachedNavigationAI")
        if nai then e.navi = tostring(nai:call("get_IsNaviNow")) .. " " .. tostring(nai:call("get_CurrentMoveType")) .. " " .. tostring(nai:get_field("NaviAIState")) end
        e.order = state.pawn_obj and state.pawn_obj:call("get_ActiveOrder")
        local bb = ch:call("get_AIBlackBoardController")
        local rm = bb and bb:call("get_ReqMainActInterPackData")
        if rm then e.pack = tostring(rm:call("get_Path")) end
    end)
    pcall(function()
        local c = R.move_cmd(state.pawn_chara)
        if c then e.cmd = tostring(c.name) .. " ex" .. tostring(c.ex_state) .. " ce" .. tostring(c.ce_state) end
        local nav = state.pawn_chara:call("get_NavigationController")
        if nav then e.navctl = tostring(nav:get_field("_CurrentState")) .. " idle " .. tostring(nav:call("get_IsRequestIdle")) end
    end)
    e.ai_ends, e.guide_stops, e.guide_forced, e.navi_stops, e.move_stops = R.ai_ends, R.guide_stops, R.guide_forced, R.navi_stops, R.move_stops
    tk.log[#tk.log + 1] = e
    if now - tk.t0 >= 15.0 then
        R.dump("DPC_takeover.json", { version = VERSION, pawn = tostring(state.pawn_name), log = tk.log }, 1)
        R.tk = nil
    end
end
-- v0.9.119, reported (Fighter pawn climbing on a Griffin): while climbing, the R1 / R2 buttons change for many vocations; the hints still showed Launchboard while the pawn was stabbing. While a
-- character clings to a monster the game turns most skill buttons into the climbing attacks and greys those
-- skills out on its skill list. Our hook on ui010201.isDisableCustomSkill (2d above) answered "never greyed"
-- during a possession, so the list kept advertising skills that were not there. The game's own answer is now
-- let through while the played pawn is on a monster (Character.IsClimbOnCharacter, read 10 x a second).
R.cling_watch = function()
    if not (state.active and state.pawn_chara) then
        if R.cling then R.cling, R.cling_grey = false, nil end
        return
    end
    local now = os.clock()
    if now < (R.cling_next or 0) then return end
    R.cling_next = now + 0.1
    local on = call(state.pawn_chara, "get_IsClimbOnCharacter") == true
    if on ~= (R.cling == true) then
        if on then
            R.cling_grey = 0
            log_msg("Climbing on a monster: the game's own greying of the skill list is shown")
        else
            log_msg(string.format("Off the monster (the game greyed a skill %d times while on it)", R.cling_grey or 0))
        end
        R.cling = on
    end
end

-- v0.9.131, reported: on take-over the pawn finished running to wherever it had been heading before it could be controlled; a jump did not break it out. Recording of that take-over
-- (DPC_takeover.json, 0.9.130): no AI decision running, not the quest guide, yet he ran on for 7.3 s with the
-- stick at rest, and NavigationAI.IsNaviNow was true the whole time (it went false once while the stick was
-- pushed, then true again). So it is the pawn's path-following itself (catching up with the party), which
-- neither the decision interrupt (0.9.72) nor the guide stop (0.9.93) touches. While a pawn is played its
-- NavigationAI is told to stop whenever it is navigating (app.NavigationAI.setNavigationStop, checked 10 x a
-- second; switch: possess_stop_navi).
R.navi_stop = function()
    if cfg.possess_stop_navi == false or not state.pawn_obj then return end
    local now = os.clock()
    if now < (R.navi_next or 0) then return end
    R.navi_next = now + 0.1
    local ok, err = pcall(function()
        local nai = state.pawn_obj:call("get_CachedNavigationAI")
        if nai and nai:call("get_IsNaviNow") == true then
            nai:call("setNavigationStop")
            R.navi_stops = (R.navi_stops or 0) + 1
            if now >= (R.navi_log_t or 0) then
                R.navi_log_t = now + 5.0
                log_msg(string.format("Stopped %s's path-following (%d so far)", tostring(state.pawn_name), R.navi_stops))
            end
        end
    end)
    if not ok then dev_error("navi stop", err) end
end

-- v0.9.132, reported on 0.9.131: the pawn still ran on. The 0.9.131 recording: the path-following was
-- stopped once at take-over and IsNaviNow stayed false, yet he ran on for about 6 s with the stick at rest. Type
-- index (dd2-modkit index, game dump of 2026-11-16) plus bridge probe nav2: a pawn's movement is a command of its
-- action executor (Character.AIDecisionMaker.DecisionModule.ActionInterface.Executor, an app.actinter.Executor;
-- its _CommandExecutor._PrimaryCommand was app.actinter.cmd.move.Approach on all three pawns while they followed).
-- Ending the decision (0.9.72) does not end that command; it runs until the pawn arrives. While a pawn is played,
-- a running command from app.actinter.cmd.move.* is ended with Executor.forceEndAction(), checked 10 x a second
-- (switch: possess_stop_move). Left alone for 8 s after this mod gave that same pawn a skill pack (packs can
-- start with an approach of their own).
R.move_cmd = function(chara)
    local dm = chara:call("get_AIDecisionMaker"):call("get_DecisionModule")
    local ai = dm and dm:call("get_ActionInterface")
    local ex = ai and ai:call("get_Executor")
    local ce = ex and ex:get_field("_CommandExecutor")
    if not ce then return nil end
    local p = ce:get_field("_PrimaryCommand")
    return { ex = ex, name = p and p:get_type_definition():get_full_name() or nil,
             ex_state = ex:get_field("_State"), ce_state = ce:call("get__State"), running = ce:call("get_IsExecute") == true }
end
R.move_stop = function()
    if cfg.possess_stop_move == false or not state.pawn_chara then R.move_addr = nil; return end
    local now = os.clock()
    if now < (R.move_next or 0) then return end
    R.move_next = now + 0.1
    local ok, err = pcall(function()
        if quick.last_addr and quick.last_addr == state.pawn_chara:get_address() and now - (quick.last_t or 0) < 8.0 then return end
        -- v0.9.162, reported: a pawn taken over while she was set on climbing a Cyclops kept at it, and it felt like
        -- having no control. A take-over recording of the same evening shows the pawn's own command
        -- (app.actinter.cmd.job02.TriadShot) still running 5.8 s into the possession. Only move.* commands were
        -- ended (0.9.132); jumping onto a monster is app.actinter.cmd.JumpGrab, outside that group. Now: for the
        -- first 1.5 s after a take-over ANY running command of the pawn is ended, and after that the move group
        -- and JumpGrab as before.
        local addr = state.pawn_chara:get_address()
        if addr ~= R.move_addr then R.move_addr, R.move_take_until = addr, now + 1.5 end
        local c = R.move_cmd(state.pawn_chara)
        if not (c and c.running and c.name) then return end
        local taking = now < (R.move_take_until or 0)
        if not (taking or c.name:find("app.actinter.cmd.move.", 1, true) == 1 or c.name == "app.actinter.cmd.JumpGrab") then return end
        c.ex:call("forceEndAction")
        R.move_stops = (R.move_stops or 0) + 1
        if taking or now >= (R.move_log_t or 0) then
            if not taking then R.move_log_t = now + 5.0 end
            log_msg(string.format("Ended %s's command %s%s (%d so far)", tostring(state.pawn_name),
                c.name:gsub("^app%.actinter%.cmd%.", ""), taking and " at take-over" or "", R.move_stops))
        end
    end)
    if not ok then dev_error("move stop", err) end
end

-- v0.9.137 dev only, reported (playing an Archer pawn against a Cyclops): when the Cyclops was knocked down, the camera was pulled away from the played pawn. Nothing was logged: the camera's target object stayed the
-- pawn (no re-attach in the trace), so the game moved the camera another way. While a pawn is played, 10 x a second:
-- the main camera controller's control type, whether it is the player camera, and how far the camera is from the
-- pawn; a log line and a brain event on every change of the first two, and when the distance jumps past 25 m.
R.cam_watch = function()
    if not (R.dev and state.active and state.pawn_chara) then R.camw = nil; return end
    local now = os.clock()
    local w = R.camw or { next = 0 }
    R.camw = w
    if now < w.next then return end
    w.next = now + 0.1
    local ok, err = pcall(function()
        local mcc = sdk.get_managed_singleton("app.CameraManager"):call("getMainCameraController", 0)
        local ct = mcc:call("get_CurrentControlType")
        if type(ct) == "userdata" then ct = ct:get_field("value__") end
        local plc = mcc:call("get_CurrentPlayerCamera")
        local far = nil
        local cam = sdk.get_primary_camera()
        if cam then
            local cp = cam:call("get_GameObject"):call("get_Transform"):call("get_Position")
            local pp = state.pawn_chara:call("get_GameObject"):call("get_Transform"):call("get_Position")
            far = math.sqrt((cp.x - pp.x) ^ 2 + (cp.y - pp.y) ^ 2 + (cp.z - pp.z) ^ 2)
        end
        local is_far = far ~= nil and far > 25.0
        if ct ~= w.ct or plc ~= w.plc or is_far ~= (w.is_far or false) then
            if not R.cam_ct_names then
                R.cam_ct_names = {}
                local td = sdk.find_type_definition("app.CameraDefine.ControlType")
                if td then for _, f in ipairs(td:get_fields()) do if f:is_static() then R.cam_ct_names[f:get_data(nil)] = f:get_name() end end end
            end
            local tgt = mcc:call("get_TargetObject")
            local s = string.format("Camera: %s (%s) -> %s (%s), player camera %s, %.1f m from %s, target %s",
                tostring(R.cam_ct_names[w.ct] or w.ct), tostring(w.ct), tostring(R.cam_ct_names[ct] or ct), tostring(ct),
                tostring(plc), far or -1, tostring(state.pawn_name), tostring(tgt and tgt:call("get_Name")))
            if w.ct ~= nil then log_msg(s); brain_event(s) end
            w.ct, w.plc, w.is_far = ct, plc, is_far
        end
    end)
    if not ok then dev_error("camera watch", err) end
end

R.ai_watch = function()
    R.takeover_rec()
    R.cling_watch()
    R.cam_watch()
    if state.active and not R.aim_hooked then R.aim_install() end -- 0.9.143: the camera-switch hook is needed for every pawn
    if not (cfg.possess_interrupt_ai and state.active and state.pawn_chara) then return end
    R.navi_stop()
    R.move_stop()
    local now = os.clock()
    if now < (R.ai_watch_next or 0) then return end
    R.ai_watch_next = now + 0.25
    R.guide_stop(state.pawn_chara, state.pawn_name)
    R.interrupt_ai(state.pawn_chara, state.pawn_name, false)
end
-- v0.9.77 quick-use items for the pawn being played. The game's D-pad item shortcut (GuiManager.CrossGuide,
-- app.ui020401: ShortcutActs = RecoverHpItem 39, RecoverStaminaItem 40, ItemMenu, Lantern; ShortcutParam picks the
-- item) reads the Arisen's input and uses the item on the Arisen. While a pawn is possessed the player's buttons go
-- to the pawn, so nothing happened. Now: the RecoverHpItem / RecoverStaminaItem press in the player's input (in
-- co-op: player 2's D-pad down / up) asks the game's own picker for the item and uses it on the pawn
-- (ItemManager.useItem), from the Arisen's bag first, else the pawn's own.
-- v0.9.92: the pawn being played keeps its lantern in step with the Arisen's. The other pawns copy his on their
-- own (their AI does it); the played pawn's AI is held off, so it stayed dark / lit. Once a second: if the two
-- differ, set the pawn's Human.LanternCtrl directly (lighting only when the pawn has a usable lantern).
R.lantern_sync = function()
    if not (cfg.pawn_quick_lantern and state.active and state.pawn_chara and state.arisen_chara) then return end
    local now = os.clock()
    if now < (R.lantern_next or 0) then return end
    R.lantern_next = now + 1.0
    local ok, err = pcall(function()
        local al = state.arisen_chara:call("get_Human"):call("get_LanternCtrl")
        local pl = state.pawn_chara:call("get_Human"):call("get_LanternCtrl")
        if not (al and pl) then return end
        local want = al:call("get_IsLanternOn") == true
        if (pl:call("get_IsLanternOn") == true) == want then return end
        if want and not (pl:call("hasEnableLantern") and pl:call("isEnableTurnOn")) then
            R.lantern_note = "pawn cannot light (no usable lantern, or not allowed now)"
            return
        end
        if want then pl:call("turnOnByOwnerAction") else pl:call("turnOffByOwnerAction") end
        if (pl:call("get_IsLanternOn") == true) ~= want then pl:call("turn(System.Boolean)", want) end
        R.lantern_syncs = (R.lantern_syncs or 0) + 1
        R.lantern_note = string.format("pawn lantern -> %s (%s)", want and "on" or "off", (pl:call("get_IsLanternOn") == true) and "on" or "off")
        log_msg("Lantern: " .. R.lantern_note)
    end)
    if not ok then dev_error("lantern sync", err) end
end
-- v0.9.148 the labels on the quick-item cross (app.ui020401, "Salubrious Draught x1"). The game fills them from the
-- Arisen's bag whoever is played (read live: the count comes from ItemManager.getHaveNum for the Arisen's
-- CharacterID; the widget's PlChara is already the played pawn and makes no difference). 0.9.142 made a press use the
-- played pawn's own item first, so the cross named one item and the press used another. Now the label says what the
-- press will use: twice a second the pawn's bag is searched in the game's own list order (the search item_tick
-- does), and where the pawn holds an item, the text the game is about to write on that slot is replaced by
-- "<item name> x<the pawn's count>" (the game's own format, read live) in a pre-hook on KeyItem.setMessage. The
-- game writes these labels every frame while the cross is open, so nothing has to be restored. A slot the pawn
-- has nothing for keeps the game's label (the Arisen's item, which is what the press falls back to).
R.cross = { own = {} }
R.cross_scan = function(now)
    local C = R.cross
    if now < (C.next or 0) then return end
    C.next = now + 0.5
    local ok, err = pcall(function()
        local gm = sdk.get_managed_singleton("app.GuiManager")
        local cg = gm and gm:get_field("CrossGuide")
        local sp = cg and cg:get_field("ShortcutParam")
        local im = sdk.get_managed_singleton("app.ItemManager")
        if not (sp and im) then C.own = {}; return end
        C.widget = cg
        C.name_m = C.name_m or sdk.find_type_definition("app.GUIBase"):get_method("getItemName(System.Int32)")
        for _, kind in ipairs({ "hp", "stamina" }) do
            local id, n
            local list = sp:get_field(kind == "hp" and "RecoverHPItems" or "RecoverStaminaItems")
            for i = 0, list:call("get_Length") - 1 do
                local e = list:call("Get", i)
                local iid = e
                if type(e) == "userdata" then iid = e:get_field("value__") end
                if type(iid) == "number" then
                    local have = im:call("getHaveNum(System.Int32, app.Character)", iid, state.pawn_chara) or 0
                    if have > 0 then id, n = iid, have; break end
                end
            end
            local o = C.own[kind]
            if not id then C.own[kind] = nil
            elseif not o or o.id ~= id or o.n ~= n then
                local text = tostring(C.name_m:call(nil, id)) .. " x" .. tostring(n)
                local str = sdk.create_managed_string(text)
                if str then C.own[kind] = { id = id, n = n, text = text, str = str:add_ref() } end
            end
        end
    end)
    if not ok then C.own = {}; dev_error("quick item labels", err) end
end
R.cross_hook = function()
    if R.cross.hooked ~= nil then return end
    R.cross.hooked = false
    local ok, err = pcall(function()
        local m = sdk.find_type_definition("app.ui020401.KeyItem"):get_method("setMessage(System.String, System.Boolean)")
        if not m then error("KeyItem.setMessage not found") end
        local act_hp, act_st = 39, 40 -- app.CharacterInput.Action RecoverHpItem / RecoverStaminaItem (the keys' Action field, read live)
        sdk.hook(m, function(args)
            local C = R.cross
            if not (state.active and not coop.active and cfg.pawn_quick_item and cfg.pawn_quick_item_labels and C.widget) then return end
            if not (C.own.hp or C.own.stamina) then return end
            pcall(function()
                if C.widget:get_field("IsShift") ~= true then return end
                local k = sdk.to_managed_object(args[2])
                local act = k and k:get_field("Action")
                local o = (act == act_hp and C.own.hp) or (act == act_st and C.own.stamina) or nil
                if not o then return end
                args[3] = sdk.to_ptr(o.str:get_address())
                if k:get_field("IsEnable") == false then k:set_field("IsEnable", true) end
                C.swaps = (C.swaps or 0) + 1
            end)
        end, function(r) return r end)
        R.cross.hooked = true
        log_msg("Quick-item cross: labels follow the played pawn's bag (hook installed)")
    end)
    if not ok then dev_error("quick item label hook", err) end
end
R.item_tick = function()
    R.lantern_sync()
    if not (cfg.pawn_quick_item and state.active and state.pawn_chara and state.arisen_chara) then return end
    local now = os.clock()
    if cfg.pawn_quick_item_labels and not coop.active then R.cross_hook(); R.cross_scan(now) end
    local kind
    if coop.active then
        local pv = coop_pad_values()
        local dn, up = pv.LDown or 0x2, pv.LUp or 0x1
        local trg = (pad_buttons or 0) & ~(pad_prev or 0)
        -- v0.9.78: the game's own layout (the tester's screenshot of the shortcut cross): up = health item,
        -- down = stamina item (left = items menu, right = lantern; those two stay the Arisen's)
        if (trg & up) ~= 0 then kind = "hp" elseif (trg & dn) ~= 0 then kind = "stamina"
        elseif (trg & (pv.LRight or 0x8)) ~= 0 then kind = "lantern" end
    else
        local trg = state.last_trg_flags or 0
        if (trg & (ACTION_FLAGS.RecoverHpItem or 0)) ~= 0 then kind = "hp"
        elseif (trg & (ACTION_FLAGS.RecoverStaminaItem or 0)) ~= 0 then kind = "stamina"
        elseif (trg & (ACTION_FLAGS.Lantern or 0)) ~= 0 then kind = "lantern" end
    end
    if not kind or now < (R.item_next or 0) then return end
    R.item_next = now + 0.6
    if kind == "lantern" then
        -- v0.9.79: the lantern shortcut works the pawn's own lantern (Human.LanternCtrl, the same on / off calls
        -- the owner's action makes). Requested: left and right should work the possessed pawn's own lantern.
        -- v0.9.80: it works the ARISEN's lantern. Wanted: the lantern stays the Arisen's, since all pawns follow his; the pawn's own controller did not light in 0.9.79.
        if not cfg.pawn_quick_lantern then return end
        local okl, errl = pcall(function()
            local lc = state.arisen_chara:call("get_Human"):call("get_LanternCtrl")
            if not lc then error("the Arisen has no lantern controller") end
            local was = lc:call("get_IsLanternOn") == true
            if was then lc:call("turnOffByOwnerAction")
            elseif lc:call("isTurnOnCondition") or (lc:call("hasEnableLantern") and lc:call("isEnableTurnOn")) then lc:call("turnOnByOwnerAction")
            else log_msg("Quick lantern: the Arisen cannot light one now (none equipped, no oil, or not allowed here)"); return end
            if (lc:call("get_IsLanternOn") == true) == was then lc:call("turn(System.Boolean)", not was) end
            log_msg(string.format("Quick lantern: Arisen %s -> %s", was and "on" or "off", (lc:call("get_IsLanternOn") == true) and "on" or "off"))
        end)
        if not okl then dev_error("quick lantern", errl) end
        return
    end
    local ok, err = pcall(function()
        local gm = sdk.get_managed_singleton("app.GuiManager")
        local cg = gm and gm:get_field("CrossGuide")
        local sp = cg and cg:get_field("ShortcutParam")
        if not sp then error("no shortcut parameter") end
        local st = sp:get_field("CurrApplyShortcutSettingType") or 0
        local r
        if kind == "hp" then r = sp:call("getRecoverHPItemID(System.Boolean, app.ItemShortcutSettingType)", false, st)
        else r = sp:call("getRecoverStaminaItemID(app.ItemShortcutSettingType)", st) end
        local id
        if type(r) == "number" then id = r
        elseif r ~= nil then
            local okh, has = pcall(r.get_field, r, "_HasValue")
            local okv, v = pcall(r.get_field, r, "_Value")
            if not okh or has == nil then okh, has = pcall(function() return r:read_byte(0) ~= 0 end) end
            if not okv or type(v) ~= "number" then okv, v = pcall(r.read_dword, r, 4) end
            if okh and has and okv and type(v) == "number" then id = v end
        end
        local im = sdk.get_managed_singleton("app.ItemManager")
        -- v0.9.142: the game's picker only looks in the Arisen's bag (read live: the played pawn held a Ripened
        -- Harspud and two Mighty Roborants, the Arisen no stamina item, picker: nothing). The played pawn's own bag
        -- is looked through first, in the order of the game's own list for that shortcut (ItemShortcutParameter.
        -- RecoverHPItems / RecoverStaminaItems); the picker's choice from the Arisen's bag comes second.
        local own
        pcall(function()
            local list = sp:get_field(kind == "hp" and "RecoverHPItems" or "RecoverStaminaItems")
            for i = 0, list:call("get_Length") - 1 do
                local e = list:call("Get", i)
                local iid = e
                if type(e) == "userdata" then iid = e:get_field("value__") end
                if type(iid) == "number" and (im:call("getHaveNum(System.Int32, app.Character)", iid, state.pawn_chara) or 0) > 0 then
                    own = iid
                    break
                end
            end
        end)
        if own then id = own end
        if not id or id <= 0 then
            R.item_last = kind .. ": no item"
            log_msg("Quick item (" .. kind .. "): neither " .. tostring(state.pawn_name) .. " nor the Arisen holds an item the game offers for this shortcut")
            return
        end
        local sig = "useItem(System.Int32, app.Character, app.Character)"
        -- v0.9.79: his own bag first, the Arisen's only when he has none of that item (0.9.77 took the Arisen's
        -- first; reported: the items seemed to come from the Arisen's pack)
        local used = im:call(sig, id, state.pawn_chara, state.pawn_chara)
        local from = "his own bag"
        if used ~= true then
            used = im:call(sig, id, state.arisen_chara, state.pawn_chara)
            from = "the Arisen's bag"
        end
        R.item_n = (R.item_n or 0) + 1
        R.item_last = string.format("%s: item %d %s (%s)", kind, id, used == true and "used" or "NOT used", from)
        log_msg(string.format("Quick item (%s): item %d on %s -> %s (%s)", kind, id, tostring(state.pawn_name), tostring(used), from))
    end)
    if not ok then dev_error("quick item", err) end
end
-- v0.9.75 the red screen edge / red flash / heartbeat (app.ui022401, GuiManager.ScreenEffect) report the ARISEN's
-- health, also while the camera and controls are on a possessed pawn. While possessing (not co-op, where player 1 is
-- the Arisen): isDangerHp() answers for the possessed pawn instead (below the game's own danger share,
-- GuiManager.getDangerHpRate, 0.25), and reqCritical() (the flash when the Arisen is hit hard) is skipped. The
-- Arisen's own danger shows on his overhead bar, which pulses red.
R.danger_hook = function()
    if R.danger_hooked then return end
    R.danger_hooked = true
    pcall(function()
        local td = sdk.find_type_definition("app.ui022401")
        sdk.hook(td:get_method("isDangerHp"), function(args) end, function(retval)
            if state.active and not coop.active and cfg.possess_danger_pawn and state.pawn_chara then
                local low = false
                pcall(function()
                    local hit = state.pawn_chara:call("get_Hit")
                    local hp = hit:call("get_Hp") or 0
                    local mx = hit:call("get_ReducedMaxHp")
                    if type(mx) ~= "number" or mx <= 0 then mx = hit:call("get_OriginalMaxHp") or 0 end
                    low = mx > 0 and hp > 0 and (hp / mx) < (R.danger_rate or 0.25)
                end)
                R.danger_swaps = (R.danger_swaps or 0) + 1
                return sdk.to_ptr(low and 1 or 0)
            end
            return retval
        end)
        sdk.hook(td:get_method("reqCritical"), function(args)
            if state.active and not coop.active and cfg.possess_danger_pawn then
                R.danger_skips = (R.danger_skips or 0) + 1
                return sdk.PreHookResult.SKIP_ORIGINAL
            end
        end, function(retval) return retval end)
        -- v0.9.91: the flash is asked for through GuiManager.requestCriticalEffect(); the reqCritical hook above
        -- never fired (0 skips in a session where the flash showed). Skip it at the source as well.
        local gtd = sdk.find_type_definition("app.GuiManager")
        local rm = gtd and gtd:get_method("requestCriticalEffect")
        if rm then
            sdk.hook(rm, function(args)
                if state.active and not coop.active and cfg.possess_danger_pawn then
                    R.danger_skips = (R.danger_skips or 0) + 1
                    return sdk.PreHookResult.SKIP_ORIGINAL
                end
            end, function(retval) return retval end)
        end
        local gm = sdk.get_managed_singleton("app.GuiManager")
        local r = gm and gm:call("getDangerHpRate")
        if type(r) == "number" and r > 0 and r < 1 then R.danger_rate = r end
        -- v0.9.141, reported: a large red flash still crosses the screen while a pawn is played whenever the Arisen takes damage, even far away. Counters in that session: reqCritical and requestCriticalEffect skipped 0 times,
        -- so the flash is not asked for through either (the widget keeps PlayerHpRate and an IsReqCritical flag of
        -- its own, so it most likely notices the Arisen's health drop inside its update). Two more places, each
        -- counted: the flag is cleared right before the widget's flow step, and after the widget's update the
        -- flow is put back to Wait unless the played pawn itself is low on health.
        local function ours() return state.active and not coop.active and cfg.possess_danger_pawn end
        local function pawn_low()
            local low = false
            pcall(function()
                local hit = state.pawn_chara:call("get_Hit")
                local hp = hit:call("get_Hp") or 0
                local mx = hit:call("get_ReducedMaxHp")
                if type(mx) ~= "number" or mx <= 0 then mx = hit:call("get_OriginalMaxHp") or 0 end
                low = mx > 0 and hp > 0 and (hp / mx) < (R.danger_rate or 0.25)
            end)
            return low
        end
        local uf = td:get_method("updateFlow")
        if uf then
            sdk.hook(uf, function(args)
                if not ours() then return end
                pcall(function()
                    local w = sdk.to_managed_object(args[2])
                    if w and w:get_field("IsReqCritical") == true then
                        w:set_field("IsReqCritical", false)
                        R.danger_flag_clears = (R.danger_flag_clears or 0) + 1
                    end
                end)
            end, function(retval) return retval end)
        end
        local up = td:get_method("update")
        if up then
            sdk.hook(up, function(args)
                local mine = ours()
                thread.get_hook_storage().w = mine and sdk.to_managed_object(args[2]) or nil
                -- v0.9.158: the flash came back (a Cyclops slammed the Arisen while a pawn was played) with every
                -- counter above at 0. Read a minute later: the widget's flow at Wait, IsReqCritical false, but its
                -- PnlCritical panel visible with play state "FADE_IN". So update() plays the panel itself, with no
                -- request and no flow change; the only thing it has to go by is the player's health against the
                -- PlayerHpRate it kept from the frame before. Two measures, both counted:
                -- (a) before update(), the kept rate is set to 0, so the Arisen's health never reads as a drop;
                -- (b) after update(), the panel is hidden unless the played pawn itself is low on health, and shown
                --     again when it is, when the pawn is released or co-op starts.
                -- v0.9.160: measure (a) is removed. A kept rate of 0 made the widget treat the player as dying.
                -- v0.9.161: measure (b) never shows the panel again itself. Showing it on release was the red
                -- screen after going back to the Arisen: read live, the panel rests in play state "DEFAULT", and
                -- DEFAULT while visible is solid red. The panel is only ever hidden here (when the game has shown
                -- it during possession and the played pawn is not low); the game shows it itself when it flashes.
            end, function(retval)
                local w = thread.get_hook_storage().w
                if w and ours() and state.pawn_chara then
                    pcall(function()
                        if w:get_field("IsReqCritical") == true then
                            w:set_field("IsReqCritical", false)
                            R.danger_flag_clears = (R.danger_flag_clears or 0) + 1
                        end
                        local fl = w:get_field("FlowNow")
                        local low = pawn_low()
                        if (fl == 1 or fl == 2) and not low then
                            w:call("setFlowId(app.ui022401.FlowId)", 0)
                            R.danger_flow_resets = (R.danger_flow_resets or 0) + 1
                        end
                        local pn = w:get_field("PnlCritical")
                        if pn and not low and pn:call("get_Visible") == true then
                            pn:call("set_Visible", false)
                            R.danger_hides = (R.danger_hides or 0) + 1
                        end
                    end)
                end
                return retval
            end)
        end
    end)
end
-- v0.9.161: undo the stuck red screen 0.9.158 - 0.9.160 could leave behind (panel visible in its DEFAULT state). Checked
-- once a second, whoever is played; visible + DEFAULT is never a state the game itself rests in (it is solid red).
R.danger_unstick = function()
    local now = os.clock()
    if now < (R.danger_unstick_t or 0) then return end
    R.danger_unstick_t = now + 1.0
    pcall(function()
        local gm = sdk.get_managed_singleton("app.GuiManager")
        local w = gm and gm:get_field("ScreenEffect")
        local pn = w and w:get_field("PnlCritical")
        if pn and pn:call("get_Visible") == true and tostring(pn:call("get_PlayState")) == "DEFAULT" then
            pn:call("set_Visible", false)
            R.danger_unstuck = (R.danger_unstuck or 0) + 1
            log_msg("Red screen: the flash panel was left visible in its default state; hidden again")
        end
    end)
end
R.gyro_tick = function()
    R.danger_unstick()
    if state.active and cfg.possess_danger_pawn then R.danger_hook() end
    if not (coop.active and cfg.coop_no_gyro) then return end
    if not R.gyro_hooked then
        R.gyro_hooked = true
        pcall(function()
            local m = sdk.find_type_definition("app.UserPadManager"):get_method("isMotionSensorEnable")
            sdk.hook(m, function(args) end, function(retval)
                if coop.active and cfg.coop_no_gyro then
                    R.gyro_blocked = (R.gyro_blocked or 0) + 1
                    return sdk.to_ptr(0)
                end
                return retval
            end)
        end)
    end
    pcall(function()
        local mcc = R.aim_mcc()
        local cur = mcc and field(mcc, "_CurrentCameraController")
        if cur and cur:call("get_GyroEnable") == true then
            cur:call("set_GyroEnable(System.Boolean)", false)
            R.gyro_cleared = (R.gyro_cleared or 0) + 1
        end
    end)
end
R.stam_calc = function()
    if not (coop.active and cfg.coop_stamina_bar and state.pawn_chara) then R.stam_x = nil; return end
    pcall(function()
        local sm = state.pawn_chara:call("get_StaminaManager")
        local mx = sm and sm:call("get_MaxValue") or 0
        if mx <= 0 then R.stam_x = nil; R.stam_ratio = nil; return end
        R.stam_ratio = math.max(0.0, math.min(1.0, (sm:call("get_RemainingAmount") or 0) / mx))
        R.stam_t = os.clock()
        R.stam_hp, R.stam_hp_cap = nil, nil
        pcall(function()
            local hit = state.pawn_chara:call("get_Hit")
            local omx = hit and hit:call("get_OriginalMaxHp") or 0
            if omx > 0 then
                R.stam_hp = math.max(0.0, math.min(1.0, (hit:call("get_Hp") or 0) / omx))
                local okc, cap = pcall(hit.call, hit, "get_ReducedMaxHp") -- the part of the bar that can still be healed
                if okc and type(cap) == "number" then R.stam_hp_cap = math.max(0.0, math.min(1.0, cap / omx)) end
            end
        end)
        if not cfg.coop_stamina_attach then return end
        -- v0.9.45: anchor on the Head joint, not the feet. The tester's screenshots: standing, a feet + 1.9 m anchor sat
        -- 31 px under the game's health bar; crouched in Launchboard it sat 95 px above it and 9 px right. The plate
        -- follows the head.
        local tr = state.pawn_chara:call("get_Transform")
        local okad, ad = pcall(state.pawn_chara.get_address, state.pawn_chara) -- addresses, never == on managed objects
        if okad and R.stam_joint_of ~= ad then
            R.stam_joint_of, R.stam_joint = ad, nil
            -- v0.9.47: the joint is "Head_0" (187 joints listed live; "Head" does not exist, so 0.9.45 silently used
            -- the feet fallback and nothing had changed)
            for _, jn in ipairs({ "Head_0", "Head", "Neck_1" }) do
                local okj, j = pcall(tr.call, tr, "getJointByName", jn)
                if okj and j then R.stam_joint, R.stam_joint_name = j, jn; break end
            end
        end
        local q, up
        if R.stam_joint then
            local okj, jp = pcall(R.stam_joint.call, R.stam_joint, "get_Position")
            if okj and jp then q, up = jp, (cfg.coop_stamina_head_up or 0.44) end
        end
        if not q then q, up = tr:call("get_Position"), 1.62 + (cfg.coop_stamina_head_up or 0.44) end
        local sp = draw.world_to_screen(Vector3f.new(q.x, q.y + up, q.z))
        if not sp then R.stam_x = nil; return end
        local ds = imgui.get_display_size()
        local k = ds.y / 2160.0
        local w = 252.0 * k * (cfg.coop_stamina_width or 1.0)
        R.stam_w, R.stam_h = w, math.max(2.0, 5.0 * k)
        -- v0.9.44: the game's plate and this bar are not from the same frame (reported: it lags the movement).
        -- Keep the last few projections and show the one coop_stamina_frames back (positive), or run ahead of the
        -- newest by that many frames of its last motion (negative), so the offset can be tuned by eye.
        local hist = R.stam_hist or {}
        R.stam_hist = hist
        table.insert(hist, 1, { sp.x, sp.y })
        if #hist > 5 then hist[6] = nil end
        local fr = math.floor((cfg.coop_stamina_frames or 0) + 0.5)
        local px, py = sp.x, sp.y
        if fr > 0 and hist[fr + 1] then px, py = hist[fr + 1][1], hist[fr + 1][2]
        elseif fr < 0 and hist[2] then px, py = sp.x + (sp.x - hist[2][1]) * -fr, sp.y + (sp.y - hist[2][2]) * -fr end
        R.stam_x = math.floor(px - w * 0.5 + (cfg.coop_stamina_dx or 0) * k + 0.5)
        R.stam_y = math.floor(py + (cfg.coop_stamina_dy or 0) * k + 0.5)
        R.stam_ratio = math.max(0.0, math.min(1.0, (sm:call("get_RemainingAmount") or 0) / mx))
        R.stam_t = os.clock()
    end)
end
-- v0.9.57 the Arisen's health and stamina while a pawn is possessed (normal possession). He has no plate over his
-- head and the HUD gauges show the pawn, so nothing showed how he was doing. Drawn over his head (Head_0 joint; there
-- is no game plate there to drift against), or as a fixed pair at the bottom of the HUD area when he is off screen.
R.ar_calc = function()
    R.ar_ok = false
    if not (cfg.arisen_bars and state.active and not coop.active and state.arisen_chara) then return end
    pcall(function()
        local ar = state.arisen_chara
        local hit = ar:call("get_Hit")
        local omx = hit and hit:call("get_OriginalMaxHp") or 0
        if omx <= 0 then return end
        R.ar_hp = math.max(0.0, math.min(1.0, (hit:call("get_Hp") or 0) / omx))
        R.ar_cap = nil
        local okc, cap = pcall(hit.call, hit, "get_ReducedMaxHp")
        if okc and type(cap) == "number" then R.ar_cap = math.max(0.0, math.min(1.0, cap / omx)) end
        local sm = ar:call("get_StaminaManager")
        local smx = sm and sm:call("get_MaxValue") or 0
        R.ar_st = smx > 0 and math.max(0.0, math.min(1.0, (sm:call("get_RemainingAmount") or 0) / smx)) or nil
        R.ar_sx, R.ar_sy = nil, nil
        if cfg.arisen_bars_overhead then
            local tr = ar:call("get_Transform")
            local okad, ad = pcall(ar.get_address, ar)
            if okad and R.ar_joint_of ~= ad then
                R.ar_joint_of, R.ar_joint = ad, nil
                for _, jn in ipairs({ "Head_0", "Head", "Neck_1" }) do
                    local okj, j = pcall(tr.call, tr, "getJointByName", jn)
                    if okj and j then R.ar_joint = j; break end
                end
            end
            local q, up = nil, 0.32
            if R.ar_joint then
                local okj, jp = pcall(R.ar_joint.call, R.ar_joint, "get_Position")
                if okj and jp then q = jp end
            end
            if not q then q, up = tr:call("get_Position"), 1.95 end
            local sp = draw.world_to_screen(Vector3f.new(q.x, q.y + up, q.z))
            local ds = imgui.get_display_size()
            if sp and sp.x > 60 and sp.y > 30 and sp.x < ds.x - 60 and sp.y < ds.y - 60 then R.ar_sx, R.ar_sy = sp.x, sp.y end
        end
        R.ar_t = os.clock()
        R.ar_ok = true
    end)
end
R.stam_cb_ok = pcall(re.on_pre_application_entry, "LockScene", function() R.stam_calc(); R.ar_calc(); pcall(R.ta_calc) end)
if R.dev then _G.DPC_dbg = { native = native, state = state, R = R, brain = brain, cfg = cfg, coop = coop, af = function() return ACTION_FLAGS end, save = function() save_cfg() end } end -- dev only: lets TestGuide plans read the pawn's processor
if cfg.pawn_aim_camera then pcall(R.aim_install) end -- at load, so the Arisen's own aim teaches the transitions and reticle point

local function dbg_event(kind, detail)
    if not cfg.debug_input then return end
    local log = state.input_log
    local n0, n1 = node_names(state.pawn_chara)
    log[#log + 1] = string.format("%.2f %s %s | idle=%s L0=%s L1=%s", os.clock(), kind, detail or "",
        tostring(state.pawn_chara and call(state.pawn_chara, "isIdle")), n0, n1)
    if #log > 300 then table.remove(log, 1) end
    state.input_log_dirty = true
    pcall(_G.log.info, "[DPC-dbg] " .. log[#log]) -- REFramework log is the reliable channel while tuning
end

-- While an attack is in flight, record every change of the action-tree nodes + NextComboAction so
-- the combo window can be identified from a real play session.
local function trace_attack_frames(sel)
    if not cfg.debug_input or os.clock() > (state.atk_trace_until or 0) then return end
    local n0, n1 = node_names(state.pawn_chara)
    local nxt = tostring(call(sel, "get_NextComboAction") or "")
    local key = n0 .. "|" .. n1 .. "|" .. nxt
    if key ~= state.atk_trace_last then
        state.atk_trace_last = key
        dbg_event("F", "next=" .. nxt)
    end
end

local function flush_input_log()
    if not cfg.debug_input or not state.input_log_dirty then return end
    local now = os.clock()
    if now < (state.next_input_log_flush or 0) then return end
    state.next_input_log_flush = now + 1.0
    state.input_log_dirty = false
    R.dump("DPC_input_log.json", state.input_log)
end

-- Locomotion (standing / walking / running) on the full-body layer = not mid-attack.
local function in_locomotion(chara)
    local n0 = node_names(chara)
    return n0 == "" or n0 == "?" or n0:find("^Locomotion") ~= nil
end

local function pawn_do_attack(heavy, speed_type, ax, ay, mag)
    local pawn_chara = state.pawn_chara
    local sel = pawn_chara and call(pawn_chara, "get_HumanActionSelector")
    if not (pawn_chara and sel) then return false end
    speed_type = speed_type or SPEED_IDLE

    if not call(pawn_chara, "get_IsDrawedWeapon") then
        call(sel, "requestDrawWeapon()")
    end
    if mag and mag > 0.12 then
        local move_deg = compute_camera_move_angle_deg(ax, ay)
        call(pawn_chara, "set_TargetMoveAngleDeg(System.Single)", move_deg)
        call(pawn_chara, "set_TargetFrontAngleDeg(System.Single)", move_deg)
    else
        -- Aim forward along camera yaw if standing still
        local front_deg = compute_camera_move_angle_deg(0.0, 1.0)
        call(pawn_chara, "set_TargetFrontAngleDeg(System.Single)", front_deg)
    end

    update_pawn_lockon_target()

    if heavy then
        call(sel, "requestSubNormalAttack(app.LocomotionSpeedTypeEnum)", speed_type)
        call(sel, "requestComboAction(app.LocomotionSpeedTypeEnum)", speed_type)
        state.last_action_str = "Heavy Attack"
    else
        if state.is_aiming then
            call(sel, "requestShoot()")
        end
        -- Mid-swing presses are held until the combo window opens (NextComboAction becomes non-empty),
        -- then sent as a normal attack, which the action tree turns into the next hit. Sending it outside
        -- the window restarts the chain at hit 1 (the "mash resets" bug).
        state.atk_trace_until = os.clock() + 2.0
        if (not state.is_aiming) and call(pawn_chara, "get_IsDrawedWeapon") and not in_locomotion(pawn_chara) then
            local now = os.clock()
            state.combo_buffer = { speed_type = speed_type, until_t = now + (cfg.combo_buffer_window or 0.45) }
            dbg_event("ATK", "buffered")
            state.last_action_str = "Light Attack (queued)"
            state.suppress_loco_until = math.max(state.suppress_loco_until, now + 0.35)
            return true
        end
        dbg_event("ATK", "fresh")
        call(sel, "requestNormalAttack(app.LocomotionSpeedTypeEnum)", speed_type)
        call(sel, "requestComboAction(app.LocomotionSpeedTypeEnum)", speed_type)
        state.last_action_str = state.is_aiming and "Loose Arrow (Shoot)" or "Light Attack"
    end

    state.pending_attack = {
        heavy = heavy,
        speed_type = speed_type,
        until_t = os.clock() + (cfg.attack_retry_window or 0.30),
        tries = 1,
    }
    state.suppress_loco_until = math.max(state.suppress_loco_until, os.clock() + 0.35)
    return true
end

local function pawn_do_skill_slot(slot_1_to_4, speed_type, ax, ay, mag) -- slot 1..6
    local pawn_chara = state.pawn_chara
    local pawn_human = state.pawn_human
    local sel = pawn_chara and call(pawn_chara, "get_HumanActionSelector")
    if not (pawn_chara and pawn_human and sel) then return false end
    speed_type = speed_type or SPEED_IDLE

    local job = get_job(pawn_human, pawn_chara)
    local skills = get_skills(pawn_human, job)
    state.pawn_job = job
    state.pawn_skills = skills
    local skill_id = skills[slot_1_to_4]
    dbg_event("SKILL", string.format("slot=%d id=%s", slot_1_to_4, tostring(skill_id)))
    if not skill_id or skill_id == 0 then
        state.last_action_str = string.format("Skill %d (Empty)", slot_1_to_4)
        return false
    end

    if not call(pawn_chara, "get_IsDrawedWeapon") then
        call(sel, "requestDrawWeapon()")
    end
    if mag and mag > 0.12 then
        local move_deg = compute_camera_move_angle_deg(ax, ay)
        call(pawn_chara, "set_TargetMoveAngleDeg(System.Single)", move_deg)
        call(pawn_chara, "set_TargetFrontAngleDeg(System.Single)", move_deg)
    else
        local front_deg = compute_camera_move_angle_deg(0.0, 1.0)
        call(pawn_chara, "set_TargetFrontAngleDeg(System.Single)", front_deg)
    end

    update_pawn_lockon_target()

    -- If already chanting this exact spell, pressing the skill button again releases it immediately
    local cur_sk = call(pawn_human, "get_CustomSkillState")
    if cur_sk == skill_id and cur_sk ~= 0 then
        call(sel, "requestRelease()")
        call(sel, "requestShoot()")
        state.last_action_str = string.format("Release %s!", skill_name(skill_id))
        return true
    end

    -- PawnCommander verified call: pcall(sel.call, sel, "requestCustomSkill", id, SPEED)
    pcall(sel.call, sel, "requestCustomSkill", skill_id, speed_type)
    local now = os.clock()
    state.pending_attack = nil
    state.is_sprinting = false
    state.pending_skill = {
        id = skill_id,
        slot = slot_1_to_4,
        speed_type = speed_type,
        until_t = now + (cfg.skill_retry_window or 0.60),
        tries = 1,
    }
    state.active_cast = {
        id = skill_id,
        slot = slot_1_to_4,
        start_t = now,
        released = false,
        is_ready = false,
        release_tries = 0,
        next_release_t = 0.0,
    }
    state.suppress_loco_until = math.max(state.suppress_loco_until, now + 0.45)
    state.last_action_str = string.format("Skill %d: %s", slot_1_to_4, skill_name(skill_id))
    log_msg(string.format("%s -> Skill %d: %s", state.pawn_name, slot_1_to_4, skill_name(skill_id)))
    return true
end

local function pawn_do_jump(speed_type, ax, ay, mag)
    local pawn_chara = state.pawn_chara
    local sel = pawn_chara and call(pawn_chara, "get_HumanActionSelector")
    if not (pawn_chara and sel) then return false end
    speed_type = speed_type or SPEED_IDLE

    -- If currently chanting a spell, Jump cancels the spell first
    local cur_sk = state.pawn_human and call(state.pawn_human, "get_CustomSkillState")
    if type(cur_sk) == "number" and cur_sk ~= 0 then
        call(sel, "requestEndAction()")
        local cur_sel = field(sel, "CurrentSelector")
        if cur_sel then call(cur_sel, "requestEndAction()") end
        state.active_cast = nil
        state.pending_skill = nil
    end

    if mag and mag > 0.12 then
        local move_deg = compute_camera_move_angle_deg(ax, ay)
        call(pawn_chara, "set_TargetMoveAngleDeg(System.Single)", move_deg)
        call(pawn_chara, "set_TargetFrontAngleDeg(System.Single)", move_deg)
    end
    call(sel, "requestJump(app.LocomotionSpeedTypeEnum)", speed_type)
    state.suppress_loco_until = math.max(state.suppress_loco_until, os.clock() + 0.35)
    state.last_action_str = "Jump"
    return true
end

-- Trigger Fighter Defend (Shield Guard) on/off
local function pawn_set_fighter_guard(enable, ax, ay, mag)
    local pawn_chara = state.pawn_chara
    local pawn_human = state.pawn_human
    local sel = pawn_chara and call(pawn_chara, "get_HumanActionSelector")
    if not (pawn_chara and sel) then return false end
    local job01_ctrl = pawn_human and call(pawn_human, "get_Job01ActionCtrl")

    if enable then
        if not call(pawn_chara, "get_IsDrawedWeapon") then
            call(sel, "requestDrawWeapon()")
            return true
        end
        state.is_sprinting = false
        -- Player-like guard: shield faces camera-forward, stick steers the guard-walk direction
        local front_deg = compute_camera_move_angle_deg(0.0, 1.0)
        call(pawn_chara, "set_TargetFrontAngleDeg(System.Single)", front_deg)
        if mag and mag > 0.12 then
            call(pawn_chara, "set_TargetMoveAngleDeg(System.Single)", compute_camera_move_angle_deg(ax, ay))
        end
        -- Verified via PawnDefendProbe spy of native pawn AI "Defend":
        --   SEL.requestAction("Job01_Guard", 0xFFFFFFFF) -> fans out to layer 0 + 1, engine then
        --   drops layer 0 into Locomotion.Strafe (guard-walk) while layer 1 holds Job01.Job01_Guard.
        -- Only (re)request when the upper body is not already in Job01_Guard, to avoid restarting it.
        local am = call(pawn_chara, "get_ActionManager")
        local fsm = am and field(am, "Fsm")
        local upper = fsm and call(fsm, "getCurrentNodeName(System.UInt32)", 1) or ""
        if not tostring(upper):find("Job01_Guard$") then
            call(sel, "requestAction(System.String, System.UInt32)", "Job01_Guard", 0xFFFFFFFF)
        end
        state.is_guarding = true
        state.last_action_str = "Defend (Shield Guard)"
    elseif state.is_guarding then
        state.is_guarding = false
        -- Native AI lowers the shield with Job01_GuardEnd on layer 1
        call(sel, "requestAction(System.String, System.UInt32)", "Job01_GuardEnd", 1)
        state.last_action_str = "Lower Shield"
    end
    return true
end

-- ----------------------------------------------------------------------------
-- Mode 2 & Mode 3: Direct ActionSelector & Locomotion Puppeteer
-- ----------------------------------------------------------------------------
local function update_puppeteer_controls(is_first_frame)
    local live_input = state.arisen_input
    local pawn_chara = state.pawn_chara
    local pawn_human = state.pawn_human
    if not (live_input and pawn_chara and pawn_human) then return end

    local sel = call(pawn_chara, "get_HumanActionSelector")
    if not sel then return end

    -- Keep Arisen's InputProcessor disabled every frame in Mode 2
    -- v0.8.5: keep it ENABLED. The game only writes your buttons into the Arisen's CharacterInput (which DPC
    -- mirrors onto the pawn) while his processor is enabled: with it disabled, 0 of 2,901 frames carried a click
    -- and the possessed pawn could not attack; re-enabling it each frame fixed attacks live (2026-11-10).
    -- He still can't act on your input: hooks 1a/1b skip his processor and sequence buffer unless the brain
    -- drives him with its own input.
    if cfg.control_mode == 2 and cfg.sub_disable_arisen_pip and state.arisen_pip then
        call(state.arisen_pip, "set_IsEnable(System.Boolean)", true)
    end

    -- Refresh pawn job & equipped skills cache (throttled: vocation/skills only change in menus)
    local now_r = os.clock()
    if now_r >= state.next_skill_refresh_t then
        state.next_skill_refresh_t = now_r + 0.5
        local j = get_job(pawn_human, pawn_chara)
        state.pawn_job = j
        state.pawn_skills = get_skills(pawn_human, j)
    end
    local job = state.pawn_job

    -- Read stick / WASD safely as pure Lua numbers
    local ax, ay, mag = read_safe_move_stick(live_input)
    state.last_stick_mag = mag

    -- Read UInt64 button bitmasks from live_input (populated by UserInputManager before UpdateBehavior)
    local on_flags = field(live_input, "ButtonOnFlags") or 0
    local trg_flags = field(live_input, "ButtonTriggerFlags") or 0
    local rel_flags = field(live_input, "ButtonReleaseFlags") or 0
    -- v0.8.6: while the brain runs, this object can hold the brain's buttons at this point in the frame
    -- (user report: brain on -> clicks stop reaching the pawn). Use the snapshot of your buttons the brain took
    -- just before it wrote its own, then open a new snapshot for this frame.
    if brain.on and brain.hw_snap_t and os.clock() - brain.hw_snap_t < 0.25 then
        on_flags = brain.hw_on or 0
        trg_flags = brain.hw_trg or 0
        rel_flags = brain.hw_rel or 0
    end
    brain.hw_saved, brain.hw_restored = false, false
    brain.pawn_native = (cfg.native_controls and native.pip and not native.failed) and true or false
    -- v0.8: the brain overwrites the Arisen's CharacterInput (this live_input) with its synthetic buttons after
    -- this point each frame, so the game's own edge detection compares your keys against the brain's. Rebuild the
    -- trigger/release edges from the hardware on-flags DPC saw last frame instead.
    if brain.on or brain.was_on_last then
        trg_flags = on_flags & ~brain.hw_prev_on
        rel_flags = brain.hw_prev_on & ~on_flags
    end
    brain.hw_prev_on = on_flags
    brain.was_on_last = brain.on
    -- v0.9 co-op: player 2's pawn reads the controller only (buttons through the game's pad assignment)
    -- v0.9.171: with both players on pawns and two controllers, player 1's pawn can read player 1's controller the
    -- same way (cfg.coop_any_p1_route = "pad") instead of the Arisen's game input ("game", default)
    if (coop.active or (R.cp_p1_pad and R.cp_p1_pad())) and coop.pad_input then
        local okc, c_on, c_ax, c_ay, c_mag = pcall(coop.pad_input)
        if okc then
            on_flags = c_on
            trg_flags = c_on & ~coop.prev_on
            rel_flags = coop.prev_on & ~c_on
            coop.prev_on = c_on
            ax, ay, mag = c_ax, c_ay, c_mag
            state.last_stick_mag = mag
        else
            coop.err = "pad: " .. tostring(c_on)
            dev_error("coop.pad_input", c_on)
            on_flags, trg_flags, rel_flags, ax, ay, mag = 0, 0, 0, 0.0, 0.0, 0.0
        end
    end
    state.last_on_flags = on_flags
    state.last_trg_flags = trg_flags

    -- In Mode 2, mirror raw input bitflags & float stick axes onto pawn_input using primitive methods only
    if cfg.control_mode == 2 and cfg.sub_mirror_input_flags and state.pawn_input then
        if is_first_frame then write_trace("frame1: mirror_input_flags") end
        set_field(state.pawn_input, "ButtonOnFlags", on_flags)
        set_field(state.pawn_input, "ButtonTriggerFlags", trg_flags)
        set_field(state.pawn_input, "ButtonReleaseFlags", rel_flags)
        call(state.pawn_input, "setAxisL(System.Single, System.Single)", ax, ay)
        call(state.pawn_input, "set_AxisMagnitudeL(System.Single)", mag)
    end

    -- Exact bitmask check: flag = (1 << ActionID)
    local function is_trg(act_name)
        local flag = ACTION_FLAGS[act_name]
        if not flag then return false end
        return (trg_flags & flag) ~= 0
    end

    local function is_on(act_name)
        local flag = ACTION_FLAGS[act_name]
        if not flag then return false end
        return (on_flags & flag) ~= 0
    end

    if cfg.debug_input and trg_flags ~= 0 then
        local names = {}
        for n, f in pairs(ACTION_FLAGS) do
            if (trg_flags & f) ~= 0 then names[#names + 1] = n end
        end
        table.sort(names)
        dbg_event("TRG", table.concat(names, "+"))
    end

    local ui_open = is_ui_open()
    -- Keyboard skill keys (Ctrl, 1-6) work even with the REFramework menu open (players keep it open to
    -- watch the DPC window); only mouse buttons stay gated so clicks on the menu don't attack.
    local shift_skill_mod = is_on("Shift1") or R.key_held("Shift1", 0x11) -- v0.9.124: the game's skill modifier key (default Ctrl)
    state.hud_shift_held = shift_skill_mod and true or false

    -- v0.7: number keys 1-6 (row or numpad) were DPC-puppeteer hotkeys. For the native processor, turn them
    -- into the same input the game produces for a skill press: SkillN + Shift1 + Shift2 (seen live).
    if cfg.native_controls and native.pip and not native.failed and state.pawn_input and not coop.active then
        local add_on, add_trg, add_rel = 0, 0, 0
        for n = 1, 6 do
            local f = ACTION_FLAGS["Skill" .. n]
            if f then
                -- v0.9.90: the numpad is for orders to someone else now; only the number row (when it is set to
                -- skills) still drives the possessed pawn
                local row = 0x30 + n
                if R.row_down(row) then
                    add_on = add_on | f | (ACTION_FLAGS.Shift1 or 0) | (ACTION_FLAGS.Shift2 or 0)
                end
                if R.row_pressed(row) then add_trg = add_trg | f end
                if state["native_k" .. n] and not R.row_down(row) then add_rel = add_rel | f end
                state["native_k" .. n] = R.row_down(row)
            end
        end
        if add_on ~= 0 or add_trg ~= 0 or add_rel ~= 0 then
            set_field(state.pawn_input, "ButtonOnFlags", on_flags | add_on)
            set_field(state.pawn_input, "ButtonTriggerFlags", trg_flags | add_trg)
            set_field(state.pawn_input, "ButtonReleaseFlags", rel_flags | add_rel)
        end
    end

    -- v0.9.87 / 0.9.88 aimed skills for bow vocations. While aiming the skill buttons fire the aimed versions. The
    -- game only builds those Skill flags when the ARISEN is a bow vocation (the flags the pawn receives are made for
    -- the Arisen's layout), so with any other Arisen the possessed Archer got each button's ordinary action.
    --  Controller (L2 held): Square / Triangle / Circle / Cross = skills 1 - 4; with a skill in slot 5 or 6 the
    --   chords Square + Cross and Triangle + Circle fire Skill6 / Skill5 (0.9.99; 0.9.87 had Circle + Cross), and a lone chord button waits
    --   0.09 s for its partner (a shorter tap still fires on release).
    -- Always SkillN without Shift1 / Shift2, and without the button's own action.
    if cfg.pawn_aim_skills and cfg.native_controls and native.pip and not native.failed and state.pawn_input
       and not coop.active and (state.pawn_job == 2 or state.pawn_job == 8) then
        local now = os.clock()
        local A = R.as or { t = {}, out = {}, prev = 0 }
        R.as = A
        local pv = coop_pad_values()
        -- v0.9.124: the aim button is the one the game has AimHold on (default R1; it was fixed to L2, the tester's remap)
        local btn = pad_buttons or 0
        local pad_aim = R.bind_held("AimHold", btn, pv.RTrigTop or 0x400)
        local sq, tri, ci, cr = pv.RLeft or 0x40, pv.RUp or 0x10, pv.RRight or 0x80, pv.RDown or 0x20
        -- 0.9.100: slot -> button from the game's assignment. Only face buttons count under L2: a slot the game
        -- has on R1 / R2 stays a shot while aiming and is used with L1 as usual.
        local bp = R.bind and R.bind.pad or {}
        local facemask = sq | tri | ci | cr
        local faces = { sq, tri, cr, ci } -- fallback = the game's default slots 1 - 4 (0.9.124; was Circle before Cross)
        if next(bp) then
            for n = 1, 4 do
                local b = bp[n]
                faces[n] = (b and (b & ~facemask) == 0 and b ~= 0) and b or 0
            end
        end
        local six = state.pawn_skills and ((state.pawn_skills[5] or 0) ~= 0 or (state.pawn_skills[6] or 0) ~= 0)
        local want, strip = 0, 0
        if pad_aim or A.prev ~= 0 or A.latch then
            pcall(coop_ensure_map)
            local function own_flags(b)
                local f = 0
                for _, e in ipairs(coop.map or {}) do
                    if e.pad == b and not tostring(e.name):find("^Skill") then f = f | (e.flag or 0) end
                end
                return f
            end
            if A.latch and (btn & A.latch.pads) == 0 then A.latch = nil end
            if pad_aim and six and not A.latch then
                for _, c in ipairs({ { bp[6] or (sq | cr), "Skill6" }, { bp[5] or (tri | ci), "Skill5" } }) do -- 0.9.100: from the game's assignment
                    if (btn & c[1]) == c[1] and ACTION_FLAGS[c[2]] then A.latch = { pads = c[1], flag = ACTION_FLAGS[c[2]] }; break end
                end
            end
            for n, b in ipairs(faces) do
                local down = b ~= 0 and (btn & b) ~= 0
                if down and pad_aim then
                    strip = strip | own_flags(b)
                    if not A.t[b] then A.t[b], A.out[b] = now, false end
                    if A.latch and (A.latch.pads & b) ~= 0 then
                        A.out[b] = true -- part of a chord: never also a single skill
                    elseif not (six and now - A.t[b] < 0.09) then
                        want = want | (ACTION_FLAGS["Skill" .. n] or 0)
                        A.out[b] = true
                    end
                else
                    if A.t[b] and not A.out[b] and not A.latch then A.pulse_f, A.pulse_until = ACTION_FLAGS["Skill" .. n] or 0, now + 0.10 end
                    A.t[b], A.out[b] = nil, nil
                end
            end
            if A.latch and pad_aim then want = want | A.latch.flag end
            if A.pulse_until and now < A.pulse_until then want = want | (A.pulse_f or 0) end
        end
        -- v0.9.89: the 0.9.88 keyboard path (numpad keys while aiming) is gone. Clarified: number-pad skills are orders for a character that is not being played, so they are never the aimed versions. Which keys fire
        -- aimed skills on keyboard is still to be settled.
        local kb_strip = 0
        local trg_s, rel_s = want & ~A.prev, A.prev & ~want
        A.prev = want
        if want ~= 0 or trg_s ~= 0 or rel_s ~= 0 or strip ~= 0 then
            local on0 = field(state.pawn_input, "ButtonOnFlags") or 0
            local trg0 = field(state.pawn_input, "ButtonTriggerFlags") or 0
            local rel0 = field(state.pawn_input, "ButtonReleaseFlags") or 0
            set_field(state.pawn_input, "ButtonOnFlags", ((on0 & ~strip) & ~kb_strip) | want)
            set_field(state.pawn_input, "ButtonTriggerFlags", ((trg0 & ~strip) & ~kb_strip) | trg_s)
            set_field(state.pawn_input, "ButtonReleaseFlags", rel0 | rel_s)
            if trg_s ~= 0 then R.aim_skill_n = (R.aim_skill_n or 0) + 1 end
        end
    end

    -- v0.9.167 bow skills used from the hip. Measured on 0.9.166 (archer-chord-1, Archer pawn, skill-shift chords): a
    -- skill started while the aim button was held always fired; started from the hip it began (Prepare node) and the
    -- game cancelled it: Whirling Arrow went to Job02_AimCancel after 1.2 s, Full Blast to CrouchShotCancel after 0.4 s.
    -- For the player the game keeps a hip skill's aim up by itself; the pawn's input processor does not. So while the
    -- played Archer is in a skill's Prepare / Ready / charge stage, the aim flags are held for him, as if the aim
    -- button were down, until the skill leaves that stage. (The Arisen brain fires its bow skills the same way.)
    -- 0.9.172-dev18: also in co-op (reported: player 2's Archer "almost fires Spiral Arrow then aborts it, unless I
    -- also hold R1"; the block skipped co-op), and for player 2's / players 3+'s extra played pawns (R.s2_pre).
    if cfg.pawn_hip_skill_aim and cfg.native_controls and native.pip and not native.failed and state.pawn_input
       and state.pawn_job == 2 and state.pawn_chara then
        R.hip_aim_hold(state.pawn_input, state.pawn_chara, R.hip_main)
    end

    -- v0.9.26 the possessed pawn gathers and loots by himself. The game's Gather / Loot prompt is computed for the
    -- player character only (InteractManager.HighestPriorityObjectForPlayer). Verified live 2026-11-15 on a corpse:
    -- addActiveInteract(pawn, InteractPoint{object, 0}) + executeInteract(pawn) makes the pawn loot it and the
    -- item goes to the pawn's inventory. (requestInteractFromAI is not acted on while his AI is suspended.)
    -- Scan 5x a second for the nearest interactive object within pawn_interact_range; DPC draws the prompt; the
    -- game's own Interact button then triggers it, and that press is kept away from the pawn (it is also dash).
    if cfg.pawn_interact and state.pawn_input and state.pawn_chara then
        local now = os.clock()
        if now >= (R.int_next or 0) then
            R.int_next = now + 0.2
            local best, bd, bn, bdead = nil, nil, nil, false
            local okscan, errscan = pcall(function()
                local im = sdk.get_managed_singleton("app.InteractManager")
                if not im then return end
                local px, py, pz = brain_pos(state.pawn_chara)
                if not px then return end
                local skip = {}
                skip[state.pawn_chara:get_GameObject():get_address()] = true
                if state.arisen_chara then skip[state.arisen_chara:get_GameObject():get_address()] = true end
                for _, e in ipairs(get_party()) do skip[e.chara:get_GameObject():get_address()] = true end
                local range = cfg.pawn_interact_range or 2.2
                for _, slot in ipairs(im:get_field("InteractiveObjects"):get_field("_entries"):get_elements()) do
                    local oks, o = pcall(slot.get_field, slot, "Value")
                    if not (oks and o) then oks, o = pcall(slot.get_field, slot, "value") end
                    if oks and o then
                        pcall(function()
                            local go = o:get_field("<Owner>k__BackingField")
                            if not go or skip[go:get_address()] then return end
                            local q = go:call("get_Transform"):call("get_Position")
                            local d = math.sqrt((q.x - px) ^ 2 + (q.y - py) ^ 2 + (q.z - pz) ^ 2)
                            if d > range or (bd and d >= bd) then return end
                            -- a character counts only when dead (a corpse to loot): no talking, no live enemies
                            local ch = go:call("getComponent(System.Type)", sdk.typeof("app.Character"))
                            local dead = false
                            if ch then
                                if ch:call("get_IsDead") ~= true then return end
                                dead = true
                                -- v0.9.109: a dead PERSON who is not an enemy (an NPC) is a Wakestone revive, not
                                -- loot. Forced from the pawn it played the revive with no "use a Wakestone?"
                                -- menu (the tester, 2026-11-16). That choice stays with the Arisen. Monsters and
                                -- human enemies (ids ch2...) are still looted.
                                if not cfg.pawn_interact_dead_people then
                                    local id = tostring(ch:call("get_CharaIDString") or "")
                                    local human = false
                                    pcall(function() human = ch:call("get_Human") ~= nil end)
                                    if human and not id:find("^ch2") then
                                        R.int_skipped_people = (R.int_skipped_people or 0) + 1
                                        return
                                    end
                                end
                            end
                            if (o:call("get_NumInteractPoints") or 0) < 1 then return end
                            -- v0.9.58 CRASH FIX: only object families the pawn has been seen to use safely. Forcing
                            -- the interact on gm52_029 (a vocation guild counter, meant to open a menu for the
                            -- player) crashed the game 21 ms later (c0000005, 2026-11-15). gm80_* = chests
                            -- and gather points, gm82_* = pickups and dropped items; anything else is left alone.
                            local nm = tostring(go:call("get_Name"))
                            if not dead and not (nm:find("^gm80_") or nm:find("^gm82_")) then return end
                            -- 0.9.172-dev38 (the tester): no prompt on riftstones (the game's "Rim"); a played pawn can't use them
                            if not dead and (nm:find("[Rr]im") or go:call("getComponent(System.Type)", sdk.typeof("app.InteractRimStone"))) then
                                R.int_rift_skips = (R.int_rift_skips or 0) + 1
                                return
                            end
                            best, bd, bn, bdead = o, d, nm, dead
                            R.int_scan_pos = { q.x, q.y, q.z }
                        end)
                    end
                end
            end)
            if not okscan and not R.int_err then R.int_err = true; dev_error("pawn interact scan", errscan) end
            R.int_obj, R.int_name, R.int_dead, R.int_dist = best, bn, bdead, bd
            R.int_pos = best and R.int_scan_pos or nil
            R.int_item = bn ~= nil and bn:find("^gm82_000") ~= nil
            -- v0.9.63 wake a sleeping companion. Requested: a possessed pawn can wake a sleeping pawn or the Arisen. A party member or the Arisen within range with the Sleep status (flag 4) takes the prompt.
            -- Done by curing the status directly (StatusConditionCtrl.reqStatusConditionCure), not through the
            -- game's rescue interact, after the forced-interact crash of 0.9.57.
            R.int_wake, R.int_wake_name = nil, nil
            if cfg.pawn_wake then
                pcall(function()
                    local px, py, pz = brain_pos(state.pawn_chara)
                    if not px then return end
                    local me = state.pawn_chara:get_address()
                    local list = {}
                    if state.arisen_chara then list[#list + 1] = { chara = state.arisen_chara, name = "the Arisen" } end
                    for _, e in ipairs(get_party()) do list[#list + 1] = e end
                    local wd
                    for _, e in ipairs(list) do
                        if e.chara:get_address() ~= me then
                            local sc = e.chara:call("get_StatusConditionCtrl")
                            local fl = sc and sc:call("get_ActiveStatusConditionFlagProp")
                            -- v0.9.68: a downed party pawn (not the Arisen) can be revived the same way
                            local down = cfg.pawn_revive and e.name ~= "the Arisen" and e.chara:call("get_IsDead") == true
                            if down or (type(fl) == "number" and (fl & 4) ~= 0) then
                                local x, y, z = brain_pos(e.chara)
                                local d = x and math.sqrt((x - px) ^ 2 + (y - py) ^ 2 + (z - pz) ^ 2)
                                if d and d <= (cfg.pawn_interact_range or 2.2) + 0.6 and (not wd or d < wd) then
                                    wd = d
                                    R.int_wake, R.int_wake_name = e.chara, tostring(e.name)
                                    R.int_wake_kind = down and "Revive" or "Wake"
                                    R.int_pos = { x, y + 0.4, z }
                                    R.int_obj = nil
                                end
                            end
                        end
                    end
                end)
            end
        end
        local f = ACTION_FLAGS.Interact or 0
        local strip = f | (ACTION_FLAGS.Dash or 0) | (ACTION_FLAGS.Sprint or 0)
        local on = field(state.pawn_input, "ButtonOnFlags") or 0
        local trg = field(state.pawn_input, "ButtonTriggerFlags") or 0
        if coop.active then f = ACTION_FLAGS.Dash or f end -- co-op: player 2's Triangle arrives as Dash (no Interact flag)
        -- v0.9.69: reviving needs the button held, like the Arisen's own revive; a ring fills while it is held
        -- (drawn with the prompt). Letting go, or the target changing, starts over. Waking stays a single press.
        local fire = (trg & f) ~= 0
        if R.int_wake and R.int_wake_kind == "Revive" and f ~= 0 and (cfg.pawn_revive_hold or 0) > 0 then
            fire = false
            local ad = R.int_wake:get_address()
            if (on & f) ~= 0 and now >= (R.int_cool or 0) then
                if R.rev_of ~= ad then R.rev_of, R.rev_t0 = ad, now end
                R.int_hold = true
                R.rev_prog = math.min(1.0, (now - R.rev_t0) / cfg.pawn_revive_hold)
                if R.rev_prog >= 1.0 then fire = true; R.rev_of, R.rev_prog = nil, nil end
            else
                R.rev_of, R.rev_prog = nil, nil
            end
        else
            R.rev_of, R.rev_prog = nil, nil
        end
        if R.int_wake and f ~= 0 and fire and now >= (R.int_cool or 0) then
            R.int_cool = now + 1.0
            R.int_hold = true
            R.wake_n = (R.wake_n or 0) + 1
            local okw, errw = pcall(function()
                if R.int_wake_kind == "Revive" then
                    -- Found live on a downed pawn (2026-11-15): PawnManager.getPartyPawn(chara) gives the app.Pawn,
                    -- setPawnRevive(hp, false, false) stands him up with that many health points (0.5 gave 0.5 hp),
                    -- so ask for half of his current maximum and set it again in case the first value is ignored.
                    local pm = sdk.get_managed_singleton("app.PawnManager")
                    local pw = pm and pm:call("getPartyPawn(app.Character, System.Boolean)", R.int_wake, false)
                    if not pw then error("no app.Pawn for the downed character") end
                    local hit = R.int_wake:call("get_Hit")
                    local mx = hit:call("get_ReducedMaxHp")
                    if type(mx) ~= "number" or mx <= 0 then mx = hit:call("get_OriginalMaxHp") or 100 end
                    local hp = mx * (cfg.pawn_revive_health or 0.5)
                    pw:call("setPawnRevive(System.Single, System.Boolean, System.Boolean)", hp, false, false)
                    if (hit:call("get_Hp") or 0) < hp * 0.9 then hit:call("setHpValue(System.Single, System.Boolean)", hp, false) end
                    return
                end
                local sc = R.int_wake:call("get_StatusConditionCtrl")
                -- the second press (if the first did not wake him) uses the flag overload instead
                if R.wake_n % 2 == 1 then
                    sc:call("reqStatusConditionCure(app.StatusConditionDef.StatusConditionEnum, System.Boolean)", 2, true)
                else
                    sc:call("reqStatusConditionCure(app.StatusConditionDef.StatusConditionFlag)", 4)
                end
            end)
            if okw and R.int_wake_kind == "Revive" then log_msg(string.format("%s: revived %s", tostring(state.pawn_name), tostring(R.int_wake_name)))
            elseif okw then log_msg(string.format("%s: woke %s (%s)", tostring(state.pawn_name), tostring(R.int_wake_name), (R.wake_n % 2 == 1) and "enum" or "flag"))
            else dev_error("pawn wake", errw) end
            R.int_wake = nil
            R.int_next = now + 0.6
        elseif R.int_obj and f ~= 0 and (trg & f) ~= 0 and now >= (R.int_cool or 0) then
            R.int_cool = now + 1.0
            R.int_hold = true
            local obj = R.int_obj
            local okx, errx = pcall(function()
                local im = sdk.get_managed_singleton("app.InteractManager")
                if im:call("isInteracting(app.Character)", state.pawn_chara) then
                    -- v0.9.29: an interact that never finished (seen with a dropped item) blocked every later press
                    if now - (R.int_last_t or 0) < 3.0 then return end
                    im:call("endInteract(app.Character)", state.pawn_chara)
                end
                R.int_last_t = now
                local pt = sdk.create_instance("app.InteractManager.InteractPoint"):add_ref()
                pt:set_field("Object", obj)
                pt:set_field("PointNo", 0)
                im:call("addActiveInteract(app.Character, app.InteractManager.InteractPoint)", state.pawn_chara, pt)
                im:call("executeInteract(app.Character)", state.pawn_chara)
                if R.int_item then
                    -- v0.9.29 dropped items (gm82_000_*): execute alone does nothing (item still there, pawn left
                    -- "interacting"); the object's Start handler is what takes it (bridge test 2026-11-15).
                    obj:get_field("StartInteractHandler"):call("Invoke", 0, state.pawn_chara)
                end
            end)
            R.int_n = (R.int_n or 0) + 1
            if okx then log_msg(string.format("%s: %s %s", tostring(state.pawn_name), R.int_dead and "looted" or "used", tostring(R.int_name)))
            else dev_error("pawn interact", errx) end
            R.int_obj = nil
            R.int_next = now + 0.6
        end
        if R.int_hold then
            if f == 0 or (on & f) == 0 then R.int_hold = false
            else
                set_field(state.pawn_input, "ButtonOnFlags", on & ~strip)
                set_field(state.pawn_input, "ButtonTriggerFlags", trg & ~strip)
            end
        end
    else
        R.int_obj, R.int_wake = nil, nil
    end

    R.ai_watch() -- v0.9.88 a possessed pawn does not run off on an order
    R.item_tick() -- v0.9.77 the game's quick-use item shortcut, for the pawn being played
    R.aim_tick() -- v0.9.29 bow aim camera for the possessed Archer
    R.gyro_tick() -- v0.9.39 co-op: player 2's controller must not gyro-aim the Arisen

    -- v0.9.24 interact helper. Looting, gathering, chests and talking belong to the Arisen even while a pawn is
    -- possessed, so they only work where he stands. Out of battle, pressing Interact while he is more than
    -- interact_bring_dist away brings him to the pawn (the same warp as F8); press again to interact.
    if cfg.interact_bring and state.pawn_input and not coop.active and state.arisen_chara and state.pawn_chara then
        local f = ACTION_FLAGS.Interact or 0
        local trg = field(state.pawn_input, "ButtonTriggerFlags") or 0
        local now = os.clock()
        if f ~= 0 and (trg & f) ~= 0 and now >= (R.bring_next or 0) and not brain.in_battle() then
            local ax, _, az = brain_pos(state.arisen_chara)
            local px, _, pz = brain_pos(state.pawn_chara)
            if ax and px then
                local d = math.sqrt((ax - px) ^ 2 + (az - pz) ^ 2)
                if d > (cfg.interact_bring_dist or 2.0) then
                    R.bring_next = now + 1.5
                    R.brings = (R.brings or 0) + 1
                    log_msg(string.format("Interact: Arisen was %.1f m away -> brought to %s", d, tostring(state.pawn_name)))
                    warp_arisen_to_pawn()
                end
            end
        end
    end

    -- v0.9.21 chorded skills on the possessed pawn. TestGuide chord-flags-2: on the controller the game raises
    -- the chord flag together with the single-button flags (L1 + Square+Cross -> Skill1 + Jump + ... + Skill6;
    -- L1 + Triangle+Circle -> Skill2 + ActCancel + ... + Skill5). The Arisen does the chord skill; the possessed
    -- pawn's processor got the same flags and did the single skill (Blink Strike / Full Moon Guard). While a chord
    -- flag is on, take the single-button actions out of the pawn's input so only the chord is left (that form is
    -- what co-op sends, and it fires).
    if cfg.native_controls and native.pip and not native.failed and state.pawn_input and not coop.active then
        local chord = (ACTION_FLAGS.Skill5 or 0) | (ACTION_FLAGS.Skill6 or 0)
        local on = field(state.pawn_input, "ButtonOnFlags") or 0
        if chord ~= 0 and (on & chord) ~= 0 then
            local strip = 0
            for _, n in ipairs({ "Skill1", "Skill2", "Skill3", "Skill4", "Jump", "ActCancel", "Sheathe", "Draw", "Descent",
                                 "GimmickCancel", "Job09AstralDown", "Grab", "Interact", "Dash" }) do
                strip = strip | (ACTION_FLAGS[n] or 0)
            end
            strip = strip & ~chord
            set_field(state.pawn_input, "ButtonOnFlags", on & ~strip)
            set_field(state.pawn_input, "ButtonTriggerFlags", (field(state.pawn_input, "ButtonTriggerFlags") or 0) & ~strip)
            set_field(state.pawn_input, "ButtonReleaseFlags", (field(state.pawn_input, "ButtonReleaseFlags") or 0) & ~strip)
            R.chord_strips = (R.chord_strips or 0) + 1
        end
    end

    if native.pip and (field(state.pawn_input, "ButtonOnFlags") or 0) ~= 0 then
        native.mirror_input_frames = native.mirror_input_frames + 1
    end
    -- v0.7: the game's own player controls drive the pawn; skip the hand-built puppeteer below.
    if native_tick() then
        state.last_action_str = "Native controls"
        return
    end

    -- Check whether a given skill slot (1..4) is currently held down by the player
    local function is_skill_slot_held(slot)
        if slot == 1 and (is_on("Skill1") or (shift_skill_mod and is_on("AttackS")) or ((R.row_down(0x31) or is_key_down_safe(0x61)))) then return true end
        if slot == 2 and (is_on("Skill2") or (shift_skill_mod and is_on("AttackL")) or ((R.row_down(0x32) or is_key_down_safe(0x62)))) then return true end
        if slot == 3 and (is_on("Skill3") or (shift_skill_mod and is_on("Jump"))    or ((R.row_down(0x33) or is_key_down_safe(0x63)))) then return true end
        if slot == 4 and (is_on("Skill4") or (shift_skill_mod and (is_on("Grab") or is_on("Interact") or is_on("ActCancel") or is_on("Dash"))) or ((R.row_down(0x34) or is_key_down_safe(0x64)))) then return true end
        if slot == 5 and (is_on("Skill5") or ((R.row_down(0x35) or is_key_down_safe(0x65)))) then return true end
        if slot == 6 and (is_on("Skill6") or ((R.row_down(0x36) or is_key_down_safe(0x66)))) then return true end
        return false
    end

    -- Fix Issue 4: Full-Speed Sprinting (app.LocomotionSpeedTypeEnum: Idle=0, Walk=1, Run=2, Dash=3)
    -- Sprint latches when Dash / KeepDash / Left Shift is pressed while moving, and clears when stopping
    local is_strafe = (state.is_guarding or state.is_aiming)
    local dash_pressed = (not shift_skill_mod) and (is_trg("Dash") or is_on("Dash") or is_on("KeepDash") or R.key_held("Dash", 0x10))
    if mag > 0.20 and dash_pressed and not is_strafe then
        state.is_sprinting = true
    elseif mag <= 0.15 or is_strafe then
        state.is_sprinting = false
    end

    local is_dash = state.is_sprinting and not is_strafe
    local speed_type = SPEED_IDLE
    if mag > 0.12 then
        if is_dash then
            speed_type = SPEED_DASH -- 3 = Full Sprint!
        elseif mag > 0.50 then
            speed_type = SPEED_RUN  -- 2 = Normal Run
        else
            speed_type = SPEED_WALK -- 1 = Walk
        end
    end

    local now = os.clock()
    local cur_sk = call(pawn_human, "get_CustomSkillState") or 0
    local in_skill = (type(cur_sk) == "number" and cur_sk ~= 0)

    if cfg.sub_puppeteer_combat or cfg.native_controls then -- native fallback (Thief / errors) always needs it
        -- 0a. Process pending skill retry window (PawnCommander pattern: ensures skill fires after weapon draw)
        if state.pending_skill then
            local ps = state.pending_skill
            if cur_sk == ps.id and cur_sk ~= 0 then
                state.pending_skill = nil
            elseif now > ps.until_t then
                state.pending_skill = nil
            else
                pcall(sel.call, sel, "requestCustomSkill", ps.id, ps.speed_type)
                ps.tries = ps.tries + 1
            end
        end

        -- 0b. Fix Issue 3: Process Active Spell / Chanting Completion (Mage, Sorcerer, Magick Archer, etc.)
        if in_skill then
            if not state.active_cast or state.active_cast.id ~= cur_sk then
                -- Find which equipped slot this skill lives in (was hard-coded to slot 1)
                local slot = 1
                for s = 1, 6 do
                    if state.pawn_skills and state.pawn_skills[s] == cur_sk then slot = s break end
                end
                state.active_cast = {
                    id = cur_sk,
                    slot = slot,
                    start_t = now,
                    released = false,
                    is_ready = false,
                    release_tries = 0,
                    next_release_t = 0.0,
                }
            end
            local cast = state.active_cast
            update_pawn_lockon_target()

            -- Check if CurrentSelector reports the spell chant is ready to release
            local cur_sel = field(sel, "CurrentSelector")
            local ready_flag = false
            if cur_sel then
                local ok_r, r_val = pcall(cur_sel.call, cur_sel, "isReadySpellAction")
                if ok_r and r_val == true then
                    ready_flag = true
                end
            end
            cast.is_ready = ready_flag

            -- Mage / Sorcerer Quickspell while chanting (hold JobSpecialAction / Left Trigger / Right Click)
            if (job == 3 or job == 6) and is_on("JobSpecialAction") then
                call(sel, "requestAction(System.String, System.UInt32)", "Concentrate", 0)
                call(sel, "setAction(System.String, System.Boolean, System.UInt32)", "Concentrate", true, 0)
                state.is_quickspelling = true
            elseif state.is_quickspelling then
                state.is_quickspelling = false
                call(sel, "setAction(System.String, System.Boolean, System.UInt32)", "Concentrate", false, 0)
            end

            -- Release rules (v0.6.0: fire ONCE, with up to 3 spaced retries, never every frame):
            --   * Spell jobs (Mage/Sorcerer): release when the chant reports ready and the player isn't
            --     holding the slot to store it (AttackS fires a stored spell). Fallback after
            --     cfg.spell_release_fallback seconds if isReadySpellAction never reports ready.
            --   * Other jobs (charge skills): release when the player lets go of the slot button (>0.35 s).
            local holding_slot = is_skill_slot_held(cast.slot)
            local elapsed = now - cast.start_t
            local is_spell_job = (job == 3 or job == 6)
            local want_release
            if is_spell_job then
                want_release = (ready_flag and (not holding_slot or is_trg("AttackS")))
                    or (not holding_slot and elapsed > (cfg.spell_release_fallback or 2.5))
            else
                want_release = (elapsed > 0.35 and not holding_slot)
            end
            local can_retry = (not cast.released) or (cast.release_tries < 4 and now >= cast.next_release_t)
            if want_release and can_retry then
                call(sel, "requestRelease()")
                call(sel, "requestShoot()")
                cast.released = true
                cast.release_tries = cast.release_tries + 1
                cast.next_release_t = now + 0.4
                state.last_action_str = string.format("Casting %s", skill_name(cur_sk))
            elseif cast.released then
                state.last_action_str = string.format("Casting %s", skill_name(cur_sk))
            elseif ready_flag and holding_slot then
                state.last_action_str = string.format("Spell Ready (Holding): %s", skill_name(cur_sk))
            else
                state.last_action_str = string.format("Chanting%s: %s",
                    state.is_quickspelling and " (Quickspell)" or "", skill_name(cur_sk))
            end
        else
            state.active_cast = nil
            state.is_quickspelling = false
        end

        -- 0b2. Combo buffer: fire the queued light attack once the combo window opens
        trace_attack_frames(sel)
        if state.combo_buffer then
            local cb = state.combo_buffer
            local nxt = call(sel, "get_NextComboAction")
            local window_open = type(nxt) == "string" and nxt ~= ""
            if window_open or now > cb.until_t or in_locomotion(pawn_chara) then
                state.combo_buffer = nil
                dbg_event("ATK", window_open and ("fire(window " .. nxt .. ")") or (now > cb.until_t and "fire(timeout)" or "fire(locomotion)"))
                call(sel, "requestNormalAttack(app.LocomotionSpeedTypeEnum)", cb.speed_type)
                call(sel, "requestComboAction(app.LocomotionSpeedTypeEnum)", cb.speed_type)
                -- Same as a direct press: keep locomotion requests from overriding the attack this frame
                state.suppress_loco_until = math.max(state.suppress_loco_until, now + 0.35)
                return
            end
        end

        -- 0c. Process pending attack retry window (ensures attack fires if triggered while weapon was sheathed)
        if state.pending_attack then
            local pa = state.pending_attack
            if now > pa.until_t or not in_locomotion(pawn_chara) then
                state.pending_attack = nil
            elseif call(pawn_chara, "get_IsDrawedWeapon") then
                if pa.heavy then
                    call(sel, "requestSubNormalAttack(app.LocomotionSpeedTypeEnum)", pa.speed_type)
                else
                    call(sel, "requestNormalAttack(app.LocomotionSpeedTypeEnum)", pa.speed_type)
                end
                pa.tries = pa.tries + 1
            end
        end

        -- 1. Check Custom Skills (Skill1..Skill4, Shift1 + Face Buttons, or Keyboard 1..4 / Numpad 1..4)
        local skill_slot_triggered = nil

        if is_trg("Skill1") then skill_slot_triggered = 1
        elseif is_trg("Skill2") then skill_slot_triggered = 2
        elseif is_trg("Skill3") then skill_slot_triggered = 3
        elseif is_trg("Skill4") then skill_slot_triggered = 4
        elseif is_trg("Skill5") then skill_slot_triggered = 5
        elseif is_trg("Skill6") then skill_slot_triggered = 6
        elseif shift_skill_mod then
            if is_trg("AttackS") then skill_slot_triggered = 1
            elseif is_trg("AttackL") then skill_slot_triggered = 2
            elseif is_trg("Jump") then skill_slot_triggered = 3
            elseif is_trg("Grab") or is_trg("Interact") or is_trg("ActCancel") or is_trg("Dash") then skill_slot_triggered = 4
            end
        end

        -- Direct keyboard number row 1-4 (0x31..0x34) & Numpad 1-4 (0x61..0x64) skill hotkeys
        if cfg.debug_input then
            for vk = 0x31, 0x36 do
                local d = is_key_down_safe(vk)
                if d and not state["dbg_k" .. vk] then dbg_event("KEY", tostring(vk - 0x30) .. " ui_open=" .. tostring(ui_open)) end
                state["dbg_k" .. vk] = d
            end
        end
        if not skill_slot_triggered then
            if R.row_pressed(0x31) or key_pressed(0x61) then skill_slot_triggered = 1
            elseif R.row_pressed(0x32) or key_pressed(0x62) then skill_slot_triggered = 2
            elseif R.row_pressed(0x33) or key_pressed(0x63) then skill_slot_triggered = 3
            elseif R.row_pressed(0x34) or key_pressed(0x64) then skill_slot_triggered = 4
            elseif R.row_pressed(0x35) or key_pressed(0x65) then skill_slot_triggered = 5
            elseif R.row_pressed(0x36) or key_pressed(0x66) then skill_slot_triggered = 6
            end
        end

        if skill_slot_triggered then
            if state.is_guarding then
                pawn_set_fighter_guard(false, ax, ay, mag)
            end
            pawn_do_skill_slot(skill_slot_triggered, speed_type, ax, ay, mag)
            return
        end

        -- In Mode 2 (ActionSelector Puppeteer), handle Vocation Action (Defend/Aim/Dodge), Jump, Attacks, Draw/Sheathe
        if cfg.control_mode == 2 then
            -- 2. Fix Issue 2: Vocation Action (Defend / Aim / Quickspell / Dodge)
            local rmb_down = (not ui_open) and R.key_held("JobSpecialAction", 0x02) -- v0.9.124: the game's vocation action key
            local rmb_trg = (not ui_open) and key_pressed(0x02)
            local pad_lt_down = R.bind_held("JobSpecialAction", pad_buttons or 0, 0x0400) -- v0.9.124: the game's vocation action button (default R1; was fixed to L2)
            local voc_on = is_on("JobSpecialAction") or is_on("AimHold") or is_on("Shift1OnlySpecificJob") or rmb_down or pad_lt_down
            local voc_trg = is_trg("JobSpecialAction") or is_trg("AimHold") or is_trg("Shift1OnlySpecificJob") or rmb_trg

            if job == 1 then
                -- Fighter: Hold JobSpecialAction / RMB / LT to Defend (Shield Guard)
                local guard_down = voc_on and not shift_skill_mod
                if guard_down and not in_skill then
                    pawn_set_fighter_guard(true, ax, ay, mag)
                elseif state.is_guarding and not guard_down then
                    pawn_set_fighter_guard(false, ax, ay, mag)
                end
            elseif job == 2 or job == 8 then
                -- Archer / Magick Archer: Hold JobSpecialAction / AimHold to Aim Bow
                if voc_on and not in_skill then
                    if not call(pawn_chara, "get_IsDrawedWeapon") then
                        call(sel, "requestDrawWeapon()")
                    end
                    local aim_deg = compute_camera_move_angle_deg(0.0, 1.0)
                    call(pawn_chara, "set_TargetFrontAngleDeg(System.Single)", aim_deg)
                    -- v0.9.126: a requestAimAction(app.LocomotionSpeedTypeEnum) call was removed here. The real
                    -- method takes no arguments, so that signature never matched and the call never ran: the
                    -- aim the pawn does enter (Job02_StartAim) comes from the mirrored AimHold input.
                    state.is_aiming = true
                    state.last_action_str = "Aiming Bow"
                elseif state.is_aiming and not voc_on then
                    state.is_aiming = false
                    call(sel, "requestEndAction()")
                end
            elseif job == 4 then
                -- Thief: Swift Step (Dodge)
                if voc_trg then
                    if mag > 0.12 then
                        local move_deg = compute_camera_move_angle_deg(ax, ay)
                        call(pawn_chara, "set_TargetMoveAngleDeg(System.Single)", move_deg)
                        call(pawn_chara, "set_TargetFrontAngleDeg(System.Single)", move_deg)
                    end
                    call(sel, "requestAction(System.String, System.UInt32)", "DodgeOfRing", 0)
                    state.suppress_loco_until = math.max(state.suppress_loco_until, now + 0.30)
                    state.last_action_str = "Swift Step"
                    return
                end
            elseif (job == 3 or job == 6) then
                -- Mage / Sorcerer: When not chanting, JobSpecialAction triggers Anodyne / Galvanize
                if voc_trg and not in_skill then
                    pawn_do_attack(true, speed_type, ax, ay, mag)
                    state.last_action_str = (job == 3) and "Anodyne" or "Galvanize"
                    return
                end
            else
                -- Warrior (Barge) & other vocations
                if voc_trg and not in_skill then
                    pawn_do_attack(true, speed_type, ax, ay, mag)
                    state.last_action_str = VOCATION_ACTION_NAMES[job] or "Vocation Action"
                    return
                end
            end

            -- 3. Jump (Action bitflag or Spacebar 0x20 when UI closed)
            if is_trg("Jump") or key_pressed(0x20) then
                if state.is_guarding then pawn_set_fighter_guard(false, ax, ay, mag) end
                pawn_do_jump(speed_type, ax, ay, mag)
                return
            end

            -- 4. Light Attack (AttackS bitflag, or optional raw LMB fallback)
            local lmb_trg = cfg.raw_mouse_fallback and (not ui_open) and key_pressed(0x01)
            if (not shift_skill_mod) and (is_trg("AttackS") or lmb_trg) then
                if state.is_guarding then pawn_set_fighter_guard(false, ax, ay, mag) end
                pawn_do_attack(false, speed_type, ax, ay, mag)
                return
            end

            -- 5. Heavy Attack (AttackL bitflag ONLY — never hijacks JobSpecialAction!)
            if (not shift_skill_mod) and is_trg("AttackL") then
                if state.is_guarding then pawn_set_fighter_guard(false, ax, ay, mag) end
                pawn_do_attack(true, speed_type, ax, ay, mag)
                return
            end

            -- 6. Draw / Sheathe / Lantern
            if is_trg("Sheathe") then
                if state.is_guarding then pawn_set_fighter_guard(false, ax, ay, mag) end
                pawn_do_sheathe(pawn_chara, sel)
                return
            elseif is_trg("Draw") then
                pawn_do_draw(pawn_chara, sel)
                return
            elseif is_trg("Lantern") then
                call(sel, "requestToggleLanternAction()")
                state.last_action_str = "Toggle Lantern"
                return
            end
        end
    end

    -- 7. Camera-Relative Locomotion
    --    Do NOT call requestLocomotionImpl during attack/skill/draw startup (suppress_loco_until),
    --    while guarding as Fighter, or while a Custom Skill is actively executing!
    if cfg.sub_puppeteer_move or cfg.native_controls then
        -- Player-like: while the full-body layer is in an attack / action node, movement input only steers
        -- (TargetMoveAngle) and never requests locomotion or idle, which would cancel the swing. The
        -- action tree returns to Locomotion on its own when the move ends.
        local in_action_startup = (now < state.suppress_loco_until) or (state.pending_skill ~= nil)
            or not in_locomotion(pawn_chara)

        if mag > 0.12 then
            local move_deg = compute_camera_move_angle_deg(ax, ay)
            state.last_move_deg = move_deg
            -- Always update target angle so attacks/skills/guard can steer toward stick direction
            call(pawn_chara, "set_TargetMoveAngleDeg(System.Single)", move_deg)

            -- Fighter Defend guard-walk (player-like): native guard puts layer 0 into Locomotion.Strafe
            -- and layer 1 into Job01.Job01_Guard. Locomotion requests only touch layer 0, so keep
            -- driving Strafe at walk speed while the shield stays up, facing camera-forward.
            if state.is_guarding and not in_skill and not in_action_startup then
                call(pawn_chara, "set_TargetFrontAngleDeg(System.Single)", compute_camera_move_angle_deg(0.0, 1.0))
                call(pawn_human, "set_IsDash(System.Boolean)", false)
                call(pawn_human, "set_IsPrevDash(System.Boolean)", false)
                safe_request_locomotion(sel, SPEED_WALK, true)
                state.was_moving = true
                state.last_action_str = "Defend (Guard Walk)"
            end

            if not in_skill and not in_action_startup and not state.is_guarding then
                if not state.is_aiming then
                    call(pawn_chara, "set_TargetFrontAngleDeg(System.Single)", move_deg)
                end

                -- Native Human & Character dash flags (Player Mirror)
                if is_dash then
                    call(pawn_human, "set_IsDash(System.Boolean)", true)
                    call(pawn_human, "set_IsPrevDash(System.Boolean)", true)
                    call(pawn_human, "notifyKeepDash")
                    call(pawn_human, "setLocomotionSpeedType(app.LocomotionSpeedTypeEnum)", SPEED_DASH)
                    call(pawn_chara, "setLocomotionSpeed(app.LocomotionSpeedTypeEnum)", SPEED_DASH)
                    call(pawn_chara, "set_DiscreteLocomotionSpeedType(app.LocomotionSpeedTypeEnum)", SPEED_DASH)
                else
                    call(pawn_human, "set_IsDash(System.Boolean)", false)
                    call(pawn_human, "set_IsPrevDash(System.Boolean)", false)
                end

                local hcac = call(pawn_human, "get_HumanCommonActionCtrl")
                if hcac then
                    call(hcac, "set_IsEnableDashToRequestedMoveSpeedOfNormalLocomotion(System.Boolean)", is_dash)
                    pcall(hcac.call, hcac, "requestMoveSpeedOfNormalLocomotion(System.Single, System.Boolean)", 1.0, is_dash)
                end

                -- Note: Second argument is is_strafe!
                -- false = NormalLocomotion (forward run/sprint), true = Strafe (combat sidestep)
                safe_request_locomotion(sel, speed_type, is_strafe)
                state.was_moving = true
                state.last_action_str = is_dash and "Sprint (Dash)" or (speed_type == SPEED_RUN and "Run" or "Walk")
            end
        elseif cfg.control_mode == 2 and state.was_moving and not in_skill and not in_action_startup and not state.is_guarding then
            state.was_moving = false
            state.is_sprinting = false
            call(pawn_human, "set_IsDash(System.Boolean)", false)
            call(pawn_human, "set_IsPrevDash(System.Boolean)", false)
            if call(sel, "isEnableRequestIdle") then
                call(sel, "requestIdleImpl(System.Boolean)", false)
            end
            state.last_action_str = "Idle"
        elseif cfg.control_mode == 2 and state.was_moving and state.is_guarding and not in_skill and not in_action_startup then
            -- Stopped while guarding: hold Strafe in place (speed Idle) so the guard-walk doesn't keep drifting
            state.was_moving = false
            call(pawn_chara, "set_TargetFrontAngleDeg(System.Single)", compute_camera_move_angle_deg(0.0, 1.0))
            safe_request_locomotion(sel, SPEED_IDLE, true)
            state.last_action_str = "Defend (Shield Guard)"
        end
    end
end

-- ----------------------------------------------------------------------------
-- Main Per-Frame Update Loop (Game Thread: UpdateBehavior)
-- ----------------------------------------------------------------------------
-- Fill the render-thread snapshot (party list for the UI, HUD values, diagnostics).
local function refresh_ui_cache()
    local now = os.clock()
    if cfg.window_open and now >= ui_cache.next_party_t then
        ui_cache.next_party_t = now + 0.5
        ui_cache.party = get_party()
        if cfg.window_open then
            local cam_mgr = sdk.get_managed_singleton("app.CameraManager")
            local mcc = cam_mgr and call(cam_mgr, "getMainCameraController", 0)
            local cam_tc = mcc and call(mcc, "get_TargetCharacter")
            ui_cache.cam_id = tostring(cam_tc and call(cam_tc, "get_CharaIDString") or "nil")
        end
    end
    if state.active and state.pawn_chara then
        ui_cache.hp = call(state.pawn_chara, "get_Hp") or 0
        ui_cache.max_hp = call(state.pawn_chara, "get_OriginalMaxHp") or 1
        ui_cache.active_sk = (state.pawn_human and call(state.pawn_human, "get_CustomSkillState")) or 0
        ui_cache.weapon_drawn = call(state.pawn_chara, "get_IsDrawedWeapon") == true
    end
end

-- ----------------------------------------------------------------------------
-- v0.8.1 Test bench: test-enemy spawner, test marks and hotkeys
-- Spawn path = EncounterDirector's waveEngine: GenerateManager.requestCreateInstance(PrefabController,
-- GenerateInfoContainer, requestID, InstanceInfo, nil, nil) once the enemy catalog's prefab is ready.
-- ----------------------------------------------------------------------------
local TEST_ENEMIES = {
    { cid = "ch220000_00", name = "Goblin" },
    { cid = "ch220000_03", name = "Goblin thrower" },
    { cid = "ch220001_10", name = "Hobgoblin" },
    { cid = "ch223000_00", name = "Wolf" },
    { cid = "ch222000_00", name = "Harpy (flying)" },
    { cid = "ch221000_00", name = "Saurian" },
    { cid = "ch226001_01", name = "Skeleton fighter" },
    { cid = "ch251000_00", name = "Ogre" },
    { cid = "ch250000_00", name = "Cyclops" },
    { cid = "ch256000_00", name = "Minotaur" },
    { cid = "ch254000_00", name = "Chimera" },
    -- v0.9.101 (ids from EncounterDirector's charRef). Added at the end so saved selections keep their meaning.
    { cid = "ch253000_00", name = "Griffin (flying, large)" },
    { cid = "ch252000_00", name = "Golem (large)" },
    { cid = "ch257000_00", name = "Drake (very large)" },
    { cid = "ch251001_00", name = "Grim Ogre" },
    { cid = "ch254001_00", name = "Gore Chimera" },
    { cid = "ch256001_00", name = "Gore Minotaur" },
    { cid = "ch220000_10", name = "Goblin (strong)" },
    { cid = "ch220002_00", name = "Chopper" },
    { cid = "ch221001_00", name = "Asp (poison)" },
    { cid = "ch221002_00", name = "Rattler" },
    { cid = "ch222003_00", name = "Succubus (flying)" },
}
local TEST_ENEMY_NAMES = {}
for i, e in ipairs(TEST_ENEMIES) do TEST_ENEMY_NAMES[i] = e.name end

-- The standard battery. "still" enemies are target dummies (_IsThinkStop): they stand there and pawns mostly
-- ignore them, so any damage is the Arisen's.
local TEST_PRESETS = {
    { label = "Dummy ahead 14m",   enemy = 1, count = 1, dist = 14.0, angle = 0,   still = true,  note = "brain: turn + shoot" },
    { label = "Dummy beside 10m",  enemy = 1, count = 1, dist = 10.0, angle = 100, still = true,  note = "brain: turn first" },
    { label = "Dummy too close 4m", enemy = 1, count = 1, dist = 4.0, angle = -30, still = true,  note = "brain: back off to 7m" },
    { label = "Dummy far 28m",     enemy = 1, count = 1, dist = 28.0, angle = 0,   still = true,  note = "brain: approach to 20m" },
    { label = "Goblin pack x3",    enemy = 1, count = 3, dist = 18.0, angle = 0,   still = false, note = "real fight" },
    { label = "Wolves x3",         enemy = 4, count = 3, dist = 20.0, angle = 0,   still = false, note = "fast movers" },
    { label = "Harpies x2",        enemy = 5, count = 2, dist = 18.0, angle = 0,   still = false, note = "airborne targets" },
    { label = "Ogre",              enemy = 8, count = 1, dist = 25.0, angle = 0,   still = false, note = "large enemy" },
    { label = "Cyclops",           enemy = 9, count = 1, dist = 28.0, angle = 0,   still = false, note = "large: climbing, weak point" },
    { label = "Cyclops dummy",     enemy = 9, count = 1, dist = 20.0, angle = 0,   still = true,  note = "large, stands still: aim / climb practice" },
    { label = "Minotaur",          enemy = 10, count = 1, dist = 28.0, angle = 0,  still = false, note = "large charger" },
    { label = "Chimera",           enemy = 11, count = 1, dist = 28.0, angle = 0,  still = false, note = "large, three heads" },
    { label = "Griffin",           enemy = 12, count = 1, dist = 30.0, angle = 0,  still = false, note = "large flyer" },
    { label = "Golem",             enemy = 13, count = 1, dist = 30.0, angle = 0,  still = false, note = "large, weak points only" },
    { label = "Drake",             enemy = 14, count = 1, dist = 35.0, angle = 0,  still = false, note = "very large (dangerous)" },
    { label = "Saurians x3",       enemy = 6, count = 3, dist = 20.0, angle = 0,   still = false, note = "medium pack" },
    { label = "Asps x2 (poison)",  enemy = 20, count = 2, dist = 18.0, angle = 0,  still = false, note = "poison: cure tests" },
    { label = "Ogre + behind you", enemy = 8, count = 1, dist = 20.0, angle = 180, still = false, note = "large enemy from behind" },
}

local spawner = { charmap = nil, mreq = nil, pending = {}, units = {}, alive = 0, spawned = 0, next_prune = 0, marks = 0 }

local function spawner_init()
    if not spawner.charmap then
        local m = {}
        local td = sdk.find_type_definition("app.CharacterID")
        for _, f in ipairs(td and td:get_fields() or {}) do
            if f:is_static() then
                local ok, v = pcall(f.get_data, f, nil)
                if ok and type(v) == "number" then m[f:get_name()] = v end
            end
        end
        spawner.charmap = m
    end
    if not spawner.mreq then
        local td = sdk.find_type_definition("app.GenerateManager")
        for _, m in ipairs(td and td:get_methods() or {}) do
            if m:get_name() == "requestCreateInstance" then
                local pt = m:get_param_types()
                if #pt == 6 and pt[1]:get_name() == "PrefabController" then spawner.mreq = m end
            end
        end
    end
    return spawner.charmap and spawner.mreq
end

local function spawner_prefab(char_id)
    local gm = sdk.get_managed_singleton("app.GenerateManager")
    local cc = gm and field(gm, "_CatalogCtrl")
    local ec = cc and field(cc, "_EnemyCatalog")
    local merged = ec and field(ec, "<MergedCatalog>k__BackingField")
    local item = merged and call(merged, "get_Item", char_id)
    return item and call(item, "get_Item")
end

local function test_mark(label)
    spawner.marks = spawner.marks + 1
    local s = string.format("=== TEST MARK %d%s ===", spawner.marks, label and (": " .. label) or "")
    log_msg(s)
    brain_event(s)
end

-- spec = { enemy = index into TEST_ENEMIES (or cid = "ch..."), count, dist, angle (deg, + = right), still,
--          around = "arisen" | "pawn" }
local function spawn_test(spec)
    if not spawner_init() then log_msg("Test spawn: GenerateManager API not found"); return false end
    local cid = spec.cid or (TEST_ENEMIES[spec.enemy or 1] or TEST_ENEMIES[1]).cid
    local char_id = spawner.charmap[cid]
    local pctrl = char_id and spawner_prefab(char_id)
    if not pctrl then log_msg("Test spawn: no prefab for " .. tostring(cid)); return false end
    local cm = sdk.get_managed_singleton("app.CharacterManager")
    local anchor = cm and call(cm, "get_ManualPlayer")
    if spec.around == "pawn" and state.active and state.pawn_chara then anchor = state.pawn_chara end
    local xf = anchor and call(anchor, "get_Transform")
    local pos = xf and call(xf, "get_Position")
    local rot = xf and call(xf, "get_Rotation")
    local wos = sdk.get_managed_singleton("app.WorldOffsetSystem")
    local gm = sdk.get_managed_singleton("app.GenerateManager")
    if not (pos and rot and wos and gm) then log_msg("Test spawn: no anchor position"); return false end
    pcall(function() pctrl:get_Item():set_Standby(true) end)
    local f = rot * Vector3f.new(0, 0, 1)
    local a = math.rad(spec.angle or 0)
    local fx, fz = f.x * math.cos(a) + f.z * math.sin(a), -f.x * math.sin(a) + f.z * math.cos(a)
    local dist, count = spec.dist or 14.0, math.max(1, math.min(8, spec.count or 1))
    for i = 1, count do
        local side = (i - (count + 1) / 2) * 2.5
        local lp = Vector3f.new(pos.x + fx * dist + fz * side, pos.y + 0.5, pos.z + fz * dist - fx * side)
        local ok, err = pcall(function()
            local up = wos:call("toUniversalPosition", lp)
            local inst = sdk.create_instance("app.InstanceInfo"):add_ref()
            local cont = inst:get_Container()
            local idw = gm:getIdWrapper(char_id)
            pcall(function() cont._CommonInfo:set_ObjectID(sdk.to_ptr(idw)) end)
            pcall(function() cont._CommonInfo._ObjectID._SelectedCharacterID = char_id end)
            cont._CommonInfo:setContextPosition(up)
            cont._CommonInfo:setContextAngle(rot)
            cont._CharaInfo._IsThinkStop = spec.still and true or false
            -- tough: can't die and is topped up when low, so pawns can't kill a test dummy (default for "still")
            local tough = spec.tough; if tough == nil then tough = spec.still and true or false end
            spawner.pending[#spawner.pending + 1] = { cid = cid, pctrl = pctrl, cont = cont, inst = inst, tough = tough,
                rid = math.random(20000, 89999), status = 1, t0 = os.clock() }
        end)
        if not ok then log_msg("Test spawn error: " .. tostring(err)) end
    end
    local s = string.format("Test spawn: %d x %s at %.0fm, %d deg%s", count, cid, dist, spec.angle or 0, spec.still and " (dummy)" or "")
    log_msg(s)
    brain_event(s)
    return true
end

local function despawn_tests()
    local n = 0
    for _, u in ipairs(spawner.units) do
        -- v0.9.15: a tough dummy that outlives its despawn (2026-11-14: the GameObject wasn't destroyed) must not
        -- stay unkillable
        pcall(function() local hit = u.chara:call("get_Hit"); if hit then hit:call("set_IsNoDie", false) end end)
        pcall(function()
            local go = u.inst:get_Instance()
            -- same guard as EncounterDirector: a dissolved corpse's GameObject may already be freed
            if go and sdk.is_managed_object(go) then
                local okV, valid = pcall(go.call, go, "get_Valid")
                if not okV or valid ~= false then go:destroy(go); n = n + 1 end
            end
        end)
    end
    spawner.units, spawner.pending, spawner.alive = {}, {}, 0
    log_msg("Despawned " .. n .. " test enemies")
end

local function spawner_tick()
    if #spawner.pending > 0 then
        local gm = sdk.get_managed_singleton("app.GenerateManager")
        for i = #spawner.pending, 1, -1 do
            local p = spawner.pending[i]
            local ok, err = pcall(function()
                if p.status == 1 then
                    if p.pctrl:get_Item():get_Ready() then
                        spawner.mreq:call(gm, p.pctrl, p.cont, p.rid, p.inst, nil, nil)
                        p.status = 4
                    end
                elseif p.status == 4 then
                    local ch = p.inst:get_Chara()
                    if ch then
                        spawner.units[#spawner.units + 1] = { inst = p.inst, chara = ch, cid = p.cid, tough = p.tough }
                        spawner.spawned = spawner.spawned + 1
                        table.remove(spawner.pending, i)
                    end
                end
            end)
            if not ok or os.clock() - p.t0 > 20 then
                log_msg("Test spawn dropped: " .. tostring(err or "timeout"))
                table.remove(spawner.pending, i)
            end
        end
    end
    for _, u in ipairs(spawner.units) do
        if u.tough then
            local ok, err = pcall(function()
                local hit = u.chara:call("get_Hit")
                if not hit then return end
                if not hit:call("get_IsNoDie") then hit:call("set_IsNoDie", true) end
                local hp, mx = hit:call("get_Hp") or 0, hit:call("get_OriginalMaxHp") or 0
                if mx > 0 and hp < mx * 0.3 then hit:call("recoverHpAndMaxHpCompletely", false) end
            end)
            if not ok and not u.tough_err then u.tough_err = true; dev_error("tough dummy", err) end
        end
    end
    local now = os.clock()
    if now >= spawner.next_prune then
        spawner.next_prune = now + 0.5
        local alive = 0
        for _, u in ipairs(spawner.units) do
            if brain_alive(u.chara) then alive = alive + 1 end
        end
        spawner.alive = alive
    end
end

-- v0.9.121 developer tool, requested: a debug key that downs a pawn (to practise the Remedy Arrow). Shift+F10,
-- the Test bench button or {"cmd":"down","idx":N} puts the selected pawn down.
-- v0.9.122: the 0.9.121 ladder (HitController.setHpValue / setHp to zero) changed the number and nothing else:
-- reported: the pawn-downer key did nothing; log: four runs, "none of the three ways". Death runs in the damage
-- path. What works (bridge test dn5, 2026-11-17, ch111011: hp 1517 -> 0, IsDead true): a HitController.DamageInfo
-- of our own handed to HitController.updateDamageHp(info, damage, false).
R.down_pawn = function(idx)
    local entry = nil
    -- 0.9.172-dev31: idx "other" = the first pawn nobody plays (coop-checks-1 asked for idx 1, which was the played
    -- pawn after the party order changed, so nobody was downed)
    if idx == "other" then
        for _, e in ipairs(get_party()) do
            if not entry and not R.held_by(e.idx) and not (state.active and state.pawn_chara and e.chara:get_address() == state.pawn_chara:get_address()) then entry = e end
        end
    end
    for _, e in ipairs(get_party()) do if e.idx == (idx or cfg.selected_pawn_idx) then entry = e end end
    if not entry then log_msg("Down a pawn: nobody selected (F7 picks a pawn)"); return false end
    if state.active and state.pawn_chara and entry.chara:get_address() == state.pawn_chara:get_address() then
        log_msg("Down a pawn: " .. entry.name .. " is the one you are playing; select another"); return false
    end
    if call(entry.chara, "get_IsDead") == true then log_msg("Down a pawn: " .. entry.name .. " is down already"); return false end
    local ok, err = pcall(function()
        local hit = entry.chara:call("get_Hit")
        local di = sdk.create_instance("app.HitController.DamageInfo")
        if not (hit and di) then error("no hit controller / damage info") end
        di = di:add_ref()
        di:set_field("Damage", 99999.0)
        di:set_field("FixedDamage", 99999.0)
        di:set_field("IsDirectDamage", true)
        di:set_field("<DamageHitController>k__BackingField", hit)
        di:set_field("<DamageOwnerHitController>k__BackingField", hit)
        hit:call("updateDamageHp(app.HitController.DamageInfo, System.Single, System.Boolean)", di, 99999.0, false)
        -- 0.9.172-dev32: the pawn was "down" (0 HP, IsDead) but stood there calmly. The game's own die handlers on
        -- the Human start the down reaction (motion, dying state), as a real fatal hit does.
        local hu = entry.chara:call("get_Human")
        if hu then
            pcall(function() hu:call("Hit_DieHandler(app.HitController.DamageInfo)", di) end)
            pcall(function() hu:call("Hit_DieReactionHandler(app.HitController.DamageInfo)", di) end)
        end
    end)
    -- 0.9.172-dev33/34: even with the die handlers the pawn counted as down (skull, red bar) but kept standing.
    -- dev33's HumanActionSelector.requestAction("DieCollapse") lost to his sit-to-stand (coop-checks-4 ended in
    -- Liv.LivManual.LivSitOnTheGroundToStand). dev34 asks the ActionManager directly at the Highest priority and
    -- walks a list (DieCollapse, DieDown, DieLoop: app.HumanActionID) until layer 0 shows a Die action.
    local node0 = ""
    pcall(function()
        local fsm = entry.chara:call("get_ActionManager"):get_field("Fsm")
        node0 = tostring(fsm:call("getCurrentNodeName(System.UInt32)", 0))
    end)
    R.down_check = { chara = entry.chara, name = entry.name, t = os.clock(), before = node0, i = 0, tried = {} }
    local dead = call(entry.chara, "get_IsDead") == true
    log_msg(string.format("Down a pawn: %s -> %s%s (action was %s)", entry.name, dead and "down" or "NOT down", ok and "" or (" (" .. tostring(err) .. ")"), node0))
    return dead
end
-- dev34: make the downed pawn's body go down. Every 0.4 s: if layer 0 isn't a Die action yet, request the next
-- name from the list at the Highest priority; log what each try led to (R.down_node, R.down_tries for tests).
R.DOWN_ACTIONS = { "DieCollapse", "DieDown", "DieLoop" }
R.down_tick = function()
    local c = R.down_check
    if not c or os.clock() < c.t then return end
    local node = ""
    pcall(function()
        local fsm = c.chara:call("get_ActionManager"):get_field("Fsm")
        node = tostring(fsm:call("getCurrentNodeName(System.UInt32)", 0))
    end)
    R.down_node = node
    if c.i > 0 then c.tried[#c.tried + 1] = R.DOWN_ACTIONS[c.i] .. "->" .. node end
    R.down_tries = table.concat(c.tried, ", ")
    if node:find("Die") or call(c.chara, "get_IsDead") ~= true or c.i >= #R.DOWN_ACTIONS then
        R.down_check = nil
        log_msg("Down a pawn: " .. c.name .. ": " .. (R.down_tries ~= "" and R.down_tries or node))
        return
    end
    c.i = c.i + 1
    pcall(function()
        c.chara:call("get_ActionManager"):call("requestActionCore(app.ActionManager.Priority, System.String, System.UInt32)", 0, R.DOWN_ACTIONS[c.i], 0)
    end)
    c.t = os.clock() + 0.4
end

-- Test hotkeys (cfg.test_hotkeys): F9 spawn the selected test, Ctrl+F9 the custom spawn (0.9.101), Shift+F9 mark,
-- F10 despawn, Ctrl+F10 down the selected pawn (0.9.121; was Shift+F10 until 0.9.127), F11 brain on/off
local function test_hotkeys()
    if not R.dev then return end
    R.down_tick()
    if not cfg.test_hotkeys then return end -- v0.9.114: never for players (F9 spawned enemies)
    local k = cfg.test_keys
    local shift = is_key_down_safe(0x10)
    if key_pressed(k.spawn) then
        if shift then test_mark("hotkey")
        elseif is_key_down_safe(0x11) then spawn_test(cfg.test_custom)
        else
            local p = TEST_PRESETS[cfg.test_preset]
            if p then
                spawn_test({ enemy = p.enemy, count = p.count, dist = p.dist, angle = p.angle, still = p.still, around = cfg.test_custom.around })
            else
                spawn_test(cfg.test_custom)
            end
        end
    end
    if key_pressed(k.despawn) then
        -- v0.9.128: Ctrl+F10, not Shift+F10. Shift+F10 is Windows' own "context menu" shortcut; after it the
        -- script side went on seeing Shift as held, and TestGuide took the next End for Shift+End (abort).
        if is_key_down_safe(0x11) then R.down_pawn() else despawn_tests() end
    end
    if key_pressed(k.toggle_brain) then
        cfg.arisen_brain = not cfg.arisen_brain
        save_cfg()
        log_msg("Arisen brain " .. (cfg.arisen_brain and "ON" or "OFF") .. " (hotkey)")
    end
end

-- v0.8 dev: data/DPC_cmd.json lets a tester (or an agent through the file system) drive DPC without the keyboard:
--   {"id":"any-new-string","cmd":"possess","idx":0} | {"id":"..","cmd":"release"} | {"id":"..","cmd":"solo","on":true}
--   {"id":"..","cmd":"set","key":"arisen_brain_skills","value":false,"save":false}
-- Each new id runs once; the result goes to data/DPC_cmd_ack.json.
local cmd_state = { last_id = nil, next_t = 0 }
local function poll_cmd_file()
    if not (R.dev and cfg.cmd_file) then return end
    local now = os.clock()
    if now < cmd_state.next_t then return end
    cmd_state.next_t = now + 0.5
    local ok, d = pcall(json.load_file, "DPC_cmd.json")
    if not ok or type(d) ~= "table" then
        -- json.load_file logs an error every poll while the file is missing: create an empty one once
        if not cmd_state.created then cmd_state.created = true; pcall(json.dump_file, "DPC_cmd.json", {}) end
        return
    end
    if d.id == nil or d.id == cmd_state.last_id then return end
    if cmd_state.last_id == nil and d.stale_ok ~= true and cmd_state.seen_first == nil then
        -- first file seen after (re)load is a leftover from before: remember it, don't run it
        cmd_state.seen_first = true
        cmd_state.last_id = d.id
        return
    end
    cmd_state.last_id = d.id
    local res = "ok"
    if d.cmd == "possess" then
        start_possession(tonumber(d.idx) or 0)
    elseif d.cmd == "release" then
        release_possession("cmd file")
    elseif d.cmd == "spawn" then
        local p = TEST_PRESETS[tonumber(d.preset) or 0]
        local spec = p and { enemy = p.enemy, count = p.count, dist = p.dist, angle = p.angle, still = p.still }
            or { cid = d.cid, enemy = tonumber(d.enemy) or 1, count = tonumber(d.count) or 1, dist = tonumber(d.dist) or 14.0,
                 angle = tonumber(d.angle) or 0, still = d.still ~= false }
        spec.around = d.around
        -- v0.9.136 "tough": true = cannot die and is topped up when low, also for enemies that fight ("still": false),
        -- so a test fight lasts as long as its step (requested: unkillable but weak test enemies). Despawn clears it.
        if d.tough ~= nil then spec.tough = d.tough and true or false end
        if not spawn_test(spec) then res = "spawn failed" end
    elseif d.cmd == "coop" then
        if d.on == false then coop_stop() else coop_start(tonumber(d.idx) or cfg.selected_pawn_idx) end
    elseif d.cmd == "cp" then
        -- v0.9.171 {"cmd":"cp","p1":"arisen"|<pawn idx>,"p2":"arisen"|<pawn idx>}: who each co-op player controls
        local function ch(v) if v == "arisen" then return "arisen" end return tonumber(v) end
        if not (R.cp and R.cp.on) then res = "co-op is not on"
        elseif not R.cp_apply({ [1] = ch(d.p1), [2] = ch(d.p2) }, "cmd file") then res = "not applied (see log)" end
    elseif d.cmd == "cp_next" then
        if not (R.cp and R.cp.on) then res = "co-op is not on"
        elseif not R.cp_next(tonumber(d.player) or 1) then res = "no change (see log)" end
    elseif d.cmd == "despawn" then
        despawn_tests()
    elseif d.cmd == "down" then
        if not R.down_pawn(d.idx == "other" and "other" or tonumber(d.idx)) then res = "not started (see log)" end
    elseif d.cmd == "quick" then
        -- v0.9.125 {"cmd":"quick","slot":1,"idx":0}: the numpad skill order, for test plans
        local okq, errq = pcall(quick_skill, tonumber(d.slot) or 1, tonumber(d.idx))
        if not okq then res = "quick: " .. tostring(errq) end
    elseif d.cmd == "rearm" then
        -- v0.9.145 {"cmd":"rearm"}: the Warfarer Arisen presses Rearmament now (for test plans)
        local okr, errr = brain.rearm(os.clock(), "command")
        if not okr then res = "rearm: " .. tostring(errr) end
    elseif d.cmd == "heal" then
        -- v0.9.125: heal / revive the party (the Numpad . cheat), so a test never leaves a pawn down
        local okh, errh = pcall(party_heal)
        if not okh then res = "heal: " .. tostring(errh) end
    elseif d.cmd == "scene" then
        -- v0.9.170 (developer, test bench): a known start for a test. Releases any pawn, ends co-op, clears test
        -- enemies, heals the party, turns the experimental switches off (this session only) and, with "anchor":
        -- "set" remembers where the Arisen stands, with "anchor": "go" brings him and the party back there when he
        -- is more than 15 m away (the game's own warp, as Warp to me does).
        if coop.active or (R.cp and R.cp.on) then pcall(coop_stop) end -- v0.9.171: both-on-pawns too
        if state.active then pcall(release_possession, "scene reset") end
        pcall(despawn_tests)
        for _, k in ipairs({ "pf_hitstop", "pf_world_slow", "coop_two_pads" }) do cfg[k] = false end
        cfg.pf_sound_voice, cfg.pf_sound_listener, cfg.pf_sound_space = true, 1, true -- (dev4: the defaults)
        local ar = sdk.get_managed_singleton("app.CharacterManager")
        ar = ar and ar:call("get_ManualPlayer")
        local pos = ar and ar:call("get_Transform"):call("get_Position")
        if pos and d.anchor == "set" then
            R.scene_anchor = { pos.x, pos.y, pos.z }
            pcall(json.dump_file, "bench/anchor.json", { pos = R.scene_anchor })
        elseif pos and d.anchor == "go" then
            local a = R.scene_anchor
            if not a then
                local oka, f = pcall(json.load_file, "bench/anchor.json")
                a = oka and type(f) == "table" and f.pos or nil
            end
            if a then
                local dx, dz = pos.x - a[1], pos.z - a[3]
                if dx * dx + dz * dz > 225 then
                    pcall(ar.call, ar, "warp(via.vec3, app.CharacterWarpOption)", Vector3f.new(a[1], a[2] + 0.3, a[3]), nil)
                    R.scene_warp_t = os.clock() + 1.5 -- the party follows a moment later (see the frame callback)
                    res = "ok (warped back)"
                end
            else
                res = "ok (no anchor yet)"
            end
        end
        local okh = pcall(party_heal)
        if not okh then res = res .. ", heal failed" end
        R.scene_t = os.clock()
    elseif d.cmd == "mark" then
        test_mark(d.label)
    elseif d.cmd == "robot" then
        -- {"cmd":"robot","who":"pad","secs":2,"buttons":["RTrigTop"],"stick":[0,1],"rstick":[1,0]}
        -- {"cmd":"robot","who":"arisen","secs":3,"actions":["AttackS"],"stick":[0,1]}   or "yaw_deg": 90 (world)
        -- {"cmd":"robot","who":"all","stop":true}
        local secs = math.min(tonumber(d.secs) or 1.0, 30.0)
        local function vec(v) if type(v) == "table" and tonumber(v[1]) and tonumber(v[2]) then return v[1] + 0.0, v[2] + 0.0 end end
        if d.stop then
            if d.who ~= "arisen" then robot.pad = nil end
            if d.who ~= "pad" then robot.arisen = nil end
        elseif d.who == "pad" then
            local mask, pv = 0, coop_pad_values()
            if type(d.buttons) == "table" then
                for _, b in ipairs(d.buttons) do mask = mask | (type(b) == "number" and b or pv[b] or 0) end
            elseif type(d.buttons) == "number" then mask = d.buttons end
            -- v0.9.124 {"who":"pad","actions":["AttackS","Skill1"]}: the buttons the game has those actions on
            -- right now (with the shift button a skill needs), so a test plan works with any controller layout
            for _, a in ipairs(type(d.actions) == "table" and d.actions or {}) do
                local m = R.bind_mask(a)
                if m then
                    mask = mask | m
                    for _, e in ipairs(R.bind.list) do
                        if e.name == a and e.pad == m and e.pre and not d.noshift then -- "noshift": the button alone
                            for _, e2 in ipairs(R.bind.list) do if e2.a == e.pre then mask = mask | e2.pad; break end end
                        end
                    end
                else
                    res = "robot: no button known for action " .. tostring(a)
                end
            end
            local lx, ly = vec(d.stick); local rx, ry = vec(d.rstick)
            robot.pad = { btn = mask, lx = lx, ly = ly, rx = rx, ry = ry, until_t = os.clock() + secs, fight = d.fight == true, antics = d.antics == true }
            robot.uses = robot.uses + 1
        elseif d.who == "arisen" then
            local want = 0
            for _, a in ipairs(type(d.actions) == "table" and d.actions or {}) do want = want | (ACTION_FLAGS[a] or 0) end
            local sx, sy = vec(d.stick)
            local mag = sx and math.min(1.0, math.sqrt(sx * sx + sy * sy)) or nil
            if sx and mag > 0 then sx, sy = sx / mag, sy / mag end
            robot.arisen = { want = want, sx = sx, sy = sy, mag = mag, yaw = tonumber(d.yaw_deg) and math.rad(d.yaw_deg) or nil,
                             until_t = os.clock() + secs }
            robot.uses = robot.uses + 1
        else
            res = "robot: who must be pad, arisen or all"
        end
    elseif d.cmd == "solo" then
        brain.solo = d.on == true
    elseif d.cmd == "set" and type(d.key) == "string" and cfg[d.key] ~= nil and type(cfg[d.key]) == type(d.value) then
        cfg[d.key] = d.value
        if d.save then save_cfg() end
    else
        res = "unknown or invalid command"
    end
    log_msg("cmd file: " .. tostring(d.cmd) .. " -> " .. res)
    pcall(json.dump_file, "DPC_cmd_ack.json", { id = d.id, cmd = d.cmd, result = res, t = now, active = state.active, brain = brain.mode,
        test_enemies_alive = spawner.alive, test_enemies_spawned = spawner.spawned })
end

local function guarded_tick(tag, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        local now = os.clock()
        if now - state.last_tick_err_t > 5.0 then -- don't flood the log every frame
            state.last_tick_err_t = now
            log_msg("ERROR in " .. tag .. ": " .. tostring(err))
        end
    end
end

-- v0.9.113 world guard. Log of 2026-11-16: during a save load ("Scene changed") some script kept calling
-- into characters that were being destroyed: 77 access violations in one second, all caught by REFramework, none
-- attributable to a particular mod from the log. As a precaution nothing in this mod touches the game world
-- while it is not in the game phase (MainFlowManager.IsInGamePhase false) or there is no player character.
-- A possession is released first; cached objects are dropped; work resumes one second after the world is back.
R.world_check = function()
    local now = os.clock()
    local okc, good = pcall(function()
        local mf = sdk.get_managed_singleton("app.MainFlowManager")
        if mf and mf:call("get_IsInGamePhase") == false then return false end
        -- (not the load icon or SaveDataManager.IsBusy: those may also be up during an ordinary autosave, and
        -- pausing or dropping a possession on every autosave would be far worse than what this guards against)
        local cm = sdk.get_managed_singleton("app.CharacterManager")
        return cm ~= nil and cm:call("get_ManualPlayer") ~= nil
    end)
    good = okc and good == true
    if not good then
        if R.world ~= false then
            R.world_losses = (R.world_losses or 0) + 1
            if state.active then pcall(release_possession, "loading") end
            -- 0.9.171: before the list is forgotten, test enemies that still exist become killable again. This also
            -- fires on screens where the world stays (a menu), and three unkillable goblins were left that way.
            for _, u in ipairs(spawner.units) do
                pcall(function() local hit = u.chara:call("get_Hit"); if hit then hit:call("set_IsNoDie", false) end end)
            end
            spawner.units, spawner.pending, spawner.alive = {}, {}, 0
            for k in pairs(hud_widgets) do hud_widgets[k] = nil end
            R.ping, R.dh, R.tk = nil, nil, nil
            brain.target, brain.lock, brain.lock_work = nil, nil, nil
            coop.tgt, coop.tgt_work = nil, nil
            quick.rows, quick.defs, quick.packs, quick.rows_try_t = nil, nil, {}, nil -- v0.9.115: game objects, read again later
            R.aim_pick, R.aim_pick_idx, R.aim_asset_addr = nil, nil, nil -- v0.9.168: aim setting, read again later
            pcall(R.cine_stop) -- v0.9.169
            if R.pf_restore_all then pcall(R.pf_restore_all, "loading") end -- v0.9.170
            if R.cp_world_lost then pcall(R.cp_world_lost) end -- v0.9.171
            if R.api_fire then pcall(R.api_fire, "world_loading", {}) end
            log_msg("World is loading: the mod pauses until it is back")
        end
        R.world, R.world_back_t = false, nil
        return false
    end
    if R.world == false then
        R.world_back_t = R.world_back_t or now
        if now - R.world_back_t < 1.0 then return false end
        log_msg("World is back: the mod resumes")
        if R.api_fire then pcall(R.api_fire, "world_back", {}) end
    end
    R.world = true
    return true
end


-- ============================================================================================================
-- v0.9.171 (dev) co-op, any combination. The north star: either player can be the Arisen or any pawn.
--   R.cp  = the co-op session: who each of the two people controls (char[1], char[2]: "arisen" or a pawn index)
--           and how that maps onto the engine.
--   Modes:
--     "classic": one player on the Arisen, the other on a pawn. This is the co-op DPC already had (coop.active,
--                the pawn in the main possession slot, fed from its player's controller through coop.pad_input).
--                With two controllers either player can be the Arisen side: R.tp.p1 is always the Arisen side's
--                controller, R.tp.p2 the pawn side's (cp.arisen_side says which person that is).
--     "pawns":   both players on pawns, the Arisen on DPC's AI. Player 1's pawn is a normal single-player
--                possession (its input is the Arisen's game input, which only player 1's controller or the
--                keyboard reaches); player 2's pawn is R.s2, a second played pawn with its own
--                PlayerInputProcessor and lock-on, fed from player 2's controller.
--   Every change of who plays whom goes through R.cp_apply, which tears the old arrangement down and builds the
--   new one with the existing start / release code (one path, easy to reason about; costs a camera transition).
--   Controls: each player's take-control combination (L1 + left stick click; F6 on the keyboard = player 1) moves
--   that player to the next character: the pawns in party order, skipping the other player's, then the Arisen if
--   he is free. With one controller (player 1 on keyboard and mouse) player 2 cannot take the Arisen.
-- ============================================================================================================
R.cp = { on = false, kb = true, char = {}, mode = "classic", arisen_side = 1, busy = false, log = {}, applies = 0 }
R.s2 = { active = false, hooked = false, latch = {}, errors = 0, frames = 0 }

R.cp_event = function(s)
    coop_event("any: " .. tostring(s))
    local L = R.cp.log
    L[#L + 1] = string.format("%.2f %s", os.clock(), tostring(s))
    if #L > 40 then table.remove(L, 1) end
end
R.cp_pawns = function() return R.cp.on and R.cp.mode == "pawns" end
-- after a change of roles: no combination until every controller has let go of its buttons, and 0.75 s at least
R.cp_quiet_ok = function()
    local c = R.cp
    return os.clock() >= (c.quiet_until or 0) and not c.need_release
end
R.cp_release_check = function() -- once a frame (R.cp_tick)
    local c = R.cp
    if not c.need_release then return end
    local any = false
    for _, d in ipairs(R.tp_devs()) do if (R.tp_read(d).b or 0) ~= 0 then any = true end end
    if not any then c.need_release = false end
end
R.s2_idx = function() return R.s2.active and R.s2.idx or nil end

R.cp_p1_pad = function() return R.cp_pawns() and not R.cp.kb and cfg.coop_any_p1_route == "pad" end
R.cp_two = function() return cfg.coop_two_pads and R.tp.p1 ~= nil and R.tp.p2 ~= nil end
-- the controller (address) of person n, from the current arrangement; "kb" / "pad" with one controller
R.cp_dev = function(n)
    local c, t = R.cp, R.tp
    if c.kb then return n == 1 and "kb" or "pad" end
    if c.mode == "pawns" then return n == 1 and t.p1 or t.p2 end
    if n == (c.arisen_side or 1) then return t.p1 else return t.p2 end
end
R.cp_label = function(n) return "P" .. tostring(n) end
R.cp_pawn_label = function() -- the label over the classic co-op pawn's bars
    if R.cp.on and R.cp.mode == "classic" then return R.cp_label(R.cp.arisen_side == 2 and 1 or 2) end
    return "P2"
end
-- names: game thread only (get_party); the settings window reads R.cp.names
R.cp_char_name = function(ch)
    if ch == "arisen" then return "the Arisen" end
    for _, e in ipairs(get_party()) do if e.idx == ch then return tostring(e.name) end end
    return "pawn " .. tostring(ch)
end
R.cp_names = function()
    local c = R.cp
    c.names = { [1] = R.cp_char_name(c.char[1]), [2] = R.cp_char_name(c.char[2]) }
end

-- session start: co-op just started (coop_start); not while R.cp_apply is rebuilding
R.cp_begin = function()
    if R.cp.busy then return end
    local c = R.cp
    c.on, c.mode, c.arisen_side, c.ar2 = true, "classic", 1, false
    R.ar2_src = nil
    c.kb = not R.cp_two()
    c.char = { [1] = "arisen", [2] = state.pawn_idx }
    c.ar_prevb = nil
    pcall(R.cp_names)
    R.cp_event("session on: P1 the Arisen, P2 " .. tostring(state.pawn_name) .. (c.kb and " (one controller)" or " (two controllers)"))
end

-- session end (co-op off, loading, a cutscene ...). Never while R.cp_apply is rebuilding.
R.cp_end = function(why)
    local c = R.cp
    if c.busy then return end
    local was_pawns = c.on and c.mode == "pawns"
    if R.s2.active then pcall(R.s2_stop, why or "co-op off") end
    if R.np then pcall(R.np_end, why or "co-op off") end
    if c.on then R.cp_event("session off (" .. tostring(why) .. ")") end
    c.on, c.mode, c.arisen_side, c.ar2 = false, "classic", 1, false
    R.ar2_src = nil
    if R.tp and not coop.active then R.tp.start_kb, R.tp.start_t = nil, nil end -- dev50
    if was_pawns and state.active and not coop.active then pcall(release_possession, "co-op off") end
    if R.tp.p1 and R.tp.p2 and R.tp.swapped then R.tp.p1, R.tp.p2, R.tp.swapped = R.tp.p2, R.tp.p1, false end
    pcall(coop_write_status)
end

-- the next character for person n: pawns in party order (not the other player's, not down), then the Arisen if
-- he is free (and, with one controller, only for player 1)
R.cp_next = function(n)
    local c = R.cp
    if not c.on or c.busy or not cfg.coop_any then return false end
    local other = (n == 1) and 2 or 1
    local round = {}
    for _, e in ipairs(get_party()) do
        local np_held = false
        for _, sl in pairs(R.np.slots) do if sl.active and sl.idx == e.idx then np_held = true end end -- 0.9.172
        if e.idx ~= c.char[other] and not np_held and R.cr_ok(e.chara) then round[#round + 1] = e.idx end
    end
    table.sort(round)
    if c.char[other] ~= "arisen" and not (c.kb and n == 2) then round[#round + 1] = "arisen" end
    local cur, pick = c.char[n], nil
    for i, v in ipairs(round) do
        if v == cur then pick = round[(i % #round) + 1]; break end
    end
    if pick == nil then pick = round[1] end
    if pick == nil or pick == cur then
        R.note = { text = R.cp_label(n) .. ": nobody else to take", t_end = os.clock() + 2.0 }
        return false
    end
    local want = { [n] = pick, [other] = c.char[other] }
    return R.cp_apply(want, R.cp_label(n) .. " pressed next")
end

-- build the arrangement want = { [1] = char, [2] = char }
R.cp_apply = function(want, why)
    local c = R.cp
    if not c.on or c.busy then return false end
    local a, b = want[1], want[2]
    if a == nil or b == nil or a == b then return false end
    -- 0.9.172: a pawn a player 3+ holds is not taken from them
    for _, v in ipairs({ a, b }) do
        if type(v) == "number" and R.np then
            for n, sl in pairs(R.np.slots) do
                if sl.active and sl.idx == v then
                    R.note = { text = tostring(sl.name) .. " is player " .. n .. "'s", t_end = os.clock() + 2.0 }
                    R.cp_event(string.format("apply P1=%s P2=%s refused: player %d plays %s", tostring(a), tostring(b), n, tostring(sl.name)))
                    return false
                end
            end
        end
    end
    if not R.cp_two() then c.kb = true end
    if c.kb and b == "arisen" then
        R.note = { text = "P2 can take the Arisen only with two controllers", t_end = os.clock() + 3.0 }
        return false
    end
    local d1, d2 = R.cp_dev(1), R.cp_dev(2)
    R.cp_event(string.format("apply P1=%s P2=%s (%s)", tostring(a), tostring(b), tostring(why)))
    c.busy = true
    c.applies = c.applies + 1
    local ok, err = pcall(function()
        c.ar2 = false
        R.ar2_src, R.ar2_view = nil, nil
        if b == "arisen" and not c.kb and cfg.coop_any_p2_arisen ~= "classic" then
            -- 0.9.171: player 2 on the Arisen. Player 1 keeps the game's input and the camera, on his pawn (a normal
            -- possession); the Arisen runs on player 2's controller through the brain's input path (R.ar2_tick).
            if R.s2.active then R.s2_stop("co-op change") end
            if coop.active and state.active then release_possession("co-op change") end
            coop.active = false
            R.tp.p1, R.tp.p2, R.tp.swapped = d1, d2, false
            R.tp.p1v, R.tp.p2v, R.tp.p1_prevb = nil, nil, nil
            pcall(json.dump_file, "DPC_two_pads.json", { p1 = R.tp.p1, p2 = R.tp.p2 })
            c.mode, c.arisen_side, c.ar2 = "pawns", 2, true
            c.ar2_take_prev, c.ar2_leave_t, c.ar2_latch = nil, nil, {}
            if not (state.active and state.pawn_idx == a) then start_possession(a) end
        elseif a == "arisen" or b == "arisen" then
            local ar_n = (a == "arisen") and 1 or 2
            local pawn = (ar_n == 1) and b or a
            if R.s2.active then R.s2_stop("co-op change") end
            if state.active and not coop.active then release_possession("co-op change") end
            if not c.kb then
                R.tp.p1, R.tp.p2 = (ar_n == 1) and d1 or d2, (ar_n == 1) and d2 or d1
                R.tp.p1v, R.tp.p2v, R.tp.p1_prevb = nil, nil, nil
                R.tp.swapped = (ar_n == 2)
                pcall(json.dump_file, "DPC_two_pads.json", { p1 = R.tp.p1, p2 = R.tp.p2 })
            end
            c.mode, c.arisen_side = "classic", ar_n
            if coop.active and state.active then
                if state.pawn_idx ~= pawn then start_possession(pawn); coop.pawn_idx = pawn end
            else
                coop_start(pawn)
            end
        else
            if coop.active and state.active then release_possession("co-op change") end
            coop.active = false
            if R.s2.active and R.s2.idx ~= b then R.s2_stop("co-op change") end
            if not c.kb then
                R.tp.p1, R.tp.p2, R.tp.swapped = d1, d2, false
                R.tp.p1v, R.tp.p2v, R.tp.p1_prevb = nil, nil, nil
                pcall(json.dump_file, "DPC_two_pads.json", { p1 = R.tp.p1, p2 = R.tp.p2 })
            end
            c.mode, c.arisen_side = "pawns", 1
            if not (state.active and state.pawn_idx == a) then start_possession(a) end
            if state.active and not R.s2.active then R.s2_start(b) end
        end
    end)
    c.busy = false
    if not ok then dev_error("co-op apply", err); R.cp_event("apply failed: " .. tostring(err)) end
    -- what we really have now
    if c.mode == "pawns" and c.ar2 then
        if not state.active then R.cp_end("could not set up") return false end
        c.char = { [1] = state.pawn_idx, [2] = "arisen" }
    elseif c.mode == "pawns" then
        if not (state.active and R.s2.active) then
            R.cp_event("both-pawns arrangement did not come up (main " .. tostring(state.active) .. ", second " .. tostring(R.s2.active) .. ")")
            -- fall back to the classic arrangement with player 2's pawn, else end the session
            c.mode = "classic"
            local p2pawn = R.s2.active and R.s2.idx or (type(b) == "number" and b or nil)
            if R.s2.active then R.s2_stop("fallback") end
            if state.active and not coop.active then release_possession("co-op change") end
            if p2pawn then
                c.busy = true
                c.arisen_side = 1
                pcall(coop_start, p2pawn)
                c.busy = false
            end
            if not coop.active then R.cp_end("could not set up") return false end
            c.char = { [1] = "arisen", [2] = state.pawn_idx }
        else
            c.char = { [1] = state.pawn_idx, [2] = R.s2.idx }
        end
    else
        if not (coop.active and state.active) then R.cp_end("could not set up") return false end
        c.char[c.arisen_side] = "arisen"
        c.char[c.arisen_side == 1 and 2 or 1] = state.pawn_idx
    end
    pcall(coop_write_status)
    pcall(R.cp_names)
    -- the buttons that made this change may still be held, now on another role's input: no combination counts
    -- until they are let go (and not for 0.75 s at all)
    c.quiet_until = os.clock() + 0.75
    c.need_release = true
    local function nm(ch) return R.cp_char_name(ch) end
    R.note = { text = string.format("P1: %s   P2: %s", nm(c.char[1]), nm(c.char[2])), t_end = os.clock() + 4.0 }
    log_msg(string.format("Co-op: P1 plays %s, P2 plays %s (%s)", nm(c.char[1]), nm(c.char[2]), c.mode))
    return ok
end

-- -------------------------------------------------------------------------------------------- second pawn
R.s2_hook = function()
    if R.s2.hooked then return end
    R.s2.hooked = true
    local td = sdk.find_type_definition("app.Player")
    local m = td and td:get_method("update")
    if not m then R.s2.hook_err = "no app.Player.update"; return end
    -- the slot where the game runs player input (the main played pawn's processor runs here too, v0.7.5)
    -- 0.9.172: every played extra pawn (player 2's R.s2 and players 3+'s slots) runs here
    local function run(s)
        if not (s.active and s.pip and not s.failed) then return end
        s.hook_frames = (s.hook_frames or 0) + 1
        if s.drive_pre then return end -- driven from the frame tick instead (see R.s2_drive)
        pcall(function() if (s.input:get_field("ButtonOnFlags") or 0) ~= 0 then s.hook_input = (s.hook_input or 0) + 1 end end)
        pcall(R.s2_target, s)
        R.s2_pre(s)
        local ok, err = pcall(s.pip.call, s.pip, "update")
        s.frames = s.frames + 1
        if not ok then
            s.errors = s.errors + 1
            s.err = tostring(err)
            if s.errors >= 5 then
                s.failed = true
                R.cp_event(R.cp_label(s.player or 2) .. "'s controls failed: " .. s.err)
                log_msg("Co-op: player " .. tostring(s.player or 2) .. "'s pawn controls failed (" .. s.err .. ")")
            end
        end
    end
    sdk.hook(m, function(args)
        run(R.s2)
        if R.np then for _, sl in pairs(R.np.slots) do run(sl) end end
    end, function(r) return r end)
end

R.s2_start = function(idx, s)
    s = s or R.s2
    local pn = s.player or 2
    if s.active then R.s2_stop("restart", s) end
    local entry
    for _, e in ipairs((pn >= 3 and R.party_all) and R.party_all() or get_party()) do if e.idx == idx then entry = e end end
    if not entry then R.cp_event("second pawn: no pawn " .. tostring(idx)); return false end
    if state.active and state.pawn_idx == idx then return false end
    if R.held_by and R.held_by(idx, s) then R.cp_event("second pawn: " .. tostring(entry.name) .. " is played by someone else"); return false end
    if not R.cr_ok(entry.chara) then R.cp_event("second pawn: " .. tostring(entry.name) .. " is down"); return false end
    local ar = quick_arisen()
    local apip = ar and call(ar, "get_InputProcessor")
    local input = call(entry.chara, "get_Input")
    if not (apip and input and entry.human) then R.cp_event("second pawn: missing input / processor"); return false end
    s.idx, s.chara, s.human, s.pawn, s.name = entry.idx, entry.chara, entry.human, entry.pawn, entry.name
    s.job, s.skills, s.input = entry.job, entry.skills, input
    s.dash_opt0 = R.dash_opt_take(input)
    s.chara_addr, s.human_addr = addr_of(entry.chara), addr_of(entry.human)
    s.sel_addr = addr_of(call(entry.chara, "get_HumanActionSelector"))
    s.prev_on, s.errors, s.frames, s.failed, s.err, s.pad = 0, 0, 0, false, nil, nil
    s.latch, s.tgt, s.tgt_work, s.tgt_next, s.next_skill_t = {}, nil, nil, 0, 0
    s.take_prev, s.leave_t = nil, nil
    s.hook_frames, s.hook_input, s.mirror_input = 0, 0, 0
    s.drive_pre = (cfg.coop_any_drive == "pre")
    set_pawn_ai_suppressed(entry.chara, entry.pawn, true, true)
    if cfg.possess_interrupt_ai then
        pcall(R.guide_stop, entry.chara, entry.name)
        pcall(R.interrupt_ai, entry.chara, entry.name, true)
    end
    pcall(function()
        local hcac = call(entry.human, "get_HumanCommonActionCtrl") or field(entry.human, "<HumanCommonActionCtrl>k__BackingField")
        s.dash_req0 = hcac and hcac:call("get_IsEnableDashToRequestedMoveSpeedOfNormalLocomotion")
        if hcac and cfg.native_dash_to_req then -- 0.9.172: see possession; off unless asked for
            hcac:call("set_IsEnableDashToRequestedMoveSpeedOfNormalLocomotion(System.Boolean)", true)
        end
    end)
    -- the same processor build as native_build, with a lock-on controller of its own (never player 1's)
    local ok, err = pcall(function()
        local pw, hu = entry.chara, entry.human
        local pip = sdk.create_instance("app.PlayerInputProcessor"):add_ref()
        local track = hu:get_field("Track")
        pip:call("set_Chara", pw)
        pip:call("set_Human", hu)
        pip:call("set_PlayerTrack", track)
        pip:set_field("Camera", apip:get_field("Camera"))
        pip:call("setup(app.Character, app.PlayerTrack)", pw, track)
        if not pip:get_field("Camera") then pip:set_field("Camera", apip:get_field("Camera")) end
        pip:call("selectProcessor")
        local alock = apip:get_field("Param"):get_field("LockOnCtrl")
        local lock = sdk.create_instance("app.LockOnController"):add_ref()
        lock:call("setup", pw, alock and alock:get_field("<ParamList>k__BackingField"))
        local param = pip:get_field("Param")
        param:set_field("Chara", pw)
        param:set_field("Human", hu)
        param:set_field("PlayerTrack", track)
        param:set_field("LockOnCtrl", lock)
        local di = pip:get_field("DetailInstances")
        for i = 0, di:get_Length() - 1 do
            local d = di[i]
            if d then d:set_field("Param", param) end
        end
        s.pip, s.param, s.lock, s.pip_job = pip, param, lock, entry.job
    end)
    if not ok then
        R.cp_event("second pawn: processor build failed: " .. tostring(err))
        log_msg("Co-op: player 2's pawn controls could not be built (" .. tostring(err) .. ")")
        set_pawn_ai_suppressed(entry.chara, entry.pawn, false, true)
        s.chara, s.human, s.pawn, s.input, s.pip, s.param, s.lock = nil, nil, nil, nil, nil, nil, nil
        return false
    end
    s.active, s.t0 = true, os.clock()
    R.s2_hook()
    R.cp_event("second pawn: " .. R.cp_label(pn) .. " plays " .. tostring(entry.name))
    if R.api_fire then pcall(R.api_fire, "possess", { player = pn, name = entry.name, job = entry.job, chara = entry.chara }) end
    return true
end

R.s2_stop = function(why, s)
    s = s or R.s2
    if not s.active then return end
    s.active = false
    local ch, hu, pw = s.chara, s.human, s.pawn
    local teardown = tostring(why or ""):find("teardown") ~= nil
    if not teardown then
        pcall(function()
            if s.input then
                s.input:set_field("ButtonOnFlags", 0)
                s.input:set_field("ButtonTriggerFlags", 0)
                s.input:set_field("ButtonReleaseFlags", s.prev_on or 0)
                s.input:call("setAxisL(System.Single, System.Single)", 0.0, 0.0)
                s.input:call("set_AxisMagnitudeL(System.Single)", 0.0)
            end
        end)
        pcall(function()
            ch:call("setLocomotionSpeed(app.LocomotionSpeedTypeEnum)", 0)
            ch:call("set_DiscreteLocomotionSpeedType(app.LocomotionSpeedTypeEnum)", 0)
        end)
        pcall(function() hu:call("set_IsDash(System.Boolean)", false); hu:call("set_IsPrevDash(System.Boolean)", false) end)
        pcall(function()
            if type(s.dash_req0) == "boolean" then hu:call("get_HumanCommonActionCtrl"):call("set_IsEnableDashToRequestedMoveSpeedOfNormalLocomotion(System.Boolean)", s.dash_req0) end
            s.dash_req0 = nil
        end)
        R.dash_opt_put(s.input, s.dash_opt0)
        s.dash_opt0 = nil
        pcall(function() if s.lock then s.lock:call("clearLockOn") end end)
        pcall(set_pawn_ai_suppressed, ch, pw, false, true)
    end
    R.cp_event("second pawn: " .. R.cp_label(s.player or 2) .. " let go of " .. tostring(s.name) .. " (" .. tostring(why) .. ")")
    if R.api_fire then pcall(R.api_fire, "release", { player = s.player or 2, name = s.name, reason = tostring(why or "manual") }) end
    s.chara, s.human, s.pawn, s.input, s.pip, s.param, s.lock = nil, nil, nil, nil, nil, nil, nil
    s.chara_addr, s.human_addr, s.sel_addr = 0, 0, 0
    s.tgt, s.tgt_work, s.hp, s.st = nil, nil, nil, nil
end

-- coop.pad_input is written for the main slot's co-op pawn (it reads the pad globals, the pawn's vocation and
-- skills from state, and keeps chord / tap latches in coop). Run it for the second pawn by lending it the second
-- pawn's values for the call and putting everything back afterwards.
R.s2_pad_input = function(p, job, skills, latch)
    local s, L = R.s2, latch or R.s2.latch
    local sv_b, sv_x, sv_y = pad_buttons, pad_stick_x, pad_stick_y
    local sv_job, sv_sk = state.pawn_job, state.pawn_skills
    local sv = { coop.face_t, coop.face_sh, coop.face_out, coop.pulse_pad, coop.pulse_until, coop.chord_latch,
        coop.last_btn, coop.last_flags, coop.last_stick }
    local sv_aim = cfg.coop_aim
    pad_buttons, pad_stick_x, pad_stick_y = p.b or 0, p.lx or 0.0, p.ly or 0.0
    state.pawn_job, state.pawn_skills = job or s.job, skills or s.skills
    coop.face_t, coop.face_sh, coop.face_out = L.face_t, L.face_sh, L.face_out
    coop.pulse_pad, coop.pulse_until, coop.chord_latch = L.pulse_pad, L.pulse_until, L.chord_latch
    cfg.coop_aim = false
    local ok, on, ax, ay, mag = pcall(coop.pad_input)
    L.face_t, L.face_sh, L.face_out = coop.face_t, coop.face_sh, coop.face_out
    L.pulse_pad, L.pulse_until, L.chord_latch = coop.pulse_pad, coop.pulse_until, coop.chord_latch
    cfg.coop_aim = sv_aim
    coop.face_t, coop.face_sh, coop.face_out, coop.pulse_pad, coop.pulse_until, coop.chord_latch = sv[1], sv[2], sv[3], sv[4], sv[5], sv[6]
    coop.last_btn, coop.last_flags, coop.last_stick = sv[7], sv[8], sv[9]
    state.pawn_job, state.pawn_skills = sv_job, sv_sk
    pad_buttons, pad_stick_x, pad_stick_y = sv_b, sv_x, sv_y
    if not ok then error(on) end
    return on or 0, ax or 0.0, ay or 0.0, mag or 0.0
end

-- the second pawn's own target (its lock-on is not updated by anything else): nearest enemy ahead of it,
-- the co-op auto-target rule
R.s2_target = function(s)
    s = s or R.s2
    if not (s.lock and s.chara and cfg.coop_auto_target) then return end
    local now = os.clock()
    if now >= (s.tgt_next or 0) then
        s.tgt_next = now + 0.1
        local px, _, pz = brain_pos(s.chara)
        if not px then return end
        local face = brain_facing(s.chara)
        local r, cone = cfg.coop_target_range or 15.0, math.rad(cfg.coop_target_cone or 75.0)
        if cfg.coop_target_game_ranges then
            local rc = R.lock_ranges(s.job)
            if rc and rc.base and rc.base > 0 then r = rc.base end
        end
        local best, bs
        local em = sdk.get_managed_singleton("app.EnemyManager")
        local arr = em and call(em, "getAllEnemies")
        local n = arr and call(arr, "get_Count") or 0
        for i = 0, n - 1 do
            local okg, e = pcall(function() return arr[i]:get_field("_Chara") end)
            if okg and e and brain_alive(e) then
                local ex, _, ez = brain_pos(e)
                if ex then
                    local d = math.sqrt((ex - px) ^ 2 + (ez - pz) ^ 2)
                    local off = math.abs(brain_angdiff(math.atan(ex - px, ez - pz), face))
                    local keep = same_obj(e, s.tgt) and 0.7 or 1.0
                    if d <= r and (off <= cone or d <= 5.0) then
                        local score = d * (1.0 + off / math.pi * 2.0) * keep
                        if not bs or score < bs then best, bs = e, score end
                    end
                end
            end
        end
        -- 0.9.172-dev36: players 3+ keep a target with a flick (s.pin) until R3 lets go or it dies
        if s.pin then
            if brain_alive(s.pin) then best = s.pin else s.pin = nil end
        end
        if not same_obj(best, s.tgt) then
            s.tgt, s.tgt_work = best, nil
            if best then pcall(function() s.tgt_work = best:call("get_LockOnTarget"):call("get_work") end) end
            if not best and s.tgt_set then pcall(s.lock.call, s.lock, "clearLockOn"); s.tgt_set = false end
        end
    end
    if s.tgt_work then
        local ok = pcall(function()
            s.lock:call(SET_TARGET_SIG, s.tgt_work, false, false)
            s.lock:call("setAimTargetInfoToCharacter")
        end)
        if ok then s.tgt_set = true; s.tgt_sets = (s.tgt_sets or 0) + 1 else s.tgt_errs = (s.tgt_errs or 0) + 1 end
    end
end

-- poll_pad, in the both-pawns arrangement: player 2's controller goes to the second pawn, and the pad globals
-- (DPC's own combinations for the main pawn) become player 1's controller only, or nothing when player 1 is on
-- the keyboard
R.cp_pad_route = function()
    if not R.cp_pawns() then return end
    local s = R.s2
    if not R.cp.kb then
        local v2, v1 = R.tp.p2v, R.tp.p1v
        s.pad = v2 and { b = v2.b or 0, lx = v2.lx or 0.0, ly = v2.ly or 0.0, rx = v2.rx or 0.0, ry = v2.ry or 0.0 } or { b = 0, lx = 0.0, ly = 0.0 }
        if v1 then
            pad_buttons, pad_stick_x, pad_stick_y, pad_stick_rx, pad_stick_ry = v1.b or 0, v1.lx or 0.0, v1.ly or 0.0, v1.rx or 0.0, v1.ry or 0.0
        else
            pad_buttons, pad_stick_x, pad_stick_y, pad_stick_rx, pad_stick_ry = 0, 0.0, 0.0, 0.0, 0.0
        end
    else
        s.pad = { b = pad_buttons or 0, lx = pad_stick_x or 0.0, ly = pad_stick_y or 0.0, rx = pad_stick_rx or 0.0, ry = pad_stick_ry or 0.0 }
        pad_buttons, pad_stick_x, pad_stick_y, pad_stick_rx, pad_stick_ry = 0, 0.0, 0.0, 0.0, 0.0
    end
end
-- the robot (developer, test plans) is player 2 in the both-pawns arrangement: its buttons and stick go to the
-- second pawn; "fight" steers it at the nearest enemy and taps light attack (the main-slot robot's rule)
R.s2_robot = function(rp)
    local s = R.s2
    s.pad = s.pad or { b = 0, lx = 0.0, ly = 0.0 }
    s.pad.b = (s.pad.b or 0) | (rp.btn or 0)
    if rp.lx then s.pad.lx, s.pad.ly = rp.lx, rp.ly end
    if rp.fight and s.chara then
        pcall(function()
            local now = os.clock()
            if now >= (rp.s2_next or 0) then
                rp.s2_next = now + 0.4
                local okp, t = pcall(quick_pick_enemy, s.chara)
                rp.s2_tgt = okp and t or nil
            end
            local px, _, pz = brain_pos(s.chara)
            local tx, tz
            if rp.s2_tgt then tx, _, tz = brain_pos(rp.s2_tgt) end
            if not (px and tx) then s.pad.lx, s.pad.ly = 0.0, 0.0; return end
            local dx, dz = tx - px, tz - pz
            local d = math.sqrt(dx * dx + dz * dz)
            local sx, sy = brain_stick_for(math.atan(dx, dz))
            local k = (d > 2.2) and 1.0 or 0.3
            s.pad.lx, s.pad.ly = sx * k, sy * k
            if d <= 3.0 then
                local m = R.bind_mask("AttackS")
                if m and ((now * 1000) % 600) < 180 then s.pad.b = s.pad.b | m end
            end
        end)
    end
end

-- once a frame (game thread): the second pawn's input, its own combinations, its bars
-- 0.9.172-dev37, coop-4p-3 (the tester): player 4's pawn "seems to be trying to get somewhere and control is not handed
-- off". The things that carry a pawn on after a take-over were only stopped for player 1's pawn: its path-following
-- (NavigationAI, 0.9.131) and its running action command (0.9.132 / 0.9.162: any command in the first 1.5 s, then
-- move.* and JumpGrab). Players 2+ get the same, 10 x a second.
R.s2_carry_stop = function(s, now)
    if now < (s.carry_next or 0) then return end
    s.carry_next = now + 0.1
    if cfg.possess_stop_navi ~= false and s.pawn then
        pcall(function()
            local nai = s.pawn:call("get_CachedNavigationAI")
            if nai and nai:call("get_IsNaviNow") == true then
                nai:call("setNavigationStop")
                s.navi_stops = (s.navi_stops or 0) + 1
            end
        end)
    end
    if cfg.possess_stop_move ~= false and s.chara then
        local addr = s.chara:get_address()
        if addr ~= s.move_addr then s.move_addr, s.move_take_until = addr, now + 1.5 end
        local okc, c = pcall(R.move_cmd, s.chara)
        if okc and c and c.running and c.name then
            local taking = now < (s.move_take_until or 0)
            if taking or c.name:find("app.actinter.cmd.move.", 1, true) == 1 or c.name == "app.actinter.cmd.JumpGrab" then
                pcall(c.ex.call, c.ex, "forceEndAction")
                s.move_stops = (s.move_stops or 0) + 1
                if (s.move_stops or 0) <= 3 then
                    R.cp_event(string.format("%s: ended %s's command %s", R.cp_label(s.player or 2), tostring(s.name), c.name:gsub("^app%.actinter%.cmd%.", "")))
                end
            end
        end
    end
end
R.s2_tick = function(s)
    s = s or R.s2
    local pn = s.player or 2
    if not s.active then return end
    local ch = s.chara
    local lost = nil
    pcall(function()
        if ch:call("get_IsDead") == true then lost = "pawn dead"
        elseif ch:call("get_IsDown") == true and (ch:call("get_Hp") or 1) <= 0 then lost = "pawn downed (0 HP)"
        elseif ch:call("get_IsCutSceneMode") == true then lost = "cutscene" end
    end)
    if lost then R.s2_stop(lost, s); s.lost = lost; return end
    set_pawn_ai_suppressed(ch, s.pawn, true, false)
    local now = os.clock()
    pcall(R.s2_carry_stop, s, now)
    if now >= (s.next_skill_t or 0) then
        s.next_skill_t = now + 0.5
        local j = get_job(s.human, ch)
        if j and j ~= s.job then
            s.job = j
            if s.pip then pcall(s.pip.call, s.pip, "selectProcessor") end
        end
        s.skills = get_skills(s.human, s.job)
        -- bars (drawn in re.on_frame from these numbers)
        pcall(function()
            local sm = ch:call("get_StaminaManager")
            local mx = sm and sm:call("get_MaxValue") or 0
            s.st = mx > 0 and math.max(0.0, math.min(1.0, (sm:call("get_RemainingAmount") or 0) / mx)) or nil
            local hit = ch:call("get_Hit")
            local omx = hit and hit:call("get_OriginalMaxHp") or 0
            s.hp = omx > 0 and math.max(0.0, math.min(1.0, (hit:call("get_Hp") or 0) / omx)) or nil
            s.bars_t = now
        end)
    end
    if now - (s.bars_t or 0) > 0.2 then
        pcall(function()
            local sm = ch:call("get_StaminaManager")
            local mx = sm and sm:call("get_MaxValue") or 0
            if mx > 0 then s.st = math.max(0.0, math.min(1.0, (sm:call("get_RemainingAmount") or 0) / mx)) end
            local hit = ch:call("get_Hit")
            local omx = hit and hit:call("get_OriginalMaxHp") or 0
            if omx > 0 then s.hp = math.max(0.0, math.min(1.0, (hit:call("get_Hp") or 0) / omx)) end
            s.bars_t = now
        end)
    end
    local p = s.pad or { b = 0, lx = 0.0, ly = 0.0 }
    s.pad = nil
    -- player 2's own combinations, on the raw buttons
    local raw = p.b or 0
    local tm = R.take_mask and R.take_mask() or 0
    if s.take_prev == nil then s.take_prev = raw end -- held from before this pawn was taken: not a new press
    if tm ~= 0 and (raw & tm) == tm and ((s.take_prev or 0) & tm) ~= tm and not R.cap and R.cp_quiet_ok() then
        s.take_prev = raw
        if pn == 2 then R.cp_next(2) else R.np_next(pn) end
        return
    end
    s.take_prev = raw
    local pv = coop_pad_values()
    local leave = (pv.LStickPush or 0x1000) | (pv.RStickPush or 0x2000)
    if (raw & leave) == leave then
        s.leave_t = s.leave_t or now
        if now - s.leave_t >= 3.0 then
            s.leave_t = nil
            R.note = { text = "Co-op: player " .. pn .. " left", t_end = now + 3.0 }
            if pn == 2 then R.cp_end("player 2 held L3 + R3") else R.np_leave(pn, "held L3 + R3") end
            return
        end
    else
        s.leave_t = nil
    end
    local okp, on, ax, ay, mag = pcall(R.s2_pad_input, p, s.job, s.skills, s.latch)
    if not okp then
        s.in_err = tostring(on)
        dev_error("co-op " .. R.cp_label(pn) .. " input", on)
        on, ax, ay, mag = 0, 0.0, 0.0, 0.0
    end
    local trg, rel = on & ~(s.prev_on or 0), (s.prev_on or 0) & ~on
    s.prev_on = on
    s.last_on, s.last_mag = on, mag
    local inp = s.input
    local okw, errw = pcall(function()
        inp:set_field("ButtonOnFlags", on)
        inp:set_field("ButtonTriggerFlags", trg)
        inp:set_field("ButtonReleaseFlags", rel)
        inp:call("setAxisL(System.Single, System.Single)", ax, ay)
        inp:call("set_AxisMagnitudeL(System.Single)", mag)
    end)
    if not okw then s.in_err = tostring(errw) end
    if on ~= 0 then s.mirror_input = (s.mirror_input or 0) + 1 end
    pcall(R.s2_drive, s)
end

-- Where the second pawn's processor runs. Two ways, as for the main played pawn (v0.7.5): in app.Player.update
-- (default, the slot where the game runs player input) or right here at pre-UpdateBehavior. "auto" starts in the
-- app.Player.update slot and moves here if that hook never fires within 1 s or never sees the input written here
-- (cfg.coop_any_drive: "auto" | "player" | "pre").
R.s2_drive = function(s)
    s = s or R.s2
    if not (s.active and s.pip and not s.failed) then return end
    local mode = cfg.coop_any_drive or "auto"
    if not s.drive_pre and mode == "auto" then
        local age = os.clock() - (s.t0 or 0)
        if age > 1.0 and (s.hook_frames or 0) == 0 then
            s.drive_pre = true
            R.cp_event(R.cp_label(s.player or 2) .. "'s controls: app.Player.update never fired -> driving at pre-UpdateBehavior")
        elseif (s.mirror_input or 0) > 120 and (s.hook_input or 0) == 0 then
            s.drive_pre = true
            R.cp_event(R.cp_label(s.player or 2) .. "'s controls: input already cleared at app.Player.update -> driving at pre-UpdateBehavior")
        end
    end
    if not s.drive_pre then return end
    pcall(R.s2_target, s)
    R.s2_pre(s)
    local ok, err = pcall(s.pip.call, s.pip, "update")
    s.frames = s.frames + 1
    if not ok then
        s.errors = s.errors + 1
        s.err = tostring(err)
        if s.errors >= 5 then s.failed = true; R.cp_event(R.cp_label(s.player or 2) .. "'s controls failed: " .. s.err) end
    end
end

-- ------------------------------------------------------------------------------- players 3 and up (0.9.172)
-- Each extra player is a slot shaped like R.s2 (same start / stop / tick / drive code, the slot passed in) with its
-- own claimed controller. Design: claude/dpc-coop-n.md. Joins with L3 + R3 held 1.5 s on an unclaimed controller
-- while co-op runs on two controllers; the take-control combination goes to the next free pawn; L3 + R3 held 3 s
-- leaves. Pawns only for now (the Arisen's driver needs player 1 on a pawn and takes one source).
R.np = { slots = {}, log = {}, pool = {} }
-- the characters players 3+ can take: the party (an extra-pawn mod that grows the party is included by the game's own
-- list) and characters other mods offer through DPC_API.add_character (index 100 and up)
R.party_all = function()
    local out = get_party()
    for i, h in ipairs(R.np.pool) do
        if not h.gone and h.chara then
            local ok, e = pcall(function()
                local ch = h.chara
                if not sdk.is_managed_object(ch) then return nil end
                local hu = call(ch, "get_Human")
                local job = get_job(hu, ch)
                return { idx = 100 + i, chara = ch, human = hu, pawn = nil, name = h.name or ("Character " .. i),
                    job = job, job_name = JOB_NAMES[job] or ("Job#" .. tostring(job)), skills = get_skills(hu, job), from_mod = h.mod }
            end)
            if ok and e then out[#out + 1] = e end
        end
    end
    return out
end
R.np_event = function(t)
    local L = R.np.log
    L[#L + 1] = string.format("%.2f %s", os.clock(), t)
    if #L > 30 then table.remove(L, 1) end
end
-- who plays pawn idx (any player but the slot given): a player number, or nil
R.held_by = function(idx, except)
    if idx == nil then return nil end
    if state.active and state.pawn_idx == idx then
        return (coop.active and not (R.cp and R.cp.on and R.cp.arisen_side == 2)) and 2 or 1
    end
    if R.s2.active and R.s2.idx == idx and except ~= R.s2 then return 2 end
    for n, sl in pairs(R.np.slots) do
        if sl.active and sl.idx == idx and sl ~= except then return n end
    end
    return nil
end
R.np_sel = function(a) -- the action selector address belongs to an extra player's pawn?
    for _, sl in pairs(R.np.slots) do if sl.active and a == (sl.sel_addr or -1) then return true end end
    return false
end
R.np_claimed = function(a)
    for n, sl in pairs(R.np.slots) do if sl.dev == a then return n end end
    return nil
end
R.np_count = function() local n = 0; for _ in pairs(R.np.slots) do n = n + 1 end; return n end
-- the first free pawn after "from" in party order (wrapping), nil if none
R.np_free_pawn = function(from, self)
    local round = {}
    for _, e in ipairs(R.party_all()) do
        if not R.held_by(e.idx, self) and R.cr_ok(e.chara) then round[#round + 1] = e.idx end
    end
    table.sort(round)
    if #round == 0 then return nil end
    if from == nil then return round[1] end
    for _, v in ipairs(round) do if v > from then return v end end
    return round[1]
end
R.np_join = function(d)
    local c = R.cp
    local n = 3
    while R.np.slots[n] do n = n + 1 end
    if n > (cfg.coop_max_players or 8) then
        R.note = { text = "Co-op: " .. (n - 1) .. " players already", t_end = os.clock() + 3.0 }
        return false
    end
    local idx = R.np_free_pawn(nil, nil)
    if not idx then
        R.note = { text = "Co-op: no free character for player " .. n, t_end = os.clock() + 3.0 }
        return false
    end
    local sl = { player = n, dev = d:get_address(), active = false, hooked = true, latch = {}, errors = 0, frames = 0 }
    R.np.slots[n] = sl
    if not R.s2_start(idx, sl) then
        R.np.slots[n] = nil
        R.note = { text = "Co-op: player " .. n .. " could not take a character", t_end = os.clock() + 3.0 }
        return false
    end
    sl.wait_release = true
    R.np_event(string.format("player %d joined (%X) on %s", n, sl.dev & 0xFFFFFF, tostring(sl.name)))
    R.note = { text = "Co-op: player " .. n .. " joined, plays " .. tostring(sl.name), t_end = os.clock() + 4.0 }
    log_msg("Co-op: player " .. n .. " joined on " .. tostring(sl.name))
    if R.api_fire then pcall(R.api_fire, "player_join", { player = n, name = sl.name }) end
    pcall(coop_write_status)
    return true
end
R.np_leave = function(n, why)
    local sl = R.np.slots[n]
    if not sl then return end
    if sl.active and why ~= "script reset" then
        local g = R.pglow[n]
        if g and g.kept then pcall(R.cine_glow, g.chara, g.name, false) end
        R.pglow[n] = nil
        R.leave_glow(sl.chara) -- dev38: show who left
    end
    if sl.active then pcall(R.s2_stop, why or "left", sl) end
    R.np.slots[n] = nil
    R.np_event("player " .. n .. " left (" .. tostring(why) .. ")")
    log_msg("Co-op: player " .. n .. " left (" .. tostring(why) .. ")")
    if R.api_fire then pcall(R.api_fire, "player_leave", { player = n, reason = tostring(why or "") }) end
    pcall(coop_write_status)
end
R.np_end = function(why)
    for n in pairs(R.np.slots) do R.np_leave(n, why) end
end
R.np_next = function(n)
    local sl = R.np.slots[n]
    if not sl then return false end
    local nxt = R.np_free_pawn(sl.idx, sl)
    if nxt == nil or nxt == sl.idx then
        R.note = { text = R.cp_label(n) .. ": nobody else to take", t_end = os.clock() + 2.0 }
        return false
    end
    local was = sl.idx
    pcall(R.s2_stop, "next character", sl)
    if not R.s2_start(nxt, sl) then
        pcall(R.s2_start, was, sl) -- back to the one before
        return false
    end
    sl.wait_release = true
    R.note = { text = R.cp_label(n) .. ": " .. tostring(sl.name), t_end = os.clock() + 3.0 }
    R.np_event("player " .. n .. " -> " .. tostring(sl.name))
    pcall(coop_write_status)
    return true
end
-- once a frame from R.cp_tick (co-op on): controllers, joins of a lost controller, each slot's tick
R.np_tick = function()
    if not next(R.np.slots) then return end
    local devs = R.tp_devs()
    local by = {}
    for _, d in ipairs(devs) do by[d:get_address()] = d end
    local now = os.clock()
    local lost = {}
    for n, sl in pairs(R.np.slots) do
        local d = sl.dev and by[sl.dev]
        if d then
            local okr, v = pcall(R.tp_read, d)
            v = okr and v or { b = 0, lx = 0.0, ly = 0.0, rx = 0.0, ry = 0.0 }
            if sl.wait_release then
                if v.b == 0 then sl.wait_release = nil end
                v = { b = 0, lx = v.lx, ly = v.ly, rx = v.rx, ry = v.ry }
            end
            sl.pad, sl.pad_lost = v, nil
            -- dev41: R.s2_tick consumes sl.pad (sets it nil), so the camera, which runs later in the frame, never saw
            -- players 3+'s sticks ("p3 and P4 cameras did not do anything"; bridge: sl.pad nil on both). Kept here.
            sl.pad_cam = { b = v.b or 0, lx = v.lx or 0.0, ly = v.ly or 0.0, rx = v.rx or 0.0, ry = v.ry or 0.0 } -- raw (np_aim takes R3 out of v)
            if sl.active then pcall(R.np_aim, sl, now) end
        else
            sl.pad, sl.pad_cam = { b = 0, lx = 0.0, ly = 0.0 }, nil
            if not sl.pad_lost then
                sl.pad_lost = now
                R.np_event("player " .. n .. "'s controller went away")
                R.note = { text = "Co-op: player " .. n .. "'s controller went away - press a button on it when it is back", t_end = now + 4.0 }
            end
            lost[#lost + 1] = sl
        end
        if sl.active then
            R.s2_tick(sl)
            if not sl.active and R.np.slots[n] then
                -- the pawn went down: the next free one, or the player waits without a character
                local why = sl.lost or "lost"
                sl.lost = nil
                local nxt = (why ~= "cutscene") and R.np_free_pawn(sl.idx, sl) or nil
                if not (nxt and R.s2_start(nxt, sl)) then
                    R.np_event("player " .. n .. ": no character (" .. why .. ")")
                    R.note = { text = "Co-op: player " .. n .. " has no character - press the take-control combination", t_end = now + 3.0 }
                end
            end
        else
            -- no character: the take-control combination looks for a free one
            local raw = sl.pad and sl.pad.b or 0
            local tm = R.take_mask and R.take_mask() or 0
            if tm ~= 0 and (raw & tm) == tm and ((sl.take_prev or 0) & tm) ~= tm then
                local nxt = R.np_free_pawn(nil, sl)
                if nxt and R.s2_start(nxt, sl) then sl.wait_release = true end
            end
            sl.take_prev = raw
        end
    end
    -- a controller that is back under a new address: the oldest lost slot takes the first unclaimed controller used
    -- (after players 1 and 2's own recovery in R.tp_tick)
    if #lost > 0 and not R.tp.keep then
        table.sort(lost, function(a, b) return (a.pad_lost or 0) < (b.pad_lost or 0) end)
        for _, d in ipairs(devs) do
            local a = d:get_address()
            if a ~= R.tp.p1 and a ~= R.tp.p2 and not R.np_claimed(a) then
                local okr, v = pcall(R.tp_read, d)
                if okr and v and R.tp_used(v) then
                    local sl = table.remove(lost, 1)
                    sl.dev, sl.pad_lost, sl.wait_release = a, nil, true
                    R.np_event(string.format("player %d's controller is back (%X)", sl.player, a & 0xFFFFFF))
                    R.note = { text = "Co-op: player " .. sl.player .. "'s controller is back", t_end = now + 3.0 }
                    if #lost == 0 then break end
                end
            end
        end
    end
end
-- 0.9.172-dev36: players 3+ aim like player 2: a quick right-stick flick keeps the next enemy on that side, R3 lets
-- go (back to the automatic target). R3 is taken out of their buttons, as for player 2.
R.np_side = function(sl, dir)
    local ds = imgui.get_display_size()
    local w = ds and ds.x or 1920
    local px, _, pz = brain_pos(sl.chara)
    if not px then return nil end
    local cx = nil
    if sl.tgt then
        local x, y, z = brain_pos(sl.tgt)
        cx = x and R.ta_sx({ x = x, y = y, z = z })
    end
    if not cx then
        local x, y, z = brain_pos(sl.chara)
        cx = x and R.ta_sx({ x = x, y = y, z = z }) or w * 0.5
    end
    local best, gap = nil, nil
    local em = sdk.get_managed_singleton("app.EnemyManager")
    local arr = em and call(em, "getAllEnemies")
    local n = arr and call(arr, "get_Count") or 0
    for i = 0, n - 1 do
        local ok, e = pcall(function() return arr[i]:get_field("_Chara") end)
        if ok and e and brain_alive(e) and not (sl.tgt and same_obj(e, sl.tgt)) then
            local ex, ey, ez = brain_pos(e)
            if ex and (ex - px) ^ 2 + (ez - pz) ^ 2 <= 45.0 ^ 2 then
                local sx = R.ta_sx({ x = ex, y = ey, z = ez })
                if sx and sx > 0 and sx < w then
                    local dx = sx - cx
                    if (dir > 0 and dx > 1) or (dir < 0 and dx < -1) then
                        if not gap or math.abs(dx) < gap then best, gap = e, math.abs(dx) end
                    end
                end
            end
        end
    end
    return best
end
R.np_aim = function(sl, now)
    local p = sl.pad
    if not (p and cfg.coop_aim) then return end
    local pv = coop_pad_values()
    local r3, l3 = pv.RStickPush or 0x2000, pv.LStickPush or 0x1000
    local b = p.b or 0
    if (b & l3) ~= 0 then sl.r3_prev, sl.r3_t = false, nil; return end -- L3 + R3: join / leave / take, left alone
    local down = (b & r3) ~= 0
    if down and not sl.r3_prev then sl.r3_t = now end
    if not down and sl.r3_prev and sl.r3_t and now - sl.r3_t < 0.4 and sl.pin then
        sl.pin, sl.tgt_next = nil, 0
        R.ta_note("Player " .. sl.player .. ": automatic target")
    end
    sl.r3_prev = down
    p.b = b & ~r3
    sl.fa = sl.fa or {}
    local d = R.flick_step(sl.fa, p.rx or 0.0, p.ry or 0.0, now)
    if d then
        local e = R.np_side(sl, d)
        if e then sl.pin, sl.tgt_next = e, 0; R.ta_note("Player " .. sl.player .. ": target kept (R3 lets go)") end
    end
end
-- the played characters of players 3+, in player order (for R.players, sound, the camera)
R.np_charas = function()
    local out = {}
    local ns = {}
    for n in pairs(R.np.slots) do ns[#ns + 1] = n end
    table.sort(ns)
    for _, n in ipairs(ns) do
        local sl = R.np.slots[n]
        if sl.active and sl.chara then out[#out + 1] = { player = n, chara = sl.chara, idx = sl.idx, name = sl.name } end
    end
    return out
end

-- once a frame from the main tick, before it returns for "nobody possessed"
-- 0.9.171: player 2 on the Arisen (both-pawns arrangement, c.ar2): player 2's controller (R.s2.pad, filled by
-- R.cp_pad_route) through the co-op pad map with the Arisen's vocation and skills, handed to the brain as its
-- scripted input. The camera's right stick stays player 1's.
R.ar2_tick = function()
    local c = R.cp
    local now = os.clock()
    local p = R.s2.pad or { b = 0, lx = 0.0, ly = 0.0 }
    R.s2.pad = nil
    local raw = p.b or 0
    local tm = R.take_mask and R.take_mask() or 0
    if c.ar2_take_prev == nil then c.ar2_take_prev = raw end
    if tm ~= 0 and (raw & tm) == tm and (c.ar2_take_prev & tm) ~= tm and not R.cap and R.cp_quiet_ok() then
        c.ar2_take_prev = raw
        R.ar2_src = nil
        R.cp_next(2)
        return
    end
    c.ar2_take_prev = raw
    local pv = coop_pad_values()
    local leave = (pv.LStickPush or 0x1000) | (pv.RStickPush or 0x2000)
    if (raw & leave) == leave then
        c.ar2_leave_t = c.ar2_leave_t or now
        if now - c.ar2_leave_t >= 3.0 then
            c.ar2_leave_t = nil
            R.ar2_src = nil
            R.note = { text = "Co-op: player 2 left", t_end = now + 3.0 }
            R.cp_end("player 2 held L3 + R3")
            return
        end
    else
        c.ar2_leave_t = nil
    end
    local job, sk = brain.job, brain.skills
    if not job then
        pcall(function()
            local cm = sdk.get_managed_singleton("app.CharacterManager")
            if not cm then return end
            local ar = cm:call("get_ManualPlayer")
            local hu = ar and ar:call("get_Human")
            job = get_job(hu, ar)
            sk = get_skills(hu, job)
        end)
    end
    c.ar2_latch = c.ar2_latch or {}
    local okp, on, ax, ay, mag = pcall(R.s2_pad_input, p, job, sk, c.ar2_latch)
    if not okp then
        c.ar2_err = tostring(on)
        dev_error("co-op P2 Arisen input", on)
        on, ax, ay, mag = 0, 0.0, 0.0, 0.0
    end
    mag = mag or 0.0
    local sx, sy = 0.0, 0.0
    if mag > 0.001 then sx, sy = (ax or 0.0) / mag, (ay or 0.0) / mag end
    R.ar2_src = { want = on or 0, sx = sx, sy = sy, mag = mag, until_t = now + 0.25, label = "player 2" }
    c.ar2_frames = (c.ar2_frames or 0) + 1
    -- 0.9.172: what player 2's bars and skill list show (the Arisen's), refreshed 5 times a second
    local v = R.ar2_view or {}
    R.ar2_view = v
    v.active = true
    if now - (v.bars_t or 0) > 0.2 then
        pcall(function()
            local cm = sdk.get_managed_singleton("app.CharacterManager")
            local ar = cm and cm:call("get_ManualPlayer")
            if not ar then return end
            local hu = ar:call("get_Human")
            v.job = job or get_job(hu, ar)
            v.skills = sk or get_skills(hu, v.job)
            if not v.name then v.name = R.cp_char_name and R.cp_char_name("arisen") or "the Arisen" end
            local sm = ar:call("get_StaminaManager")
            local mx = sm and sm:call("get_MaxValue") or 0
            if mx > 0 then v.st = math.max(0.0, math.min(1.0, (sm:call("get_RemainingAmount") or 0) / mx)) end
            local hit = ar:call("get_Hit")
            local omx = hit and hit:call("get_OriginalMaxHp") or 0
            if omx > 0 then v.hp = math.max(0.0, math.min(1.0, (hit:call("get_Hp") or 0) / omx)) end
            v.bars_t = now
        end)
    end
end

R.cp_tick = function()
    local c = R.cp
    if not c.on then
        if R.s2.active then R.s2_stop("no co-op") end
        if next(R.np.slots) then R.np_end("no co-op") end
        return
    end
    if c.busy then return end
    local oknp, enp = pcall(R.np_tick)
    if not oknp then R.np.err = tostring(enp); dev_error("co-op extra players", enp) end
    pcall(R.cp_release_check)
    if c.mode == "classic" then
        if not coop.active then R.cp_end("co-op ended") return end
        if not R.cp_two() then c.kb = true elseif c.kb then c.kb = false end
        if state.active and c.char[c.arisen_side == 1 and 2 or 1] ~= state.pawn_idx then
            c.char[c.arisen_side == 1 and 2 or 1] = state.pawn_idx
            pcall(R.cp_names)
            pcall(coop_write_status)
        end
        -- the Arisen side's own take-control combination (two controllers: his controller; one: F6, below)
        if not c.kb then
            local v = R.tp.p1v
            local b = v and v.b or 0
            local tm = R.take_mask and R.take_mask() or 0
            local prev = c.ar_prevb or 0
            c.ar_prevb = b
            if cfg.coop_any and tm ~= 0 and (b & tm) == tm and (prev & tm) ~= tm and not R.cap and R.cp_quiet_ok() then R.cp_next(c.arisen_side) end
        end
        return
    end
    -- both on pawns
    if not state.active then
        local why = tostring(R.cp_last_rel or "")
        if why:find("loading") or why:find("cutscene") or why:find("teardown") or why:find("script") or why:find("arisen died") then
            R.cp_end(why)
        elseif R.s2.active then
            R.cp_apply({ [1] = "arisen", [2] = R.s2.idx }, "P1 back to the Arisen (" .. why .. ")")
        else
            R.cp_end(why)
        end
        return
    end
    c.char[1] = state.pawn_idx
    if c.ar2 then R.ar2_tick() return end
    if not R.s2.active then
        -- player 2's pawn went down / into a cutscene: the next free character for player 2, else end
        local why = R.s2.lost or "lost"
        R.s2.lost = nil
        if why == "cutscene" then R.cp_end("cutscene") return end
        R.note = { text = "P2's pawn is down", t_end = os.clock() + 3.0 }
        local nxt
        for _, e in ipairs(get_party()) do
            if e.idx ~= state.pawn_idx and R.cr_ok(e.chara) and (not nxt or e.idx < nxt) then nxt = e.idx end
        end
        if nxt then
            R.cp_apply({ [1] = state.pawn_idx, [2] = nxt }, "P2's pawn " .. why)
        elseif not c.kb then
            R.cp_apply({ [1] = state.pawn_idx, [2] = "arisen" }, "P2's pawn " .. why)
        else
            R.cp_end("P2's pawn " .. why)
        end
        return
    end
    R.s2_tick()
end

-- the world went away (loading): nothing of the session survives it
R.cp_world_lost = function()
    if R.s2.active then pcall(R.s2_stop, "loading") end
    pcall(R.np_end, "loading")
    if R.cp.on then R.cp.busy = false; R.cp_end("loading") end
end

-- 0.9.172: players 3+'s bars, stacked above player 2's place, one row per player
re.on_frame(function()
    if not (R.np and next(R.np.slots) and cfg.coop_stamina_bar) then return end
    if R.hud_hidden and R.hud_hidden() then return end
    pcall(function()
        local hx, hy, hw, hh = R.hud_rect()
        local w = hw * 0.12 * (cfg.coop_stamina_width or 1.0)
        local h = math.max(2.0, (cfg.coop_bars_thick or 4.0) * hh / 2160.0)
        local al = math.floor(255 * math.max(0.15, math.min(1.0, cfg.coop_bars_alpha or 0.65)))
        local function col(rgb, f) return (math.floor(al * (f or 1.0)) << 24) | rgb end
        local row = 0
        local ns = {}
        for n in pairs(R.np.slots) do ns[#ns + 1] = n end
        table.sort(ns)
        for _, n in ipairs(ns) do
            local sl = R.np.slots[n]
            -- players 3, 5, 7 ... on the left, 4, 6, 8 ... on the right of player 2's bars
            local side = (n % 2 == 1) and -1 or 1
            local x = hx + hw * (cfg.coop_stamina_hud_x or 0.5) - w * 0.5 + side * (w + hw * 0.1)
            local y = hy + hh * (cfg.coop_stamina_hud_y or 0.9) - math.floor((n - 3) / 2) * hh * 0.05
            local ty = y - math.max(16.0, hh * 0.02)
            local label = "P" .. n .. "  " .. (sl.active and tostring(sl.name or "") or "(no character)") .. (sl.pad_lost and "  - controller lost" or "")
            draw.text(label, x, ty, col(sl.pad_lost and 0x5555FF or 0xD8D8D8))
            if sl.active and cfg.coop_skill_palette and cfg.coop_np_palette ~= false and R.palette_draw then
                -- left-side players' lists grow to the left of their bars, right-side ones to the right
                local px = (side < 0) and (x + w) or x
                pcall(R.palette_draw, sl, n, "DirectPawnControl_SkillHUD_P" .. n, px, ty - hh * 0.005, (side < 0) and 1.0 or 0.0)
            end
            if sl.active and sl.st then
                local gap = h + math.max(2.0, hh * 0.003)
                if sl.hp then
                    draw.filled_rect(x, y, w, h, col(0x000000, 0.55))
                    draw.filled_rect(x, y, w * sl.hp, h, col(0x60A878))
                    y = y + gap
                end
                draw.filled_rect(x, y, w, h, col(0x000000, 0.55))
                draw.filled_rect(x, y, w * sl.st, h, col(0x50B4D2))
            end
            row = row + 1
        end
    end)
end)

-- P2's bars in the both-pawns arrangement (classic co-op draws its own); 0.9.172: also with player 2 on the Arisen
re.on_frame(function()
    local s = R.s2
    if R.cp.on and R.cp.ar2 and R.ar2_view then s = R.ar2_view end
    if not (s.active and R.cp_pawns() and cfg.coop_stamina_bar) then return end
    if R.hud_hidden and R.hud_hidden() then return end
    if not s.st or os.clock() - (s.bars_t or 0) > 0.6 then return end
    pcall(function()
        local hx, hy, hw, hh = R.hud_rect()
        local w = hw * 0.16 * (cfg.coop_stamina_width or 1.0)
        local h = math.max(2.0, (cfg.coop_bars_thick or 4.0) * hh / 2160.0)
        local x = hx + hw * (cfg.coop_stamina_hud_x or 0.5) - w * 0.5
        local y = hy + hh * (cfg.coop_stamina_hud_y or 0.9)
        local al = math.floor(255 * math.max(0.15, math.min(1.0, cfg.coop_bars_alpha or 0.65)))
        local function col(rgb, f) return (math.floor(al * (f or 1.0)) << 24) | rgb end
        local gap = h + math.max(2.0, hh * 0.003)
        local ty = y - math.max(16.0, hh * 0.02)
        if s.hp then
            draw.filled_rect(x, y, w, h, col(0x000000, 0.55))
            draw.filled_rect(x, y, w * s.hp, h, col(0x60A878))
            y = y + gap
        end
        draw.filled_rect(x, y, w, h, col(0x000000, 0.55))
        draw.filled_rect(x, y, w * s.st, h, col(0x50B4D2))
        draw.text("P2  " .. tostring(s.name or ""), x, ty, col(0xD8D8D8))
    end)
    -- player 2's skill list, the classic co-op palette's look and place (controller buttons only)
    if cfg.coop_skill_palette then
        pcall(function()
            local hx, hy, hw, hh = R.hud_rect()
            local wx, wy = hx + hw * (cfg.coop_palette_left or 0.60), hy + hh * (cfg.coop_palette_bottom or 0.93)
            R.palette_draw(s, 2, "DirectPawnControl_SkillHUD_P2", wx, wy, 0.0)
        end)
    end
end)
-- 0.9.172: one player's skill list window (player 2's, and players 3+'s beside their bars). pivot_x 0 = the window's
-- left edge at wx, 1 = its right edge. The window is always closed, whatever goes wrong inside (an error here left it
-- open once: ImGui "Missing End()").
R.palette_draw = function(s, pn, win, wx, wy, pivot_x)
    imgui.set_next_window_pos(Vector2f.new(wx, wy), 1, Vector2f.new(pivot_x or 0.0, 1.0))
    imgui.begin_window(win, nil, (1 << 0) | (1 << 1) | (1 << 3) | (1 << 6))
    local okb, errb = pcall(function()
        imgui.text_colored(string.format("Player %d: %s (%s)", pn, tostring(s.name), JOB_NAMES[s.job] or "Pawn"), 0xFF88EEFF)
        imgui.separator()
        local sk = s.skills or {}
        local six = (sk[5] or 0) ~= 0 or (sk[6] or 0) ~= 0
        for n = 1, 6 do
            local sid = sk[n] or 0
            if sid ~= 0 then
                local sbl = R.SLOT_BIND_LABELS or {} -- set where the table is declared (later in the file)
                local lbl = (six and sbl.six and sbl.six[n]) or sbl[n] or ("[Skill " .. n .. "]")
                local okg, gl = pcall(R.bind_label, n)
                if okg and gl then lbl = "[Num" .. n .. " / " .. tostring(gl) .. "]" end
                local inner = lbl:match("/ ([^%]]+)%]") or (lbl:gsub("[%[%]]", ""))
                local okp, pl = pcall(R.pad_label, "[" .. inner .. "]", R.dev_style(s.dev or (pn == 2 and R.tp.p2) or nil))
                imgui.text_colored(string.format("   %s  %s", okp and tostring(pl) or ("[" .. inner .. "]"), skill_name(sid)), 0xFFFFFFFF)
            end
        end
    end)
    if not okb then s.hud_err = tostring(errb) end
    imgui.end_window()
end

-- 0.9.172: tell a player coming from an older version, once, when the game world is up
re.on_frame(function()
    if R.fresh_note and R.world == true then
        R.fresh_note = nil
        R.note = { text = "Direct Pawn Control 0.9.172: settings start from the new defaults (your key bindings are kept)", t_end = os.clock() + 8.0 }
        pcall(log_msg, "Settings: started from the 0.9.172 defaults; key and controller bindings kept (old file: DirectPawnControl.before_0.9.172.json)")
    end
end)
re.on_script_reset(function()
    if R.s2 and R.s2.active then pcall(R.s2_stop, "script reset") end
    if R.np then pcall(R.np_end, "script reset") end
end)

re.on_pre_application_entry("UpdateBehavior", function()
    ensure_enums()
    poll_pad()
    poll_keys()
    R.world_now = R.world_check()
    if not R.world_now then return end

    -- Live Speedometer Calculation
    local now_t = os.clock()
    local dt_spd = now_t - (state.last_speed_time or now_t)
    if dt_spd >= 0.05 then
        state.last_speed_time = now_t
        if state.active and state.pawn_chara then
            local pxf = call(state.pawn_chara, "get_Transform")
            local ppos = pxf and call(pxf, "get_Position")
            if ppos and state.last_pawn_pos then
                local dx = ppos.x - state.last_pawn_pos.x
                local dz = ppos.z - state.last_pawn_pos.z
                state.live_speed_mps = math.sqrt(dx * dx + dz * dz) / dt_spd
            end
            state.last_pawn_pos = ppos
        else
            state.live_speed_mps = 0.0
            state.last_pawn_pos = nil
        end
    end

    -- 0. Drain queued UI actions on the game thread
    while #main_thread_queue > 0 do
        local item = table.remove(main_thread_queue, 1)
        write_trace("Queued action: " .. tostring(item.desc))
        local ok, err = pcall(item.fn)
        if not ok then
            log_msg("ERROR in " .. tostring(item.desc) .. ": " .. tostring(err))
        end
    end

    -- 1. Hotkeys
    -- v0.9.90 selection. F7 picks a character (a marker shows over them for a few seconds), F6 takes control of the
    -- pick, the numpad skill keys order the pick. While a pawn is possessed the pick starts on the Arisen, so F6
    -- still returns to him and the numpad orders him; F7 then walks through the other pawns. In co-op F7 keeps
    -- its old meaning (switch player 2's pawn at once). Design note, 2026-11-16: while possessing, the number pad orders the Arisen by default; wanted: a key to select a pawn or the Arisen with an in-game highlight, and a way to switch to the selection from anywhere.
    if state.active and not coop.active then
        if R.sel_for ~= state.pawn_idx then R.sel_for, R.sel_kind, R.sel_idx, R.sel_name = state.pawn_idx, "arisen", nil, "the Arisen" end
    else
        R.sel_for, R.sel_kind, R.sel_idx = nil, "pawn", nil
    end
    -- v0.9.96 controller: HOLD a D-pad direction (no shoulder button held) for pad_hold_s: left / right = select the
    -- previous / next character, up = switch to the selection, down = back to the Arisen. A tap still gives the
    -- game's pawn order; the order also goes out at the start of a hold (accepted risk: it may set off the D-pad orders). Not in co-op.
    R.bind_read()
    R.kbind_read()
    if R.kbind and not R.clash_logged then
        R.clash_logged = true
        for _, c in ipairs(R.key_clashes()) do log_msg("Key clash: " .. c .. ". Change one of them (the mod's keys are in its settings window)") end
    end
    R.ring_hook()
    R.hold = nil
    if R.ord_block_raw then -- the D-pad is up again: 0.4 s more, then orders pass as usual
        local pv = coop_pad_values()
        if ((pad_buttons or 0) & ((pv.LUp or 0x1) | (pv.LDown or 0x2) | (pv.LLeft or 0x4) | (pv.LRight or 0x8))) == 0 then
            R.ord_block_raw = false
            R.ord_block_until = os.clock() + 0.4
        end
    end
    if cfg.pad_hold_select and not coop.active then
        R.order_hook()
        local dir = R.dpad_dir(pad_buttons or 0)
        local dh = R.dh or {}
        R.dh = dh
        if dir ~= dh.dir then
            -- released (or changed) before the hold time: that was a tap, so give the order the game asked for
            if dh.dir and not dh.fired and dh.order and dh.pc then
                local pc, order = dh.pc, dh.order
                R.ord_bypass = true
                local okr, errr = pcall(pc.call, pc, "tryUpdatePawnOrder(app.PawnOrderController.PawnOrder)", order)
                R.ord_bypass = false
                R.ord_replays = (R.ord_replays or 0) + 1
                if not okr then dev_error("order replay", errr) end
            end
            if dh.dir and dh.fired then R.ord_block_raw = true; R.dh_cmd = nil
            elseif dh.dir and R.dh_cmd then R.cmd_replay, R.dh_cmd = R.dh_cmd, nil end -- a tap: the mod's own reactions to the order
            -- a press the hook saw before this tick did (dh.dir still nil) keeps its captured order
            local ko, kp = nil, nil
            if dh.dir == nil and dir then ko, kp = dh.order, dh.pc end
            dh.dir, dh.t0, dh.fired, dh.order, dh.pc = dir, os.clock(), false, ko, kp
        elseif dir and not dh.fired and os.clock() - dh.t0 >= (cfg.pad_hold_s or 0.5) then
            dh.fired = true
            dh.order = nil
            R.hold = dir
            R.holds = (R.holds or 0) + 1
        end
    end
    R.cap_tick()
    R.hint_tick()
    quick.hold_tick()
    R.arrow_hook()
    R.arrow_tick()
    pcall(R.arrow_give_tick)
    -- v0.9.149: a combination of the player's choice takes the Arisen back (none by default)
    if (tonumber(cfg.pad.back) or 0) ~= 0 and state.active and not coop.active and pad_combo_pressed(cfg.pad.back) then R.hold = "down" end
    -- v0.9.98: L1 + left stick click = take control of the selection (same as F6)
    -- v0.9.149: the combination can be changed (cfg.pad.take); it fires on the frame the last of its buttons goes down
    if cfg.pad_l1_l3_possess and not R.cap and os.clock() >= (R.cap_quiet or 0) then
        local tm = R.take_mask()
        local b = pad_buttons or 0
        if tm ~= 0 and (b & tm) == tm and ((pad_prev or 0) & tm) ~= tm then
            if coop.active then
                -- v0.9.153 requested: player 2 can change pawn with the same combination. Pawns only, in party order;
                -- no way to the Arisen from here (he is player 1's), and no D-pad selection (the D-pad is player 2's
                -- quick items and lantern in co-op).
                if cfg.coop_p2_switch and state.active and not (R.cp and R.cp.on and not R.cp_quiet_ok()) then
                    local nxt = R.next_pawn_only(get_party())
                    if nxt then
                        log_msg("Co-op: player 2 switches to " .. tostring(nxt.name))
                        cfg.selected_pawn_idx = nxt.idx
                        save_cfg()
                        start_possession(nxt.idx)
                        coop.pawn_idx = nxt.idx
                        coop_write_status()
                        R.note = { text = "Co-op: player 2 plays " .. tostring(state.pawn_name), t_end = os.clock() + 3.0 }
                    end
                end
            elseif cfg.coop_any and R.cp and R.cp.on then
                if R.cp_quiet_ok() then pcall(R.cp_next, 1) end -- v0.9.171: both on pawns: player 1's next character (his controller only here)
            elseif state.active then
                -- v0.9.148 requested: while a pawn is played this combination went back to the Arisen (the selection
                -- starts on him), the same as holding D-pad down. It now switches straight to the next pawn in the
                -- party, in party order and wrapping round; the Arisen is not in the round (D-pad down is his).
                local party = get_party()
                local nxt, picked = R.next_pawn(party)
                if nxt == "arisen" then
                    log_msg("Take-control combination: back to the Arisen (" .. (picked and "picked with the arrows" or "end of the round") .. ")")
                    if not picked then -- the next press as the Arisen starts the round again at the first pawn
                        local first
                        for _, e in ipairs(party) do if not first or e.idx < first.idx then first = e end end
                        if first then cfg.selected_pawn_idx = first.idx; save_cfg() end
                    end
                    toggle_possession()
                elseif nxt then
                    log_msg("Take-control combination: " .. (picked and "the pick, " or "next pawn, ") .. tostring(nxt.name))
                    cfg.selected_pawn_idx = nxt.idx
                    save_cfg()
                    start_possession(nxt.idx)
                else
                    log_msg("L1 + left stick click: no other pawn in the party to switch to")
                end
            else
                R.hold = "up"
            end
        end
    end
    if R.hold == "down" and state.active then toggle_possession() end
    -- v0.9.150: couch co-op has its own key (Ctrl+F6 by default; with or without Ctrl, as it was chosen) and an
    -- optional controller combination. The take-control key does nothing while Ctrl is held, as before.
    local coop_key = R.key_hit("coop")
    local coop_hit = coop_key or pad_combo_pressed(cfg.pad.coop) or R.p1_combo_pressed(cfg.pad.coop)
    if not coop_hit then pcall(R.cr_tick) end
    pcall(R.rb_tick)
    if coop_hit then
        R.cr.want = false
        -- dev46: co-op started from the keyboard: player 1 is on keyboard and mouse this session
        if not (coop.active or (R.cp and R.cp.on)) then R.tp.start_kb, R.tp.start_t = coop_key and true or nil, os.clock() end
        coop_toggle()
    elseif R.key_hit("toggle_possess") or pad_combo_pressed(cfg.pad.toggle_possess) or R.hold == "up" then
        if cfg.coop_any and R.cp and R.cp.on then
            pcall(R.cp_next, 1) -- v0.9.171: in co-op F6 is player 1's next character (it used to end co-op)
        elseif state.active and not coop.active and R.sel_kind == "pawn" and R.sel_idx ~= nil and R.sel_idx ~= state.pawn_idx then
            cfg.selected_pawn_idx = R.sel_idx
            save_cfg()
            start_possession(R.sel_idx)
        else
            toggle_possession()
        end
    end
    if R.key_hit("cycle_pawn") or R.hold == "left" or R.hold == "right" then
        local party = get_party()
        if #party > 0 then
            if state.active and not coop.active and not cfg.cycle_switches_now then
                -- candidates: the Arisen, then every pawn except the one being played
                local list = { { kind = "arisen", name = "the Arisen", chara = state.arisen_chara } }
                for _, e in ipairs(party) do
                    if e.idx ~= state.pawn_idx then list[#list + 1] = { kind = "pawn", idx = e.idx, name = e.name, chara = e.chara } end
                end
                local cur = 1
                for i, c in ipairs(list) do
                    if c.kind == R.sel_kind and (c.kind == "arisen" or c.idx == R.sel_idx) then cur = i end
                end
                local pick = list[((R.hold == "left") and ((cur - 2) % #list) or (cur % #list)) + 1]
                R.sel_kind, R.sel_idx, R.sel_name = pick.kind, pick.idx, pick.name
                R.ping = { chara = pick.chara, name = pick.name, t_end = os.clock() + 3.0 }
                R.last_pick = { chara = pick.chara, t = os.clock() } -- dev52: for a co-op join
                R.sel_label, R.sel_label_until = pick.name, os.clock() + 4.0
                log_msg("Selected: " .. tostring(pick.name))
            else
                cfg.selected_pawn_idx = (cfg.selected_pawn_idx + ((R.hold == "left") and -1 or 1)) % #party
                save_cfg()
                if state.active then
                    start_possession(cfg.selected_pawn_idx)
                    if coop.active then coop.pawn_idx = cfg.selected_pawn_idx; coop_write_status() end -- v0.9.152
                else
                    for _, e in ipairs(party) do
                        if e.idx == cfg.selected_pawn_idx then
                            R.ping = { chara = e.chara, name = e.name, t_end = os.clock() + 3.0 }
                            R.last_pick = { chara = e.chara, t = os.clock() } -- dev52: for a co-op join
                            R.sel_label, R.sel_label_until = e.name, os.clock() + 4.0
                        end
                    end
                    log_msg("Selected Pawn slot: " .. tostring(cfg.selected_pawn_idx + 1))
                end
            end
        end
    end
    -- the marker's position, read on the game thread
    if R.ping then
        if os.clock() >= R.ping.t_end or not R.ping.chara then R.ping = nil
        else
            pcall(function()
                local x, y, z = brain_pos(R.ping.chara)
                if x then R.ping.pos = { x, y + 2.05, z } end
            end)
        end
    end
    pcall(R.jump_tick) -- 0.9.172: keys straight to the Arisen / pawn n
    if R.key_hit("warp_arisen") then
        warp_arisen_to_pawn()
    end
    if cfg.party_heal_key and R.key_hit("party_heal") then guarded_tick("party_heal", party_heal) end
    if R.key_hit("party_warp") then guarded_tick("party_warp", party_warp_to_me) end
    guarded_tick("verify_warps", verify_warps)
    -- v0.9.14 quick skills: Numpad 1-6 = the selected character uses skill 1-6. v0.9.90: also while a pawn is
    -- possessed, for the pick (the Arisen by default, or the pawn chosen with F7), never for the pawn being played.
    if cfg.quick_skills and not coop.active then
        for n = 1, 6 do
            if R.key_hit("skill" .. n) then
                if not state.active then
                    guarded_tick("quick_skill", function() quick_skill(n) end)
                elseif R.sel_kind == "pawn" and R.sel_idx ~= nil and R.sel_idx ~= state.pawn_idx then
                    local idx = R.sel_idx
                    guarded_tick("quick_skill", function() quick_skill(n, idx) end)
                else
                    brain.order_slot, brain.order_until = n, os.clock() + (cfg.arisen_brain_skill_hold or 0.5)
                    brain.order_bits = brain_flag("Skill" .. n) | brain_flag("Shift1") | brain_flag("Shift2")
                    log_msg("Arisen order: skill slot " .. n .. (brain.on and "" or " (his brain is off: nothing will happen)"))
                end
            end
        end
    end

    guarded_tick("cmd_file", poll_cmd_file)
    if R.cp_tick then guarded_tick("any_coop", R.cp_tick) end -- v0.9.171 co-op players: both on pawns, the second pawn

    if not state.active then
        guarded_tick("arisen_brain", brain_tick)
        guarded_tick("arisen_brain_dump", brain_dump)
        return
    end

    state.frames_since_start = state.frames_since_start + 1
    local is_first_frame = (state.frames_since_start == 1)
    if is_first_frame then
        write_trace("frame1: begin post-possession tick")
    end

    -- 2. Safety Guards: Auto-release if Pawn or Arisen is invalid, dead, downed, or in cutscene
    if not (state.pawn_chara and state.arisen_chara) then
        release_possession("character reference lost")
        return
    end
    -- v0.8.9: get_IsDown is also true for an ordinary knockdown from a hit, which released possession mid-fight
    -- (user report). Only release when dead, or knocked down with no HP left (the revivable "dying" state).
    if call(state.pawn_chara, "get_IsDead") then
        release_possession("possessed pawn dead")
        return
    end
    if call(state.pawn_chara, "get_IsDown") and (call(state.pawn_chara, "get_Hp") or 1) <= 0 then
        release_possession("possessed pawn downed (0 HP)")
        return
    end
    if call(state.arisen_chara, "get_IsDead") then
        release_possession("arisen died")
        return
    end
    if call(state.pawn_chara, "get_IsCutSceneMode") or call(state.arisen_chara, "get_IsCutSceneMode") then
        release_possession("cutscene started")
        return
    end

    -- v0.9.95: the lock-on must stay the played pawn's. Seen live: it had gone back to the Arisen mid-possession
    -- (telemetry lock_chara = ch100000_00), so the pawn's attacks looked for targets around the Arisen.
    if cfg.exp_rebind_lockon and not coop.active and state.arisen_lockon_ctrl and not brain.lock_swapped then
        pcall(function()
            local c = state.arisen_lockon_ctrl:get_field("Chara")
            if not same_obj(c, state.pawn_chara) then
                state.arisen_lockon_ctrl:set_field("Chara", state.pawn_chara)
                state.arisen_lockon_ctrl:call("clearLockOn")
                R.lock_fixes = (R.lock_fixes or 0) + 1
                log_msg("Lock-on had left the played pawn; given back (" .. tostring(R.lock_fixes) .. ")")
            end
        end)
    end

    -- 3. Keep Pawn AI suppressed & Camera locked onto Pawn
    if cfg.sub_suppress_ai then
        if is_first_frame then write_trace("frame1: set_pawn_ai_suppressed") end
        set_pawn_ai_suppressed(state.pawn_chara, state.pawn_obj, true, false)
    end
    if cfg.sub_camera_attach then
        if is_first_frame then write_trace("frame1: attach_camera_to") end
        attach_camera_to(state.pawn_go)
    end

    -- 4. In Mode 2 / Mode 3, run ActionSelector / Locomotion Puppeteer
    if cfg.control_mode == 2 or cfg.control_mode == 3 then
        if is_first_frame then write_trace("frame1: update_puppeteer_controls begin") end
        guarded_tick("update_puppeteer_controls", update_puppeteer_controls, is_first_frame)
        if is_first_frame then write_trace("frame1: update_puppeteer_controls done") end
    end

    -- 4b. Keep the native HUD pointed at the pawn
    guarded_tick("maintain_native_hud", maintain_native_hud)
    guarded_tick("flush_input_log", flush_input_log)

    -- 5. Update Arisen tether / auto-follow
    if is_first_frame then write_trace("frame1: update_arisen_tether") end
    guarded_tick("update_arisen_tether", update_arisen_tether)

    -- 6. v0.8 Arisen combat brain (decides; the PlayerInputProcessor hook applies it)
    guarded_tick("arisen_brain", brain_tick)
    guarded_tick("arisen_brain_dump", brain_dump)

    if is_first_frame then
        write_trace("frame1: SURVIVED full post-possession tick!")
    end
end)

-- Separate hook so the UI cache refreshes even while not possessing (the main tick returns early)
-- v0.9.66 (dev only) demonstration recorder. While nobody is possessed and the player plays the Arisen himself, log
-- every change of his action nodes together with the buttons held at that moment, to data/DPC_demo.json. Lets a
-- vocation without a pawn (Trickster) be learned from the player: which input leads to which action.
R.demo = { log = {}, last = "" }
function R.demo_tick()
    if not R.dev or coop.active then return end
    local now = os.clock()
    if now < (R.demo.next or 0) then return end
    R.demo.next = now + 0.05
    local cm = sdk.get_managed_singleton("app.CharacterManager")
    local ar = cm and cm:call("get_ManualPlayer")
    if not ar then return end
    -- v0.9.127: while a pawn is played, the pawn is recorded instead (its own input and actions), so the same
    -- thing done as the Arisen and as a pawn can be laid side by side (first use: climbing on a monster)
    local who = "Arisen"
    if state.active then
        if not state.pawn_chara then return end
        ar, who = state.pawn_chara, tostring(state.pawn_name or "pawn")
    end
    local fsm = ar:call("get_ActionManager"):get_field("Fsm")
    local n = tostring(fsm:call("getCurrentNodeName(System.UInt32)", 0)) .. " | " .. tostring(fsm:call("getCurrentNodeName(System.UInt32)", 1))
    local inp = ar:call("get_Input")
    local on = inp and inp:get_field("ButtonOnFlags") or 0
    local names = {}
    for name, flag in pairs(ACTION_FLAGS) do
        if type(flag) == "number" and flag ~= 0 and (on & flag) == flag then names[#names + 1] = name end
    end
    table.sort(names)
    local b = table.concat(names, "+")
    -- v0.9.123: the skill charge too (Human.IsSkillPreparing / RatePrepareSkill / IsSkillPrepared, skill state),
    -- to learn from the player how a charged Magick Archer skill is started. Rate in steps of 25 %.
    local prep = ""
    pcall(function()
        local hu = ar:call("get_Human")
        local ing = hu:call("get_IsSkillPreparing") == true
        local rate = tonumber(hu:call("get_RatePrepareSkill")) or 0
        local sk = hu:call("get_CustomSkillState") or 0
        if ing or sk ~= 0 then
            prep = string.format(" {skill %s%s %d%%%s}", tostring(sk), ing and " charging" or "", math.floor(rate * 4) * 25,
                hu:call("get_IsSkillPrepared") == true and " ready" or "")
        end
    end)
    if ar:call("get_IsClimbOnCharacter") == true then prep = prep .. " (on monster)" end
    local key = who .. "#" .. n .. "#" .. b .. prep
    if key == R.demo.last then return end
    R.demo.last = key
    local lg = R.demo.log
    if who ~= R.demo.who then R.demo.who = who; lg[#lg + 1] = string.format("%.2f ---- now recording: %s ----", now, who) end
    lg[#lg + 1] = string.format("%.2f [%s] %s%s", now, b, n, prep)
    if #lg > 400 then table.remove(lg, 1) end
    if now >= (R.demo.dump_next or 0) then
        R.demo.dump_next = now + 1.0
        local job = 0
        pcall(function() job = get_job(ar:call("get_Human"), ar) end)
        R.dump("DPC_demo.json", { version = VERSION, job = job, t = now, log = lg }, 1)
    end
end

re.on_pre_application_entry("UpdateBehavior", function()
    if R.world_now == false then return end -- v0.9.113 world guard (set by the main tick just before this one)
    guarded_tick("demo", R.demo_tick)
    guarded_tick("arisen_guard", R.guard_tick)
    guarded_tick("refresh_ui_cache", refresh_ui_cache)
    guarded_tick("spawner", spawner_tick)
    guarded_tick("test_hotkeys", test_hotkeys)
end)

-- Always restore cleanly when scripts are reloaded/reset in REFramework
-- ----------------------------------------------------------------------------
-- v0.9.170 (dev, untested) "Whoever you play is the player": sound, hit-stop and the big-kill slow-motion.
-- See claude/dpc-player-feel-plan.md. Approach B (per-character settings: the Wwise sound settings) and C (scoped
-- swaps: the game's "who is the player" field, CharacterManager.<ManualPlayer>k__BackingField, is set to the played
-- pawn only for the length of one game call, then put back; the method DD2PartySwitcher uses, reused with credit).
-- Never the full swap (A): PartySwitcher's full swap logged 8+ crashes and DPC's own Mode 3 swap crashed.
-- Every part is its own switch (cfg.pf_*) so a test can turn them on one at a time; all off = 0.9.169.
-- ----------------------------------------------------------------------------
R.pf = { n = {}, hooked = {} }
R.pf_played = function() -- the character one player plays alone (not co-op: there player 1 still plays the Arisen)
    if state.active and not coop.active and state.pawn_chara and state.arisen_chara then return state.pawn_chara end
    return nil
end
R.pf_count = function(k)
    if not cfg.pf_scope_log then return end
    local n = R.pf.n
    n[k] = (n[k] or 0) + 1
end

-- Scoped ManualPlayer swap. While one is open R.mp_swapped holds the real player; a nested call (one of these game
-- methods calling another) does not swap again. DPC's own code that must know the real Arisen during a window
-- calls R.real_player().
R.MP_FIELD = "<ManualPlayer>k__BackingField"
R.real_player = function()
    if R.mp_swapped then return R.mp_swapped.old end
    local cm = sdk.get_managed_singleton("app.CharacterManager")
    return cm and cm:call("get_ManualPlayer")
end
R.mp_pre = function(key)
    local st = thread.get_hook_storage()
    st.mp = nil
    if R.mp_swapped then return end
    local p = R.pf_played()
    if not p then return end
    local cm = sdk.get_managed_singleton("app.CharacterManager")
    if not cm then return end
    local old = cm:get_field(R.MP_FIELD)
    -- only when the game's player is the Arisen we know (never stack on someone else's swap)
    if not old or old:get_address() ~= state.arisen_chara:get_address() then return end
    cm:set_field(R.MP_FIELD, p)
    R.mp_swapped = { cm = cm, old = old, key = key }
    st.mp = true
    R.pf_count(key)
end
R.mp_post = function(retval)
    local st = thread.get_hook_storage()
    if st and st.mp then
        st.mp = nil
        local sw = R.mp_swapped
        R.mp_swapped = nil
        if sw then pcall(sw.cm.set_field, sw.cm, R.MP_FIELD, sw.old) end
    end
    return retval
end
-- hooks are installed the first time their switch is on, and stay (they do nothing while it is off)
R.pf_hook_group = function(group, list, cfg_key)
    if R.pf.hooked[group] then return end
    R.pf.hooked[group] = {}
    for _, e in ipairs(list) do
        local td = sdk.find_type_definition(e[1])
        local m = td and td:get_method(e[2])
        if m then
            local key = e[1]:gsub("^app%.", "") .. "." .. e[2]:gsub("%(.*", "")
            local ok = pcall(sdk.hook, m, function(args)
                if cfg[cfg_key] then R.mp_pre(key) end
            end, R.mp_post)
            R.pf.hooked[group][#R.pf.hooked[group] + 1] = key .. (ok and "" or " (hook failed)")
        else
            R.pf.hooked[group][#R.pf.hooked[group] + 1] = e[1] .. "." .. e[2] .. " (not found)"
        end
    end
    log_msg("Player feel: " .. group .. " hooks: " .. table.concat(R.pf.hooked[group], ", "))
end
R.PF_HOOKS = {
    space = { { "app.SoundSpaceManager", "updateFieldAIArea" }, { "app.SoundSpaceManager", "updateSemiEnvPhase1" },
              { "app.SoundSpaceManager", "<updateGlobalParam>g__updatePlayerPosY|259_0" } },
    hitstop = { { "app.HitController", "getHitStopTime" } },
    slow = { { "app.Ch200000", "isEnableWorldSlow" }, { "app.Ch200000", "checkDieWorldSlow" },
             { "app.Ch200000", "requestDieWorldSlow" }, { "app.Ch261000", "isEnableWorldSlow" },
             { "app.Ch255000", "callDieWorldSlow" } },
}

-- Sound part 1: the Wwise sound settings of a character (category Player / Pawn, its RTPC, "treated as player").
R.pf_wc = function(chara)
    local go = chara and chara:call("get_GameObject")
    return go and go:call("getComponent(System.Type)", sdk.typeof("app.WwiseCharacter"))
end
R.pf_wc_get = function(w)
    return { w:call("get_CharacterCategory"), w:call("get_CharacterRTPC"), w:call("get_IsRTPCTreatedAsPlayer") }
end
R.pf_wc_set = function(w, v)
    w:call("set_CharacterCategory", v[1])
    w:call("set_CharacterRTPC", v[2] + 0.0)
    w:call("set_IsRTPCTreatedAsPlayer", v[3])
end
R.pf_voice_restore = function(why)
    local v = R.pf.voice
    if not v then return end
    R.pf.voice = nil
    pcall(R.pf_wc_set, v.wa, v.a)
    pcall(R.pf_wc_set, v.wp, v.p)
    log_msg("Player feel: sound settings back (" .. tostring(why) .. ")")
end
R.pf_voice_tick = function(p)
    local v = R.pf.voice
    if v and (not p or v.paddr ~= p:get_address()) then R.pf_voice_restore("pawn changed"); v = nil end
    if not p then return end
    if not v then
        local wa, wp = R.pf_wc(state.arisen_chara), R.pf_wc(p)
        if not (wa and wp) then R.pf.voice_err = "no WwiseCharacter"; return end
        v = { wa = wa, wp = wp, a = R.pf_wc_get(wa), p = R.pf_wc_get(wp), paddr = p:get_address(), next_t = 0 }
        R.pf.voice = v
        R.pf.voice_seen = string.format("Arisen %s/%.2f/%s, pawn %s/%.2f/%s", tostring(v.a[1]), v.a[2] or -1, tostring(v.a[3]),
            tostring(v.p[1]), v.p[2] or -1, tostring(v.p[3]))
        log_msg("Player feel: sound settings swapped (" .. R.pf.voice_seen .. ")")
    end
    local now = os.clock()
    if now < v.next_t then return end
    v.next_t = now + 0.5
    -- written again twice a second in case the game sets them back (counted, so a test shows whether it does)
    local cur = R.pf_wc_get(v.wp)
    if cur[1] ~= v.a[1] or cur[3] ~= v.a[3] then R.pf_count("sound settings rewritten") end
    R.pf_wc_set(v.wp, v.a)
    R.pf_wc_set(v.wa, v.p)
end

-- Sound part 2: where loudness by distance is worked out from (via.simplewwise.Driver; static).
R.pf_drv = function()
    R.pf.drv = R.pf.drv or sdk.find_type_definition("via.simplewwise.Driver")
    return R.pf.drv
end
R.pf_listener_tick = function(p)
    local mode = p and (cfg.pf_sound_listener or 0) or 0
    local drv = R.pf_drv()
    if not drv then return end
    if mode == 0 then
        if R.pf.dec_old ~= nil then
            pcall(function() drv:get_method("set_CalcDistanceDecayAtPlayerPos(System.Boolean)"):call(nil, R.pf.dec_old) end)
            R.pf.dec_old = nil
            log_msg("Player feel: loudness by distance back to the game's")
        end
        return
    end
    if R.pf.dec_old == nil then
        R.pf.dec_old = drv:get_method("get_CalcDistanceDecayAtPlayerPos"):call(nil) == true
        log_msg("Player feel: loudness by distance from " .. (mode == 1 and "the camera" or "the played pawn") .. " (game had " .. tostring(R.pf.dec_old) .. ")")
    end
    local ear = nil
    if mode == 1 then local oke, e = pcall(R.pf_coop_ear); ear = oke and e or nil end
    R.pf.ear_on = ear ~= nil
    drv:get_method("set_CalcDistanceDecayAtPlayerPos(System.Boolean)"):call(nil, mode == 2 or ear ~= nil)
    if mode == 2 or ear then R.pf_listener_pos(p) end
end
-- 0.9.171: co-op with "the camera": when the camera pulls back to keep both players in view, loudness by distance
-- from the camera made everything quiet. The sound engine works out loudness from one point and left / right from
-- the camera (the game's own split: loudness at the player, panning at the camera). So loudness is worked out from
-- an "ear" on the camera's line of sight, pf_sound_ear_dist from the middle of the two players: both are heard in
-- proportion, as a close camera on that middle would hear them, and panning still follows the camera.
R.pf_coop_ear = function()
    if not cfg.pf_sound_coop_ear then return nil end
    local pl = R.players()
    local a, b = pl[1], pl[2]
    if not (a and b) then return nil end
    local pa = a:call("get_GameObject"):call("get_Transform"):call("get_Position")
    local pb = b:call("get_GameObject"):call("get_Transform"):call("get_Position")
    local cam = sdk.get_primary_camera()
    local cp = cam and cam:call("get_GameObject"):call("get_Transform"):call("get_Position")
    if not (pa and pb and cp) then return nil end
    local mx, my, mz = (pa.x + pb.x) * 0.5, (pa.y + pb.y) * 0.5 + 1.5, (pa.z + pb.z) * 0.5
    local dx, dy, dz = cp.x - mx, cp.y - my, cp.z - mz
    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
    local base = math.max(1.0, cfg.pf_sound_ear_dist or 5.0)
    local k = (d > base) and (base / d) or 1.0
    R.pf.ear_cam_d = d
    return Vector3f.new(mx + dx * k, my + dy * k, mz + dz * k)
end
R.pf_listener_pos = function(p) -- also run late in the frame (below): the game may write its own player's position
    p = p or R.pf_played()
    if not p then return end
    local mode = cfg.pf_sound_listener or 0
    local pos
    if mode == 2 then
        pos = p:call("get_GameObject"):call("get_Transform"):call("get_Position")
    elseif mode == 1 and R.pf.ear_on then
        local oke, e = pcall(R.pf_coop_ear)
        pos = oke and e or nil
    end
    if not pos then return end
    local drv = R.pf_drv()
    drv:get_method("set_PlayerPositionForDistanceDecay(via.vec3)"):call(nil, pos)
end

-- dev5: skills with a slow-motion moment (Riotous Fury, ...). Their app.SlowAction has PlayerOnly set, and its start()
-- checks the character's CharacterID against the Arisen's (ch000000_00, 0xac525575 at Character+0xc4c; read from
-- the disassembly of SlowAction.start, 2026-11-19), not who the player is. So it never fires for a played pawn, and
-- would still fire for the Arisen. For a PlayerOnly action whose character is the played pawn, PlayerOnly is off for
-- the length of start() (the game then takes its player path); for the Arisen's while a pawn is played,
-- EnableRequestSlow is cleared after start(). The character is cached on the action, so the very first use of a
-- skill by a given pawn may still miss (the cache is filled inside that start()).
R.pf_slow_hook = function()
    if R.pf.hooked.skillslow then return end
    R.pf.hooked.skillslow = {}
    local td = sdk.find_type_definition("app.SlowAction")
    local m = td and td:get_method("start")
    if not m then R.pf.hooked.skillslow[1] = "SlowAction.start not found"; return end
    sdk.hook(m, function(args)
        local st = thread.get_hook_storage()
        st.sl = nil
        if not cfg.pf_skill_slow then return end
        local p = R.pf_played()
        if not p then return end
        local a = sdk.to_managed_object(args[2])
        if not a or a:get_field("PlayerOnly") ~= true then return end
        local ch = a:get_field("<CachedCharacter>k__BackingField")
        local who = ch and ch:get_address() or 0
        if who == p:get_address() then
            a:set_field("PlayerOnly", false)
            st.sl = { a = a, restore = true }
            R.pf_count("skill slow-mo for the played pawn")
        elseif state.arisen_chara and who == state.arisen_chara:get_address() then
            st.sl = { a = a, arisen = true }
        elseif who == 0 then
            st.sl = { a = a, first = true }
        end
    end, function(r)
        local st = thread.get_hook_storage()
        local s = st.sl
        st.sl = nil
        if s then
            pcall(function()
                if s.restore then s.a:set_field("PlayerOnly", true) end
                if s.arisen then
                    s.a:set_field("EnableRequestSlow", false)
                    R.pf_count("skill slow-mo held back for the Arisen")
                end
                if s.first then -- the character was only cached inside this start(): set the flag the game would have
                    local ch = s.a:get_field("<CachedCharacter>k__BackingField")
                    local p = R.pf_played()
                    local who = ch and ch:get_address() or 0
                    if p and who == p:get_address() then
                        s.a:set_field("EnableRequestSlow", true)
                        R.pf_count("skill slow-mo first use (flag set)")
                    elseif state.arisen_chara and who == state.arisen_chara:get_address() then
                        s.a:set_field("EnableRequestSlow", false)
                    end
                end
            end)
        end
        return r
    end)
    R.pf.hooked.skillslow[1] = "SlowAction.start"
    log_msg("Player feel: skill slow-motion hook on")
end

R.pf_tick = function()
    if R.world_now == false then return end
    if cfg.pf_skill_slow then pcall(R.pf_slow_hook) end
    local p = R.pf_played()
    if cfg.pf_sound_space then R.pf_hook_group("space", R.PF_HOOKS.space, "pf_sound_space") end
    if cfg.pf_hitstop then R.pf_hook_group("hitstop", R.PF_HOOKS.hitstop, "pf_hitstop") end
    if cfg.pf_world_slow then R.pf_hook_group("slow", R.PF_HOOKS.slow, "pf_world_slow") end
    local ok, err = pcall(R.pf_voice_tick, cfg.pf_sound_voice and p or nil)
    if not ok then R.pf.voice_err = tostring(err) end
    ok, err = pcall(R.pf_listener_tick, p)
    if not ok then R.pf.listener_err = tostring(err) end
end
-- ----------------------------------------------------------------------------
-- 0.9.172 co-op sound listener. With the camera pulled back to keep the players in view, sounds cut off hard (the tester,
-- 2026-11-20): also in classic co-op, where loudness is already worked out at the Arisen, so it is the distance from
-- the LISTENER (soundlib.SoundListener on MainCamera; Driver.getListenerPosition(0) = the camera's position) that
-- drops them. The listener is moved toward the players along the camera's line of sight, to pf_sound_ear_dist from the
-- middle of all players; its orientation (left / right) stays the camera's.
-- How the game reads SoundListener._Offset (world or camera space; or whether it reads it at all) is not known, so
-- the way is found in play: each candidate is tried for 20 frames while Driver.getListenerPosition is compared with
-- the target point; the first that lands within 1 m is kept. Candidates: _Offset in world space, _Offset in the
-- camera's space, then the component's own setListenerPosition(Transform, vec3) after its lateUpdate (world, camera
-- space). If none lands, nothing more is written ("no way found") and the offset is put back.
-- 0.9.172-dev6, from coop-sound-1 (2026-11-20): setListenerPosition(Transform, vec3) puts the listener AT the vec3
-- (an absolute position: an offset there sent it ~170 m off), and _Offset in camera space moved it the right
-- distance the opposite way (6.0 m off on a 3.1 m move). Candidates now: the setter with the target point, the
-- camera-space offset reversed, then the two that did not land, in case a camera angle tells them apart.
R.lis = { ways = { "set_abs", "off_local_neg", "off_world", "off_local" }, way_i = 1, found = nil, failed = false,
    n = 0, err_sum = 0.0, active = false, want = nil, errs = 0 }
R.lis_comp = function()
    local L = R.lis
    if L.comp and (os.clock() - (L.comp_t or 0)) < 5.0 then return L.comp end
    L.comp_t = os.clock()
    L.comp = nil
    pcall(function()
        local sm = sdk.get_native_singleton("via.SceneManager")
        local scene = sdk.call_native_func(sm, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
        local arr = scene:call("findComponents(System.Type)", sdk.typeof("soundlib.SoundListener"))
        local n = arr and (arr:call("get_Count") or arr:call("get_Length")) or 0
        for i = 0, n - 1 do
            local c = arr:call("get_Item", i)
            if c and (c:get_field("_ListenerIdx") or 0) == 0 then L.comp = c break end
        end
    end)
    return L.comp
end
R.lis_dot = function(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
-- every frame, before the game's update: where the listener should be (nil = leave it at the camera)
R.lis_target = function()
    if not (cfg.coop_listener_move and R.world_now ~= false) then return nil end
    if not ((coop.active and state.active) or (R.cp and R.cp.on)) then return nil end
    local pl = R.players()
    local n, sx, sy, sz = 0, 0.0, 0.0, 0.0
    for _, ch in pairs(pl) do
        local okp, p = pcall(function() return ch:call("get_GameObject"):call("get_Transform"):call("get_Position") end)
        if okp and p then n = n + 1; sx, sy, sz = sx + p.x, sy + p.y, sz + p.z end
    end
    -- (players 3+ are in R.players)
    if n < 2 then return nil end
    local mx, my, mz = sx / n, sy / n + 1.5, sz / n
    local tr = sdk.get_primary_camera():call("get_GameObject"):call("get_Transform")
    local cp = tr:call("get_Position")
    local dx, dy, dz = mx - cp.x, my - cp.y, mz - cp.z
    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
    local base = math.max(1.0, cfg.pf_sound_ear_dist or 5.0)
    if d <= base + 0.5 or d > 120.0 then return nil end -- close enough already; or the camera is somewhere else (a menu)
    local k = (d - base) / d
    local w = { x = dx * k, y = dy * k, z = dz * k } -- world offset from the camera
    return { w = w, wlen = d - base, cam = cp, tr = tr, ear = { x = cp.x + w.x, y = cp.y + w.y, z = cp.z + w.z }, d = d }
end
R.lis_local = function(tr, w)
    local ax, ay, az = tr:call("get_AxisX"), tr:call("get_AxisY"), tr:call("get_AxisZ")
    return Vector3f.new(R.lis_dot(w, ax), R.lis_dot(w, ay), R.lis_dot(w, az))
end
R.lis_way = function() local L = R.lis; return L.found or (not L.failed and L.ways[L.way_i]) or nil end
R.lis_pre = function(args) -- before SoundListener.lateUpdate
    local L = R.lis
    -- the component the game is updating right now (never a cached one that a load may have destroyed)
    local c = args and args[2] and sdk.to_managed_object(args[2]) or nil
    if not c then return end
    if (c:get_field("_ListenerIdx") or 0) ~= 0 then return end
    if L.comp_addr ~= c:get_address() then L.comp_addr, L.off0, L.wrote = c:get_address(), nil, false end
    L.comp = c
    local t, way = L.want, R.lis_way()
    if L.off0 == nil then local o = c:get_field("_Offset"); L.off0 = o and Vector3f.new(o.x, o.y, o.z) or Vector3f.new(0.0, 0.0, 0.0) end
    if not (t and way) then
        if L.wrote then c:set_field("_Offset", L.off0); L.wrote = false end
        return
    end
    if way == "off_world" then c:set_field("_Offset", Vector3f.new(t.w.x, t.w.y, t.w.z)); L.wrote = true
    elseif way == "off_local" then c:set_field("_Offset", R.lis_local(t.tr, t.w)); L.wrote = true
    elseif way == "off_local_neg" then
        local o = R.lis_local(t.tr, t.w)
        c:set_field("_Offset", Vector3f.new(-o.x, -o.y, -o.z)); L.wrote = true
    elseif L.wrote then c:set_field("_Offset", L.off0); L.wrote = false end
end
R.lis_post = function() -- after SoundListener.lateUpdate (the component its pre-hook saw this frame)
    local L = R.lis
    local c = L.comp
    local t, way = L.want, R.lis_way()
    if not (c and t and way) then return end
    if way == "set_abs" then
        c:call("setListenerPosition(via.Transform, via.vec3)", t.tr, Vector3f.new(t.ear.x, t.ear.y, t.ear.z))
    end
end
-- measured once a frame (the engine's listener may lag a frame: compared with last frame's target)
R.lis_measure = function()
    local L = R.lis
    local t = L.want_prev
    L.want_prev = L.want
    -- 0.9.172-dev6: loudness from the same point (the game works it out from the Arisen in classic co-op, so a far
    -- player's swings stayed quiet). Late in the frame, after the game wrote its own player position.
    if L.want and cfg.coop_listener_loudness then
        pcall(function()
            local d = R.pf_drv()
            d:get_method("set_CalcDistanceDecayAtPlayerPos(System.Boolean)"):call(nil, true)
            d:get_method("set_PlayerPositionForDistanceDecay(via.vec3)"):call(nil, Vector3f.new(L.want.ear.x, L.want.ear.y, L.want.ear.z))
            L.loud = true
        end)
    elseif L.loud then
        L.loud = false -- the game (or the played-pawn setting) writes its own point again from the next frame
    end
    if not t then return end
    local drv = R.pf_drv()
    local lp = drv and drv:get_method("getListenerPosition"):call(nil, 0)
    if not lp then return end
    local ex, ey, ez = lp.x - t.ear.x, lp.y - t.ear.y, lp.z - t.ear.z
    local err = math.sqrt(ex * ex + ey * ey + ez * ez)
    local cx, cy, cz = lp.x - t.cam.x, lp.y - t.cam.y, lp.z - t.cam.z
    L.err, L.from_cam = err, math.sqrt(cx * cx + cy * cy + cz * cz)
    if L.found or L.failed then
        if L.found and (t.wlen or 0) >= 3.0 then
            -- the way found keeps landing? (a camera lined up with the world's axes cannot tell world from camera
            -- space apart; it shows once the camera turns): 30 frames in a row off target -> find the way again
            if err > math.max(1.5, 0.15 * t.wlen) then L.bad_run = (L.bad_run or 0) + 1 else L.bad_run = 0 end
            if L.bad_run >= 30 then
                log_msg(string.format("Co-op sound: %s stopped landing (%.1f m off), finding the way again", L.found, err))
                L.drifts = (L.drifts or 0) + 1
                local was = L.found
                L.found, L.bad_run, L.n, L.err_sum, L.wsum = nil, 0, 0, 0.0, 0.0
                L.way_i = 1
                for i, w in ipairs(L.ways) do if w == was then L.way_i = (i % #L.ways) + 1 end end
                L.tried = { "(again after " .. was .. ")" }
                L.left = #L.ways -- tries before giving up
            end
        end
        return
    end
    -- a candidate that throws the listener far away is dropped at once (do not leave it there 20 frames)
    if err > 30.0 then L.n, L.err_sum = 19, err * 19 end
    -- only frames where the listener has to move a fair way tell the candidates apart
    if (t.wlen or 0) < 3.0 and err <= 30.0 then return end
    L.n, L.err_sum = L.n + 1, L.err_sum + err
    L.wsum = (L.wsum or 0.0) + t.wlen
    if L.n >= 20 then
        local avg = L.err_sum / L.n
        local wavg = L.wsum / L.n
        L.wsum = 0.0
        L.tried = L.tried or {}
        L.tried[#L.tried + 1] = string.format("%s %.1f of %.1f m", L.ways[L.way_i], avg, wavg)
        if avg < math.max(1.0, 0.15 * wavg) then
            L.found, L.left = L.ways[L.way_i], nil
            log_msg(string.format("Co-op sound: listener moved by %s (off by %.2f m on average)", L.found, avg))
        else
            L.way_i = L.way_i + 1
            if L.left then -- a second round after a drift: wraps round the list, each way once
                L.left = L.left - 1
                if L.way_i > #L.ways then L.way_i = 1 end
            end
            if (L.left and L.left <= 0) or (not L.left and L.way_i > #L.ways) then
                L.failed = true
                log_msg("Co-op sound: no way found to move the listener (" .. table.concat(L.tried, ", ") .. ")")
            end
        end
        L.n, L.err_sum = 0, 0.0
    end
end
R.lis_hook = function()
    local L = R.lis
    if L.hooked then return end
    L.hooked = true
    local td = sdk.find_type_definition("soundlib.SoundListener")
    local m = td and td:get_method("lateUpdate")
    if not m then L.hook_err = "SoundListener.lateUpdate not found"; return end
    sdk.hook(m, function(args)
        local ok, e = pcall(R.lis_pre, args)
        if not ok then L.errs = L.errs + 1; L.err_msg = tostring(e) end
    end, function(retval)
        local ok, e = pcall(R.lis_post)
        if not ok then L.errs = L.errs + 1; L.err_msg = tostring(e) end
        return retval
    end)
end
R.lis_tick = function() -- before UpdateBehavior, every frame
    local L = R.lis
    local okt, t = pcall(R.lis_target)
    L.want = okt and t or nil
    if not okt then L.target_err = tostring(t) end
    L.active = L.want ~= nil
    L.d = L.want and L.want.d or nil
    if (L.want or L.wrote) and cfg.coop_listener_move then pcall(R.lis_hook) end
end
re.on_application_entry("LateUpdateBehavior", function() if R.lis.want or R.lis.want_prev then pcall(R.lis_measure) end end)
re.on_pre_application_entry("UpdateBehavior", function() pcall(R.lis_tick) end)

R.pf_restore_all = function(why)
    pcall(function() -- 0.9.172: the listener's offset back (not during a load: the object may be gone; a new one starts clean)
        local L = R.lis
        local loading = tostring(why or ""):find("loading") ~= nil
        if L.wrote and L.comp and L.off0 and not loading and sdk.is_managed_object(L.comp) then L.comp:set_field("_Offset", L.off0) end
        L.wrote = false
        if loading then L.comp, L.comp_addr = nil, nil end
        L.want, L.want_prev = nil, nil
    end)
    pcall(R.pf_voice_restore, why)
    pcall(R.pf_listener_tick, nil)
    if R.mp_swapped then -- a window left open (should not happen): put the Arisen back
        local sw = R.mp_swapped
        R.mp_swapped = nil
        pcall(sw.cm.set_field, sw.cm, R.MP_FIELD, sw.old)
    end
end
re.on_pre_application_entry("UpdateBehavior", function() pcall(R.pf_tick) end)
re.on_application_entry("LateUpdateBehavior", function() pcall(R.pf_listener_pos) end)

-- ----------------------------------------------------------------------------
-- v0.9.170 (dev) Mod API, layers 1, 2 and 4 (queries, events, claims, option overrides). Spec:
-- claude/dpc-mod-api.md. Every foreign function runs in pcall; one that fails 5 times within 10 s is switched off
-- and shown under "Connected mods". Callbacks run on the game thread (DPC fires events from there).
-- ----------------------------------------------------------------------------
R.api = { regs = {}, on = {}, claims = {}, overrides = {}, next_id = 1 }
R.API_FEATURES = { events = true, claims = true, overrides = true, players = true, coop2pads = true,
    players_n = true, characters = true, -- 1.1 (0.9.172): players 3+, characters offered by other mods
    control = true } -- 1.2 (0.9.173): possess / release_pawn
R.api_run = function(reg, ...)
    if reg.off or reg.disabled then return false end
    local t0 = os.clock()
    local ok, res = pcall(reg.fn, ...)
    local dt = os.clock() - t0
    reg.calls = (reg.calls or 0) + 1
    reg.cost = (reg.cost or 0) + dt
    if not ok then
        reg.err = tostring(res)
        local now = os.clock()
        reg.fails = reg.fails or {}
        reg.fails[#reg.fails + 1] = now
        while reg.fails[1] and now - reg.fails[1] > 10.0 do table.remove(reg.fails, 1) end
        if #reg.fails >= 5 then
            reg.off = true
            log_msg(string.format("Mod API: %s's %s switched off after 5 errors in 10 s: %s", reg.mod, reg.what, reg.err))
            R.note = { text = "A connected mod (" .. reg.mod .. ") had errors; DPC switched it off", t_end = os.clock() + 4.0 }
            if reg.on_off then pcall(reg.on_off) end
        end
        return false
    end
    return true, res
end
R.api_reg = function(kind, what, fn, opts)
    opts = type(opts) == "table" and opts or {}
    local reg = { id = R.api.next_id, kind = kind, what = what, fn = fn, mod = tostring(opts.mod or "unnamed mod"), opts = opts }
    R.api.next_id = R.api.next_id + 1
    R.api.regs[#R.api.regs + 1] = reg
    return reg
end
R.api_fire = function(ev, payload)
    local list = R.api.on[ev]
    if not list then return end
    for _, reg in ipairs(list) do R.api_run(reg, payload or {}) end
end
R.api_drop = function(reg)
    if not reg then return end
    reg.gone = true
    for i, r in ipairs(R.api.regs) do if r == reg then table.remove(R.api.regs, i); break end end
    if reg.kind == "event" then
        local list = R.api.on[reg.what] or {}
        for i, r in ipairs(list) do if r == reg then table.remove(list, i); break end end
    elseif reg.kind == "claim" and R.api.claims[reg.what] == reg then
        R.api.claims[reg.what] = nil
    elseif reg.kind == "override" and R.api.overrides[reg.what] == reg then
        R.api.overrides[reg.what] = nil
        if reg.saved_set then cfg[reg.what] = reg.saved end
    end
end
-- true when another mod holds this resource (DPC then skips its own version of it)
R.api_claimed = function(res)
    local c = R.api.claims[res]
    return c ~= nil and not c.off and not c.disabled
end

-- players: who controls whom. Single player: player 1 plays the Arisen, or the pawn while one is played.
-- Co-op: player 1 the Arisen, player 2 the pawn.
R.players = function()
    local out = {}
    if state.active and state.pawn_chara then
        if coop.active then
            out[1], out[2] = state.arisen_chara, state.pawn_chara
            if R.cp and R.cp.on and R.cp.arisen_side == 2 then out[1], out[2] = state.pawn_chara, state.arisen_chara end -- v0.9.171
        else
            out[1] = state.pawn_chara
            if R.s2 and R.s2.active then out[2] = R.s2.chara end -- v0.9.171: both on pawns
            if R.cp and R.cp.on and R.cp.ar2 then out[2] = state.arisen_chara end -- 0.9.171: player 2 on the Arisen
        end
    else
        local okc, ar = pcall(R.real_player)
        out[1] = okc and ar or nil
    end
    if R.np then for _, e in ipairs(R.np_charas()) do out[e.player] = e.chara end end -- 0.9.172: players 3+
    return out
end
R.api_char_info = function(ch)
    if not ch then return nil end
    local info = { chara = ch }
    local np_sl = nil
    if R.np then for _, sl in pairs(R.np.slots) do if sl.active and ch:get_address() == (sl.chara_addr or -1) then np_sl = sl end end end
    if np_sl then -- 0.9.172: players 3+
        info.name, info.job, info.slot = np_sl.name, np_sl.job, np_sl.idx
        info.job_name, info.is_main_pawn, info.is_arisen = JOB_NAMES[np_sl.job], np_sl.idx == 0, false
        info.player = np_sl.player
    elseif R.s2 and R.s2.active and ch:get_address() == (R.s2.chara_addr or -1) then -- v0.9.171: player 2's second pawn
        info.name, info.job, info.slot = R.s2.name, R.s2.job, R.s2.idx
        info.job_name, info.is_main_pawn, info.is_arisen = JOB_NAMES[R.s2.job], R.s2.idx == 0, false
    elseif state.active and state.pawn_chara and ch:get_address() == state.pawn_chara:get_address() then
        info.name, info.job, info.slot = state.pawn_name, state.pawn_job, state.pawn_idx
        info.job_name, info.is_main_pawn, info.is_arisen = JOB_NAMES[state.pawn_job], state.pawn_idx == 0, false
    else
        info.is_arisen, info.name = true, "Arisen"
        pcall(function() info.job = ch:call("get_Human"):call("get_JobContext"):get_field("CurrentJob") end)
        info.job_name = info.job and JOB_NAMES[info.job]
    end
    return info
end
R.api_who = function() -- the payload name of the character the last event is about
    return state.pawn_name
end

R.api_build = function()
    local api = { version = "1.2", major = 1, minor = 2, dpc_version = VERSION }
    api.has = function(f) return R.API_FEATURES[f] == true end
    api.state = function()
        local pl = R.players()
        local ar = state.arisen_chara or R.real_player()
        local ar_info = R.api_char_info(ar)
        return {
            active = state.active == true,
            played = state.active and R.api_char_info(state.pawn_chara) or nil,
            arisen = { name = ar_info and ar_info.name, job = ar_info and ar_info.job, chara = ar, ai_on = brain.on == true },
            coop = { active = coop.active == true or (R.cp and R.cp.on) == true, two_pads = R.tp_on() == true,
                     players = (function()
                         local t = {}
                         for i, c in pairs(pl) do t[i] = R.api_char_info(c) end
                         return t
                     end)() },
            transition = { running = R.cine ~= nil, style = cfg.switch_cine_profile },
        }
    end
    api.played = function(p) return R.players()[p or 1] end
    -- 1.1: every player: { player, chara, info, controller_lost }, in player order
    api.players = function()
        local out = {}
        local pl = R.players()
        local ns = {}
        for i in pairs(pl) do ns[#ns + 1] = i end
        table.sort(ns)
        for _, i in ipairs(ns) do
            local sl = R.np and R.np.slots[i]
            out[#out + 1] = { player = i, chara = pl[i], info = R.api_char_info(pl[i]), controller_lost = (sl and sl.pad_lost ~= nil) or false }
        end
        return out
    end
    api.players_max = function() return cfg.coop_max_players or 8 end
    -- 1.1: offer a character the party does not hold (one your mod spawned) to players 3+. Returns a handle;
    -- DPC_API.remove_character(h) takes it back (a player on it lets go first).
    api.add_character = function(chara, opts)
        if not (chara and sdk.is_managed_object(chara)) then return nil, "not a character" end
        opts = type(opts) == "table" and opts or {}
        local h = { chara = chara, name = opts.name, mod = tostring(opts.mod or "a mod") }
        table.insert(R.np.pool, h)
        log_msg("Mod API: " .. h.mod .. " offers " .. tostring(h.name or "a character") .. " to players 3+")
        return h
    end
    api.remove_character = function(h)
        if not h or h.gone then return end
        h.gone = true
        for _, sl in pairs(R.np.slots) do
            if sl.active and sl.chara and h.chara and sl.chara:get_address() == h.chara:get_address() then pcall(R.s2_stop, "character taken back", sl) end
        end
    end
    api.player_of = function(ch)
        if not ch then return nil end
        local a = ch:get_address()
        for i, c in pairs(R.players()) do if c and c:get_address() == a then return i end end
        return nil
    end
    api.is_played = function(ch) return api.player_of(ch) ~= nil end
    api.arisen_ai = function()
        local t = brain.target
        local tn = nil
        pcall(function() tn = t and t:call("get_GameObject"):call("get_Name") end)
        return { on = brain.on == true, target = t, target_name = tn, mode = cfg.control_mode }
    end
    api.party = function()
        local out = {}
        local pl = R.players()
        local okp, party = pcall(get_party)
        if not okp then return out end
        for _, e in ipairs(party) do
            local who = "ai"
            for i, c in pairs(pl) do if c and e.chara and c:get_address() == e.chara:get_address() then who = "player" .. i end end
            out[#out + 1] = { slot = e.idx, name = e.name, job = e.job, job_name = e.job_name, chara = e.chara, controlled_by = who }
        end
        return out
    end
    api.option = function(k)
        local v = cfg[k]
        if type(v) == "table" then return nil end
        return v
    end
    api.on = function(ev, fn, opts)
        if type(fn) ~= "function" then return nil end
        local reg = R.api_reg("event", tostring(ev), fn, opts)
        R.api.on[reg.what] = R.api.on[reg.what] or {}
        table.insert(R.api.on[reg.what], reg)
        return reg
    end
    api.off = function(h) R.api_drop(h) end
    -- claims: one owner per resource; a higher priority takes it over (the earlier owner's on_lost runs)
    api.claim = function(res, opts)
        opts = type(opts) == "table" and opts or {}
        res = tostring(res)
        local cur = R.api.claims[res]
        if cur and not cur.off and (cur.opts.priority or 0) >= (opts.priority or 0) then return nil, "held by " .. cur.mod end
        if cur then
            R.api.claims[res] = nil
            if type(cur.opts.on_lost) == "function" then R.api_run({ fn = cur.opts.on_lost, mod = cur.mod, what = "on_lost" }) end
            R.api_drop(cur)
        end
        local reg = R.api_reg("claim", res, function() end, opts)
        R.api.claims[res] = reg
        reg.release = function() R.api_drop(reg) end
        log_msg("Mod API: " .. reg.mod .. " claimed " .. res)
        if res == "camera.transition" then pcall(R.cine_stop) end
        return reg
    end
    api.release = function(h) R.api_drop(h) end
    -- a DPC setting for this session only; never saved to the player's config
    api.override = function(key, value, opts)
        key = tostring(key)
        if cfg[key] == nil or type(cfg[key]) == "table" then return nil, "no such setting" end
        local cur = R.api.overrides[key]
        if cur then R.api_drop(cur) end
        local reg = R.api_reg("override", key, function() end, opts)
        reg.saved, reg.saved_set, reg.value = cfg[key], true, value
        cfg[key] = value
        R.api.overrides[key] = reg
        return reg
    end
    api.clear_override = function(h) R.api_drop(h) end
    -- 1.2 (0.9.173): ask DPC to switch who player 1 plays, the same as the take-control key. Asked for by a mod author
    -- whose command wheel switches characters. The checks below run at once; the switch itself runs on DPC's next
    -- game frame (the "possess" / "release" events confirm it; "control_failed" says why if it could not happen).
    -- Returns true, or nil and a reason; never throws.
    api.possess = function(target, opts)
        local mod = type(opts) == "table" and tostring(opts.mod or "a mod") or "a mod"
        local why = R.api_control_refusal()
        if why then return nil, why end
        -- the pawn list itself, not get_party(): that one toggles in_internal_query, which the game-thread hooks
        -- read, and a mod may call this from its UI (render thread)
        local party = R.api_pawn_list()
        if #party == 0 then return nil, "no party" end
        local entry = nil
        if type(target) == "number" then
            for _, e in ipairs(party) do if e.idx == target then entry = e end end
            if not entry then return nil, "no such slot" end
        elseif target ~= nil and type(target) ~= "string" and select(2, pcall(sdk.is_managed_object, target)) == true then
            local a = target:get_address()
            local ar = state.arisen_chara or R.real_player()
            if ar and ar:get_address() == a then -- the Arisen: same as release_pawn
                return api.release_pawn(opts)
            end
            for _, e in ipairs(party) do if e.chara and e.chara:get_address() == a then entry = e end end
            if not entry then return nil, "not in the party" end
        else
            return nil, "expected an app.Character or a party slot number"
        end
        if state.active and state.pawn_idx == entry.idx then return true end -- already played
        local by = api.player_of(entry.chara)
        if by then return nil, "played by player " .. by end
        local okd, down = pcall(function()
            return entry.chara:call("get_IsDead") == true or (entry.chara:call("get_IsDown") == true and (entry.chara:call("get_Hp") or 1) <= 0)
        end)
        if okd and down then return nil, "downed" end
        local want_addr = entry.chara:get_address()
        local losses = R.world_losses or 0
        enqueue_game_thread("API possess (" .. mod .. ")", function()
            local again = R.api_control_refusal()
            if not again and (R.world_losses or 0) ~= losses then again = "loading" end -- a load came in between
            local idx = nil
            for _, e in ipairs(R.api_pawn_list()) do if e.chara:get_address() == want_addr then idx = e.idx end end
            if not again and idx == nil then again = "not in the party" end
            if again then pcall(R.api_fire, "control_failed", { what = "possess", reason = again, mod = mod }); return end
            log_msg("Mod API: " .. mod .. " asks to play slot " .. tostring(idx))
            cfg.selected_pawn_idx = idx
            if start_possession(idx) == false then
                pcall(R.api_fire, "control_failed", { what = "possess", reason = "refused", mod = mod })
            end
        end)
        return true
    end
    api.release_pawn = function(opts)
        local mod = type(opts) == "table" and tostring(opts.mod or "a mod") or "a mod"
        local why = R.api_control_refusal()
        if why then return nil, why end
        if not state.active then return true end -- already on the Arisen
        local losses = R.world_losses or 0
        enqueue_game_thread("API release (" .. mod .. ")", function()
            if not state.active then return end
            local again = R.api_control_refusal()
            if not again and (R.world_losses or 0) ~= losses then again = "loading" end
            if again then pcall(R.api_fire, "control_failed", { what = "release", reason = again, mod = mod }); return end
            release_possession("mod API: " .. mod)
        end)
        return true
    end
    R.api_table = api
end
-- { idx, chara } for each pawn in the party, read straight from the game's list (safe from any thread)
R.api_pawn_list = function()
    local out = {}
    pcall(function()
        local pm = sdk.get_managed_singleton("app.PawnManager")
        local list = pm and pm:call("get_PawnCharacterList")
        local n = list and list:call("get_Count") or 0
        for i = 0, n - 1 do
            local c = list:call("get_Item", i)
            if c then out[#out + 1] = { idx = i, chara = c } end
        end
    end)
    return out
end
-- why a mod may not switch control right now (nil = it may). Reads only.
R.api_control_refusal = function()
    if R.world == false or R.world_now == false then return "loading" end
    if coop.active or (R.cp and R.cp.on) or (R.s2 and R.s2.active) then return "coop" end
    if R.np then for _, sl in pairs(R.np.slots) do if sl.active then return "coop" end end end
    local okc, cut = pcall(function()
        local ar = state.arisen_chara or R.real_player()
        return ar ~= nil and ar:call("get_IsCutSceneMode") == true
    end)
    if okc and cut then return "cutscene" end
    if R.cap then return "busy" end
    return nil
end
R.api_build()

dev.api_overrides = R.api.overrides -- save_cfg leaves these out of the saved config

-- publish and run anything queued by mods that loaded before DPC (principle 5)
_G.DPC_API = R.api_table
R.api_drain = function()
    local q = _G.DPC_API_QUEUE
    _G.DPC_API_QUEUE = nil
    if type(q) == "table" then
        for _, fn in ipairs(q) do
            if type(fn) == "function" then R.api_run({ fn = fn, mod = "queued mod", what = "load" }, R.api_table) end
        end
    end
    -- a queue a later mod creates by mistake (DPC already loaded) is drained once a second
    re.on_frame(function()
        local q2 = _G.DPC_API_QUEUE
        if type(q2) == "table" and #q2 > 0 then
            _G.DPC_API_QUEUE = nil
            for _, fn in ipairs(q2) do
                if type(fn) == "function" then R.api_run({ fn = fn, mod = "queued mod", what = "load" }, R.api_table) end
            end
        end
    end)
end
R.api_drain()
R.api_ready_fired = false
re.on_pre_application_entry("UpdateBehavior", function()
    if R.scene_warp_t and os.clock() >= R.scene_warp_t then -- v0.9.170 "scene" command: the party joins the Arisen
        R.scene_warp_t = nil
        pcall(party_warp_to_me)
    end
    if not R.api_ready_fired then R.api_ready_fired = true; R.api_fire("ready", { version = "1.0" }) end
    local t = brain.on and brain.target or nil
    local a = 0
    pcall(function() a = t and t:get_address() or 0 end)
    if a ~= (R.api_ai_t or 0) then
        R.api_ai_t = a
        if a ~= 0 and R.api.on.arisen_ai_target then
            local tn = nil
            pcall(function() tn = t:call("get_GameObject"):call("get_Name") end)
            R.api_fire("arisen_ai_target", { target = t, target_name = tn })
        end
    end
end)

-- "Connected mods" (settings window)
R.api_draw = function()
    local regs = R.api.regs
    if #regs == 0 then
        imgui.text("   None. Other mods can use DPC through _G.DPC_API (see API.md in the mod's source).")
        return
    end
    for _, reg in ipairs(regs) do
        local status = reg.off and "OFF (errors)" or (reg.disabled and "off" or "on")
        local cost = (reg.calls or 0) > 0 and string.format("  %d calls, %.2f ms avg", reg.calls, 1000 * reg.cost / reg.calls) or ""
        local label = string.format("%s: %s %s [%s]%s##api%d", reg.mod, reg.kind, reg.what, status, cost, reg.id)
        local c, v = imgui.checkbox(label, not reg.disabled and not reg.off)
        if c then reg.disabled = not v; if v then reg.off, reg.fails = false, {} end end
        if reg.err then imgui.text_colored("      last error: " .. reg.err:sub(1, 160), 0xFF5555FF) end
    end
end

re.on_script_reset(function()
    pcall(R.pf_restore_all, "script reset") -- v0.9.170
    if state.active then
        pcall(release_possession, "script reset")
    end
    pcall(R.cine_stop) -- v0.9.169: game speed and glow back to normal
    pcall(function()
        if R.nodie_on then sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer"):call("get_Hit"):call("set_IsNoDie", false) end
    end)
    -- v0.9.147: test enemies do not outlive a script reset. The list of them lives in this script, so after a reset
    -- nothing could remove them or make the unkillable ones killable again (three goblins were left that way).
    pcall(despawn_tests)
    pcall(quick.hold_end_all, "script reset") -- v0.9.151: no pawn is left with its decision maker off
    pcall(function() -- v0.9.156: arrow counters this script raised go back
        local A, im = R.arrows, sdk.get_managed_singleton("app.ItemManager")
        local ar = sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer")
        if A and A.shown and im and ar then
            for f, id in pairs({ _PoisonArrowNum = 166, _WaterArrowNum = 167, _OilArrowNum = 168, _ExplosiveArrowNum = 169 }) do
                local n = im:call("getHaveNum(System.Int32, app.Character)", id, ar)
                if type(n) == "number" then im:set_field(f, n) end
            end
        end
    end)
    pcall(R.session_write, false)
end)

do -- v0.9.16: did the last session end in the middle of a possession?
    local ok, d = pcall(json.load_file, "DPC_session.json")
    if ok and type(d) == "table" and d.active == true then
        -- v0.9.74: log only. The automatic switch of Thief pawns to the fallback controls after two such endings is
        -- gone: it could not tell a crash from quitting while possessing, never reset, and no Thief crash has been
        -- seen since the v0.7.5 timing fix. The manual option stays under Options.
        log_msg(string.format("Last session ended while possessing %s (%s).", tostring(d.pawn), JOB_NAMES[d.job] or "?"))
    end
    pcall(R.session_write, false)
end

-- ----------------------------------------------------------------------------
-- ImGui UI, Skill Palette HUD & Live Diagnostic Panel
-- ----------------------------------------------------------------------------
local MODE_LABELS = {
    [2] = "Mode 2 (Recommended Safe): ActionSelector Puppeteer (Angle C)",
    [1] = "Mode 1 (Experimental): Native InputProcessor Swap (Angle B)",
    [3] = "Mode 3 (Experimental): Hybrid (Native Processor + Puppeteer Assist)",
}

local SLOT_BIND_LABELS = { -- four-skill layout
    [1] = "[Num1 / L1+Square]",
    [2] = "[Num2 / L1+Triangle]",
    [3] = "[Num3 / L1+Cross]",
    [4] = "[Num4 / L1+Circle]",
    [5] = "[Num5]",
    [6] = "[Num6]",
    six = { -- v0.9.22: the game's layout once slot 5 or 6 holds a skill
        "[Num1 / L1+Square]", "[Num2 / L1+Triangle]", "[Num3 / L1+Cross]", "[Num4 / L1+Circle]", -- 0.9.124: the default layout
        "[Num5 / L1+Triangle+Circle]", "[Num6 / L1+Square+Cross]",
    },
}
R.SLOT_BIND_LABELS = SLOT_BIND_LABELS -- 0.9.171: the player-2 palette (declared earlier in the file) reads it here

re.on_draw_ui(function()
    if imgui.tree_node("Direct Pawn Control (v" .. VERSION .. ")") then
        local chg
        chg, cfg.window_open = imgui.checkbox("Show the settings window", cfg.window_open)
        if chg then save_cfg() end
        imgui.tree_pop()
    end
end)

-- v0.9.16: the rectangle overlays are placed in. On an ultrawide screen the middle 16:9, so a 16:9 recording
-- (OBS crop) shows them. The windows can still be dragged while the REFramework menu is open.
function R.hud_rect()
    local disp = imgui.get_display_size()
    local W = (disp and disp.x and disp.x > 400) and disp.x or 1920
    local H = (disp and disp.y and disp.y > 300) and disp.y or 1080
    local safe = cfg.hud_safe_169
    if safe == "auto" then safe = (W / H) > 1.9 end
    if safe and W / H > 16 / 9 then
        local w = H * 16 / 9
        return (W - w) * 0.5, 0, w, H
    end
    return 0, 0, W, H
end

R.hud_hide_t, R.hud_hide = 0, false
function R.hud_hidden()
    local now = os.clock()
    if R.world ~= true then R.hud_hide = true; return true end
    if now < R.hud_hide_t then return R.hud_hide end
    R.hud_hide_t = now + 0.1
    local hide = false
    pcall(function()
        local function num(v)
            if type(v) == "userdata" then
                local okv, x = pcall(v.get_field, v, "value__")
                v = okv and x or nil
            end
            return tonumber(v)
        end
        local gm = sdk.get_managed_singleton("app.GuiManager")
        if gm and gm:call("isPausedGUI") == true then hide = true; return end
        local fm = sdk.get_managed_singleton("app.FacilityManager")
        if fm and (num(fm:call("get_ExecFacility")) or 0) ~= 0 then hide = true; return end
        -- 0.9.172-dev37 (the tester: "get rid of the co-op camera in the rift"): the Rift is the game's "Rim"
        -- (app.FacilityManager.RimStateNow: None 0 / End 15 outside it). Co-op stays on; the overlays hide there.
        local rs = fm and num(fm:get_field("RimStateNow"))
        R.rift = rs ~= nil and rs ~= 0 and rs ~= 15
        R.rift_state = rs
        if R.rift then hide = true; return end
        if coop.active then
            local cm = sdk.get_managed_singleton("app.CameraManager")
            local mc = cm and cm:call("getMainCameraController", 0)
            -- 0.9.172-dev26: the climbing camera (control type 6) too, like the bow aim (7): the target markers and
            -- player 2's bars vanished as soon as player 1 started climbing (the tester, coop-climb-2)
            -- 0.9.172-dev27: the game cameras agreed with the tester (2026-11-21) where play goes on: normal, combat, narrow,
            -- notice, climbing, bow aim, ballista, following an NPC, shot. Cutscenes, talk, cinematic grabs, photo,
            -- character edit and the rest still hide the overlays.
            local ctv = num(mc and mc:call("get_CurrentControlType"))
            if mc and mc:call("get_CurrentPlayerCamera") == false and not R.OVERLAY_CAMS[ctv or -1] then
                hide = true
            end
        end
    end)
    R.hud_hide = hide
    return hide
end

re.on_frame(function()
    local hx, hy, hw, hh = R.hud_rect()
    local cond = 1 << 1                       -- ImGuiCond_Once
    if (R.hud_repos or 0) > 0 then R.hud_repos = R.hud_repos - 1; cond = 1 end -- Always, for a few frames
    if not R.hud_hidden() then
    -- 1. Top-Left Status HUD Banner while possessing a Pawn
    if state.active and cfg.hud_overlay then
        imgui.set_next_window_pos(Vector2f.new(hx + 24, hy + 24), cond)
        imgui.begin_window("DirectPawnControl_HUD", nil, (1 << 0) | (1 << 1) | (1 << 3) | (1 << 6))
        local hp = ui_cache.hp or 0
        local max_hp = ui_cache.max_hp or 1
        local job_str = JOB_NAMES[state.pawn_job] or "Pawn"
        imgui.text_colored(string.format("CONTROLLING PAWN: %s (%s)", state.pawn_name, job_str), 0xFF55FF55)
        imgui.text(string.format("HP: %.0f / %.0f  |  Speed: %.1f m/s  |  Action: %s", hp, max_hp, state.live_speed_mps, state.last_action_str))
        imgui.text_colored(string.format("[%s] Select   [%s] Go to selection   [Numpad 1-6] Order it   [%s] Warp Arisen here", R.key_label("cycle_pawn"), R.key_label("toggle_possess"), R.key_label("warp_arisen")), 0xFFCCCCCC)
        if coop.active then
            imgui.text_colored("CO-OP  P1: Arisen (mouse+keyboard)   P2: " .. tostring(state.pawn_name) .. " (controller)", 0xFFCCCCCC)
        else
        imgui.text_colored(state.arisen_stay and "Arisen: WAITING  (Come = follow)" or "Arisen: FOLLOWING  (Wait = stay)", 0xFFCCCCCC)
        imgui.text_colored("Selection: " .. tostring(R.sel_name or "the Arisen"), 0xFF30D0FF)
        end
        if brain.on then
            imgui.text_colored(string.format("Arisen brain: %s  %s %.0fm", tostring(brain.mode), tostring(brain.target_id), brain.dist or 0), 0xFFCCCCCC)
        end
        imgui.end_window()
    end

    -- v0.9.42 co-op: thin yellow stamina bar under player 2's pawn's health bar. The game's plate is not read; the bar
    -- is anchored to a point above the pawn's feet (the plate looked anchored there in the tester's screenshots: health
    -- bar about 252 px wide at 2160 p, centred over the root, roughly 1.9 m up) and tuned with two settings.
    if cfg.arisen_bars and state.active and not coop.active then
        if not R.stam_cb_ok then R.ar_calc() end
        if R.ar_ok and R.ar_hp and os.clock() - (R.ar_t or 0) < 0.25 then
            pcall(function()
                local k = hh / 2160.0
                local h = math.max(2.0, (cfg.coop_bars_thick or 4.0) * k)
                local al = math.floor(255 * math.max(0.15, math.min(1.0, cfg.coop_bars_alpha or 0.65)))
                local function col(rgb, f) return (math.floor(al * (f or 1.0)) << 24) | rgb end
                local w, x, y, label
                if R.ar_sx then
                    w = 252.0 * k
                    x, y = math.floor(R.ar_sx - w * 0.5 + 0.5), math.floor(R.ar_sy + 0.5)
                else
                    w = hw * 0.16 * (cfg.coop_stamina_width or 1.0)
                    x = hx + hw * (cfg.coop_stamina_hud_x or 0.5) - w * 0.5
                    y = hy + hh * (cfg.coop_stamina_hud_y or 0.9)
                    label = true
                end
                draw.filled_rect(x, y, w, h, col(0x000000, 0.55))
                if R.ar_cap and R.ar_cap > R.ar_hp then draw.filled_rect(x, y, w * R.ar_cap, h, col(0x2A502A)) end
                -- v0.9.75: below the danger share his health bar turns red and pulses
                if R.ar_hp < (R.danger_rate or 0.25) then
                    draw.filled_rect(x, y, w * R.ar_hp, h * 1.5, col(0x3030F0, 0.75 + 0.75 * math.abs(math.sin(os.clock() * 5.0))))
                else
                    draw.filled_rect(x, y, w * R.ar_hp, h, col(0x60A878))
                end
                if R.ar_st then
                    local y2 = y + h + math.max(2.0, hh * 0.003)
                    draw.filled_rect(x, y2, w, h, col(0x000000, 0.55))
                    draw.filled_rect(x, y2, w * R.ar_st, h, col(0x50B4D2))
                end
                if label then draw.text("Arisen", x, y - math.max(16.0, hh * 0.02), col(0xD8D8D8)) end
            end)
        end
    end

    -- v0.9.43: the position is computed in R.stam_calc at LockScene (scene and camera final for the frame); computing
    -- it here, at draw time, wiggled on every movement (the tester).
    if coop.active and cfg.coop_stamina_bar and state.pawn_chara then
        if not R.stam_cb_ok then R.stam_calc() end
        local fresh = R.stam_ratio and os.clock() - (R.stam_t or 0) < 0.25
        if fresh and cfg.coop_stamina_attach then
            if R.stam_x then
                pcall(function()
                    draw.filled_rect(R.stam_x - 1, R.stam_y - 1, R.stam_w + 2, R.stam_h + 2, 0xB0000000)
                    draw.filled_rect(R.stam_x, R.stam_y, R.stam_w * R.stam_ratio, R.stam_h, 0xFF2BD0FF)
                end)
            end
        elseif fresh then
            -- v0.9.48: fixed HUD bar (default). Three anchors for a bar under the game's plate (feet, LockScene,
            -- Head_0) all drifted against it: with the head the height matched but the plate sat 100 - 260 px to
            -- either side. The plate's own position is not readable, so player 2's stamina gets a fixed place.
            pcall(function()
                -- v0.9.50: thin and muted so the pair sits behind the Arisen's own gauges (the tester: 0.9.49 was about
                -- 12 px thick and brighter than the game's bars). Thickness and opacity are settings.
                local w = hw * 0.16 * (cfg.coop_stamina_width or 1.0)
                local h = math.max(2.0, (cfg.coop_bars_thick or 4.0) * hh / 2160.0)
                local x = hx + hw * (cfg.coop_stamina_hud_x or 0.5) - w * 0.5
                local y = hy + hh * (cfg.coop_stamina_hud_y or 0.9)
                local al = math.floor(255 * math.max(0.15, math.min(1.0, cfg.coop_bars_alpha or 0.65)))
                local function col(rgb, f) return (math.floor(al * (f or 1.0)) << 24) | rgb end
                local gap = h + math.max(2.0, hh * 0.003)
                local ty = y - math.max(16.0, hh * 0.02)
                if cfg.coop_health_bar and R.stam_hp then
                    draw.filled_rect(x, y, w, h, col(0x000000, 0.55))
                    if R.stam_hp_cap and R.stam_hp_cap > R.stam_hp then draw.filled_rect(x, y, w * R.stam_hp_cap, h, col(0x2A502A)) end
                    draw.filled_rect(x, y, w * R.stam_hp, h, col(0x60A878))
                    y = y + gap
                end
                draw.filled_rect(x, y, w, h, col(0x000000, 0.55))
                draw.filled_rect(x, y, w * R.stam_ratio, h, col(0x50B4D2))
                draw.text((R.cp_pawn_label and R.cp_pawn_label() or "P2") .. "  " .. tostring(state.pawn_name or ""), x, ty, col(0xD8D8D8))
            end)
        end
    end

    -- v0.9.110 selection name on the HUD (the marker cannot be seen when the pick is off screen). Requested: a name label left of the health and stamina bars.
    -- Bright for 4 s after a change; stays dim while a pawn other than the default pick is selected.
    -- v0.9.114: the same line also says, for 3 s, who you just started playing ("Playing as <name>", "Back to the
    -- Arisen", "Co-op: player 2 plays <name>"): the only on-screen word from the mod now that the status panel is off.
    if cfg.sel_label ~= false and (R.sel_label or R.note) then
        pcall(function()
            local now = os.clock()
            local note = R.note and now < R.note.t_end and R.note.text or nil
            local fresh = now < (R.sel_label_until or 0)
            local keep = state.active and not coop.active and R.sel_kind == "pawn" and R.sel_idx ~= nil
            if not (note or (R.sel_label and (fresh or keep))) then return end
            if note then fresh = true end
            local a = fresh and 255 or 150
            local x = hx + hw * (cfg.sel_label_x or 0.215)
            local y = hy + hh * (cfg.sel_label_y or 0.957)
            -- v0.9.111 bigger text (requested: a larger font): the default font loaded at a size that
            -- follows the screen height (sel_label_size, share of the height; 30 px at 2160). Loaded once per size;
            -- if the font cannot be loaded the label falls back to the small built-in text.
            local px = math.floor(hh * (cfg.sel_label_size or 0.014) + 0.5)
            if px ~= R.sel_font_px then
                R.sel_font_px, R.sel_font = px, nil
                pcall(function() R.sel_font = imgui.load_font(nil, px) end)
                R.sel_font_t = now
            end
            local pushed = false
            -- not on the frames right after loading: the font atlas is rebuilt first
            if R.sel_font and now - (R.sel_font_t or now) > 0.5 then pushed = pcall(imgui.push_font, R.sel_font) end
            if pushed then y = y - px * 0.45 end
            local okd = pcall(draw.text, note or ("Selected:  " .. tostring(R.sel_label)), x, y, (a << 24) | (note and 0xFFFFFF or 0x30D0FF))
            if pushed then pcall(imgui.pop_font) end
            R.sel_font_ok = pushed and okd
        end)
    end

    -- v0.9.149 the controls hint: one dim line over the selection label
    if cfg.hint_controls and R.hint then
        pcall(function()
            local now = os.clock()
            local px = math.floor(hh * (cfg.sel_label_size or 0.014) + 0.5)
            if px ~= R.sel_font_px then
                R.sel_font_px, R.sel_font = px, nil
                pcall(function() R.sel_font = imgui.load_font(nil, px) end)
                R.sel_font_t = now
            end
            local x = hx + hw * (cfg.sel_label_x or 0.215)
            local y = hy + hh * (cfg.hint_y or 0.925)
            local pushed = false
            if R.sel_font and now - (R.sel_font_t or now) > 0.5 then pushed = pcall(imgui.push_font, R.sel_font) end
            if pushed then y = y - px * 0.45 end
            pcall(draw.text, R.hint, x + 1, y + 1, 0xA0000000)
            pcall(draw.text, R.hint, x, y, 0xC0E0E0E0)
            if pushed then pcall(imgui.pop_font) end
        end)
    end

    -- v0.9.90 selection marker: a yellow wedge and the name over the picked character for 3 s after F7
    if R.cr.want and R.cr.down then
        pcall(function()
            local x, y = R.ta_screen(R.cr.down)
            local k = hh / 2160.0
            local pulse = 0.5 + 0.5 * math.sin(os.clock() * 6.0)
            local txt = "Revive " .. tostring(R.cr.name or "player 2")
            if x then
                y = y - 90.0 * k
                draw.filled_circle(x, y, (18.0 + 6.0 * pulse) * k, 0xC0000000, 24)
                draw.filled_circle(x, y, (14.0 + 6.0 * pulse) * k, 0xF02020E0, 24)
                draw.text(txt, x - 40, y - 34.0 * k - 16, 0xF0FFFFFF)
            else
                draw.text("Player 2 is down: " .. txt, hx + hw * 0.5 - 110, hy + hh * 0.12, 0xF04040FF)
            end
        end)
    end
    if cfg.coop_aim and coop.active then
        local okd, errd = pcall(R.ta_draw, hh)
        if not okd then R.ta_dbg = "aim error: " .. tostring(errd) end
    end
    if R.ping and R.ping.pos then
        pcall(function()
            local sp = draw.world_to_screen(Vector3f.new(R.ping.pos[1], R.ping.pos[2], R.ping.pos[3]))
            if not sp then return end
            local k = hh / 2160.0
            local left = math.max(0.0, R.ping.t_end - os.clock())
            local a = math.floor(255 * math.min(1.0, left / 0.6))
            local bob = math.sin(os.clock() * 6.0) * 6.0 * k
            local w, h = 26.0 * k, 34.0 * k
            local x, y = sp.x, sp.y + bob
            local col = (a << 24) | 0x30D0FF
            draw.filled_quad(x - w, y - h, x + w, y - h, x, y, x, y, col)
            -- v0.9.112: no name here (the game's own name plate is already over his head; the HUD label names him)
        end)
    end

    -- v0.9.26 DPC's own Gather / Loot prompt for the possessed pawn
    if state.active and cfg.pawn_interact and (R.int_obj or R.int_wake) then
        -- v0.9.37: the prompt sits over the thing itself (in co-op the pawn can be anywhere on screen); the fixed
        -- lower-middle spot is only the fallback when the object is off screen.
        local ix, iy = hx + hw * 0.5 - 110, hy + hh * 0.62
        if R.int_pos then
            local oksp, sp = pcall(draw.world_to_screen, Vector3f.new(R.int_pos[1], R.int_pos[2] + 0.35, R.int_pos[3]))
            if oksp and sp then
                local ds = imgui.get_display_size()
                if sp.x > 20 and sp.y > 20 and sp.x < ds.x - 220 and sp.y < ds.y - 40 then ix, iy = sp.x - 70, sp.y - 30 end
            end
        end
        -- v0.9.69 hold ring for Revive: a dim ring left of the prompt, filled clockwise from the top
        if R.int_wake and R.int_wake_kind == "Revive" and (cfg.pawn_revive_hold or 0) > 0 then
            pcall(function()
                local k = hh / 2160.0
                local cx, cy = ix - 34.0 * k, iy + 22.0 * k
                local r1, r0 = 24.0 * k, 16.0 * k
                local N = 48
                local prog = R.rev_prog or 0.0
                for i = 0, N - 1 do
                    local a0 = (i / N) * 2 * math.pi - math.pi / 2
                    local a1 = ((i + 1) / N) * 2 * math.pi - math.pi / 2
                    local c0, s0, c1, s1 = math.cos(a0), math.sin(a0), math.cos(a1), math.sin(a1)
                    local col = ((i + 0.5) / N <= prog) and 0xFFF0F0F0 or 0x70000000
                    draw.filled_quad(cx + c0 * r0, cy + s0 * r0, cx + c0 * r1, cy + s0 * r1,
                                     cx + c1 * r1, cy + s1 * r1, cx + c1 * r0, cy + s1 * r0, col)
                end
            end)
        end
        imgui.set_next_window_pos(Vector2f.new(ix, iy), 1)
        imgui.begin_window("DirectPawnControl_Interact", nil, (1 << 0) | (1 << 1) | (1 << 3) | (1 << 6))
        imgui.text_colored(string.format("[Interact]  %s", R.int_wake and (((R.int_wake_kind == "Revive" and (cfg.pawn_revive_hold or 0) > 0) and "Hold: Revive" or tostring(R.int_wake_kind or "Wake")) .. " " .. tostring(R.int_wake_name)) or (R.int_dead and "Loot" or (R.int_item and "Pick up" or "Gather / Use"))), 0xFF66FFFF)
        imgui.end_window()
    end

    -- 2. Bottom-Right Dynamic Pawn Skill Palette HUD Overlay (Issue 1 Fix)
    -- v0.9.70: in co-op the palette is back for player 2 (the game's own skill HUD belongs to player 1's Arisen),
    -- with the controller buttons only.
    local p2_pal = coop.active and cfg.coop_skill_palette
    if state.active and (cfg.skill_hud_overlay or p2_pal) then
        local wx, wy = hx + hw - 340, hy + hh - 230
        if p2_pal then
            -- v0.9.71: right of player 2's bars, bottom edge level with them (the 0.9.70 spot covered the game's
            -- own button hints). Anchored by its bottom-left corner so a longer list grows upward.
            wx, wy = hx + hw * (cfg.coop_palette_left or 0.60), hy + hh * (cfg.coop_palette_bottom or 0.93)
            imgui.set_next_window_pos(Vector2f.new(wx, wy), 1, Vector2f.new(0.0, 1.0))
        else
            imgui.set_next_window_pos(Vector2f.new(wx, wy), cond)
        end
        imgui.begin_window("DirectPawnControl_SkillHUD", nil, (1 << 0) | (1 << 1) | (1 << 3) | (1 << 6))
        local job_str = JOB_NAMES[state.pawn_job] or "Pawn"
        local voc_act = VOCATION_ACTION_NAMES[state.pawn_job] or "Vocation Action"
        imgui.text_colored(string.format(p2_pal and "Player 2: %s (%s)" or "%s — %s Skills", state.pawn_name, job_str), 0xFF88EEFF)
        imgui.separator()
        local active_sk = ui_cache.active_sk or 0
        for s = 1, 6 do
          local sid = state.pawn_skills and state.pawn_skills[s] or 0
          if s <= 4 or sid ~= 0 then
            local sname = skill_name(sid)
            local is_active = (sid ~= 0 and active_sk == sid)
            local color = is_active and 0xFF44FF44 or (sid ~= 0 and 0xFFFFFFFF or 0xFF888888)
            local prefix = is_active and ">> " or "   "
            local six = state.pawn_skills and ((state.pawn_skills[5] or 0) ~= 0 or (state.pawn_skills[6] or 0) ~= 0)
            local lbl = six and SLOT_BIND_LABELS.six[s] or SLOT_BIND_LABELS[s]
            local gl = R.bind_label(s) -- 0.9.100: the game's own assignment when it could be read
            if gl then lbl = "[Num" .. s .. " / " .. gl .. "]" end
            if p2_pal then lbl = R.pad_label("[" .. (lbl:match("/ ([^%]]+)%]") or lbl:gsub("[%[%]]", "")) .. "]", R.dev_style(R.tp.p2)) end
            if not p2_pal or sid ~= 0 then
                imgui.text_colored(string.format("%s%s  %s", prefix, lbl, sname), color)
            end
          end
        end
        imgui.separator()
        local voc_color = (state.is_guarding or state.is_aiming or state.is_quickspelling) and 0xFF44FF44 or 0xFFCCCCCC
        local voc_btn = R.btn_text(R.bind_mask("JobSpecialAction")) or "R1" -- v0.9.124: from the game's assignment
        imgui.text_colored(string.format(p2_pal and ("   " .. R.pad_label("[" .. voc_btn .. "]", R.dev_style(R.tp.p2)) .. "  %s") or ("   [" .. R.pad_label(voc_btn) .. "]  %s"), voc_act), voc_color)
        imgui.end_window()
    end
    end

    if not cfg.window_open then return end
    -- v0.9.114: the settings window belongs to the REFramework menu; it never sits over the game on its own
    do
        local okd, drawing = pcall(reframework.is_drawing_ui, reframework)
        if okd and drawing == false then return end
    end

    cfg.window_open = imgui.begin_window("Direct Pawn Control  v" .. VERSION, cfg.window_open, 1 << 6)
    if not cfg.window_open then
        save_cfg()
        imgui.end_window()
        return
    end
    -- v0.9.124: a key of the mod that the game also uses (after a remap in the game's options)
    do
        local okc, cl = pcall(R.key_clashes)
        if okc and cl and #cl > 0 then
            for _, c in ipairs(cl) do imgui.text_colored("Key clash: " .. c, 0xFF40C0FF) end
        end
    end

    local party = ui_cache.party or {}
    local chg
    local GREEN, GREY, BLUE, RED, YELLOW = 0xFF55FF55, 0xFFAAAAAA, 0xFFFFCC88, 0xFF5555FF, 0xFF55DDFF

    -- ===== 1. Possession =====================================================================================
    if state.active then
        imgui.text_colored(string.format("POSSESSING %s (%s)", state.pawn_name, JOB_NAMES[state.pawn_job] or "Pawn"), GREEN)
        if imgui.button("Release [F6]") then
            enqueue_game_thread("UI release_possession", function() release_possession("UI button") end)
        end
        imgui.same_line()
        if imgui.button("Warp Arisen here [F8]") then enqueue_game_thread("UI warp_arisen", warp_arisen_to_pawn) end
    else
        imgui.text_colored("Playing as the Arisen", BLUE)
    end
    for _, e in ipairs(party) do
        local is_sel = (cfg.selected_pawn_idx == e.idx)
        local is_possessed = (state.active and state.pawn_idx == e.idx)
        local label = string.format("%s%s (%s)##pawn%d", is_possessed and "* " or (is_sel and "> " or ""), e.name, e.job_name, e.idx)
        if e.idx > 0 then imgui.same_line() end
        if imgui.button(label) then
            local idx = e.idx
            cfg.selected_pawn_idx = idx
            save_cfg()
            enqueue_game_thread("UI possess", function() start_possession(idx) end)
        end
    end
    if #party == 0 then imgui.text_colored("No party pawns found", RED) end
    imgui.text_colored(string.format("Click a pawn to possess it.  %s select (marker)   %s take control of the selection   Numpad 1-6 order it   %s warp Arisen", R.key_label("cycle_pawn"), R.key_label("toggle_possess"), R.key_label("warp_arisen")), GREY)

    -- Couch co-op (v0.9)
    if coop.active then
        imgui.text_colored(string.format("CO-OP: player 2 (controller) plays %s   map: %s", tostring(state.pawn_name), tostring(coop.map_src)), GREEN)
        if imgui.button("Stop co-op [Ctrl+F6]") then enqueue_game_thread("UI coop stop", coop_stop) end
        if cfg.show_legacy then
            imgui.same_line()
            imgui.text(string.format("pad 0x%X -> 0x%X", coop.last_btn or 0, coop.last_flags or 0))
        end
        if coop.err then imgui.text_colored("co-op error: " .. tostring(coop.err), RED) end
        if R.ta_dbg and cfg.show_legacy then imgui.text(R.ta_dbg) end
        if cfg.coop_two_pads and (R.tp.n or 0) >= 2 then
            if R.tp_on() then
                imgui.text_colored("Two controllers: player 1 = Arisen, player 2 = pawn", GREEN)
                if imgui.button("Swap controllers") then R.tp_swap() end
                imgui.same_line()
                if imgui.button("Choose again (player 2 holds L3 + R3)") then R.tp_reset(); pcall(json.dump_file, "DPC_two_pads.json", {}) end
                local t = R.tp
                local p2v = { b = 0 }
                for _, d in ipairs(R.tp_devs()) do if d:get_address() == t.p2 then p2v = R.tp_read(d) end end
                local ai = state.arisen_input
                local aon = 0
                pcall(function() aon = ai and (ai:get_field("ButtonOnFlags") or 0) or 0 end)
                if cfg.show_legacy then
                    imgui.text(string.format("P1 pad 0x%X   P2 pad 0x%X   game -> Arisen 0x%X   Arisen actions 0x%X",
                        R.tp_p1().b or 0, p2v.b or 0, t.pb_in or 0, aon))
                    imgui.text(string.format("processButton: %d calls, %d this frame, arg 0x%X", t.pb or 0, t.pb_same or 0, t.pb_a3 or 0))
                end
            else
                imgui.text_colored("Two controllers: player 2, hold L3 + R3 on your controller", YELLOW or GREEN)
            end
        end
    else
        local sel_name = "selected pawn"
        for _, e in ipairs(party) do if e.idx == cfg.selected_pawn_idx then sel_name = e.name end end
        if imgui.button("Start couch co-op: controller plays " .. sel_name .. " [Ctrl+F6]") then
            enqueue_game_thread("UI coop start", function() coop_start(cfg.selected_pawn_idx) end)
        end
    end

    -- ===== 2. Settings (v0.9.82: grouped; advanced, test and legacy options live in a separate, hidden bin) ====
    imgui.separator()
    local function cb(label, key)
        local c
        c, cfg[key] = imgui.checkbox(label, cfg[key])
        if c then save_cfg() end
        return c
    end
    local function sl(label, key, lo, hi, fmt)
        local c
        c, cfg[key] = imgui.slider_float(label, cfg[key], lo, hi, fmt or "%.2f")
        if c then save_cfg() end
    end
    local function group(title, open_first)
        if open_first and imgui.set_next_item_open then pcall(imgui.set_next_item_open, true, 1 << 1) end
        return imgui.tree_node(title)
    end

    -- 0.9.172-dev21 settings layout (the tester: "hide/remove options that no longer make sense, hide away options that are
    -- rarely necessary, and put the most high impact modes at the top where players can tune the feel"). Top: a few
    -- choices that change how the mod plays, each one line. Then co-op. Everything else folds away; diagnostics and
    -- superseded switches only with "Show advanced, test and legacy options".
    local function pick(label, key, values, labels)
        local cur = 1
        for i, v in ipairs(values) do if cfg[key] == v then cur = i end end
        local c, v = imgui.combo(label, cur, labels)
        if c then cfg[key] = values[v]; save_cfg() end
        return c
    end
    local CD = rawget(_G, "CameraDistance_API")

    imgui.text_colored("How it plays", BLUE)
    do -- the Arisen while you play a pawn: one choice for the two brain switches
        local cur = (cfg.arisen_brain and 1) or (cfg.arisen_brain_follow and 2) or 3
        local c, v = imgui.combo("The Arisen while you play a pawn", cur, { "Fights on his own and follows you", "Follows you, does not fight", "Stays where he is" })
        if c then
            cfg.arisen_brain = (v == 1)
            cfg.arisen_brain_follow = (v ~= 3)
            cfg.arisen_auto_follow = cfg.arisen_brain_follow
            save_cfg()
        end
    end
    cb("   He cannot die", "arisen_no_death")
    do -- switching characters: style + glow on one line each
        local cur = cfg.switch_cine and (cfg.switch_cine_profile or 2) or 1
        local c, v = imgui.combo("Switching characters", cur, R.CINE_PROFILES)
        if c then cfg.switch_cine, cfg.switch_cine_profile = true, v; save_cfg() end
        local GLOWS = R.CINE_GLOWS
        local gcur = 1
        for i, g in ipairs(GLOWS) do if g[1] == (cfg.switch_glow or "") then gcur = i end end
        local labels = {}
        for i, g in ipairs(GLOWS) do labels[i] = g[2] end
        local c3, gv = imgui.combo("   Glow on who you take over", gcur, labels)
        if c3 then cfg.switch_glow = GLOWS[gv][1]; save_cfg() end
        local g = GLOWS[c3 and gv or gcur]
        if g and g[3] then imgui.same_line(); imgui.text_colored("||||||", g[3]); imgui.same_line(); imgui.text_colored("||||||", g[4]) end
    end
    pick("Sound: loudness by distance from", "pf_sound_listener", { 1, 2, 0 }, { "The camera (recommended)", "The pawn you play", "The Arisen (the game's own)" })
    cb("Show the Arisen's health and stamina while you play a pawn", "arisen_bars")
    cb("Warn when someone in the party is down (while you play a pawn or in co-op)", "down_alert")
    if cfg.arisen_bars then cb("   over his head (off: at the bottom of the screen)", "arisen_bars_overhead") end
    cb("Special arrows are not used up while you play a pawn", "cheat_free_arrows")
    if cfg.cheat_free_arrows then cb("   and a played Archer without them gets one of each (those weigh nothing)", "free_arrows_give") end

    imgui.spacing()
    imgui.text_colored("Couch co-op", BLUE)
    if CD and CD.get then -- Camera Distance installed: its co-op camera style from here
        local cur = (CD.get("coop_style") == "follow") and 2 or 1
        local c, v = imgui.combo("Co-op camera", cur, { "Classic: aimed at the middle of everyone (Camera Distance)", "Follow player 1, pull back for player 2 (Camera Distance)" })
        if c and CD.set then CD.set("coop_style", v == 1 and "classic" or "follow") end
    end
    pick("Camera turning", "coop_cam_turn", { "shared", "p1", "auto" },
        { "Every player's right stick (slow push turns, quick flick switches target)", "Player 1's right stick", "Automatic, a slow push still turns it" })
    if cfg.coop_cam_turn ~= "p1" then
        -- 0.9.172-dev36: which players' sticks turn it (all by default)
        cfg.coop_cam_from = cfg.coop_cam_from or {}
        local top = math.max(2, (R.np_count and R.np_count() or 0) + 2, 4)
        imgui.text("   Turns the camera:")
        for n = 1, top do
            imgui.same_line()
            local c, v = imgui.checkbox("P" .. n .. "##camfrom" .. n, cfg.coop_cam_from["p" .. n] ~= false)
            if c then
                -- dev38: was "(not v) and false or nil", always nil in Lua, so a box never stayed unticked
                if v then cfg.coop_cam_from["p" .. n] = nil else cfg.coop_cam_from["p" .. n] = false end
                save_cfg()
            end
        end
    end
    cb("Aiming for both players (target markers; R3 keeps a target, a quick right-stick flick moves to the next)", "coop_aim")
    cb("Any combination: each player can take any free character, the Arisen included", "coop_any")
    if cfg.coop_any then cb("   The Arisen cannot die while player 2 plays him", "coop_p2_arisen_no_death") end
    cb("Two controllers: player 1 plays on one too (a second controller joins by holding L3 + R3)", "coop_two_pads")
    -- dev46: "Player 1 on keyboard and mouse" is gone: the keyboard is always player 1's, plus the controller the Arisen was played on
    cb("Player 2's controller rumbles", "coop_p2_rumble")
    cb("A player's character glows in their colour when they join or change character", "coop_join_glow")
    if cfg.coop_join_glow ~= false then
        -- dev45 (the tester): "Make sub-ticks for each player glow under the all keep glowing, so they can do all glow or
        -- do them individually". Ticking the top one switches every player on again.
        local was = cfg.coop_glow_keep
        cb("   ... and keeps glowing while they play it (everyone)", "coop_glow_keep")
        if cfg.coop_glow_keep and not was then cfg.coop_glow_keep_p = {}; save_cfg() end
        if cfg.coop_glow_keep then
            cfg.coop_glow_keep_p = cfg.coop_glow_keep_p or {}
            local top = math.max(4, (R.np_count and R.np_count() or 0) + 2)
            imgui.text("      Keep glowing:")
            for n = 1, top do
                imgui.same_line()
                local c, v = imgui.checkbox("P" .. n .. "##glowkeep" .. n, cfg.coop_glow_keep_p["p" .. n] ~= false)
                if c then
                    if v then cfg.coop_glow_keep_p["p" .. n] = nil else cfg.coop_glow_keep_p["p" .. n] = false end
                    save_cfg()
                end
            end
        end
    end
    -- 0.9.173-dev1: one colour per player for their target marker, glow and Camera Distance's off-screen marker
    if imgui.tree_node("Player colours (target marker, glow, off-screen marker)") then
        local names, pos_of = {}, {}
        for i, id in ipairs(R.COLOR_ORDER) do names[i] = R.ta_colors[id][1]; pos_of[id] = i end
        local top = math.max(4, (R.np_count and R.np_count() or 0) + 2)
        for n = 1, top do
            local c, v = imgui.combo("Player " .. n .. "##pcol" .. n, pos_of[R.player_color(n)] or 1, names)
            v = R.COLOR_ORDER[v]
            if c and v and R.ta_colors[v] then R.set_player_color(n, v); save_cfg(); coop.status_key = nil; coop.tgt_status_due = true end -- rewrite DPC_coop.json next frame (Camera Distance)
            imgui.same_line()
            if imgui.button("Preview##pcolprev" .. n) then pcall(R.color_preview, n) end
        end
        imgui.text_colored("Preview lights up that player's character (or yours) for 2.5 s.", GREY)
        imgui.tree_pop()
    end
    if package.loaded["PawnTacticalWheel.input"] then cb("Pawn Tactical Wheel (another mod) doesn't open from controllers in co-op (its keyboard key still works)", "coop_block_ptw") end
    cb("Resume co-op by itself after cutscenes, loading or a downed pawn", "coop_auto_resume")
    if R.cr.want then
        imgui.text_colored("Co-op resumes when " .. tostring(R.cr.name or "the pawn") .. " is back (" .. tostring(R.cr.reason) .. ")", YELLOW)
        imgui.same_line()
        if imgui.button("Don't resume") then R.cr.want, R.cr.down = false, nil end
    end
    if R.cp and R.cp.on then
        local nm = R.cp.names or {}
        imgui.text(string.format("   Now: P1 %s, P2 %s%s", tostring(nm[1]), tostring(nm[2]), R.cp.kb and " (one controller)" or ""))
        if R.s2.active and (R.s2.failed or R.s2.in_err) then imgui.text_colored("   P2's pawn: " .. tostring(R.s2.err or R.s2.in_err), 0xFF5555FF) end
    end
    if cfg.coop_two_pads then
        local t = R.tp
        imgui.text(string.format("   %d controller(s) found. %s", t.n or 0,
            (t.p2 and not t.wait_release) and "Player 2's controller is set." or "Player 2: hold L3 + R3 on your controller (also starts co-op)."))
        if t.p2 and imgui.button("   Swap the two controllers") then R.tp_swap() end
        if t.p2 then imgui.same_line(); if imgui.button("Choose again") then R.tp_reset(); pcall(json.dump_file, "DPC_two_pads.json", {}) end end
    end
    if imgui.button("   Reset controllers (if a controller stops working)") then R.pad_reset() end

    if group("Co-op: details") then
        cb("Health and stamina bars for player 2", "coop_stamina_bar")
        cb("Skill list for player 2", "coop_skill_palette")
        chg, cfg.coop_pad_names = imgui.combo("   Button names in the skill list", cfg.coop_pad_names or 1, { "Auto (from the controller)", "PlayStation", "Xbox" })
        if chg then save_cfg() end
        cb("When co-op starts, bring player 2's pawn next to the Arisen (if it is far away)", "coop_start_bring")
        if cfg.coop_aim then
            imgui.text_colored("Aiming", GREY)
            cb("   Target markers", "coop_aim_markers")
            cb("   Player 1: R3 (middle mouse) keeps the enemy nearest the screen centre", "coop_aim_p1")
            if cfg.coop_aim_p1 then
                cb("      and the Arisen's attacks aim at it while he fights", "coop_aim_p1_assist")
                cb("      player 1's flicks move it too (two controllers)", "coop_aim_p1_flick")
            end
            local c3
            c3, cfg.coop_aim_size = imgui.slider_float("   Marker size", cfg.coop_aim_size or 1.0, 0.5, 2.0)
            if c3 then save_cfg() end
            imgui.text("   (each player's marker colour is under \"Player colours\")")
        end
        if cfg.coop_cam_turn == "p1" then cb("   Player 1's stick mode: the camera turns toward his target by itself", "coop_cam_p1_steer") end
        if cfg.coop_cam_turn == "auto" or (cfg.coop_cam_turn == "p1" and cfg.coop_cam_p1_steer) then
            imgui.text_colored("Camera turning by itself", GREY)
            sl("   Speed", "coop_cam_auto_speed", 0.1, 1.0)
            sl("   Starts when this far off (deg)", "coop_cam_deadband", 2.0, 30.0, "%.0f")
        end
        if cfg.coop_p2_rumble then
            imgui.text_colored("Rumble", GREY)
            sl("   Strength", "coop_p2_rumble_power", 0.1, 1.0)
            cb("   on player 2's hits (stronger for big hits and kills)", "coop_rb_dealt")
            cb("   when a skill starts", "coop_rb_skill")
            cb("   knocked down, out of stamina, healed / revived, blocked hits", "coop_rb_status")
            if imgui.button("   Test player 2 rumble") then
                if R.rb_dev() then R.rb_pulse(0.8, 0.5) else R.note = { text = "Two controllers: player 2 has no controller set yet", t_end = os.clock() + 3.0 } end
            end
            imgui.same_line()
            imgui.text(R.rb.shape and "works" or (R.rb.err and "failed" or "not tried yet"))
        end
        imgui.tree_pop()
    end

    if group("Switching characters: timing") then
        sl("Game speed while switching (1 = normal)", "switch_cine_slowmo", 0.1, 1.0)
        if (cfg.switch_cine_slowmo or 1) < 0.99 then
            sl("   Full speed back before the camera lands (s)", "switch_cine_speed_back_s", 0.0, 2.0)
            sl("   ... easing up over (s)", "switch_cine_speed_ramp_s", 0.05, 1.5)
        end
        if (cfg.switch_glow or "") ~= "" then sl("Glow (s)", "switch_cine_glow_s", 0.2, 4.0) end
        if (cfg.switch_cine_profile or 2) == 4 then
            imgui.text_colored("Custom style", GREY)
            sl("   Look (s)", "switch_cine_look_s", 0.0, 1.5)
            sl("   Hold (s)", "switch_cine_hold_s", 0.0, 1.5)
            cb("   Pull back first so both are in view", "switch_cine_pull")
            if cfg.switch_cine_pull then
                sl("      Extra distance (m)", "switch_cine_pull_m", 0.0, 8.0)
                sl("      Height (m)", "switch_cine_rise_m", 0.0, 20.0)
            end
            sl("   Glide (s)", "switch_cine_glide_s", 0.1, 3.0)
        end
        imgui.tree_pop()
    end

    if group("Playing as the player: sound and feel") then
        imgui.text("   The game treats the Arisen as the player. These treat whoever you play as the player instead.")
        cb("The pawn you play sounds like the player (breathing, steps, voice)", "pf_sound_voice")
        cb("The place's echo and ambience follow the pawn you play", "pf_sound_space")
        cb("Co-op: the listener moves toward the players (a pulled-back camera does not cut sounds off)", "coop_listener_move")
        if cfg.coop_listener_move then cb("   loudness from the same point", "coop_listener_loudness") end
        cb("Skills' own slow motion (Riotous Fury, ...) for the pawn you play", "pf_skill_slow")
        imgui.tree_pop()
    end

    if group("Cheats") then
        cb("Numpad . heals and revives the party", "party_heal_key")
        if cfg.party_heal_key then cb("   ... and the Arisen", "party_heal_arisen") end
        imgui.tree_pop()
    end

    imgui.separator()
    if group("Connected mods (" .. #R.api.regs .. ")##dpcapi") then -- v0.9.170 mod API
        R.api_draw()
        imgui.tree_pop()
    end
    if group("Positions and sizes") then
        sl("Player 2's bars: left / right", "coop_stamina_hud_x", 0.05, 0.95)
        sl("Player 2's bars: up / down", "coop_stamina_hud_y", 0.05, 0.98)
        sl("Player 2's bars: width", "coop_stamina_width", 0.5, 2.0)
        sl("Player 2's skill list: left / right", "coop_palette_left", 0.0, 0.9)
        sl("Player 2's skill list: up / down (bottom edge)", "coop_palette_bottom", 0.1, 1.0)
        sl("All bars: thickness (px)", "coop_bars_thick", 1.0, 14.0, "%.0f")
        sl("All bars: opacity", "coop_bars_alpha", 0.15, 1.0)
        if imgui.button("Reset overlay positions") then R.hud_repos = 3 end
        imgui.tree_pop()
    end

    if group("Controls (change a key or a button combination)") then
        cb("Show the controls hint on screen (which button controls whom)", "hint_controls")
        if cfg.hint_controls then sl("   hint height on the screen", "hint_y", 0.05, 0.98, "%.3f") end
        local function row(label, kind, id, shown)
            imgui.text(string.format("%-34s %s", label, shown))
            imgui.same_line()
            if R.cap and R.cap.kind == kind and R.cap.id == id then
                imgui.text_colored(kind == "key" and "press a key (Esc cancels)" or "hold two or more buttons for a second (Esc cancels)", 0xFF30D0FF)
            elseif imgui.button("Change##" .. kind .. id) then
                R.cap, R.cap_msg = { kind = kind, id = id, t0 = os.clock() }, nil
            end
            -- 0.9.173: any key can be left unset (a player asked to free the numpad for other mods)
            if kind == "key" and (cfg.keys[id] or 0) ~= 0 then
                imgui.same_line()
                if imgui.button("Clear##k" .. id) then
                    cfg.keys[id], cfg.keys[id .. "_ctrl"] = 0, false
                    R.clash_logged, R.cap_msg = nil, label .. ": no key"
                    save_cfg()
                end
            end
        end
        cb("Keyboard shortcuts on (untick to use DPC from the controller only)", "hotkeys_on")
        imgui.text_colored("Keyboard (hold Ctrl while you press the new key to make it Ctrl + that key)", GREY)
        row("Take control / go back", "key", "toggle_possess", R.key_label("toggle_possess"))
        row("Select the next character", "key", "cycle_pawn", R.key_label("cycle_pawn"))
        row("Warp the Arisen to you", "key", "warp_arisen", R.key_label("warp_arisen"))
        row("Warp every pawn to you", "key", "party_warp", R.key_label("party_warp"))
        row("Heal / revive the party", "key", "party_heal", R.key_label("party_heal"))
        row("Start / stop couch co-op", "key", "coop", R.key_label("coop"))
        -- 0.9.172: straight to a character
        row("Go straight to: the Arisen", "key", "jump_arisen", R.key_label("jump_arisen"))
        local nshow = math.max(3, math.min(R.JUMP_MAX, #(R.jump_names or {})))
        for k = 1, nshow do
            local nm = R.jump_names and R.jump_names[k]
            row(string.format("Go straight to: pawn %d%s", k, nm and (" (" .. nm .. ")") or ""), "key", "jump_pawn" .. k, R.key_label("jump_pawn" .. k))
        end
        for n = 1, 6 do row("Order: skill slot " .. n, "key", "skill" .. n, R.key_label("skill" .. n)) end
        cb("   an ordered skill is kept until it is done (the pawn's own AI waits meanwhile)", "quick_skill_hold_ai")
        cb("   with no enemy about, an ordered attack skill is performed on the spot", "quick_skill_no_target")
        imgui.text_colored("Controller", GREY)
        row("Take control / next character", "pad", "take", tostring(R.combo_name(R.take_mask()) or "?"))
        cb("   keep the Arisen out of that round (pawns only; go back with the line below)", "cycle_skip_arisen")
        row("Back to the Arisen", "pad", "back", (tonumber(cfg.pad.back) or 0) ~= 0 and tostring(R.combo_name(cfg.pad.back)) or "hold D-pad down")
        cb("   in co-op, player 2 changes pawn with that same combination (pawns only)", "coop_p2_switch")
        row("Start / stop couch co-op", "pad", "coop", (tonumber(cfg.pad.coop) or 0) ~= 0 and tostring(R.combo_name(cfg.pad.coop)) or "none")
        if R.cap_msg then imgui.text_colored("Last change: " .. R.cap_msg, GREY) end
        if imgui.button("Reset all controls to the defaults") then
            cfg.hotkeys_on = true
            for k in pairs(cfg.keys) do if tostring(k):sub(-5) == "_ctrl" then cfg.keys[k] = false end end
            for k, v in pairs(R.KEY_DEFAULTS) do cfg.keys[k] = v end
            cfg.pad.take, cfg.pad.back, cfg.pad.coop = 0, 0, 0
            R.clash_logged, R.cap_msg = nil, "defaults restored"
            save_cfg()
        end
        imgui.tree_pop()
    end
    if group("Features (all on by default; switch one off if it gets in your way)") then
        imgui.text_colored("Playing a pawn", GREY)
        cb("Pick up, gather, loot and open chests as the pawn", "pawn_interact")
        cb("Wake a sleeping companion (Interact next to them)", "pawn_wake")
        cb("Revive a downed pawn (hold Interact next to them)", "pawn_revive")
        if cfg.pawn_revive then sl("   seconds to hold (the game's own revive: 3.8)", "pawn_revive_hold", 0.0, 6.0, "%.1f") end
        cb("Quick-use recovery items go to the pawn you control", "pawn_quick_item")
        if cfg.pawn_quick_item then cb("   the quick-item cross shows that pawn's own items", "pawn_quick_item_labels") end
        cb("The skill list shows the played pawn's own special-arrow counts", "pawn_arrow_counts")
        cb("The lantern shortcut works the Arisen's lantern", "pawn_quick_lantern")
        cb("Controller: hold D-pad left / right to select a character; hold down to go back to the Arisen", "pad_hold_select")
        cb("Controller: L1 + left stick click takes control of the selection (while playing a pawn: the next pawn)", "pad_l1_l3_possess")
        cb("Red low-health screen edge follows the pawn you control", "possess_danger_pawn")
        if cb("The game's skill display shows the pawn's skills", "native_hud_skill_hook") and state.active then
            enqueue_game_thread("UI toggle native_hud_skill_hook", function() apply_native_hud_skills(cfg.native_hud_skill_hook) end)
        end
        imgui.text_colored("How the Arisen fights on his own", GREY)
        cb("Only while the party is in a fight (ignores wildlife)", "arisen_brain_battle_only")
        cb("Uses his weapon skills", "arisen_brain_skills")
        cb("Fights as Fighter, Thief, Warrior, Mystic Spearhand", "arisen_brain_melee")
        cb("Fights as Mage, Sorcerer", "arisen_brain_caster")
        cb("   speeds up spells with Quickspell (uses stamina)", "arisen_brain_quickspell")
        cb("   heals the party (the pawn you control first)", "arisen_brain_heal")
        cb("   tops everyone up after a fight", "arisen_brain_topup_on")
        cb("   cures debilitations when he has the spell", "arisen_brain_cure")
        cb("Fights as Magick Archer, Trickster, Warfarer (basic)", "arisen_brain_hybrid")
        cb("   Warfarer: swaps weapons during a fight (Rearmament must be in a skill slot)", "arisen_brain_rearm")
        if cfg.arisen_brain_rearm then sl("   seconds between weapon swaps", "arisen_brain_rearm_every", 5.0, 120.0, "%.0f") end
        cb("Magick Archer: his Remedy Arrow revives a downed pawn (assisted: the mod completes the revive)", "arisen_brain_ma_remedy_assist")
        imgui.text_colored("Couch co-op", GREY)
        cb("The warp key (Numpad 7) also brings player 2's pawn", "coop_warp_p2")
        cb("The controller's motion sensor does not aim the Arisen", "coop_no_gyro")
        imgui.text_colored("Archer pawn", GREY)
        cb("Bow aim camera (zoom, body follows the camera)", "pawn_aim_camera")
        cb("Aim reticle", "pawn_aim_reticle")
        cb("Arrows go to the reticle", "pawn_aim_point")
        cb("Skills while aiming on a controller (aim button + skill buttons)", "pawn_aim_skills")
        cb("Skills from the hip keep their aim until they fire", "pawn_hip_skill_aim")
        imgui.tree_pop()
    end

    imgui.separator()
    cb("Show advanced, test and legacy options", "show_legacy")
    if cfg.show_legacy then
    if imgui.tree_node("Advanced and legacy switches") then
        imgui.text_colored("Leave these alone unless you are chasing a problem.", GREY)
        if cb("Native controls (the game's own player controls drive the pawn)", "native_controls") and state.active then
            enqueue_game_thread("UI toggle native_controls", function()
                if cfg.native_controls then native_build() else native_release() end
            end)
        end
        cb("Stop the pawn's current AI action when taking control", "possess_interrupt_ai")
        cb("F7 while playing a pawn switches pawn at once (old behaviour) instead of selecting", "cycle_switches_now")
        cb("Arisen brain: holds fire and flanks without line of sight", "arisen_brain_los")
        cb("Archer pawn: aim at what the reticle is on (ray cast)", "pawn_aim_ray")
        sl("Archer pawn: aim distance when nothing is hit (m)", "pawn_aim_point_dist", 5.0, 100.0, "%.0f")
        cb("Old skill palette outside co-op (debug)", "skill_hud_overlay")
        cb("Interact brings the Arisen to your pawn (also fires on dash)", "interact_bring")
        -- 0.9.172-dev21: moved here from the main page (rarely needed, troubleshooting or superseded)
        imgui.text_colored("Screen", GREY)
        cb("Status panel while playing a pawn (top left; detailed, for troubleshooting)", "hud_overlay")
        do
            local on = cfg.hud_safe_169 == true or (cfg.hud_safe_169 == "auto" and select(3, R.hud_rect()) < imgui.get_display_size().x)
            local c2, v = imgui.checkbox("Keep overlays inside the middle 16:9 (ultrawide recording)", on)
            if c2 then cfg.hud_safe_169 = v; R.hud_repos = 3; save_cfg() end
        end
        imgui.text_colored("Co-op", GREY)
        cb("A second controller starts co-op by holding L3 + R3 (either player ends it holding them 3 s)", "coop_pad_join")
        cb("The controller you use drives the Arisen (switches the game's active controller)", "pad_active_follow")
        do
            local okc, v = imgui.checkbox("Player 2 changes target only with a quick flick (off: any push past 70 %)", cfg.coop_aim_flick ~= "quick")
            if okc then cfg.coop_aim_flick = v and "deliberate" or "quick"; save_cfg() end
        end
        if cfg.coop_two_pads then
            local c1, v1 = imgui.combo("The Arisen's buttons (two controllers)", cfg.coop_two_pads_buttons or 1,
                { "Take out only player 2's (try first)", "Leave them to the game", "Player 1's controller only" })
            if c1 then cfg.coop_two_pads_buttons = v1; save_cfg() end
            local c2, v2 = imgui.combo("Camera while player 2 moves their right stick", cfg.coop_two_pads_cam or 1,
                { "Player 1's right stick", "Holds still" })
            if c2 then cfg.coop_two_pads_cam = v2; save_cfg() end
            if R.tp.err then imgui.text_colored("two controllers error: " .. tostring(R.tp.err), 0xFF5555FF) end
        end
        if R.rb.nodes_seen then imgui.text("player 2's action (rumble): " .. tostring(R.rb.nodes_seen):gsub("%%", "%%%%")) end
        if R.rb.err then imgui.text("rumble error: " .. tostring(R.rb.err):sub(1, 60):gsub("%%", "%%%%")) end
        imgui.text_colored("Playing as the player (experimental)", GREY)
        cb("Hit-stop (the short freeze on a hit) as if the pawn you play were the player", "pf_hitstop")
        cb("Big-kill slow motion as if the pawn you play were the player", "pf_world_slow")
        if not cfg.coop_listener_move and (cfg.pf_sound_listener or 0) == 1 then
            cb("Co-op: hear both players from an ear near them (superseded by the moving listener)", "pf_sound_coop_ear")
            if cfg.pf_sound_coop_ear then sl("   Ear distance from the players (m)", "pf_sound_ear_dist", 2.0, 15.0, "%.1f") end
        end
        do
            local L = R.lis
            if cfg.coop_listener_move then
                local st = L.found and ("moved by " .. L.found) or (L.failed and "no way found to move it") or (L.active and ("finding the way: trying " .. tostring(L.ways[L.way_i])) or "waiting for co-op")
                imgui.text("Listener: " .. st)
                if L.active and L.err then imgui.text(string.format("   camera %.0f m from the players; listener %.1f m from the camera, %.1f m off target", L.d or 0, L.from_cam or 0, L.err)) end
                if L.tried then imgui.text("   tried: " .. table.concat(L.tried, ", ")) end
                if L.err_msg or L.hook_err then imgui.text_colored("   listener error: " .. tostring(L.err_msg or L.hook_err), 0xFF5555FF) end
            end
            local parts = {}
            for k, n in pairs(R.pf.n) do parts[#parts + 1] = k .. " " .. n end
            table.sort(parts)
            if #parts > 0 then imgui.text("Ran: " .. table.concat(parts, ", ")) end
            if R.pf.voice_seen then imgui.text("Sound settings: " .. R.pf.voice_seen) end
            if R.pf.voice_err then imgui.text_colored("sound error: " .. R.pf.voice_err, 0xFF5555FF) end
            if R.pf.listener_err then imgui.text_colored("distance error: " .. R.pf.listener_err, 0xFF5555FF) end
        end
        imgui.tree_pop()
    end

    -- ===== 3. Test bench =====================================================================================
    if R.dev and imgui.tree_node("Test bench") then -- v0.9.114: developer mode only
        if imgui.button("Down the selected pawn (Ctrl+F10)") then R.down_pawn() end -- v0.9.121
        -- live readout
        if state.active then
            local ctl = "puppeteer (Mode 2)"
            if cfg.native_controls and native.pip and not native.failed then
                ctl = string.format("native, %d frames, %d errors", native.frames, native.errors)
            elseif cfg.native_controls and native.failed then
                ctl = "native FAILED -> puppeteer (see log)"
            end
            imgui.text(string.format("Pawn controls: %s", ctl))
        else
            imgui.text_colored("Pawn controls: not possessing", GREY)
        end
        local bcol = brain.on and GREEN or GREY
        imgui.text_colored(string.format("Arisen brain: %s%s", tostring(brain.mode), brain.solo and "  [SOLO]" or ""), bcol)
        if brain.on or brain.solo then
            imgui.text(string.format("  target %s  hp %s  %.1fm  off %.0f deg", tostring(brain.target_id),
                brain.target_hp and string.format("%.0f", brain.target_hp) or "-", brain.dist or 0, brain.off or 0))
            imgui.text(string.format("  shots %d  skills %d  injected %d  errors %d", brain.presses, brain.skill_uses, brain.inj, brain.errs))
            if brain.err then imgui.text_colored("  last error: " .. tostring(brain.err), RED) end
        end
        imgui.text(string.format("Test enemies: %d alive / %d spawned  (%d loading)", spawner.alive, spawner.spawned, #spawner.pending))

        -- spawn presets
        imgui.separator()
        imgui.text("Spawn (relative to the " .. (cfg.test_custom.around == "pawn" and "possessed pawn" or "Arisen") .. "):")
        for i, p in ipairs(TEST_PRESETS) do
            if (i - 1) % 4 ~= 0 then imgui.same_line() end
            local sel = (cfg.test_preset == i)
            if imgui.button((sel and "> " or "") .. p.label .. "##preset" .. i) then
                cfg.test_preset = i
                save_cfg()
                local spec = { enemy = p.enemy, count = p.count, dist = p.dist, angle = p.angle, still = p.still, around = cfg.test_custom.around }
                enqueue_game_thread("UI spawn " .. p.label, function() spawn_test(spec) end)
            end
        end
        if cfg.test_preset > 0 and TEST_PRESETS[cfg.test_preset] then
            imgui.text_colored("  F9 repeats: " .. TEST_PRESETS[cfg.test_preset].label .. "  (" .. TEST_PRESETS[cfg.test_preset].note .. ")", GREY)
        end
        if imgui.tree_node("Custom spawn") then
            local c = cfg.test_custom
            local ch1, ch2, ch3, ch4, ch5, ch6
            ch1, c.enemy = imgui.combo("Enemy", c.enemy, TEST_ENEMY_NAMES)
            ch2, c.count = imgui.slider_int("Count", c.count, 1, 8)
            ch3, c.dist = imgui.slider_float("Distance (m)", c.dist, 3.0, 40.0)
            ch4, c.angle = imgui.slider_int("Angle (deg, + = right)", c.angle, -180, 180)
            ch5, c.still = imgui.checkbox("Target dummy (stands still)", c.still)
            imgui.same_line()
            local around_pawn = c.around == "pawn"
            ch6, around_pawn = imgui.checkbox("Around the possessed pawn", around_pawn)
            c.around = around_pawn and "pawn" or "arisen"
            if ch1 or ch2 or ch3 or ch4 or ch5 or ch6 then save_cfg() end
            if imgui.button("Spawn custom [Ctrl+F9]") then
                cfg.test_preset = 0
                save_cfg()
                local spec = { enemy = c.enemy, count = c.count, dist = c.dist, angle = c.angle, still = c.still, around = c.around }
                enqueue_game_thread("UI spawn custom", function() spawn_test(spec) end)
            end
            imgui.tree_pop()
        end
        if imgui.button("Despawn test enemies [F10]") then enqueue_game_thread("UI despawn", despawn_tests) end
        imgui.same_line()
        if imgui.button("Mark this moment [Shift+F9]") then enqueue_game_thread("UI mark", function() test_mark("button") end) end

        -- test switches
        imgui.separator()
        chg, cfg.test_hotkeys = imgui.checkbox("Test hotkeys: F9 spawn, Ctrl+F9 custom spawn, Shift+F9 mark, F10 despawn, F11 brain on/off", cfg.test_hotkeys)
        if chg then save_cfg() end
        chg, brain.solo = imgui.checkbox("Brain drives the Arisen with nothing possessed (your input is ignored!)", brain.solo)
        chg, cfg.arisen_brain_telemetry = imgui.checkbox("Brain telemetry -> data/DPC_arisen_brain.json", cfg.arisen_brain_telemetry)
        if chg then save_cfg() end
        imgui.same_line()
        chg, cfg.debug_input = imgui.checkbox("Input log", cfg.debug_input)
        if chg then save_cfg() end
        imgui.tree_pop()
    end

    -- ===== 4. Pawn action buttons (possessed) ================================================================
    if state.active and imgui.tree_node("Pawn action buttons") then
        if imgui.button("Light attack") then enqueue_game_thread("UI Light Attack", function() pawn_do_attack(false, 0, 0, 0, 0) end) end
        imgui.same_line()
        if imgui.button("Heavy attack") then enqueue_game_thread("UI Heavy Attack", function() pawn_do_attack(true, 0, 0, 0, 0) end) end
        imgui.same_line()
        if state.pawn_job == 1 then
            if imgui.button(state.is_guarding and "Stop defend" or "Defend") then
                enqueue_game_thread("UI Toggle Guard", function() pawn_set_fighter_guard(not state.is_guarding, 0, 0, 0) end)
            end
            imgui.same_line()
        end
        if imgui.button("Jump") then enqueue_game_thread("UI Jump", function() pawn_do_jump(0, 0, 0, 0) end) end
        imgui.same_line()
        if imgui.button("Draw") then enqueue_game_thread("UI Draw", function() pawn_do_draw() end) end
        imgui.same_line()
        if imgui.button("Sheathe") then enqueue_game_thread("UI Sheathe", function() pawn_do_sheathe() end) end
        local cur_skills = state.pawn_skills or { 0, 0, 0, 0, 0, 0 }
        for s = 1, 6 do
            local slot_idx = s
            if s <= 4 or (cur_skills[s] or 0) ~= 0 then
                if s > 1 then imgui.same_line() end
                if imgui.button(string.format("[%d] %s##sk%d", s, skill_name(cur_skills[s]), s)) then
                    enqueue_game_thread("UI Skill " .. s, function() pawn_do_skill_slot(slot_idx, 0, 0, 0, 0) end)
                end
            end
        end
        imgui.tree_pop()
    end

    -- ===== 5. Tuning & experimental ==========================================================================
    if imgui.tree_node("Brain, co-op and control tuning") then
        imgui.text("Arisen brain")
        local c1, c2, c3, c4, c5, c6
        c1, cfg.arisen_brain_keep_min = imgui.slider_float("Back off inside (m)", cfg.arisen_brain_keep_min, 2.0, 15.0)
        c2, cfg.arisen_brain_keep_max = imgui.slider_float("Approach beyond (m)", cfg.arisen_brain_keep_max, 8.0, 35.0)
        c3, cfg.arisen_brain_shot_cd = imgui.slider_float("Seconds between shots", cfg.arisen_brain_shot_cd, 0.3, 3.0)
        c4, cfg.arisen_brain_skill_cd = imgui.slider_float("Seconds between skills", cfg.arisen_brain_skill_cd, 2.0, 30.0)
        c5, cfg.arisen_brain_skill_hold = imgui.slider_float("Skill button hold (s)", cfg.arisen_brain_skill_hold, 0.1, 2.0)
        c6, cfg.arisen_brain_face_tol = imgui.slider_float("Facing tolerance (deg)", cfg.arisen_brain_face_tol, 2.0, 30.0)
        local c7
        c7, cfg.arisen_brain_stuck_s = imgui.slider_float("Sidestep after no damage for (s, 0 = never)", cfg.arisen_brain_stuck_s, 0.0, 20.0)
        if c1 or c2 or c3 or c4 or c5 or c6 or c7 then save_cfg() end
        chg, cfg.arisen_own_lockon = imgui.checkbox("Give the Arisen his own lock-on while a pawn is played", cfg.arisen_own_lockon)
        if chg then save_cfg() end
        chg, cfg.arisen_brain_lock = imgui.checkbox("Lock his lock-on onto the brain's target (needed for hits and skills)", cfg.arisen_brain_lock)
        if chg then save_cfg() end
        chg, cfg.arisen_brain_keep_hud_redirect = imgui.checkbox("Keep HUD job/skill redirect while the brain runs (may break his archery)", cfg.arisen_brain_keep_hud_redirect)
        if chg then save_cfg() end
        chg, cfg.arisen_brain_any_job = imgui.checkbox("Ranged brain on every other vocation (untested)", cfg.arisen_brain_any_job)
        if chg then save_cfg() end

        imgui.separator()
        imgui.text("Couch co-op")
        chg, cfg.coop_zero_pad_for_arisen = imgui.checkbox("Arisen ignores the controller's buttons (processButton)", cfg.coop_zero_pad_for_arisen)
        if chg then save_cfg() end
        chg, cfg.coop_block_p2_stick = imgui.checkbox("Player 2's left stick doesn't move the Arisen", cfg.coop_block_p2_stick)
        if chg then save_cfg() end
        chg, cfg.coop_block_p2_camera = imgui.checkbox("Player 2's right stick doesn't turn the camera", cfg.coop_block_p2_camera)
        if chg then save_cfg() end
        local ch_b
        ch_b, cfg.coop_map_assign = imgui.checkbox("Player 2's buttons follow the game's controller settings", cfg.coop_map_assign)
        if ch_b then
            coop.map = nil
            save_cfg()
        end
        if coop.map_src then imgui.text("   in use: " .. tostring(coop.map_src)) end

        imgui.separator()
        imgui.text("Pawn controls")
        chg, cfg.native_skip_thief = imgui.checkbox("Thief pawns use the puppeteer instead of native controls", cfg.native_skip_thief)
        if chg then
            save_cfg()
            if state.active then
                enqueue_game_thread("UI toggle native_skip_thief", function()
                    if cfg.native_controls then native_build() else native_release() end
                end)
            end
        end
        chg, cfg.raw_mouse_fallback = imgui.checkbox("Raw LMB/RMB fallback (only if AttackS/AttackL are unbound)", cfg.raw_mouse_fallback)
        if chg then save_cfg() end
        for _, m in ipairs({ 2, 1, 3 }) do
            local active_m = (cfg.control_mode == m)
            local chg_m, new_val = imgui.checkbox(MODE_LABELS[m], active_m)
            if chg_m and new_val and not active_m then
                local target_m = m
                enqueue_game_thread("UI switch_control_mode", function() switch_control_mode(target_m) end)
            end
        end
        if imgui.tree_node("Subsystems") then
            chg, cfg.sub_camera_attach = imgui.checkbox("Attach camera to pawn", cfg.sub_camera_attach)
            if chg then save_cfg() end
            chg, cfg.sub_disable_arisen_pip = imgui.checkbox("Block Arisen input processor while possessing", cfg.sub_disable_arisen_pip)
            if chg then save_cfg() end
            chg, cfg.sub_suppress_ai = imgui.checkbox("Suppress pawn AI", cfg.sub_suppress_ai)
            if chg then save_cfg() end
            chg, cfg.sub_puppeteer_move = imgui.checkbox("Puppeteer movement", cfg.sub_puppeteer_move)
            if chg then save_cfg() end
            chg, cfg.sub_puppeteer_combat = imgui.checkbox("Puppeteer combat & skills", cfg.sub_puppeteer_combat)
            if chg then save_cfg() end
            chg, cfg.sub_mirror_input_flags = imgui.checkbox("Mirror buttons & stick to pawn input", cfg.sub_mirror_input_flags)
            if chg then save_cfg() end
            imgui.tree_pop()
        end
        if imgui.tree_node("Mode 1 / Mode 3 flags") then
            chg, cfg.exp_rebind_lockon = imgui.checkbox("Rebind LockOnCtrl.Chara to pawn", cfg.exp_rebind_lockon)
            if chg then save_cfg() end
            chg, cfg.exp_swap_inputs = imgui.checkbox("Swap CharacterInput between Arisen & pawn", cfg.exp_swap_inputs)
            if chg then save_cfg() end
            chg, cfg.swap_player_comp_refs = imgui.checkbox("Rebind app.Player.Chara/Human to pawn", cfg.swap_player_comp_refs)
            if chg then save_cfg() end
            chg, cfg.swap_manual_player = imgui.checkbox("CharacterManager:setManualPlayer(pawn)", cfg.swap_manual_player)
            if chg then save_cfg() end
            chg, cfg.set_human_is_arisen = imgui.checkbox("Pawn Human.IsArisen = true while possessed", cfg.set_human_is_arisen)
            if chg then save_cfg() end
            imgui.tree_pop()
        end
        imgui.tree_pop()
    end

    -- ===== 6. Diagnostics ====================================================================================
    if imgui.tree_node("Diagnostics & log") then
        imgui.text("Camera target: " .. tostring(ui_cache.cam_id))
        if state.active and state.pawn_chara then
            imgui.text(string.format("Frames possessed %d | Arisen processor blocked %d", state.frames_since_start, state.arisen_pip_blocked_count))
            imgui.text(string.format("On 0x%X | Trg 0x%X | weapon drawn %s", state.last_on_flags, state.last_trg_flags, tostring(ui_cache.weapon_drawn)))
            imgui.text(string.format("Stick %.2f | sprint %s | guard %s | last action %s",
                state.last_stick_mag, tostring(state.is_sprinting), tostring(state.is_guarding), state.last_action_str))
        end
        imgui.separator()
        for i = math.max(1, #logs - 15), #logs do imgui.text(logs[i]) end
        imgui.tree_pop()
    end
    end -- cfg.show_legacy

    imgui.end_window()
end)

re.on_frame(function()
    local now = os.clock()
    if coop.tgt_status_due then coop.tgt_status_due = false; coop_write_status() end
    if now < dev.next then return end
    dev.next = now + 1.0
    if (brain.errs or 0) > dev.seen_brain_errs then
        dev.errors = dev.errors + (brain.errs - dev.seen_brain_errs)
        dev.seen_brain_errs = brain.errs
        dev.last_error, dev.last_error_t = "brain: " .. tostring(brain.err), now
    end
    local info = (coop.active and "co-op" or (state.active and ("possessing " .. tostring(state.pawn_name)) or "idle"))
        .. " | brain " .. tostring(brain.mode)
        .. ((coop.active and cfg.coop_auto_target) and (" | p2 target " .. tostring(coop.tgt_name or "none") .. string.format(" (range %.0f m)", coop.tgt_range or 0)) or "")
        .. ((robot.pad or robot.arisen) and " | ROBOT" or "")
    R.dump("dev_status/DirectPawnControl.json", {
        mod = "DirectPawnControl", version = VERSION, t = now, errors = dev.errors,
        last_error = dev.last_error, last_error_t = dev.last_error_t, save_ok = dev.save_ok, info = info,
        aim = { hold = R.aim_hold == true, blocked = R.aim_blocked or 0, reqs = R.aim_reqs or 0, learned = R.aim_enter ~= nil, off = R.aim_off == true,
dash_label = { text = R.dash_n_text or 0, seen = R.dash_seen, repoints = R.hud_repoints or 0, slots = R.dash_slots, puts = R.dash_puts or 0 },
    flash = { skips = R.danger_skips or 0, flag_clears = R.danger_flag_clears or 0, flow_resets = R.danger_flow_resets or 0, hides = R.danger_hides or 0, unstuck = R.danger_unstuck or 0 },
            pt_x = R.aim_pt_x, pt_y = R.aim_pt_y, dp_x = R.aim_dp_x, dp_y = R.aim_dp_y, fixes = R.aim_fixes or 0, hip_aims = R.hip_aim_n or 0, ret_fail = R.aim_ret_fail == true, setting = R.aim_set, setups = R.aim_setups or 0, evals = R.aim_evals or 0, aim_skills = R.aim_skill_n or 0,
            dist = R.aim_last_d, ray_errs = R.aim_ray_errs or 0, ray_off = R.aim_ray_off == true },
        gyro = { blocked = R.gyro_blocked or 0, cleared = R.gyro_cleared or 0 },
        arrows = R.arrows and R.arrows.n or nil,
        stam_joint = R.stam_joint_name,
    })
end)

log_msg("DirectPawnControl v" .. VERSION .. " loaded (Default: Safe Mode 2). Press F6 to possess Main Pawn.")
coop_write_status() -- v0.9: CameraDistance polls this file; make sure it exists (inactive) from the start
