-- Direct Pawn Control: co-op: the second played pawn (R.s2).
-- Part of DirectPawnControl.lua, which loads the files in this folder in order (this one is 19 of 26).
-- Never run on its own: REFramework only runs the files directly in reframework/autorun.
local S = require("DirectPawnControl/shared")
local dev_error, cfg, R, log_msg, same_obj, call = S.dev_error, S.cfg, S.R, S.log_msg, S.same_obj, S.call
local field, get_job, get_skills, get_party, state = S.field, S.get_job, S.get_skills, S.get_party, S.state
local addr_of, coop, brain_pos, brain_facing = S.addr_of, S.coop, S.brain_pos, S.brain_facing
local brain_angdiff, brain_alive, brain_stick_for = S.brain_angdiff, S.brain_alive, S.brain_stick_for
local SET_TARGET_SIG, set_pawn_ai_suppressed = S.SET_TARGET_SIG, S.set_pawn_ai_suppressed
local quick_arisen, quick_pick_enemy, coop_pad_values = S.quick_arisen, S.quick_pick_enemy, S.coop_pad_values

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
        if s.io_ran == R.io_frame then return end -- dev24: already run before the pawn's Human.update
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
    if R.ferry_on and R.ferry_on() then R.cp_event("second pawn: not during a Ferrystone teleport"); return false end -- 0.9.178-dev3
    if s.active then R.s2_stop("restart", s) end
    local entry
    for _, e in ipairs((pn >= 3 and R.party_all) and R.party_all() or get_party()) do if e.idx == idx then entry = e end end
    if not entry then R.cp_event("second pawn: no pawn " .. tostring(idx)); return false end
    if state.active and state.pawn_idx == idx then return false end
    if R.held_by and R.held_by(idx, s) then R.cp_event("second pawn: " .. tostring(entry.name) .. " is played by someone else"); return false end
    if not R.cr_ok(entry.chara) then R.cp_event("second pawn: " .. tostring(entry.name) .. " is down"); return false end
    if R.unlean_defer({ { chara = entry.chara, name = entry.name } }, function() R.s2_start(idx, s) end, "Player " .. tostring(pn) .. " take-over") then
        return true -- pending: taken once the pawn has stood up
    end
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
    local sv_b, sv_x, sv_y = S.pad_buttons, S.pad_stick_x, S.pad_stick_y
    local sv_job, sv_sk = state.pawn_job, state.pawn_skills
    local sv = { coop.face_t, coop.face_sh, coop.face_out, coop.pulse_pad, coop.pulse_until, coop.chord_latch,
        coop.last_btn, coop.last_flags, coop.last_stick }
    local sv_aim = cfg.coop_aim
    S.pad_buttons, S.pad_stick_x, S.pad_stick_y = p.b or 0, p.lx or 0.0, p.ly or 0.0
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
    S.pad_buttons, S.pad_stick_x, S.pad_stick_y = sv_b, sv_x, sv_y
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
            S.pad_buttons, S.pad_stick_x, S.pad_stick_y, S.pad_stick_rx, S.pad_stick_ry = v1.b or 0, v1.lx or 0.0, v1.ly or 0.0, v1.rx or 0.0, v1.ry or 0.0
        else
            S.pad_buttons, S.pad_stick_x, S.pad_stick_y, S.pad_stick_rx, S.pad_stick_ry = 0, 0.0, 0.0, 0.0, 0.0
        end
    else
        s.pad = { b = S.pad_buttons or 0, lx = S.pad_stick_x or 0.0, ly = S.pad_stick_y or 0.0, rx = S.pad_stick_rx or 0.0, ry = S.pad_stick_ry or 0.0 }
        S.pad_buttons, S.pad_stick_x, S.pad_stick_y, S.pad_stick_rx, S.pad_stick_ry = 0, 0.0, 0.0, 0.0, 0.0
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
            if (taking or c.name:find("app.actinter.cmd.move.", 1, true) == 1 or c.name == "app.actinter.cmd.JumpGrab")
                and R.busy_interact(s.chara) then
                -- 0.9.178-dev2 (from 0.9.177-dev1): never force-end inside an object interaction (lean / sit / bathe:
                -- freeze); abort it instead
                R.abort_interact(s.chara)
                s.lean_skips = (s.lean_skips or 0) + 1
                if s.lean_skips <= 3 then
                    R.cp_event(string.format("%s: %s is in an object interaction, asked it to stop", R.cp_label(s.player or 2), tostring(s.name)))
                end
            elseif taking or c.name:find("app.actinter.cmd.move.", 1, true) == 1 or c.name == "app.actinter.cmd.JumpGrab" then
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
    pcall(R.qi_pad, s, raw, ch, "player " .. tostring(pn) .. ", " .. tostring(s.name))
    pcall(R.dord, s, raw, ch, "player " .. tostring(pn))
    pcall(R.card_refresh, s, ch, raw)
    pcall(R.xint_tick, s, ch, raw, "player " .. tostring(pn) .. ", " .. tostring(s.name))
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
    if R.view_turn then ax, ay = R.view_rot(s.chara, ax, ay) end -- 1.3
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
