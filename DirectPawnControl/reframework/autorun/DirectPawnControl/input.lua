-- Direct Pawn Control: keyboard and gamepad polling, hotkeys.
-- Part of DirectPawnControl.lua, which loads the files in this folder in order (this one is 10 of 26).
-- Never run on its own: REFramework only runs the files directly in reframework/autorun.
local S = require("DirectPawnControl/shared")
local robot, cfg, save_cfg, R, log_msg, call = S.robot, S.cfg, S.save_cfg, S.R, S.log_msg, S.call
local get_party, state, brain, coop, coop_event = S.get_party, S.state, S.brain, S.coop, S.coop_event
local brain_pos, brain_stick_for, quick_pick_enemy = S.brain_pos, S.brain_stick_for, S.quick_pick_enemy
local coop_pad_values, coop_start, coop_stop = S.coop_pad_values, S.coop_start, S.coop_stop

-- ----------------------------------------------------------------------------
-- Keyboard & Gamepad Polling (Hotkeys + Safe Stick & Button Input)
-- ----------------------------------------------------------------------------
local prev_keys = {}
S.is_key_down_safe = function(vk) -- forward-declared near the top (co-op filter uses it)
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
        key_now[vk] = S.is_key_down_safe(vk)
    end
end

local function key_pressed(vk)
    if not vk or vk == 0 then return false end
    if R.cap or os.clock() < (R.cap_quiet or 0) then return false end -- v0.9.149: a key is being chosen in the settings window
    if key_now[vk] == nil then
        -- First query: start tracking; never report an edge on the first frame
        local d = S.is_key_down_safe(vk)
        key_now[vk] = d
        prev_keys[vk] = d
        return false
    end
    return key_now[vk] and not prev_keys[vk]
end

-- v0.9.23: the number row is the game's own (pawn orders: Go, Wait, ...) again while possessing. The numpad
-- keeps the skills. number_row_skills = true brings the old behaviour back.
function R.row_down(vk) return cfg.number_row_skills and S.is_key_down_safe(vk) or false end
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
R.tp_kb = function() return R.tp.p1 == R.KB_ADDR or (R.tp.start_kb == true and not R.tp.start_pad and not R.tp.p1) end
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
-- 0.9.178-dev4: when the game's current keyboard-mode stretch began (every frame, in co-op too)
R.hid_track = function(now)
    local t = R.tp
    local mgr = sdk.get_managed_singleton("app.UserInputManager")
    local m = mgr and mgr:call("get_HIDInputMode")
    if m == 1 and t.hid_last ~= 1 then t.kb_enter_t = now end
    t.hid_last = m
    -- 0.9.178-dev9: the last moment the game was in keyboard mode, as it stood about half a second ago (the Ctrl of
    -- Ctrl + F6 flips the game to keyboard mode itself, so the frames right before the press must not count)
    if m == 1 then t.kb_seen_t = now end
    if now - (t.kb_snap_t or -1e9) >= 0.25 then
        t.kb_old, t.kb_snap, t.kb_snap_t = t.kb_snap, t.kb_seen_t, now
    end
end
-- 0.9.178-dev4 (the tester, 2026-11-26: Arisen on a controller, Ctrl + F6, a second controller (connected after the start)
-- took the pawn; then the Arisen "can only move while none of his attacks work. M+KB is also controlling him").
-- dev46 / dev57 took a Ctrl + F6 start to mean player 1 is on keyboard and mouse, so player 1 got no controller
-- (R.KB_ADDR): R.tp_arisen_buttons then takes every pad button away from the Arisen, while his stick still came
-- through the game's active controller. The key press itself is no sign of the keyboard: pressing Ctrl flips the
-- game to keyboard mode. At Ctrl + F6, the controller player 1 was on: the most recently used one that is still
-- connected, when the game was still in controller mode, or its keyboard mode began only with the key press (within
-- 3 s) and the controller was used before that. Otherwise nil: player 1 on keyboard and mouse, as before.
R.p1_start_pad = function(now)
    local t = R.tp
    local best, bt
    for a, at in pairs(t.act or {}) do if not bt or at > bt then best, bt = a, at end end
    if not best or now - bt > 600 then return nil end
    local here = false
    for _, d in ipairs(R.tp_devs()) do if d:get_address() == best then here = true end end
    if not here then return nil end
    local mode
    local uim = sdk.get_managed_singleton("app.UserInputManager")
    if uim then pcall(function() mode = uim:call("get_HIDInputMode") end) end
    if mode == 0 then return best end
    if mode ~= 1 then return nil end
    if t.hid_last ~= 1 then return best end -- the keyboard mode begins this very frame (the key press)
    -- 0.9.178-dev9 (test PC: keyboard and mouse player 1, Ctrl + F6: player 1 also kept a controller, so the second
    -- controller could not be player 3's). dev4 took the controller whenever keyboard mode had begun within 3 s and
    -- after the last controller use. Now: player 1 is on a controller only if he used it after the last moment the game
    -- was in keyboard mode before the key press (t.kb_old, about half a second back).
    local kb_before = t.kb_old
    if kb_before == nil then
        local ke = t.kb_enter_t
        if ke and now - ke <= 3.0 and bt <= ke + 0.1 then return best end -- no history yet: dev4's rule
        return nil
    end
    if bt > kb_before + 0.05 then return best end
    return nil
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
    if t.start_kb then -- co-op started from the keyboard (Ctrl + F6)
        if t.start_pad and t.start_pad ~= joiner then -- 0.9.178-dev4: player 1 was on that controller
            for _, d in ipairs(devs) do if d:get_address() == t.start_pad then t.snap = nil; return d end end
        end
        return R.kb_dev
    end
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
R.kb_wait = function() return R.tp.start_kb == true and not R.tp.start_pad and coop.active and not (R.tp_on and R.tp_on()) end
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
        t.start_kb, t.start_pad = nil, nil -- dev46: the keyboard start belongs to that co-op session
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
    local spd -- 0.9.178-dev4: player 1's controller at a Ctrl + F6 start, if still connected
    if t.start_kb and t.start_pad then for _, d in ipairs(devs) do if d:get_address() == t.start_pad then spd = d end end end
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
    if not t.p2 and t.start_kb and #devs == 1 and not spd and now - (t.start_t or 0) > 0.3 then
        local d = devs[1]
        local a = d:get_address()
        if not ((t.act or {})[a] and (t.act[a] > (t.start_t or 0) - 5.0) and t.act[a] <= (t.start_t or 0)) then
            t.p2, p2d, p1d, t.p1 = a, d, R.kb_dev, R.KB_ADDR
            t.wait_release, t.keep = true, nil
            R.note = { text = "Co-op: player 1 on keyboard and mouse, player 2 on the controller (Ctrl + F6 ends)", t_end = now + 4.0 }
            coop_event(string.format("two controllers: one controller -> player 2 (%X), player 1 on keyboard", a & 0xFFFFFF))
        end
    end
    -- dev57 (the tester: "if the solo player was on mouse and keyboard last then the next controller should just go to P2
    -- (make L3+R3 for adding a player on that controller)"): started from the keyboard with several controllers,
    -- the first one used after Ctrl + F6 is player 2's; L3 + R3 is then for players 3 and 4. coop_kb_next_pad.
    if not t.p2 and t.start_kb and #devs >= 2 and cfg.coop_kb_next_pad ~= false and now - (t.start_t or 0) > 0.3 then
        local best, bt = nil, nil
        for _, d in ipairs(devs) do
            local at = (t.act or {})[d:get_address()]
            if d ~= spd and at and at > (t.start_t or 0) + 0.25 and (not bt or at < bt) then best, bt = d, at end
        end
        if best and spd then -- 0.9.178-dev4: player 1 keeps the controller he was on
            local a = best:get_address()
            t.p2, p2d, p1d, t.p1 = a, best, spd, t.start_pad
            t.wait_release, t.keep = true, nil
            pcall(json.dump_file, "DPC_two_pads.json", { p1 = t.p1, p2 = t.p2 })
            R.note = { text = "Co-op: player 1 keeps their controller, player 2 on that one (L3 + R3 on another adds a player)", t_end = now + 4.0 }
            coop_event(string.format("two controllers: first other controller used -> player 2 (%X), player 1 keeps %X", a & 0xFFFFFF, t.p1 & 0xFFFFFF))
        elseif best then
            local a = best:get_address()
            t.p2, p2d, p1d, t.p1 = a, best, R.kb_dev, R.KB_ADDR
            t.wait_release, t.keep = true, nil
            R.note = { text = "Co-op: player 1 on keyboard and mouse, player 2 on that controller (L3 + R3 on another adds a player)", t_end = now + 4.0 }
            coop_event(string.format("two controllers: first controller used -> player 2 (%X), player 1 on keyboard", a & 0xFFFFFF))
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
                local any = spd and cfg.coop_kb_next_pad ~= false -- 0.9.178-dev4
                R.note = { text = any and "Co-op: player 2, press a button on your controller (player 1 keeps theirs)"
                    or "Co-op, two controllers: player 2, hold L3 + R3 (both stick clicks) on your controller", t_end = now + 5.0 }
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
-- dev10: seen on the test PC after controllers were swapped / turned off: the controllers' input reached the game
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
-- 0.9.178-dev12 (the tester: "I would like P1 to be the one to control the menus which he seems to be able to do UNLESS
-- someone else is controlling the Arisen"). With player 2 on the Arisen (classic, R.cp.arisen_side 2) the game's own
-- controller is player 2's, and the game's menus read only that one. While a game menu is open, or for 1.5 s after
-- player 1 presses his menu or map button, the game's controller is player 1's; then player 2's again.
R.MENU_MASK = nil
R.menu_mask = function()
    if R.MENU_MASK ~= nil then return R.MENU_MASK end
    local mask = 0
    pcall(function()
        local td = sdk.find_type_definition("via.hid.GamePadButton")
        -- dev19: + CCenter, the PS5 touchpad press (the map on a PlayStation controller; read live: the touchpad is
        -- 0x10000, and Share never reaches the game)
        for _, n in ipairs({ "CRight", "CLeft", "CCenter" }) do -- Options / Start, Share / Back / View, touchpad
            local f = td and td:get_field(n)
            local v = f and f:get_data(nil)
            if type(v) == "number" then mask = mask | v end
        end
    end)
    R.MENU_MASK = mask
    return mask
end
R.game_menu_checks = nil
R.game_menu_open = function(now)
    local g = R.gmo or {}
    R.gmo = g
    if now - (g.t or -1) < 0.1 then return g.v end
    g.t = now
    if R.game_menu_checks == nil then
        local list = {}
        for _, c in ipairs({ { "app.GuiManager", { "get_IsPausedGUINoLock", "get_IsOpenMainFlowUI", "get_IsOptionMenuOpen" } },
                             { "app.PauseManager", { "get_IsPaused" } } }) do
            local td = sdk.find_type_definition(c[1])
            for _, mn in ipairs(c[2]) do
                local m = td and td:get_method(mn)
                if m and m:get_num_params() == 0 then list[#list + 1] = { cls = c[1], m = m } end
            end
        end
        R.game_menu_checks = list
    end
    local open = false
    for _, c in ipairs(R.game_menu_checks) do
        local obj = sdk.get_managed_singleton(c.cls)
        if obj then
            local ok, v = pcall(c.m.call, c.m, obj)
            if ok and v == true then open = true break end
        end
    end
    g.v = open
    return open
end
R.p1_menu_want = function(devs, now)
    local t = R.tp
    if cfg.coop_menus_p1 == false then return nil end
    if not (coop.active and R.cp and R.cp.on and R.cp.arisen_side == 2 and not R.cp.kb and t.p1 and t.p2) then
        t.menu_p1_until, t.menu_owner = nil, nil
        -- dev17: player 1 on the Arisen (the menus are his anyway): the same note when player 2 keeps pressing
        if coop.active and t.p2 and R.game_menu_open(now) then
            for _, d in ipairs(devs) do
                if d:get_address() == t.p2 then
                    local ok, b = pcall(d.call, d, "get_Button")
                    b = ok and b or 0
                    if b ~= 0 and (t.menu_other_prevb or 0) == 0 then
                        if now - (t.menu_p2_t or -10) > 3.0 then t.menu_p2_n = 0 end
                        t.menu_p2_n, t.menu_p2_t = (t.menu_p2_n or 0) + 1, now
                        if t.menu_p2_n >= 2 then
                            R.note = { text = "Player 1 controls this menu", t_end = now + 3.0, menu = true }
                            t.menu_p2_n = 0
                        end
                    end
                    t.menu_other_prevb = b
                end
            end
        end
        return nil
    end
    local p1dev, p2dev = R.cp_dev(1), R.cp_dev(2)
    if not p1dev or p1dev == R.KB_ADDR then return nil end
    local mask = R.menu_mask()
    local p2b = 0
    for _, d in ipairs(devs) do
        local a = d:get_address()
        if a == p1dev or a == p2dev then
            local ok, b = pcall(d.call, d, "get_Button")
            b = ok and b or 0
            if a == p1dev then
                if mask ~= 0 and (b & mask) ~= 0 and ((t.menu_p1_prevb or 0) & mask) == 0 then
                    t.menu_p1_btn_t = now
                    R.cp_event(string.format("player 1 menu / map button (%X): the game's controller is his for 1.5 s", b & mask))
                end
                t.menu_p1_prevb = b
            else
                if mask ~= 0 and (b & mask) ~= 0 and ((t.menu_p2_prevmb or 0) & mask) == 0 then t.menu_p2_btn_t = now end
                t.menu_p2_prevmb = b
                p2b = b
            end
        end
    end
    -- dev16 (test PC: player 2 on the Arisen talked to the Rift; the hire screen went to player 1 half way, then the
    -- parting gift back to player 2: the game reports no menu for a moment between the Rift's screens). A menu now
    -- belongs to whoever opened it until it has been closed for a second: player 1 for the pause menu or map opened
    -- with a menu / map button (either player's), player 2 for a menu that came from his own interaction (the Rift,
    -- a shop, talking): the game's controller stays his.
    local open = R.game_menu_open(now)
    if open then
        if not t.menu_owner then
            -- dev18 (the tester, confused that player 2's Start opened a menu player 2 could not drive): simply, whoever
            -- opened it. Player 1's menu / map button: player 1. Player 2's button or his own interaction: player 2.
            local p1_age, p2_age = now - (t.menu_p1_btn_t or -9), now - (t.menu_p2_btn_t or -9)
            t.menu_owner = (p1_age < 1.5 and p1_age <= p2_age) and "p1" or "p2"
            R.cp_event(string.format("menu opened: %s drives it (P1 button %.1f s ago, P2 button %.1f s ago)", t.menu_owner == "p1" and "player 1" or "player 2", p1_age, p2_age))
        end
        t.menu_closed_t = nil
    elseif t.menu_owner then
        t.menu_closed_t = t.menu_closed_t or now
        if now - t.menu_closed_t > 1.0 then t.menu_owner, t.menu_closed_t = nil, nil; R.cp_event("menu closed") end
    end
    local want = nil
    if t.menu_owner == "p1" then want = p1dev
    elseif not t.menu_owner and now - (t.menu_p1_btn_t or -9) < 1.5 then want = p1dev end -- his press opens it
    -- dev13 / dev17: two presses within 3 s on the controller of the player who is NOT driving the open menu: a note
    -- saying who is ("Player 1 controls this menu" / "Player 2 ...")
    local p1b = t.menu_p1_prevb or 0
    if open and t.menu_owner then
        local other_b = (t.menu_owner == "p1") and p2b or p1b
        local prev = t.menu_other_prevb or 0
        if other_b ~= 0 and prev == 0 then
            if now - (t.menu_p2_t or -10) > 3.0 then t.menu_p2_n = 0 end
            t.menu_p2_n, t.menu_p2_t = (t.menu_p2_n or 0) + 1, now
            if t.menu_p2_n >= 2 then
                local who = (t.menu_owner == "p1") and "Player 1" or "Player 2"
                R.note = { text = who .. " controls this menu", t_end = now + 3.0, menu = true }
                t.menu_p2_n = 0
            end
        end
        t.menu_other_prevb = other_b
    else
        t.menu_other_prevb = 0
    end
    return want
end
R.pad_active_tick = function(devs, now, force)
    -- v0.9.171: in co-op with two controllers the active controller decides who drives the Arisen's input (and,
    -- with both players on pawns, player 1's pawn): kept right even with the follow switch off
    local coop2 = cfg.coop_two_pads and (coop.active or (R.cp_pawns and R.cp_pawns()))
    if not (cfg.pad_active_follow or force or coop2) then return end
    local t = R.tp
    t.act = t.act or {}
    local menu_want = nil
    if coop2 then
        local okm, mw = pcall(R.p1_menu_want, devs, now)
        menu_want = okm and mw or nil
        if (menu_want ~= nil) ~= (t.menu_p1_on == true) then force = true end -- switch at once, both ways
        t.menu_p1_on = menu_want ~= nil
    end
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
    if menu_want then
        want = menu_want -- dev12: a game menu, player 2 on the Arisen: player 1's controller drives the menu
    elseif (coop.active or (R.cp_pawns and R.cp_pawns())) and cfg.coop_two_pads and t.p1 and t.p2 and not t.wait_release then
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
    pcall(R.hid_track, now) -- 0.9.178-dev4
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
    S.pad_prev = S.pad_buttons
    S.pad_buttons = 0
    S.pad_stick_x, S.pad_stick_y = 0.0, 0.0
    S.pad_stick_rx, S.pad_stick_ry = 0.0, 0.0
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
        S.pad_device_ok = true
        if tpv then
            S.pad_buttons = tpv.b or 0
            S.pad_stick_x, S.pad_stick_y, S.pad_stick_rx, S.pad_stick_ry = tpv.lx, tpv.ly, tpv.rx, tpv.ry
        end
    end
    local ok, pad = false, nil
    if tpv == nil then ok, pad = pcall(sdk.call_native_func, gp_single, gp_td, "get_MergedDevice") end
    if tpv == nil then S.pad_device_ok = (ok and pad ~= nil) and true or false end
    if ok and pad then
        local b = call(pad, "get_Button")
        if type(b) == "number" then S.pad_buttons = b end
        local ok_ax, ax_vec = pcall(pad.call, pad, "get_AxisL")
        if ok_ax and ax_vec then
            local ok_x, vx = pcall(function() return ax_vec.x end)
            local ok_y, vy = pcall(function() return ax_vec.y end)
            if ok_x and type(vx) == "number" then S.pad_stick_x = vx end
            if ok_y and type(vy) == "number" then S.pad_stick_y = vy end
        end
        local ok_r, r = pcall(pad.call, pad, "get_AxisR")
        if ok_r and r then
            pcall(function() S.pad_stick_rx, S.pad_stick_ry = r.x + 0.0, r.y + 0.0 end)
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
                S.pad_buttons, S.pad_stick_x, S.pad_stick_y, S.pad_stick_rx, S.pad_stick_ry = 0, 0.0, 0.0, 0.0, 0.0
            end
            S.pad_buttons = S.pad_buttons | (rp.btn or 0)
            if rp.lx then S.pad_stick_x, S.pad_stick_y = rp.lx, rp.ly end
            if rp.rx then S.pad_stick_rx, S.pad_stick_ry = rp.rx, rp.ry end
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
                    S.pad_stick_x, S.pad_stick_y = brain_stick_for(math.atan(dx, dz))
                    local m = R.bind_mask("Jump")
                    if m and ((now * 1000) % 900) < 160 then S.pad_buttons = S.pad_buttons | m end
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
                    if not (px and tx) then S.pad_stick_x, S.pad_stick_y = 0.0, 0.0; return end
                    local dx, dz = tx - px, tz - pz
                    local d = math.sqrt(dx * dx + dz * dz)
                    local sx, sy = brain_stick_for(math.atan(dx, dz))
                    local k = (d > 2.2) and 1.0 or 0.3 -- close in, then only keep facing it
                    S.pad_stick_x, S.pad_stick_y = sx * k, sy * k
                    if d <= 3.0 then
                        local heavy = (math.floor(now / 0.6) % 6) == 5
                        local m = R.bind_mask(heavy and "AttackL" or "AttackS")
                        if m and ((now * 1000) % 600) < 180 then S.pad_buttons = S.pad_buttons | m end
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
    local now_down = (S.pad_buttons & mask) == mask
    local was_down = (S.pad_prev & mask) == mask
    return now_down and not was_down
end
-- v0.9.151: every key of the mod can carry Ctrl (cfg.keys.<id>_ctrl, taken from whether Ctrl was held when the key
-- was chosen). A key without Ctrl does nothing while Ctrl is held, and the other way round.
R.key_hit = function(id)
    if cfg.hotkeys_on == false then return false end -- 0.9.173: master switch (a player keeps DPC controller-only)
    local vk = cfg.keys[id]
    if not vk or vk == 0 or not key_pressed(vk) then return false end
    return S.is_key_down_safe(0x11) == (cfg.keys[id .. "_ctrl"] == true)
end
R.key_label = function(id)
    local vk = cfg.keys[id]
    if not vk or vk == 0 then return "none" end
    return ((cfg.keys[id .. "_ctrl"] == true) and "Ctrl + " or "") .. R.vk_name(vk)
end

-- Read left-stick / WASD movement vector as pure Lua numbers (NEVER calls app.CharacterInput:get_AxisL()!)
local function read_safe_move_stick(live_input)
    local ax, ay = S.pad_stick_x, S.pad_stick_y
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

-- shared with the modules loaded after this one (see shared.lua)
S.poll_keys, S.key_pressed, S.is_ui_open, S.poll_pad = poll_keys, key_pressed, is_ui_open, poll_pad
S.pad_combo_pressed, S.read_safe_move_stick = pad_combo_pressed, read_safe_move_stick
