-- Direct Pawn Control: game fixes around the world: rumble, ring, orders, take-over, interact, revive, items, cards data, danger flash.
-- Part of DirectPawnControl.lua, which loads the files in this folder in order (this one is 14 of 26).
-- Never run on its own: REFramework only runs the files directly in reframework/autorun.
local S = require("DirectPawnControl/shared")
local VERSION, dev_error, cfg, R, log_msg, same_obj = S.VERSION, S.dev_error, S.cfg, S.R, S.log_msg, S.same_obj
local call, field, get_job, get_skills, get_party = S.call, S.field, S.get_job, S.get_skills, S.get_party
local state, addr_of, brain, coop, brain_event = S.state, S.addr_of, S.brain, S.coop, S.brain_event
local brain_pos, quick, coop_pad_values, node_names = S.brain_pos, S.quick, S.coop_pad_values, S.node_names

-- dev34 (reported: "I seem to get controller rumble when arisen is hit but I am possessing the pawn"). DD2.exe 4.1:
-- UserPadManager.requestVibration(VibrationPresetRequestData, via.GameObject) rumbles only when the source
-- GameObject's character is CharacterManager.ManualPlayer (the Arisen), so the Arisen's hits rumbled and the played
-- pawn's never did. While a pawn is played (not classic co-op, where player 1 is the Arisen): the Arisen's requests
-- are dropped, and the pawn's are made with ManualPlayer = the pawn for that one call.
R.rmb = { ar = 0, pw = 0, n_drop = 0, n_pawn = 0 }
R.rmb_tick = function()
    local B = R.rmb
    B.on = cfg.pawn_rumble_follow ~= false and state.active and not coop.active and state.pawn_chara ~= nil or false
    if not B.on then return end
    B.ar = state.arisen_chara and addr_of(state.arisen_chara:call("get_GameObject")) or 0
    B.pw = addr_of(state.pawn_chara:call("get_GameObject")) or 0
    if not B.cm then B.cm = sdk.get_managed_singleton("app.CharacterManager") end
end
R.rmb_hook = function()
    local td = sdk.find_type_definition("app.UserPadManager")
    local m = td and td:get_method("requestVibration(app.VibrationPresetRequestData, via.GameObject)")
    if not m then log_msg("rumble follow: UserPadManager.requestVibration not found (game update?)"); return end
    sdk.hook(m, function(args)
        local B = R.rmb
        if not B.on then return end
        local go = sdk.to_int64(args[4])
        if go == 0 then return end
        local hs = thread.get_hook_storage()
        if go == B.ar then
            B.n_drop = B.n_drop + 1
            hs.rmb_skip = true
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
        if go == B.pw and B.cm then
            local cur = B.cm:get_field("<ManualPlayer>k__BackingField")
            if cur and cur:get_address() ~= addr_of(state.pawn_chara) then
                B.cm:set_field("<ManualPlayer>k__BackingField", state.pawn_chara)
                hs.rmb_cur = cur
                B.n_pawn = B.n_pawn + 1
            end
        end
    end, function(retval)
        local hs = thread.get_hook_storage()
        if hs.rmb_skip then hs.rmb_skip = nil; return sdk.to_ptr(0) end
        local cur = hs.rmb_cur
        if cur then hs.rmb_cur = nil; pcall(R.rmb.cm.set_field, R.rmb.cm, "<ManualPlayer>k__BackingField", cur) end
        return retval
    end)
end
pcall(R.rmb_hook)
re.on_pre_application_entry("UpdateBehavior", function() pcall(R.rmb_tick) end)
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
        -- 0.9.178-dev2 (from 0.9.177-dev1; tavern lean, PXXXND's report): never force-end while an object interaction
        -- holds the pawn. The take-over waits until the pawn is free of its lean (0.9.176), but the AI pack it was
        -- running (InteractingWithObject) can still be walking it to the wall / bench / bath: the interaction can
        -- start inside this 1.5 s window, and ending ANY command then goes down the same cancel chain into
        -- AdjustJack.reject (dd2-modding rule 24). Ask the interaction to abort instead; this check runs again 0.1 s later.
        if R.busy_interact(state.pawn_chara) then
            R.abort_interact(state.pawn_chara)
            R.move_lean_skips = (R.move_lean_skips or 0) + 1
            if R.move_lean_skips <= 3 then
                log_msg(string.format("%s is in an object interaction: asked it to stop instead of ending %s",
                    tostring(state.pawn_name), (c.name:gsub("^app%.actinter%.cmd%.", ""))))
            end
            return
        end
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
        local cam = R.primary_cam()
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

-- 0.9.178-dev20 (the tester: climbing with the Arisen, then switching characters "kept pulling the camera back to the
-- arisen and cancelling the switch"). Log: the take-over at [time] came while the Arisen clung to a monster; the
-- camera was already the climbing camera (6, the game's camera for the player clinging), 16 m from the played pawn,
-- and stayed until he let go 20 s later. v0.9.143 only refuses a switch TO it (switchCamera pre-hook); one already up
-- when a pawn is taken was left. Now, while a pawn is played (not classic co-op, where player 1 is the Arisen), the
-- climbing camera is switched back to the usual one, as the bow-aim exit does.
R.climb_cam_off = function()
    if not (cfg.possess_no_climb_cam and state.active and state.pawn_chara and not coop.active) then return end
    local now = os.clock()
    if now < (R.ccam_next or 0) then return end
    R.ccam_next = now + 0.25
    local mcc = R.aim_mcc and R.aim_mcc()
    if not mcc then return end
    local ct = mcc:call("get_CurrentControlType")
    if type(ct) == "userdata" then ct = ct:get_field("value__") end
    if ct ~= 6 then return end
    local ip = R.aim_interp and R.aim_interp("exit")
    if not ip then return end
    R.aim_mine = true
    local ok = pcall(mcc.call, mcc, R.aim_sig, 0, ip, nil, 0)
    R.aim_mine = false
    R.ccam_n = (R.ccam_n or 0) + 1
    if R.ccam_n <= 3 or R.ccam_n % 20 == 0 then
        log_msg(string.format("Camera: the Arisen's climbing camera was up while %s is played: back to the usual camera (%s, %d)", tostring(state.pawn_name), ok and "ok" or "failed", R.ccam_n))
    end
end
R.ai_watch = function()
    R.takeover_rec()
    pcall(R.climb_cam_off)
    R.cling_watch()
    R.cam_watch()
    if state.active and not R.aim_hooked then R.aim_install() end -- 0.9.143: the camera-switch hook is needed for every pawn
    if not (state.active and state.pawn_chara) then return end
    R.navi_stop() -- their own switches (possess_stop_navi / possess_stop_move); 0.9.176-dev17: no longer also behind
    R.move_stop() -- possess_interrupt_ai, so turning that off doesn't leave the pawn following its last move
    if not cfg.possess_interrupt_ai then return end
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
-- 0.9.177: the pawn-interact object search, shared by the main played pawn and the other players' pawns
R.int_scan = function(chara)
    local best, bd, bn, bdead = nil, nil, nil, false
    R.int_rev_best = nil
    local okscan, errscan = pcall(function()
        local im = sdk.get_managed_singleton("app.InteractManager")
        if not im then return end
        local px, py, pz = brain_pos(chara)
        if not px then return end
        local skip = {}
        skip[chara:get_GameObject():get_address()] = true
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
                            -- 0.9.177 (the tester, a dead soldier nobody could loot): human enemies (bandits) are not ch2 either.
                            -- dev18 used EnemyCtrl, but every character has one (read live: pawns and a revivable NPC, ch300735, too).
                            -- Hostility tells them apart: a dead human hostile to the Arisen is loot; one who isn't (an NPC, a
                            -- Wakestone revive) stays the Arisen's (the tester: "maybe only player 1 should be able to do that").
                            local enemy = false
                            pcall(function() enemy = state.arisen_chara ~= nil and ch:call("isHostile(app.Character)", state.arisen_chara) == true end)
                            if human and not id:find("^ch2") and not enemy then
                                R.int_skipped_people = (R.int_skipped_people or 0) + 1; R.int_skipped_last = id
                                if not R.int_rev_best or d < R.int_rev_best.d then
                                    local nm
                                    pcall(function()
                                        R.gui_name_m = R.gui_name_m or sdk.find_type_definition("app.GUIBase"):get_method("getName(app.Character)")
                                        nm = R.gui_name_m:call(nil, ch)
                                    end)
                                    R.int_rev_best = { chara = ch, obj = o, d = d, pos = { q.x, q.y, q.z }, id = id, name = (nm and nm ~= "") and tostring(nm) or nil }
                                end
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
                    R.int_scan_pos = { q.x, q.y, q.z }; R.int_scan_last = R.int_scan_pos
                end)
            end
        end
    end)
    if not okscan and not R.int_err then R.int_err = true; dev_error("pawn interact scan", errscan) end
    return best, bn, bdead, bd, best and R.int_scan_last or nil
end

-- 0.9.177 (the tester: "co-op pawn cannot open this chest"): players 3+ (and player 2 when both players are on pawns) had
-- no interact at all; only the main played pawn did. Now every played pawn gets the same search (5x a second,
-- chests / gather points / pickups / corpses, R.int_scan) and its own controller's Interact button uses it, with
-- the same calls as the main pawn. Waking / reviving stays with the main pawn for now.
-- 0.9.177 (the tester: "player 1 as anyone, whether a pawn or in co-op, should be able to clearly see it's a revive and
-- choose to do it in a nicely handled way ... we don't want crashes"). Read from DD2.exe 4.1: a dead person's
-- HumanReviveInteractController.startInteractHuman(point, interactor) locks the body (OccupiedManager), picks a
-- Wakestone (real first, then forgery: WakestoneUser.selectUseItemIncludingForgery) and asks the game's
-- WakestoneUser to use it; CharacterManager.onUpdate then calls useWakestoneIfRequested(ManualPlayer), so the ARISEN
-- sheathes and plays the revive. Forcing that interact from a pawn (0.9.57) made the pawn the interactor; here the
-- Arisen is always the one who interacts, through the same InteractManager calls the player's button makes:
--  * the played pawn near such a body gets a prompt in player 1's colour: "Revive <who> (Wakestone, by the Arisen)";
--  * first press asks to confirm (2.5 s), the second brings the Arisen next to the body (out of battle only), holds
--    DPC's Arisen AI for a few seconds, and has him start the game's own revive interact;
--  * nothing happens without a Wakestone or Forgery; players 2+ never get it.
R.rev_npc_label = function()
    local r = R.int_rev
    if not r then return "" end
    local who = r.name or "this person"
    if os.clock() < (R.rev_confirm_until or 0) then return "Press again: revive " .. tostring(who) .. " with a Wakestone (the Arisen comes)" end
    return "Revive " .. tostring(who) .. " (Wakestone, by the Arisen)"
end
R.rev_npc_press = function(now)
    local r = R.int_rev
    if not r or not state.arisen_chara then return end
    local ws = sdk.find_type_definition("app.WakestoneUser")
    local have = ws and ws:get_method("isEnableUseWakestoneIncludingForgery"):call(nil)
    if have ~= true then
        R.note = { text = "No Wakestone (or Forgery) to revive with", t_end = now + 2.5 }
        log_msg("Wakestone revive: none in the bag")
        return
    end
    if brain.in_battle and brain.in_battle() then
        R.note = { text = "Finish the fight first: the Arisen revives people out of battle", t_end = now + 2.5 }
        return
    end
    if now >= (R.rev_confirm_until or 0) then
        R.rev_confirm_until = now + 2.5
        return
    end
    R.rev_confirm_until = 0
    local ar = state.arisen_chara
    -- next to the body, on the side the pawn stands on, a little up (the warp rules: never onto the anchor itself)
    local px, py, pz = brain_pos(state.pawn_chara)
    local bx, by, bz = r.pos[1], r.pos[2], r.pos[3]
    local dx, dz = (px or bx + 1.0) - bx, (pz or bz) - bz
    local l = math.sqrt(dx * dx + dz * dz)
    if l < 0.01 then dx, dz, l = 1.0, 0.0, 1.0 end
    local tx, tz = bx + dx / l * 1.2, bz + dz / l * 1.2
    ar:call("warp(via.vec3, app.CharacterWarpOption)", Vector3f.new(tx, by + 0.4, tz), nil)
    R.brain_hold_until = now + 8.0
    R.rev_job = { t = now + 0.6, obj = r.obj, chara = r.chara, id = r.id }
    log_msg(string.format("Wakestone revive: Arisen brought to %s, interact in 0.6 s", tostring(r.id)))
end
R.rev_job_tick = function()
    local j = R.rev_job
    if not j or os.clock() < j.t then return end
    R.rev_job = nil
    local ok, err = pcall(function()
        local ar = state.arisen_chara
        if not ar then
            local cm = sdk.get_managed_singleton("app.CharacterManager")
            if not cm then error("no character manager") end
            ar = cm:call("get_ManualPlayer")
        end
        if j.chara:call("get_IsDead") ~= true then error("no longer dead") end
        local im = sdk.get_managed_singleton("app.InteractManager")
        if im:call("isInteracting(app.Character)", ar) then im:call("endInteract(app.Character)", ar) end
        local pt = sdk.create_instance("app.InteractManager.InteractPoint"):add_ref()
        pt:set_field("Object", j.obj)
        pt:set_field("PointNo", 0)
        im:call("addActiveInteract(app.Character, app.InteractManager.InteractPoint)", ar, pt)
        im:call("executeInteract(app.Character)", ar)
    end)
    if ok then log_msg("Wakestone revive: the Arisen started the game's revive on " .. tostring(j.id))
    else
        R.brain_hold_until = nil
        R.note = { text = "The revive could not start: " .. tostring(err), t_end = os.clock() + 3.0 }
        dev_error("wakestone revive", err)
    end
end
re.on_pre_application_entry("UpdateBehavior", function() if R.rev_job and R.world_now then pcall(R.rev_job_tick) end end)

R.int_label_for = function(name, dead, item)
    if dead then return "Loot" end
    if item then return "Pick up" end
    name = tostring(name or "")
    if name:find("^gm80_001") then return "Open chest" end
    return "Gather / use"
end
R.xint_tick = function(sl, chara, raw, who)
    if not (cfg.pawn_interact and chara) then return end
    local now = os.clock()
    if now >= (sl.int_next or 0) then
        sl.int_next = now + 0.2
        local best, bn, bdead, bd, bpos = R.int_scan(chara)
        sl.int_obj, sl.int_name, sl.int_dead, sl.int_pos = best, bn, bdead, bpos
        sl.int_item = bn ~= nil and bn:find("^gm82_000") ~= nil
        sl.int_label = best and R.int_label_for(bn, bdead, sl.int_item) or nil
    end
    local m = R.bind_mask("Interact") or 0x80
    local prev = sl.int_prev
    sl.int_prev = raw
    if prev == nil or (raw & m) == 0 or (prev & m) ~= 0 then return end
    if not sl.int_obj or now < (sl.int_cool or 0) then return end
    sl.int_cool = now + 1.0
    local obj, item = sl.int_obj, sl.int_item
    local okx, errx = pcall(function()
        local im = sdk.get_managed_singleton("app.InteractManager")
        if im:call("isInteracting(app.Character)", chara) then
            if now - (sl.int_last_t or 0) < 3.0 then return end
            im:call("endInteract(app.Character)", chara)
        end
        sl.int_last_t = now
        local pt = sdk.create_instance("app.InteractManager.InteractPoint"):add_ref()
        pt:set_field("Object", obj)
        pt:set_field("PointNo", 0)
        im:call("addActiveInteract(app.Character, app.InteractManager.InteractPoint)", chara, pt)
        im:call("executeInteract(app.Character)", chara)
        if item then obj:get_field("StartInteractHandler"):call("Invoke", 0, chara) end
    end)
    if okx then log_msg(string.format("%s: %s %s", tostring(who), sl.int_dead and "looted" or "used", tostring(sl.int_name)))
    else dev_error("co-op pawn interact", errx) end
    sl.int_obj, sl.int_next = nil, now + 0.6
end

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
    if coop.active and state.active and state.pawn_chara then
        R.c2view = R.c2view or {}
        -- 0.9.178-dev7 (test PC: player 2 on the Arisen had player 1's pawn on his card and no bars over him): in
        -- the any-combination classic arrangement with player 2 on the Arisen (R.cp.arisen_side 2), player 2's card
        -- is the Arisen's; player 1's card (R.c1_tick) is the pawn's
        local p2_ar = R.cp and R.cp.on and R.cp.arisen_side == 2 and state.arisen_chara
        R.c2view.want_skills = p2_ar and true or nil
        -- dev18: the buttons shown on player 2's card are his own controller's (coop.last_btn is the pawn side's,
        -- player 1's, when player 2 is on the Arisen: player 1's L1 lit both cards)
        local b2 = coop.last_btn or 0
        if p2_ar then local v2 = R.tp_p1 and R.tp_p1(); b2 = v2 and v2.b or 0 end
        pcall(R.card_refresh, R.c2view, p2_ar or state.pawn_chara, b2)
        R.dord_c2 = R.dord_c2 or {}
        pcall(R.dord, R.dord_c2, S.pad_buttons or 0, state.pawn_chara, "player 2")
    end
    pcall(R.dord_watch_tick)
    if not (cfg.pawn_quick_item and state.active and state.pawn_chara and state.arisen_chara) then return end
    local now = os.clock()
    if cfg.pawn_quick_item_labels and not coop.active then R.cross_hook(); R.cross_scan(now) end
    local kind
    if coop.active then
        local pv = coop_pad_values()
        local dn, up = pv.LDown or 0x2, pv.LUp or 0x1
        local trg = (S.pad_buttons or 0) & ~(S.pad_prev or 0)
        -- v0.9.78: the game's own layout (the tester's screenshot of the shortcut cross): up = health item,
        -- down = stamina item (left = items menu, right = lantern; those two stay the Arisen's)
        if (trg & up) ~= 0 then kind = "hp" elseif (trg & dn) ~= 0 then kind = "stamina"
        elseif (trg & (pv.LRight or 0x8)) ~= 0 then kind = "lantern" end
        if kind and R.qi_pre_mask then -- dev22: the game's held button for the item shortcut
            local pre = R.qi_pre_mask(kind == "hp" and "RecoverHpItem" or (kind == "stamina" and "RecoverStaminaItem" or "Lantern"))
            if pre ~= 0 and ((S.pad_buttons or 0) & pre) ~= pre then kind = nil end
        end
    else
        local trg = state.last_trg_flags or 0
        if (trg & (S.ACTION_FLAGS.RecoverHpItem or 0)) ~= 0 then kind = "hp"
        elseif (trg & (S.ACTION_FLAGS.RecoverStaminaItem or 0)) ~= 0 then kind = "stamina"
        elseif (trg & (S.ACTION_FLAGS.Lantern or 0)) ~= 0 then kind = "lantern" end
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
-- 0.9.177: the D-pad item cross for players 2 and up (the tester: player 2 on the Arisen "doesn't seem to be able to use
-- his down arrow stamina curative"). The game's cross reads player 1's input only, and DPC's player-2 button map
-- leaves the item shortcuts out (COOP_NOT_P2), so a co-op player's D-pad did nothing. Now each player's own D-pad
-- works their own character: up = healing item, down = stamina item (the game's lists for those shortcuts, in its
-- order; the character's own bag first, then the Arisen's), right = the Arisen's lantern (the party follows his).
R.qi_pick = function(kind, chara)
    local gm = sdk.get_managed_singleton("app.GuiManager")
    local cg = gm and gm:get_field("CrossGuide")
    local sp = cg and cg:get_field("ShortcutParam")
    local im = sdk.get_managed_singleton("app.ItemManager")
    if not (sp and im and chara) then return nil end
    local list = sp:get_field(kind == "hp" and "RecoverHPItems" or "RecoverStaminaItems")
    if not list then return nil end
    local ids = {}
    for i = 0, list:call("get_Length") - 1 do
        local e = list:call("Get", i)
        local iid = e
        if type(e) == "userdata" then iid = e:get_field("value__") end
        if type(iid) == "number" then ids[#ids + 1] = iid end
    end
    local ar = state.arisen_chara
    for _, owner in ipairs({ chara, ar }) do
        if owner then
            for _, iid in ipairs(ids) do
                local n = im:call("getHaveNum(System.Int32, app.Character)", iid, owner) or 0
                if n > 0 then return iid, n, owner end
            end
        end
        if ar and owner and addr_of(owner) == addr_of(ar) then break end
    end
    return nil
end
R.qi_use = function(kind, chara, who)
    local id, n, owner = R.qi_pick(kind, chara)
    if not id then
        R.note = { text = tostring(who) .. ": no " .. (kind == "hp" and "healing" or "stamina") .. " item", t_end = os.clock() + 2.0 }
        log_msg("Quick item (" .. kind .. ", " .. tostring(who) .. "): nothing in the bags for this shortcut")
        return
    end
    local im = sdk.get_managed_singleton("app.ItemManager")
    local used = im:call("useItem(System.Int32, app.Character, app.Character)", id, owner, chara)
    local own = addr_of(owner) == addr_of(chara)
    log_msg(string.format("Quick item (%s, %s): item %d -> %s (%s)", kind, tostring(who), id, tostring(used), own and "own bag" or "the Arisen's bag"))
end
R.qi_lantern = function(who)
    local lc = state.arisen_chara and state.arisen_chara:call("get_Human"):call("get_LanternCtrl")
    if not lc then return end
    local was = lc:call("get_IsLanternOn") == true
    if was then lc:call("turnOffByOwnerAction")
    elseif lc:call("isTurnOnCondition") or (lc:call("hasEnableLantern") and lc:call("isEnableTurnOn")) then lc:call("turnOnByOwnerAction")
    else R.note = { text = "The Arisen cannot light a lantern now", t_end = os.clock() + 2.0 }; return end
    if (lc:call("get_IsLanternOn") == true) == was then lc:call("turn(System.Boolean)", not was) end
    log_msg(string.format("Quick lantern (%s): %s", tostring(who), (lc:call("get_IsLanternOn") == true) and "on" or "off"))
end
-- dev22: the button the game wants held for an action (its PreInput), as a pad mask, or 0
R.qi_pre_mask = function(action)
    if not (R.bind and R.bind.list) then return 0 end
    for _, e in ipairs(R.bind.list) do
        if e.name == action and e.pre then
            for _, e2 in ipairs(R.bind.list) do if e2.a == e.pre then return e2.pad or 0 end end
        end
    end
    return 0
end
-- st: the player's state table (keeps last frame's buttons); raw: that player's controller buttons this frame
R.qi_pad = function(st, raw, chara, who)
    if not cfg.pawn_quick_item then return end
    local prev = st.qi_prev
    st.qi_prev = raw
    if prev == nil then return end -- held from before: not a new press
    local pv = coop_pad_values()
    local trg = raw & ~prev
    local kind
    if (trg & (pv.LUp or 0x1)) ~= 0 then kind = "hp" elseif (trg & (pv.LDown or 0x2)) ~= 0 then kind = "stamina"
    elseif (trg & (pv.LRight or 0x8)) ~= 0 then kind = "lantern" end
    -- dev22 (the tester: "don't they normally have to hold that skill button to access curatives?"): if the game binds the
    -- item shortcut with a button that must be held (its PreInput), that button must be held here too
    if kind then
        local pre = R.qi_pre_mask and R.qi_pre_mask(kind == "hp" and "RecoverHpItem" or (kind == "stamina" and "RecoverStaminaItem" or "Lantern")) or 0
        if pre ~= 0 and (raw & pre) ~= pre then return end
    end
    if not kind then return end
    local now = os.clock()
    if now < (st.qi_next or 0) then return end
    st.qi_next = now + 0.6
    local ok, err = pcall(function()
        if kind == "lantern" then
            if cfg.pawn_quick_lantern then R.qi_lantern(who) end
        else
            R.qi_use(kind, chara, who)
        end
    end)
    if not ok then dev_error("co-op quick item", err) end
end
-- dev23 (the tester: "build plain d pad gestures with the setting to choose between real orders or just the animations/sounds
-- (so co-op players could give signals)"). A co-op player's D-pad tap with no shoulder button or trigger held: the
-- game's layout (up Go, down Come, left Wait, right Help). Mode 2 gives the real order through the game's own
-- app.PawnOrderController (one, on the PawnMetaAI object; it orders every pawn no one plays, and the pawns answer
-- in their own voices) and plays a gesture on the player's character; mode 3 plays the gesture only. The gestures are
-- app.HumanActionID nodes (GesComehere, GesPointing, GesCall, GesSoothe), requested only while the character is in
-- locomotion (the engine ignores them mid-attack anyway). A direction the item shortcut takes as a plain press (the
-- game binds no held button for it) stays the item's.
R.DORD = {
    { mask = "LUp", def = 0x1, order = 2, ges = "GesPointing", name = "Go", item = "RecoverHpItem" },
    { mask = "LDown", def = 0x2, order = 1, ges = "GesComehere", name = "Come", item = "RecoverStaminaItem" },
    { mask = "LLeft", def = 0x4, order = 4, ges = "GesSoothe", name = "Wait" },
    { mask = "LRight", def = 0x8, order = 3, ges = "GesCall", name = "Help", item = "Lantern" },
}
R.dord_pc = function()
    local pc = R.dord_pc_obj
    if pc and sdk.is_managed_object(pc) then return pc end
    R.dord_pc_obj = nil
    local sm = sdk.get_native_singleton("via.SceneManager")
    local scene = sm and sdk.call_native_func(sm, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
    local arr = scene and scene:call("findComponents(System.Type)", sdk.typeof("app.PawnOrderController"))
    local els = arr and arr.get_elements and arr:get_elements() or {}
    pc = els[1]
    if pc then pc:add_ref(); R.dord_pc_obj = pc end
    return pc
end
R.dord = function(st, raw, chara, who)
    local mode = cfg.coop_dpad_orders or 2
    -- dev60: gestures removed (tests dpad-1 / dpad-2 and six request forms on three layers: accepted, never played;
    -- the Arisen's and pawns' action trees have no gesture nodes). Mode 3 (gesture only) now does nothing.
    if mode ~= 2 or not chara then return end
    local prev = st.do_prev
    st.do_prev = raw
    if prev == nil then return end
    local pv = coop_pad_values()
    local mods = (pv.LTrigTop or 0x100) | (pv.LTrigBottom or 0x200) | (pv.RTrigTop or 0x400) | (pv.RTrigBottom or 0x800)
    if (raw & mods) ~= 0 then return end
    local trg = raw & ~prev
    local e
    for _, d in ipairs(R.DORD) do
        if (trg & (pv[d.mask] or d.def)) ~= 0 then e = d end
    end
    if not e then return end
    if e.item and cfg.pawn_quick_item and R.qi_pre_mask and R.qi_pre_mask(e.item) == 0 then
        if e.item ~= "Lantern" or cfg.pawn_quick_lantern then return end
    end
    local now = os.clock()
    if now < (st.do_next or 0) then return end
    st.do_next = now + 0.5
    local r = { who = who, name = e.name, mode = mode, t = now }
    if mode == 2 then
        local okp, pc = pcall(R.dord_pc)
        if not okp then r.order = "lookup error " .. tostring(pc); pc = nil end
        if pc then
            R.ord_bypass = true
            local okr, res = pcall(pc.call, pc, "tryUpdatePawnOrder(app.PawnOrderController.PawnOrder)", e.order)
            R.ord_bypass = false
            r.order = okr and tostring(res) or ("error " .. tostring(res))
        else
            r.order = r.order or "no order controller"
        end
    end
    local okg, errg = true, nil
    if false then okg, errg = pcall(function()
        local am = chara:call("get_ActionManager")
        local fsm = am and am:get_field("Fsm")
        local node = fsm and fsm:call("getCurrentNodeName(System.UInt32)", 0) or ""
        r.node = node
        if not node:find("Locomotion") then r.ges = "busy"; return end
        -- dev59: through the action selector, the way the pawn AI requests its actions; idle requests paused 1.4 s
        local sel = chara:call("get_HumanActionSelector")
        if sel then
            DPC_GES_HOLD[sel:get_address()] = now + 1.4
            sel:call("requestAction(System.String, System.UInt32)", e.ges, 0xFFFFFFFF)
        else
            am:call("requestActionCore(app.ActionManager.Priority, System.String, System.UInt32)", 0, e.ges, 0)
        end
        r.ges = e.ges
        R.dord_watch = { chara = chara, want = e.ges, t = now }
    end) end
    if not okg then r.ges = "error " .. tostring(errg) end
    R.dord_last = r
    R.dord_n = (R.dord_n or 0) + 1
    log_msg(string.format("Co-op D-pad: %s -> %s (order %s, gesture %s)", tostring(who), e.name, tostring(r.order or "-"), tostring(r.ges)))
end
-- did the gesture actually play? (read for the test; dropped after a second)
R.dord_watch_tick = function()
    local w = R.dord_watch
    if not w then return end
    if os.clock() - w.t > 1.0 then R.dord_watch = nil; return end
    pcall(function()
        local n = w.chara:call("get_ActionManager"):get_field("Fsm"):call("getCurrentNodeName(System.UInt32)", 0) or ""
        if n:find(w.want, 1, true) then R.dord_played = (R.dord_played or 0) + 1; R.dord_watch = nil end
    end)
end
-- what a player's card shows on its item line, read on the game thread a few times a second
R.card_refresh = function(v, chara, btn)
    local now = os.clock()
    if btn ~= nil then
        v.btn = btn
        if (btn & 0xF) ~= 0 then v.dpad_t = now end -- D-pad touched (card_items 2)
    end
    v.chara = chara
    pcall(function()
        local p = chara:call("get_Transform"):call("get_Position")
        v.wpos = { p.x, p.y, p.z }
    end)
    if now - (v.card_t or 0) < 0.25 then return end
    if v.want_skills then
        pcall(function()
            local hu = chara:call("get_Human")
            v.job = get_job(hu, chara)
            v.skills = get_skills(hu, v.job)
        end)
    end
    v.card_t = now
    pcall(function()
        R.item_name_m = R.item_name_m or sdk.find_type_definition("app.GUIBase"):get_method("getItemName(System.Int32)")
        local nm = R.item_name_m
        local hit = chara:call("get_Hit")
        local omx = hit and hit:call("get_OriginalMaxHp") or 0
        if omx > 0 then v.hp = math.max(0.0, math.min(1.0, (hit:call("get_Hp") or 0) / omx)) end
        local sm = chara:call("get_StaminaManager")
        local mx = sm and sm:call("get_MaxValue") or 0
        if mx > 0 then v.st = math.max(0.0, math.min(1.0, (sm:call("get_RemainingAmount") or 0) / mx)) end
        v.items = v.items or {}
        for _, kind in ipairs({ "hp", "stamina" }) do
            local id, n, owner = R.qi_pick(kind, chara)
            if id then
                v.items[kind] = { name = tostring(nm:call(nil, id)), n = n, arisen = owner ~= nil and addr_of(owner) ~= addr_of(chara) }
            else
                v.items[kind] = nil
            end
        end
        local lc = state.arisen_chara and state.arisen_chara:call("get_Human"):call("get_LanternCtrl")
        v.lantern = lc and lc:call("get_IsLanternOn") == true
        local hu = chara:call("get_Human")
        v.sk_now = hu and hu:call("get_CustomSkillState") or 0
    end)
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

-- 0.9.178-dev3 Ferrystone crash (Nexus bug report, DrCh0ke 2026-11-26, 0.9.177; the tester: "the ferrystone swaps to
-- arisen then crashes"). The Ferrystone flow (app.FerrystoneFlowController: activateFlow -> startReal / startDirection
-- -> updateFadeIn -> teleportCharacters) is built around CharacterManager.ManualPlayer, the Arisen. With a pawn played,
-- DPC only let go once a later check tripped (the cutscene check, or the world guard), in the middle of the flow, and
-- a release that was not a load played the switch transition: DPC's camera glide on the camera joint while the
-- Ferrystone's own direction moves it, slow motion written every frame to the app.WorkRate of every character and shell
-- (a list kept for 0.15 s at a time) while the teleport moves the party and the area around them unloads, and a glow
-- on the Arisen. Now: as soon as the flow starts, any transition or glow still running ends (while everything it
-- touched still exists), player 1 lets go of the pawn as for a cutscene with no transition, players 2+ end as for a
-- cutscene, and no pawn is taken until the flow is over. If a teleport is reached with a pawn still played, it lets
-- go right there. Seen by hooks on the flow's methods, and by its Routine fields every frame as a second way.
-- (The Routine fields are read the way guitarguy1104's DD2PartySwitcher reads them; not yet seen in game here.)
local release_possession = S.release_possession
R.ferry = { live = false, req = nil, until_t = 0, n = 0, hooks = 0, seen = {} }
R.ferry_flow_busy = function() -- true / false, or nil when it cannot be read
    local fc = sdk.get_managed_singleton("app.FerrystoneFlowController")
    if not fc then return nil end
    local ok, v = pcall(function()
        local r = fc:get_field("Routine")
        local d = fc:get_field("Director")
        local dr = d and d:get_field("Routine")
        if r == nil and dr == nil then return nil end
        return (tonumber(r) or 0) ~= 0 or (tonumber(dr) or 0) ~= 0
    end)
    if ok then return v end
    return nil
end
R.ferry_on = function()
    return R.ferry.live == true or os.clock() < (R.ferry.until_t or 0)
end
R.ferry_quiet = function()
    pcall(R.cine_stop) -- the transition's camera, slow motion (put back to 1.0 now, before anything is freed) and glow
    for i = #(R.glows_timed or {}), 1, -1 do
        local g = R.glows_timed[i]
        table.remove(R.glows_timed, i)
        pcall(R.cine_glow, g.chara, g.name, false)
    end
end
R.ferry_let_go = function(where)
    local who = {}
    if state.active then
        who[#who + 1] = tostring(state.pawn_name)
        pcall(release_possession, "cutscene: ferrystone")
    end
    if R.s2 and R.s2.active then
        who[#who + 1] = tostring(R.s2.name)
        pcall(R.s2_stop, "cutscene", R.s2); R.s2.lost = "cutscene"
    end
    for _, sl in pairs(R.np and R.np.slots or {}) do
        if sl.active then
            who[#who + 1] = tostring(sl.name)
            pcall(R.s2_stop, "cutscene", sl); sl.lost = "cutscene"
        end
    end
    if #who > 0 then log_msg("Ferrystone (" .. where .. "): let go of " .. table.concat(who, ", ") .. " before the teleport") end
    return #who
end
R.ferry_begin = function(src)
    local F = R.ferry
    F.until_t = math.max(F.until_t or 0, os.clock() + 10.0)
    if F.live then return end
    F.live, F.t0, F.n = true, os.clock(), (F.n or 0) + 1
    log_msg("Ferrystone: the flow started (" .. tostring(src) .. "); DPC holds still until it is over")
    R.ferry_quiet()
    R.ferry_let_go(src)
end
R.ferry_end = function(why)
    local F = R.ferry
    if not F.live then return end
    F.live = false
    F.until_t = os.clock() + 1.5 -- a short wait after, while the party lands
    F.seen = {} -- log the next flow's steps again
    log_msg(string.format("Ferrystone: over (%s, %.1f s)", tostring(why), os.clock() - (F.t0 or os.clock())))
end
R.ferry_tick = function()
    local F = R.ferry
    if F.req then local r = F.req; F.req = nil; R.ferry_begin(r) end
    local busy = R.ferry_flow_busy()
    if busy == true then
        if not F.live then R.ferry_begin("flow seen running") end
        F.until_t = math.max(F.until_t or 0, os.clock() + 1.5)
        if state.active or (R.s2 and R.s2.active) then R.ferry_let_go("still running") end -- a take-over that slipped in
    elseif F.live then
        if busy == false and os.clock() - (F.t0 or 0) > 1.0 then R.ferry_end("flow idle")
        elseif busy == nil and os.clock() >= (F.until_t or 0) then R.ferry_end("10 s after the last flow step") end
    end
end
re.on_pre_application_entry("UpdateBehavior", function() pcall(R.ferry_tick) end)
do
    local td = sdk.find_type_definition("app.FerrystoneFlowController")
    -- the steps that start a flow (picked on the map, or a failed / forged stone), and the steps of a running one
    local START = { "activateFlow", "activateFailureFlow", "activateForgeryFlow", "startReal", "startDirection", "startFailure", "startForgery" }
    local STEP = { "updateFadeIn", "teleportCharacters", "teleportPlayerIfRequired" }
    local function hook(name, fn)
        local m = td and td:get_method(name)
        if not m then return end
        local ok = pcall(sdk.hook, m, function(args) pcall(fn, name) end, function(r) return r end)
        if ok then R.ferry.hooks = R.ferry.hooks + 1 end
    end
    for _, n in ipairs(START) do
        hook(n, function(name)
            local F = R.ferry
            F.until_t = math.max(F.until_t or 0, os.clock() + 10.0)
            if not F.live and not F.req then F.req = name end -- handled at the next UpdateBehavior, not inside the game's call
            if not F.seen[name] then F.seen[name] = true; log_msg("Ferrystone: " .. name) end
        end)
    end
    for _, n in ipairs(STEP) do
        hook(n, function(name)
            local F = R.ferry
            F.until_t = math.max(F.until_t or 0, os.clock() + 4.0)
            if not F.live then F.req = F.req or name end
            -- the last chance: a teleport with a pawn still played lets go here, inside the call, before it moves anyone
            if name ~= "updateFadeIn" and (state.active or (R.s2 and R.s2.active)) then
                R.ferry_quiet()
                R.ferry_let_go(name)
            end
            if not F.seen[name] then F.seen[name] = true; log_msg("Ferrystone: " .. name) end
        end)
    end
    if td then log_msg("Ferrystone guard: " .. R.ferry.hooks .. " flow steps hooked") end
end
