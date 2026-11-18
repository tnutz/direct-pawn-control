-- PawnSprintDeepTest.lua
-- Broad and Deep In-Engine Test Suite & AI Sprint Spy for Pawn Sprinting/Dashing
-- Dragon's Dogma 2 (REFramework)
--
-- Objective:
--   Deterministically test, measure, and identify the exact engine mechanism required
--   to achieve true Arisen-speed sprinting on a controlled/possessed pawn.
--
-- Features:
--   1. Comprehensive Runtime Reflection Dump (Fixed, Crash-Safe):
--      Dumps all methods & fields related to Speed, Dash, Sprint, Locomotion, and Move
--      across HumanActionSelector, HumanCommonActionCtrl, CharaMovementController,
--      CharaController, PlayerInputProcessor, PawnNavigationController, Character, and Human.
--   2. AI Sprint Spy / Tap:
--      Installs pre-hooks on requestLocomotionImpl, requestAction, setAction,
--      requestMoveSpeedOfNormalLocomotion, and PawnNavigationController to intercept
--      the EXACT parameters called when pawns sprint to catch up or during "Come" orders.
--   3. Live "Trigger 'Come' Order & Capture Native Sprint" Button:
--      Sends PawnOrder.Come (1) to the Main Pawn and records a 6-second high-speed telemetry
--      capture of all calls, motion states, and physical m/s speed.
--   4. "Replay Captured Native Sprint" Button:
--      Directly replays the exact captured API call sequence on the possessed pawn.
--   5. 11 Systematic In-Engine Sprint Test Recipes & Automated Suite Runner.
--   6. Live Real-Time Speedometer (m/s) & Telemetry HUD.

local VERSION = "1.3.0"
local REPORT_PATH = "sprint_deep_test_report.json"
local REFLECTION_DUMP_PATH = "sprint_reflection_dump.json"
local TAP_LOG_PATH = "sprint_ai_tap_log.json"

-- ----------------------------------------------------------------------------
-- Safe SDK Helpers & Managed Pointer Comparisons
-- ----------------------------------------------------------------------------
local function same_obj(a, b)
    if not a or not b then return false end
    local ok_a, addr_a = pcall(a.get_address, a)
    local ok_b, addr_b = pcall(b.get_address, b)
    return ok_a and ok_b and addr_a ~= nil and addr_a ~= 0 and addr_a == addr_b
end

local function call(obj, method, ...)
    if not obj then return nil end
    local ok, res = pcall(obj.call, obj, method, ...)
    if ok then return res end
    return nil
end

local function field(obj, name)
    if not obj then return nil end
    local ok, res = pcall(obj.get_field, obj, name)
    if ok then return res end
    return nil
end

local function set_field(obj, name, val)
    if not obj then return false end
    local ok = pcall(obj.set_field, obj, name, val)
    return ok
end

-- ----------------------------------------------------------------------------
-- Robust Locomotion & Speed Callers
-- Note: In RE Engine HumanActionSelector:requestLocomotionImpl(speed_type, is_strafe):
--   speed_type: 0=Idle, 1=Walk, 2=Run, 3=Dash
--   is_strafe:  false=NormalLocomotion (forward sprint/run), true=Strafe (combat sidestep)
-- ----------------------------------------------------------------------------
local function safe_request_locomotion(sel, speed_type, is_strafe)
    if not sel then return false end
    is_strafe = (is_strafe == true)
    local ok1 = pcall(sel.call, sel, "requestLocomotionImpl", speed_type, is_strafe)
    if ok1 then return true end
    local ok2 = pcall(sel.call, sel, "requestLocomotionImpl(app.LocomotionSpeedTypeEnum, System.Boolean)", speed_type, is_strafe)
    if ok2 then return true end
    local ok3 = pcall(sel.call, sel, "requestLocomotionImpl(System.UInt32, System.Boolean)", speed_type, is_strafe)
    if ok3 then return true end
    return pcall(sel.call, sel, "requestLocomotion", speed_type, is_strafe)
end

local function safe_hcac_speed(hcac, speed, is_dash)
    if not hcac then return end
    pcall(hcac.call, hcac, "set_IsEnableDashToRequestedMoveSpeedOfNormalLocomotion(System.Boolean)", is_dash == true)
    pcall(hcac.call, hcac, "requestMoveSpeedOfNormalLocomotion", speed, is_dash == true)
    pcall(hcac.call, hcac, "requestMoveSpeedOfNormalLocomotion(System.Single, System.Boolean)", speed, is_dash == true)
end

-- ----------------------------------------------------------------------------
-- Crash-Safe Reflection Dumper
-- ----------------------------------------------------------------------------
local function dump_class_reflection(type_name, keyword_filter)
    local td = sdk.find_type_definition(type_name)
    if not td then return { name = type_name, error = "TypeDef not found" } end

    local methods = {}
    local ok_m, m_list = pcall(td.get_methods, td)
    if ok_m and m_list then
        for _, m in ipairs(m_list) do
            local ok_name, mname = pcall(m.get_name, m)
            if ok_name and mname then
                local match = false
                if not keyword_filter then
                    match = true
                else
                    local lower = mname:lower()
                    for _, kw in ipairs(keyword_filter) do
                        if lower:find(kw) then match = true; break end
                    end
                end
                if match then
                    local params = {}
                    local ok_pts, pts = pcall(m.get_param_types, m)
                    local ok_pns, pns = pcall(m.get_param_names, m)
                    if ok_pts and pts then
                        for pi, pt in ipairs(pts) do
                            local pn = (ok_pns and pns and pns[pi]) or ("arg" .. pi)
                            local ptn = pt and pt:get_full_name() or "?"
                            table.insert(params, pn .. ":" .. ptn)
                        end
                    end
                    local ok_rt, rt = pcall(m.get_return_type, m)
                    local rtn = (ok_rt and rt) and rt:get_full_name() or "void"
                    table.insert(methods, string.format("%s %s(%s)", rtn, mname, table.concat(params, ", ")))
                end
            end
        end
    end

    local fields = {}
    local ok_f, f_list = pcall(td.get_fields, td)
    if ok_f and f_list then
        for _, f in ipairs(f_list) do
            local ok_fname, fname = pcall(f.get_name, f)
            if ok_fname and fname then
                local match = false
                if not keyword_filter then
                    match = true
                else
                    local lower = fname:lower()
                    for _, kw in ipairs(keyword_filter) do
                        if lower:find(kw) then match = true; break end
                    end
                end
                if match then
                    local ok_ft, ft = pcall(f.get_type, f)
                    local ftn = (ok_ft and ft) and ft:get_full_name() or "?"
                    local ok_st, st = pcall(f.is_static, f)
                    table.insert(fields, string.format("%s %s (static=%s)", ftn, fname, tostring(ok_st and st or false)))
                end
            end
        end
    end

    table.sort(methods)
    table.sort(fields)
    return { name = type_name, methods = methods, fields = fields }
end

local function generate_reflection_dump()
    local keywords = { "speed", "dash", "sprint", "locomotion", "move", "run", "walk", "rate", "fast", "player", "action" }
    local target_types = {
        "app.HumanActionSelector",
        "app.Job01ActionSelector",
        "app.HumanCommonActionCtrl",
        "app.CharaMovementController",
        "app.CharaController",
        "app.PlayerInputProcessor",
        "app.PlayerInputProcessorDetail",
        "app.PawnNavigationController",
        "app.PawnFollowOrder",
        "app.Character",
        "app.Human",
        "app.LocomotionSpeedTypeEnum",
        "app.StaminaManager"
    }

    local dump = { generated_at = os.time(), types = {} }
    for _, tname in ipairs(target_types) do
        dump.types[tname] = dump_class_reflection(tname, keywords)
    end

    if json and json.dump_file then
        pcall(json.dump_file, REFLECTION_DUMP_PATH, dump, 2)
    end
    return dump
end

-- ----------------------------------------------------------------------------
-- Position & Motion Sampling
-- ----------------------------------------------------------------------------
local function get_chara_pos(chara)
    if not chara then return nil end
    local xf = call(chara, "get_Transform")
    local pos = xf and call(xf, "get_Position")
    if not pos then return nil end
    return { x = pos.x, y = pos.y, z = pos.z }
end

local function get_chara_motion_info(chara)
    if not chara then return { bank = -1, id = -1, speed = 0, name = "nil" } end
    local mc = call(chara, "get_MotionController")
    if mc then
        local mid = call(mc, "get_MotionID") or -1
        local mbid = call(mc, "get_MotionBankID") or -1
        if mid ~= -1 or mbid ~= -1 then
            return { bank = mbid, id = mid, speed = 1.0, name = string.format("Bank#%d_ID#%d", mbid, mid) }
        end
    end

    local go = call(chara, "get_GameObject")
    if not go then return { bank = -1, id = -1, speed = 0, name = "no_go" } end
    local motion = call(go, "getComponent(System.Type)", sdk.typeof("via.motion.Motion"))
    if not motion then return { bank = -1, id = -1, speed = 0, name = "no_motion" } end
    local layer = call(motion, "getLayer", 0)
    if not layer then return { bank = -1, id = -1, speed = 0, name = "no_layer" } end

    local motion_id = call(layer, "getMotionID") or -1
    local bank_id = call(layer, "getMotionBankID") or -1
    local speed = call(layer, "get_Speed") or 0.0
    return {
        bank = bank_id,
        id = motion_id,
        speed = speed,
        name = string.format("Bank#%d_ID#%d", bank_id, motion_id)
    }
end

-- ----------------------------------------------------------------------------
-- State & Telemetry History
-- ----------------------------------------------------------------------------
local state = {
    ui_open = true,
    reflection_dump = nil,
    test_running = false,
    current_test_name = "",
    current_test_idx = 0,
    test_start_time = 0.0,
    test_duration = 1.5,
    test_start_pos = nil,
    test_results = {},
    -- Live Speedometer Telemetry
    last_tick_time = os.clock(),
    pawn_last_pos = nil,
    pawn_live_speed_mps = 0.0,
    arisen_last_pos = nil,
    arisen_live_speed_mps = 0.0,
    -- Benchmark Cache
    arisen_benchmarks = {
        walk = { speed_mps = 0.0, motion = "" },
        run = { speed_mps = 0.0, motion = "" },
        sprint = { speed_mps = 0.0, motion = "" }
    },
    -- AI Sprint Tap / Spy
    tap_active = false,
    tap_capture_until = 0.0,
    tap_logs = {},
    tap_best_speed_mps = 0.0,
    tap_captured_recipe = nil,      -- Stores the exact parameters captured during native sprint
    status_msg = "Ready. Open REFramework menu -> Pawn Sprint Deep Test."
}

-- Generate reflection dump safely on load
pcall(function() state.reflection_dump = generate_reflection_dump() end)

-- Helper to log intercepted calls into tap_logs and persist to disk
local function log_tap(source, method, details)
    local now = os.clock()
    local entry = {
        time = string.format("%.2f", now),
        source = source,
        method = method,
        details = details,
        pawn_speed_mps = string.format("%.2f", state.pawn_live_speed_mps),
        motion = "Bank#" .. tostring(state.pawn_live_speed_mps > 6.0 and "SPRINT" or (state.pawn_live_speed_mps > 3.5 and "RUN" or "WALK"))
    }
    table.insert(state.tap_logs, 1, entry)
    while #state.tap_logs > 100 do table.remove(state.tap_logs) end

    -- Check if this was during high speed (sprint!)
    if state.pawn_live_speed_mps > 5.0 and not state.tap_captured_recipe then
        state.tap_best_speed_mps = state.pawn_live_speed_mps
        state.tap_captured_recipe = {
            source = source,
            method = method,
            details = details,
            speed_mps = state.pawn_live_speed_mps
        }
    end

    if json and json.dump_file then
        pcall(json.dump_file, TAP_LOG_PATH, {
            captured_at = os.time(),
            best_speed_mps = state.tap_best_speed_mps,
            captured_recipe = state.tap_captured_recipe,
            logs = state.tap_logs
        }, 2)
    end
end

-- ----------------------------------------------------------------------------
-- Target Pawn Discovery
-- ----------------------------------------------------------------------------
local function get_target_pawn()
    local pm = sdk.get_managed_singleton("app.PawnManager")
    local mp = pm and (field(pm, "_MainPawn") or call(pm, "get_MainPawn"))
    local chara = mp and call(mp, "get_CachedCharacter")
    if not chara then return nil end
    local human = call(chara, "get_Human")
    local sel = call(chara, "get_HumanActionSelector")
    local hcac = human and (call(human, "get_HumanCommonActionCtrl") or field(human, "<HumanCommonActionCtrl>k__BackingField"))
    local chara_input = call(chara, "get_Input")
    local nav = call(chara, "get_NavigationController")
    return {
        chara = chara,
        human = human,
        sel = sel,
        hcac = hcac,
        input = chara_input,
        pawn_obj = mp,
        nav = nav
    }
end

-- ----------------------------------------------------------------------------
-- Install Live AI Sprint Spy Hooks (Taps into Native Pawn Sprinting)
-- ----------------------------------------------------------------------------
local hooks_installed = false
local function install_sprint_hooks()
    if hooks_installed then return end

    -- 1. Hook app.HumanActionSelector:requestLocomotionImpl
    local sel_td = sdk.find_type_definition("app.HumanActionSelector")
    if sel_td then
        local m_loco = sel_td:get_method("requestLocomotionImpl(app.LocomotionSpeedTypeEnum, System.Boolean)")
            or sel_td:get_method("requestLocomotionImpl")
        if m_loco then
            sdk.hook(
                m_loco,
                function(args)
                    local this_sel = sdk.to_managed_object(args[2])
                    local p = get_target_pawn()
                    if p and p.sel and same_obj(this_sel, p.sel) then
                        local speed_type = sdk.to_int64(args[3]) & 0xFFFFFFFF
                        local is_dash = sdk.to_int64(args[4]) ~= 0
                        log_tap("HumanActionSelector", "requestLocomotionImpl",
                            string.format("speed_type=%d, is_dash=%s", speed_type, tostring(is_dash)))
                    end
                end,
                function(retval) return retval end
            )
        end

        local m_act = sel_td:get_method("requestAction(System.String, System.UInt32)")
        if m_act then
            sdk.hook(
                m_act,
                function(args)
                    local this_sel = sdk.to_managed_object(args[2])
                    local p = get_target_pawn()
                    if p and p.sel and same_obj(this_sel, p.sel) then
                        local act_obj = sdk.to_managed_object(args[3])
                        local act_name = act_obj and act_obj:call("ToString") or tostring(args[3])
                        log_tap("HumanActionSelector", "requestAction", "action=" .. tostring(act_name))
                    end
                end,
                function(retval) return retval end
            )
        end
    end

    -- 2. Hook app.HumanCommonActionCtrl:requestMoveSpeedOfNormalLocomotion
    local hcac_td = sdk.find_type_definition("app.HumanCommonActionCtrl")
    if hcac_td then
        local m_spd = hcac_td:get_method("requestMoveSpeedOfNormalLocomotion(System.Single, System.Boolean)")
            or hcac_td:get_method("requestMoveSpeedOfNormalLocomotion")
        if m_spd then
            sdk.hook(
                m_spd,
                function(args)
                    local this_hcac = sdk.to_managed_object(args[2])
                    local p = get_target_pawn()
                    if p and p.hcac and same_obj(this_hcac, p.hcac) then
                        local spd = sdk.to_float(args[3]) or 0.0
                        local is_dash = sdk.to_int64(args[4]) ~= 0
                        log_tap("HumanCommonActionCtrl", "requestMoveSpeedOfNormalLocomotion",
                            string.format("speed=%.2f, is_dash=%s", spd, tostring(is_dash)))
                    end
                end,
                function(retval) return retval end
            )
        end

        local m_dash_flag = hcac_td:get_method("set_IsEnableDashToRequestedMoveSpeedOfNormalLocomotion(System.Boolean)")
        if m_dash_flag then
            sdk.hook(
                m_dash_flag,
                function(args)
                    local this_hcac = sdk.to_managed_object(args[2])
                    local p = get_target_pawn()
                    if p and p.hcac and same_obj(this_hcac, p.hcac) then
                        local enable = sdk.to_int64(args[3]) ~= 0
                        log_tap("HumanCommonActionCtrl", "set_IsEnableDashToRequestedMoveSpeedOfNormalLocomotion",
                            "enable=" .. tostring(enable))
                    end
                end,
                function(retval) return retval end
            )
        end
    end

    hooks_installed = true
end
pcall(install_sprint_hooks)

-- ----------------------------------------------------------------------------
-- Live Speedometer & Arisen Benchmark Telemetry
-- ----------------------------------------------------------------------------
local function update_live_telemetry()
    local now = os.clock()
    local dt = now - state.last_tick_time
    if dt < 0.033 then return end
    state.last_tick_time = now

    local cm = sdk.get_managed_singleton("app.CharacterManager")
    local pm = sdk.get_managed_singleton("app.PawnManager")
    if not cm or not pm then return end

    local arisen = call(cm, "get_ManualPlayer")
    local main_pawn = call(pm, "get_MainPawn")
    local pawn_chara = main_pawn and call(main_pawn, "get_CachedCharacter")

    -- 1. Arisen Telemetry
    if arisen then
        local pos = get_chara_pos(arisen)
        if pos and state.arisen_last_pos then
            local dx = pos.x - state.arisen_last_pos.x
            local dz = pos.z - state.arisen_last_pos.z
            local dist = math.sqrt(dx * dx + dz * dz)
            state.arisen_live_speed_mps = dist / dt
            local motion = get_chara_motion_info(arisen)
            if state.arisen_live_speed_mps > 6.0 then
                state.arisen_benchmarks.sprint = { speed_mps = state.arisen_live_speed_mps, motion = motion.name }
            elseif state.arisen_live_speed_mps > 3.0 and state.arisen_live_speed_mps <= 6.0 then
                state.arisen_benchmarks.run = { speed_mps = state.arisen_live_speed_mps, motion = motion.name }
            elseif state.arisen_live_speed_mps > 0.8 and state.arisen_live_speed_mps <= 3.0 then
                state.arisen_benchmarks.walk = { speed_mps = state.arisen_live_speed_mps, motion = motion.name }
            end
        end
        state.arisen_last_pos = pos
    end

    -- 2. Pawn Telemetry
    if pawn_chara then
        local pos = get_chara_pos(pawn_chara)
        if pos and state.pawn_last_pos then
            local dx = pos.x - state.pawn_last_pos.x
            local dz = pos.z - state.pawn_last_pos.z
            local dist = math.sqrt(dx * dx + dz * dz)
            state.pawn_live_speed_mps = dist / dt
            if state.pawn_live_speed_mps > state.tap_best_speed_mps then
                state.tap_best_speed_mps = state.pawn_live_speed_mps
            end
        end
        state.pawn_last_pos = pos
    end

    -- 3. Check active "Come" tap window
    if state.tap_active and now > state.tap_capture_until then
        state.tap_active = false
        state.status_msg = string.format("Native Sprint Capture Finished! Peak Speed: %.2f m/s", state.tap_best_speed_mps)
    end
end

-- Trigger "Come" Order and monitor the main pawn as they sprint to catch up
local function trigger_come_order_and_tap()
    local p = get_target_pawn()
    if not (p and p.pawn_obj) then
        state.status_msg = "Error: Main Pawn not found in world."
        return
    end

    -- Set order = 1 (Come)
    set_field(p.pawn_obj, "_NextOrder", 1)
    call(p.pawn_obj, "changeActiveOrderToNextOrder")
    call(p.pawn_obj, "set_ActiveOrder", 1)
    call(p.pawn_obj, "set_ActiveOrderTime", 0.0)

    state.tap_active = true
    state.tap_capture_until = os.clock() + 6.0
    state.status_msg = "Sent 'Come' order! Monitoring the main pawn's native sprint for 6 seconds..."
end

-- ----------------------------------------------------------------------------
-- The Decisive Sprint Test Battery (6 Focused Recipes)
-- ----------------------------------------------------------------------------
local RECIPES = {
    {
        name = "Recipe 1: Baseline Walk (speed_type=1, is_strafe=false)",
        desc = "Standard walking locomotion request.",
        tick = function(pawn, human, sel, hcac, chara_input, angle)
            call(pawn, "set_TargetMoveAngleDeg(System.Single)", angle)
            call(pawn, "set_TargetFrontAngleDeg(System.Single)", angle)
            safe_request_locomotion(sel, 1, false)
        end
    },
    {
        name = "Recipe 2: Baseline Run / Jog (speed_type=2, is_strafe=false)",
        desc = "Standard jogging/running locomotion request (~4.1 m/s).",
        tick = function(pawn, human, sel, hcac, chara_input, angle)
            call(pawn, "set_TargetMoveAngleDeg(System.Single)", angle)
            call(pawn, "set_TargetFrontAngleDeg(System.Single)", angle)
            safe_request_locomotion(sel, 2, false)
        end
    },
    {
        name = "Recipe 3: The Flawed Call — Strafe Dash (speed_type=3, is_strafe=true)",
        desc = "Demonstrates why passing true throttled the pawn to combat strafe speed (~3.47 m/s).",
        tick = function(pawn, human, sel, hcac, chara_input, angle)
            call(pawn, "set_TargetMoveAngleDeg(System.Single)", angle)
            call(pawn, "set_TargetFrontAngleDeg(System.Single)", angle)
            safe_request_locomotion(sel, 3, true)
        end
    },
    {
        name = "Recipe 4: Intercepted Native Sprint (speed_type=3, is_strafe=false)",
        desc = "The exact call intercepted from 'Come' order: NormalLocomotion Dash (>7.0 m/s).",
        tick = function(pawn, human, sel, hcac, chara_input, angle)
            call(pawn, "set_TargetMoveAngleDeg(System.Single)", angle)
            call(pawn, "set_TargetFrontAngleDeg(System.Single)", angle)
            safe_request_locomotion(sel, 3, false)
        end
    },
    {
        name = "Recipe 5: Native Sprint + Human Dash Flags",
        desc = "Combines NormalLocomotion Dash with Human:set_IsDash(true) and notifyKeepDash().",
        tick = function(pawn, human, sel, hcac, chara_input, angle)
            call(pawn, "set_TargetMoveAngleDeg(System.Single)", angle)
            call(pawn, "set_TargetFrontAngleDeg(System.Single)", angle)
            if human then
                call(human, "set_IsDash(System.Boolean)", true)
                call(human, "set_IsPrevDash(System.Boolean)", true)
                call(human, "notifyKeepDash")
                call(human, "setLocomotionSpeedType(app.LocomotionSpeedTypeEnum)", 3)
            end
            safe_request_locomotion(sel, 3, false)
        end,
        cleanup = function(pawn, human, sel, hcac, chara_input)
            if human then
                call(human, "set_IsDash(System.Boolean)", false)
                call(human, "set_IsPrevDash(System.Boolean)", false)
            end
        end
    },
    {
        name = "Recipe 6: Full Player Mirror (Dash Flags + Character Speed 3 + HCAC 1.0)",
        desc = "Full player-accurate sprint stack: Human Dash flags + Character LocomotionSpeed 3 + HCAC 1.0 + NormalLocomotion.",
        setup = function(pawn, human, sel, hcac, chara_input)
            if hcac then
                call(hcac, "set_IsEnableDashToRequestedMoveSpeedOfNormalLocomotion(System.Boolean)", true)
            end
        end,
        tick = function(pawn, human, sel, hcac, chara_input, angle)
            call(pawn, "set_TargetMoveAngleDeg(System.Single)", angle)
            call(pawn, "set_TargetFrontAngleDeg(System.Single)", angle)
            if human then
                call(human, "set_IsDash(System.Boolean)", true)
                call(human, "set_IsPrevDash(System.Boolean)", true)
                call(human, "notifyKeepDash")
                call(human, "setLocomotionSpeedType(app.LocomotionSpeedTypeEnum)", 3)
            end
            if pawn then
                call(pawn, "setLocomotionSpeed(app.LocomotionSpeedTypeEnum)", 3)
                call(pawn, "set_DiscreteLocomotionSpeedType(app.LocomotionSpeedTypeEnum)", 3)
            end
            safe_hcac_speed(hcac, 1.0, true)
            safe_request_locomotion(sel, 3, false)
        end,
        cleanup = function(pawn, human, sel, hcac, chara_input)
            if human then
                call(human, "set_IsDash(System.Boolean)", false)
                call(human, "set_IsPrevDash(System.Boolean)", false)
            end
            if pawn then
                call(pawn, "setLocomotionSpeed(app.LocomotionSpeedTypeEnum)", 0)
                call(pawn, "set_DiscreteLocomotionSpeedType(app.LocomotionSpeedTypeEnum)", 0)
            end
        end
    }
}

-- ----------------------------------------------------------------------------
-- Test Execution Engine
-- ----------------------------------------------------------------------------
local active_recipe = nil
local active_recipe_idx = 0
local fixed_drive_angle = 0.0

local function start_recipe(idx)
    local p = get_target_pawn()
    if not (p and p.chara and p.sel) then
        state.status_msg = "Error: Target pawn components not found."
        return false
    end

    local rec = RECIPES[idx]
    if not rec then return false end

    fixed_drive_angle = call(p.chara, "get_TargetFrontAngleDeg") or 0.0

    active_recipe = rec
    active_recipe_idx = idx
    state.current_test_name = rec.name
    state.test_start_time = os.clock()
    state.test_start_pos = get_chara_pos(p.chara)

    if rec.setup then
        pcall(rec.setup, p.chara, p.human, p.sel, p.hcac, p.input)
    end
    state.status_msg = "Running " .. rec.name .. "..."
    return true
end

local function finish_current_recipe()
    if not active_recipe then return end
    local p = get_target_pawn()
    local end_pos = p and get_chara_pos(p.chara)
    local total_time = os.clock() - state.test_start_time

    if active_recipe.cleanup and p then
        pcall(active_recipe.cleanup, p.chara, p.human, p.sel, p.hcac, p.input)
    end

    if p and p.sel and call(p.sel, "isEnableRequestIdle") then
        call(p.sel, "requestIdleImpl(System.Boolean)", false)
    end

    local dist_xz = 0.0
    if state.test_start_pos and end_pos then
        local dx = end_pos.x - state.test_start_pos.x
        local dz = end_pos.z - state.test_start_pos.z
        dist_xz = math.sqrt(dx * dx + dz * dz)
    end

    local actual_speed_mps = total_time > 0 and (dist_xz / total_time) or 0.0
    local last_motion = p and get_chara_motion_info(p.chara) or { name = "unknown" }

    local classification = "WALK"
    if actual_speed_mps > 6.0 then
        classification = "TRUE_SPRINT"
    elseif actual_speed_mps > 3.5 then
        classification = "RUN_JOG"
    end

    local result_entry = {
        recipe_idx = active_recipe_idx,
        name = active_recipe.name,
        desc = active_recipe.desc,
        duration_s = total_time,
        distance_meters = dist_xz,
        measured_speed_mps = actual_speed_mps,
        classification = classification,
        motion_clip = last_motion.name,
        achieved_true_sprint = (classification == "TRUE_SPRINT")
    }

    table.insert(state.test_results, result_entry)
    active_recipe = nil
    active_recipe_idx = 0
end

local function start_full_suite()
    state.test_results = {}
    state.test_running = true
    state.current_test_idx = 1
    start_recipe(1)
end

-- ----------------------------------------------------------------------------
-- UpdateBehavior Game-Thread Tick
-- ----------------------------------------------------------------------------
re.on_pre_application_entry("UpdateBehavior", function()
    update_live_telemetry()

    if not state.test_running and not active_recipe then return end

    local now = os.clock()
    local p = get_target_pawn()
    if not (p and p.chara and p.sel) then
        state.test_running = false
        active_recipe = nil
        return
    end

    if active_recipe then
        local elapsed = now - state.test_start_time
        if elapsed < state.test_duration then
            pcall(active_recipe.tick, p.chara, p.human, p.sel, p.hcac, p.input, fixed_drive_angle)
        else
            finish_current_recipe()

            if state.test_running then
                state.current_test_idx = state.current_test_idx + 1
                if state.current_test_idx <= #RECIPES then
                    start_recipe(state.current_test_idx)
                else
                    state.test_running = false
                    local final_report = {
                        version = VERSION,
                        generated_at = os.time(),
                        arisen_benchmarks = state.arisen_benchmarks,
                        results = state.test_results,
                        summary = {
                            total_recipes_tested = #state.test_results,
                            true_sprint_recipes = {}
                        }
                    }
                    for _, r in ipairs(state.test_results) do
                        if r.achieved_true_sprint then
                            table.insert(final_report.summary.true_sprint_recipes, r.name .. string.format(" (%.2f m/s)", r.measured_speed_mps))
                        end
                    end
                    if json and json.dump_file then
                        pcall(json.dump_file, REPORT_PATH, final_report, 2)
                    end
                    state.status_msg = "Test Suite Complete! Report saved to " .. REPORT_PATH
                end
            end
        end
    end
end)

-- ----------------------------------------------------------------------------
-- ImGui UI & Diagnostic Panel
-- ----------------------------------------------------------------------------
re.on_draw_ui(function()
    if imgui.tree_node("Pawn Sprint Deep Test & Benchmark (v" .. VERSION .. ")") then
        local chg
        chg, state.ui_open = imgui.checkbox("Show Sprint Diagnostic Panel", state.ui_open)
        imgui.tree_pop()
    end
end)

re.on_frame(function()
    if not state.ui_open then return end

    state.ui_open = imgui.begin_window("Pawn Sprint Deep Diagnostic Harness", state.ui_open, 1 << 6)
    if not state.ui_open then
        imgui.end_window()
        return
    end

    -- Live Speedometer Header
    imgui.text_colored("--- LIVE REAL-TIME TELEMETRY ---", 0xFF88EEFF)
    local p_color = (state.pawn_live_speed_mps > 6.0) and 0xFF44FF44 or ((state.pawn_live_speed_mps > 3.5) and 0xFFFFAA44 or 0xFFFFFFFF)
    imgui.text_colored(string.format("Pawn Live Speed:   %.2f m/s  [Peak Sprint: %.2f m/s]", state.pawn_live_speed_mps, state.tap_best_speed_mps), p_color)
    local a_color = (state.arisen_live_speed_mps > 6.0) and 0xFF44FF44 or 0xFFCCCCCC
    imgui.text_colored(string.format("Arisen Live Speed: %.2f m/s  [Benchmark Sprint: %.2f m/s]", state.arisen_live_speed_mps, state.arisen_benchmarks.sprint.speed_mps), a_color)
    imgui.text_colored("Status: " .. state.status_msg, 0xFFEEEE55)

    -- AI Sprint Tap Section (The User's Key Observation)
    imgui.separator()
    imgui.text_colored("--- AI NATIVE SPRINT TAP & SPY ---", 0xFFFF88FF)
    imgui.text("Tap intercepts what the game engine calls when pawns sprint to catch up.")
    if state.tap_active then
        local rem = state.tap_capture_until - os.clock()
        imgui.text_colored(string.format("RECORDING ACTIVE (%.1fs remaining)... Order your pawns to 'Come'!", rem), 0xFF00FFFF)
    else
        if imgui.button("Order 'Come' & Monitor Native Sprint (6s)") then
            trigger_come_order_and_tap()
        end
        imgui.same_line()
        if imgui.button("Clear Tap Logs") then
            state.tap_logs = {}
            state.tap_captured_recipe = nil
        end
    end

    if state.tap_captured_recipe then
        imgui.text_colored(string.format("CAPTURED NATIVE SPRINT API (%.2f m/s):", state.tap_captured_recipe.speed_mps), 0xFF55FF55)
        imgui.text(string.format("  Source: %s | Method: %s", state.tap_captured_recipe.source, state.tap_captured_recipe.method))
        imgui.text(string.format("  Details: %s", state.tap_captured_recipe.details))
    end

    if imgui.tree_node(string.format("Live Intercepted Calls Log (%d entries)", #state.tap_logs)) then
        for i = 1, math.min(15, #state.tap_logs) do
            local e = state.tap_logs[i]
            imgui.text(string.format("[%ss | %sm/s] %s::%s -> %s", e.time, e.pawn_speed_mps, e.source, e.method, e.details))
        end
        imgui.tree_pop()
    end

    -- Automated Recipes Section
    imgui.separator()
    imgui.text_colored("--- AUTOMATED SPRINT TEST SUITE ---", 0xFFFFFF55)
    if state.test_running then
        imgui.text_colored(string.format("RUNNING TEST [%d/%d]: %s", state.current_test_idx, #RECIPES, state.current_test_name), 0xFF00FFFF)
        local elapsed = os.clock() - state.test_start_time
        imgui.text(string.format("Progress: %.1fs / %.1fs", elapsed, state.test_duration))
        if imgui.button("Abort Suite") then
            state.test_running = false
            finish_current_recipe()
        end
    else
        if imgui.button("RUN ALL 6 DECISIVE RECIPES (Automated Benchmark)") then
            start_full_suite()
        end
        imgui.same_line()
        if imgui.button("Dump Reflection JSON") then
            local ok, d = pcall(generate_reflection_dump)
            if ok then
                state.reflection_dump = d
                state.status_msg = "Successfully dumped reflection JSON to " .. REFLECTION_DUMP_PATH
            else
                state.status_msg = "Dump failed: " .. tostring(d)
            end
        end
    end

    -- Individual Recipe Buttons
    imgui.separator()
    imgui.text("Individual Recipe Triggers (1.5s drive along facing direction):")
    for i, rec in ipairs(RECIPES) do
        local btn_label = string.format("Run #%d: %s", i, rec.name)
        if imgui.button(btn_label) and not state.test_running and not active_recipe then
            start_recipe(i)
        end
    end

    -- Results Table
    if #state.test_results > 0 then
        imgui.separator()
        imgui.text_colored("--- TEST RESULTS SUMMARY ---", 0xFF55FF55)
        for _, r in ipairs(state.test_results) do
            local res_color = r.achieved_true_sprint and 0xFF44FF44 or (r.classification == "RUN_JOG" and 0xFFFFAA44 or 0xFF888888)
            imgui.text_colored(string.format("[%s] #%d: %.2f m/s  |  Dist: %.1fm  |  %s",
                r.classification, r.recipe_idx, r.measured_speed_mps, r.distance_meters, r.name), res_color)
        end
    end

    -- Reflection Inspection
    if imgui.tree_node("Reflection Catalog of Movement & Speed APIs") then
        if state.reflection_dump and state.reflection_dump.types then
            for tname, tinfo in pairs(state.reflection_dump.types) do
                if imgui.tree_node(tname .. string.format(" (%d methods, %d fields)", #(tinfo.methods or {}), #(tinfo.fields or {}))) then
                    if tinfo.methods and #tinfo.methods > 0 then
                        imgui.text_colored("Methods:", 0xFF88EEFF)
                        for _, m in ipairs(tinfo.methods) do imgui.text("  " .. m) end
                    end
                    if tinfo.fields and #tinfo.fields > 0 then
                        imgui.text_colored("Fields:", 0xFFFFDD55)
                        for _, f in ipairs(tinfo.fields) do imgui.text("  " .. f) end
                    end
                    imgui.tree_pop()
                end
            end
        else
            imgui.text("Click 'Dump Reflection JSON' to populate.")
        end
        imgui.tree_pop()
    end

    imgui.end_window()
end)
