-- Direct Pawn Control: the Arisen's combat brain (he fights like a pawn of his vocation while you play a pawn).
-- Part of DirectPawnControl.lua, which loads the files in this folder in order (this one is 04 of 26).
-- Never run on its own: REFramework only runs the files directly in reframework/autorun.
local S = require("DirectPawnControl/shared")
local VERSION, robot, dev_error, cfg, R, log_msg = S.VERSION, S.robot, S.dev_error, S.cfg, S.R, S.log_msg
local same_obj, call, get_job, get_skills, get_party = S.same_obj, S.call, S.get_job, S.get_skills, S.get_party
local state, addr_of = S.state, S.addr_of

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

local function brain_flag(name) return S.ACTION_FLAGS[name] or 0 end

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
    if S.get_cam_angle_rad_method then
        local ok, r = pcall(S.get_cam_angle_rad_method.call, S.get_cam_angle_rad_method, nil)
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
        -- 0.9.177: the Arisen is reviving someone with a Wakestone for the player (R.rev_npc_*): hands off
        if R.brain_hold_until and os.clock() < R.brain_hold_until then brain.mode = "paused (Wakestone revive)"; return end
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
    -- 0.9.178-dev8: both players on pawns: player 2's right stick turns the shared camera (R.cp_cam_add)
    if ok and R.cp_cam_add then pcall(R.cp_cam_add, inp) end
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
            pad_device = S.pad_device_ok, pad_stick = coop.last_stick,
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

-- shared with the modules loaded after this one (see shared.lua)
S.brain, S.coop, S.COOP_OVERRIDES, S.coop_event, S.brain_event = brain, coop, COOP_OVERRIDES, coop_event, brain_event
S.brain_flag, S.brain_pos, S.brain_facing, S.brain_angdiff = brain_flag, brain_pos, brain_facing, brain_angdiff
S.brain_alive, S.brain_stick_for, S.brain_tick = brain_alive, brain_stick_for, brain_tick
S.SET_TARGET_SIG, S.REMOVE_TARGET_SIG, S.brain_lock_apply = SET_TARGET_SIG, REMOVE_TARGET_SIG, brain_lock_apply
S.brain_lock_restore, S.brain_restore_input, S.brain_inject = brain_lock_restore, brain_restore_input, brain_inject
S.brain_dump = brain_dump
