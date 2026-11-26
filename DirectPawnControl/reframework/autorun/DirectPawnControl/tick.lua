-- Direct Pawn Control: the main game-thread tick, script reset, demo recorder.
-- Part of DirectPawnControl.lua, which loads the files in this folder in order (this one is 22 of 26).
-- Never run on its own: REFramework only runs the files directly in reframework/autorun.
local S = require("DirectPawnControl/shared")
local VERSION, dev_error, cfg, save_cfg, R = S.VERSION, S.dev_error, S.cfg, S.save_cfg, S.R
local write_trace, log_msg, same_obj, call, field = S.write_trace, S.log_msg, S.same_obj, S.call, S.field
local main_thread_queue, ensure_enums, get_job = S.main_thread_queue, S.ensure_enums, S.get_job
local get_party, state, brain, coop, brain_flag = S.get_party, S.state, S.brain, S.coop, S.brain_flag
local brain_pos, brain_tick, brain_dump = S.brain_pos, S.brain_tick, S.brain_dump
local set_pawn_ai_suppressed, attach_camera_to = S.set_pawn_ai_suppressed, S.attach_camera_to
local maintain_native_hud, quick, quick_skill = S.maintain_native_hud, S.quick, S.quick_skill
local party_heal, party_warp_to_me, verify_warps = S.party_heal, S.party_warp_to_me, S.verify_warps
local release_possession, start_possession = S.release_possession, S.start_possession
local coop_pad_values, coop_write_status, coop_toggle = S.coop_pad_values, S.coop_write_status, S.coop_toggle
local toggle_possession, poll_keys, poll_pad = S.toggle_possession, S.poll_keys, S.poll_pad
local pad_combo_pressed, warp_arisen_to_pawn = S.pad_combo_pressed, S.warp_arisen_to_pawn
local update_arisen_tether, flush_input_log = S.update_arisen_tether, S.flush_input_log
local update_puppeteer_controls, refresh_ui_cache = S.update_puppeteer_controls, S.refresh_ui_cache
local spawner_tick, test_hotkeys, poll_cmd_file = S.spawner_tick, S.test_hotkeys, S.poll_cmd_file
local guarded_tick = S.guarded_tick

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
        if ((S.pad_buttons or 0) & ((pv.LUp or 0x1) | (pv.LDown or 0x2) | (pv.LLeft or 0x4) | (pv.LRight or 0x8))) == 0 then
            R.ord_block_raw = false
            R.ord_block_until = os.clock() + 0.4
        end
    end
    if cfg.pad_hold_select and not coop.active then
        R.order_hook()
        local dir = R.dpad_dir(S.pad_buttons or 0)
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
        local b = S.pad_buttons or 0
        if tm ~= 0 and (b & tm) == tm and ((S.pad_prev or 0) & tm) ~= tm then
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
        if not (coop.active or (R.cp and R.cp.on)) then
            R.tp.start_kb, R.tp.start_t = coop_key and true or nil, os.clock()
            -- 0.9.178-dev4: but player 1 keeps the controller he was playing on, if he was (R.p1_start_pad)
            R.tp.start_pad = coop_key and R.p1_start_pad and R.p1_start_pad(os.clock()) or nil
            if R.tp.start_pad then log_msg(string.format("Co-op from the key with player 1 on a controller (%X): player 1 keeps it", R.tp.start_pad & 0xFFFFFF)) end
        end
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
    -- 0.9.176-dev1: dev_trace_frames > 0 traces every stage of the first N frames after a take-over (tavern hang)
    local tr = state.frames_since_start <= math.max(1, cfg.dev_trace_frames or 0)
    R.tr_frame = tr and state.frames_since_start or nil
    if tr then
        write_trace(string.format("f%d: begin post-possession tick", state.frames_since_start), R.trace_pawn_state and R.trace_pawn_state() or nil)
    end
    -- 0.9.176-dev15: "the pawn keeps running somewhere after the take-over and I don't get control" (long-standing).
    -- For the first 8 s, every 0.5 s: what the pawn's action layers and AI decision are, how far it moved, and the
    -- stick. A pawn that moves with the stick at rest is being driven by something else; this says what.
    if state.frames_since_start == 1 then R.run_watch = R.dev and { t0 = os.clock(), next_t = 0, last = nil } or nil end
    if R.run_watch and os.clock() - R.run_watch.t0 < 8 and os.clock() >= R.run_watch.next_t then
        local w = R.run_watch
        w.next_t = os.clock() + 0.5
        pcall(function()
            local p = state.pawn_chara:call("get_GameObject"):call("get_Transform"):call("get_Position")
            local moved = w.last and math.sqrt((p.x - w.last.x) ^ 2 + (p.z - w.last.z) ^ 2) or 0
            w.last = { x = p.x, z = p.z }
            local exs = "?"
            pcall(function()
                local dm = state.pawn_chara:call("get_AIDecisionMaker"):call("get_DecisionModule")
                local ex = field(field(dm, "<ActionInterface>k__BackingField"), "<Executor>k__BackingField")
                exs = tostring(field(ex, "_State")) .. (field(ex, "_CurrentNode") and " node" or " no node")
            end)
            log_msg(string.format("run watch %.1fs: moved %.2f m, stick %.2f, pack %s | %s", os.clock() - w.t0, moved,
                state.last_stick_mag or 0, exs, tostring(R.trace_pawn_state and R.trace_pawn_state())))
        end)
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
        if tr then write_trace(string.format("f%d: set_pawn_ai_suppressed", state.frames_since_start)) end
        set_pawn_ai_suppressed(state.pawn_chara, state.pawn_obj, true, false)
    end
    if cfg.sub_camera_attach then
        if tr then write_trace(string.format("f%d: attach_camera_to", state.frames_since_start)) end
        attach_camera_to(state.pawn_go)
    end

    -- 4. In Mode 2 / Mode 3, run ActionSelector / Locomotion Puppeteer
    if cfg.control_mode == 2 or cfg.control_mode == 3 then
        if tr then write_trace(string.format("f%d: update_puppeteer_controls begin", state.frames_since_start)) end
        guarded_tick("update_puppeteer_controls", update_puppeteer_controls, is_first_frame)
        if tr then write_trace(string.format("f%d: update_puppeteer_controls done", state.frames_since_start)) end
    end

    -- 4b. Keep the native HUD pointed at the pawn
    guarded_tick("maintain_native_hud", maintain_native_hud)
    guarded_tick("flush_input_log", flush_input_log)

    -- 5. Update Arisen tether / auto-follow
    if tr then write_trace(string.format("f%d: update_arisen_tether", state.frames_since_start)) end
    guarded_tick("update_arisen_tether", update_arisen_tether)

    -- 6. v0.8 Arisen combat brain (decides; the PlayerInputProcessor hook applies it)
    guarded_tick("arisen_brain", brain_tick)
    guarded_tick("arisen_brain_dump", brain_dump)

    if tr then
        write_trace(string.format("f%d: SURVIVED full post-possession tick", state.frames_since_start))
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
    for name, flag in pairs(S.ACTION_FLAGS) do
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
