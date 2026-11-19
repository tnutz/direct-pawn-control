-- CaptureGuide v1.2 (2026-11-19): shoot a video from a shot list, so no take is wasted and the edit can be automatic.
--
-- One file drives everything: reframework/data/capture/shots.json. For each shot the guide shows what the shot is
-- and what to do, sets the scene (commands to DirectPawnControl: heal, spawn, possess, co-op, the robot player),
-- counts down, clears the screen for the take, and afterwards asks: keep or retake. Every take is written to
-- reframework/data/capture/log.json.
--
-- So that a recording can be cut without anyone hunting for the takes, each take is bracketed by a sync mark: a
-- strip of ten squares in the top-left corner, shown for 8 frames at the start and 8 frames after the end.
--   square 1 white, square 2 magenta (start) or cyan (end), squares 3-10 = the take's serial number in binary
--   (white = 1, black = 0). tools/capture/find_marks.py reads them back out of the video files, and
--   tools/capture/cut.py cuts the kept takes and puts the captions from the shot list on them.
--
-- Keys (keyboard):
--   Ctrl+End    arm / disarm capture mode (while armed, TestGuide's own overlay and keys are off)
--   End         start the take / stop a take that has no fixed length / KEEP the take
--   Home        RETAKE (after a take), or give up a running take
--   PageDown / PageUp   next / previous shot (while a shot's card is showing)
--   Delete      during a take: put a "marked" moment on the take's timeline (a good bit to find again)
--
-- v1.2 events: during a take the guide notes what happens, with the time into the take, in the take's "events" in
-- log.json, for the capture desk's timeline and search. Kinds: kill, hit (a big hit on an enemy), hurt (a party
-- member hit hard), down, revive, climb, skill, switch (who you play), coop, cue (a shot action fired), mark.
-- Nothing is hooked: the guide reads health, skill state and flags a few times a second. Enemies that "cannot die"
-- (spawn "tough") are topped up by DirectPawnControl, so they never give a kill.
--
-- shots.json:
-- { "id": "dpc-showcase-1", "title": "Direct Pawn Control showcase",
--   "shots": [
--     { "id": "01-switch", "title": "The switch", "caption": "Now take the pawn.",
--       "brief": "What the viewer should see.", "you": "What you do during the take (omit when the robot does it all).",
--       "setup": [ {"cmd": "heal"}, {"cmd": "despawn"} ],      commands before the countdown, 0.6 s apart
--       "setup_secs": 3,                                        wait after the last setup command (default 2)
--       "secs": 10,                                             take length; omit for "until you press End"
--       "actions": [ { "at": 1.0, "cmd": {"cmd": "possess", "idx": 0} } ],   commands during the take
--       "cleanup": [ {"cmd": "despawn"} ],
--       "want": [ {"k": "skill", "what": "Launchboard"}, {"k": "kill", "n": 2}, {"k": "switch", "who": "Arisen"} ] } ],
--   "events": { "big_hit_pct": 6, "hurt_pct": 25 } }                        optional thresholds (% of max health)
-- "want" is what the shot must show: the card lists it, and after the take the review says which ones the take got
-- (an event matches when its kind is k and "who" / "what" appear in its who / what, any case; n = how many).
-- Commands are DirectPawnControl's command file (developer mode): possess, release, coop, spawn, despawn, heal,
-- quick, robot, set, down.

local VERSION = "1.2"
local DIR = "capture/"
local SHOTS_FILE, LOG_FILE = DIR .. "shots.json", DIR .. "log.json"
local VK_END, VK_HOME, VK_PGUP, VK_PGDN, VK_CTRL, VK_SHIFT, VK_DEL = 0x23, 0x24, 0x21, 0x22, 0x11, 0x10, 0x2E
local CMD_GAP = 0.6           -- DirectPawnControl reads its command file every 0.5 s
local MARK_FRAMES = 8
local WHITE, BLACK, MAGENTA, CYAN = 0xFFFFFFFF, 0xFF000000, 0xFFFF00FF, 0xFFFFFF00   -- ABGR
local C_TEXT, C_DIM, C_GO, C_WARN, C_OK = 0xFFFFFFFF, 0xFFAAAAAA, 0xFF33DDFF, 0xFF5555FF, 0xFF66DD66
local MAX_EVENTS = 600

local cg = {
    armed = false, list = nil, i = 1, st = "card",   -- card | setup | count | take | endmark | review | done
    t = 0, queue = {}, next_cmd = 0, cmd_n = 0, acts = nil,
    mark = nil, mark_left = 0, take = nil, note = nil, errors = 0,
    log = { takes = {}, next_serial = 1 }, keys = {},
}

local function err(where, e)
    cg.errors = cg.errors + 1
    cg.note = "error in " .. where .. ": " .. tostring(e)
    log.error("[CaptureGuide] " .. cg.note)
end

local function pressed(vk)
    local d = reframework:is_key_down(vk)
    local hit = d and not cg.keys[vk]
    cg.keys[vk] = d
    return hit
end

local function save_log() pcall(json.dump_file, LOG_FILE, cg.log, 1) end

local function load_files()
    local ok, l = pcall(json.load_file, SHOTS_FILE)
    if not (ok and type(l) == "table" and type(l.shots) == "table" and #l.shots > 0) then
        cg.list, cg.note = nil, "no shot list: put one at reframework/data/" .. SHOTS_FILE
        return false
    end
    cg.list = l
    local okl, lg = pcall(json.load_file, LOG_FILE)
    -- One log for every shot list: a changed or new list never starts the log over (the takes say which list
    -- they were shot for), and the serial numbers in the marks keep counting on.
    if okl and type(lg) == "table" and type(lg.takes) == "table" then
        cg.log = lg
        cg.log.next_serial = tonumber(lg.next_serial) or ((#lg.takes % 255) + 1)
    elseif not cg.log_loaded then
        cg.log = { takes = {}, next_serial = 1 }
    end -- else: the file could not be read just now; keep what is in memory instead of starting an empty log
    cg.log_loaded = true
    cg.log.list = l.id
    return true
end

-- A shot is done when it has a kept take. "Shoot again" in the capture desk sets fresh_after to the number of
-- takes in the log at that moment: only a take kept after that counts.
local function kept(shot_id)
    local after = 0
    for _, s in ipairs(cg.list and cg.list.shots or {}) do if s.id == shot_id then after = tonumber(s.fresh_after) or 0 end end
    for i, t in ipairs(cg.log.takes) do if i > after and t.shot == shot_id and t.verdict == "keep" then return true end end
    return false
end
local function takes_of(shot_id)
    local n = 0
    for _, t in ipairs(cg.log.takes) do if t.shot == shot_id then n = n + 1 end end
    return n
end
local function first_open()
    for i, s in ipairs(cg.list.shots) do if not kept(s.id) then return i end end
    return nil
end

local function queue(cmds)
    for _, c in ipairs(cmds or {}) do cg.queue[#cg.queue + 1] = c end
end
local function flush(now)
    if #cg.queue == 0 or now < cg.next_cmd then return end
    local c = table.remove(cg.queue, 1)
    local d = {}
    for k, v in pairs(c) do d[k] = v end
    cg.cmd_n = cg.cmd_n + 1
    d.id = string.format("cg-%d-%.2f", cg.cmd_n, now)
    pcall(json.dump_file, "DPC_cmd.json", d)
    cg.next_cmd = now + CMD_GAP
end

local function shot() return cg.list and cg.list.shots[cg.i] end

local function go(st, now) cg.st, cg.t = st, now end

-- ---------------------------------------------------------------- events (v1.2)
local ev = { party = {}, party_t = -1, foes = {}, foe_t = 0, coop_t = 0, coop = nil, played = nil, names = {} }

local function add_event(k, who, what, n)
    local tk = cg.take
    if not (tk and cg.st == "take") or ev.priming then return end
    tk.events = tk.events or {}
    if #tk.events >= MAX_EVENTS then return end
    local e = { t = math.floor((os.clock() - tk.t0) * 100 + 0.5) / 100, k = k }
    if who and who ~= "" then e.who = tostring(who) end
    if what and what ~= "" then e.what = tostring(what) end
    if n then e.n = n end
    tk.events[#tk.events + 1] = e
end

local function addr(o)
    local ok, a = pcall(function() return o:get_address() end)
    return ok and a or nil
end

local gui_td
local function chara_name(ch)
    local a = addr(ch)
    if a and ev.names[a] then return ev.names[a] end
    local name
    pcall(function()
        gui_td = gui_td or sdk.find_type_definition("app.GUIBase")
        local m = gui_td and gui_td:get_method("getName(app.Character)")
        local s = m and m:call(nil, ch)
        if s and tostring(s) ~= "" then name = tostring(s) end
    end)
    if not name then pcall(function() name = tostring(ch:call("get_CharaIDString")) end) end
    name = name or "?"
    if a then ev.names[a] = name end
    return name
end

local skill_names, skill_td = {}, nil
local function skill_name(id)
    if skill_names[id] then return skill_names[id] end
    local name
    pcall(function()
        gui_td = gui_td or sdk.find_type_definition("app.GUIBase")
        local m = gui_td and gui_td:get_method("getCustomSkillName(app.HumanCustomSkillID, app.HumanCustomSkillLevelNo)")
        local s = m and m:call(nil, id, 0)
        if s and tostring(s) ~= "" then name = tostring(s) end
    end)
    if not name then
        pcall(function()   -- the enum's own name, e.g. Job01_FullMoonSlash -> Full Moon Slash
            skill_td = skill_td or sdk.find_type_definition("app.HumanCustomSkillID")
            for _, f in ipairs(skill_td:get_fields()) do
                if f:is_static() and f:get_data(nil) == id then
                    name = f:get_name():gsub("^Job%d+_", ""):gsub("(%l)(%u)", "%1 %2")
                    break
                end
            end
        end)
    end
    name = name or ("skill " .. tostring(id))
    skill_names[id] = name
    return name
end

local function dbg_state()
    local d = rawget(_G, "DPC_dbg")
    return type(d) == "table" and d.state or nil
end

-- the Arisen and the party pawns, with names (refreshed once a second)
local function party(now)
    if now - ev.party_t < 1.0 then return ev.party end
    ev.party_t = now
    local out = {}
    pcall(function()
        local st = dbg_state()
        local ar = st and st.active and st.arisen_chara or nil
        if not ar then
            local cm = sdk.get_managed_singleton("app.CharacterManager")
            ar = cm and cm:call("get_ManualPlayer")
        end
        if ar then out[#out + 1] = { ch = ar, name = "Arisen" } end
        local pm = sdk.get_managed_singleton("app.PawnManager")
        local list = pm and pm:call("get_PawnCharacterList")
        local n = list and list:call("get_Count") or 0
        for i = 0, n - 1 do
            local ch = list:call("get_Item", i)
            if ch then
                local name
                pcall(function()
                    local pdc = ch:call("get_Human"):call("get_PawnDataContext")
                    name = pdc:call("get_Name")
                    if name and tostring(name):find("[\128-\255]") then
                        local nick = pdc:call("get_Nickname")
                        if nick and nick ~= "" then name = nick end
                    end
                end)
                out[#out + 1] = { ch = ch, name = (name and name ~= "") and tostring(name) or ("pawn " .. (i + 1)) }
            end
        end
    end)
    -- keep each member's last readings across the refresh
    local old = {}
    for _, m in ipairs(ev.party) do if m.a then old[m.a] = m end end
    for _, m in ipairs(out) do
        m.a = addr(m.ch)
        local o = m.a and old[m.a]
        if o then m.hp, m.dead, m.climb, m.skill = o.hp, o.dead, o.climb, o.skill end
    end
    ev.party = out
    return out
end

-- who is being played: "you", "player 2" or nil (shown with the name in skill events)
local function role(m)
    local st = dbg_state()
    local played = st and st.active and st.pawn_chara and addr(st.pawn_chara)
    local co = ev.coop and ev.coop.active == true
    if played and m.a == played then return co and "player 2" or "you" end
    if m.name == "Arisen" and (co or not played) then return "you" end
    return nil
end

local function read_hp(ch)
    local hp, mx
    pcall(function()
        local hit = ch:call("get_Hit")
        hp = hit:call("get_Hp")
        mx = hit:call("get_ReducedMaxHp")
        if type(mx) ~= "number" or mx <= 0 then mx = hit:call("get_OriginalMaxHp") end
    end)
    return hp, mx
end

local function watch_party(now)
    local pct = tonumber(cg.list and cg.list.events and cg.list.events.hurt_pct) or 25
    for _, m in ipairs(party(now)) do
        local ch = m.ch
        -- skills: the skill a character is in right now (0 = none); a new value is a skill being used
        local okk, sk = pcall(function() return ch:call("get_Human"):call("get_CustomSkillState") end)
        if okk and type(sk) == "number" then
            if sk ~= 0 and sk ~= m.skill then
                local r = role(m)
                add_event("skill", m.name .. (r and (" (" .. r .. ")") or ""), skill_name(sk))
            end
            m.skill = sk
        end
        local okd, dead = pcall(ch.call, ch, "get_IsDead")
        if okd and type(dead) == "boolean" then
            if m.dead ~= nil and dead ~= m.dead then add_event(dead and "down" or "revive", m.name) end
            m.dead = dead
        end
        local okc, cl = pcall(ch.call, ch, "get_IsClimbOnCharacter")
        if okc and type(cl) == "boolean" then
            if cl and m.climb == false then add_event("climb", m.name) end
            m.climb = cl
        end
        local hp, mx = read_hp(ch)
        if hp and mx and mx > 0 then
            if m.hp and m.hp - hp >= mx * pct / 100 then
                add_event("hurt", m.name, nil, math.floor((m.hp - hp) / mx * 100 + 0.5))
            end
            m.hp = hp
        end
    end
end

local function watch_foes(now)
    if now - ev.foe_t < 0.1 then return end
    ev.foe_t = now
    local pct = tonumber(cg.list and cg.list.events and cg.list.events.big_hit_pct) or 6
    local cx, cz
    for _, m in ipairs(ev.party) do
        if m.name == "Arisen" then
            pcall(function() local p = m.ch:call("get_GameObject"):call("get_Transform"):call("get_Position"); cx, cz = p.x, p.z end)
        end
    end
    local seen = {}
    pcall(function()
        local em = sdk.get_managed_singleton("app.EnemyManager")
        local arr = em and em:call("getAllEnemies")
        local n = arr and arr:call("get_Count") or 0
        for i = 0, n - 1 do
            local ok, ch = pcall(function() return arr[i]:get_field("_Chara") end)
            local a = ok and ch and addr(ch)
            if a then
                local near = true
                if cx then
                    pcall(function()
                        local p = ch:call("get_GameObject"):call("get_Transform"):call("get_Position")
                        near = (p.x - cx) ^ 2 + (p.z - cz) ^ 2 < 70 * 70
                    end)
                end
                if near then
                    seen[a] = true
                    local f = ev.foes[a]
                    if not f then f = {}; ev.foes[a] = f end
                    local okd, dead = pcall(ch.call, ch, "get_IsDead")
                    dead = okd and dead == true
                    local hp, mx = read_hp(ch)
                    if f.dead == false and dead then add_event("kill", nil, chara_name(ch)) end
                    if not dead and hp and mx and mx > 0 and f.hp and f.hp - hp >= mx * pct / 100 then
                        add_event("hit", nil, chara_name(ch), math.floor((f.hp - hp) / mx * 100 + 0.5))
                    end
                    f.dead, f.hp = dead, hp
                end
            end
        end
    end)
    for a in pairs(ev.foes) do if not seen[a] then ev.foes[a] = nil end end
end

local function watch_dpc(now)
    local st = dbg_state()
    if now - ev.coop_t >= 0.5 then
        ev.coop_t = now
        local ok, c = pcall(json.load_file, "DPC_coop.json")
        local was = ev.coop and ev.coop.active == true
        if ok and type(c) == "table" then
            ev.coop = c
            if (c.active == true) ~= was then
                add_event("coop", nil, c.active and ("on, player 2 plays " .. tostring(c.pawn_name or "?")) or "off")
            end
        end
    end
    if not st then return end
    local played = st.active and tostring(st.pawn_name or "?") or "Arisen"
    if ev.played and played ~= ev.played then
        local co = ev.coop and ev.coop.active == true
        if co and played ~= "Arisen" then add_event("switch", "player 2", played)
        else add_event("switch", "you", played) end
    end
    ev.played = played
end

local function watch(now)
    watch_dpc(now)
    watch_party(now)
    watch_foes(now)
end

-- prime the readings, so a take starts from what is already true (not "everyone just stopped being down")
local function watch_reset(now)
    ev.foes, ev.party_t, ev.coop_t, ev.coop = {}, -1, 0, nil
    ev.played = nil
    for _, m in ipairs(party(now)) do m.hp, m.dead, m.climb, m.skill = nil, nil, nil, nil end
end

-- how many of the shot's wanted events a take got: list of { want, got, need }
local function lower(x) return string.lower(tostring(x or "")) end
local function want_check(s, tk)
    local out = {}
    for _, w in ipairs(type(s.want) == "table" and s.want or {}) do
        if type(w) == "table" and w.k then
            local got = 0
            for _, e in ipairs(tk and tk.events or {}) do
                if e.k == w.k and (not w.who or lower(e.who):find(lower(w.who), 1, true))
                   and (not w.what or lower(e.what):find(lower(w.what), 1, true)) then got = got + 1 end
            end
            out[#out + 1] = { w = w, got = got, need = math.max(1, tonumber(w.n) or 1) }
        end
    end
    return out
end
local KIND_WORD = { kill = "kill", hit = "big hit", hurt = "party member hit hard", down = "someone down",
                    revive = "revive", climb = "climb", skill = "skill", switch = "switch", coop = "co-op",
                    cue = "cue", mark = "marked moment" }
local function want_text(w)
    local s = KIND_WORD[w.k] or tostring(w.k)
    if w.what then s = s .. ": " .. tostring(w.what) end
    if w.who then s = s .. " by " .. tostring(w.who) end
    if (tonumber(w.n) or 1) > 1 then s = s .. " x" .. tostring(w.n) end
    return s
end

local function begin_take(now)
    local s = shot()
    local serial = cg.log.next_serial
    cg.log.next_serial = (serial % 255) + 1
    cg.take = { serial = serial, shot = s.id, list = cg.list.id, take = takes_of(s.id) + 1, t0 = now, wall0 = os.date("%Y-%m-%d %H:%M:%S"),
                verdict = "pending", secs = tonumber(s.secs), events = {} }
    cg.log.takes[#cg.log.takes + 1] = cg.take
    save_log()
    cg.acts = {}
    for _, a in ipairs(s.actions or {}) do
        if type(a) == "table" and type(a.cmd) == "table" then cg.acts[#cg.acts + 1] = { at = tonumber(a.at) or 0, cmd = a.cmd } end
    end
    table.sort(cg.acts, function(a, b) return a.at < b.at end)
    cg.mark, cg.mark_left = "start", MARK_FRAMES
    go("take", now)
    watch_reset(now)
    ev.priming = true
    ev.foe_t = 0
    pcall(watch, now)   -- first readings only: nothing is recorded as a change on the first look
    ev.priming = false
end

local function end_take(now, verdict)
    local s = shot()
    cg.take.t1 = now
    cg.take.len = math.floor((now - cg.take.t0) * 100 + 0.5) / 100
    if verdict then cg.take.verdict = verdict end
    cg.take.t0 = nil   -- clock values mean nothing in the file; events carry times from the take's start
    cg.take.t1 = nil
    save_log()
    cg.queue = {}
    queue({ { cmd = "robot", who = "all", stop = true } })
    queue(s.cleanup)
    cg.mark, cg.mark_left = "end", MARK_FRAMES
    go("endmark", now)
end

local function tick(now)
    local ctrl, shift = reframework:is_key_down(VK_CTRL), reframework:is_key_down(VK_SHIFT)
    local k_end, k_home, k_up, k_dn = pressed(VK_END), pressed(VK_HOME), pressed(VK_PGUP), pressed(VK_PGDN)
    if k_end and ctrl then
        if cg.armed and (cg.st == "take") then end_take(now, "retake") end
        cg.armed = not cg.armed
        _G.CAPTURE_GUIDE_ACTIVE = cg.armed or nil
        if cg.armed then
            cg.note = nil
            if load_files() then
                -- "Shoot this next" in the capture desk: capture/next.json names one shot to open on, once
                local okn, nx = pcall(json.load_file, DIR .. "next.json")
                local want
                if okn and type(nx) == "table" and type(nx.shot) == "string" then
                    for i, s in ipairs(cg.list.shots) do if s.id == nx.shot then want = i end end
                    pcall(json.dump_file, DIR .. "next.json", { used = nx.shot })
                end
                cg.i = want or first_open() or 1
                go((want or first_open()) and "card" or "done", now)
            end
        else
            cg.queue = {}
            pcall(json.dump_file, "DPC_cmd.json", { id = "cg-stop-" .. now, cmd = "robot", who = "all", stop = true })
        end
        return
    end
    if not cg.armed or not cg.list then return end
    flush(now)
    local s = shot()
    if cg.st == "card" then
        if k_dn and cg.i < #cg.list.shots then cg.i = cg.i + 1
        elseif k_up and cg.i > 1 then cg.i = cg.i - 1
        elseif k_end and not shift then
            cg.queue = {}
            queue(s.setup)
            go("setup", now)
        end
    elseif cg.st == "setup" then
        if #cg.queue == 0 and now - cg.t >= (tonumber(s.setup_secs) or 2.0) and now >= cg.next_cmd then go("count", now) end
        if k_home then cg.queue = {}; go("card", now) end
    elseif cg.st == "count" then
        if k_home then go("card", now)
        elseif now - cg.t >= 3.0 then begin_take(now) end
    elseif cg.st == "take" then
        local el = now - cg.take.t0
        while cg.acts[1] and el >= cg.acts[1].at do
            local c = table.remove(cg.acts, 1).cmd
            queue({ c })
            local what = tostring(c.cmd or "?")
            if c.cmd == "robot" then what = "robot " .. (c.stop and "stop" or c.fight and "fight" or c.antics and "antics" or tostring(c.who or ""))
            elseif c.cmd == "spawn" then what = "spawn x" .. tostring(c.count or 1) end
            add_event("cue", nil, what)
        end
        local okw, ew = pcall(watch, now)
        if not okw then err("events", ew) end
        if pressed(VK_DEL) then add_event("mark", nil, "marked") end
        if k_home then end_take(now, "retake")
        elseif s.secs and el >= tonumber(s.secs) then end_take(now)
        elseif k_end and el > 0.5 then end_take(now) end
    elseif cg.st == "endmark" then
        if cg.mark_left <= 0 then
            if cg.take.verdict == "retake" then go("card", now) else go("review", now) end
        end
    elseif cg.st == "review" then
        if k_end then
            cg.take.verdict = "keep"; save_log()
            local nxt = first_open()
            if nxt then cg.i = nxt; go("card", now) else go("done", now) end
        elseif k_home then
            cg.take.verdict = "retake"; save_log()
            go("card", now)
        end
    elseif cg.st == "done" then
        if k_up then cg.i = #cg.list.shots; go("card", now) end
    end
end

-- the sync mark: ten squares in the top-left corner, each 1/45 of the screen height
local function draw_mark()
    if not cg.mark or cg.mark_left <= 0 or not cg.take then return end
    cg.mark_left = cg.mark_left - 1
    if cg.mark == "start" and cg.mark_left == 0 and cg.take.t0 then
        -- the frame of the last start square: the capture desk counts a take's time from just after it
        cg.take.mark_t = math.floor((os.clock() - cg.take.t0) * 1000 + 0.5) / 1000
    end
    local d = imgui.get_display_size()
    local c = math.max(8, math.floor(((d and d.y) or 1080) / 45 + 0.5))
    draw.filled_rect(0, 0, c * 10, c, BLACK)
    draw.filled_rect(0, 0, c, c, WHITE)
    draw.filled_rect(c, 0, c, c, cg.mark == "start" and MAGENTA or CYAN)
    for b = 0, 7 do
        if ((cg.take.serial >> (7 - b)) & 1) == 1 then draw.filled_rect(c * (2 + b), 0, c, c, WHITE) end
    end
end

local font_big, font_mid
local function text(f, col, s)
    local pushed = f and pcall(imgui.push_font, f)
    imgui.text_colored(s, col)
    if pushed then pcall(imgui.pop_font) end
end

local function draw_card(now)
    if cg.st == "take" or cg.st == "endmark" then return end   -- nothing on screen during a take
    if not font_big then pcall(function() font_big = imgui.load_font(nil, 34); font_mid = imgui.load_font(nil, 22) end) end
    local d = imgui.get_display_size()
    imgui.set_next_window_pos(Vector2f.new(((d and d.x) or 1920) * 0.5 - 420, 80), 1 << 3) -- ImGuiCond_Appearing
    pcall(imgui.set_next_window_bg_alpha, 0.82)
    imgui.begin_window("Capture##CaptureGuide", nil, (1 << 6) | (1 << 0))
    if not cg.list then
        text(font_mid, C_WARN, tostring(cg.note or "no shot list"))
        text(nil, C_DIM, "Ctrl+End leaves capture mode")
        imgui.end_window()
        return
    end
    local s = shot()
    text(nil, C_DIM, string.format("CAPTURE: %s   (CaptureGuide v%s)   Ctrl+End leaves capture mode", tostring(cg.list.title or cg.list.id), VERSION))
    if cg.st == "done" then
        text(font_big, C_GO, "Every shot has a kept take.")
        text(font_mid, C_TEXT, "Stop the recording. The log is in reframework/data/" .. LOG_FILE)
        text(nil, C_DIM, "PageUp goes back to the shots, to redo one")
    else
        local done = 0
        for _, x in ipairs(cg.list.shots) do if kept(x.id) then done = done + 1 end end
        text(font_mid, C_DIM, string.format("Shot %d of %d   (%d kept)   %s%s", cg.i, #cg.list.shots, done,
            kept(s.id) and "this one has a kept take" or ("takes so far: " .. takes_of(s.id)), ""))
        text(font_big, C_TEXT, tostring(s.title or s.id))
        if s.brief then text(font_mid, C_TEXT, tostring(s.brief)) end
        text(font_mid, s.you and C_GO or C_DIM, s.you and ("YOU: " .. tostring(s.you)) or "Hands off: the robot plays this one.")
        text(font_mid, C_DIM, s.secs and string.format("Length: %d s", math.floor(tonumber(s.secs))) or "Length: until you press End")
        local wants = want_check(s, cg.st == "review" and cg.take or nil)
        if #wants > 0 then
            if cg.st == "review" then
                local miss = 0
                for _, c in ipairs(wants) do if c.got < c.need then miss = miss + 1 end end
                text(font_mid, miss == 0 and C_OK or C_WARN, miss == 0 and "This take has everything the shot needs:"
                    or string.format("This take is missing %d of %d:", miss, #wants))
                for _, c in ipairs(wants) do
                    text(font_mid, c.got >= c.need and C_OK or C_WARN, string.format("  %s  %s  (%d)", c.got >= c.need and "[x]" or "[ ]", want_text(c.w), c.got))
                end
            else
                text(font_mid, C_TEXT, "Must show:")
                for _, c in ipairs(wants) do text(font_mid, C_TEXT, "  - " .. want_text(c.w)) end
            end
        end
        imgui.spacing()
        if cg.st == "card" then
            text(font_big, C_GO, "Press END to shoot it")
            text(nil, C_DIM, "PageDown / PageUp: another shot")
        elseif cg.st == "setup" then
            text(font_big, C_GO, "Setting the scene...")
            text(nil, C_DIM, "Home cancels")
        elseif cg.st == "count" then
            text(font_big, C_GO, string.format("Rolling in %d", math.max(1, math.ceil(3.0 - (now - cg.t)))))
            text(nil, C_DIM, "The screen clears for the take. Home cancels. Delete during the take marks a moment")
        elseif cg.st == "review" then
            text(font_big, C_GO, string.format("Take %d: %.1f s", cg.take.take, cg.take.len or 0))
            local cnt, order = {}, {}
            for _, e in ipairs(cg.take.events or {}) do
                if not cnt[e.k] then cnt[e.k] = 0; order[#order + 1] = e.k end
                cnt[e.k] = cnt[e.k] + 1
            end
            local parts = {}
            for _, k in ipairs(order) do parts[#parts + 1] = string.format("%d %s", cnt[k], k) end
            text(nil, C_DIM, #parts > 0 and ("Events: " .. table.concat(parts, ", ")) or "No events noted in this take")
            text(font_big, C_TEXT, "END = keep it      HOME = shoot it again")
        end
    end
    if cg.note then text(nil, C_WARN, cg.note) end
    imgui.end_window()
end

re.on_frame(function()
    local now = os.clock()
    local ok, e = pcall(tick, now)
    if not ok then err("tick", e) end
    if not cg.armed then return end
    local okm, em = pcall(draw_mark)
    if not okm then err("mark", em) end
    local okd, ed = pcall(draw_card, now)
    if not okd then err("card", ed) end
end)

re.on_script_reset(function() _G.CAPTURE_GUIDE_ACTIVE = nil end)

log.info("[CaptureGuide] v" .. VERSION .. " loaded: Ctrl+End arms capture mode (shot list: reframework/data/" .. SHOTS_FILE .. ")")
