-- Direct Pawn Control: co-op: players 3 and up (R.np), player 2's Arisen, the co-op tick.
-- Part of DirectPawnControl.lua, which loads the files in this folder in order (this one is 20 of 26).
-- Never run on its own: REFramework only runs the files directly in reframework/autorun.
local S = require("DirectPawnControl/shared")
local dev_error, cfg, R, log_msg, same_obj, call = S.dev_error, S.cfg, S.R, S.log_msg, S.same_obj, S.call
local JOB_NAMES, get_job, get_skills, get_party, state = S.JOB_NAMES, S.get_job, S.get_skills, S.get_party, S.state
local brain, coop, brain_pos, brain_alive = S.brain, S.coop, S.brain_pos, S.brain_alive
local coop_pad_values, coop_write_status = S.coop_pad_values, S.coop_write_status

-- ------------------------------------------------------------------------------- players 3 and up (0.9.172)
-- Each extra player is a slot shaped like R.s2 (same start / stop / tick / drive code, the slot passed in) with its
-- own claimed controller. Design: claude/dpc-coop-n.md. Joins with L3 + R3 held 1.5 s on an unclaimed controller
-- while co-op runs on two controllers; the take-control combination goes to the next free pawn; L3 + R3 held 3 s
-- leaves. Pawns only for now (the Arisen's driver needs player 1 on a pawn and takes one source).
R.np = { slots = {}, log = {}, pool = {} }
-- the characters players 3+ can take: the party (an extra-pawn mod that grows the party is included by the game's own
-- list) and characters other mods offer through DPC_API.add_character (index 100 and up)
R.party_all = function()
    local out = get_party()
    for i, h in ipairs(R.np.pool) do
        if not h.gone and h.chara then
            local ok, e = pcall(function()
                local ch = h.chara
                if not sdk.is_managed_object(ch) then return nil end
                local hu = call(ch, "get_Human")
                local job = get_job(hu, ch)
                return { idx = 100 + i, chara = ch, human = hu, pawn = nil, name = h.name or ("Character " .. i),
                    job = job, job_name = JOB_NAMES[job] or ("Job#" .. tostring(job)), skills = get_skills(hu, job), from_mod = h.mod }
            end)
            if ok and e then out[#out + 1] = e end
        end
    end
    return out
end
R.np_event = function(t)
    local L = R.np.log
    L[#L + 1] = string.format("%.2f %s", os.clock(), t)
    if #L > 30 then table.remove(L, 1) end
end
-- who plays pawn idx (any player but the slot given): a player number, or nil
R.held_by = function(idx, except)
    if idx == nil then return nil end
    if state.active and state.pawn_idx == idx then
        return (coop.active and not (R.cp and R.cp.on and R.cp.arisen_side == 2)) and 2 or 1
    end
    if R.s2.active and R.s2.idx == idx and except ~= R.s2 then return 2 end
    for n, sl in pairs(R.np.slots) do
        if sl.active and sl.idx == idx and sl ~= except then return n end
    end
    return nil
end
R.np_sel = function(a) -- the action selector address belongs to an extra player's pawn?
    for _, sl in pairs(R.np.slots) do if sl.active and a == (sl.sel_addr or -1) then return true end end
    return false
end
R.np_claimed = function(a)
    for n, sl in pairs(R.np.slots) do if sl.dev == a then return n end end
    return nil
end
R.np_count = function() local n = 0; for _ in pairs(R.np.slots) do n = n + 1 end; return n end
-- the first free pawn after "from" in party order (wrapping), nil if none
R.np_free_pawn = function(from, self)
    local round = {}
    for _, e in ipairs(R.party_all()) do
        if not R.held_by(e.idx, self) and R.cr_ok(e.chara) then round[#round + 1] = e.idx end
    end
    table.sort(round)
    if #round == 0 then return nil end
    if from == nil then return round[1] end
    for _, v in ipairs(round) do if v > from then return v end end
    return round[1]
end
R.np_join = function(d)
    local c = R.cp
    local n = 3
    while R.np.slots[n] do n = n + 1 end
    if n > (cfg.coop_max_players or 8) then
        R.note = { text = "Co-op: " .. (n - 1) .. " players already", t_end = os.clock() + 3.0 }
        return false
    end
    local idx = R.np_free_pawn(nil, nil)
    if not idx then
        R.note = { text = "Co-op: no free character for player " .. n, t_end = os.clock() + 3.0 }
        return false
    end
    local sl = { player = n, dev = d:get_address(), active = false, hooked = true, latch = {}, errors = 0, frames = 0 }
    R.np.slots[n] = sl
    if not R.s2_start(idx, sl) then
        R.np.slots[n] = nil
        R.note = { text = "Co-op: player " .. n .. " could not take a character", t_end = os.clock() + 3.0 }
        return false
    end
    sl.wait_release = true
    R.np_event(string.format("player %d joined (%X) on %s", n, sl.dev & 0xFFFFFF, tostring(sl.name)))
    R.note = { text = "Co-op: player " .. n .. " joined, plays " .. tostring(sl.name), t_end = os.clock() + 4.0 }
    log_msg("Co-op: player " .. n .. " joined on " .. tostring(sl.name))
    if R.api_fire then pcall(R.api_fire, "player_join", { player = n, name = sl.name }) end
    pcall(coop_write_status)
    return true
end
R.np_leave = function(n, why)
    local sl = R.np.slots[n]
    if not sl then return end
    if sl.active and why ~= "script reset" then
        local g = R.pglow[n]
        if g and g.kept then pcall(R.cine_glow, g.chara, g.name, false) end
        R.pglow[n] = nil
        R.leave_glow(sl.chara) -- dev38: show who left
    end
    if sl.active then pcall(R.s2_stop, why or "left", sl) end
    R.np.slots[n] = nil
    R.np_event("player " .. n .. " left (" .. tostring(why) .. ")")
    log_msg("Co-op: player " .. n .. " left (" .. tostring(why) .. ")")
    if R.api_fire then pcall(R.api_fire, "player_leave", { player = n, reason = tostring(why or "") }) end
    pcall(coop_write_status)
end
R.np_end = function(why)
    for n in pairs(R.np.slots) do R.np_leave(n, why) end
end
R.np_next = function(n)
    local sl = R.np.slots[n]
    if not sl then return false end
    local nxt = R.np_free_pawn(sl.idx, sl)
    if nxt == nil or nxt == sl.idx then
        R.note = { text = R.cp_label(n) .. ": nobody else to take", t_end = os.clock() + 2.0 }
        return false
    end
    local was = sl.idx
    pcall(R.s2_stop, "next character", sl)
    if not R.s2_start(nxt, sl) then
        pcall(R.s2_start, was, sl) -- back to the one before
        return false
    end
    sl.wait_release = true
    R.note = { text = R.cp_label(n) .. ": " .. tostring(sl.name), t_end = os.clock() + 3.0 }
    R.np_event("player " .. n .. " -> " .. tostring(sl.name))
    pcall(coop_write_status)
    return true
end
-- once a frame from R.cp_tick (co-op on): controllers, joins of a lost controller, each slot's tick
R.np_tick = function()
    if not next(R.np.slots) then return end
    local devs = R.tp_devs()
    local by = {}
    for _, d in ipairs(devs) do by[d:get_address()] = d end
    local now = os.clock()
    local lost = {}
    for n, sl in pairs(R.np.slots) do
        local d = sl.dev and by[sl.dev]
        if d then
            local okr, v = pcall(R.tp_read, d)
            v = okr and v or { b = 0, lx = 0.0, ly = 0.0, rx = 0.0, ry = 0.0 }
            if sl.wait_release then
                if v.b == 0 then sl.wait_release = nil end
                v = { b = 0, lx = v.lx, ly = v.ly, rx = v.rx, ry = v.ry }
            end
            sl.pad, sl.pad_lost = v, nil
            -- dev41: R.s2_tick consumes sl.pad (sets it nil), so the camera, which runs later in the frame, never saw
            -- players 3+'s sticks ("p3 and P4 cameras did not do anything"; bridge: sl.pad nil on both). Kept here.
            sl.pad_cam = { b = v.b or 0, lx = v.lx or 0.0, ly = v.ly or 0.0, rx = v.rx or 0.0, ry = v.ry or 0.0 } -- raw (np_aim takes R3 out of v)
            if sl.active then pcall(R.np_aim, sl, now) end
        else
            sl.pad, sl.pad_cam = { b = 0, lx = 0.0, ly = 0.0 }, nil
            if not sl.pad_lost then
                sl.pad_lost = now
                R.np_event("player " .. n .. "'s controller went away")
                R.note = { text = "Co-op: player " .. n .. "'s controller went away - press a button on it when it is back", t_end = now + 4.0 }
            end
            lost[#lost + 1] = sl
        end
        if sl.active then
            R.s2_tick(sl)
            if not sl.active and R.np.slots[n] then
                -- the pawn went down: the next free one, or the player waits without a character
                local why = sl.lost or "lost"
                sl.lost = nil
                local nxt = (why ~= "cutscene") and R.np_free_pawn(sl.idx, sl) or nil
                if not (nxt and R.s2_start(nxt, sl)) then
                    R.np_event("player " .. n .. ": no character (" .. why .. ")")
                    R.note = { text = "Co-op: player " .. n .. " has no character - press the take-control combination", t_end = now + 3.0 }
                end
            end
        else
            -- no character: the take-control combination looks for a free one
            local raw = sl.pad and sl.pad.b or 0
            local tm = R.take_mask and R.take_mask() or 0
            if tm ~= 0 and (raw & tm) == tm and ((sl.take_prev or 0) & tm) ~= tm then
                local nxt = R.np_free_pawn(nil, sl)
                if nxt and R.s2_start(nxt, sl) then sl.wait_release = true end
            end
            sl.take_prev = raw
        end
    end
    -- a controller that is back under a new address: the oldest lost slot takes the first unclaimed controller used
    -- (after players 1 and 2's own recovery in R.tp_tick)
    if #lost > 0 and not R.tp.keep then
        table.sort(lost, function(a, b) return (a.pad_lost or 0) < (b.pad_lost or 0) end)
        for _, d in ipairs(devs) do
            local a = d:get_address()
            if a ~= R.tp.p1 and a ~= R.tp.p2 and not R.np_claimed(a) then
                local okr, v = pcall(R.tp_read, d)
                if okr and v and R.tp_used(v) then
                    local sl = table.remove(lost, 1)
                    sl.dev, sl.pad_lost, sl.wait_release = a, nil, true
                    R.np_event(string.format("player %d's controller is back (%X)", sl.player, a & 0xFFFFFF))
                    R.note = { text = "Co-op: player " .. sl.player .. "'s controller is back", t_end = now + 3.0 }
                    if #lost == 0 then break end
                end
            end
        end
    end
end
-- 0.9.172-dev36: players 3+ aim like player 2: a quick right-stick flick keeps the next enemy on that side, R3 lets
-- go (back to the automatic target). R3 is taken out of their buttons, as for player 2.
R.np_side = function(sl, dir)
    local ds = imgui.get_display_size()
    local w = ds and ds.x or 1920
    local px, _, pz = brain_pos(sl.chara)
    if not px then return nil end
    local cx = nil
    if sl.tgt then
        local x, y, z = brain_pos(sl.tgt)
        cx = x and R.ta_sx({ x = x, y = y, z = z })
    end
    if not cx then
        local x, y, z = brain_pos(sl.chara)
        cx = x and R.ta_sx({ x = x, y = y, z = z }) or w * 0.5
    end
    local best, gap = nil, nil
    local em = sdk.get_managed_singleton("app.EnemyManager")
    local arr = em and call(em, "getAllEnemies")
    local n = arr and call(arr, "get_Count") or 0
    for i = 0, n - 1 do
        local ok, e = pcall(function() return arr[i]:get_field("_Chara") end)
        if ok and e and brain_alive(e) and not (sl.tgt and same_obj(e, sl.tgt)) then
            local ex, ey, ez = brain_pos(e)
            if ex and (ex - px) ^ 2 + (ez - pz) ^ 2 <= 45.0 ^ 2 then
                local sx = R.ta_sx({ x = ex, y = ey, z = ez })
                if sx and sx > 0 and sx < w then
                    local dx = sx - cx
                    if (dir > 0 and dx > 1) or (dir < 0 and dx < -1) then
                        if not gap or math.abs(dx) < gap then best, gap = e, math.abs(dx) end
                    end
                end
            end
        end
    end
    return best
end
R.np_aim = function(sl, now)
    local p = sl.pad
    if not (p and cfg.coop_aim) then return end
    local pv = coop_pad_values()
    local r3, l3 = pv.RStickPush or 0x2000, pv.LStickPush or 0x1000
    local b = p.b or 0
    if (b & l3) ~= 0 then sl.r3_prev, sl.r3_t = false, nil; return end -- L3 + R3: join / leave / take, left alone
    local down = (b & r3) ~= 0
    if down and not sl.r3_prev then sl.r3_t = now end
    if not down and sl.r3_prev and sl.r3_t and now - sl.r3_t < 0.4 and sl.pin then
        sl.pin, sl.tgt_next = nil, 0
        R.ta_note("Player " .. sl.player .. ": automatic target")
    end
    sl.r3_prev = down
    p.b = b & ~r3
    sl.fa = sl.fa or {}
    local d = R.flick_step(sl.fa, p.rx or 0.0, p.ry or 0.0, now)
    if d then
        local e = R.np_side(sl, d)
        if e then sl.pin, sl.tgt_next = e, 0; R.ta_note("Player " .. sl.player .. ": target kept (R3 lets go)") end
    end
end
-- the played characters of players 3+, in player order (for R.players, sound, the camera)
R.np_charas = function()
    local out = {}
    local ns = {}
    for n in pairs(R.np.slots) do ns[#ns + 1] = n end
    table.sort(ns)
    for _, n in ipairs(ns) do
        local sl = R.np.slots[n]
        if sl.active and sl.chara then out[#out + 1] = { player = n, chara = sl.chara, idx = sl.idx, name = sl.name } end
    end
    return out
end

-- once a frame from the main tick, before it returns for "nobody possessed"
-- 0.9.171: player 2 on the Arisen (both-pawns arrangement, c.ar2): player 2's controller (R.s2.pad, filled by
-- R.cp_pad_route) through the co-op pad map with the Arisen's vocation and skills, handed to the brain as its
-- scripted input. The camera's right stick stays player 1's.
R.ar2_tick = function()
    local c = R.cp
    local now = os.clock()
    local p = R.s2.pad or { b = 0, lx = 0.0, ly = 0.0 }
    R.s2.pad = nil
    local raw = p.b or 0
    local tm = R.take_mask and R.take_mask() or 0
    if c.ar2_take_prev == nil then c.ar2_take_prev = raw end
    if tm ~= 0 and (raw & tm) == tm and (c.ar2_take_prev & tm) ~= tm and not R.cap and R.cp_quiet_ok() then
        c.ar2_take_prev = raw
        R.ar2_src = nil
        R.cp_next(2)
        return
    end
    c.ar2_take_prev = raw
    local pv = coop_pad_values()
    local leave = (pv.LStickPush or 0x1000) | (pv.RStickPush or 0x2000)
    if (raw & leave) == leave then
        c.ar2_leave_t = c.ar2_leave_t or now
        if now - c.ar2_leave_t >= 3.0 then
            c.ar2_leave_t = nil
            R.ar2_src = nil
            R.note = { text = "Co-op: player 2 left", t_end = now + 3.0 }
            R.cp_end("player 2 held L3 + R3")
            return
        end
    else
        c.ar2_leave_t = nil
    end
    local job, sk = brain.job, brain.skills
    if not job then
        pcall(function()
            local cm = sdk.get_managed_singleton("app.CharacterManager")
            if not cm then return end
            local ar = cm:call("get_ManualPlayer")
            local hu = ar and ar:call("get_Human")
            job = get_job(hu, ar)
            sk = get_skills(hu, job)
        end)
    end
    c.ar2_latch = c.ar2_latch or {}
    local okp, on, ax, ay, mag = pcall(R.s2_pad_input, p, job, sk, c.ar2_latch)
    if not okp then
        c.ar2_err = tostring(on)
        dev_error("co-op P2 Arisen input", on)
        on, ax, ay, mag = 0, 0.0, 0.0, 0.0
    end
    mag = mag or 0.0
    if R.view_turn then ax, ay = R.view_rot(state.arisen_chara, ax or 0.0, ay or 0.0) end -- 1.3
    local sx, sy = 0.0, 0.0
    if mag > 0.001 then sx, sy = (ax or 0.0) / mag, (ay or 0.0) / mag end
    R.ar2_src = { want = on or 0, sx = sx, sy = sy, mag = mag, until_t = now + 0.25, label = "player 2" }
    if state.arisen_chara then
        pcall(R.qi_pad, c, raw, state.arisen_chara, "player 2, the Arisen")
        if R.ar2_view then pcall(R.card_refresh, R.ar2_view, state.arisen_chara, raw) end
    end
    c.ar2_frames = (c.ar2_frames or 0) + 1
    -- 0.9.172: what player 2's bars and skill list show (the Arisen's), refreshed 5 times a second
    local v = R.ar2_view or {}
    R.ar2_view = v
    v.active = true
    if now - (v.bars_t or 0) > 0.2 then
        pcall(function()
            local cm = sdk.get_managed_singleton("app.CharacterManager")
            local ar = cm and cm:call("get_ManualPlayer")
            if not ar then return end
            local hu = ar:call("get_Human")
            v.job = job or get_job(hu, ar)
            v.skills = sk or get_skills(hu, v.job)
            if not v.name then v.name = R.cp_char_name and R.cp_char_name("arisen") or "the Arisen" end
            local sm = ar:call("get_StaminaManager")
            local mx = sm and sm:call("get_MaxValue") or 0
            if mx > 0 then v.st = math.max(0.0, math.min(1.0, (sm:call("get_RemainingAmount") or 0) / mx)) end
            local hit = ar:call("get_Hit")
            local omx = hit and hit:call("get_OriginalMaxHp") or 0
            if omx > 0 then v.hp = math.max(0.0, math.min(1.0, (hit:call("get_Hp") or 0) / omx)) end
            v.bars_t = now
        end)
    end
end

R.cp_tick = function()
    local c = R.cp
    if not c.on then
        if R.s2.active then R.s2_stop("no co-op") end
        if next(R.np.slots) then R.np_end("no co-op") end
        return
    end
    if c.busy then return end
    local oknp, enp = pcall(R.np_tick)
    if not oknp then R.np.err = tostring(enp); dev_error("co-op extra players", enp) end
    pcall(R.cp_release_check)
    if c.mode == "classic" then
        if not coop.active then R.cp_end("co-op ended") return end
        if not R.cp_two() then c.kb = true elseif c.kb then c.kb = false end
        if state.active and c.char[c.arisen_side == 1 and 2 or 1] ~= state.pawn_idx then
            c.char[c.arisen_side == 1 and 2 or 1] = state.pawn_idx
            pcall(R.cp_names)
            pcall(coop_write_status)
        end
        -- the Arisen side's own take-control combination (two controllers: his controller; one: F6, below)
        if not c.kb then
            local v = R.tp.p1v
            local b = v and v.b or 0
            local tm = R.take_mask and R.take_mask() or 0
            local prev = c.ar_prevb or 0
            c.ar_prevb = b
            if cfg.coop_any and tm ~= 0 and (b & tm) == tm and (prev & tm) ~= tm and not R.cap and R.cp_quiet_ok() then R.cp_next(c.arisen_side) end
        end
        return
    end
    -- both on pawns
    if not state.active then
        local why = tostring(R.cp_last_rel or "")
        if why:find("loading") or why:find("cutscene") or why:find("teardown") or why:find("script") or why:find("arisen died") then
            R.cp_end(why)
        elseif R.s2.active then
            R.cp_apply({ [1] = "arisen", [2] = R.s2.idx }, "P1 back to the Arisen (" .. why .. ")")
        else
            R.cp_end(why)
        end
        return
    end
    c.char[1] = state.pawn_idx
    if c.ar2 then R.ar2_tick() return end
    if not R.s2.active then
        -- player 2's pawn went down / into a cutscene: the next free character for player 2, else end
        local why = R.s2.lost or "lost"
        R.s2.lost = nil
        if why == "cutscene" then R.cp_end("cutscene") return end
        R.note = { text = "P2's pawn is down", t_end = os.clock() + 3.0 }
        local nxt
        for _, e in ipairs(get_party()) do
            if e.idx ~= state.pawn_idx and R.cr_ok(e.chara) and (not nxt or e.idx < nxt) then nxt = e.idx end
        end
        if nxt then
            R.cp_apply({ [1] = state.pawn_idx, [2] = nxt }, "P2's pawn " .. why)
        elseif not c.kb then
            R.cp_apply({ [1] = state.pawn_idx, [2] = "arisen" }, "P2's pawn " .. why)
        else
            R.cp_end("P2's pawn " .. why)
        end
        return
    end
    R.s2_tick()
end

-- the world went away (loading): nothing of the session survives it
R.cp_world_lost = function()
    if R.s2.active then pcall(R.s2_stop, "loading") end
    pcall(R.np_end, "loading")
    if R.cp.on then R.cp.busy = false; R.cp_end("loading") end
end

-- 0.9.172: players 3+'s bars, stacked above player 2's place, one row per player
re.on_frame(function()
    if not (R.np and next(R.np.slots) and cfg.coop_stamina_bar) then return end
    if R.hud_hidden and R.hud_hidden() then return end
    pcall(function()
        local hx, hy, hw, hh = R.hud_rect()
        local w = hw * 0.12 * (cfg.coop_stamina_width or 1.0)
        local h = math.max(2.0, (cfg.coop_bars_thick or 4.0) * hh / 2160.0)
        local al = math.floor(255 * math.max(0.15, math.min(1.0, cfg.coop_bars_alpha or 0.65)))
        local function col(rgb, f) return (math.floor(al * (f or 1.0)) << 24) | rgb end
        local row = 0
        local ns = {}
        for n in pairs(R.np.slots) do ns[#ns + 1] = n end
        table.sort(ns)
        for _, n in ipairs(ns) do
            local sl = R.np.slots[n]
            -- players 3, 5, 7 ... on the left, 4, 6, 8 ... on the right of player 2's bars
            local side = (n % 2 == 1) and -1 or 1
            local x = hx + hw * (cfg.coop_stamina_hud_x or 0.5) - w * 0.5 + side * (w + hw * 0.1)
            local y = hy + hh * (cfg.coop_stamina_hud_y or 0.9) - math.floor((n - 3) / 2) * hh * 0.05
            local ty = y - math.max(16.0, hh * 0.02)
            local label = "P" .. n .. "  " .. (sl.active and tostring(sl.name or "") or "(no character)") .. (sl.pad_lost and "  - controller lost" or "")
            local cards = cfg.coop_player_card ~= false and cfg.coop_skill_palette -- dev22: the card has the name and the bars
            if not cards or not sl.active or sl.pad_lost then draw.text(label, x, ty, col(sl.pad_lost and 0x5555FF or 0xD8D8D8)) end
            if sl.active and cfg.coop_skill_palette and cfg.coop_np_palette ~= false and R.palette_draw then
                -- left-side players' lists grow to the left of their bars, right-side ones to the right
                local px = (side < 0) and (x + w) or x
                pcall(R.palette_draw, sl, n, "DirectPawnControl_SkillHUD_P" .. n, px, ty - hh * 0.005, (side < 0) and 1.0 or 0.0)
            end
            if sl.active and sl.st and not cards then
                local gap = h + math.max(2.0, hh * 0.003)
                if sl.hp then
                    draw.filled_rect(x, y, w, h, col(0x000000, 0.55))
                    draw.filled_rect(x, y, w * sl.hp, h, col(0x60A878))
                    y = y + gap
                end
                draw.filled_rect(x, y, w, h, col(0x000000, 0.55))
                draw.filled_rect(x, y, w * sl.st, h, col(0x50B4D2))
            end
            row = row + 1
        end
    end)
end)

-- P2's bars in the both-pawns arrangement (classic co-op draws its own); 0.9.172: also with player 2 on the Arisen
re.on_frame(function()
    local s = R.s2
    if R.cp.on and R.cp.ar2 and R.ar2_view then s = R.ar2_view end
    if not (s.active and R.cp_pawns() and cfg.coop_stamina_bar) then return end
    if R.hud_hidden and R.hud_hidden() then return end
    if not s.st or os.clock() - (s.bars_t or 0) > 0.6 then return end
    local card = cfg.coop_player_card ~= false and cfg.coop_skill_palette
    if not card then pcall(function()
        local hx, hy, hw, hh = R.hud_rect()
        local w = hw * 0.16 * (cfg.coop_stamina_width or 1.0)
        local h = math.max(2.0, (cfg.coop_bars_thick or 4.0) * hh / 2160.0)
        local x = hx + hw * (cfg.coop_stamina_hud_x or 0.5) - w * 0.5
        local y = hy + hh * (cfg.coop_stamina_hud_y or 0.9)
        local al = math.floor(255 * math.max(0.15, math.min(1.0, cfg.coop_bars_alpha or 0.65)))
        local function col(rgb, f) return (math.floor(al * (f or 1.0)) << 24) | rgb end
        local gap = h + math.max(2.0, hh * 0.003)
        local ty = y - math.max(16.0, hh * 0.02)
        if s.hp then
            draw.filled_rect(x, y, w, h, col(0x000000, 0.55))
            draw.filled_rect(x, y, w * s.hp, h, col(0x60A878))
            y = y + gap
        end
        draw.filled_rect(x, y, w, h, col(0x000000, 0.55))
        draw.filled_rect(x, y, w * s.st, h, col(0x50B4D2))
        draw.text("P2  " .. tostring(s.name or ""), x, ty, col(0xD8D8D8))
    end) end
    -- player 2's skill list, the classic co-op palette's look and place (controller buttons only)
    if cfg.coop_skill_palette then
        pcall(function()
            local hx, hy, hw, hh = R.hud_rect()
            local wx, wy = hx + hw * (cfg.coop_palette_left or 0.60), hy + hh * (cfg.coop_palette_bottom or 0.93)
            R.palette_draw(s, 2, "DirectPawnControl_SkillHUD_P2", wx, wy, 0.0)
        end)
    end
end)
