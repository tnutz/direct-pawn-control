-- Direct Pawn Control: stamina bars, attacks, skills, chant / cancel, jump, Fighter guard.
-- Part of DirectPawnControl.lua, which loads the files in this folder in order (this one is 15 of 26).
-- Never run on its own: REFramework only runs the files directly in reframework/autorun.
local S = require("DirectPawnControl/shared")
local cfg, save_cfg, R, log_msg, call, field = S.cfg, S.save_cfg, S.R, S.log_msg, S.call, S.field
local SPEED_IDLE, skill_name, get_job, get_skills = S.SPEED_IDLE, S.skill_name, S.get_job, S.get_skills
local get_party, state, addr_of, brain, coop, native = S.get_party, S.state, S.addr_of, S.brain, S.coop, S.native
local compute_camera_move_angle_deg = S.compute_camera_move_angle_deg
local update_pawn_lockon_target, node_names = S.update_pawn_lockon_target, S.node_names

R.stam_calc = function()
    if not (coop.active and cfg.coop_stamina_bar and state.pawn_chara) then R.stam_x = nil; return end
    if cfg.coop_player_card ~= false and cfg.coop_skill_palette then R.stam_x = nil; return end -- dev22: the cards show the bars
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
    if R.cards_world_on and R.cards_world_on() then return end -- dev32: co-op with player 2 on the Arisen: his card bars are under him already
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
if R.dev then _G.DPC_dbg = { native = native, state = state, R = R, brain = brain, cfg = cfg, coop = coop, af = function() return S.ACTION_FLAGS end, save = function() save_cfg() end } end -- dev only: lets TestGuide plans read the pawn's processor
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

-- 0.9.177-dev3 (dev): chant_test, driven by the test bench. Steps per slot: cast, wait press_after, press, wait 1.6 s.
function R.chant_test_start(rounds, press_after)
    if not state.active then
        for _, e in ipairs(get_party()) do
            if e.job == 3 or e.job == 6 then
                R.chant_t = { phase = "possess", idx = e.idx, t = os.clock() + 2.5, rounds = rounds, pa = press_after }
                R.start_possession(e.idx)
                log_msg("chant_test: taking " .. tostring(e.name) .. " (job " .. e.job .. ")")
                return "taking " .. tostring(e.name)
            end
        end
        return "no Mage / Sorcerer pawn in the party"
    end
    R.chant_t = { phase = "next", slot = 0, t = os.clock(), rounds = rounds, round = 1, pa = press_after }
    return "started"
end

function R.chant_test_tick()
    local c = R.chant_t
    if not c or os.clock() < c.t then return end
    if c.phase == "possess" then
        if not state.active then log_msg("chant_test: take-over did not happen"); R.chant_t = nil; return end
        c.phase, c.slot, c.round, c.t = "next", 0, 1, os.clock() + 0.5
        return
    end
    if not state.active then log_msg("chant_test: no longer playing a pawn, stopped"); R.chant_t = nil; return end
    if c.phase == "next" then
        c.slot = c.slot + 1
        if c.slot > 4 then
            if c.round >= c.rounds then log_msg("chant_test: done"); R.chant_t = nil; return end
            c.round, c.slot = c.round + 1, 1
        end
        local ok = R.do_skill_slot and R.do_skill_slot(c.slot)
        local sk = call(state.pawn_human, "get_CustomSkillState") or 0
        log_msg(string.format("chant_test round %d slot %d: cast %s", c.round, c.slot, ok and "requested" or "failed/empty"))
        if c.round == 1 and c.slot == 1 and R.dev then R.op = { until_t = os.clock() + 2.0, seq = 0, rows = {}, n = 0 } end
        c.phase, c.t = "press", os.clock() + c.pa
    elseif c.phase == "press" then
        local sk = call(state.pawn_human, "get_CustomSkillState") or 0
        if sk == 0 then
            log_msg(string.format("chant_test slot %d: no skill running at the press, skipped", c.slot))
            c.phase, c.t = "next", os.clock() + 1.0
            return
        end
        log_msg(string.format("chant_test slot %d: pressing cancel during %s", c.slot, skill_name(sk)))
        R.ct_press = true
        c.phase, c.t = "next", os.clock() + 1.6
    end
end

-- 0.9.176-dev9: end the played pawn's current skill (chant cancel). Logs whether it took.
function R.cancel_skill(sk, why)
    local sel = state.pawn_chara and call(state.pawn_chara, "get_HumanActionSelector")
    if not sel then return false end
    call(sel, "requestEndAction()")
    local cur_sel = field(sel, "CurrentSelector")
    if cur_sel then call(cur_sel, "requestEndAction()") end
    state.active_cast = nil
    state.pending_skill = nil
    R.cancel_n = (R.cancel_n or 0) + 1
    R.cancel_check = { t = os.clock() + 0.25, sk = sk, n = R.cancel_n }
    log_msg(string.format("%s during %s: requestEndAction (%d)", why or "cancel", skill_name(sk), R.cancel_n))
    return true
end

-- dev14: the gates the game's sheathe / cancel code checks (read from DD2.exe 4.1: processSheathe, processCancelSkill)
function R.cancel_gates(sk)
    local function tr(t)
        if not t then return "nil" end
        local function b(n) return field(t, n) and "1" or "0" end
        return "Cancel " .. b("Cancel") .. " CancelBuf " .. b("CancelBuffer") .. " All " .. b("All") .. " AllBuf " .. b("AllBuffer")
            .. " SpFlag " .. b("SpecialFlag") .. " NormAtk " .. b("NormalAttack") .. " ClrNA " .. b("IsClearNormalAttack")
    end
    local pip = native.pip
    local hu, ch = state.pawn_human, state.pawn_chara
    local wd = ch and field(ch, "WeaponDrawContext")
    local pt = pip and call(pip, "get_PlayerTrack")
    -- processCancelSkill's last gate (DD2.exe 4.1, PlayerInputProcessorDetail.isSkillCancelable): Human.AttackState == 3
    -- (Skill) and Character.EachTempStatus.PrevData has PrepareSkill (bit 38). Job03 adds two node checks first.
    pcall(function()
        local ts = field(ch, "<EachTempStatus>k__BackingField")
        local d, pd = ts and field(ts, "Data"), ts and field(ts, "PrevData")
        local function bits(v)
            if type(v) ~= "number" then return tostring(v) end
            local t = {}
            for _, b in ipairs({ 36, 37, 38, 39, 41, 45 }) do if (v >> b) & 1 == 1 then t[#t + 1] = tostring(b) end end
            return table.concat(t, ",")
        end
        local am = field(ch, "<ActionManager>k__BackingField")
        local h1 = am and call(am, "getCurrentActionHash", 1)
        local h0 = am and call(am, "getCurrentActionHash", 0)
        log_msg(string.format("gates2 %s: temp Data bits[%s] Prev bits[%s] (37 PrepareSpell, 38 PrepareSkill, 45 Concentrate) action hash L0 %s L1 %s",
            skill_name(sk), bits(d), bits(pd), h0 and string.format("%x", h0 & 0xFFFFFFFF) or "?", h1 and string.format("%x", h1 & 0xFFFFFFFF) or "?"))
    end)
    log_msg(string.format("gates %s: drawn=%s disSheathe=%s atkState=%s pipTrack=%s | Track: %s | Upper: %s | input same=%s",
        skill_name(sk), tostring(wd and field(wd, "IsDrawedWeapon")), tostring(pip and field(pip, "IsDisableSheatheButton")),
        tostring(hu and call(hu, "get_AttackState")),
        (pt and hu and addr_of(pt) == addr_of(field(hu, "Track"))) and "Track" or (pt and hu and addr_of(pt) == addr_of(field(hu, "UpperTrack"))) and "Upper" or tostring(pt),
        tr(hu and field(hu, "Track")), tr(hu and field(hu, "UpperTrack")),
        tostring(ch and state.pawn_input and addr_of(call(ch, "get_Input")) == addr_of(state.pawn_input))))
end

function R.cancel_pending_tick()
    local c = R.cancel_pending
    if not c or os.clock() < c.t then return end
    R.cancel_pending = nil
    local now_sk = state.pawn_human and call(state.pawn_human, "get_CustomSkillState") or 0
    if now_sk == c.sk then R.cancel_skill(c.sk, "L2")
    else log_msg("L2: the game ended " .. skill_name(c.sk) .. " by itself") end
end

function R.cancel_check_tick()
    local c = R.cancel_check
    if not c or os.clock() < c.t then return end
    R.cancel_check = nil
    local now_sk = state.pawn_human and call(state.pawn_human, "get_CustomSkillState") or 0
    log_msg(string.format("cancel %d: skill %s after 0.25 s (%s)", c.n, skill_name(now_sk),
        (now_sk == c.sk) and "STILL ACTIVE" or "ended"))
end

R.do_skill_slot = function(n) return pawn_do_skill_slot(n, 0, 0, 0, 0) end

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

-- 0.9.178-dev2 (from 0.9.177-dev1) Galvanize watch (PXXXND's report, Nexus 2026-11-22: "Galvanize on my controlled
-- Sorcerer pawn doesn't restore stamina"). The cause is not known yet, so this only measures. While a Mage /
-- Sorcerer (the played pawn, or the Arisen when nothing is played, as a baseline) holds JobSpecialAction or AttackL
-- outside a chant, it samples every 0.25 s: stamina, the action nodes, and what HumanStaminaController says about
-- recovery (DisableRecoverStamina bits: Fsm 1, Sequence 2, RunOut 4, Damage 8, Down 16, Consume 32, SpellStock 64,
-- AfterDash 128, External 256). When the hold ends (0.6 s or longer) it logs ONE summary line "Galvanize watch: ..."
-- and keeps it in R.galv_last (also in the dev status). Reads only; nothing is changed. Registered with the other
-- per-frame checks in coop_sound.lua, where the single file had it.
R.galv = nil
R.galv_next = 0
function R.galv_stam(ch)
    local sm = call(ch, "get_StaminaManager")
    return sm and call(sm, "get_RemainingAmount") or nil
end
function R.galv_who()
    if state.active and state.pawn_chara and state.pawn_human and state.pawn_input and not coop.active then
        return state.pawn_chara, state.pawn_human, state.pawn_input, state.pawn_job, "played pawn"
    end
    if state.active or coop.active then return nil end
    local cm = sdk.get_managed_singleton("app.CharacterManager")
    local ar = cm and call(cm, "get_ManualPlayer")
    local hu = ar and call(ar, "get_Human")
    if not hu then return nil end
    return ar, hu, state.arisen_input or call(ar, "get_Input"), get_job(hu, ar), "Arisen"
end
function R.galv_tick()
    if cfg.galvanize_watch == false then return end
    local now = os.clock()
    if now < R.galv_next then return end
    R.galv_next = now + 0.25
    local ch, hu, inp, job, who = R.galv_who()
    local g = R.galv
    local held = false
    if ch and inp and (job == 3 or job == 6) then
        local AF = S.ACTION_FLAGS or {}
        local mask = (AF.JobSpecialAction or 0) | (AF.AttackL or 0)
        local on = field(inp, "ButtonOnFlags") or 0
        local sk = call(hu, "get_CustomSkillState") or 0
        held = mask ~= 0 and (on & mask) ~= 0 and sk == 0
    end
    local st = ch and R.galv_stam(ch)
    if held then
        if not g or g.who ~= who then
            g = { who = who, job = job, t0 = now, st0 = st, pre = R.galv_pre_rate, n = 0, dis = 0, ext = 0, fsm = 0,
                  dash = 0, add_min = nil, add_max = nil, nodes = {} }
            R.galv = g
        end
        g.n = g.n + 1
        g.st1 = st
        local c = call(hu, "get_HumanStaminaCtrl")
        if c then
            local d = field(c, "DisableRecoverStamina") or 0
            if type(d) == "number" then g.dis = g.dis | d end
            if field(c, "IsRequestDisableRecoverStaminaFromExternal") then g.ext = g.ext + 1 end
            if field(c, "IsRequestDisableRecoverStaminaFromFsm") then g.fsm = g.fsm + 1 end
            local a = field(c, "StaminaAddValue")
            if type(a) == "number" then
                g.add_min = math.min(g.add_min or a, a)
                g.add_max = math.max(g.add_max or a, a)
            end
        end
        if call(hu, "get_IsDash") then g.dash = g.dash + 1 end
        if #g.nodes < 6 and R.node_names then
            local n0, n1 = R.node_names(ch)
            local s = tostring(n0) .. " | " .. tostring(n1)
            if g.nodes[#g.nodes] ~= s then g.nodes[#g.nodes + 1] = s end
        end
        return
    end
    if g then
        R.galv = nil
        local dt = now - g.t0
        if dt >= 0.6 then
            local rate = (g.st0 and g.st1 and dt > 0) and (g.st1 - g.st0) / dt or nil
            local line = string.format("Galvanize watch (%s, job %s): held %.1f s, stamina %s -> %s (%s/s; before the hold %s/s), DisableRecoverStamina bits %d, external %d/%d, fsm %d/%d, IsDash %d/%d, StaminaAddValue %s..%s, nodes: %s",
                g.who, tostring(g.job), dt, tostring(g.st0 and math.floor(g.st0) or "?"), tostring(g.st1 and math.floor(g.st1) or "?"),
                rate and string.format("%.0f", rate) or "?", g.pre and string.format("%.0f", g.pre) or "?",
                g.dis, g.ext, g.n, g.fsm, g.n, g.dash, g.n,
                g.add_min and string.format("%.3f", g.add_min) or "?", g.add_max and string.format("%.3f", g.add_max) or "?",
                table.concat(g.nodes, " ; "))
            R.galv_last = line
            log_msg(line)
        end
    end
    -- the stamina rate just before a hold, to compare against (sampled every 0.25 s while not holding)
    if st and R.galv_prev_st and R.galv_prev_who == who then R.galv_pre_rate = (st - R.galv_prev_st) / 0.25 end
    R.galv_prev_st, R.galv_prev_who = st, who
end

-- 0.9.178-dev2 (from 0.9.177-dev1) candidate fix, LOW confidence, for the same report. In 0.9.86 a stuck
-- "Consume" block kept the Arisen's stamina from coming back, and on release DPC clears the Arisen's IsDash because a
-- dash flag left on keeps stamina draining. Nothing clears it on the played pawn under native controls (the
-- puppeteer path clears it itself). If the played pawn still has IsDash set while the stick has been at rest for
-- 0.5 s, clear IsDash / IsPrevDash (what the game does when you stop sprinting). Off with
-- cfg.pawn_stale_dash_fix = false. Counted in R.stale_dash_n; the first 3 are logged.
R.stale_dash_since = nil
function R.stale_dash_tick()
    if not cfg.pawn_stale_dash_fix or not cfg.native_controls then R.stale_dash_since = nil; return end
    local hu = state.active and not coop.active and state.pawn_human
    if not hu or (state.last_stick_mag or 0) >= 0.1 or not call(hu, "get_IsDash") then R.stale_dash_since = nil; return end
    local now = os.clock()
    if not R.stale_dash_since then R.stale_dash_since = now; return end
    if now - R.stale_dash_since < 0.5 then return end
    call(hu, "set_IsDash(System.Boolean)", false)
    call(hu, "set_IsPrevDash(System.Boolean)", false)
    R.stale_dash_since = nil
    R.stale_dash_n = (R.stale_dash_n or 0) + 1
    if R.stale_dash_n <= 3 then log_msg(string.format("played pawn: IsDash was still on with the stick at rest, cleared (%d)", R.stale_dash_n)) end
end

-- shared with the modules loaded after this one (see shared.lua)
S.dbg_event, S.trace_attack_frames, S.flush_input_log = dbg_event, trace_attack_frames, flush_input_log
S.in_locomotion, S.pawn_do_attack, S.pawn_do_skill_slot = in_locomotion, pawn_do_attack, pawn_do_skill_slot
S.pawn_do_jump, S.pawn_set_fighter_guard = pawn_do_jump, pawn_set_fighter_guard
