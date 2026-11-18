-- PawnDefendProbe.lua  (v1.0)
-- Standalone diagnostic for the Fighter "Defend" core skill on a pawn.
--
-- PART A - SPY (always on): logs every action request the game makes for pawn characters
--   (ActionManager.requestActionCore / requestActionByHash / trySetActionImmediatelyFromOtherFsm,
--    HumanActionSelector.requestAction / requestCustomSkill, Job01ActionController.start/finishAscertain)
--   plus per-frame behavior-tree node changes (layers 0-2), IsGuard and pawn Input flags.
--   => Let the Fighter pawn (NOT possessed) defend naturally in a fight; the log captures exactly what it calls.
--
-- PART B - RECIPES: hold [V] (or the UI "Hold" checkbox) to apply the selected recipe to the first Fighter pawn.
--
-- Log file: reframework/data/PawnDefendProbe_log.txt  (flushed every ~1s)

local VERSION = "1.0"
local HOLD_KEY = 0x56 -- V

local function call(obj, m, ...)
    if not obj then return nil end
    local ok, r = pcall(obj.call, obj, m, ...)
    if ok then return r end
    return nil
end
local function field(obj, n)
    if not obj then return nil end
    local ok, r = pcall(obj.get_field, obj, n)
    if ok then return r end
    return nil
end

-- ---------------------------------------------------------------------------
-- Logging
-- ---------------------------------------------------------------------------
local LOG_FILE = "PawnDefendProbe_log.txt"
local log_all = {}
local log_view = {}
local dirty = false
local last_flush = 0
local function L(msg)
    local line = string.format("[%8.3f] %s", os.clock(), msg)
    log_all[#log_all + 1] = line
    log_view[#log_view + 1] = line
    if #log_view > 40 then table.remove(log_view, 1) end
    if #log_all > 6000 then table.remove(log_all, 1) end
    dirty = true
end
local function flush()
    if not dirty then return end
    dirty = false
    pcall(fs.write, LOG_FILE, table.concat(log_all, "\n"))
end

-- ---------------------------------------------------------------------------
-- Pawn tracking (address -> label) for hook filtering
-- ---------------------------------------------------------------------------
local pawns = {}          -- list of { chara, human, am, label, job, am_addr, chara_addr, sel_addr, j01_addr }
local am_map, sel_map, j01_map = {}, {}, {}
local target = nil        -- first fighter pawn (or first pawn)
local last_refresh = -10

local function refresh()
    pawns, am_map, sel_map, j01_map = {}, {}, {}, {}
    target = nil
    local pm = sdk.get_managed_singleton("app.PawnManager")
    if not pm then return end
    local list = call(pm, "get_PawnCharacterList")
    if not list then return end
    local n = call(list, "get_Count") or 0
    for i = 0, n - 1 do
        local c = call(list, "get_Item", i)
        if c then
            local h = call(c, "get_Human")
            local jc = h and call(h, "get_JobContext")
            local job = jc and call(jc, "get_Job") or -1
            local go = call(c, "get_GameObject")
            local label = string.format("P%d:%s(job%d)", i, go and call(go, "get_Name") or "?", job)
            local am = call(c, "get_ActionManager")
            local sel = call(c, "get_HumanActionSelector")
            local j01 = h and call(h, "get_Job01ActionCtrl")
            local p = { chara = c, human = h, am = am, sel = sel, j01 = j01, label = label, job = job }
            pawns[#pawns + 1] = p
            if am then am_map[am:get_address()] = label end
            if sel then sel_map[sel:get_address()] = label end
            if j01 then j01_map[j01:get_address()] = label end
            if job == 1 and (not target or target.job ~= 1) then target = p end
            if not target then target = p end
        end
    end
end

local function str_arg(a)
    local ok, r = pcall(function()
        local o = sdk.to_managed_object(a)
        if not o then return "nil" end
        return o:call("ToString()")
    end)
    return ok and tostring(r) or "?"
end
local function u32(a) return (sdk.to_int64(a) or 0) & 0xFFFFFFFF end

-- ---------------------------------------------------------------------------
-- PART A: hooks
-- ---------------------------------------------------------------------------
local spy_enabled = true
local recent_requests = {}  -- {t, name, layer, src} for target pawn (for replay)

local function note_request(label, src, name, layer)
    if target and label == target.label then
        recent_requests[#recent_requests + 1] = { t = os.clock(), name = name, layer = layer, src = src }
        if #recent_requests > 200 then table.remove(recent_requests, 1) end
    end
end

local function hook(tname, mname, pre)
    local td = sdk.find_type_definition(tname)
    local m = td and td:get_method(mname)
    if not m then L("!! hook missing " .. tname .. "." .. mname) return end
    sdk.hook(m, pre, function(r) return r end)
end

hook("app.ActionManager", "requestActionCore(app.ActionManager.Priority, System.String, System.UInt32)", function(args)
    if not spy_enabled then return end
    local label = am_map[sdk.to_int64(args[2])]
    if not label then return end
    local name, layer = str_arg(args[4]), u32(args[5])
    L(string.format("%s AM.requestActionCore prio=%d name=%s layer=%d", label, u32(args[3]), name, layer))
    note_request(label, "AM", name, layer)
end)
hook("app.ActionManager", "requestActionByHash(System.UInt32, System.UInt32, System.Boolean)", function(args)
    if not spy_enabled then return end
    local label = am_map[sdk.to_int64(args[2])]
    if not label then return end
    L(string.format("%s AM.requestActionByHash hash=%d layer=%d force=%d", label, u32(args[3]), u32(args[4]), u32(args[5]) & 1))
end)
hook("app.ActionManager", "trySetActionImmediatelyFromOtherFsm(via.behaviortree.ActionArg, System.String, System.UInt32, System.Boolean)", function(args)
    if not spy_enabled then return end
    local label = am_map[sdk.to_int64(args[2])]
    if not label then return end
    L(string.format("%s AM.trySetImmediately name=%s layer=%d", label, str_arg(args[4]), u32(args[5])))
end)
hook("app.ActionManager", "endAction(System.UInt32)", function(args)
    if not spy_enabled then return end
    local label = am_map[sdk.to_int64(args[2])]
    if not label then return end
    L(string.format("%s AM.endAction layer=%d", label, u32(args[3])))
end)
hook("app.HumanActionSelector", "requestAction(System.String, System.UInt32)", function(args)
    if not spy_enabled then return end
    local label = sel_map[sdk.to_int64(args[2])]
    if not label then return end
    L(string.format("%s SEL.requestAction name=%s layer=%d", label, str_arg(args[3]), u32(args[4])))
end)
hook("app.HumanActionSelector", "requestCustomSkill(app.HumanCustomSkillID, app.LocomotionSpeedTypeEnum)", function(args)
    if not spy_enabled then return end
    local label = sel_map[sdk.to_int64(args[2])]
    if not label then return end
    L(string.format("%s SEL.requestCustomSkill id=%d speed=%d", label, u32(args[3]), u32(args[4])))
end)
for _, mn in ipairs({ "requestSubNormalAttack(app.LocomotionSpeedTypeEnum)", "requestEndAction()", "requestAimAction()", "requestUpperBodyDefaultAction()" }) do
    hook("app.HumanActionSelector", mn, function(args)
        if not spy_enabled then return end
        local label = sel_map[sdk.to_int64(args[2])]
        if not label then return end
        L(string.format("%s SEL.%s", label, mn))
    end)
end
for _, mn in ipairs({ "startAscertain()", "finishAscertain()" }) do
    hook("app.Job01ActionController", mn, function(args)
        if not spy_enabled then return end
        local label = j01_map[sdk.to_int64(args[2])]
        if not label then return end
        L(string.format("%s J01.%s", label, mn))
    end)
end

-- Per-frame watcher (node names, IsGuard, input flags)
local watch_prev = {}
local function watch_frame()
    for _, p in ipairs(pawns) do
        local fsm = p.am and field(p.am, "Fsm")
        local nodes = {}
        if fsm then
            for layer = 0, 2 do
                local ok, nm = pcall(fsm.call, fsm, "getCurrentNodeName(System.UInt32)", layer)
                nodes[#nodes + 1] = ok and tostring(nm) or "?"
            end
        end
        local inp = call(p.chara, "get_Input")
        local s = string.format("guard=%s nodes=[%s] inOn=0x%X",
            tostring(call(p.chara, "get_IsGuard")), table.concat(nodes, " | "),
            inp and (field(inp, "ButtonOnFlags") or 0) or 0)
        if watch_prev[p.label] ~= s then
            watch_prev[p.label] = s
            L(p.label .. " STATE " .. s)
        end
        p.cur_state = s
    end
end

-- ---------------------------------------------------------------------------
-- PART B: recipes
-- ---------------------------------------------------------------------------
local RECIPES = {
    "1 Replay spied (replay names target requested in the 1.0s before its last natural IsGuard=true)",
    "2 Input inject: pawn Input ButtonOn |= 1<<29 (JobSpecialAction) every frame, Trigger on 1st frame",
    "3 Input inject + SEL.requestAction(Guard01) on 1st frame",
    "4 AM.requestAction(Guard01, 0, force=true) every frame",
    "5 Custom name/layer via SEL.requestAction (once or every frame)",
    "6 Custom name/layer via AM.requestAction force=true (once or every frame)",
    "7 NATIVE DEFEND: SEL.requestAction(Job01_Guard, 0xFFFFFFFF) while upper body not in guard; release Job01_GuardEnd@1",
}
local cfg = { recipe = 7, suppress_ai = true, custom_name = "Guard01", custom_layer = 0, every_frame = false, hold_ui = false, show = true }
local held_prev = false
local hold_frames = 0
local replay_on, replay_off = {}, {}
local last_guard_true = {}

local function set_ai(p, on)
    local aidm = call(p.chara, "get_AIDecisionMaker")
    local dm = aidm and (call(aidm, "get_DecisionModule") or field(aidm, "<DecisionModule>k__BackingField"))
    if dm then call(dm, "set_IsSkipThink(System.Boolean)", on) end
end

local function inject(p, first)
    local inp = call(p.chara, "get_Input")
    if not inp then return end
    local bit = 1 << 29
    local on = field(inp, "ButtonOnFlags") or 0
    pcall(inp.set_field, inp, "ButtonOnFlags", on | bit)
    if first then
        local trg = field(inp, "ButtonTriggerFlags") or 0
        pcall(inp.set_field, inp, "ButtonTriggerFlags", trg | bit)
    end
end
local function uninject(p)
    local inp = call(p.chara, "get_Input")
    if not inp then return end
    local bit = 1 << 29
    pcall(inp.set_field, inp, "ButtonOnFlags", (field(inp, "ButtonOnFlags") or 0) & ~bit)
    pcall(inp.set_field, inp, "ButtonTriggerFlags", (field(inp, "ButtonTriggerFlags") or 0) & ~bit)
    pcall(inp.set_field, inp, "ButtonReleaseFlags", (field(inp, "ButtonReleaseFlags") or 0) | bit)
end

local function apply_recipe(p, first)
    local r = cfg.recipe
    if not call(p.chara, "get_IsDrawedWeapon") then
        if first or hold_frames % 20 == 0 then call(p.sel, "requestDrawWeapon()") end
        return
    end
    if r == 1 then
        if first then
            if #replay_on == 0 then L("REPLAY: nothing captured yet - let the pawn guard naturally first") end
            for _, q in ipairs(replay_on) do
                L(string.format("REPLAY -> AM.requestAction(%s, %d, true)", q.name, q.layer))
                call(p.am, "requestAction(System.String, System.UInt32, System.Boolean)", q.name, q.layer, true)
            end
        end
    elseif r == 2 then
        inject(p, first)
    elseif r == 3 then
        inject(p, first)
        if first then call(p.sel, "requestAction(System.String, System.UInt32)", "Guard01", 0) end
    elseif r == 4 then
        call(p.am, "requestAction(System.String, System.UInt32, System.Boolean)", "Guard01", 0, true)
    elseif r == 5 then
        if first or cfg.every_frame then call(p.sel, "requestAction(System.String, System.UInt32)", cfg.custom_name, cfg.custom_layer) end
    elseif r == 6 then
        if first or cfg.every_frame then call(p.am, "requestAction(System.String, System.UInt32, System.Boolean)", cfg.custom_name, cfg.custom_layer, true) end
    elseif r == 7 then
        local fsm = field(p.am, "Fsm")
        local upper = fsm and call(fsm, "getCurrentNodeName(System.UInt32)", 1) or ""
        if not tostring(upper):find("Job01_Guard$") then
            call(p.sel, "requestAction(System.String, System.UInt32)", "Job01_Guard", 0xFFFFFFFF)
        end
    end
end

local function release_recipe(p)
    local r = cfg.recipe
    if r == 2 or r == 3 then uninject(p) end
    if r == 3 or r == 4 then call(p.sel, "requestAction(System.String, System.UInt32)", "Guard01End", 0) end
    if r == 7 then call(p.sel, "requestAction(System.String, System.UInt32)", "Job01_GuardEnd", 1) end
end

-- capture replay sequence on natural guard start
local function capture_natural_guard()
    if not target then return end
    local g = call(target.chara, "get_IsGuard") and true or false
    local prev = last_guard_true[target.label]
    if g and not prev and hold_frames == 0 then
        local now = os.clock()
        replay_on = {}
        for _, q in ipairs(recent_requests) do
            if now - q.t <= 1.0 then replay_on[#replay_on + 1] = q end
        end
        local names = {}
        for _, q in ipairs(replay_on) do names[#names + 1] = q.name .. "@" .. q.layer end
        L("*** NATURAL GUARD START on " .. target.label .. " ; requests in prior 1s: " .. table.concat(names, ", "))
    elseif prev and not g then
        L("*** GUARD END on " .. target.label)
    end
    last_guard_true[target.label] = g
end

local function key_down(vk)
    local ok, r = pcall(reframework.is_key_down, reframework, vk)
    return ok and r or false
end

re.on_pre_application_entry("UpdateBehavior", function()
    local now = os.clock()
    if now - last_refresh > 1.0 then
        last_refresh = now
        refresh()
    end
    if now - last_flush > 1.0 then last_flush = now; flush() end
    if spy_enabled then watch_frame() end
    capture_natural_guard()

    local p = target
    if not (p and p.sel and p.am) then return end
    local held = cfg.hold_ui or key_down(HOLD_KEY)
    if held then
        local first = not held_prev
        if first then
            L(string.format("=== HOLD START recipe %d on %s (custom=%s@%d)", cfg.recipe, p.label, cfg.custom_name, cfg.custom_layer))
            hold_frames = 0
        end
        if cfg.suppress_ai then set_ai(p, true) end
        apply_recipe(p, first)
        hold_frames = hold_frames + 1
    elseif held_prev then
        L(string.format("=== HOLD END after %d frames, guard=%s", hold_frames, tostring(call(p.chara, "get_IsGuard"))))
        release_recipe(p)
        if cfg.suppress_ai then set_ai(p, false) end
        hold_frames = 0
    end
    held_prev = held
end)

-- ---------------------------------------------------------------------------
-- UI
-- ---------------------------------------------------------------------------
re.on_draw_ui(function()
    if not imgui.tree_node("PawnDefendProbe v" .. VERSION) then return end
    local c
    c, spy_enabled = imgui.checkbox("Spy enabled (log pawn action requests)", spy_enabled)
    imgui.text("Target: " .. (target and target.label or "none"))
    imgui.text("State : " .. (target and target.cur_state or "-"))
    c, cfg.recipe = imgui.combo("Recipe", cfg.recipe, RECIPES)
    c, cfg.suppress_ai = imgui.checkbox("Suppress pawn AI think while holding", cfg.suppress_ai)
    c, cfg.custom_name = imgui.input_text("Custom action name", cfg.custom_name)
    c, cfg.custom_layer = imgui.slider_int("Custom layer", cfg.custom_layer, 0, 2)
    c, cfg.every_frame = imgui.checkbox("Custom: request every frame", cfg.every_frame)
    c, cfg.hold_ui = imgui.checkbox("Hold (same as holding V)", cfg.hold_ui)
    imgui.text(string.format("Replay buffer: %d requests captured", #replay_on))
    if imgui.button("Insert log marker") then L("------------- MARKER -------------") end
    imgui.same_line()
    if imgui.button("Clear log") then log_all, log_view = {}, {}; dirty = true; flush() end
    imgui.same_line()
    if imgui.button("Flush log file") then dirty = true; flush() end
    imgui.separator()
    for _, line in ipairs(log_view) do imgui.text(line) end
    imgui.tree_pop()
end)

L("PawnDefendProbe v" .. VERSION .. " loaded")
