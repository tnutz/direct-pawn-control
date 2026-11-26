-- Direct Pawn Control: mod API for other mods (_G.DPC).
-- Part of DirectPawnControl.lua, which loads the files in this folder in order (this one is 25 of 26).
-- Never run on its own: REFramework only runs the files directly in reframework/autorun.
local S = require("DirectPawnControl/shared")
local VERSION, dev, cfg, R, log_msg = S.VERSION, S.dev, S.cfg, S.R, S.log_msg
local enqueue_game_thread, JOB_NAMES, skill_name = S.enqueue_game_thread, S.JOB_NAMES, S.skill_name
local get_party, state, arg_addr, brain, coop, quick = S.get_party, S.state, S.arg_addr, S.brain, S.coop, S.quick
local party_warp_to_me, release_possession = S.party_warp_to_me, S.release_possession
local start_possession, despawn_tests = S.start_possession, S.despawn_tests

-- ----------------------------------------------------------------------------
-- v0.9.170 (dev) Mod API, layers 1, 2 and 4 (queries, events, claims, option overrides). Spec:
-- claude/dpc-mod-api.md. Every foreign function runs in pcall; one that fails 5 times within 10 s is switched off
-- and shown under "Connected mods". Callbacks run on the game thread (DPC fires events from there).
-- ----------------------------------------------------------------------------
R.api = { regs = {}, on = {}, claims = {}, overrides = {}, next_id = 1 }
R.API_FEATURES = { events = true, claims = true, overrides = true, players = true, coop2pads = true,
    players_n = true, characters = true, -- 1.1 (0.9.172): players 3+, characters offered by other mods
    control = true, -- 1.2 (0.9.173): possess / release_pawn
    views = true } -- 1.3 (0.9.177-dev37): set_view_turn / view_axes, for split-screen mods
-- 1.3: a split-screen mod gives each player their own view. The game moves a character relative to the main
-- camera, so DPC turns that player's left stick by the angle the mod returns (their view's yaw minus the main
-- view's yaw, radians). One provider; R.view_turn = { fn, mod, n, err }.
R.view_turn = nil
-- dev38: the provider's views are on (opts.active), so player 2's right stick is his view's, never the main camera's
R.views_on = function()
    local vt = R.view_turn
    if not (vt and vt.active) then return false end
    local ok, on = pcall(vt.active)
    return ok and on == true
end
-- dev39: every player's view ({ player, x, y, w, h (pixels), pos, rot (quaternion), fov, vertical, aspect, fwd }) from
-- a split-screen mod, so DPC's bars and cards go into the right view (first split test: they bled across)
R.view_list = nil
R.views_now = function()
    local vl = R.view_list
    if not vl then return nil end
    local ok, list = pcall(vl.fn)
    if ok and type(list) == "table" and #list > 0 then return list end
    return nil
end
R.view_of = function(list, pn)
    for _, v in ipairs(list or {}) do local num = v.player; if num == pn then return v end end -- numbers
    return nil
end
R.qrot = function(q, x, y, z)
    local qx, qy, qz, qw = q[1], q[2], q[3], q[4]
    local tx, ty, tz = 2 * (qy * z - qz * y), 2 * (qz * x - qx * z), 2 * (qx * y - qy * x)
    return x + qw * tx + (qy * tz - qz * ty), y + qw * ty + (qz * tx - qx * tz), z + qw * tz + (qx * ty - qy * tx)
end
-- a world point in one view, or nil when it is behind the camera or outside the view
R.vproj = function(v, x, y, z)
    local fw = v.fwd or -1
    local fx, fy, fz = R.qrot(v.rot, 0, 0, fw)
    local rx, ry, rz = R.qrot(v.rot, -fw, 0, 0)
    local ux, uy, uz = R.qrot(v.rot, 0, 1, 0)
    local dx, dy, dz = x - v.pos[1], y - v.pos[2], z - v.pos[3]
    local zc = dx * fx + dy * fy + dz * fz
    if zc < 0.05 then return nil end
    local t = math.tan(math.rad(v.fov) / 2)
    local tv = v.vertical and t or t / v.aspect
    local th = tv * v.aspect
    local nx = (dx * rx + dy * ry + dz * rz) / (zc * th)
    local ny = (dx * ux + dy * uy + dz * uz) / (zc * tv)
    if math.abs(nx) > 1.0 or math.abs(ny) > 1.0 then return nil end
    return v.x + (nx + 1) * 0.5 * v.w, v.y + (1 - ny) * 0.5 * v.h
end
-- dev40: while a split-screen mod draws several views the game's primary camera can be one of the extra views
-- (seen: UserEditCamera, then BgCamera). DPC's own camera reads use the main camera then.
R.main_cam_c = nil
R.primary_cam = function()
    if R.view_list then
        local c = R.main_cam_c
        if c and pcall(function() assert(c:call("get_GameObject"):call("get_Valid")) end) then return c end
        R.main_cam_c = nil
        local ok, cam = pcall(function()
            local sm = sdk.get_native_singleton("via.SceneManager")
            local sc = sdk.call_native_func(sm, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
            local go = sc:call("findGameObject(System.String)", "MainCamera")
            return go and go:call("getComponent(System.Type)", sdk.typeof("via.Camera"))
        end)
        if ok and cam then R.main_cam_c = cam:add_ref(); return R.main_cam_c end
    end
    return sdk.get_primary_camera()
end
R.view_rot = function(chara, ax, ay)
    local vt = R.view_turn
    if not (vt and chara) or (ax == 0 and ay == 0) then return ax, ay end
    local ok, d = pcall(vt.fn, chara)
    if not ok then vt.err = tostring(d); vt.n_err = (vt.n_err or 0) + 1; return ax, ay end
    if type(d) ~= "number" or d ~= d or d == 0 then return ax, ay end
    vt.n = (vt.n or 0) + 1
    local c, sn = math.cos(d), math.sin(d)
    return ax * c - ay * sn, ax * sn + ay * c
end
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
    local api = { version = "1.3", major = 1, minor = 3, dpc_version = VERSION }
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
    -- 1.3: fn(chara) -> radians to turn that character's player's left stick, or nil. nil fn removes it.
    api.set_view_turn = function(fn, opts)
        opts = type(opts) == "table" and opts or {}
        if fn == nil then R.view_turn = nil; return true end
        if type(fn) ~= "function" then return nil, "expected a function" end
        R.view_turn = { fn = fn, mod = tostring(opts.mod or "a mod"), n = 0,
            active = type(opts.active) == "function" and opts.active or nil } -- dev38
        log_msg("Mod API: " .. R.view_turn.mod .. " turns players' sticks for their own views")
        return true
    end
    -- 1.3: { lx, ly, rx, ry, b } of player p's own controller (read only), or nil (keyboard, no controller)
    -- dev39: fn() -> every player's view (see R.view_list); nil removes it
    api.set_view_list = function(fn, opts)
        opts = type(opts) == "table" and opts or {}
        if fn == nil then R.view_list = nil; return true end
        if type(fn) ~= "function" then return nil, "expected a function" end
        R.view_list = { fn = fn, mod = tostring(opts.mod or "a mod") }
        return true
    end
    api.view_axes = function(p)
        p = p or 1
        local t = R.tp or {}
        local function by_addr(a)
            if not a or a == R.KB_ADDR then return nil end
            for _, d in ipairs(R.tp_devs()) do if d:get_address() == a then return R.tp_read(d) end end
            return nil
        end
        if p == 1 then return t.p1 ~= R.KB_ADDR and t.p1v or nil end
        if p == 2 then
            local v = t.p2v or by_addr(t.p2)
            if v then return v end
            -- one controller, player 1 on the keyboard: the game's merged pad is player 2's
            -- dev40: not in two-controller co-op while player 2 has not claimed one yet (L3 + R3): the split test
            -- turned his view with the merged pad while his character could not move
            if R.tp_kb and R.tp_kb() and not cfg.coop_two_pads then
                local gs, gt = sdk.get_native_singleton("via.hid.GamePad"), sdk.find_type_definition("via.hid.GamePad")
                local ok, pad = pcall(sdk.call_native_func, gs, gt, "get_MergedDevice")
                if ok and pad then return R.tp_read(pad) end
            end
            return nil
        end
        local sl = R.np and R.np.slots and R.np.slots[p]
        return sl and by_addr(sl.dev) or nil
    end
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

-- 0.9.174 Loot to the Arisen (cfg.pawn_loot_to_arisen, off by default; asked for by the tester, and a candidate fix for a
-- report where the game died right after a played pawn's loot on a load order with several loot-award hooks).
-- The pawn still runs the loot (the path verified since v0.9.26); for 1.5 s after that, the game's item award is
-- re-addressed from the pawn to the Arisen: the receiver argument of ItemManager.getItem(..., app.Character, ...) and
-- the CharacterID of getItemNoLock. So the items land in his bag and every other mod's hook on those calls sees the
-- player as the receiver, as in vanilla. Nothing changes when the option is off or no loot window is open.
R.loot_win = nil
R.loot_window_open = function()
    R.loot_win = nil
    if not cfg.pawn_loot_to_arisen or not state.pawn_chara then return end
    local ar = state.arisen_chara or R.real_player()
    if not ar then return end
    local okp, pid = pcall(state.pawn_chara.call, state.pawn_chara, "get_CharaID")
    local oka, aid = pcall(ar.call, ar, "get_CharaID")
    R.loot_win = { pawn = state.pawn_chara:get_address(), ar_addr = ar:get_address(), pawn_id = okp and tonumber(pid) or nil,
        ar_id = oka and tonumber(aid) or nil, t_end = os.clock() + 1.5, n = 0 }
end
R.loot_hooks_install = function() -- a function, not a do-block: the main chunk is at Lua's 200-locals limit
    local td = sdk.find_type_definition("app.ItemManager")
    -- (signature, position of the receiver in args: args[2] is the ItemManager, args[3] the first parameter)
    local by_chara = {
        { "getItem(app.ItemDropLottery.ItemResult, app.Character, app.ItemDefine.GetItemOption)", 4 },
        { "getItem(app.ItemDropLottery.ItemResult, app.Character)", 4 },
        { "getItem(System.Int32, System.Int32, app.Character, app.ItemDefine.GetItemOption)", 5 },
        { "getItem(System.Int32, System.Int32, app.Character)", 5 },
    }
    local by_id = { { "getItemNoLock(System.Int32, System.Int32, app.CharacterID, app.ItemDefine.GetItemOption, System.Int32, System.Int32)", 5 } }
    R.loot_hooks = 0
    if td then
        for _, h in ipairs(by_chara) do
            local m = td:get_method(h[1])
            if m then
                local at = h[2]
                pcall(sdk.hook, m, function(args)
                    local w = R.loot_win
                    if not w or os.clock() > w.t_end then return end -- the common path: no loot window open
                    if arg_addr(args[at]) ~= w.pawn then return end
                    args[at] = sdk.to_ptr(w.ar_addr)
                    w.n = w.n + 1
                end, function(retval) return retval end)
                R.loot_hooks = R.loot_hooks + 1
            end
        end
        for _, h in ipairs(by_id) do
            local m = td:get_method(h[1])
            if m then
                local at = h[2]
                pcall(sdk.hook, m, function(args)
                    local w = R.loot_win
                    if not w or os.clock() > w.t_end or not w.pawn_id or not w.ar_id then return end
                    if (sdk.to_int64(args[at]) & 0xFFFFFFFF) ~= w.pawn_id then return end
                    args[at] = sdk.to_ptr(w.ar_id)
                    w.n = w.n + 1
                end, function(retval) return retval end)
                R.loot_hooks = R.loot_hooks + 1
            end
        end
    end
end
R.loot_hooks_install()

-- 0.9.175 Skill diagnostics. Players report pawn skills that "don't work" (one with the Dullahan / Skill Creator
-- mods, one random on an archer). When a requested skill never starts inside the retry window, log what the pawn
-- was doing, its stamina, whether the weapon was drawn, whether the skill id is a vanilla one, and which known
-- skill-changing mods are loaded, so a report (or the log) says why. Counters for TestGuide: R.skill_ok_n,
-- R.skill_fail_n, R.skill_fail_last.
R.SKILL_ID_VANILLA_MAX = 131 -- Trickster / Assassin maister skills; Skill Creator gives its "new" skills 121/132 and up
R.skill_mods = function()
    if R.skill_mods_s then return R.skill_mods_s end
    local t = {}
    if _G.NickCore then t[#t + 1] = "_NickCore" end
    for _, m in ipairs({ { "SkillCreator/SkillHandler", "Skill Creator" }, { "Dullahan/Config", "Dullahan" },
                         { "_ScriptCore/Hotkeys", "_ScriptCore" } }) do
        if package.loaded[m[1]] then t[#t + 1] = m[2] end
    end
    if _G.SkillMaker or _G.skill_maker then t[#t + 1] = "Skill Maker" end
    R.skill_mods_s = table.concat(t, ", ")
    return R.skill_mods_s
end
-- 0.9.175 Dullahan compatibility. Dullahan's "Rearmament" option (on by default) pre-hooks the game's player input
-- (PlayerInputProcessorDetail.processCustomSkill) and, when a skill doesn't belong to the ARISEN's current weapon,
-- swaps his weapon and cancels the press. A pawn played with native controls uses its own copy of that input code,
-- so its skills were cancelled whenever its vocation differed from the Arisen's and he was free to act (Nexus
-- report, reproduced in skill-mods-1/2 with an Archer pawn and a Fighter Arisen). While anyone plays a pawn,
-- DPC turns that option off and puts it back afterwards (the Arisen isn't pressing skills then anyway).
R.compat_tick = function()
    local now = os.clock()
    if now < (R.compat_next or 0) then return end
    R.compat_next = now + 0.5
    local dc = package.loaded["Dullahan/Config"]
    dc = type(dc) == "table" and dc.WARFARER -- the option lives in Config.WARFARER (dev2 looked at the top level)
    if type(dc) ~= "table" then return end
    local playing = state.active or coop.active
    if playing and dc.REARMAMENT and not R.compat_rearm_off then
        R.compat_rearm_off = true
        dc.REARMAMENT = false
        log_msg("Dullahan found: its Rearmament option is paused while a pawn is played (it would cancel the pawn's skills)")
    elseif not playing and R.compat_rearm_off then
        R.compat_rearm_off = nil
        dc.REARMAMENT = true
    end
end
re.on_frame(function() pcall(R.compat_tick) end)
R.skill_fail_note = function(ps, cur_sk)
    local pc, ph = state.pawn_chara, state.pawn_human
    local node, st, drawn = "?", nil, nil
    pcall(function()
        local fsm = pc:call("get_ActionManager"):get_field("Fsm")
        node = tostring(fsm:call("getCurrentNodeName(System.UInt32)", 0)) .. " | " .. tostring(fsm:call("getCurrentNodeName(System.UInt32)", 1))
    end)
    pcall(function()
        local sm = pc:call("get_StaminaManager")
        st = sm:call("get_RemainingAmount")
    end)
    pcall(function() drawn = pc:call("get_IsDrawedWeapon") end)
    local why = {}
    if (ps.id or 0) > R.SKILL_ID_VANILLA_MAX then why[#why + 1] = "not a vanilla skill id (added by a skill mod; the game can't play it on a pawn)" end
    if st and st <= 1 then why[#why + 1] = "out of stamina" end
    if drawn == false then why[#why + 1] = "weapon not drawn" end
    local mods = R.skill_mods()
    R.skill_fail_n = (R.skill_fail_n or 0) + 1
    R.skill_fail_last = { id = ps.id, slot = ps.slot, tries = ps.tries, node = node, stamina = st, drawn = drawn,
        now_skill = cur_sk, mods = mods, why = table.concat(why, "; ") }
    log_msg(string.format("Skill %s: %s (id %s) did not start after %d tries. Pawn: %s, stamina %s, weapon %s, skill now %s%s%s",
        tostring(ps.slot), skill_name(ps.id), tostring(ps.id), ps.tries or 0, node, st and string.format("%.0f", st) or "?",
        drawn == nil and "?" or (drawn and "drawn" or "sheathed"), tostring(cur_sk),
        #why > 0 and (". Likely: " .. R.skill_fail_last.why) or "", mods ~= "" and (". Skill mods loaded: " .. mods) or ""))
end

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
