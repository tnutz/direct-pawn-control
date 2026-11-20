-- TestGuide v1.0 (2026-11-11): on-screen test runner for live mod tests.
--
-- Claude (or anyone) drops a plan into reframework/data/test_guide/plan.json. TestGuide shows it on screen,
-- waits until the player presses the ready trigger, then walks through the steps with a big countdown.
-- Each step can send commands to DirectPawnControl (data/DPC_cmd.json), and the plan can record probes
-- (Lua expressions) at a fixed rate into a result file. Progress goes to test_guide/status.json.
--
-- Controls:  End (keyboard) or L3+R3 (controller) = ready / start.   Shift+End = abort or dismiss.
--
-- Plan format (JSON):
-- {
--   "id": "walk2",                         unique per plan; a finished id is never run again
--   "title": "Arisen walking speed",
--   "intro": "Start co-op first (Ctrl+F6).",  shown while waiting for ready
--   "steps": [
--     { "text": "Hold W", "secs": 5, "cmds": [ {"cmd": "set", "key": "coop_arisen_kb_stick", "value": true} ] },
--     { "text": "Let go of W, push the controller's left stick", "secs": 5 },
--     { "text": "Untick X in the menu, then press End", "wait": true }   (v1.3: no timer; End / L3+R3 moves on)
--     { "text": "...", "secs": 4, "each_frame": "lua chunk" }   (v1.4: run every frame of the step, before the game's
--                                   LateUpdate, with the probe env (H, and globals that persist across steps/probes))
--   ],
-- Queue (v1.5): plans in reframework/data/test_guide/queue/*.json run in file-name order after plan.json,
-- each once (by id). The waiting overlay shows which one is up; Shift+End skips it.
--   "record": { "hz": 10, "out": "test_guide/result_walk2.json", "show": ["speed"],   (v1.1: live values on screen)
--               "at": "frame"   (v1.2: sample in re.on_frame, after the camera's lateUpdate; needed for
--                                draw.world_to_screen and the final camera pose. Default: LateUpdateBehavior.)
--               "probes": { "speed": "return H.speed()", "mag": "return H.ar_input():call('get_AxisMagnitudeL')" } }
-- }
-- Probes are Lua chunks run with the helpers table H (see below) plus sdk/json/re/reframework/math/string.
--
-- v2.0 additions
--   "requires": { "DirectPawnControl": "0.9.6", "CameraDistance": "2.8.1" }
--       The test will not start until those mods report at least these versions (see Dev HUD below).
--   step "expect": [ { "probe": "v", "agg": "avg", "op": ">", "value": 4.0, "label": "Arisen runs" } ]
--       Checked when the step ends, over that step's recorded samples of the probe.
--       agg: avg | min | max | last | any | all | frac (share of samples that are true)      (default avg; any for booleans)
--       op:  > >= < <= == ~= contains                                                       (default ==, value true)
--       Verdicts are shown on screen (PASS / FAIL), and written to status.json and the result file.
--   Dev HUD: every mod of ours writes reframework/data/dev_status/<Mod>.json once a second
--       { mod, version, t = os.clock(), errors, last_error, last_error_t, save_ok, info }.
--       The HUD lists them: version, a red line for a recent error or failed save, grey if the mod stopped reporting.
--       Shift+Home hides or shows it.
--   Flight recorder: the last 30 s of key state at 10 Hz, kept all the time. Home (or Create/Share + L3 on the pad)
--       saves it to test_guide/flight_<n>.json. For "that looked wrong" moments outside a test.
--
-- v2.4 unattended runs (the test bench, tools/capture/bench.py): while test_guide/auto.json says
--   { "on": true, "until": <os.time()>, "run": "<id>" } (the bench renews it), a waiting plan starts by itself once
--   its requirements are met and the Arisen has been in the world for 3 s; a "wait" step moves on after its
--   "auto_secs" (default 3); a finished plan clears after 3 s. status.json also carries wall = os.time() and auto.
--   Plans written for the bench should not need a person (no "wait" steps that need a real action).
--
-- Each recorded row gets t (seconds since start), step (1-based) and every probe value (errors -> "ERR: ...").

local VERSION = "2.4.1"
local DIR = "test_guide/"
local PLAN_FILE, STATUS_FILE = DIR .. "plan.json", DIR .. "status.json"
local KEY_READY, KEY_SHIFT = 0x23, 0x10           -- End, Shift
local KEY_FLIGHT = 0x24                           -- Home
local PAD_FLIGHT = 0x4000 | 0x1000                -- CLeft (Create/Share) + LStickPush
local DEV_DIR = "dev_status/"
local CONFIG_FILE = DIR .. "config.json"
local tg_cfg = { hud = true, recorder = true }
local PAD_READY = 0x1000 | 0x2000                 -- LStickPush + RStickPush
local CMD_GAP = 0.6                               -- DPC reads its command file every 0.5 s

local gs = {
    plan = nil, state = "idle",                   -- idle | waiting | countdown | running | done | aborted
    t0 = 0, step = 0, step_t0 = 0, rows = {}, last_sample = -1, next_poll = 0,
    cmd_queue = {}, next_cmd_t = 0, cmd_n = 0, probes = nil, msg = nil, finished = {},
    key_prev = false, pad_prev = false, done_t = 0,
    verdicts = {}, dev = {}, dev_next = 0, unmet = nil,
    flight = {}, flight_last = -1, flight_n = 0, toast = nil, toast_until = 0, fkey_prev = false, fpad_prev = false,
    my_errors = 0, my_last_error = nil, my_last_error_t = nil,
}
local function tg_error(where, err)
    gs.my_errors = gs.my_errors + 1
    gs.my_last_error, gs.my_last_error_t = where .. ": " .. tostring(err), os.clock()
    gs.msg = "error: " .. gs.my_last_error
end

-- ---------------------------------------------------------------------------
-- Helpers available to probes as H
-- ---------------------------------------------------------------------------
local H = {}
local gp_s, gp_td
function H.pad()
    gp_s = gp_s or sdk.get_native_singleton("via.hid.GamePad")
    gp_td = gp_td or sdk.find_type_definition("via.hid.GamePad")
    if not (gp_s and gp_td) then return nil end
    local ok, d = pcall(sdk.call_native_func, gp_s, gp_td, "get_MergedDevice")
    return ok and d or nil
end
function H.pad_buttons() local d = H.pad(); return d and d:call("get_Button") or 0 end
function H.v2(v) if v == nil then return nil end local ok, s = pcall(function() return string.format("%.2f,%.2f", v.x, v.y) end); return ok and s or tostring(v) end
function H.v3(v) if v == nil then return nil end local ok, s = pcall(function() return string.format("%.2f,%.2f,%.2f", v.x, v.y, v.z) end); return ok and s or tostring(v) end
function H.arisen() local cm = sdk.get_managed_singleton("app.CharacterManager"); return cm and cm:call("get_ManualPlayer") end
function H.ar_input() local a = H.arisen(); return a and a:call("get_Input") end
function H.pawn(i)
    local pm = sdk.get_managed_singleton("app.PawnManager")
    local l = pm and pm:call("get_PawnCharacterList")
    if not l or (i or 0) >= l:call("get_Count") then return nil end
    return l[i or 0]
end
function H.node(chara, layer)
    if not chara then return nil end
    return chara:call("get_ActionManager"):get_field("Fsm"):call("getCurrentNodeName(System.UInt32)", layer or 0)
end
function H.key(vk) return reframework:is_key_down(vk) end
local speed_state = {}
-- horizontal speed (m/s) of a character between two calls with the same tag (default: the Arisen)
function H.speed(chara, tag)
    chara = chara or H.arisen()
    if not chara then return nil end
    tag = tag or "arisen"
    local p = chara:call("get_Transform"):call("get_Position")
    local now = os.clock()
    local s = speed_state[tag]
    speed_state[tag] = { x = p.x, z = p.z, t = now }
    if not s or now - s.t <= 0 then return nil end
    local dx, dz = p.x - s.x, p.z - s.z
    return math.floor(math.sqrt(dx * dx + dz * dz) / (now - s.t) * 100 + 0.5) / 100
end
function H.dpc_brain() local ok, d = pcall(json.load_file, "DPC_arisen_brain.json"); return ok and d or nil end

-- ---------------------------------------------------------------------------
local function write_status()
    local p = gs.plan
    pcall(json.dump_file, STATUS_FILE, {
        version = VERSION, state = gs.state, id = p and p.id, title = p and p.title,
        step = gs.step, steps = p and p.steps and #p.steps or 0,
        elapsed = (gs.state == "running") and (os.clock() - gs.t0) or nil,
        rows = #gs.rows, msg = gs.msg, finished = gs.finished, t = os.clock(),
        verdicts = gs.verdicts, unmet = gs.unmet, queue_file = gs.queue_file,
        wall = os.time(), auto = gs.auto and gs.auto_run or nil, -- v2.4
    })
end

-- ---------------------------------------------------------------------------
-- v2.0: versions / requires / expectations
-- ---------------------------------------------------------------------------
local function ver_tuple(v)
    local t = {}
    for n in tostring(v or ""):gmatch("%d+") do t[#t + 1] = tonumber(n) end
    return t
end
local function ver_at_least(have, need)
    local a, b = ver_tuple(have), ver_tuple(need)
    for i = 1, math.max(#a, #b) do
        local x, y = a[i] or 0, b[i] or 0
        if x ~= y then return x > y end
    end
    return true
end

local function read_dev_status(now)
    if now < gs.dev_next then return end
    gs.dev_next = now + 1.0
    local dev = {}
    if fs and fs.glob then
        local okg, files = pcall(fs.glob, [[dev_status\\.*\.json]])
        if okg and type(files) == "table" then
            for _, f in ipairs(files) do
                local ok, d = pcall(json.load_file, f)
                if ok and type(d) == "table" and type(d.mod) == "string" then dev[d.mod] = d end
            end
        end
    end
    gs.dev = dev
    -- our own entry (also proves the folder is writable)
    pcall(json.dump_file, DEV_DIR .. "TestGuide.json", {
        mod = "TestGuide", version = VERSION, t = now, errors = gs.my_errors,
        last_error = gs.my_last_error, last_error_t = gs.my_last_error_t,
        info = gs.plan and (tostring(gs.plan.id) .. " " .. gs.state) or "idle",
    })
end

local function check_requires(p)
    if type(p.requires) ~= "table" then return nil end
    local unmet = {}
    for mod, need in pairs(p.requires) do
        local d = gs.dev[mod]
        local alive = d and type(d.t) == "number" and (os.clock() - d.t) < 5.0
        if not alive then
            unmet[#unmet + 1] = string.format("%s %s needed: not running (or older than its Dev HUD support)", mod, tostring(need))
        elseif not ver_at_least(d.version, need) then
            unmet[#unmet + 1] = string.format("%s %s needed, %s loaded: Reset Scripts", mod, tostring(need), tostring(d.version))
        end
    end
    table.sort(unmet)
    return #unmet > 0 and unmet or nil
end

local OPS = {
    [">"] = function(a, b) return a > b end, [">="] = function(a, b) return a >= b end,
    ["<"] = function(a, b) return a < b end, ["<="] = function(a, b) return a <= b end,
    ["=="] = function(a, b) return a == b end, ["~="] = function(a, b) return a ~= b end,
    contains = function(a, b) return type(a) == "string" and a:find(tostring(b), 1, true) ~= nil end,
}
local function truthy(v) return v == true or (type(v) == "number" and v ~= 0) end

local function eval_expect(e, step_i)
    local vals = {}
    for _, r in ipairs(gs.rows) do
        if r.step == step_i and r[e.probe] ~= nil then vals[#vals + 1] = r[e.probe] end
    end
    local label = e.label or (tostring(e.probe) .. " " .. tostring(e.op or "==") .. " " .. tostring(e.value))
    if #vals == 0 then return { step = step_i, label = label, pass = false, got = "no samples" } end
    local op = OPS[e.op or "=="] or OPS["=="]
    local want = e.value; if want == nil then want = true end
    local agg = e.agg or ((type(vals[1]) == "boolean" or type(want) == "boolean" or e.op == "contains") and "any" or "avg")
    local got, pass
    if agg == "any" or agg == "all" or agg == "frac" then
        local hits = 0
        for _, v in ipairs(vals) do
            local ok, r = pcall(op, v, want)
            if ok and r then hits = hits + 1 end
        end
        if agg == "frac" then
            got = hits / #vals
            pass = got >= (tonumber(e.min_frac) or 0.9)
        else
            got = string.format("%d of %d", hits, #vals)
            pass = (agg == "any" and hits > 0) or (agg == "all" and hits == #vals)
        end
    else
        local nums = {}
        for _, v in ipairs(vals) do
            if type(v) == "number" then nums[#nums + 1] = v elseif type(v) == "boolean" then nums[#nums + 1] = v and 1 or 0 end
        end
        if #nums == 0 then return { step = step_i, label = label, pass = false, got = "no numeric samples" } end
        if agg == "min" then got = math.huge; for _, v in ipairs(nums) do got = math.min(got, v) end
        elseif agg == "max" then got = -math.huge; for _, v in ipairs(nums) do got = math.max(got, v) end
        elseif agg == "last" then got = nums[#nums]
        else got = 0; for _, v in ipairs(nums) do got = got + v end; got = got / #nums end
        local ok, r = pcall(op, got, want)
        pass = ok and r == true
        got = math.floor(got * 100 + 0.5) / 100
    end
    return { step = step_i, label = label, pass = pass, got = got, agg = agg, op = e.op or "==", value = want }
end

local function eval_step(step_i)
    local st = gs.plan and gs.plan.steps[step_i]
    if not st or type(st.expect) ~= "table" then return end
    for _, e in ipairs(st.expect) do
        local ok, v = pcall(eval_expect, e, step_i)
        gs.verdicts[#gs.verdicts + 1] = ok and v or { step = step_i, label = tostring(e.label or e.probe), pass = false, got = "check error: " .. tostring(v) }
    end
end

local function compile_probes(rec)
    gs.env_shared = setmetatable({ H = H }, { __index = _G })
    local env = gs.env_shared
    local list = {}
    for name, code in pairs(rec.probes or {}) do
        local fn, err = load(code, "=probe:" .. name, "t", env)
        list[#list + 1] = { name = name, fn = fn, err = err }
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

local function queue_cmds(cmds)
    for _, c in ipairs(cmds or {}) do gs.cmd_queue[#gs.cmd_queue + 1] = c end
end

local function flush_cmds(now)
    if #gs.cmd_queue == 0 or now < gs.next_cmd_t then return end
    local c = table.remove(gs.cmd_queue, 1)
    local d = {}
    for k, v in pairs(c) do d[k] = v end
    gs.cmd_n = gs.cmd_n + 1
    d.id = string.format("tg-%s-%d-%.2f", tostring(gs.plan and gs.plan.id), gs.cmd_n, now)
    pcall(json.dump_file, "DPC_cmd.json", d)
    gs.next_cmd_t = now + CMD_GAP
end

local function save_results(final_state)
    local p = gs.plan
    if p and p.record and p.record.out then
        pcall(json.dump_file, p.record.out, { id = p.id, state = final_state, verdicts = gs.verdicts, versions = (function()
            local v = {}; for mod, d in pairs(gs.dev) do v[mod] = d.version end; return v end)(), rows = gs.rows })
    end
end

local function finish(state, msg)
    gs.state, gs.msg, gs.done_t = state, msg, os.clock()
    save_results(state)
    if gs.plan and gs.plan.id then gs.finished[#gs.finished + 1] = gs.plan.id end
    if #gs.finished > 300 then table.remove(gs.finished, 1) end -- 2.1: was 20, so old queue files ran again
    write_status()
end

local function load_plan(p)
    if type(p) ~= "table" or type(p.id) ~= "string" or type(p.steps) ~= "table" or #p.steps == 0 then return end
    for _, id in ipairs(gs.finished) do if id == p.id then return end end
    if gs.plan and gs.plan.id == p.id then return end
    gs.plan, gs.state, gs.step, gs.rows, gs.msg = p, "waiting", 0, {}, nil
    gs.verdicts, gs.unmet = {}, nil
    gs.env_shared = nil
    gs.probes = p.record and compile_probes(p.record) or nil
    gs.env = gs.env_shared or setmetatable({ H = H }, { __index = _G })
    for i, st in ipairs(p.steps) do
        if type(st.each_frame) == "string" then
            local fn, err = load(st.each_frame, "=step" .. i, "t", gs.env)
            st._fn, st._err = fn, err
        end
    end
    gs.cmd_queue = {}
    for tag in pairs(speed_state) do speed_state[tag] = nil end
    queue_cmds(p.setup_cmds)
    write_status()
end

local function start_step(i, now)
    gs.step, gs.step_t0 = i, now
    queue_cmds(gs.plan.steps[i].cmds)
    write_status()
end

local function sample(now)
    local rec = gs.plan.record
    if not (rec and gs.probes) then return end
    local dt = 1.0 / (tonumber(rec.hz) or 10)
    if now - gs.last_sample < dt then return end
    gs.last_sample = now
    local row = { t = math.floor((now - gs.t0) * 100 + 0.5) / 100, step = gs.step }
    for _, pr in ipairs(gs.probes) do
        if pr.fn then
            local ok, v = pcall(pr.fn)
            if ok then
                if type(v) == "userdata" then v = tostring(v) end
                row[pr.name] = v
            else
                row[pr.name] = "ERR: " .. tostring(v)
            end
        else
            row[pr.name] = "COMPILE: " .. tostring(pr.err)
        end
    end
    gs.rows[#gs.rows + 1] = row
end

local function ready_pressed()
    -- v2.3: Ctrl+End belongs to CaptureGuide (arm / disarm capture mode)
    local k = reframework:is_key_down(KEY_READY) and not reframework:is_key_down(0x11)
    local pd = (H.pad_buttons() & PAD_READY) == PAD_READY
    local hit = (k and not gs.key_prev) or (pd and not gs.pad_prev)
    gs.key_prev, gs.pad_prev = k, pd
    return hit
end

local function tick()
    local now = os.clock()
    read_dev_status(now)
    -- v2.3: while CaptureGuide is armed this script keeps quiet: no plan is started and End / Home are not read,
    -- so a take is never interrupted and nothing of this overlay gets into a recording
    if _G.CAPTURE_GUIDE_ACTIVE then gs.key_prev, gs.pad_prev = true, true; return end
    if now >= gs.next_poll then
        gs.next_poll = now + 1.0
        -- v2.4: unattended mode, renewed by the test bench (expires on its own if the bench stops)
        local oka, a = pcall(json.load_file, DIR .. "auto.json")
        gs.auto = oka and type(a) == "table" and a.on == true and type(a["until"]) == "number" and a["until"] > os.time()
        gs.auto_run = gs.auto and tostring(a.run or "") or nil
        if gs.auto then
            local okw, inw = pcall(function()
                local mf = sdk.get_managed_singleton("app.MainFlowManager")
                local cm = sdk.get_managed_singleton("app.CharacterManager")
                return mf ~= nil and mf:call("get_IsInGamePhase") == true and cm ~= nil and cm:call("get_ManualPlayer") ~= nil
            end)
            if okw and inw then gs.world_t = gs.world_t or now else gs.world_t = nil end
        end
        if gs.state ~= "running" and gs.state ~= "countdown" then
            local ok, p = pcall(json.load_file, PLAN_FILE)
            if ok then load_plan(p) end
            -- v1.5 queue: with nothing waiting, take the first plan in test_guide/queue/ (by file name) whose
            -- id has not run yet. Lets several tests be lined up and run back to back.
            -- (v2.4: not while the bench runs; it hands over its plans one at a time through plan.json)
            if gs.state == "idle" and not gs.auto and fs and fs.glob then
                local okg, files = pcall(fs.glob, [[test_guide\\queue\\.*\.json]])
                if okg and type(files) == "table" then
                    table.sort(files)
                    for _, f in ipairs(files) do
                        local okq, q = pcall(json.load_file, f)
                        if okq and type(q) == "table" then
                            load_plan(q)
                            if gs.state ~= "idle" then gs.queue_file = f break end
                        end
                    end
                end
            end
        end
    end
    flush_cmds(now)
    local pressed = ready_pressed()
    local shift = reframework:is_key_down(KEY_SHIFT)
    -- v2.2: Shift only counts for Shift+End when it went down in the last 5 s. On 2026-11-17 a Shift+F10 pressed
    -- for the mod under test (Windows' context-menu shortcut) left Shift reading as held for good: End then
    -- aborted the plan instead of moving to the next step.
    if shift and not gs.shift_prev then gs.shift_t = now end
    gs.shift_prev = shift
    shift = shift and (now - (gs.shift_t or -100)) < 5.0
    if gs.state == "waiting" then
        if pressed and shift then finish("aborted", "dismissed") return end
        local unmet = check_requires(gs.plan)
        local changed = (unmet and table.concat(unmet, "|") or "") ~= (gs.unmet and table.concat(gs.unmet, "|") or "")
        gs.unmet = unmet
        if changed then write_status() end
        local auto_go = gs.auto and gs.world_t ~= nil and now - gs.world_t >= 3.0 -- v2.4
        if (pressed or auto_go) and not gs.unmet then gs.state, gs.t0 = "countdown", now + 3.0; write_status() end
    elseif gs.state == "countdown" then
        if pressed and shift then finish("aborted", "aborted during countdown") return end
        if now >= gs.t0 then gs.state = "running"; start_step(1, now) end
    elseif gs.state == "running" then
        if pressed and shift then finish("aborted", "aborted at step " .. gs.step) return end
        if not (gs.plan.record and gs.plan.record.at == "frame") then sample(now) end
        local st = gs.plan.steps[gs.step]
        if st._fn then
            local okf, ferr = pcall(st._fn)
            if not okf then gs.msg = "error: step " .. gs.step .. ": " .. tostring(ferr) end
        elseif st._err then gs.msg = "error: step " .. gs.step .. ": " .. tostring(st._err) end
        local advance
        if st.wait then
            advance = pressed and not shift and (now - gs.step_t0) > 0.3
            if gs.auto and now - gs.step_t0 >= (tonumber(st.auto_secs) or 3) then advance = true end -- v2.4
        else
            advance = now - gs.step_t0 >= (tonumber(st.secs) or 5)
        end
        if advance then
            eval_step(gs.step)
            if gs.step < #gs.plan.steps then start_step(gs.step + 1, now)
            else finish("done", "finished") end
        end
    elseif (gs.state == "done" or gs.state == "aborted")
           and (now - gs.done_t > ((gs.auto and 3) or ((#gs.verdicts > 0) and 30 or 8)) or (pressed and now - gs.done_t > 0.5)) then
        gs.state, gs.plan = "idle", nil
        write_status()
    end
end

re.on_pre_application_entry("LateUpdateBehavior", function()
    local ok, err = pcall(tick)
    if not ok then tg_error("tick", err) end
end)

-- ---------------------------------------------------------------------------
-- v2.0: flight recorder (always on, 30 s ring at 10 Hz, sampled after the camera update)
-- ---------------------------------------------------------------------------
local FLIGHT_HZ, FLIGHT_SECS = 10, 30
local function flight_row(now)
    local r = { t = math.floor(now * 100 + 0.5) / 100 }
    pcall(function()
        local a = H.arisen(); if not a then return end
        local p = a:call("get_Transform"):call("get_Position")
        r.a_pos = string.format("%.1f,%.1f,%.1f", p.x, p.y, p.z)
        r.a_node = H.node(a)
        r.a_hp = a:call("get_Hp")
        local inp = a:call("get_Input")
        if inp then
            r.a_on = string.format("0x%X", inp:get_field("ButtonOnFlags") or 0)
            r.a_mag = math.floor((inp:call("get_AxisMagnitudeL") or 0) * 100) / 100
        end
    end)
    for i = 0, 2 do
        pcall(function()
            local pw = H.pawn(i); if not pw then return end
            local p = pw:call("get_Transform"):call("get_Position")
            r["p" .. i .. "_pos"] = string.format("%.1f,%.1f,%.1f", p.x, p.y, p.z)
            r["p" .. i .. "_node"] = H.node(pw)
            r["p" .. i .. "_hp"] = pw:call("get_Hp")
            local inp = pw:call("get_Input")
            if inp then r["p" .. i .. "_on"] = string.format("0x%X", inp:get_field("ButtonOnFlags") or 0) end
        end)
    end
    pcall(function()
        local d = H.pad(); if not d then return end
        r.pad = string.format("0x%X", d:call("get_Button") or 0)
        r.padL, r.padR = H.v2(d:call("get_AxisL")), H.v2(d:call("get_AxisR"))
    end)
    pcall(function()
        local cam = sdk.get_primary_camera()
        local c = cam:call("get_GameObject"):call("get_Transform"):call("get_Position")
        r.cam = string.format("%.1f,%.1f,%.1f", c.x, c.y, c.z)
        r.fov = cam:call("get_FOV")
        local mc = sdk.get_managed_singleton("app.CameraManager"):call("getMainCameraController", 0)
        local cur = mc and mc:call("get_CurrentCameraController")
        r.cam_ctrl = cur and cur:get_type_definition():get_name()
    end)
    r.keys = (reframework:is_key_down(0x57) and "W" or "") .. (reframework:is_key_down(0x41) and "A" or "")
        .. (reframework:is_key_down(0x53) and "S" or "") .. (reframework:is_key_down(0x44) and "D" or "")
        .. (reframework:is_key_down(0x01) and " LMB" or "") .. (reframework:is_key_down(0x02) and " RMB" or "")
    local dpc = gs.dev.DirectPawnControl
    if dpc then r.dpc = dpc.info end
    return r
end

local function flight_tick(now)
    if not tg_cfg.recorder then return end
    if now - gs.flight_last >= 1.0 / FLIGHT_HZ then
        gs.flight_last = now
        local f = gs.flight
        f[#f + 1] = flight_row(now)
        if #f > FLIGHT_HZ * FLIGHT_SECS then table.remove(f, 1) end
    end
    local k = reframework:is_key_down(KEY_FLIGHT) and not reframework:is_key_down(KEY_SHIFT)
    local pd = (H.pad_buttons() & PAD_FLIGHT) == PAD_FLIGHT
    if (k and not gs.fkey_prev) or (pd and not gs.fpad_prev) then
        gs.flight_n = gs.flight_n + 1
        local okt, stamp = pcall(os.time)
        local okd, when = pcall(os.date, "%Y-%m-%d %H:%M:%S")
        local name = string.format("%sflight_%d_%d.json", DIR, okt and stamp or math.floor(now), gs.flight_n)
        local ok = pcall(json.dump_file, name, { saved_at = okd and when or nil, clock = now, dev = gs.dev,
            test = gs.plan and { id = gs.plan.id, state = gs.state, step = gs.step } or nil, rows = gs.flight })
        gs.toast = ok and string.format("Flight recording #%d saved (last %d s)", gs.flight_n, FLIGHT_SECS) or "Flight recording FAILED to save"
        gs.toast_until = now + 4.0
        pcall(json.dump_file, DIR .. "flight_latest.json", { file = name, n = gs.flight_n, saved_at = okd and when or nil })
    end
    gs.fkey_prev, gs.fpad_prev = k, pd
end

-- ---------------------------------------------------------------------------
-- Overlay
-- ---------------------------------------------------------------------------
local font_big = imgui.load_font(nil, 34)
local font_mid = imgui.load_font(nil, 22)
local WHITE, YELLOW, GREEN, GREY, RED = 0xFFFFFFFF, 0xFF33DDFF, 0xFF55EE55, 0xFFAAAAAA, 0xFF5555FF

local function text(f, col, s)
    if f then imgui.push_font(f) end
    imgui.text_colored(s, col)
    if f then imgui.pop_font() end
end

local hud_key_prev = false
local function draw_hud(now)
    local hk = reframework:is_key_down(KEY_FLIGHT) and reframework:is_key_down(KEY_SHIFT)
    if hk and not hud_key_prev then tg_cfg.hud = not tg_cfg.hud; pcall(json.dump_file, CONFIG_FILE, tg_cfg) end
    hud_key_prev = hk
    local toast = gs.toast and now < gs.toast_until
    if not tg_cfg.hud and not toast then return end
    imgui.set_next_window_pos(Vector2f.new(60, 12), 1 << 1)
    pcall(imgui.set_next_window_bg_alpha, 0.55)
    imgui.begin_window("Dev HUD##TestGuideHUD", nil, (1 << 6) | (1 << 0))
    if toast then text(font_mid, YELLOW, gs.toast) end
    if tg_cfg.hud then
        local names = {}
        for mod in pairs(gs.dev) do names[#names + 1] = mod end
        table.sort(names)
        local parts = {}
        for _, mod in ipairs(names) do
            local d = gs.dev[mod]
            local alive = type(d.t) == "number" and (now - d.t) < 5.0
            local err_recent = d.last_error and type(d.last_error_t) == "number" and (now - d.last_error_t) < 120.0
            if not alive then
                text(nil, GREY, string.format("%s %s  (not reporting)", mod, tostring(d.version)))
            elseif err_recent or d.save_ok == false then
                text(nil, RED, string.format("%s %s  %s%s", mod, tostring(d.version),
                    d.save_ok == false and "SETTINGS NOT SAVED  " or "",
                    err_recent and (string.format("error x%s: ", tostring(d.errors or "?")) .. tostring(d.last_error):sub(1, 110)) or ""))
            else
                parts[#parts + 1] = string.format("%s %s", mod, tostring(d.version))
            end
        end
        if #parts > 0 then text(nil, GREY, table.concat(parts, "   ") .. "   |  Home = save last 30 s") end
    end
    imgui.end_window()
end

re.on_frame(function()
    if _G.CAPTURE_GUIDE_ACTIVE then return end -- v2.3
    local now0 = os.clock()
    local okf, ferr = pcall(flight_tick, now0)
    if not okf then tg_error("flight", ferr) end
    local okh, herr = pcall(draw_hud, now0)
    if not okh then tg_error("hud", herr) end
    if gs.state == "idle" or not gs.plan then return end
    if gs.state == "running" and gs.plan.record and gs.plan.record.at == "frame" then
        local ok, err = pcall(sample, os.clock())
        if not ok then gs.msg = "error: " .. tostring(err) end
    end
    local p, now = gs.plan, os.clock()
    imgui.set_next_window_pos(Vector2f.new(60, 60), 1 << 1) -- ImGuiCond_FirstUseEver
    pcall(imgui.set_next_window_bg_alpha, 0.75)
    imgui.begin_window("Test Guide##TestGuide", nil, (1 << 6) | (1 << 0)) -- AlwaysAutoResize | NoTitleBar
    text(font_mid, GREY, string.format("TEST: %s   (TestGuide v%s)", tostring(p.title or p.id), VERSION))
    if gs.state == "waiting" then
        if p.intro then text(font_mid, WHITE, p.intro) end
        imgui.spacing()
        for i, st in ipairs(p.steps) do
            local len = st.wait and "you press End" or string.format("%ds", math.floor(tonumber(st.secs) or 5))
            text(font_mid, GREY, string.format("%d. %s  (%s)", i, st.text or "", len))
        end
        imgui.spacing()
        if gs.unmet then
            for _, u in ipairs(gs.unmet) do text(font_mid, RED, u) end
            text(font_big, RED, "Can't start yet")
        else
            text(font_big, YELLOW, "Press END (or L3+R3) when ready")
        end
        text(nil, GREY, "Shift+End dismisses this test")
    elseif gs.state == "countdown" then
        text(font_big, YELLOW, string.format("Starting in %d...", math.ceil(gs.t0 - now)))
        local st = p.steps[1]
        text(font_mid, WHITE, "First: " .. tostring(st and st.text))
    elseif gs.state == "running" then
        local st = p.steps[gs.step]
        text(font_mid, GREY, string.format("Step %d of %d", gs.step, #p.steps))
        text(font_big, GREEN, tostring(st.text))
        if st.wait then
            text(font_big, YELLOW, "Press END (or L3+R3) when done")
        else
            local left = (tonumber(st.secs) or 5) - (now - gs.step_t0)
            text(font_big, YELLOW, string.format("%.0f", math.max(0, math.ceil(left))))
        end
        local nxt = p.steps[gs.step + 1]
        if nxt then text(font_mid, GREY, "Next: " .. tostring(nxt.text)) end
        if p.record then
            local last = gs.rows[#gs.rows]
            if last and type(p.record.show) == "table" then
                for _, name in ipairs(p.record.show) do
                    local v = last[name]
                    if type(v) == "number" then v = string.format("%.1f", v) end
                    text(font_mid, WHITE, string.format("%s = %s", tostring(name), tostring(v)))
                end
            end
            text(nil, GREY, string.format("recording (%d samples)   Shift+End aborts", #gs.rows))
        end
    else
        text(font_big, gs.state == "done" and GREEN or RED, gs.state == "done" and "Done - thanks!" or ("Stopped: " .. tostring(gs.msg)))
        if #gs.verdicts > 0 then
            local fails = 0
            for _, v in ipairs(gs.verdicts) do if not v.pass then fails = fails + 1 end end
            text(font_big, fails == 0 and GREEN or RED, fails == 0 and string.format("ALL %d CHECKS PASSED", #gs.verdicts)
                or string.format("%d of %d CHECKS FAILED", fails, #gs.verdicts))
            for _, v in ipairs(gs.verdicts) do
                text(font_mid, v.pass and GREEN or RED, string.format("%s  step %d: %s  (got %s)", v.pass and "PASS" or "FAIL",
                    v.step, tostring(v.label), tostring(v.got)))
            end
            text(nil, GREY, "End closes this")
        end
    end
    -- checks already decided while the test is still running
    if gs.state == "running" and #gs.verdicts > 0 then
        local v = gs.verdicts[#gs.verdicts]
        text(nil, v.pass and GREEN or RED, string.format("last check: %s %s (got %s)", v.pass and "PASS" or "FAIL", tostring(v.label), tostring(v.got)))
    end
    if gs.msg and gs.msg:find("^error") then text(nil, RED, gs.msg) end
    imgui.end_window()
end)

-- keep the finished ids across script resets so a stale plan never runs twice; make sure plan.json exists
-- (json.load_file logs an error on every poll of a missing file)
do
    local ok, st = pcall(json.load_file, STATUS_FILE)
    if ok and type(st) == "table" and type(st.finished) == "table" then
        for _, id in ipairs(st.finished) do if type(id) == "string" then gs.finished[#gs.finished + 1] = id end end
    end
    local okp, p = pcall(json.load_file, PLAN_FILE)
    if not okp or type(p) ~= "table" then pcall(json.dump_file, PLAN_FILE, {}) end
    local okc, c = pcall(json.load_file, CONFIG_FILE)
    if okc and type(c) == "table" then
        for k, v in pairs(c) do if tg_cfg[k] ~= nil and type(v) == type(tg_cfg[k]) then tg_cfg[k] = v end end
    else
        pcall(json.dump_file, CONFIG_FILE, tg_cfg)
    end
end
write_status()
-- v2.4.1: REFramework logs an error for every read of a missing file; without the bench there is no auto.json, and
-- the once-a-second check filled the log. Make an "off" one once (one logged miss, at load).
do
    local ok, a = pcall(json.load_file, DIR .. "auto.json")
    if not ok or type(a) ~= "table" then pcall(json.dump_file, DIR .. "auto.json", { on = false }) end
end
log.info("[TestGuide] v" .. VERSION .. " loaded: drop a plan in reframework/data/test_guide/plan.json")
