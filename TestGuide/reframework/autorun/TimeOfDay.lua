-- TimeOfDay.lua (dev tool, not shipped): pass time to a chosen hour the game's own way, for testing looks
-- (glows, lighting, night scenes). REFramework menu -> "Time of day (dev)".
--
-- Uses the game's own time skip (fade to black, the clock moves forward, the world catches up), the same call a
-- campfire sleep makes. Read from the game on 2026-11-19 (a campfire sleep at day 69 [time]):
--   app.TimeSkipManager.request(30, 0, 0, WarpTarget.None, <callback>, false, false, <Nullable<float> by reference>)
-- The first two numbers are the target hour and minute counted from midnight today (30 = [time] tomorrow).
-- Lessons, both paid for:
--   * the last argument must be a real Nullable<float> value; passing nil handed the game a null pointer and
--     crashed it (DD2.exe+0x602360b, inside request);
--   * the callback must be a real System.Action; the game's own empty one is TimeSkipManager.<>c.<>9__87_0.
-- Only ever forward in time. Never setTime / setDay: setTime(12, 0, 0, false) moved the day 68 -> 56.
local VERSION = "2.0"
local PRESETS = {
    { "the Archer pawn", 5, 30 }, { "Morning", 8, 0 }, { "Noon", 12, 0 }, { "Afternoon", 15, 30 },
    { "Dusk", 18, 30 }, { "Night", 21, 0 }, { "Midnight", 0, 0 }, { "Small hours", 3, 0 },
}
local cfg = { hour = 12, minute = 0 }
local CFG = "TimeOfDay.json"
pcall(function() local c = json.load_file(CFG); if type(c) == "table" then cfg.hour = c.hour or 12; cfg.minute = c.minute or 0 end end)
local st = { msg = nil, busy_until = 0 }

local function now()
    local tm = sdk.get_managed_singleton("app.TimeManager")
    if not tm then return nil end
    local ok, d, h, m = pcall(function() return tm:call("get_InGameDay"), tm:call("get_InGameHour"), tm:call("get_InGameMinute") end)
    if ok then return d, h, m end
end

local SIG = "request(System.Int32, System.Int32, System.Int32, app.TimeSkipManager.WarpTarget, System.Action, System.Boolean, System.Boolean, System.Nullable`1<System.Single>)"
local function pass_time_to(h, m)
    if os.clock() < st.busy_until then st.msg = "A skip is already running"; return end
    local d, ch, cm = now()
    local ts = sdk.get_managed_singleton("app.TimeSkipManager")
    if not (d and ts) then st.msg = "Not in game"; return end
    local cmp = sdk.get_managed_singleton("app.CharacterManager")
    if not (cmp and cmp:call("get_ManualPlayer")) then st.msg = "No player"; return end
    local target_h = h
    if h * 60 + m <= ch * 60 + cm + 1 then target_h = h + 24 end -- always forward: the next time it is h:m
    local ok, err = pcall(function()
        local noop = sdk.find_type_definition("app.TimeSkipManager.<>c"):get_field("<>9__87_0"):get_data(nil)
        if not noop then error("the game's empty callback is missing") end
        local nv = ValueType.new(sdk.find_type_definition("System.Nullable`1<System.Single>"))
        nv:write_byte(0, 0) -- no value
        st.nv, st.noop = nv, noop -- keep them alive while the skip runs
        local r = ts:call(SIG, target_h, m, 0, 0, noop, false, false, nv)
        if not r then error("the game refused the skip") end
    end)
    if ok then
        st.busy_until = os.clock() + 8.0
        st.msg = string.format("Passing time: day %d %02d:%02d -> %s%02d:%02d", d, ch, cm, target_h >= 24 and "tomorrow " or "", h, m)
    else
        st.msg = "Failed: " .. tostring(err)
    end
end

re.on_draw_ui(function()
    if not imgui.tree_node("Time of day (dev) v" .. VERSION) then return end
    local d, h, m = now()
    imgui.text(d and string.format("Now: day %d, %02d:%02d", d, h, m) or "Not in game")
    imgui.text("Passes time forward the game's way (fade, like resting). Never goes back.")
    for i, p in ipairs(PRESETS) do
        if i > 1 and (i - 1) % 4 ~= 0 then imgui.same_line() end
        if imgui.button(p[1] .. string.format(" %02d:%02d", p[2], p[3])) then pass_time_to(p[2], p[3]) end
    end
    local c1, c2
    c1, cfg.hour = imgui.slider_int("Hour", cfg.hour, 0, 23)
    c2, cfg.minute = imgui.slider_int("Minute", cfg.minute, 0, 59)
    if c1 or c2 then pcall(json.dump_file, CFG, cfg) end
    if imgui.button(string.format("Pass time to %02d:%02d", cfg.hour, cfg.minute)) then pass_time_to(cfg.hour, cfg.minute) end
    if st.msg then imgui.text(st.msg) end
    imgui.tree_pop()
end)
