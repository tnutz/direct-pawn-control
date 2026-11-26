-- Direct Pawn Control: co-op any combination: who each player controls (R.cp).
-- Part of DirectPawnControl.lua, which loads the files in this folder in order (this one is 18 of 26).
-- Never run on its own: REFramework only runs the files directly in reframework/autorun.
local S = require("DirectPawnControl/shared")
local dev_error, cfg, R, log_msg, get_party, state = S.dev_error, S.cfg, S.R, S.log_msg, S.get_party, S.state
local coop, coop_event, release_possession = S.coop, S.coop_event, S.release_possession
local start_possession, coop_write_status, coop_start = S.start_possession, S.coop_write_status, S.coop_start

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

-- 0.9.178-dev10 (the tester: "Can we keep co-op on across ferrystones and the like? If not can we save the config we had
-- and restore it after?"). Co-op still ends for a Ferrystone, cutscene or loading (the Ferrystone crash fix needs
-- everyone let go before the teleport); what each player had is remembered here and put back by R.cr_tick.
-- Characters are kept by name (party order can change), controllers by address.
R.cr_snapshot = function()
    local c = R.cp
    if not c.on then return nil end
    local function nm(ch)
        if ch == "arisen" then return "arisen" end
        for _, e in ipairs(get_party()) do if e.idx == ch then return tostring(e.name) end end
        return nil
    end
    local arr = { p1 = nm(c.char[1]), p2 = nm(c.char[2]), tp1 = R.tp and R.tp.p1, tp2 = R.tp and R.tp.p2, extra = {} }
    if R.np then
        local ns = {}
        for n in pairs(R.np.slots) do ns[#ns + 1] = n end
        table.sort(ns)
        for _, n in ipairs(ns) do
            local sl = R.np.slots[n]
            if sl and sl.dev then arr.extra[#arr.extra + 1] = { dev = sl.dev, name = sl.name } end
        end
    end
    return arr
end
-- the pawn the classic restart gives player 2 (a pawn either player had)
R.cr_start_pawn = function(arr)
    if arr.p2 and arr.p2 ~= "arisen" then return arr.p2 end
    if arr.p1 and arr.p1 ~= "arisen" then return arr.p1 end
    return nil
end
-- after the classic restart: put players 1 and 2 back on their characters, then players 3+ on their controllers
R.cr_restore = function(arr)
    local function idx_of(name)
        if name == "arisen" then return "arisen" end
        for _, e in ipairs(get_party()) do if tostring(e.name) == name then return e.idx end end
        return nil
    end
    local a, b = idx_of(arr.p1), idx_of(arr.p2)
    local c = R.cp
    local applied = false
    if c.on and a ~= nil and b ~= nil and a ~= b and not (c.char[1] == a and c.char[2] == b) then
        applied = R.cp_apply({ [1] = a, [2] = b }, "co-op resumed") == true
    end
    for _, x in ipairs(arr.extra or {}) do
        local taken = (R.tp.p1 == x.dev) or (R.tp.p2 == x.dev)
        for _, sl in pairs(R.np and R.np.slots or {}) do if sl.dev == x.dev then taken = true end end
        if not taken then
            for _, d in ipairs(R.tp_devs()) do
                if d:get_address() == x.dev then pcall(R.np_join, d) break end
            end
        end
    end
    R.cp_event(string.format("resume: P1=%s P2=%s, %d more (%s)", tostring(arr.p1), tostring(arr.p2), #(arr.extra or {}), applied and "rearranged" or "as started"))
end

-- session end (co-op off, loading, a cutscene ...). Never while R.cp_apply is rebuilding.
R.cp_end = function(why)
    local c = R.cp
    if c.busy then return end
    local was_pawns = c.on and c.mode == "pawns"
    -- dev10: the both-pawns arrangement has no classic co-op to end (coop.on_release does not run), so the resume is
    -- noted here; a classic session already noted it in coop.on_release
    if c.on and cfg.coop_auto_resume and not R.CR_USER[tostring(why)] and not (R.cr and R.cr.want) then
        local arr = R.cr_snapshot()
        local pawn = arr and R.cr_start_pawn(arr)
        if pawn then
            local cr = R.cr
            cr.want, cr.name, cr.idx, cr.reason, cr.arr = true, pawn, nil, tostring(why), arr
            cr.p1, cr.p2 = R.cp_dev(1), R.cp_dev(2) -- dev11: each person's own controller
            cr.ok_since, cr.tries, cr.next, cr.noted, cr.down = nil, 0, os.clock() + 1.0, false, nil
        end
    end
    if R.s2.active then pcall(R.s2_stop, why or "co-op off") end
    if R.np then pcall(R.np_end, why or "co-op off") end
    if c.on then R.cp_event("session off (" .. tostring(why) .. ")") end
    c.on, c.mode, c.arisen_side, c.ar2 = false, "classic", 1, false
    R.ar2_src = nil
    if R.tp and not coop.active then R.tp.start_kb, R.tp.start_t, R.tp.start_pad = nil, nil, nil end -- dev50
    -- 0.9.177 (the tester: "when we drop co-op, player 1 should stay on whatever character he was controlling"): player 1's
    -- pawn here is an ordinary single-player possession; it stays. (Before, ending co-op sent him back to the Arisen.)
    if was_pawns and state.active and not coop.active and cfg.coop_end_keep_p1 == false then pcall(release_possession, "co-op off") end
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
    if R.unlean_defer({ R.chara_of_idx(a) or {}, R.chara_of_idx(b) or {} }, function() R.cp_apply(want, why) end, "Co-op change") then return true end
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
