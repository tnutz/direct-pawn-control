-- DPC_API_Example.lua: a small mod that uses Direct Pawn Control's mod API (_G.DPC_API, v1).
-- Shows: getting the API whatever the load order, queries, events, a claim, a session-only option override.
-- Dev copy for testing; a cleaned-up version goes to the public repo as examples/dpc_api_example.lua.
-- REFramework menu > "DPC API example" has the buttons. Events are also written to
-- reframework/data/DPC_API_example_log.json so a test can read them back.

local MOD = "dpc_api_example"
local ex = { log = {}, h = {}, claim = {}, ov = {}, bad = nil }
_G.DPC_API_EXAMPLE = ex -- (only so TestGuide plans can drive it)

local function note(text)
    ex.log[#ex.log + 1] = string.format("%.2f %s", os.clock(), text)
    while #ex.log > 60 do table.remove(ex.log, 1) end
    pcall(json.dump_file, "DPC_API_example_log.json", ex.log)
end

-- 1. Get the API whether DPC loaded before or after this script
local function with_dpc(fn)
    if _G.DPC_API then fn(_G.DPC_API)
    else _G.DPC_API_QUEUE = _G.DPC_API_QUEUE or {}; table.insert(_G.DPC_API_QUEUE, fn) end
end

with_dpc(function(api)
    if api.major ~= 1 then note("API major " .. tostring(api.major) .. ": not for me"); return end
    ex.api = api
    note("got DPC_API " .. api.version .. " (DPC " .. tostring(api.dpc_version) .. ")")
    -- 2. events
    for _, ev in ipairs({ "ready", "possess", "release", "switch", "coop_start", "coop_stop", "transition_start",
                          "transition_end", "arisen_ai_target", "world_loading", "world_back", "control_failed" }) do
        ex.h[ev] = api.on(ev, function(p)
            local parts = {}
            for k, v in pairs(p) do
                if type(v) ~= "userdata" then parts[#parts + 1] = k .. "=" .. tostring(v) end
            end
            table.sort(parts)
            note(ev .. " " .. table.concat(parts, " "))
        end, { mod = MOD })
    end
end)

-- toggles a test (or the menu) can call
ex.set_claim = function(res, on)
    local api = ex.api
    if not api then return "no api" end
    if on and not ex.claim[res] then
        ex.claim[res] = api.claim(res, { mod = MOD, on_lost = function() note("lost " .. res); ex.claim[res] = nil end })
        note((ex.claim[res] and "claimed " or "could not claim ") .. res)
    elseif not on and ex.claim[res] then
        api.release(ex.claim[res]); ex.claim[res] = nil
        note("released " .. res)
    end
end
ex.set_override = function(key, value)
    local api = ex.api
    if not api then return end
    if ex.ov[key] then api.clear_override(ex.ov[key]); ex.ov[key] = nil; note("override off " .. key) end
    if value ~= nil then ex.ov[key] = api.override(key, value, { mod = MOD }); note("override " .. key .. " = " .. tostring(value)) end
end
ex.set_bad = function(on) -- a handler that always fails: DPC should switch it off after 5 errors in 10 s
    local api = ex.api
    if not api then return end
    if on and not ex.bad then
        ex.bad = api.on("possess", function() error("deliberate test error") end, { mod = MOD .. "_bad" })
    elseif not on and ex.bad then
        api.off(ex.bad); ex.bad = nil
    end
end
ex.snapshot = function()
    local api = ex.api
    if not api then return "no api" end
    local s = api.state()
    local p1, p2 = api.played(1), api.played(2)
    local nm = function(c) local i = c and api.player_of(c); return i and ("P" .. i) or "-" end
    return string.format("active=%s played=%s coop=%s two_pads=%s P1=%s P2=%s ai_on=%s party=%d",
        tostring(s.active), tostring(s.played and s.played.name), tostring(s.coop.active), tostring(s.coop.two_pads),
        nm(p1), nm(p2), tostring(s.arisen.ai_on), #api.party())
end

re.on_draw_ui(function()
    if not imgui.tree_node("DPC API example") then return end
    if not ex.api then imgui.text("Waiting for Direct Pawn Control...") imgui.tree_pop() return end
    imgui.text(ex.snapshot())
    for _, res in ipairs({ "camera.transition", "camera.follow" }) do
        local c, v = imgui.checkbox("Claim " .. res, ex.claim[res] ~= nil)
        if c then ex.set_claim(res, v) end
    end
    local c, v = imgui.checkbox("Override: switch slow-motion off (this session only)", ex.ov.switch_cine_slowmo ~= nil)
    if c then ex.set_override("switch_cine_slowmo", v and 1.0 or nil) end
    c, v = imgui.checkbox("Add a handler that always fails", ex.bad ~= nil)
    if c then ex.set_bad(v) end
    -- 1.2: switching who is played
    if ex.api.possess then
        for _, e in ipairs(ex.api.party()) do
            if imgui.button("Play " .. tostring(e.name) .. "##ex" .. tostring(e.slot)) then
                local ok, why = ex.api.possess(e.chara, { mod = MOD })
                note("possess " .. tostring(e.name) .. ": " .. tostring(ok) .. " " .. tostring(why or ""))
            end
            imgui.same_line()
        end
        if imgui.button("Back to the Arisen##ex") then
            local ok, why = ex.api.release_pawn({ mod = MOD })
            note("release_pawn: " .. tostring(ok) .. " " .. tostring(why or ""))
        end
    end
    for i = math.max(1, #ex.log - 12), #ex.log do imgui.text(ex.log[i]) end
    imgui.tree_pop()
end)
