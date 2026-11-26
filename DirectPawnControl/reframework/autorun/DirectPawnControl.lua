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

local VERSION = "0.9.178"

-- 0.9.178: the script is split into the files in reframework/autorun/DirectPawnControl/, one per part, with no
-- change in behaviour. This file loads them in the order below, which is the order the single file ran in
-- (settings first, the settings window last), so hooks and callbacks are registered in the same order as before.
-- REFramework only runs the files directly in reframework/autorun, so the folder's files run only from here.
-- What the parts share goes through one table (DirectPawnControl/shared.lua); see that file.
local MODULES = {
    "config", "helpers", "party", "brain", "hooks", "camera_hud", "native_controls", "possession", "coop", "input",
    "follow", "aim_binds", "fixes_combat", "fixes_world", "actions", "puppeteer", "testbench", "coop_players",
    "second_pawn", "more_players", "cards", "tick", "player_feel", "coop_sound", "api", "ui"
}
-- A script reset (or a second load in the same Lua state) runs every part again instead of reusing old copies.
for k in pairs(package.loaded) do
    if type(k) == "string" and k:sub(1, 18) == "DirectPawnControl/" then package.loaded[k] = nil end
end
local function load_part(name)
    local ok, part = pcall(require, "DirectPawnControl/" .. name)
    if not ok then
        error("Direct Pawn Control " .. VERSION .. ": reframework/autorun/DirectPawnControl/" .. name .. ".lua did not load"
            .. " (the DirectPawnControl folder must sit next to DirectPawnControl.lua): " .. tostring(part), 0)
    end
    return part
end
local S = load_part("shared")
S.VERSION = VERSION
for _, name in ipairs(MODULES) do load_part(name) end
