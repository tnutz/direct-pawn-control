-- CaptureGuide v1.0 (2026-11-18): shoot a video from a shot list, so no take is wasted and the edit can be automatic.
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
--       "cleanup": [ {"cmd": "despawn"} ] } ] }
-- Commands are DirectPawnControl's command file (developer mode): possess, release, coop, spawn, despawn, heal,
-- quick, robot, set, down.

local VERSION = "1.1"
local DIR = "capture/"
local SHOTS_FILE, LOG_FILE = DIR .. "shots.json", DIR .. "log.json"
local VK_END, VK_HOME, VK_PGUP, VK_PGDN, VK_CTRL, VK_SHIFT = 0x23, 0x24, 0x21, 0x22, 0x11, 0x10
local CMD_GAP = 0.6           -- DirectPawnControl reads its command file every 0.5 s
local MARK_FRAMES = 8
local WHITE, BLACK, MAGENTA, CYAN = 0xFFFFFFFF, 0xFF000000, 0xFFFF00FF, 0xFFFFFF00   -- ABGR
local C_TEXT, C_DIM, C_GO, C_WARN = 0xFFFFFFFF, 0xFFAAAAAA, 0xFF33DDFF, 0xFF5555FF

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

local function begin_take(now)
    local s = shot()
    local serial = cg.log.next_serial
    cg.log.next_serial = (serial % 255) + 1
    cg.take = { serial = serial, shot = s.id, list = cg.list.id, take = takes_of(s.id) + 1, t0 = now, wall0 = os.date("%Y-%m-%d %H:%M:%S"),
                verdict = "pending", secs = tonumber(s.secs) }
    cg.log.takes[#cg.log.takes + 1] = cg.take
    save_log()
    cg.acts = {}
    for _, a in ipairs(s.actions or {}) do
        if type(a) == "table" and type(a.cmd) == "table" then cg.acts[#cg.acts + 1] = { at = tonumber(a.at) or 0, cmd = a.cmd } end
    end
    table.sort(cg.acts, function(a, b) return a.at < b.at end)
    cg.mark, cg.mark_left = "start", MARK_FRAMES
    go("take", now)
end

local function end_take(now, verdict)
    local s = shot()
    cg.take.t1 = now
    cg.take.len = math.floor((now - cg.take.t0) * 100 + 0.5) / 100
    if verdict then cg.take.verdict = verdict end
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
        while cg.acts[1] and el >= cg.acts[1].at do queue({ table.remove(cg.acts, 1).cmd }) end
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
        imgui.spacing()
        if cg.st == "card" then
            text(font_big, C_GO, "Press END to shoot it")
            text(nil, C_DIM, "PageDown / PageUp: another shot")
        elseif cg.st == "setup" then
            text(font_big, C_GO, "Setting the scene...")
            text(nil, C_DIM, "Home cancels")
        elseif cg.st == "count" then
            text(font_big, C_GO, string.format("Rolling in %d", math.max(1, math.ceil(3.0 - (now - cg.t)))))
            text(nil, C_DIM, "The screen clears for the take. Home cancels")
        elseif cg.st == "review" then
            text(font_big, C_GO, string.format("Take %d: %.1f s", cg.take.take, cg.take.len or 0))
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
