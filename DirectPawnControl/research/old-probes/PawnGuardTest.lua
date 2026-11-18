-- PawnGuardTest.lua
-- Deterministic Fighter Pawn Core Skill "Defend" Test Mod
-- Dragon's Dogma 2 (REFramework)
--
-- Features:
-- 1. Continuous per-frame guard maintenance while holding RMB or clicking Test.
-- 2. Proper weapon draw sequencing: waits for get_IsDrawedWeapon() before requesting guard.
-- 3. Pawn AI suppression (IsSkipThink & DisableNavi) so AI doesn't cancel guard on frame 2.
-- 4. Correct component calls: Job01ActionController:startAscertain() on human:get_Job01ActionCtrl().
-- 5. Strips Arisen Shift1/AimHold on RMB so native Archer skill/aim menu never pops up.

local VERSION = "1.2.0"

local function call(obj, method, ...)
    if not obj then return nil end
    local ok, res = pcall(obj.call, obj, method, ...)
    return ok and res or nil
end

local function field(obj, name)
    if not obj then return nil end
    local ok, res = pcall(obj.get_field, obj, name)
    return ok and res or nil
end

local function set_field(obj, name, val)
    if not obj then return false end
    local ok = pcall(obj.set_field, obj, name, val)
    return ok
end

local cfg = {
    window_open = true,
    rmb_override = true,
    mute_arisen_rmb = true,
    active_recipe = 1,
}

local state = {
    pawn_chara = nil,
    pawn_human = nil,
    pawn_name = "None",
    pawn_job = 0,
    arisen_chara = nil,
    arisen_input = nil,
    is_guarding = false,
    rmb_held = false,
    guard_held_frames = 0,
    last_guard_call = "None",
    current_action_name = "Idle",
    weapon_drawn = false,
    is_chara_guarding = false,
    logs = {},
}

local function log_test(msg)
    local line = string.format("[%.2f] %s", os.clock(), tostring(msg))
    table.insert(state.logs, line)
    while #state.logs > 15 do table.remove(state.logs, 1) end
    pcall(log.info, "[PawnGuardTest] " .. tostring(msg))
end

-- ----------------------------------------------------------------------------
-- Guard Candidate Recipes
-- ----------------------------------------------------------------------------
local CANDIDATES = {
    {
        id = 1,
        name = "1. Guard01 + Job01ActionCtrl:startAscertain()",
        desc = "Calls startAscertain on Job01ActionController and Guard01 on ActionSelector",
        action_str = "Guard01",
        use_ascertain = true,
    },
    {
        id = 2,
        name = "2. Job01_Ascertain (Skill 103)",
        desc = "Requests CustomSkill 103 (Fighter Vocation Action / Ascertain)",
        skill_id = 103,
        use_ascertain = true,
    },
    {
        id = 3,
        name = "3. Input Injection (pawn_input: ButtonOnFlags |= 1 << 29)",
        desc = "Injects JobSpecialAction bitmask directly into pawn's CharacterInput each frame",
        is_input = true,
    },
    {
        id = 4,
        name = "4. Pure Guard01 Action Request",
        desc = "Continuous requestAction('Guard01', 0) on every frame",
        action_str = "Guard01",
        use_ascertain = false,
    },
    {
        id = 5,
        name = "5. Action: Job01_Guard",
        desc = "Continuous requestAction('Job01_Guard', 0)",
        action_str = "Job01_Guard",
        use_ascertain = true,
    },
    {
        id = 6,
        name = "6. Action: RolGuard",
        desc = "Continuous requestAction('RolGuard', 0)",
        action_str = "RolGuard",
        use_ascertain = false,
    },
}

-- ----------------------------------------------------------------------------
-- Pawn Discovery & Target Refresh
-- ----------------------------------------------------------------------------
local function refresh_targets()
    local cm = sdk.get_managed_singleton("app.CharacterManager")
    local pm = sdk.get_managed_singleton("app.PawnManager")
    if cm then
        state.arisen_chara = call(cm, "get_ManualPlayer")
        state.arisen_input = state.arisen_chara and call(state.arisen_chara, "get_Input")
    end

    if not pm then return end

    local list = call(pm, "get_PawnCharacterList")
    local chosen_chara, chosen_human, chosen_name, chosen_job = nil, nil, nil, 0

    if list then
        local count = call(list, "get_Count") or 0
        for i = 0, count - 1 do
            local c = call(list, "get_Item", i)
            if c then
                local h = call(c, "get_Human")
                local jc = h and call(h, "get_JobContext")
                local j = jc and call(jc, "get_Job") or 0
                local pdc = h and call(h, "get_PawnDataContext")
                local name = pdc and call(pdc, "get_Name") or ("Pawn " .. i)

                if j == 1 and not chosen_chara then
                    chosen_chara, chosen_human, chosen_name, chosen_job = c, h, name, j
                    break
                elseif not chosen_chara then
                    chosen_chara, chosen_human, chosen_name, chosen_job = c, h, name, j
                end
            end
        end
    end

    if chosen_chara then
        state.pawn_chara = chosen_chara
        state.pawn_human = chosen_human
        state.pawn_name = chosen_name
        state.pawn_job = chosen_job
        state.weapon_drawn = call(chosen_chara, "get_IsDrawedWeapon") or false
        state.is_chara_guarding = call(chosen_chara, "get_IsGuard") or false
    end
end

-- ----------------------------------------------------------------------------
-- AI Suppression Helper
-- ----------------------------------------------------------------------------
local function set_ai_suppressed(chara, suppress)
    if not chara then return end
    local aidm = call(chara, "get_AIDecisionMaker")
    local dm = aidm and (call(aidm, "get_DecisionModule") or field(aidm, "<DecisionModule>k__BackingField"))
    if dm then call(dm, "set_IsSkipThink(System.Boolean)", suppress) end

    local nav = call(chara, "get_NavigationController") or field(chara, "<NavigationController>k__BackingField")
    if nav then call(nav, "set_IsRequestDisableNavi(System.Boolean)", suppress) end
end

-- ----------------------------------------------------------------------------
-- Maintain Guard (Called EVERY FRAME while RMB or Test button is held)
-- ----------------------------------------------------------------------------
local function maintain_guard_per_frame(cand)
    local chara = state.pawn_chara
    local human = state.pawn_human
    if not (chara and human and cand) then return end
    local sel = call(chara, "get_HumanActionSelector")
    if not sel then return end

    -- 1. Suppress AI so PawnAI doesn't cancel guard
    set_ai_suppressed(chara, true)

    -- 2. Weapon must be drawn
    if not call(chara, "get_IsDrawedWeapon") then
        call(sel, "requestDrawWeapon()")
        state.last_guard_call = "Drawing Weapon..."
        return
    end

    local job01_ctrl = call(human, "get_Job01ActionCtrl")

    -- 3. Execute Candidate on every frame
    if cand.use_ascertain and job01_ctrl then
        pcall(job01_ctrl.call, job01_ctrl, "startAscertain")
    end

    if cand.is_input then
        local p_input = call(chara, "get_Input")
        if p_input then
            local on_flags = field(p_input, "ButtonOnFlags") or 0
            set_field(p_input, "ButtonOnFlags", on_flags | (1 << 29))
            state.last_guard_call = "ButtonOnFlags |= (1 << 29)"
        end
    elseif cand.skill_id then
        pcall(sel.call, sel, "requestCustomSkill", cand.skill_id, 0)
        state.last_guard_call = string.format("requestCustomSkill(%d, 0)", cand.skill_id)
    elseif cand.action_str then
        pcall(sel.call, sel, "requestAction(System.String, System.UInt32)", cand.action_str, 0)
        pcall(sel.call, sel, "setAction(System.String, System.Boolean, System.UInt32)", cand.action_str, true, 0)
        state.last_guard_call = string.format("requestAction('%s', 0) + setAction", cand.action_str)
    end

    state.guard_held_frames = state.guard_held_frames + 1
    state.is_guarding = true
end

-- ----------------------------------------------------------------------------
-- Release Guard (Called when RMB or Test button is released)
-- ----------------------------------------------------------------------------
local function release_guard(cand)
    local chara = state.pawn_chara
    local human = state.pawn_human
    if not (chara and human) then return end
    local sel = call(chara, "get_HumanActionSelector")
    local job01_ctrl = call(human, "get_Job01ActionCtrl")

    if sel then
        pcall(sel.call, sel, "requestAction(System.String, System.UInt32)", "Guard01End", 0)
        pcall(sel.call, sel, "requestEndAction")
    end

    if job01_ctrl then
        pcall(job01_ctrl.call, job01_ctrl, "finishAscertain")
    end

    if cand and cand.is_input then
        local p_input = call(chara, "get_Input")
        if p_input then
            local on_flags = field(p_input, "ButtonOnFlags") or 0
            set_field(p_input, "ButtonOnFlags", on_flags & ~(1 << 29))
        end
    end

    -- Restore AI thinking
    set_ai_suppressed(chara, false)

    state.is_guarding = false
    state.guard_held_frames = 0
    state.last_guard_call = "Guard Released"
    log_test("Guard Released")
end

-- ----------------------------------------------------------------------------
-- Update Loop
-- ----------------------------------------------------------------------------
re.on_pre_application_entry("UpdateBehavior", function()
    refresh_targets()

    -- Check hardware Right Mouse Button (0x02)
    local ui_open = pcall(reframework.is_drawing_ui, reframework) and reframework:is_drawing_ui()
    local rmb_down = false
    if not ui_open then
        local ok, down = pcall(reframework.is_key_down, reframework, 0x02)
        rmb_down = (ok and down == true)
    end
    state.rmb_held = rmb_down

    -- Mute Arisen's Shift1 (1<<14), Shift1OnlySpecificJob (1<<30), AimHold (1<<11) while RMB is down
    if rmb_down and cfg.mute_arisen_rmb and state.arisen_input then
        local mask = ~((1 << 14) | (1 << 30) | (1 << 11))
        local on_f = field(state.arisen_input, "ButtonOnFlags")
        if type(on_f) == "number" and (on_f & ~mask) ~= 0 then
            set_field(state.arisen_input, "ButtonOnFlags", on_f & mask)
        end
        local trg_f = field(state.arisen_input, "ButtonTriggerFlags")
        if type(trg_f) == "number" and (trg_f & ~mask) ~= 0 then
            set_field(state.arisen_input, "ButtonTriggerFlags", trg_f & mask)
        end
    end

    -- Continuous per-frame Guard while RMB is held
    local active_cand = CANDIDATES[cfg.active_recipe]
    if cfg.rmb_override and active_cand and state.pawn_chara then
        if rmb_down then
            maintain_guard_per_frame(active_cand)
        elseif state.is_guarding then
            release_guard(active_cand)
        end
    end

    -- Telemetry
    if state.pawn_chara then
        state.weapon_drawn = call(state.pawn_chara, "get_IsDrawedWeapon") or false
        state.is_chara_guarding = call(state.pawn_chara, "get_IsGuard") or false
        local sel = call(state.pawn_chara, "get_HumanActionSelector")
        local cur_sel = sel and field(sel, "CurrentSelector")
        local act_name = cur_sel and call(cur_sel, "getActionName") or "None"
        state.current_action_name = tostring(act_name)
    end
end)

-- ----------------------------------------------------------------------------
-- In-Engine UI
-- ----------------------------------------------------------------------------
re.on_draw_ui(function()
    if imgui.tree_node("Pawn Core Skill Defend Test (v" .. VERSION .. ")") then
        local chg
        chg, cfg.window_open = imgui.checkbox("Show Defend Test Window", cfg.window_open)
        imgui.tree_pop()
    end
end)

re.on_frame(function()
    if not cfg.window_open then return end

    imgui.set_next_window_size(Vector2f.new(540, 520), 1 << 2)
    cfg.window_open = imgui.begin_window("Fighter Core Skill 'Defend' Test — v" .. VERSION, cfg.window_open, 0)
    if not cfg.window_open then
        imgui.end_window()
        return
    end

    imgui.text_colored("TARGET PAWN: " .. tostring(state.pawn_name) .. " (Job " .. tostring(state.pawn_job) .. ")", 0xFF55FF55)
    imgui.text(string.format("Weapon Drawn: %s  |  Character.IsGuard: %s",
        state.weapon_drawn and "YES" or "NO",
        state.is_chara_guarding and "TRUE [GUARD ACTIVE!]" or "FALSE"))
    imgui.text(string.format("Guard Status: %s (Held: %d frames)",
        state.is_guarding and "ACTIVE" or "IDLE", state.guard_held_frames))
    imgui.text("Current Selector Action: " .. tostring(state.current_action_name))
    imgui.text("Last Call: " .. tostring(state.last_guard_call))
    imgui.separator()

    -- RMB Mode Configuration
    imgui.text("Right-Click (RMB) Settings:")
    local chg_rmb, new_rmb = imgui.checkbox("Hold Right-Click (RMB) -> Continuously Raise Shield", cfg.rmb_override)
    if chg_rmb then cfg.rmb_override = new_rmb end
    imgui.same_line()
    local chg_m, new_m = imgui.checkbox("Mute Arisen Skill/Aim UI", cfg.mute_arisen_rmb)
    if chg_m then cfg.mute_arisen_rmb = new_m end

    imgui.text_colored(string.format("Hardware RMB State: %s", state.rmb_held and "HELD DOWN" or "RELEASED"),
        state.rmb_held and 0xFF44FF44 or 0xFF888888)
    imgui.separator()

    -- Candidate Selector
    imgui.text("Select Core Skill 'Defend' Implementation to Test:")
    for idx, cand in ipairs(CANDIDATES) do
        local is_sel = (cfg.active_recipe == idx)
        local chg_r, new_val = imgui.checkbox(cand.name, is_sel)
        if chg_r and new_val then
            cfg.active_recipe = idx
            log_test("Selected " .. cand.name)
        end
        imgui.text_colored("   " .. cand.desc, 0xFF888888)
    end

    imgui.separator()
    imgui.text("Manual Action Buttons:")
    if imgui.button("Draw Weapon & Shield") then
        if state.pawn_chara then
            local sel = call(state.pawn_chara, "get_HumanActionSelector")
            if sel then call(sel, "requestDrawWeapon()") end
        end
    end
    imgui.same_line()
    if imgui.button(state.is_guarding and "Release Guard" or "Hold Guard (Toggle)") then
        local active_cand = CANDIDATES[cfg.active_recipe]
        if not state.is_guarding then
            maintain_guard_per_frame(active_cand)
        else
            release_guard(active_cand)
        end
    end
    imgui.same_line()
    if imgui.button("Refresh Targets") then
        refresh_targets()
    end

    imgui.separator()
    imgui.text("Recent Events:")
    for _, l in ipairs(state.logs) do
        imgui.text_colored(l, 0xFFCCCCCC)
    end

    imgui.end_window()
end)
