-- DevBench.lua v1.0 (2026-11-19): the in-game half of the test bench (tools/capture/bench.py). Developer only.
--
-- 1. Heartbeat: reframework/data/bench/heartbeat.json once a second, with wall-clock time, so the bench can tell a
--    running game from a hung one (Lua stops when the game hangs) and the title screen from the world.
-- 2. Title flow log (watch-only): the game's calls when a save is loaded from the title screen go to
--    bench/flow_log.json (slot numbers included). Loading the test save by hand once tells us what to call.
-- 3. Autoload: bench/autoload.json { "mode": "call" | "observe" | "off", "slot": n, "id": "..." }. In "call" mode,
--    once per id, after 4 s on the title menu: MainFlowManager.setContinueSlot(slot) + requestStartType(Latest).
--    UNTESTED GUESS until the flow log shows the game's own sequence; the bench's default is "observe" (and its
--    keypress fallback). Nothing here runs without that file.
-- 4. Save block (v1.1): bench/saveblock.json { "on": true, "until": <os.time()>, "mode": "flag" | "skip" }, renewed by
--    the bench (expires by itself if the bench stops, and saving works again). While on, the game does not save, so a
--    test run never changes the save and "revert" is just restarting the game.
--      flag (default): the game's own switch, MainFlowManager.setSaveDisableByPlayer(true), set again every second
--                      and set back to what it was when the block ends.
--      skip:           the save requests themselves are dropped (MainFlowManager.requestSaveGameData /
--                      requestDataSaveAuto, SaveDataManager.requestSave / requestSaveAuto / requestSaveManual /
--                      requestSaveSlot). Risk: something in the game may wait for its save to finish.
--    Every save request is written to bench/flow_log.json either way, with whether it was blocked.
-- 5. Quit to title (v1.2): bench/title.json { "id": "...", "mode": "call" }, once per id, while in the world: looks
--    through GuiManager.getGUIList() for the game's own menu screens that have a returnTitle() (app.ui060804, the
--    system menu's page; app.ui060101) and calls it. UNTESTED: whether a screen has to be open, and whether a
--    "quit without saving?" question follows, is not known yet; the hooks below write the game's own calls to the
--    flow log when someone quits by hand, which tells us. Result in heartbeat.title_req.
-- Nothing in this script changes the game except the "call" step, the save block and the quit above.

local VERSION = "1.4"
local DIR = "bench/"
local db = { next_hb = 0, flow = {}, title_t = nil, done_id = nil, hooked = false, note = nil,
             block = nil, block_mode = nil, flag_old = nil, saves_seen = 0, saves_blocked = 0 }

local function wall() return os.time() end

local function snapshot()
    local s = { wall = wall(), clock = os.clock(), version = VERSION }
    pcall(function()
        local mf = sdk.get_managed_singleton("app.MainFlowManager")
        if not mf then return end
        s.phase = mf:call("get_FlowPhase")
        s.in_game = mf:call("get_IsInGamePhase") == true
        s.title = mf:call("get_IsTitleMenuPhase") == true
        s.slot = mf:call("get_LastLoadedSlot")
    end)
    pcall(function()
        local cm = sdk.get_managed_singleton("app.CharacterManager")
        s.player = cm ~= nil and cm:call("get_ManualPlayer") ~= nil
    end)
    pcall(function()
        local sd = sdk.get_managed_singleton("app.SaveDataManager")
        if sd then s.loading_slot = sd:call("getLoadingGameSlotId") end
    end)
    s.autoload = db.note
    s.save_block = db.block and db.block_mode or false
    s.saves_seen, s.saves_blocked = db.saves_seen, db.saves_blocked
    return s
end

local function flow(what, extra)
    db.flow[#db.flow + 1] = { wall = wall(), what = what, extra = extra }
    while #db.flow > 200 do table.remove(db.flow, 1) end
    pcall(json.dump_file, DIR .. "flow_log.json", db.flow)
end

-- watch-only hooks: every one returns the game's own result untouched
local function hook_watch()
    if db.hooked then return end
    db.hooked = true
    local function int_arg(a) local ok, v = pcall(sdk.to_int64, a); return ok and v or nil end
    local list = {
        { "app.MainFlowManager", "setContinueSlot" }, { "app.MainFlowManager", "requestLoadGameData" },
        { "app.MainFlowManager", "requestStartType" }, { "app.MainFlowManager", "changeFlowPhase" },
        { "app.MainFlowManager", "set_LastLoadedSlot" },
        { "app.SaveDataManager", "requestLoadSlot" }, { "app.SaveDataManager", "requestLoadManual" },
        { "app.SaveDataManager", "requestLoadAuto" },
        { "app.ui060804", "returnTitle" }, { "app.ui060101", "returnTitle" }, -- v1.2: quitting to title
        { "app.MainFlowManager", "restart" }, { "app.MainFlowResumeClass", "restart" },
    }
    -- save requests: logged always; dropped while the block is on in "skip" mode (v1.1)
    local saves = {
        { "app.MainFlowManager", "requestSaveGameData" }, { "app.MainFlowManager", "requestDataSaveAuto" },
        { "app.SaveDataManager", "requestSave" }, { "app.SaveDataManager", "requestSaveAuto" },
        { "app.SaveDataManager", "requestSaveManual" }, { "app.SaveDataManager", "requestSaveSlot" },
    }
    for _, e in ipairs(saves) do
        local td = sdk.find_type_definition(e[1])
        local m = td and td:get_method(e[2])
        if m then
            local name = e[1]:gsub("^app%.", "") .. "." .. e[2]
            pcall(sdk.hook, m, function(args)
                db.saves_seen = db.saves_seen + 1
                local drop = db.block and db.block_mode == "skip"
                if drop then db.saves_blocked = db.saves_blocked + 1 end
                flow("SAVE " .. name, { blocked = drop, block = db.block and db.block_mode or false })
                if drop then return sdk.PreHookResult.SKIP_ORIGINAL end
            end, function(r) return r end)
        end
    end
    for _, e in ipairs(list) do
        local td = sdk.find_type_definition(e[1])
        local m = td and td:get_method(e[2])
        if m then
            local name = e[1]:gsub("^app%.", "") .. "." .. e[2]
            pcall(sdk.hook, m, function(args)
                local a3 = int_arg(args[3])
                if a3 and a3 > 0xFFFFFFFF then a3 = "ptr" end -- (an object argument, not a number)
                flow(name, { arg1 = a3 })
            end, function(r) return r end)
        end
    end
end

local function autoload_tick(s)
    local ok, a = pcall(json.load_file, DIR .. "autoload.json")
    if not ok or type(a) ~= "table" then db.note = nil; return end
    if a.mode ~= "call" or type(a.slot) ~= "number" then db.note = a.mode; return end
    if db.done_id == a.id then return end
    if not s.title then db.title_t = nil; db.note = "call: waiting for the title menu"; return end
    db.title_t = db.title_t or os.clock()
    if os.clock() - db.title_t < 4.0 then db.note = "call: on the title menu"; return end
    db.done_id = a.id
    local okc, err = pcall(function()
        local mf = sdk.get_managed_singleton("app.MainFlowManager")
        mf:call("setContinueSlot", a.slot)
        mf:call("requestStartType", 2) -- app.MainFlowManager.StartType.Latest
    end)
    db.note = okc and ("call: asked for slot " .. a.slot) or ("call failed: " .. tostring(err))
    flow("bench autoload", { slot = a.slot, ok = okc, err = okc and nil or tostring(err) })
end

-- v1.3: returnTitle() only sets the menu's IsReturnTitle flag; the game acts on it when the menu opens (Esc), which
-- the bench presses. If the game is still in the world 30 s later, clear the flag so a later Esc does not quit.
local function title_gui()
    local gm = sdk.get_managed_singleton("app.GuiManager")
    local list = gm and gm:call("getGUIList")
    local n = list and list:call("get_Count") or 0
    for i = 0, n - 1 do
        local g = list:call("get_Item", i)
        if g and g:get_type_definition():get_full_name() == "app.ui060101" then return g end
    end
    return nil
end
local function title_tick(s)
    if db.title_set_t and (not s.in_game or os.time() - db.title_set_t > 30) then
        if s.in_game then
            pcall(function() local g = title_gui(); if g then g:set_field("IsReturnTitle", false) end end)
            db.title_req = "timed out: flag cleared"
            flow("bench title request", { result = db.title_req })
        end
        db.title_set_t = nil
    end
    local ok, r = pcall(json.load_file, DIR .. "title.json")
    if not ok or type(r) ~= "table" or r.id == nil or r.id == db.title_id then return end
    -- v1.4: only a fresh request (written in the last 60 s, with its time). 1.3 took an old request again after
    -- Reset Scripts (it remembered done requests only in memory) and the next Esc quit to title without saving.
    if type(r.wall) ~= "number" or math.abs(os.time() - r.wall) > 60 then db.title_id = r.id; return end
    if not s.in_game then return end
    db.title_id = r.id
    local done = nil
    pcall(function()
        local g = title_gui()
        if g then g:call("returnTitle"); done = "app.ui060101"; db.title_set_t = os.time() end
    end)
    db.title_req = done and ("flag set (" .. done .. ".returnTitle); waiting for Esc") or "no pause menu screen found"
    flow("bench title request", { result = db.title_req })
end

local function block_tick()
    local ok, b = pcall(json.load_file, DIR .. "saveblock.json")
    local on = ok and type(b) == "table" and b.on == true and type(b["until"]) == "number" and b["until"] > os.time()
    local mode = on and (b.mode == "skip" and "skip" or "flag") or nil
    local mf = sdk.get_managed_singleton("app.MainFlowManager")
    if on then
        if not db.block then flow("save block on", { mode = mode }) end
        db.block, db.block_mode = true, mode
        if mode == "flag" and mf then
            if db.flag_old == nil then db.flag_old = mf:call("get_IsSaveDisableByPlayer") == true end
            mf:call("setSaveDisableByPlayer", true)
        end
    elseif db.block then
        flow("save block off", { restore_flag = db.flag_old })
        if db.flag_old ~= nil and mf then pcall(mf.call, mf, "setSaveDisableByPlayer", db.flag_old) end
        db.block, db.block_mode, db.flag_old = nil, nil, nil
    end
end

re.on_frame(function()
    local now = os.clock()
    if now < db.next_hb then return end
    db.next_hb = now + 1.0
    pcall(hook_watch)
    local s = snapshot()
    pcall(autoload_tick, s)
    pcall(title_tick, s)
    s.title_req = db.title_req
    pcall(block_tick)
    pcall(json.dump_file, DIR .. "heartbeat.json", s)
end)

log.info("[DevBench] v" .. VERSION .. " loaded")
