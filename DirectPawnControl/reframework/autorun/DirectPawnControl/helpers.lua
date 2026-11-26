-- Direct Pawn Control: logging, crash breadcrumbs, safe SDK helpers, the game-thread action queue, enums.
-- Part of DirectPawnControl.lua, which loads the files in this folder in order (this one is 02 of 26).
-- Never run on its own: REFramework only runs the files directly in reframework/autorun.
local S = require("DirectPawnControl/shared")
local VERSION, TRACE_PATH, cfg, R = S.VERSION, S.TRACE_PATH, S.cfg, S.R

-- ----------------------------------------------------------------------------
-- Logging, Synchronous Crash Breadcrumb Trace & Safe SDK Helpers
-- ----------------------------------------------------------------------------
local logs = {}
local MAX_LOGS = 80
local trace_steps = {}

local function write_trace(step_name, extra)
    table.insert(trace_steps, string.format("[%.3f] %s%s",
        os.clock(), tostring(step_name), extra and (" | " .. tostring(extra)) or ""))
    while #trace_steps > (((cfg and (cfg.dev_trace_frames or 0)) or 0) > 0 and 400 or 50) do table.remove(trace_steps, 1) end
    if json and json.dump_file then
        R.dump(TRACE_PATH, {
            version = VERSION,
            last_step = step_name,
            control_mode = cfg.control_mode,
            steps = trace_steps,
        }, 2)
    end
end

local function log_msg(msg)
    local line = string.format("[%.2f] %s", os.clock(), tostring(msg))
    table.insert(logs, line)
    if #logs > MAX_LOGS then table.remove(logs, 1) end
    write_trace("LOG: " .. tostring(msg))
    pcall(log.info, "[DirectPawnControl] " .. tostring(msg))
end

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

-- Multi-signature robust locomotion caller:
-- sel:requestLocomotionImpl(app.LocomotionSpeedTypeEnum speed_type, System.Boolean is_strafe)
--   speed_type: 0=Idle, 1=Walk, 2=Run, 3=Dash
--   is_strafe:  false=NormalLocomotion (forward sprint/run/walk), true=Strafe (combat sidestep)
-- The first form that succeeds is cached, so we never retry failing signatures every frame
-- (repeated caught engine exceptions are a known delayed-crash cause in DD2).
local LOCO_FORMS = {
    "requestLocomotionImpl(app.LocomotionSpeedTypeEnum, System.Boolean)",
    "requestLocomotionImpl",
    "requestLocomotionImpl(System.UInt32, System.Boolean)",
    "requestLocomotion",
}
local loco_form_idx = nil
local loco_probe_fail_until = 0.0
-- dev59 (D-pad test dpad-1: the gestures were asked for and accepted, but never played, not even one fired by the
-- test itself): the mod asks for idle / walk locomotion every frame for a played character, which cuts a gesture off
-- at once. For 1.4 s after a gesture request, an idle request for that character is skipped; moving cancels it.
DPC_GES_HOLD = DPC_GES_HOLD or {}
local function safe_request_locomotion(sel, speed_type, is_strafe)
    if not sel then return false end
    if speed_type == 0 and next(DPC_GES_HOLD) then
        local okh, a = pcall(sel.get_address, sel)
        local untilt = okh and DPC_GES_HOLD[a]
        if untilt then
            if os.clock() < untilt then return true end
            DPC_GES_HOLD[a] = nil
        end
    end
    is_strafe = (is_strafe == true)
    if loco_form_idx then
        local ok = pcall(sel.call, sel, LOCO_FORMS[loco_form_idx], speed_type, is_strafe)
        if ok then return true end
        loco_form_idx = nil -- re-probe once if the cached form stopped working
    end
    if os.clock() < loco_probe_fail_until then return false end
    for i, form in ipairs(LOCO_FORMS) do
        if pcall(sel.call, sel, form, speed_type, is_strafe) then
            loco_form_idx = i
            return true
        end
    end
    loco_probe_fail_until = os.clock() + 5.0 -- all forms failed: back off instead of throwing every frame
    return false
end

-- ----------------------------------------------------------------------------
-- Game-Thread Action Queue (Prevents calling game SDK methods from re.on_frame)
-- ----------------------------------------------------------------------------
local main_thread_queue = {}

local function enqueue_game_thread(desc, fn)
    table.insert(main_thread_queue, { desc = desc, fn = fn })
end

-- ----------------------------------------------------------------------------
-- Enums & Static Methods (Loaded Lazily from Runtime Reflection)
-- ----------------------------------------------------------------------------
S.SKILL_NAMES = {}
S.ACTION_ENUM = {}
S.ACTION_FLAGS = {}
local PAD_BUTTONS = {}
local JOB_NAMES = {
    [1] = "Fighter", [2] = "Archer", [3] = "Mage", [4] = "Thief",
    [5] = "Warrior", [6] = "Sorcerer", [7] = "Mystic Spearhand",
    [8] = "Magick Archer", [9] = "Trickster", [10] = "Warfarer",
}
local VOCATION_ACTION_NAMES = {
    [1] = "Defend (Shield Guard)",
    [2] = "Steady Shot (Aim)",
    [3] = "Quickspell / Anodyne",
    [4] = "Swift Step (Dodge)",
    [5] = "Barge",
    [6] = "Quickspell / Galvanize",
    [7] = "Redoubted Bolt",
    [8] = "Magickal Bow Aim",
    [9] = "Invoke Effigy",
    [10] = "Vocation Action",
}
-- app.LocomotionSpeedTypeEnum verified values:
local SPEED_IDLE = 0
local SPEED_WALK = 1
local SPEED_RUN  = 2
local SPEED_DASH = 3

local enums_loaded = false
S.get_cam_angle_rad_method = nil
S.in_internal_query = false

local function read_enum(type_name)
    local by_val, by_name, list = {}, {}, {}
    local td = sdk.find_type_definition(type_name)
    if not td then return by_val, by_name, list end
    for _, f in ipairs(td:get_fields()) do
        if f:is_static() then
            local ok, v = pcall(f.get_data, f, nil)
            local name = f:get_name()
            if ok and type(v) == "number" and name ~= "value__" then
                by_val[v] = name
                by_name[name] = v
                table.insert(list, { name = name, value = v })
            end
        end
    end
    table.sort(list, function(a, b) return a.value < b.value end)
    return by_val, by_name, list
end

local function ensure_enums()
    if enums_loaded then return end
    local sk_val = read_enum("app.HumanCustomSkillID")
    local _, act_name = read_enum("app.CharacterInput.Action")
    local _, _, pad_list = read_enum("via.hid.GamePadButton")
    local pip_detail_td = sdk.find_type_definition("app.PlayerInputProcessorDetail")
    if pip_detail_td then
        S.get_cam_angle_rad_method = pip_detail_td:get_method("getCameraAngleRad")
    end
    local ci_td = sdk.find_type_definition("app.CharacterInput")
    local get_flag_m = ci_td and ci_td:get_method("getInputFlag")
    if next(sk_val) and next(act_name) then
        S.SKILL_NAMES = sk_val
        S.ACTION_ENUM = act_name
        PAD_BUTTONS = pad_list
        S.ACTION_FLAGS = {}
        for name, id in pairs(act_name) do
            if type(id) == "number" and id >= 0 and id < 63 then
                local flag = (1 << id)
                if get_flag_m then
                    local ok, fval = pcall(get_flag_m.call, get_flag_m, nil, id)
                    if ok and type(fval) == "number" and fval > 0 then
                        flag = fval
                    end
                end
                S.ACTION_FLAGS[name] = flag
            end
        end
        enums_loaded = true
        log_msg("Loaded runtime enums & CharacterInput bitflags")
    end
end

-- Localized names are resolved on the game thread (get_skills) and only read here, so skill_name()
-- is safe to call from the render thread.
local LOC_NAMES = {}   -- HumanCustomSkillID -> localized name at its current level
local LOC_LEVEL = {}   -- HumanCustomSkillID -> level the cached name was resolved at
local gui_name_job, gui_name_plain, gui_name_tried = nil, nil, false

local function valid_name(v)
    return type(v) == "string" and v ~= "" and not v:find("^<REF")
end

local function localize_skill(sc, job, id)
    if not cfg.localized_skill_names or type(id) ~= "number" or id == 0 or not sc then return end
    local lv = call(sc, "getCustomSkillLevel", id)
    if type(lv) ~= "number" or lv < 1 then lv = 1 end
    if LOC_LEVEL[id] == lv then return end
    LOC_LEVEL[id] = lv
    if not gui_name_tried then
        gui_name_tried = true
        local td = sdk.find_type_definition("app.GUIBase")
        if td then
            gui_name_job = td:get_method("getCustomSkillName(app.Character.JobEnum, app.HumanCustomSkillID, app.HumanCustomSkillLevelNo)")
            gui_name_plain = td:get_method("getCustomSkillName(app.HumanCustomSkillID, app.HumanCustomSkillLevelNo)")
        end
    end
    -- The job-qualified overload resolves names the plain one misses (e.g. High Flagration -> "<REF ...>").
    local tries = {}
    if gui_name_job then tries[#tries + 1] = function(l) return gui_name_job:call(nil, job, id, l) end end
    if gui_name_plain then tries[#tries + 1] = function(l) return gui_name_plain:call(nil, id, l) end end
    for _, l in ipairs({ lv, 1 }) do
        for _, f in ipairs(tries) do
            local ok, v = pcall(f, l)
            if ok and valid_name(v) then
                LOC_NAMES[id] = v
                return
            end
        end
    end
end

local function skill_name(id)
    if not id or id == 0 then return "(empty)" end
    if cfg.localized_skill_names and LOC_NAMES[id] then return LOC_NAMES[id] end
    local n = S.SKILL_NAMES[id]
    if n then return (n:gsub("^Job%d%d_", "")) end
    return "Skill#" .. tostring(id)
end

-- shared with the modules loaded after this one (see shared.lua)
S.logs, S.write_trace, S.log_msg, S.same_obj, S.call, S.field = logs, write_trace, log_msg, same_obj, call, field
S.set_field, S.safe_request_locomotion, S.main_thread_queue = set_field, safe_request_locomotion, main_thread_queue
S.enqueue_game_thread, S.JOB_NAMES, S.VOCATION_ACTION_NAMES = enqueue_game_thread, JOB_NAMES, VOCATION_ACTION_NAMES
S.SPEED_IDLE, S.SPEED_WALK, S.SPEED_RUN, S.SPEED_DASH = SPEED_IDLE, SPEED_WALK, SPEED_RUN, SPEED_DASH
S.read_enum, S.ensure_enums, S.localize_skill, S.skill_name = read_enum, ensure_enums, localize_skill, skill_name
