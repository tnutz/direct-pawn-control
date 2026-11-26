-- Direct Pawn Control: dev status, robot player, configuration (cfg), saved settings, possession state, the R table.
-- Part of DirectPawnControl.lua, which loads the files in this folder in order (this one is 01 of 26).
-- Never run on its own: REFramework only runs the files directly in reframework/autorun.
local S = require("DirectPawnControl/shared")
local VERSION = S.VERSION


-- v0.9.7 Dev HUD status (TestGuide 2.0 shows it): errors that used to be swallowed by pcall, and whether the
-- settings file saved. Written to data/dev_status/DirectPawnControl.json once a second.
local dev = { errors = 0, last_error = nil, last_error_t = nil, save_ok = nil, next = 0, seen_brain_errs = 0 }
-- v0.9.7 robot player (for unattended tests; driven by the "robot" command, usually from a TestGuide step):
--   pad:    fakes player 2's controller as DPC sees it (co-op input, DPC pad combos). Not the game's own pad read.
--   arisen: drives the Arisen through the brain's input injection (stick + action flags), bypassing the brain's rules.
-- Each entry expires on its own (secs), so a lost command can never leave a button held.
local robot = { pad = nil, arisen = nil, uses = 0 }
local dev_error_seen = {}
local function dev_error(where, err)
    dev.errors = dev.errors + 1
    dev.last_error, dev.last_error_t = where .. ": " .. tostring(err), os.clock()
    -- 0.9.176-dev17: the first error of each kind goes to the log too (these were invisible: a stop that failed
    -- every frame left no trace)
    if not dev_error_seen[where] then
        dev_error_seen[where] = true
        pcall(function() log.info("[DirectPawnControl] error in " .. where .. ": " .. tostring(err)) end)
    end
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
    coop_glow_split = false,
    coop_aim_markers_split = false, -- dev58: target markers while the screen is split (coop_aim_markers is the shared screen's)
    coop_kb_next_pad = true,        -- dev57: co-op started from the keyboard: the first controller used afterwards is player 2's (no L3 + R3)        -- dev56: the join and kept glows also in split screen (off: each player has their own view, so who is who is clear)
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
    coop_auto_resume = true,          -- 0.9.178-dev10: on by default, and it puts every player back on their character (the tester). Co-op starts again by itself after cutscenes, Ferrystones, loading or a downed pawn
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
    pawn_revive_npc = true,           -- 0.9.177: player 1's pawn gets a Revive prompt on a dead person; the Arisen comes and uses a Wakestone (the game's own revive)
    party_warp_arisen = true,         -- 0.9.177: Numpad 7 (warp every pawn to you) also brings the Arisen while you play a pawn
    coop_end_keep_p1 = true,          -- 0.9.177: when co-op ends, player 1 stays on the character he was playing
    coop_player_card = true,
    card_layout = 2,                  -- 0.9.178-dev7: a row at the bottom middle by default again (the tester). 0.9.177: where the cards go: 1 each player's own spot (dev9), 2 a row at the bottom middle, 3 a stack at the bottom middle, 4 (dev49, default) stacked at the side, off the characters
    card_layout_split = 1,            -- dev53: cards in split screen (each in its player's own view): 1 at the side, 2 bottom middle. card_layout is for a shared screen only
    card_side = 1,                    -- dev49: layout 4: 1 left, 2 right (of the screen, or of each player's view in split screen)
    card_side_x = 0.01,               -- dev49: layout 4: distance from that edge (share of the width)
    card_side_bottom = 0.97,          -- dev49: layout 4: bottom of the lowest card (share of the height); dev52: 0.80 -> 0.97 (lower, the screen bottom is free)
    card_p1_split_native = true,      -- dev52: in split screen player 1 keeps the game's own HUD (no card for player 1)
    card_palette = 4,                 -- 1 always the skills, 2 like the game's own (a list), 3 skills and actions together, 4 controller-shaped, fixed size (dev22, the tester: the list "wiggles")
    card_bars = 4,                    -- dev33: card and OVER the character (reported: "UI blocks feet bars a lot"); 5 = card and under
    card_items = 1,                   -- the D-pad item lines: 1 always, 2 only while the D-pad is touched or an item runs low (1 left), 3 never
    card_bg_alpha = 0.50,             -- card background opacity (dev22: lighter, the tester)
    card_p1 = false,                  -- dev22: player 1 gets a card too in co-op (else the game's own HUD only)
    card_p1_mode = 3,                 -- 0.9.178-dev6: card only by default in a shared screen (the tester: "the consistent interface with P2 so they can each see themselves glow with their health and stam overhead"; split screen still gives player 1 the game's HUD, card_p1_split_native). dev29: player 1's HUD in co-op: 1 the game's, 2 the game's + a card, 3 a card only (the game's skills and gauges hidden)
    card_grid_w = 460,                -- dev29: width of the controller-shaped card (360 cut the labels)
    pawn_input_order = false,         -- dev24: a played pawn's input runs right before its own Human.update, where the Arisen's runs (no state faking). dev25: off until measured (blind melee 1 / 5)
    pawn_lockon_from_pawn = true,     -- dev25: the game's lock-on measures targets from the played pawn, not the Arisen (single player)
    pawn_rumble_follow = true,        -- dev34: controller rumble comes from the character you play (the game only rumbles for ManualPlayer, the Arisen)
    pawn_player_identity = false,     -- 0.9.177-dev31 pilot: while the game runs the played pawn's own input / movement / skills / combat, it is told the pawn is the player (off until tested)
    pid_groups = { input = true, move = true, spell = true, skill = true, combat = true, interact = true, human = true, feedback = true },
    coop_dpad_orders = 2,             -- dev23: a co-op player's plain D-pad press: 1 nothing, 2 the pawn order + a gesture, 3 the gesture only (a signal)
    card_bottom = 0.985,              -- bottom edge of the row / stack (share of the screen height)          -- 0.9.177: each co-op player 2+ gets one card: coloured title bar, bars, skills, D-pad items
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
    possess_unlean = true,            -- 0.9.176: a pawn leaning on a wall (object interaction) stands up before you take it over
    galvanize_watch = true,           -- 0.9.178-dev2: log one "Galvanize watch" line per Mage / Sorcerer Galvanize hold (reads only)
    pawn_stale_dash_fix = true,       -- 0.9.178-dev2: clear a played pawn's IsDash left on while the stick is at rest (stamina keeps draining)
    dev_trace_frames = 0,             -- 0.9.176-dev1 (dev): trace every stage of the first N frames after a take-over
    pawn_interact = true,             -- v0.9.26: the possessed pawn gathers / loots himself (own prompt + Interact button)
    pawn_loot_to_arisen = false,      -- 0.9.174: what the played pawn loots / gathers goes into the Arisen's bag (as in vanilla); other mods can set it (DPC_API.override)
    pawn_interact_range = 2.2,        -- m
    cycle_switches_now = false,       -- v0.9.90: F7 while possessing switches pawn at once (the old behaviour) instead of selecting
    show_legacy = false,              -- v0.9.82: the advanced / test / legacy bin of the settings window
    arisen_no_interact = true,        -- 0.9.177: while you play a pawn (not co-op), the Arisen gets no interact prompt (loot, talk, examine) and can't use one
    pawn_prev_state = true,
    pawn_prev_move = true,            -- 0.9.177-dev21: with pawn_prev_state, also the move state (off = attack and skill state only; under test: the tester felt aiming "pulled")           -- 0.9.177: a played pawn's input processor sees last frame's attack / skill / move state, as the Arisen's does (see R.pipfix)
    exp_pawn_cbt = false,             -- 0.9.176-dev12 (experiment, was pawn_job_input): run the Arisen's customizeButtonTrigger on the played pawn's processor. Measured: L2 already carries ActCancel for every vocation, so this changed nothing for the cancel
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
    coop_menus_p1 = true,             -- 0.9.178-dev12: with player 2 on the Arisen, player 1's controller drives the game's menus (the tester)
    coop_any_p2_arisen = "classic",   -- 0.9.178-dev6: "classic" by default (test PC: with "brain", player 2's Arisen walked the way he faced, not where the stick pointed, and turned to things on his own; player 2 had no camera). 0.9.171: player 2 on the Arisen (two controllers): "brain" = player 1 keeps the camera, player 2's controller drives the Arisen; "classic" = the Arisen takes player 2's controller and the camera
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
    migrated_0176 = false,
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
S.pad_buttons, S.pad_prev = 0, 0
S.pad_stick_x, S.pad_stick_y = 0.0, 0.0
S.pad_stick_rx, S.pad_stick_ry = 0.0, 0.0
S.is_key_down_safe = nil -- v0.9.1: forward declaration; coop.filter called it as an undefined global
S.pad_device_ok = nil -- nil = not polled yet, false = no controller device, true = reading it

S.coop_saved_for_cfg = nil -- set while co-op overrides are applied (see coop_apply_overrides)
local function save_cfg()
    cfg.version_tag = "v5"
    if json and json.dump_file then
        local cur = nil
        if S.coop_saved_for_cfg then
            cur = {}
            for k, v in pairs(S.coop_saved_for_cfg) do cur[k] = cfg[k]; cfg[k] = v end
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
if (tonumber(cfg.card_v) or 0) < 1 then -- dev28: dev12's card defaults were saved into configs; dev22's never reached them (cards shrank on L1)
    if cfg.card_palette == 2 then cfg.card_palette = 4 end
    if cfg.card_bars == 1 then cfg.card_bars = 5 end
    if cfg.card_bg_alpha == 0.8 then cfg.card_bg_alpha = 0.5 end
    cfg.card_v = 1
    save_cfg()
end
if (tonumber(cfg.card_v) or 0) < 2 then -- dev33: bars over the character by default (the card UI covered the ones at the feet)
    if cfg.card_bars == 5 then cfg.card_bars = 4 end
    cfg.card_v = 2
    save_cfg()
end
if cfg.io_off_v ~= 1 then -- dev27: dev24's input-order fix (default then) was saved into configs; it scored 1 / 5
    cfg.pawn_input_order, cfg.io_off_v = false, 1
    save_cfg()
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
if not cfg.migrated_card_low then -- 0.9.177-dev52: side cards sit lower
    if (cfg.card_side_bottom or 0.80) == 0.80 then cfg.card_side_bottom = 0.97 end
    cfg.migrated_card_low = true
end
if not cfg.migrated_card_side then -- 0.9.177-dev49: cards at the side by default (the old default sat over the characters)
    if (cfg.card_layout or 2) == 2 then cfg.card_layout = 4 end
    cfg.migrated_card_side = true
end
if not cfg.migrated_auto_resume then -- 0.9.178-dev10: co-op comes back after a Ferrystone / cutscene by default
    cfg.coop_auto_resume = true
    cfg.migrated_auto_resume = true
end
if not cfg.migrated_card_row then -- 0.9.178-dev7: the row at the bottom middle is the default again (the tester)
    if cfg.card_layout == 4 then cfg.card_layout = 2 end
    cfg.migrated_card_row = true
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
if not cfg.migrated_0176 then
    -- 0.9.176: two settings that dev test plans (tavern-lean-4..7) switched for a step and that the next save kept:
    -- the AI interrupt at take-over (off = a taken-over pawn ran on with its AI's last move) and the take-over trace.
    -- Only where the trace is on (a dev-only setting no player changes), so a player's own choice stays.
    if (cfg.dev_trace_frames or 0) ~= 0 then
        cfg.possess_interrupt_ai = true
        cfg.dev_trace_frames = 0
    end
    cfg.migrated_0176 = true
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

-- shared with the modules loaded after this one (see shared.lua)
S.dev, S.robot, S.dev_error, S.TRACE_PATH, S.cfg, S.save_cfg = dev, robot, dev_error, TRACE_PATH, cfg, save_cfg
S.R = R
