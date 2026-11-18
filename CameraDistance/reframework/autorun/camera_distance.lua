-- ==============================================================================
-- Camera Distance & Framing Studio for Dragon's Dogma 2
-- REFramework Lua Mod (v2.2.0)
--
-- Features:
--   - Contextual Distance Offsets (Exploration vs. Combat/Weapon Drawn/Battle Mode)
--   - Smooth Exponential Transitions (no jarring camera snaps)
--   - Over-the-Shoulder (OTS) 3rd-Person Framing (Horizontal X, Vertical Y, Shoulder Swap)
--   - RTS / Tactical Bird's-Eye Mode (High-altitude orbital zoom + downward pitch angle
--     + forward battlefield lead offset)
--   - Field of View (FOV) Control with Combat FOV boost & automatic vanilla restoration
--   - Auto-Suspend during Cutscenes, Dialogues, Pause Menus, and Bow/Scope Aiming
--     (using native MainCameraController:get_CurrentPlayerCamera())
--   - On-the-Fly Quick Zoom (Keyboard Hotkeys, Mouse Wheel + Modifier, Gamepad Combos)
--   - Built-in & Custom Presets + Live Telemetry
--   - Couch co-op framing with DirectPawnControl (keeps player 2's pawn on screen)
--
-- Threading (v2.2): all game calls run on the game thread (pre-LateUpdateBehavior). Only the ImGui panel
-- runs on the render thread.
-- ==============================================================================

local MOD_NAME = "Camera Distance & Framing"
local MOD_VERSION = "2.9.8"
local CONFIG_FILE = "camera_distance_config.json"

-- ==============================================================================
-- Built-in Presets (Standard 3rd-person presets keep pitch_deg = 0.0 for natural mouse/stick look)
-- ==============================================================================

local BUILTIN_PRESETS = {
    {
        name = "Vanilla (Default)",
        desc = "Unmodified Dragon's Dogma 2 camera distance and framing.",
        distance = 0.0,
        use_combat_distance = false,
        combat_distance = 0.0,
        extra_distance = 0.0,
        shoulder_x = 0.0,
        height_y = 0.0,
        pitch_deg = 0.0,
        forward_lead = 0.0,
        rts_mode = false,
        fov_enabled = false,
        fov_value = 60.0,
        combat_fov_offset = 0.0,
    },
    {
        name = "Over-the-Shoulder (Action 3rd Person)",
        desc = "Close, immersive over-the-right-shoulder framing (RE4 / God of War style). Pulls out slightly in combat.",
        distance = -0.75,
        use_combat_distance = true,
        combat_distance = 0.85,
        extra_distance = 0.0,
        shoulder_x = 0.48,
        height_y = 0.15,
        pitch_deg = 0.0,
        forward_lead = 0.0,
        rts_mode = false,
        fov_enabled = false,
        fov_value = 60.0,
        combat_fov_offset = 4.0,
    },
    {
        name = "Classic RPG (Balanced)",
        desc = "Comfortable wider view for exploration (+1.5m) that automatically zooms out (+3.5m) in combat.",
        distance = 1.50,
        use_combat_distance = true,
        combat_distance = 3.50,
        extra_distance = 0.0,
        shoulder_x = 0.0,
        height_y = 0.20,
        pitch_deg = 0.0,
        forward_lead = 0.0,
        rts_mode = false,
        fov_enabled = false,
        fov_value = 60.0,
        combat_fov_offset = 0.0,
    },
    {
        name = "Monster Hunter / Wide Combat",
        desc = "Wide battlefield awareness (+2.5m explore / +6.0m combat) ideal for fighting and climbing large monsters.",
        distance = 2.50,
        use_combat_distance = true,
        combat_distance = 6.00,
        extra_distance = 0.0,
        shoulder_x = 0.0,
        height_y = 0.35,
        pitch_deg = 0.0,
        forward_lead = 0.0,
        rts_mode = false,
        fov_enabled = false,
        fov_value = 60.0,
        combat_fov_offset = 0.0,
    },
    {
        name = "Panoramic (Ultra Wide)",
        desc = "Far pulled-back camera (+5.5m explore / +9.0m combat) for scenic exploration and multi-boss encounters.",
        distance = 5.50,
        use_combat_distance = true,
        combat_distance = 9.00,
        extra_distance = 0.0,
        shoulder_x = 0.0,
        height_y = 0.50,
        pitch_deg = 0.0,
        forward_lead = 0.0,
        rts_mode = false,
        fov_enabled = false,
        fov_value = 60.0,
        combat_fov_offset = 0.0,
    },
    {
        name = "RTS / Tactical Bird's-Eye",
        desc = "High-altitude orbital camera angled down over the battlefield. Great for ARPG/RTS style play and Encounter Director battles!",
        distance = 8.00,
        use_combat_distance = false,
        combat_distance = 8.00,
        extra_distance = 8.00,
        shoulder_x = 0.0,
        height_y = 0.50,
        pitch_deg = 32.0,
        forward_lead = 1.50,
        rts_mode = true,
        fov_enabled = false,
        fov_value = 60.0,
        combat_fov_offset = 0.0,
    },
}

local DEFAULT_CONFIG = {
    config_version = 3,
    enabled = true,
    active_preset_index = 1,       -- 2.9.4: a fresh install starts on the vanilla camera

    -- Distance Settings
    distance = 0.0,                -- Base / Exploration DistanceOffset via CameraManager
    use_combat_distance = false,   -- Automatically switch to combat_distance when in combat
    combat_distance = 0.0,         -- Combat DistanceOffset
    combat_trigger_mode = 1,       -- 1 = Battle Mode / Weapon Drawn / Enemies, 2 = Weapon Drawn Only, 3 = Nearby Enemies Only
    combat_enemy_radius = 24.0,    -- Radius (m) to detect active hostile enemies
    combat_linger_sec = 2.5,       -- Seconds to hold combat camera after sheathing / last enemy

    -- Post-Collision / Joint Framing Offsets
    extra_distance = 0.0,          -- Additional pull-back distance along camera Back axis
    shoulder_x = 0.0,              -- Horizontal offset magnitude (meters)
    shoulder_side = 1,             -- 1 = Right (+X), -1 = Left (-X)
    height_y = 0.0,                -- Vertical world Y offset (+Up, -Down)
    pitch_deg = 0.0,               -- Orbital downward look angle in degrees (0 = native pitch)
    forward_lead = 0.0,            -- Shifts camera forward along horizontal look direction

    -- RTS / Tactical Bird's-Eye Quick Toggle Settings
    rts_mode = false,
    rts_distance = 8.0,            -- Native DistanceOffset when RTS mode is toggled on
    rts_extra_distance = 8.0,      -- Extra orbital distance in RTS mode
    rts_height_y = 0.5,            -- Additional vertical height boost in RTS mode
    rts_pitch_deg = 32.0,          -- Downward orbital angle (degrees) in RTS mode
    rts_forward_lead = 1.5,        -- Forward battlefield lead (meters) in RTS mode

    -- Smooth Interpolation
    smooth_transitions = true,
    transition_speed = 6.0,

    -- Field of View (FOV)
    fov_enabled = false,
    fov_value = 60.0,
    combat_fov_offset = 0.0,

    -- Auto-Suspend Safeguards
    suspend_in_menus = true,
    suspend_in_cutscenes = true,
    suspend_when_aiming = true,

    -- Quick-Zoom & Hotkeys
    zoom_step = 0.75,
    enable_keyboard_hotkeys = false, -- 2.9.5: off until the player turns them on (vanilla by default)
    enable_mousewheel_zoom = false,
    mousewheel_modifier_key = 18,  -- 18 = Alt, 17 = Ctrl, 16 = Shift
    enable_gamepad_combos = false, -- Hold L1+R1 + D-Pad

    hotkeys = {
        zoom_in = 107,             -- Numpad +
        zoom_out = 109,            -- Numpad -
        swap_shoulder = 111,       -- Numpad /
        toggle_rts = 96,           -- Numpad 0
        cycle_preset = 106,        -- Numpad *
        toggle_mod = 0,
    },

    custom_presets = {},

    -- Couch co-op framing (v2.2): with DirectPawnControl co-op, pull back and centre between the Arisen and
    -- player 2's pawn so both stay on screen
    coop_framing = true,
    coop_start_dist = 4.0,         -- separation (m) before the camera starts pulling back
    coop_zoom_per_m = 0.45,        -- extra DistanceOffset per metre of separation beyond coop_start_dist
    coop_max_extra = 10.0,         -- cap on the extra distance
    coop_center = 0.5,             -- 0 = stay on the Arisen, 0.5 = midpoint, 1 = on the pawn
    coop_max_shift = 12.0,         -- cap on the sideways camera shift (m)
    -- v2.2.1 experiment: the co-op shift makes nametags flicker. The joint offset is applied after lateUpdate and
    -- restored before the next update, so anything that reads the camera in between sees the unshifted pose.
    -- false = leave the offset in place (the next lateUpdate rebuilds it from the controller's own _Position).
    native_offsets = true,        -- 2.9.0: shoulder / height / forward lead / extra distance through the game's own
                                  -- camera update (no nametag flicker); only RTS pitch still uses the joint
    joint_restore = true,         -- unused since 2.4.0 (the pose is always restored again)
    -- 2.3.0 "fit both" framing: pull back as far as needed to fit both characters, using the camera's FOV and
    -- aspect; shift fully toward the midpoint sideways but only partly along the view direction (a full shift
    -- along the view pushed the nearer character off the bottom of the screen in the 2.2 test).
    coop_fit = true,
    coop_center_depth = 0.25,      -- share of the along-view separation the camera moves toward the pawn
    coop_margin = 2.0,             -- extra half-width (m) kept around the two characters
    coop_base_dist = 5.7,          -- vanilla camera distance from the Arisen (measured)
    coop_depth_factor = 0.6,       -- pull-back per metre of along-view separation
    coop_fit_cap = 30.0,     -- cap on the fit pull-back (m)
    coop_aim_fov_max = 50.0,       -- bow zoom limit: widest view while aiming (real vertical FOV; normal is 36)
    coop_aim_back_max = 4.0,       -- 2.8.0: bow zoom limit: furthest the aim camera may pull back (m)
    coop_aim_zoom_limit = false,   -- 2.7.0: in co-op, widen the bow-aim zoom just enough to keep player 2's pawn in view
    safe_169 = false,              -- 2.9.5: off by default (an ultrawide player wants the whole screen used). 2.9.3: on screens wider than 16:9, frame co-op and place the marker for the middle
                                   -- 16:9 (so a 16:9 recording shows both players); "auto", true or false
    coop_marker = true,            -- 2.6.0: edge marker pointing at player 2's pawn while he is off screen
    coop_arisen_fill = 0.45,       -- 2.5.0: how far off-centre the Arisen may be pushed (share of the half-screen; 0 = never)
    coop_fill = 0.8,               -- 2.4.0: keep both characters inside this share of the screen
}

local function deep_copy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = deep_copy(v)
    end
    return copy
end

local config = deep_copy(DEFAULT_CONFIG)

-- 2.8.2 Dev HUD status (TestGuide 2.0 shows it): data/dev_status/CameraDistance.json once a second
local dev = { errors = 0, last_error = nil, last_error_t = nil, save_ok = nil, next = 0 }
local function dev_error(where, err)
    dev.errors = dev.errors + 1
    dev.last_error, dev.last_error_t = where .. ": " .. tostring(err), os.clock()
end

local function save_config()
    -- 2.8.1: the file stopped updating on 2026-11-12 (new co-op options were lost on every script reset); log why
    local ok, res = pcall(json.dump_file, CONFIG_FILE, config)
    dev.save_ok = ok and res ~= false
    if not dev.save_ok then
        log.info("[CameraDistance] save_config failed: " .. tostring(res))
        dev_error("save_config", res)
    end
end

local function load_config()
    local loaded = json.load_file(CONFIG_FILE)
    if type(loaded) == "table" then
        local is_v1 = (loaded.distance ~= nil and loaded.use_combat_distance == nil and loaded.hotkeys == nil)
        local is_pre_v2_1 = (loaded.config_version == nil or loaded.config_version < 2)
        for k, v in pairs(loaded) do
            if type(v) == "table" and type(config[k]) == "table" then
                for sk, sv in pairs(v) do
                    config[k][sk] = sv
                end
            else
                config[k] = v
            end
        end
        if is_v1 then
            config.combat_distance = loaded.distance
            config.use_combat_distance = false
        elseif is_pre_v2_1 and not config.rts_mode then
            -- Clear non-zero pitch_deg that v2.0 presets set on standard 3rd-person presets
            config.pitch_deg = 0.0
        end
        -- 2.9.5: quick-zoom keys and wheel became opt-in. Settings files from before that carry the old "on"
        -- defaults, so turn them off once; the player can turn them back on and it sticks.
        if (loaded.config_version or 0) < 3 then
            config.enable_keyboard_hotkeys = false
            config.enable_mousewheel_zoom = false
            config.config_version = 3
            save_config()
        end
        config.config_version = 3
    end
end

load_config()

-- ==============================================================================
-- Runtime State & Smoothing Variables
-- ==============================================================================

local state = {
    cur_native_dist = 0.0,
    cur_extra_dist = 0.0,
    cur_shoulder_x = 0.0,
    cur_height_y = 0.0,
    cur_pitch_deg = 0.0,
    cur_forward_lead = 0.0,
    cur_fov = 60.0,

    initialized = false,
    was_enabled = false,
    vanilla_fov = nil,
    fov_was_overridden = false,
    last_clock = os.clock(),
    combat_last_active_time = -100.0,

    -- Saved unmodified joint pose so we can restore before MainCameraController.update
    saved_joint = nil,
    saved_orig_pos = nil,
    saved_orig_rot = nil,

    is_in_combat = false,
    combat_reason = "None",
    is_suspended = false,
    suspend_reason = "None",

    last_cam_pos = nil,
    last_pivot_pos = nil,
    status_msg = "Ready (v2.1)",

    new_preset_name = "My Custom Camera",

    -- co-op framing
    enemy_scan_next = 0.0, enemy_scan_result = false, tick_error_logged = false,
    coop_active = false, coop_idx = 0, coop_name = "", coop_next_poll = 0.0, coop_fail = 0,
    coop_sep = 0.0, coop_extra = 0.0, coop_shift_x = 0.0, coop_shift_z = 0.0,
    hotkey_rebinding = nil,
}

-- ==============================================================================
-- Input Handling (Keyboard, Mouse Wheel, Gamepad)
-- ==============================================================================

local input = {
    kb_singleton = nil,
    kb_type = nil,
    ms_singleton = nil,
    ms_type = nil,
    gp_type = nil,
    key_down_prev = {},
    gp_btn_prev = 0,
}

local function init_input()
    pcall(function()
        input.kb_singleton = sdk.get_native_singleton("via.hid.Keyboard")
        input.kb_type = sdk.find_type_definition("via.hid.Keyboard")
        input.ms_singleton = sdk.get_native_singleton("via.hid.Mouse")
        input.ms_type = sdk.find_type_definition("via.hid.Mouse")
        input.gp_type = sdk.find_type_definition("via.hid.GamePad")
    end)
end
init_input()

local function get_kb_device()
    if not input.kb_type then return nil end
    local ok, dev = pcall(function()
        if input.kb_singleton then
            return sdk.call_native_func(input.kb_singleton, input.kb_type, "get_Device")
        end
        local m = input.kb_type:get_method("get_Device")
        return m and m:call(nil)
    end)
    return ok and dev or nil
end

local function is_key_down(vk)
    if not vk or vk <= 0 then return false end
    local dev = get_kb_device()
    if not dev then return false end
    local ok, down = pcall(function() return dev:call("isDown", vk) end)
    if ok and down == true then return true end
    if vk == 18 then
        local ok1, d1 = pcall(function() return dev:call("isDown", 164) or dev:call("isDown", 165) end)
        if ok1 and d1 then return true end
    elseif vk == 17 then
        local ok1, d1 = pcall(function() return dev:call("isDown", 162) or dev:call("isDown", 163) end)
        if ok1 and d1 then return true end
    elseif vk == 16 then
        local ok1, d1 = pcall(function() return dev:call("isDown", 160) or dev:call("isDown", 161) end)
        if ok1 and d1 then return true end
    end
    return false
end

local function is_key_triggered(vk)
    if not vk or vk <= 0 then return false end
    local down = is_key_down(vk)
    local was_down = input.key_down_prev[vk] == true
    input.key_down_prev[vk] = down
    return down and not was_down
end

local function get_mouse_wheel_delta()
    if not input.ms_type then return 0.0 end
    local ok, delta = pcall(function()
        local dev = nil
        if input.ms_singleton then
            dev = sdk.call_native_func(input.ms_singleton, input.ms_type, "get_Device")
        else
            local m = input.ms_type:get_method("get_Device")
            dev = m and m:call(nil)
        end
        if not dev then return 0.0 end
        local ok_w, w = pcall(function() return dev:call("get_Wheel") end)
        if ok_w and type(w) == "number" and w ~= 0 then return w end
        return 0.0
    end)
    return (ok and type(delta) == "number") and delta or 0.0
end

local function get_gamepad_buttons()
    if not input.gp_type then return 0 end
    local ok, btns = pcall(function()
        local m = input.gp_type:get_method("get_MergedDevice")
        local dev = m and m:call(nil)
        if not dev then return 0 end
        return dev:call("get_Button") or 0
    end)
    return (ok and type(btns) == "number") and btns or 0
end

local KEY_NAMES = {
    [0] = "None",
    [16] = "Shift", [17] = "Ctrl", [18] = "Alt",
    [33] = "PageUp", [34] = "PageDown", [35] = "End", [36] = "Home",
    [45] = "Insert", [46] = "Delete",
    [66] = "B", [67] = "C", [71] = "G", [72] = "H", [86] = "V", [88] = "X", [90] = "Z",
    [96] = "Num 0", [97] = "Num 1", [98] = "Num 2", [99] = "Num 3",
    [100] = "Num 4", [101] = "Num 5", [102] = "Num 6", [103] = "Num 7",
    [104] = "Num 8", [105] = "Num 9",
    [106] = "Num *", [107] = "Num +", [109] = "Num -", [110] = "Num .", [111] = "Num /",
    [112] = "F1", [113] = "F2", [114] = "F3", [115] = "F4", [116] = "F5",
    [117] = "F6", [118] = "F7", [119] = "F8", [120] = "F9", [121] = "F10", [122] = "F11",
    [187] = "Equals (+)", [189] = "Minus (-)", [219] = "Left Bracket [", [221] = "Right Bracket ]",
}

local function get_key_name(vk)
    if not vk or vk <= 0 then return "Unbound" end
    if KEY_NAMES[vk] then return string.format("%s (%d)", KEY_NAMES[vk], vk) end
    if vk >= 65 and vk <= 90 then
        return string.format("%s (%d)", string.char(vk), vk)
    end
    return string.format("Key %d", vk)
end

-- ==============================================================================
-- Engine Singletons & Player / Context Detection
-- ==============================================================================

local function get_camera_manager()
    return sdk.get_managed_singleton("app.CameraManager")
end

local function get_main_camera_controller(cam_mgr)
    cam_mgr = cam_mgr or get_camera_manager()
    if not cam_mgr then return nil end
    local ok, ctrl = pcall(function() return cam_mgr:call("getMainCameraController", 0) end)
    return ok and ctrl or nil
end

local function get_manual_player()
    local cm = sdk.get_managed_singleton("app.CharacterManager")
    if not cm then return nil end
    local ok, player = pcall(function() return cm:call("get_ManualPlayer") end)
    if ok and player then return player end
    local ok2, player2 = pcall(function() return cm:get_field("<ManualPlayer>k__BackingField") end)
    return ok2 and player2 or nil
end

local function get_player_position(player)
    player = player or get_manual_player()
    if not player then return nil end
    local ok, pos = pcall(function()
        local xform = player:call("get_Transform")
        if not xform then
            local go = player:call("get_GameObject")
            xform = go and go:call("get_Transform")
        end
        return xform and xform:call("get_Position")
    end)
    return ok and pos or nil
end

-- Detect if the game is paused, in a cutscene/event/dialogue, or aiming
-- 2.9.7: the checks here used to be get_IsAim / get_IsShootAim on the player and its Human. Neither exists
-- in the game (type index, dd2.exe 4.1.0.0), and REFramework answers nil for an unknown method, so this was
-- always false. The bow / magick bow aim is camera control type 7 (app.CameraDefine.ControlType.Aim) on the
-- main camera controller (seen live in DirectPawnControl's archer-aim-1 probe).
local CONTROL_TYPE_AIM = 7
local function is_player_aiming(main_ctrl)
    if not main_ctrl then return false end
    local ok, ct = pcall(main_ctrl.call, main_ctrl, "get_CurrentControlType")
    if not ok then return false end
    if type(ct) == "userdata" then
        local ok_v, v = pcall(ct.get_field, ct, "value__")
        ct = ok_v and v or nil
    end
    return ct == CONTROL_TYPE_AIM
end

local function check_suspend_state(player, cam_mgr, main_ctrl)
    if config.suspend_in_menus then
        local gui_mgr = sdk.get_managed_singleton("app.GuiManager")
        if gui_mgr then
            local ok_p, is_paused = pcall(function() return gui_mgr:call("isPausedGUI") end)
            if ok_p and is_paused == true then
                return true, "Menu / Paused"
            end
        end
    end

    -- Native MainCameraController:get_CurrentPlayerCamera() returns false during cutscenes, talks, & non-player cameras!
    if config.suspend_in_cutscenes and main_ctrl then
        local ok_pc, is_pl_cam = pcall(function() return main_ctrl:call("get_CurrentPlayerCamera") end)
        if ok_pc and is_pl_cam == false then
            -- 2.9.8: the bow aim camera also answers "not the player camera", so this check caught aiming first
            -- and the status read "Event/Talk" while aiming. Same suspension, the right name.
            if config.suspend_when_aiming and is_player_aiming(main_ctrl) then return true, "Aiming" end
            return true, "Non-Player Camera (Event/Talk)"
        end
    end

    if config.suspend_when_aiming and is_player_aiming(main_ctrl) then
        return true, "Aiming"
    end

    return false, "None"
end

-- Detect if the player is in combat
local function check_combat_state(player, player_pos, main_ctrl, now)
    if not player then return false, "No Player" end

    local mode = config.combat_trigger_mode or 1
    local weapon_drawn = false
    local battle_cam = false
    local enemies_nearby = false

    -- A. Check weapon drawn & native MainCameraController:get_IsBattleMode()
    if mode == 1 or mode == 2 then
        pcall(function()
            if main_ctrl and mode == 1 and main_ctrl:call("get_IsBattleMode") == true then
                battle_cam = true
            end
            -- 2.9.7: app.Character.get_IsDrawedWeapon is the real getter. The names tried before
            -- (get_IsDrawWeapon, get_IsBattle, Weapon.get_IsDraw) do not exist, so "weapon drawn" never fired.
            if player:call("get_IsDrawedWeapon") == true then
                weapon_drawn = true
            end
        end)
    end

    -- B. Check nearby live hostile enemies
    if (mode == 1 or mode == 3) and not weapon_drawn and not battle_cam and player_pos and now < state.enemy_scan_next then
        enemies_nearby = state.enemy_scan_result
    elseif (mode == 1 or mode == 3) and not weapon_drawn and not battle_cam and player_pos then
        -- the enemy list scan is the expensive part: 4 times a second is plenty for a 2.5 s linger
        state.enemy_scan_next = now + 0.25
        local r_sq = (config.combat_enemy_radius or 24.0) ^ 2
        pcall(function()
            local em = sdk.get_managed_singleton("app.EnemyManager")
            local list = em and em:get_field("_EnemyList")
            if not list then return end
            local count = list:call("get_Count") or 0
            for i = 0, math.min(count - 1, 48) do
                local entry = list:call("get_Item", i) or list[i]
                local chara = entry and entry:get_field("_Chara")
                if chara then
                    local is_dead = chara:call("get_IsDead")
                    if not is_dead then -- 2.9.7: dropped a get_IsThinkStop check; app.Character has no such method
                        local e_xform = chara:get_field("<Transform>k__BackingField") or chara:call("get_Transform")
                        local e_pos = e_xform and e_xform:call("get_Position")
                        if e_pos then
                            local dx = e_pos.x - player_pos.x
                            local dy = e_pos.y - player_pos.y
                            local dz = e_pos.z - player_pos.z
                            if (dx * dx + dy * dy + dz * dz) <= r_sq then
                                enemies_nearby = true
                                break
                            end
                        end
                    end
                end
            end
        end)
    end

    if (mode == 1 or mode == 3) and state.enemy_scan_next > now then state.enemy_scan_result = enemies_nearby end

    if weapon_drawn then
        state.combat_last_active_time = now
        return true, "Weapon Drawn"
    elseif battle_cam then
        state.combat_last_active_time = now
        return true, "Battle Camera"
    elseif enemies_nearby then
        state.combat_last_active_time = now
        return true, "Enemies Nearby"
    elseif (now - state.combat_last_active_time) < (config.combat_linger_sec or 2.5) then
        return true, "Combat Cooldown"
    end

    return false, "Exploration"
end

-- ==============================================================================
-- Preset Management
-- ==============================================================================

local function apply_preset_table(p)
    if not p then return end
    if p.distance ~= nil then config.distance = p.distance end
    if p.use_combat_distance ~= nil then config.use_combat_distance = p.use_combat_distance end
    if p.combat_distance ~= nil then config.combat_distance = p.combat_distance end
    if p.extra_distance ~= nil then config.extra_distance = p.extra_distance end
    if p.shoulder_x ~= nil then
        config.shoulder_x = math.abs(p.shoulder_x)
        if p.shoulder_x < -0.001 then
            config.shoulder_side = -1
        elseif p.shoulder_x > 0.001 then
            config.shoulder_side = 1
        end
    end
    if p.height_y ~= nil then config.height_y = p.height_y end
    if p.pitch_deg ~= nil then config.pitch_deg = p.pitch_deg end
    if p.forward_lead ~= nil then config.forward_lead = p.forward_lead end
    if p.rts_mode ~= nil then config.rts_mode = p.rts_mode end
    if p.fov_enabled ~= nil then config.fov_enabled = p.fov_enabled end
    if p.fov_value ~= nil then config.fov_value = p.fov_value end
    if p.combat_fov_offset ~= nil then config.combat_fov_offset = p.combat_fov_offset end
    save_config()
end

local function apply_builtin_preset(idx)
    local p = BUILTIN_PRESETS[idx]
    if not p then return end
    config.active_preset_index = idx
    apply_preset_table(p)
    state.status_msg = "Applied preset: " .. p.name
end

local function cycle_next_preset()
    local next_idx = ((config.active_preset_index or 1) % #BUILTIN_PRESETS) + 1
    apply_builtin_preset(next_idx)
end

local function adjust_active_zoom(delta)
    if config.rts_mode then
        config.rts_extra_distance = math.max(-2.0, math.min(40.0, (config.rts_extra_distance or 8.0) + delta))
        state.status_msg = string.format("RTS Orbital Zoom: %+.2fm", config.rts_extra_distance)
    elseif config.use_combat_distance and state.is_in_combat then
        config.combat_distance = math.max(-2.5, math.min(25.0, (config.combat_distance or 3.5) + delta))
        state.status_msg = string.format("Combat Distance: %+.2fm", config.combat_distance)
    else
        config.distance = math.max(-2.5, math.min(25.0, (config.distance or 0.0) + delta))
        state.status_msg = string.format("Distance Offset: %+.2fm", config.distance)
    end
    save_config()
end

-- ==============================================================================
-- Core Camera Math & Frame Updates
-- ==============================================================================

local function lerp(a, b, t)
    return a + (b - a) * t
end

-- DirectPawnControl writes reframework/data/DPC_coop.json when couch co-op starts/stops.
local function poll_coop_status(now)
    if now < state.coop_next_poll then return end
    -- json.load_file logs an error for a missing file; back off when DPC isn't installed
    state.coop_next_poll = now + ((state.coop_fail > 3) and 30.0 or 1.0)
    local ok, d = pcall(json.load_file, "DPC_coop.json")
    if ok and type(d) == "table" then
        state.coop_fail = 0
        state.coop_active = d.active == true
        state.coop_idx = tonumber(d.pawn_idx) or 0
        state.coop_name = tostring(d.pawn_name or "")
    else
        state.coop_fail = state.coop_fail + 1
        state.coop_active = false
    end
end

local function get_coop_pawn_position()
    local pm = sdk.get_managed_singleton("app.PawnManager")
    if not pm then return nil end
    local ok, pos = pcall(function()
        local list = pm:call("get_PawnCharacterList")
        local chara = list and list:call("get_Item", state.coop_idx)
        local xf = chara and chara:call("get_Transform")
        return xf and xf:call("get_Position")
    end)
    return ok and pos or nil
end

local function reset_camera_to_vanilla()
    local cam_mgr = get_camera_manager()
    if cam_mgr then
        pcall(function() cam_mgr:call("set_DistanceOffset", 0.0) end)
    end
    if state.fov_was_overridden and state.vanilla_fov then
        local pri_cam = sdk.get_primary_camera()
        if pri_cam then
            pcall(function() pri_cam:call("set_FOV", state.vanilla_fov) end)
        end
        state.fov_was_overridden = false
    end
    state.cur_native_dist = 0.0
    state.cur_extra_dist = 0.0
    state.cur_shoulder_x = 0.0
    state.cur_height_y = 0.0
    state.cur_pitch_deg = 0.0
    state.cur_forward_lead = 0.0
    state.coop_extra, state.coop_shift_x, state.coop_shift_z = 0.0, 0.0, 0.0
end

re.on_script_reset(function()
    reset_camera_to_vanilla()
end)

-- Per-frame camera logic. v2.1 ran this from re.on_frame (the render thread) while it called into the game
-- (GuiManager, EnemyManager, CameraManager, the primary camera); v2.2 runs it on the game thread, before
-- MainCameraController.lateUpdate reads DistanceOffset and our joint offsets.
-- 2.9.6 world guard: nothing here touches the camera or the player while the game is not in the game phase
-- (MainFlowManager.IsInGamePhase false: title, loading a save). Precaution after the access violations logged during a save load on
-- 2026-11-16 (caught by REFramework; not attributable to a mod from the log). Resumes 1 s after the world is back.
local function world_ok()
    local now = os.clock()
    local okc, good = pcall(function()
        local mf = sdk.get_managed_singleton("app.MainFlowManager")
        if mf and mf:call("get_IsInGamePhase") == false then return false end
        return true
    end)
    if not (okc and good == true) then state.world_bad_t = now; return false end
    return now - (state.world_bad_t or -10.0) >= 1.0
end

local function camera_tick()
    local now = os.clock()
    local dt = math.min(0.1, math.max(0.0001, now - state.last_clock))
    state.last_clock = now
    if not world_ok() then state.initialized = false; return end

    local cam_mgr = get_camera_manager()

    -- Handle Hotkey Rebinding in UI if active
    if state.hotkey_rebinding then
        for vk = 8, 222 do
            if vk ~= 1 and vk ~= 2 and vk ~= 45 and is_key_triggered(vk) then
                if vk == 27 then
                    state.hotkey_rebinding = nil
                    state.status_msg = "Hotkey rebind cancelled"
                else
                    config.hotkeys[state.hotkey_rebinding] = vk
                    state.status_msg = string.format("Bound '%s' to %s", state.hotkey_rebinding, get_key_name(vk))
                    state.hotkey_rebinding = nil
                    save_config()
                end
                break
            end
        end
    else
        -- Poll Keyboard Hotkeys
        if config.enable_keyboard_hotkeys and config.hotkeys then
            if config.hotkeys.toggle_mod and config.hotkeys.toggle_mod > 0 and is_key_triggered(config.hotkeys.toggle_mod) then
                config.enabled = not config.enabled
                if not config.enabled then
                    reset_camera_to_vanilla()
                end
                state.status_msg = config.enabled and "Mod Enabled" or "Mod Disabled (Reset to Vanilla)"
                save_config()
            end

            if config.enabled then
                if is_key_triggered(config.hotkeys.zoom_out) then
                    adjust_active_zoom(config.zoom_step or 0.75)
                elseif is_key_triggered(config.hotkeys.zoom_in) then
                    adjust_active_zoom(-(config.zoom_step or 0.75))
                elseif is_key_triggered(config.hotkeys.swap_shoulder) then
                    config.shoulder_side = (config.shoulder_side == -1) and 1 or -1
                    state.status_msg = (config.shoulder_side == 1) and "Shoulder: Right (+X)" or "Shoulder: Left (-X)"
                    save_config()
                elseif is_key_triggered(config.hotkeys.toggle_rts) then
                    config.rts_mode = not config.rts_mode
                    state.status_msg = config.rts_mode and "RTS Tactical Camera: ON" or "RTS Tactical Camera: OFF"
                    save_config()
                elseif is_key_triggered(config.hotkeys.cycle_preset) then
                    cycle_next_preset()
                end
            end
        end

        -- Poll Mouse Wheel + Modifier Key Quick-Zoom
        if config.enabled and config.enable_mousewheel_zoom then
            local mod_vk = config.mousewheel_modifier_key or 18
            if mod_vk == 0 or is_key_down(mod_vk) then
                local wheel = get_mouse_wheel_delta()
                if math.abs(wheel) > 0.001 then
                    local dir = (wheel > 0) and -1.0 or 1.0
                    adjust_active_zoom(dir * (config.zoom_step or 0.75))
                end
            end
        end

        -- Poll Optional Gamepad Combos (Hold L1 [256] + R1 [1024] + D-Pad)
        if config.enabled and config.enable_gamepad_combos and not state.coop_active then
            local btns = get_gamepad_buttons()
            local prev = input.gp_btn_prev
            input.gp_btn_prev = btns
            local l1_r1 = (btns & 256 ~= 0) and (btns & 1024 ~= 0)
            if l1_r1 then
                local just_pressed = btns & (~prev)
                if (just_pressed & 1) ~= 0 then
                    adjust_active_zoom(-(config.zoom_step or 0.75))
                elseif (just_pressed & 2) ~= 0 then
                    adjust_active_zoom(config.zoom_step or 0.75)
                elseif (just_pressed & 4) ~= 0 then
                    config.shoulder_side = (config.shoulder_side == -1) and 1 or -1
                    save_config()
                elseif (just_pressed & 8) ~= 0 then
                    config.rts_mode = not config.rts_mode
                    save_config()
                end
            end
        end
    end

    if not config.enabled then
        if state.was_enabled then
            reset_camera_to_vanilla()
            state.was_enabled = false
        end
        return
    end
    state.was_enabled = true

    if not cam_mgr then return end

    local main_ctrl = get_main_camera_controller(cam_mgr)
    local player = get_manual_player()
    local player_pos = get_player_position(player)

    -- Check Suspend & Combat Contexts
    state.is_suspended, state.suspend_reason = check_suspend_state(player, cam_mgr, main_ctrl)
    state.aim_now = is_player_aiming(main_ctrl)
    if not state.aim_now and not (config.fov_enabled) then
        -- remember the un-aimed FOV: the zoom limit never widens past it
        pcall(function()
            local f = sdk.get_primary_camera():call("get_FOV")
            if type(f) == "number" and f > 5.0 and f < 150.0 then state.normal_fov = f end
        end)
    end
    state.is_in_combat, state.combat_reason = check_combat_state(player, player_pos, main_ctrl, now)

    -- Determine Target Parameters based on Active Context
    local target_native_dist = 0.0
    local target_extra_dist = 0.0
    local target_shoulder_x = 0.0
    local target_height_y = 0.0
    local target_pitch_deg = 0.0
    local target_forward_lead = 0.0

    if not state.is_suspended then
        if config.rts_mode then
            target_native_dist = config.rts_distance or 8.0
            target_extra_dist = config.rts_extra_distance or 8.0
            target_shoulder_x = 0.0
            target_height_y = config.rts_height_y or 0.5
            target_pitch_deg = config.rts_pitch_deg or 32.0
            target_forward_lead = config.rts_forward_lead or 1.5
        else
            if config.use_combat_distance and state.is_in_combat then
                target_native_dist = config.combat_distance or config.distance
            else
                target_native_dist = config.distance or 0.0
            end
            target_extra_dist = config.extra_distance or 0.0
            target_shoulder_x = (config.shoulder_x or 0.0) * (config.shoulder_side or 1)
            target_height_y = config.height_y or 0.0
            target_pitch_deg = config.pitch_deg or 0.0
            target_forward_lead = config.forward_lead or 0.0
        end
    end

    -- Couch co-op framing: pull back with the Arisen <-> pawn separation and shift toward the midpoint
    poll_coop_status(now)
    local target_coop_extra, target_sx, target_sz = 0.0, 0.0, 0.0
    if config.coop_framing and state.coop_active and not state.is_suspended and player_pos then
        local pp = get_coop_pawn_position()
        if pp then
            local dx, dz = pp.x - player_pos.x, pp.z - player_pos.z
            local sep = math.sqrt(dx * dx + dz * dz)
            state.coop_sep = sep
            local fx, fz = nil, nil
            if config.coop_fit ~= false then
                pcall(function()
                    local q = sdk.get_primary_camera():call("get_GameObject"):call("get_Transform"):call("get_Rotation")
                    local bx = 2.0 * (q.x * q.z + q.w * q.y)
                    local bz = 1.0 - 2.0 * (q.x * q.x + q.y * q.y)
                    local l = math.sqrt(bx * bx + bz * bz)
                    if l > 0.001 then fx, fz = -bx / l, -bz / l end
                end)
            end
            if sep < 80.0 and fx then
                -- 2.4.0 frustum solver. The view direction belongs to player 1, so the only free variable is how
                -- far back the camera sits. Each character must be inside the view pyramid: far enough ahead of the
                -- camera that (a) its sideways offset fits the horizontal FOV and (b) its feet fit the vertical FOV.
                -- Take the smallest pull-back that satisfies both. Ahead and near the centre line needs none.
                -- The 2.2/2.3 sideways joint shift is not used: it only reached the screen on some frames (that
                -- was the nametag flicker) and not at all with the 2.2.1 switch.
                local rx, rz = fz, -fx
                local side = dx * rx + dz * rz             -- + = pawn to the right of the Arisen on screen
                local depth = dx * fx + dz * fz            -- + = pawn farther from the camera than the Arisen
                local vfov, aspect, cosp, sinp = 36.0, state.coop_aspect or (16.0 / 9.0), 1.0, 0.0
                pcall(function()
                    local cam = sdk.get_primary_camera()
                    vfov = cam:call("get_FOV") or vfov
                    local q = cam:call("get_GameObject"):call("get_Transform"):call("get_Rotation")
                    local bx = 2.0 * (q.x * q.z + q.w * q.y)
                    local by = 2.0 * (q.y * q.z - q.w * q.x)
                    local bz = 1.0 - 2.0 * (q.x * q.x + q.y * q.y)
                    cosp = math.max(0.3, math.sqrt(bx * bx + bz * bz))
                    sinp = by                              -- + = camera looks down
                end)
                if type(vfov) ~= "number" or vfov <= 0 then vfov = 36.0 elseif vfov < 3.2 then vfov = math.deg(vfov) end
                if not state.coop_aspect then
                    pcall(function()
                        local ds = imgui.get_display_size()
                        if ds and ds.y > 0 then state.coop_aspect = ds.x / ds.y; aspect = state.coop_aspect end
                    end)
                end
                do -- 2.9.3: frame for the middle 16:9 when asked
                    local safe = config.safe_169
                    if safe == "auto" then safe = aspect > 1.9 end
                    if safe and aspect > 16.0 / 9.0 then aspect = 16.0 / 9.0 end
                end
                local fill = config.coop_fill or 0.8
                local tan_v = math.tan(math.rad(vfov) * 0.5)
                local k = math.max(0.2, tan_v * aspect * fill)
                local kA = math.max(0.0, tan_v * aspect * math.min(fill, config.coop_arisen_fill or 0.45))
                local pitch = math.atan(sinp, cosp)
                local base = 5.5
                pcall(function()
                    local ctrl = cam_mgr:call("getMainCameraController", 0)
                    local cur = ctrl and ctrl:call("get_CurrentCameraController")
                    local bd = cur and cur:call("get_BaseDistance")
                    if type(bd) == "number" and bd > 0.5 then base = bd end
                end)
                local along0 = base + state.cur_native_dist          -- camera distance without the co-op extra
                local need = along0 * cosp
                local lim_v = math.max(0.15, math.tan(pitch + math.atan(tan_v * fill)))
                local dy = player_pos.y - pp.y                       -- + = pawn stands lower than the Arisen
                local min_front = 0.0
                for _ = 1, 3 do
                    local cam_h = 1.5 + (need / cosp) * sinp + dy    -- camera height above the pawn's feet
                    min_front = math.min(40.0, math.max(2.0, cam_h / lim_v))
                    -- 2.5.0: the camera may also slide sideways by cs (native aim-point shift), which puts the
                    -- Arisen off-centre by cs. He may use up to kA of the half-screen, the pawn up to k:
                    --   |cs| <= kA * need   and   |side - cs| <= k * (depth + need)
                    -- so the smallest pull-back that has a solution is (|side| - k * depth) / (kA + k).
                    need = math.max(along0 * cosp, min_front - depth, (math.abs(side) - k * depth) / (kA + k))
                end
                local cs = math.max(0.0, math.abs(side) - k * (depth + need))   -- least shift that still fits the pawn
                cs = math.min(cs, kA * need)
                if side < 0 then cs = -cs end
                target_sx, target_sz = rx * cs, rz * cs
                state.coop_cs = cs
                target_coop_extra = math.min(config.coop_fit_cap or 30.0, math.max(0.0, need / cosp - along0))
                state.coop_fit_dbg = string.format("across %.1f  ahead %.1f  camera needs %.1f m behind the Arisen (normal %.1f)  slide %.1f  fov %.0f  aspect %.2f",
                    side, depth, need, along0 * cosp, cs, vfov, aspect)
            elseif sep < 80.0 then
                target_coop_extra = math.min(config.coop_max_extra or 10.0,
                    math.max(0.0, (sep - (config.coop_start_dist or 4.0)) * (config.coop_zoom_per_m or 0.45)))
                local c = config.coop_center or 0.5
                target_sx, target_sz = dx * c, dz * c
                local sl = math.sqrt(target_sx * target_sx + target_sz * target_sz)
                local mx = config.coop_max_shift or 12.0
                if sl > mx then target_sx, target_sz = target_sx / sl * mx, target_sz / sl * mx end
            end
        end
    end

    -- Smooth Interpolation
    local alpha = 1.0
    if config.smooth_transitions and state.initialized then
        local speed = math.max(0.5, config.transition_speed or 6.0)
        alpha = 1.0 - math.exp(-speed * dt)
    end
    state.initialized = true

    state.cur_native_dist = lerp(state.cur_native_dist, target_native_dist, alpha)
    state.cur_extra_dist = lerp(state.cur_extra_dist, target_extra_dist, alpha)
    state.cur_shoulder_x = lerp(state.cur_shoulder_x, target_shoulder_x, alpha)
    state.cur_height_y = lerp(state.cur_height_y, target_height_y, alpha)
    state.cur_pitch_deg = lerp(state.cur_pitch_deg, target_pitch_deg, alpha)
    state.cur_forward_lead = lerp(state.cur_forward_lead, target_forward_lead, alpha)
    -- 2.4.1: pull back fast (someone is leaving the frame), come back in slowly (no pumping while he weaves)
    local coop_alpha = alpha
    if state.initialized and dt then
        local sp = (target_coop_extra > state.coop_extra) and (config.coop_out_speed or 14.0) or (config.coop_in_speed or 2.5)
        coop_alpha = 1.0 - math.exp(-sp * dt)
    end
    state.coop_extra = lerp(state.coop_extra, target_coop_extra, coop_alpha)
    local shift_alpha = (state.initialized and dt) and (1.0 - math.exp(-(config.coop_shift_speed or 8.0) * dt)) or alpha
    state.coop_shift_x = lerp(state.coop_shift_x, target_sx, shift_alpha)
    state.coop_shift_z = lerp(state.coop_shift_z, target_sz, shift_alpha)

    -- 1. Apply Native DistanceOffset to app.CameraManager
    pcall(function()
        local ex = config.native_offsets and (state.cur_extra_dist or 0.0) or 0.0
        cam_mgr:call("set_DistanceOffset", state.cur_native_dist + state.coop_extra + ex)
    end)

    -- 2. Apply Optional FOV Override to Primary Camera
    local pri_cam = sdk.get_primary_camera()
    if pri_cam then
        pcall(function() -- 2.9.0: horizontal right / forward of the camera, for the native preset offsets
            local q = pri_cam:call("get_GameObject"):call("get_Transform"):call("get_Rotation")
            local bx = 2.0 * (q.x * q.z + q.w * q.y)
            local bz = 1.0 - 2.0 * (q.x * q.x + q.y * q.y)
            local l = math.sqrt(bx * bx + bz * bz)
            if l > 0.0001 then
                state.cam_fx, state.cam_fz = -bx / l, -bz / l
                state.cam_rx, state.cam_rz = -state.cam_fz, state.cam_fx
            end
        end)
        pcall(function()
            if not state.vanilla_fov then
                local cur_f = pri_cam:call("get_FOV")
                if type(cur_f) == "number" and cur_f > 10.0 and cur_f < 150.0 then
                    state.vanilla_fov = cur_f
                end
            end

            if config.fov_enabled and not state.is_suspended then
                local target_fov = config.fov_value or 60.0
                if state.is_in_combat and config.combat_fov_offset then
                    target_fov = target_fov + config.combat_fov_offset
                end
                state.cur_fov = lerp(state.cur_fov, target_fov, alpha)
                pri_cam:call("set_FOV", state.cur_fov)
                state.fov_was_overridden = true
            elseif state.fov_was_overridden and state.vanilla_fov then
                pri_cam:call("set_FOV", state.vanilla_fov)
                state.fov_was_overridden = false
            end
        end)
    end
end

re.on_pre_application_entry("LateUpdateBehavior", function()
    local ok, err = pcall(camera_tick)
    if not ok and not state.tick_error_logged then
        state.tick_error_logged = true
        log.info("[CameraDistance] camera tick error: " .. tostring(err))
    end
    if not ok then state.status_msg = "Error: " .. tostring(err); dev_error("camera tick", err) end
end)

-- ==============================================================================
-- Hooks on app.MainCameraController:
--   1. Pre-hook on update(): restores _CameraJoint's unmodified pose so the game's
--      camera update never experiences feedback/accumulation from our joint offsets.
--   2. Post-hook on lateUpdate(): applies Over-the-Shoulder (X), Height (Y),
--      Extra Distance (Z), Forward Lead, and RTS Orbital Pitch using local via.vec3
--      pivot (get_TargetPosition / get_Pog) and explicit (.x, .y, .z, .w) fields.
-- ==============================================================================

local function install_camera_controller_hooks()
    local td = sdk.find_type_definition("app.MainCameraController")
    if not td then return false end

    -- 2.5.0 co-op sideways shift: move the controller's aim point (_Pog) right after the game computes it.
    -- updatePosition then places the camera from the shifted point, so the whole camera slides by exactly
    -- that amount with the view direction unchanged, and everything in the frame sees one pose
    -- (TestGuide cam-shift-2, variant H: +3 m on _Pog -> camera +3.00 m, stable, no accumulation).
    local root_td = sdk.find_type_definition("app.PlayerCameraControllerRoot")
    local pog_m = root_td and root_td:get_method("updatePog")
    if pog_m then
        sdk.hook(pog_m, function(args)
            thread.get_hook_storage().pog_ctrl = sdk.to_managed_object(args[2])
        end, function(retval)
            local sx, sz, sy = state.coop_shift_x, state.coop_shift_z, 0.0
            -- 2.9.0: the preset offsets ride on the same native slide. Shoulder = camera right, lead = camera
            -- forward (both horizontal, from last frame's camera), height = world up.
            if config.native_offsets then
                local sh, ld = state.cur_shoulder_x or 0.0, state.cur_forward_lead or 0.0
                local rx, rz, fx, fz = state.cam_rx or 0.0, state.cam_rz or 0.0, state.cam_fx or 0.0, state.cam_fz or 0.0
                sx = sx + rx * sh + fx * ld
                sz = sz + rz * sh + fz * ld
                sy = state.cur_height_y or 0.0
            end
            if not config.enabled or (math.abs(sx) < 0.001 and math.abs(sz) < 0.001 and math.abs(sy) < 0.001) then return retval end
            pcall(function()
                local o = thread.get_hook_storage().pog_ctrl
                if not o then return end
                local mc = o:call("get_MainCameraController")
                if mc and mc:get_field("_Role") ~= 0 then return end
                local v = o:get_field("_Pog")
                v.x, v.y, v.z = v.x + sx, v.y + sy, v.z + sz
                o:set_field("_Pog", v)
            end)
            return retval
        end)
    end

    local update_method = td:get_method("update")
    if update_method then
        sdk.hook(
            update_method,
            function(args)
                if state.saved_joint and state.saved_orig_pos and state.saved_orig_rot then
                    pcall(function()
                        state.saved_joint:call("set_Position", state.saved_orig_pos)
                        state.saved_joint:call("set_Rotation", state.saved_orig_rot)
                    end)
                    state.saved_joint = nil
                end
            end,
            nil
        )
    end

    -- 2.9.1 RTS pitch through the controller (the joint path was the last nametag flicker). After the player
    -- camera controller's onUpdate has placed _Position / _Rotation, orbit them up around _Pog and tilt the view
    -- down by the same angle; MainCameraController.lateUpdate then copies one consistent pose to the joint before
    -- anything reads it. The fields are put back in the next onUpdate's pre-hook, so nothing accumulates.
    local upd_m = root_td and root_td:get_method("onUpdate")
    if upd_m then
        sdk.hook(upd_m, function(args)
            local o = sdk.to_managed_object(args[2])
            thread.get_hook_storage().upd_ctrl = o
            local sv = state.pitch_saved
            if sv and o and sv.addr == o:get_address() then
                pcall(function() o:set_field("_Position", sv.pos); o:set_field("_Rotation", sv.rot) end)
            end
            state.pitch_saved = nil
        end, function(retval)
            if not (config.enabled and config.native_offsets) then return retval end
            local pitch_deg = state.cur_pitch_deg or 0.0
            if math.abs(pitch_deg) < 0.01 then return retval end
            pcall(function()
                local o = thread.get_hook_storage().upd_ctrl
                if not o then return end
                -- (no type-name check: the live object is a subclass, app.UsuallyCameraController; 2.9.1 checked the
                -- name and so never ran)
                local mc = o:call("get_MainCameraController")
                if mc and mc:get_field("_Role") ~= 0 then return end
                local P, q, G = o:get_field("_Position"), o:get_field("_Rotation"), o:get_field("_Pog")
                if not (P and q and G) then return end
                local rx, ry, rz = P.x - G.x, P.y - G.y, P.z - G.z
                if rx * rx + ry * ry + rz * rz > 2500.0 then return end -- not local coordinates
                -- separate copies (get_field returns a new value each call), so no constructor-order questions
                state.pitch_saved = { addr = o:get_address(), pos = o:get_field("_Position"), rot = o:get_field("_Rotation") }
                -- the same orbit as the old joint path: keep the horizontal back distance and side offset,
                -- rotate (back, up) by the pitch, then post-multiply the rotation by local X (-pitch)
                local qx, qy, qz, qw = q.x, q.y, q.z, q.w
                local bx = 2.0 * (qx * qz + qw * qy)
                local bz = 1.0 - 2.0 * (qx * qx + qy * qy)
                local hl = math.sqrt(bx * bx + bz * bz)
                local hbx, hbz = 0.0, 1.0
                if hl > 0.0001 then hbx, hbz = bx / hl, bz / hl end
                local rel_back = rx * hbx + rz * hbz
                local rel_side = rx * (-hbz) + rz * hbx
                local base_dist = math.max(1.5, rel_back)
                local pr = math.rad(pitch_deg)
                local cp, sp = math.cos(pr), math.sin(pr)
                local orb_back = base_dist * cp - ry * sp
                local orb_up = ry * cp + base_dist * sp
                P.x = G.x + hbx * orb_back + (-hbz) * rel_side
                P.y = G.y + orb_up
                P.z = G.z + hbz * orb_back + hbx * rel_side
                local h = -pr * 0.5
                local sh, ch = math.sin(h), math.cos(h)
                q.w, q.x, q.y, q.z = qw * ch - qx * sh, qw * sh + qx * ch, qy * ch + qz * sh, qz * ch - qy * sh
                o:set_field("_Position", P)
                o:set_field("_Rotation", q)
                state.pitch_native_t = os.clock()
                state.pitch_native_n = (state.pitch_native_n or 0) + 1
            end)
            return retval
        end)
    end

    local late_method = td:get_method("lateUpdate")
    if not late_method then return false end

    -- 2.8.0 co-op bow zoom limit. The bow aim has its own controller (app.AimCameraController) whose onUpdate
    -- computes _Position / _Pog / _Fov; the camera then looks from _Position at _Pog. Verified live (TestGuide
    -- aim-zoom-exp-2): moving _Position back along the Pog->Position line pulls the aim camera back without
    -- turning it (3 m -> 3.5 m became 6.3 m), and writing _Fov changes the view (90 -> 54 real, factor 0.6).
    -- While player 2's pawn would be outside the aim view: pull back along the sightline first (up to
    -- coop_aim_back_max), then widen the FOV for the rest (up to coop_aim_fov_max).
    local aim_td = sdk.find_type_definition("app.AimCameraController")
    local aim_m = aim_td and aim_td:get_method("onUpdate")
    if aim_m then
        sdk.hook(aim_m, function(args)
            thread.get_hook_storage().aim_ctrl = sdk.to_managed_object(args[2])
        end, function(retval)
            if not (config.enabled and config.coop_aim_zoom_limit and state.coop_active) then
                state.zl_back, state.zl_fov, state.zl_dbg = nil, nil, nil
                return retval
            end
            pcall(function()
                local o = thread.get_hook_storage().aim_ctrl
                if not o then return end
                local mc = o:call("get_MainCameraController")
                if mc and mc:get_field("_Role") ~= 0 then return end
                local pp = get_coop_pawn_position()
                if not pp then return end
                local p, g = o:get_field("_Position"), o:get_field("_Pog")
                local fx, fy, fz = g.x - p.x, g.y - p.y, g.z - p.z
                local l = math.sqrt(fx * fx + fy * fy + fz * fz)
                if l < 0.01 then return end
                fx, fy, fz = fx / l, fy / l, fz / l
                local hl = math.sqrt(fx * fx + fz * fz)
                if hl < 0.01 then return end
                local rx, rz = -fz / hl, fx / hl                       -- horizontal right
                local ux, uy, uz = -fy * fx / hl, hl, -fy * fz / hl    -- camera up
                local vx, vy, vz = pp.x - p.x, (pp.y + 1.0) - p.y, pp.z - p.z
                local side = vx * rx + vz * rz
                local up = vx * ux + vy * uy + vz * uz
                local ahead = vx * fx + vy * fy + vz * fz
                local game_fov = o:get_field("_Fov") or 60.0           -- controller units; real vertical FOV = 0.6 x
                local aspect = state.coop_aspect or (16.0 / 9.0)
                local fill = config.coop_fill or 0.8
                local tan_v = math.tan(math.rad(game_fov * 0.6) * 0.5) * fill
                local need_ahead = math.max(math.abs(side) / (tan_v * aspect), (math.abs(up) + 1.0) / tan_v)
                local back_max = config.coop_aim_back_max or 4.0
                local want_back = math.min(back_max, math.max(0.0, need_ahead - ahead))
                local want_fov = game_fov
                local ahead2 = ahead + want_back
                if need_ahead > ahead2 + 0.01 and ahead2 > 0.5 then
                    local tv = math.max(math.abs(side) / aspect, math.abs(up) + 1.0) / ahead2 / fill
                    want_fov = math.deg(2.0 * math.atan(tv)) / 0.6
                    want_fov = math.max(game_fov, math.min((config.coop_aim_fov_max or 50.0) / 0.6, want_fov))
                elseif ahead2 <= 0.5 then
                    want_back = 0.0                                    -- he is behind the camera: leave the aim alone
                end
                local function ease(cur, tgt)
                    local sp = (tgt > cur) and 10.0 or 4.0
                    return cur + (tgt - cur) * (1.0 - math.exp(-sp * 0.0167))
                end
                state.zl_back = ease(state.zl_back or 0.0, want_back)
                state.zl_fov = ease(state.zl_fov or game_fov, want_fov)
                if state.zl_back > 0.01 then
                    p.x, p.y, p.z = p.x - fx * state.zl_back, p.y - fy * state.zl_back, p.z - fz * state.zl_back
                    o:set_field("_Position", p)
                end
                if state.zl_fov > game_fov + 0.05 then o:set_field("_Fov", state.zl_fov) end
                state.zl_dbg = string.format("aim: pawn %.1f across, %.1f ahead -> back %.1f m, view %.0f deg",
                    side, ahead, state.zl_back, state.zl_fov * 0.6)
            end)
            return retval
        end)
    end

    sdk.hook(
        late_method,
        function(args)
            thread.get_hook_storage().this_ctrl = sdk.to_managed_object(args[2])
        end,
        function(retval)
            if not config.enabled then return retval end

            local ctrl = thread.get_hook_storage().this_ctrl
            if not ctrl then return retval end

            -- Only modify the primary gameplay camera (_Role == 0)
            local ok_role, role = pcall(function() return ctrl:get_field("_Role") end)
            if ok_role and role ~= nil and role ~= 0 then
                return retval
            end

            local sx = state.cur_shoulder_x
            local hy = state.cur_height_y
            local ez = state.cur_extra_dist
            local pitch_deg = state.cur_pitch_deg
            local fwd_lead = state.cur_forward_lead
            if config.native_offsets then sx, hy, ez, fwd_lead = 0.0, 0.0, 0.0, 0.0 end -- 2.9.0: applied natively
            -- 2.9.1: pitch too, while the controller hook is doing it (falls back to the joint if it stops running)
            if config.native_offsets and os.clock() - (state.pitch_native_t or -10.0) < 0.5 then pitch_deg = 0.0 end

            -- Fast exit if all spatial/angle adjustments are near zero
            local csx, csz = 0.0, 0.0 -- 2.5.0: the co-op shift is applied natively in updatePog (see below), not on the joint
            if math.abs(sx) < 0.001 and math.abs(hy) < 0.001 and math.abs(ez) < 0.001
               and math.abs(pitch_deg) < 0.01 and math.abs(fwd_lead) < 0.001
               and math.abs(csx) < 0.001 and math.abs(csz) < 0.001 then
                return retval
            end

            pcall(function()
                local joint = ctrl:get_field("_CameraJoint")
                if not joint then return end

                -- Read the engine's freshly computed local via.vec3 position and via.Quaternion rotation
                local cam_pos = ctrl:get_field("_Position") or joint:call("get_Position")
                local cam_rot = ctrl:get_field("_Rotation") or joint:call("get_Rotation")
                if not cam_pos or not cam_rot then return end

                -- Save unmodified pose to restore on next update()
                state.saved_joint = joint
                state.saved_orig_pos = cam_pos
                state.saved_orig_rot = cam_rot

                local qx, qy, qz, qw = cam_rot.x, cam_rot.y, cam_rot.z, cam_rot.w

                -- Local +X (Right vector)
                local rx = 1.0 - 2.0 * (qy * qy + qz * qz)
                local ry = 2.0 * (qx * qy + qw * qz)
                local rz = 2.0 * (qx * qz - qw * qy)

                -- Local +Z (Back vector: points from look-at target toward camera)
                local bx = 2.0 * (qx * qz + qw * qy)
                local by = 2.0 * (qy * qz - qw * qx)
                local bz = 1.0 - 2.0 * (qx * qx + qy * qy)

                -- Horizontal forward unit vector (camera's horizontal look direction)
                local hfx, hfz = -bx, -bz
                local hlen = math.sqrt(hfx * hfx + hfz * hfz)
                if hlen > 0.0001 then
                    hfx = hfx / hlen
                    hfz = hfz / hlen
                else
                    hfx, hfz = 0.0, 1.0
                end

                local new_x = cam_pos.x
                local new_y = cam_pos.y
                local new_z = cam_pos.z
                local new_qx, new_qy, new_qz, new_qw = qx, qy, qz, qw
                local rot_modified = false

                -- 1. Orbital Pitch / RTS High-Angle Transformation around LOCAL via.vec3 Pivot
                if math.abs(pitch_deg) >= 0.01 then
                    local pivot = nil
                    -- Use local via.vec3 target position (NEVER get_TargetPositionPrev which is 64-bit Universal!)
                    pcall(function()
                        local cur_sub = ctrl:call("get_CurrentCameraController")
                        if cur_sub then
                            pivot = cur_sub:call("get_Pog")
                        end
                    end)
                    if not pivot then
                        pcall(function() pivot = ctrl:call("get_TargetPosition") end)
                    end
                    if not pivot then
                        local player_pos = get_player_position()
                        if player_pos then
                            pivot = Vector3f.new(player_pos.x, player_pos.y + 1.35, player_pos.z)
                        end
                    end

                    -- Verify pivot is in local coordinates near the camera (< 50m away)
                    if pivot then
                        local dx_check = new_x - pivot.x
                        local dy_check = new_y - pivot.y
                        local dz_check = new_z - pivot.z
                        if (dx_check * dx_check + dy_check * dy_check + dz_check * dz_check) > 2500.0 then
                            -- Fallback to a virtual pivot 4m in front of the camera along its look vector
                            pivot = Vector3f.new(new_x - bx * 4.0, new_y - by * 4.0, new_z - bz * 4.0)
                        end

                        state.last_pivot_pos = pivot
                        local rel_x = new_x - pivot.x
                        local rel_y = new_y - pivot.y
                        local rel_z = new_z - pivot.z

                        local hbx, hbz = -hfx, -hfz
                        local rel_back = rel_x * hbx + rel_z * hbz
                        local rel_side = rel_x * (-hbz) + rel_z * hbx

                        local base_dist = math.max(1.5, rel_back + ez)
                        ez = 0.0 -- Absorbed into orbital radius

                        local pitch_rad = math.rad(pitch_deg)
                        local cos_p = math.cos(pitch_rad)
                        local sin_p = math.sin(pitch_rad)

                        -- Orbit camera upward in the vertical plane while keeping distance from pivot
                        local orb_back = base_dist * cos_p - rel_y * sin_p
                        local orb_up   = rel_y * cos_p + base_dist * sin_p

                        new_x = pivot.x + hbx * orb_back + (-hbz) * rel_side
                        new_y = pivot.y + orb_up
                        new_z = pivot.z + hbz * orb_back + hbx * rel_side

                        -- Post-multiply cam_rot by local X pitch (-pitch_rad tilts look vector down)
                        local half_p = -pitch_rad * 0.5
                        local sx_p = math.sin(half_p)
                        local cx_p = math.cos(half_p)

                        new_qw = qw * cx_p - qx * sx_p
                        new_qx = qw * sx_p + qx * cx_p
                        new_qy = qy * cx_p + qz * sx_p
                        new_qz = qz * cx_p - qy * sx_p
                        rot_modified = true
                    end
                end

                -- 2. Apply Over-the-Shoulder (Right +X), Height (+World Y), Extra Distance (+Back), and Forward Lead
                new_x = new_x + rx * sx + bx * ez + hfx * fwd_lead + csx
                new_y = new_y + ry * sx + by * ez + hy
                new_z = new_z + rz * sx + bz * ez + hfz * fwd_lead + csz

                local j_pos = joint:call("get_Position")
                if j_pos then
                    j_pos.x = new_x
                    j_pos.y = new_y
                    j_pos.z = new_z
                    joint:call("set_Position", j_pos)
                    state.last_cam_pos = j_pos
                end

                -- Mutate .x, .y, .z, .w explicitly by field name (avoids glm::quat(w,x,y,z) order bug!)
                if rot_modified then
                    local j_rot = joint:call("get_Rotation")
                    if j_rot then
                        j_rot.x = new_qx
                        j_rot.y = new_qy
                        j_rot.z = new_qz
                        j_rot.w = new_qw
                        joint:call("set_Rotation", j_rot)
                    end
                end
            end)

            return retval
        end
    )
    return true
end

pcall(install_camera_controller_hooks)

-- ==============================================================================
-- ImGui User Interface
-- ==============================================================================

local function ui_colored(text, color)
    if imgui.text_colored then
        local ok = pcall(function() imgui.text_colored(text, color) end)
        if not ok then imgui.text(text) end
    else
        imgui.text(text)
    end
end

local function ui_tooltip(text)
    if imgui.is_item_hovered and imgui.is_item_hovered() and imgui.set_tooltip then
        imgui.set_tooltip(text)
    end
end

-- 2.6.0 off-screen marker: while player 2's pawn is outside the view (bow aiming, camera blocked by terrain, pull-back
-- cap reached), draw a dot with an arrow on the screen edge in his direction, with his name and distance.
local function draw_coop_marker()
    if not (config.enabled and config.coop_marker ~= false and state.coop_active) then return end
    local pp = get_coop_pawn_position()
    local cam = sdk.get_primary_camera()
    if not (pp and cam) then return end
    local ds = imgui.get_display_size()
    local W, Hh = ds.x, ds.y
    if not (W and Hh and W > 0 and Hh > 0) then return end
    local X0 = 0.0 -- 2.9.3: left edge of the area the marker lives in (middle 16:9 when asked)
    do
        local safe = config.safe_169
        if safe == "auto" then safe = (W / Hh) > 1.9 end
        if safe and W / Hh > 16.0 / 9.0 then local w = Hh * 16.0 / 9.0; X0 = (W - w) * 0.5; W = w end
    end
    local scr = draw.world_to_screen(Vector3f.new(pp.x, pp.y + 1.0, pp.z))
    if scr and scr.x >= X0 and scr.x <= X0 + W and scr.y >= 0 and scr.y <= Hh then return end
    local tr = cam:call("get_GameObject"):call("get_Transform")
    local c, q = tr:call("get_Position"), tr:call("get_Rotation")
    local bx = 2.0 * (q.x * q.z + q.w * q.y)
    local bz = 1.0 - 2.0 * (q.x * q.x + q.y * q.y)
    local l = math.sqrt(bx * bx + bz * bz)
    if l < 0.001 then return end
    local fx, fz = -bx / l, -bz / l
    local vx, vy, vz = pp.x - c.x, (pp.y + 1.0) - c.y, pp.z - c.z
    local right = -(vx * fz - vz * fx)          -- + = to the right on screen
    local ahead = vx * fx + vz * fz
    local dxs, dys = right, -vy
    if ahead > 0 and math.abs(right) < ahead * 0.2 and math.abs(vy) > 0.5 then dxs = right * 0.3 end
    if ahead <= 0 and math.abs(dxs) < 0.5 then dys = math.abs(vy) + 1.0 end   -- straight behind: point down
    local n = math.sqrt(dxs * dxs + dys * dys)
    if n < 0.001 then return end
    dxs, dys = dxs / n, dys / n
    local cx, cy = X0 + W * 0.5, Hh * 0.5
    local m = math.max(40.0, Hh * 0.05)
    local hx, hy = cx - m, cy - m
    local t = math.min(hx / math.max(0.0001, math.abs(dxs)), hy / math.max(0.0001, math.abs(dys)))
    local px, py = cx + dxs * t, cy + dys * t
    local r = math.max(10.0, Hh * 0.012)
    local col, dark = 0xFF33CCFF, 0xC0000000
    draw.filled_circle(px, py, r + 3, dark, 24)
    draw.filled_circle(px, py, r, col, 24)
    draw.line(px + dxs * (r + 4), py + dys * (r + 4), px + dxs * (r * 2.6), py + dys * (r * 2.6), col)
    draw.line(px + dxs * (r * 2.6), py + dys * (r * 2.6), px + dxs * (r * 1.7) - dys * r * 0.6, py + dys * (r * 1.7) + dxs * r * 0.6, col)
    draw.line(px + dxs * (r * 2.6), py + dys * (r * 2.6), px + dxs * (r * 1.7) + dys * r * 0.6, py + dys * (r * 1.7) - dxs * r * 0.6, col)
    local dist = math.sqrt(vx * vx + vy * vy + vz * vz)
    local label = string.format("%s  %.0f m", (state.coop_name ~= "" and state.coop_name) or "Player 2", dist)
    local tx = px - dxs * (r * 2 + 8) - (dxs > 0.3 and (#label * 9) or (dxs < -0.3 and 0 or #label * 4.5))
    local ty = py - dys * (r * 2 + 8) - 9
    draw.text(label, tx + 1, ty + 1, 0xFF000000)
    draw.text(label, tx, ty, 0xFFFFFFFF)
end

re.on_frame(function()
    local okm, merr = pcall(draw_coop_marker)
    if not okm then dev_error("coop marker", merr) end
    local now = os.clock()
    if now >= dev.next then
        dev.next = now + 1.0
        local info = (state.is_suspended and ("suspended: " .. tostring(state.suspend_reason)) or "active")
            .. (state.coop_active and (" | co-op +" .. string.format("%.1f", state.coop_extra or 0) .. " m") or "")
            .. (state.zl_dbg and " | zoom limit on" or "")
        if math.abs(state.cur_pitch_deg or 0.0) >= 0.01 then
            info = info .. string.format(" | pitch %.0f %s", state.cur_pitch_deg,
                (os.clock() - (state.pitch_native_t or -10.0) < 0.5) and "native" or "joint")
        end
        if state.dev_on == nil then -- 2.9.3: only with the developer tooling (data/DPC_dev.json)
            local okd, d = pcall(json.load_file, "DPC_dev.json")
            state.dev_on = okd and type(d) == "table" and d.dev == true
        end
        if state.dev_on then pcall(json.dump_file, "dev_status/CameraDistance.json", {
            mod = "CameraDistance", version = MOD_VERSION, t = now, errors = dev.errors,
            last_error = dev.last_error, last_error_t = dev.last_error_t, save_ok = dev.save_ok, info = info,
        }) end
    end
end)

re.on_draw_ui(function()
    if not imgui.tree_node(MOD_NAME .. " Studio v" .. MOD_VERSION) then return end

    local ok_ui, err_ui = pcall(function()
        local changed = false
        local c = false

        -- ======================================================================
        -- 1. Top Control Bar & Live Telemetry Banner
        -- ======================================================================
        c, config.enabled = imgui.checkbox("Enable Camera Mod", config.enabled)
        if c then
            changed = true
            if not config.enabled then
                reset_camera_to_vanilla()
            end
        end

        imgui.same_line()
        if imgui.button("Reset to Vanilla") then
            apply_builtin_preset(1)
            reset_camera_to_vanilla()
        end
        ui_tooltip("Reset all distance, shoulder, pitch, and FOV settings to unmodified vanilla defaults.")

        imgui.same_line()
        local rts_label = config.rts_mode and "[RTS Bird's-Eye: ACTIVE]" or "Toggle RTS / Bird's-Eye"
        if imgui.button(rts_label) then
            config.rts_mode = not config.rts_mode
            changed = true
        end
        ui_tooltip("Instantly toggle high-angle RTS / Tactical overhead camera mode.")

        -- Live State Banner
        if not config.enabled then
            ui_colored("Status: DISABLED (Vanilla Camera Active)", 0xFF888888)
        elseif state.is_suspended then
            ui_colored(string.format("Status: AUTO-SUSPENDED (%s) | Smoothly returning to vanilla", state.suspend_reason), 0xFF00CCFF)
        elseif config.rts_mode then
            ui_colored(string.format("Status: RTS TACTICAL MODE | Dist: %+.1fm (+%.1fm) | Pitch: %.0f deg",
                state.cur_native_dist, state.cur_extra_dist, state.cur_pitch_deg), 0xFFFFAA00)
        elseif state.is_in_combat and config.use_combat_distance then
            ui_colored(string.format("Status: COMBAT (%s) | Offset: %+.2fm | Shoulder: %+.2fm | Height: %+.2fm",
                state.combat_reason, state.cur_native_dist, state.cur_shoulder_x, state.cur_height_y), 0xFF5577FF)
        elseif not state.coop_active and not config.fov_enabled and math.abs(state.cur_native_dist) < 0.01
            and math.abs(state.cur_extra_dist) < 0.01 and math.abs(state.cur_shoulder_x) < 0.01
            and math.abs(state.cur_height_y) < 0.01 and math.abs(state.cur_pitch_deg) < 0.01 then
            ui_colored("Status: the game's own camera (nothing changed). Pick a style below to change it.", 0xFF66FF66)
        else
            ui_colored(string.format("Status: EXPLORATION | Offset: %+.2fm | Shoulder: %+.2fm | Height: %+.2fm",
                state.cur_native_dist, state.cur_shoulder_x, state.cur_height_y), 0xFF66FF66)
        end

        if state.status_msg and state.status_msg ~= "" then
            imgui.text("Last Action: " .. state.status_msg)
        end

        imgui.separator()

        -- ======================================================================
        -- 2. Quick Camera Presets (Built-in & Custom)
        -- ======================================================================
        -- 2.9.4: the styles sit at the top, always visible, so a new player can try them with one click
        ui_colored("Camera style (click one to try it; hover for a description):", 0xFFFFDD88)
        for i, p in ipairs(BUILTIN_PRESETS) do
            if i > 1 and (i - 1) % 3 ~= 0 then
                imgui.same_line()
            end
            local label = (config.active_preset_index == i) and ("[ " .. p.name .. " ]") or p.name
            if imgui.button(label .. "##preset_" .. i) then
                apply_builtin_preset(i)
            end
            ui_tooltip(p.desc)
        end
        imgui.separator()

        ui_colored("Optional extras (all off by default):", 0xFFFFDD88)
        c, config.enable_mousewheel_zoom = imgui.checkbox("Zoom with Alt + mouse wheel", config.enable_mousewheel_zoom)
        changed = changed or c
        ui_tooltip("Hold the modifier key (Alt unless changed below) and roll the wheel to move the camera in or out.")
        c, config.enable_keyboard_hotkeys = imgui.checkbox("Camera keys on the number pad", config.enable_keyboard_hotkeys)
        changed = changed or c
        ui_tooltip("Numpad + / - zoom, Numpad / swaps shoulder, Numpad * next style, Numpad 0 bird's-eye. Rebind them under Hotkeys below.")
        c, config.enable_gamepad_combos = imgui.checkbox("Camera buttons on the controller (hold L1+R1, then D-pad)", config.enable_gamepad_combos)
        changed = changed or c
        ui_tooltip("While holding L1 + R1: D-Pad Up/Down zooms in/out, D-Pad Left swaps shoulder, D-Pad Right toggles the bird's-eye camera. Not used during co-op.")
        ui_colored("Couch co-op (only does anything while DirectPawnControl co-op is running):", 0xFFFFDD88)
        do
            local ck
            ck, config.coop_framing = imgui.checkbox("Keep both players on screen", config.coop_framing)
            changed = changed or ck
            ck, config.coop_marker = imgui.checkbox("Show an edge marker for player 2 while he is off screen", config.coop_marker ~= false)
            changed = changed or ck
        end
        imgui.separator()

        if imgui.tree_node("Custom Presets") then
            imgui.text("Save / Load Custom Presets:")
            local cn, new_name = imgui.input_text("Preset Name##cust_name", state.new_preset_name)
            if cn then state.new_preset_name = new_name end
            imgui.same_line()
            if imgui.button("Save Current as Preset") then
                table.insert(config.custom_presets, {
                    name = (state.new_preset_name ~= "" and state.new_preset_name) or ("Custom " .. (#config.custom_presets + 1)),
                    distance = config.distance,
                    use_combat_distance = config.use_combat_distance,
                    combat_distance = config.combat_distance,
                    extra_distance = config.extra_distance,
                    shoulder_x = config.shoulder_x * (config.shoulder_side or 1),
                    height_y = config.height_y,
                    pitch_deg = config.pitch_deg,
                    forward_lead = config.forward_lead,
                    rts_mode = config.rts_mode,
                    fov_enabled = config.fov_enabled,
                    fov_value = config.fov_value,
                    combat_fov_offset = config.combat_fov_offset,
                })
                state.status_msg = "Saved custom preset: " .. state.new_preset_name
                changed = true
            end

            if config.custom_presets and #config.custom_presets > 0 then
                for idx, cp in ipairs(config.custom_presets) do
                    if imgui.button("Load: " .. cp.name .. "##load_cp_" .. idx) then
                        apply_preset_table(cp)
                        state.status_msg = "Loaded custom preset: " .. cp.name
                    end
                    imgui.same_line()
                    if imgui.button("Delete##del_cp_" .. idx) then
                        table.remove(config.custom_presets, idx)
                        changed = true
                        break
                    end
                end
            end

            imgui.tree_pop()
        end

        -- ======================================================================
        -- 3. Distance Controls (Exploration vs. Combat)
        -- ======================================================================
        if imgui.tree_node("Distance Controls (Exploration & Combat)") then
            c, config.distance = imgui.slider_float("Exploration Distance Offset", config.distance, -2.0, 20.0, "%.2f m")
            changed = changed or c
            ui_tooltip("Camera distance offset while exploring out of combat. Negative pulls closer (Over-the-Shoulder); positive zooms out.")

            c, config.use_combat_distance = imgui.checkbox("Use Separate Combat Distance", config.use_combat_distance)
            changed = changed or c
            ui_tooltip("Automatically transition to a different camera distance when weapons are drawn or enemies engage.")

            if config.use_combat_distance then
                c, config.combat_distance = imgui.slider_float("Combat Distance Offset", config.combat_distance, -2.0, 20.0, "%.2f m")
                changed = changed or c
                ui_tooltip("Camera distance offset during combat / when weapon is drawn.")

                local trigger_modes = {
                    "Battle Camera / Weapon Drawn / Enemies",
                    "Weapon Drawn Only",
                    "Nearby Hostile Enemies Only",
                }
                c, config.combat_trigger_mode = imgui.combo("Combat Trigger Rule", config.combat_trigger_mode or 1, trigger_modes)
                changed = changed or c

                if (config.combat_trigger_mode or 1) ~= 2 then
                    c, config.combat_enemy_radius = imgui.slider_float("Enemy Detection Radius", config.combat_enemy_radius or 24.0, 8.0, 60.0, "%.1f m")
                    changed = changed or c
                end

                c, config.combat_linger_sec = imgui.slider_float("Post-Combat Hold Time", config.combat_linger_sec or 2.5, 0.0, 10.0, "%.1f s")
                changed = changed or c
                ui_tooltip("How long to keep the combat camera active after sheathing your weapon or defeating the last enemy.")
            end

            imgui.spacing()
            c, config.extra_distance = imgui.slider_float("Extra Post-Collision Distance", config.extra_distance or 0.0, -2.0, 25.0, "%.2f m")
            changed = changed or c
            ui_tooltip("Additional distance applied directly to the camera joint after native collision. Useful for ultra-wide zoom.")

            imgui.spacing()
            c, config.smooth_transitions = imgui.checkbox("Smooth Camera Transitions", config.smooth_transitions)
            changed = changed or c
            if config.smooth_transitions then
                c, config.transition_speed = imgui.slider_float("Transition Speed", config.transition_speed or 6.0, 1.0, 20.0, "%.1f")
                changed = changed or c
                ui_tooltip("Lower = slow cinematic glide; Higher = fast responsive snap.")
            end

            imgui.tree_pop()
        end

        -- ======================================================================
        -- 4. 3rd-Person Framing & Over-the-Shoulder (OTS)
        -- ======================================================================
        if imgui.tree_node("Over-the-Shoulder & Framing Offsets") then
            c, config.shoulder_x = imgui.slider_float("Horizontal Shoulder Offset", config.shoulder_x or 0.0, 0.0, 1.50, "%.2f m")
            changed = changed or c
            ui_tooltip("Shifts the camera horizontally over your character's shoulder (0.45m - 0.60m recommended for OTS).")

            local side_text = (config.shoulder_side == -1) and "Active Shoulder: LEFT (-X)" or "Active Shoulder: RIGHT (+X)"
            if imgui.button(side_text .. " (Click to Swap)") then
                config.shoulder_side = (config.shoulder_side == -1) and 1 or -1
                changed = true
            end
            imgui.same_line()
            if imgui.button("Center Horizontally (0.0)") then
                config.shoulder_x = 0.0
                changed = true
            end

            c, config.height_y = imgui.slider_float("Vertical Height Offset (Y)", config.height_y or 0.0, -1.0, 4.0, "%+.2f m")
            changed = changed or c
            ui_tooltip("Raises or lowers the camera vertically relative to the character.")

            c, config.pitch_deg = imgui.slider_float("Camera Downward Pitch Angle", config.pitch_deg or 0.0, -15.0, 60.0, "%+.1f deg")
            changed = changed or c
            ui_tooltip("Orbits the camera higher above the player and tilts the view downward by this angle (keep at 0.0 for normal 3rd-person look).")

            c, config.forward_lead = imgui.slider_float("Forward Battlefield Lead", config.forward_lead or 0.0, -3.0, 8.0, "%+.2f m")
            changed = changed or c
            ui_tooltip("Shifts the camera ahead in your look direction so you see more of the battlefield in front of your character.")

            imgui.tree_pop()
        end

        -- ======================================================================
        -- 5. RTS / Tactical Bird's-Eye Mode Settings
        -- ======================================================================
        if imgui.tree_node("Couch co-op fine tuning") then
            local c1, c2, c3, c4, c5, c6
            local cz
            cz, config.coop_aim_zoom_limit = imgui.checkbox("Limit the bow-aim zoom so player 2 stays in view", config.coop_aim_zoom_limit == true)
            if cz then save_config() end
            if config.coop_aim_zoom_limit then
                local cf2
                local cf3
                cf3, config.coop_aim_back_max = imgui.slider_float("Zoom limit: furthest pull-back while aiming (m)", config.coop_aim_back_max or 4.0, 0.0, 10.0)
                cf2, config.coop_aim_fov_max = imgui.slider_float("Zoom limit: widest view while aiming (deg)", config.coop_aim_fov_max or 50.0, 36.0, 80.0)
                if cf2 or cf3 then save_config() end
            end
            if state.zl_dbg then imgui.text(state.zl_dbg) end
            local cm
            do
                local on = config.safe_169 ~= false
                local c3, v = imgui.checkbox("On ultrawide screens, frame co-op for the middle 16:9 (recording)", on)
                if c3 then config.safe_169 = v and "auto" or false; state.coop_aspect = nil; save_config() end
            end
            if cm then save_config() end
            c2, config.coop_start_dist = imgui.slider_float("Pull back after (m)", config.coop_start_dist, 0.0, 20.0)
            c3, config.coop_zoom_per_m = imgui.slider_float("Pull back per metre", config.coop_zoom_per_m, 0.0, 1.5)
            c4, config.coop_max_extra = imgui.slider_float("Max pull back (m)", config.coop_max_extra, 0.0, 25.0)
            c5, config.coop_center = imgui.slider_float("Centre (0 Arisen .. 1 pawn)", config.coop_center, 0.0, 1.0)
            c6, config.coop_max_shift = imgui.slider_float("Max shift (m)", config.coop_max_shift, 0.0, 30.0)
            local cf
            cf, config.coop_fit = imgui.checkbox("Fit both on screen (2.3; untick for the 2.2 per-metre pull-back)", config.coop_fit ~= false)
            if cf then save_config() end
            if config.coop_fit ~= false then
                local f1, f2
                f1, config.coop_fit_cap = imgui.slider_float("Fit: max pull back (m)", config.coop_fit_cap or 30.0, 0.0, 60.0)
                f2, config.coop_fill = imgui.slider_float("Fit: use this share of the screen", config.coop_fill or 0.8, 0.4, 1.0)
                local f3
                f3, config.coop_arisen_fill = imgui.slider_float("Fit: how far off-centre the Arisen may go (0 = never)", config.coop_arisen_fill or 0.45, 0.0, 0.8)
                if f1 or f2 or f3 then save_config() end
                if state.coop_fit_dbg then imgui.text(state.coop_fit_dbg) end
            end
            changed = changed or c1 or c2 or c3 or c4 or c5 or c6
            if state.coop_fail > 3 then
                ui_colored("DirectPawnControl not detected (no data/DPC_coop.json)", 0xFF8888FF)
            elseif state.coop_active then
                ui_colored(string.format("Co-op ON: %s  %.1fm apart  pulled back %.1fm  shifted %.1fm",
                    state.coop_name, state.coop_sep, state.coop_extra,
                    math.sqrt(state.coop_shift_x ^ 2 + state.coop_shift_z ^ 2)), 0xFF88FF88)
            else
                imgui.text("Co-op off (start it in DirectPawnControl with Ctrl+F6)")
            end
            imgui.tree_pop()
        end

        if imgui.tree_node("RTS / Tactical Bird's-Eye Mode") then
            c, config.rts_mode = imgui.checkbox("Enable RTS / Bird's-Eye Mode Now", config.rts_mode)
            changed = changed or c
            ui_tooltip("Orbits the camera high into the air angled down at the battlefield while preserving full movement and rotation.")

            c, config.rts_distance = imgui.slider_float("RTS Native Distance", config.rts_distance or 8.0, 0.0, 20.0, "%.1f m")
            changed = changed or c

            c, config.rts_extra_distance = imgui.slider_float("RTS High-Altitude Orbital Zoom", config.rts_extra_distance or 8.0, 0.0, 40.0, "%.1f m")
            changed = changed or c
            ui_tooltip("Controls how high/far the orbital RTS camera sits above the player.")

            c, config.rts_pitch_deg = imgui.slider_float("RTS Downward Angle (Pitch)", config.rts_pitch_deg or 32.0, 10.0, 65.0, "%.1f deg")
            changed = changed or c
            ui_tooltip("Downward viewing angle in degrees (30 - 40 deg feels like an ARPG/RTS tactical camera; 55 deg is near top-down).")

            c, config.rts_height_y = imgui.slider_float("RTS Pivot Elevation", config.rts_height_y or 0.5, 0.0, 6.0, "%.2f m")
            changed = changed or c

            c, config.rts_forward_lead = imgui.slider_float("RTS Forward Battlefield Lead", config.rts_forward_lead or 1.5, 0.0, 10.0, "%.2f m")
            changed = changed or c
            ui_tooltip("Pushes the camera center ahead of the player so the player stands in the lower third of the screen.")

            imgui.tree_pop()
        end

        -- ======================================================================
        -- 6. Field of View (FOV) & Auto-Suspend Safeguards
        -- ======================================================================
        if imgui.tree_node("Field of View (FOV) & Cutscene Safeguards") then
            c, config.fov_enabled = imgui.checkbox("Override Field of View (FOV)", config.fov_enabled)
            if c then
                changed = true
                if not config.fov_enabled and state.vanilla_fov then
                    local pri_cam = sdk.get_primary_camera()
                    if pri_cam then pcall(function() pri_cam:call("set_FOV", state.vanilla_fov) end) end
                    state.fov_was_overridden = false
                end
            end

            if config.fov_enabled then
                c, config.fov_value = imgui.slider_float("Base FOV (Degrees)", config.fov_value or 60.0, 35.0, 110.0, "%.1f deg")
                changed = changed or c

                c, config.combat_fov_offset = imgui.slider_float("Combat FOV Boost", config.combat_fov_offset or 0.0, -10.0, 20.0, "%+.1f deg")
                changed = changed or c
                ui_tooltip("Extra FOV added dynamically when in combat.")
            end

            imgui.separator()
            imgui.text("Auto-Suspend Safeguards (Prevents breaking framing):")
            c, config.suspend_in_menus = imgui.checkbox("Auto-Suspend in Pause / Fullscreen Menus", config.suspend_in_menus)
            changed = changed or c

            c, config.suspend_in_cutscenes = imgui.checkbox("Auto-Suspend in Cutscenes & NPC Dialogues", config.suspend_in_cutscenes)
            changed = changed or c

            c, config.suspend_when_aiming = imgui.checkbox("Auto-Suspend While Aiming (Bow / Magick Bow / Scopes)", config.suspend_when_aiming)
            changed = changed or c

            imgui.tree_pop()
        end

        -- ======================================================================
        -- 7. Quick-Zoom, Mouse Wheel & Hotkeys
        -- ======================================================================
        if imgui.tree_node("Hotkeys: step size, modifier key and rebinding") then
            c, config.zoom_step = imgui.slider_float("Quick-Zoom Step Size", config.zoom_step or 0.75, 0.25, 3.0, "%.2f m")
            changed = changed or c

            if config.enable_mousewheel_zoom then
                local mod_options = { "Left/Right Alt (18)", "Left/Right Ctrl (17)", "Left/Right Shift (16)" }
                local cur_mod_idx = (config.mousewheel_modifier_key == 17 and 2) or (config.mousewheel_modifier_key == 16 and 3) or 1
                local mc, new_mod_idx = imgui.combo("Mouse Wheel Modifier Key", cur_mod_idx, mod_options)
                if mc then
                    config.mousewheel_modifier_key = (new_mod_idx == 2 and 17) or (new_mod_idx == 3 and 16) or 18
                    changed = true
                end
            end


            if config.enable_keyboard_hotkeys then
                if state.hotkey_rebinding then
                    ui_colored("Press any key to bind '" .. state.hotkey_rebinding .. "' (Press ESC to cancel)...", 0xFF00CCFF)
                end

                local hk_list = {
                    { key = "zoom_out",      label = "Zoom Out (+Distance)" },
                    { key = "zoom_in",       label = "Zoom In (-Distance)" },
                    { key = "swap_shoulder", label = "Swap Left/Right Shoulder" },
                    { key = "toggle_rts",    label = "Toggle RTS Bird's-Eye Mode" },
                    { key = "cycle_preset",  label = "Cycle Built-in Presets" },
                    { key = "toggle_mod",    label = "Toggle Mod On/Off" },
                }

                for _, item in ipairs(hk_list) do
                    local vk = config.hotkeys[item.key] or 0
                    imgui.text(string.format("%-28s: %s", item.label, get_key_name(vk)))
                    imgui.same_line()
                    if imgui.button("Rebind##rb_" .. item.key) then
                        state.hotkey_rebinding = item.key
                    end
                    imgui.same_line()
                    if imgui.button("Clear##clr_" .. item.key) then
                        config.hotkeys[item.key] = 0
                        changed = true
                    end
                end
            end

            imgui.tree_pop()
        end

        -- ======================================================================
        -- 8. Diagnostics & Live Camera Telemetry
        -- ======================================================================
        if imgui.tree_node("Diagnostics & Live Camera Telemetry") then
            if state.last_cam_pos then
                imgui.text(string.format("Camera Local Pos: (%.2f, %.2f, %.2f)",
                    state.last_cam_pos.x, state.last_cam_pos.y, state.last_cam_pos.z))
            end
            if state.last_pivot_pos then
                imgui.text(string.format("Target Local Pivot: (%.2f, %.2f, %.2f)",
                    state.last_pivot_pos.x, state.last_pivot_pos.y, state.last_pivot_pos.z))
            end
            imgui.text(string.format("Vanilla Base FOV: %s", state.vanilla_fov and string.format("%.1f deg", state.vanilla_fov) or "Not sampled yet"))

            imgui.tree_pop()
        end

        if changed then
            save_config()
        end
    end)

    if not ok_ui then
        imgui.text("UI Error: " .. tostring(err_ui))
    end

    imgui.tree_pop()
end)