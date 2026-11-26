-- Direct Pawn Control: pawn action helpers: camera angle, lock-on, draw / sheathe, aiming, button and key bindings.
-- Part of DirectPawnControl.lua, which loads the files in this folder in order (this one is 12 of 26).
-- Never run on its own: REFramework only runs the files directly in reframework/autorun.
local S = require("DirectPawnControl/shared")
local dev_error, cfg, R, log_msg, call, field = S.dev_error, S.cfg, S.R, S.log_msg, S.call, S.field
local set_field, state, coop, native, coop_pad_values = S.set_field, S.state, S.coop, S.native, S.coop_pad_values

-- ----------------------------------------------------------------------------
-- Pawn Action Helpers (PawnCommander Verified Signatures & Vocation Actions)
-- ----------------------------------------------------------------------------
local function compute_camera_move_angle_deg(axis_x, axis_y)
    -- 1. Primary: Static primitive method app.PlayerInputProcessorDetail.getCameraAngleRad() -> System.Single
    local cam_yaw = nil
    if S.get_cam_angle_rad_method then
        local ok, rad = pcall(S.get_cam_angle_rad_method.call, S.get_cam_angle_rad_method, nil)
        if ok and type(rad) == "number" then
            cam_yaw = rad
        end
    end

    -- 2. Fallback: Read <CameraFront>k__BackingField directly
    if not cam_yaw then
        local cm = sdk.get_managed_singleton("app.CharacterManager")
        local cf = cm and field(cm, "<CameraFront>k__BackingField")
        if cf then
            local ok_cf, yaw = pcall(function()
                if cf.x ~= 0 or cf.z ~= 0 then
                    return math.atan(cf.x, cf.z)
                end
                return 0.0
            end)
            if ok_cf and type(yaw) == "number" then
                cam_yaw = yaw
            end
        end
    end

    cam_yaw = cam_yaw or 0.0
    state.last_cam_deg = math.deg(cam_yaw)

    -- Stick: +y is forward (along cam_yaw), +x is right (cam_yaw - pi/2 in RH Y-up)
    local stick_angle = math.atan(-axis_x, axis_y)
    return math.deg(cam_yaw + stick_angle)
end

local function update_pawn_lockon_target()
    local loc = state.arisen_lockon_ctrl
    if not (loc and state.pawn_chara) then return end
    if coop.active then return end -- co-op: that is player 1's lock-on
    set_field(loc, "Chara", state.pawn_chara)
    -- v0.9.126: two calls removed here (updateTargetWhenUnlock, updateSpellTarget). No type in the game has
    -- them (type index, dd2.exe 4.1.0.0), so they never ran; pointing Chara at the pawn is what does the work.
end

local function pawn_do_draw(pawn_chara, sel)
    pawn_chara = pawn_chara or state.pawn_chara
    sel = sel or (pawn_chara and call(pawn_chara, "get_HumanActionSelector"))
    if not sel then return false end
    call(sel, "requestDrawWeapon()")
    state.suppress_loco_until = math.max(state.suppress_loco_until, os.clock() + 0.25)
    state.last_action_str = "Draw Weapon"
    return true
end

local function pawn_do_sheathe(pawn_chara, sel)
    pawn_chara = pawn_chara or state.pawn_chara
    sel = sel or (pawn_chara and call(pawn_chara, "get_HumanActionSelector"))
    if not sel then return false end
    state.pending_skill = nil
    state.pending_attack = nil
    state.active_cast = nil
    state.is_sprinting = false
    call(sel, "requestEndAction()")
    call(sel, "requestSheatheWeapon(System.Boolean)", false)
    state.suppress_loco_until = math.max(state.suppress_loco_until, os.clock() + 0.25)
    state.last_action_str = "Sheathe Weapon"
    return true
end

-- Dev diagnostics: ring buffer of input / action events, readable through the agent bridge as
-- _G.DPC.state.input_log. Cheap (string building only when an event happens).
local function node_names(chara)
    local am = chara and call(chara, "get_ActionManager")
    local fsm = am and field(am, "Fsm")
    if not fsm then return "?", "?" end
    return tostring(call(fsm, "getCurrentNodeName(System.UInt32)", 0) or ""), tostring(call(fsm, "getCurrentNodeName(System.UInt32)", 1) or "")
end
R.node_names = node_names

-- v0.9.29 bow aim for the possessed Archer. Measured 2026-11-15 (archer-aim-1 / -2): the game enters the aim camera
-- with MainCameraController.switchCamera(7, interp, nil, 0) and leaves with switchCamera(0, ...), but only for the
-- player character. A possessed Archer does go into Job02_StartAim, nothing asks for the camera, and when DPC asks,
-- the game switches back to type 0 on the next frame (about 50 calls a second). So while the pawn aims DPC requests
-- type 7 and skips the game's switch-back in a pre-hook (verified: aim camera held in every sample), and turns the
-- pawn to the camera yaw each frame (verified: body-to-camera angle 22 deg -> 0.5 deg). The block only applies
-- while aim_until is fresh, so a stopped script can never leave the Arisen's own aim camera stuck.
R.aim_sig = "switchCamera(app.CameraDefine.ControlType, app.CameraSwitchInterpParam, app.PostEffectSetting, app.CameraDefine.ToPlayerCameraOption)"
R.aim_on_aim = function(mcc)
    local cur = field(mcc, "_CurrentCameraController")
    local on = false
    if cur then pcall(function() on = cur:get_type_definition():get_name() == "AimCameraController" end) end
    return on
end
R.aim_mcc = function()
    local cm = sdk.get_managed_singleton("app.CameraManager")
    if not cm then return nil end
    return call(cm, "getMainCameraController", 0)
end
R.aim_interp = function(which) -- the game's own transition object once the Arisen has aimed, else a built-in preset
    local e = (which == "exit") and R.aim_exit or R.aim_enter
    if e then return e end
    if R.aim_preset == nil then
        R.aim_preset = false
        pcall(function()
            local v = sdk.find_type_definition("app.CameraSwitchInterpParam"):get_field("Smooth"):get_data(nil)
            if v then R.aim_preset = v:add_ref() end
        end)
    end
    return R.aim_preset or nil
end
R.aim_install = function()
    if R.aim_hooked then return end
    R.aim_hooked = true
    local td = sdk.find_type_definition("app.MainCameraController")
    local m = td and td:get_method(R.aim_sig)
    if not m then log_msg("Aim camera: switchCamera not found; feature off"); R.aim_off = true; return end
    local ok, err = pcall(sdk.hook, m, function(args)
        local okh, res = pcall(function()
            if R.aim_mine then return nil end
            local ct = sdk.to_int64(args[3]) & 0xFFFFFFFF
            -- v0.9.143 reported while playing the main pawn: the camera was being pulled away. Camera watch:
            -- "Combat (2) -> Climbing (6), player camera false", target object still the pawn; the Arisen (Mystic
            -- Spearhand, on his own) was on a Griffin. The climbing camera is the game's camera for the PLAYER
            -- character clinging to a monster, so it went to the Arisen. Not switched to while a pawn is played
            -- (normal possession; in co-op player 1 is the Arisen). A played pawn that climbs never got this
            -- camera anyway. The cinematic action camera (10) is refused here too, behind 0.9.139's block.
            if state.active and not coop.active and ((ct == 6 and cfg.possess_no_climb_cam) or (ct == 10 and cfg.possess_no_cinematic_cam)) then
                R.cam_refused = (R.cam_refused or 0) + 1
                R.cam_refused_last = ct
                return sdk.PreHookResult.SKIP_ORIGINAL
            end
            if R.aim_hold and ct ~= 7 and os.clock() < (R.aim_until or 0) then
                R.aim_blocked = (R.aim_blocked or 0) + 1
                return sdk.PreHookResult.SKIP_ORIGINAL
            end
            local io = sdk.to_managed_object(args[4]) -- learn the game's own transitions from the Arisen's aim
            if io then
                if ct == 7 then
                    if not R.aim_enter then R.aim_enter = io:add_ref() end
                    R.aim_seen7 = true
                elseif ct == 0 and R.aim_seen7 then
                    if not R.aim_exit then R.aim_exit = io:add_ref() end
                    R.aim_seen7 = false
                end
            end
            return nil
        end)
        if okh and res then return res end
    end, function(retval) return retval end)
    if not ok then log_msg("Aim camera: hook failed (" .. tostring(err) .. "); feature off"); R.aim_off = true end
end
R.aim_rsig = "requestDraw(via.Point, System.Single, System.Boolean)"
-- Reticle for the possessed Archer: app.ui020801 (GuiManager.Aim), driven every frame by requestDraw(point, scale,
-- flag). Measured (archer-aim-3 / -5): the point is in real screen pixels. The Arisen's reticle sits at the UI's
-- DrawPos 960,540 (centre of its 1920x1080 canvas); a request at 1920,540 on a 7680x2160 screen gave DrawPos 480,270
-- and one at 960,540 gave a reticle further left, i.e. DrawPos = point * (1920 / width, 1080 / height). So the centre
-- of the real screen is the right point on any aspect ratio.
-- v0.9.166: not on every PC. On a 5120x1440 screen with Windows display scaling at 150 %, REFramework reported the
-- display as 7680x2160, the request went to 3840,1080 and the reticle was drawn at DrawPos 1440,810: three quarters
-- of the way right and down, i.e. the game's own screen is the unscaled 5120x1440. So the point now corrects itself:
-- after each request the widget's DrawPos is read back, and the point is scaled until DrawPos is 960,540.
R.aim_reticle = function()
    if not cfg.pawn_aim_reticle or R.aim_ret_fail then return end
    local ok, err = pcall(function()
        local gm = sdk.get_managed_singleton("app.GuiManager")
        local ui = gm and gm:get_field("Aim")
        if not ui then return end
        local okd, ds = pcall(imgui.get_display_size)
        if okd and ds and ds.x and ds.x > 0 then R.aim_disp_x, R.aim_disp_y = ds.x, ds.y end
        if not R.aim_disp_x then return end
        local x = math.floor(R.aim_disp_x * 0.5 * (R.aim_fix_x or 1.0) + 0.5)
        local y = math.floor(R.aim_disp_y * 0.5 * (R.aim_fix_y or 1.0) + 0.5)
        if not R.aim_pt or R.aim_pt_x ~= x or R.aim_pt_y ~= y then
            local pt = ValueType.new(sdk.find_type_definition("via.Point"))
            pcall(function() pt:set_field("x", x); pt:set_field("y", y) end)
            local okr, rx = pcall(pt.get_field, pt, "x")
            if not (okr and rx == x) then pt:write_dword(0, x); pt:write_dword(4, y) end
            R.aim_pt, R.aim_pt_x, R.aim_pt_y = pt, x, y
        end
        R.aim_mine = true
        local okc, e2 = pcall(ui.call, ui, R.aim_rsig, R.aim_pt, 1.0, false)
        R.aim_mine = false
        if not okc then error(e2) end
        -- read back where the widget put it (UI canvas 1920x1080; centre 960,540) and correct the point
        local okp, dp = pcall(ui.get_field, ui, "DrawPos")
        if okp and dp and dp.x and dp.y and dp.x > 1 and dp.y > 1 then
            R.aim_dp_x, R.aim_dp_y = dp.x, dp.y
            if math.abs(dp.x - 960) > 2 or math.abs(dp.y - 540) > 2 then
                R.aim_fix_x = math.max(0.1, math.min(4.0, (R.aim_fix_x or 1.0) * 960 / dp.x))
                R.aim_fix_y = math.max(0.1, math.min(4.0, (R.aim_fix_y or 1.0) * 540 / dp.y))
                R.aim_fixes = (R.aim_fixes or 0) + 1
            end
        end
    end)
    if not ok then R.aim_mine = false; R.aim_ret_fail = true; dev_error("aim reticle", err) end
end
-- Where the arrow goes. Measured (archer-aim-6): while the Arisen aims, his Character.AimTargetPosition has a value
-- exactly on the camera's centre line (0.00 m off) at the distance of what he looks at (12.6 - 13.6 m facing a
-- wall); the possessed pawn's has none, so his arrows had the right heading but no elevation. DPC writes a point on
-- the centre line right after the pawn's input processor ran, at the distance R.aim_ray finds (0.9.35; a fixed
-- distance made near shots land left, because the pawn stands left of the camera line).
-- v0.9.35 distance to what the camera's centre line hits, the way the game picks the Arisen's aim point. A ray on
-- filter layer 0 returns everything near-sorted (probes ray1-5, 2026-11-15): sensors, markers, the party's own bodies,
-- then the world. Take the first hit that is world geometry (collidable layer 1 or 22: EnvRoot / GroundCol) or a
-- character that is not the Arisen or a pawn. No result pool growth with either castRay form (132/138/354 unchanged).
R.aim_ray = function(p, z)
    if R.aim_ray_off then return nil end
    local ok, d = pcall(function()
        if not R.aim_q then
            R.aim_q = sdk.create_instance("via.physics.CastRayQuery"):add_ref()
            R.aim_res = sdk.create_instance("via.physics.CastRayResult"):add_ref()
            R.aim_q:call("clearOptions"); R.aim_q:call("enableAllHits"); R.aim_q:call("enableNearSort")
            R.aim_phys_td = sdk.find_type_definition("via.physics.System")
            R.aim_scene_td = sdk.find_type_definition("via.SceneManager")
        end
        local q, res = R.aim_q, R.aim_res
        q:call("setRay(via.vec3, via.vec3)", Vector3f.new(p.x, p.y, p.z), Vector3f.new(p.x - z.x * 150.0, p.y - z.y * 150.0, p.z - z.z * 150.0))
        local scene = sdk.call_native_func(sdk.get_native_singleton("via.SceneManager"), R.aim_scene_td, "get_CurrentScene()")
        sdk.call_native_func(sdk.get_native_singleton("via.physics.System"), R.aim_phys_td,
            "castRay(via.Scene, via.physics.CastRayQuery, via.physics.CastRayResult)", scene, q, res)
        local n = res:call("get_NumContactPoints") or 0
        local found
        for i = 0, n - 1 do
            local c = res:call("getContactCollidable(System.UInt32)", i)
            local layer = c:call("get_FilterInfo"):call("get_Layer")
            local solid = (layer == 1 or layer == 22)
            if not solid then
                local go = c:call("get_GameObject")
                local tag = tostring(go:call("get_Tag") or "")
                if tag:find("Character", 1, true) then
                    local folder = go:call("get_Folder")
                    local fname = folder and tostring(folder:call("get_Name")) or ""
                    solid = fname ~= "Player" and fname ~= "Pawn"
                end
            end
            if solid then
                local pos = res:call("getContactPoint(System.UInt32)", i):get_field("Position")
                local dd = math.sqrt((pos.x - p.x) ^ 2 + (pos.y - p.y) ^ 2 + (pos.z - p.z) ^ 2)
                if dd > 1.0 then found = dd; break end
            end
        end
        res:call("clear")
        return found
    end)
    if not ok then
        R.aim_ray_errs = (R.aim_ray_errs or 0) + 1
        if R.aim_ray_errs >= 5 then R.aim_ray_off = true; dev_error("aim ray", d) end
        return nil
    end
    return d
end
R.aim_point = function()
    if not (R.aim_hold and state.pawn_chara) then return end
    -- v0.9.36: face the camera again AFTER his processor ran. With a move input the processor turned him to the
    -- move direction (he turned round when backing up); the Arisen keeps facing the target and backpedals.
    if S.get_cam_angle_rad_method then
        local okr, rad = pcall(S.get_cam_angle_rad_method.call, S.get_cam_angle_rad_method, nil)
        if okr and type(rad) == "number" then
            call(state.pawn_chara, "set_TargetFrontAngleDeg(System.Single)", math.deg(rad) + 0.0)
        end
    end
    if not cfg.pawn_aim_point then return end
    pcall(function()
        local tr = R.primary_cam():call("get_GameObject"):call("get_Transform")
        local p, z = tr:call("get_Position"), tr:call("get_WorldMatrix")[2]
        local d = (cfg.pawn_aim_ray and R.aim_ray(p, z)) or cfg.pawn_aim_point_dist or 30.0
        R.aim_last_d = d
        -- v0.9.33: the setter takes System.Nullable<via.vec3> (32 bytes: _HasValue at 0, _Value at 16). 0.9.30 passed
        -- a bare vector, which is what made the bow circle.
        if not R.aim_nv then R.aim_nv = ValueType.new(sdk.find_type_definition("System.Nullable`1<via.vec3>")) end
        local nv = R.aim_nv
        nv:write_byte(0, 1)
        nv:write_float(16, p.x - z.x * d); nv:write_float(20, p.y - z.y * d); nv:write_float(24, p.z - z.z * d)
        state.pawn_chara:call("set_AimTargetPosition", nv)
        R.aim_pts = (R.aim_pts or 0) + 1
    end)
end
R.aim_stop = function()
    if not R.aim_hold then return end
    R.aim_hold, R.aim_until, R.aim_t = false, 0, nil
    R.aim_pick_idx = nil
    local mcc = R.aim_mcc()
    if not (mcc and R.aim_on_aim(mcc)) then return end
    local ip = R.aim_interp("exit")
    if not ip then return end
    R.aim_mine = true
    pcall(mcc.call, mcc, R.aim_sig, 0, ip, nil, 0)
    R.aim_mine = false
end
-- v0.9.85 the aim camera needs an aim setting. app.AimCameraController takes its rotation speeds, zoom (FOV) and
-- gyro from an AimSetting that the game picks with AimCameraSetting.evaluate(player GameObject) when the PLAYER
-- starts to aim, and keeps afterwards. With an Archer Arisen who had aimed earlier in the session a setting was
-- already there, so the pawn's aim worked (2026-11-15). With a Thief Arisen it was nil: reticle, but no turning
-- and no zoom (the tester, 2026-11-16). So pick the setting for the pawn: evaluate(pawn GameObject) while he aims,
-- else the first enabled non-throwing setting with a zoom, and hand it to the controller with setupAim.
R.AIM_BY_NODE = { { "FullBend", 4 }, { "BodyBinder", 5 }, { "MeteorShot", 6 }, { "RandomShot", 8 }, { "FullBlast", 9 }, { "HeavyRain", 10 } }
R.aim_setup = function(mcc)
    local now = os.clock()
    if now < (R.aim_setup_next or 0) then return end
    R.aim_setup_next = now + 0.1
    local ok, err = pcall(function()
        local ac = mcc:get_field("<CameraControllers>k__BackingField"):call("get_Item", 7)
        if not ac then R.aim_set = "no controller"; return end
        local asset = ac:get_field("_AimCameraSetting")
        local arr = asset and asset:get_field("_AimSettings")
        if not arr then R.aim_set = "no settings"; return end
        -- v0.9.86: every setting's condition is a player condition (app.gc.pl.*), so evaluate() never answers
        -- for a pawn, and 0.9.85's "first with a zoom" picked the Meteor Shot sniper view (index 6: 15 deg/s,
        -- FOV 15). The list, read live: 11 = DrawBow (the normal bow aim: 100 / 90 deg/s, gyro), 4 FullBend,
        -- 5 BodyBinder, 6 MeteorShot, 8 RandomShot, 9 FullBlast, 10 HeavyRain. Pick by the pawn's own action.
        local _, up = node_names(state.pawn_chara)
        local idx = 11
        for _, m in ipairs(R.AIM_BY_NODE) do if up:find(m[1], 1, true) then idx = m[2]; break end end
        if idx >= arr:get_size() then idx = 11 end
        local s = arr:get_element(idx)
        -- sanity: the index must still be a bow setting on this game version
        local cn = ""
        pcall(function() cn = s:get_field("_Condition"):get_field("_Conditions"):get_element(0):get_type_definition():get_full_name() end)
        if idx == 11 and not cn:find("DrawBow", 1, true) then
            for i = 0, arr:get_size() - 1 do
                local okc, n2 = pcall(function() return arr:get_element(i):get_field("_Condition"):get_field("_Conditions"):get_element(0):get_type_definition():get_full_name() end)
                if okc and n2 == "app.gc.pl.DrawBow" then s, idx = arr:get_element(i), i; break end
            end
        end
        R.aim_pick, R.aim_set = s, "index " .. idx
        R.aim_asset_addr = asset:get_address()
        -- the controller asks AimCameraSetting.evaluate(player) for its setting; answer for the pawn while he aims
        -- v0.9.168 crash fix (second test PC 2026-11-19, DD2.exe+0x52590e4 inside setupAim during switchCamera: the engine
        -- read the header of an already freed object, 0x700000000). The answer was a bare pointer with no reference
        -- of its own; the game keeps and later releases what evaluate returns, so each answer cost the setting one
        -- reference until it was freed under the camera. Now each answer carries its own reference (a small, harmless
        -- leak on an asset that lives all session), only the live asset is answered for, and the cache is dropped
        -- when the world loads.
        if not R.aim_eval_hooked then
            R.aim_eval_hooked = true
            sdk.hook(asset:get_type_definition():get_method("evaluate"), function(args)
                R.aim_eval_this = sdk.to_int64(args[2])
            end, function(retval)
                local pick = R.aim_pick
                if R.aim_hold and pick and R.aim_eval_this == R.aim_asset_addr and os.clock() < (R.aim_until or 0) then
                    local okr = pcall(pick.add_ref, pick)
                    if okr then
                        R.aim_evals = (R.aim_evals or 0) + 1
                        return sdk.to_ptr(pick:get_address())
                    end
                end
                return retval
            end)
        end
        if R.aim_pick_idx ~= idx then
            R.aim_pick_idx = idx
            ac:call("setupAim(app.AimCameraSetting.AimSetting)", s)
            R.aim_setups = (R.aim_setups or 0) + 1
        end
    end)
    if not ok and not R.aim_setup_err then R.aim_setup_err = true; dev_error("aim setup", err) end
end
R.aim_tick = function()
    if not cfg.pawn_aim_camera or R.aim_off then
        if R.aim_hold then R.aim_stop() end
        return
    end
    local now = os.clock()
    local want = false
    if state.active and not coop.active and state.pawn_chara and state.pawn_job == 2 and native.pip and not native.failed then
        local _, up = node_names(state.pawn_chara)
        if up:find("Job02_StartAim", 1, true)
            or (R.aim_hold and up:find("Job02", 1, true) and not up:find("AimCancel", 1, true) and not up:find("WithoutAim", 1, true)) then
            R.aim_t = now
        end
        want = R.aim_t ~= nil and (now - R.aim_t) < 0.25
    end
    if not want then
        if R.aim_hold then R.aim_stop() end
        return
    end
    R.aim_install()
    if R.aim_off then return end
    local mcc = R.aim_mcc()
    if not mcc then return end
    R.aim_hold, R.aim_until = true, now + 0.5
    R.aim_setup(mcc)
    if not R.aim_on_aim(mcc) and now >= (R.aim_req_t or 0) then
        R.aim_req_t = now + 0.5
        local ip = R.aim_interp("enter")
        if ip then
            R.aim_mine = true
            local ok, err = pcall(mcc.call, mcc, R.aim_sig, 7, ip, nil, 0)
            R.aim_mine = false
            R.aim_reqs = (R.aim_reqs or 0) + 1
            if not ok and not R.aim_err then R.aim_err = true; dev_error("aim camera", err) end
        end
    end
    if S.get_cam_angle_rad_method then -- body turns with the camera, as it does for the Arisen
        local okr, rad = pcall(S.get_cam_angle_rad_method.call, S.get_cam_angle_rad_method, nil)
        if okr and type(rad) == "number" then
            call(state.pawn_chara, "set_TargetFrontAngleDeg(System.Single)", math.deg(rad) + 0.0)
        end
    end
    R.aim_reticle()
end
-- v0.9.39 co-op gyro. The DualSense's motion sensor aims the Arisen's bow camera (RotateCameraControllerBase has
-- GyroEnable / GyroSensitivity / _GyroAngle; app.UserPadManager.isMotionSensorEnable() is the game's own option
-- check), and in co-op that controller is in player 2's hands. While co-op is on: the option check answers false, and
-- the camera controller in use has its GyroEnable cleared each frame. Both stop the moment co-op ends.
-- v0.9.80 the Arisen cannot die while a pawn is possessed (normal possession; in co-op player 1 plays him).
-- HitController.IsNoDie is the game's own flag: he still takes damage and drops to his last sliver of health, but
-- does not go down, so a mistake by the brain is not a game over. Cleared on release, in co-op and on script reset.
R.guard_tick = function()
    local want = (state.active and not coop.active and cfg.arisen_no_death) and true or false
    if want and R.cp and R.cp.on and R.cp.ar2 and not cfg.coop_p2_arisen_no_death then want = false end -- 0.9.171
    local now = os.clock()
    if want == (R.nodie_on or false) and now < (R.nodie_next or 0) then return end
    if not want and not R.nodie_on then return end
    R.nodie_next = now + 1.0
    local ok = pcall(function()
        local ar = sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer")
        ar:call("get_Hit"):call("set_IsNoDie", want)
    end)
    if ok and want ~= (R.nodie_on or false) then
        log_msg("Arisen death protection " .. (want and "ON" or "off"))
    end
    if ok then R.nodie_on = want end
end
-- v0.9.80 which button names to show player 2: "ps" or "xbox", from the controller that last gave input
-- (via.hid.GamePad.get_LastInputDevice().get_DeviceKindDetails()), unless coop_pad_names forces one.
R.pad_style = function()
    if cfg.coop_pad_names == 2 then return "ps" elseif cfg.coop_pad_names == 3 then return "xbox" end
    local now = os.clock()
    if R.pad_style_v and now < (R.pad_style_next or 0) then return R.pad_style_v end
    R.pad_style_next = now + 1.0
    local v = R.pad_style_v or "ps"
    pcall(function()
        local gp = sdk.get_native_singleton("via.hid.GamePad")
        local td = sdk.find_type_definition("via.hid.GamePad")
        local dev = sdk.call_native_func(gp, td, "get_LastInputDevice")
        local k = dev and dev:call("get_DeviceKindDetails")
        R.pad_kind = k
        if k == 5 or k == 6 or k == 8 or k == 9 then v = "ps"
        elseif k and k >= 11 and k <= 23 then v = "xbox" end
    end)
    R.pad_style_v = v
    return v
end
-- v0.9.100 the game's own controller assignment: UserInputManager.getCurrentCharacterPadAssign().AssignList, one
-- Info per binding (Action index, GamePadButton mask, PreInput = the shift action that must be held). Read live
-- 2026-11-16: Skill1 = L1+Square, Skill2 = L1+Triangle, Skill3 = L1+R1, Skill4 = L1+R2, Skill5 = L1+Triangle+Circle,
-- Skill6 = L1+Square+Cross (the game moves 3 / 4 off Circle / Cross when chord slots are in use). The skill buttons
-- for co-op, for aimed skills and for the labels all come from here now; the old fixed tables are the fallback.
R.bind_read = function()
    local now = os.clock()
    if now < (R.bind_next or 0) then return end
    R.bind_next = now + 2.0
    local ok, err = pcall(function()
        local uim = sdk.get_managed_singleton("app.UserInputManager")
        local pa = uim and uim:call("getCurrentCharacterPadAssign")
        local list = pa and pa:get_field("AssignList")
        local n = list and list:call("get_Count") or 0
        if n == 0 then return end
        local idx = {}
        for s = 1, 6 do
            local f = S.ACTION_FLAGS["Skill" .. s]
            if f and f ~= 0 then for b = 0, 63 do if f == (1 << b) then idx[b] = s end end end
        end
        local pad, pre, sig = {}, {}, ""
        for i = 0, n - 1 do
            local it = list:call("get_Item", i)
            local a, b, p = it:get_field("Action"), it:get_field("Button"), it:get_field("PreInput")
            local s = idx[a]
            if s and b and b ~= 0 and not pad[s] then pad[s], pre[s] = b, p or 0; sig = sig .. s .. ":" .. b .. " " end
        end
        -- v0.9.124: every binding, not only the skills (R.bind.by[action name] = { button masks }, R.bind.list for
        -- the co-op map). Action index a <-> input flag 1 << a; PreInput 14 / 15 = Shift1 / Shift2 must be held.
        local names = {}
        for nm, v in pairs(S.ACTION_ENUM or {}) do if type(v) == "number" then names[v] = names[v] or {}; table.insert(names[v], nm) end end
        local all, by, sig_all = {}, {}, ""
        for i = 0, n - 1 do
            local it = list:call("get_Item", i)
            local a, b, p = it:get_field("Action"), it:get_field("Button"), it:get_field("PreInput")
            if type(a) == "number" and type(b) == "number" and b ~= 0 then
                local ign = it:get_field("IsIgnorePreInput") == true
                local prei = (type(p) == "number" and p ~= 0 and not ign) and p or nil
                for _, nm in ipairs(names[a] or { "Action" .. a }) do
                    all[#all + 1] = { a = a, name = nm, flag = S.ACTION_FLAGS[nm] or (1 << a), pad = b, pre = prei }
                    by[nm] = by[nm] or {}
                    table.insert(by[nm], b)
                end
                sig_all = sig_all .. a .. ":" .. b .. ":" .. tostring(prei or 0) .. " "
            end
        end
        if next(pad) then
            if R.bind and R.bind.sig ~= sig then log_msg("Controller skill buttons changed: " .. sig) end
            if not R.bind then log_msg("Controller skill buttons (from the game): " .. sig) end
            if R.bind and R.bind.sig_all ~= sig_all then
                log_msg("Controller layout changed in the game's options: the co-op button map is rebuilt")
                coop.map = nil
            end
            R.bind = { pad = pad, pre = pre, sig = sig, list = all, by = by, sig_all = sig_all }
            if not R.bind_logged then
                R.bind_logged = true
                local function nm(a) return R.btn_text(R.bind_mask(a)) or "-" end
                log_msg(string.format("Controller layout (from the game): light %s, heavy %s, jump %s, dash %s, grab %s, vocation action %s, sheathe %s, skill shift %s",
                    nm("AttackS"), nm("AttackL"), nm("Jump"), nm("Dash"), nm("Grab"), nm("JobSpecialAction"), nm("Sheathe"), nm("Shift1")))
            end
        end
    end)
    if not ok then R.bind_err = tostring(err) end
end
R.BTN_NAMES = { { "RLeft", "Square" }, { "RUp", "Triangle" }, { "RRight", "Circle" }, { "RDown", "Cross" },
                { "RTrigTop", "R1" }, { "RTrigBottom", "R2" }, { "LTrigTop", "L1" }, { "LTrigBottom", "L2" },
                { "LStickPush", "L3" }, { "RStickPush", "R3" },
                { "LUp", "D-pad up" }, { "LDown", "D-pad down" }, { "LLeft", "D-pad left" }, { "LRight", "D-pad right" } }
-- v0.9.124 the game's keyboard / mouse bindings: UserInputManager.KeyBindController.getCurrentKeyBindSettingTable(),
-- 101 app.KeyBindSettingItem (found with bridge probe kb3, 2026-11-17): _CharacterCommand = the same Action index
-- as the pad list, _PrimaryKey / _SecondaryKey / _ThirdKey = via.hid.KeyboardKey, which are Windows virtual-key
-- codes (W 87, Space 32, left mouse 1, right mouse 2, left Ctrl 162). Read into R.kbind[action index].
R.kbind_read = function()
    -- v0.9.125: not on a timer any more. The game crashed 17 s into a co-op session on 0.9.124 (access violation
    -- in its own HUD code, ui020901.update -> setupStatusIcon -> GUIBase.ConditionIconRef.setup, on a worker
    -- thread; cause not established). Walking the game's key table every 6 s from the script thread was the one
    -- new thing that touched game data continuously, so as a precaution it is read once after loading and again
    -- only when a possession or co-op session starts (R.kbind_next = 0 asks for a read).
    local now = os.clock()
    if now < (R.kbind_next or 0) then return end
    R.kbind_next = math.huge
    local ok, err = pcall(function()
        local uim = sdk.get_managed_singleton("app.UserInputManager")
        local kb = uim and uim:get_field("<KeyBindController>k__BackingField")
        local tbl = kb and kb:call("getCurrentKeyBindSettingTable")
        if not tbl then return end
        local t, sig, n = {}, "", 0
        local en = tbl:call("GetEnumerator")
        while en:call("MoveNext") and n < 400 do
            n = n + 1
            local v = en:call("get_Current"):get_field("value")
            if v and v:get_field("_IsSystemInput") ~= true and v:get_field("_DisableBind") ~= true then
                local a = v:get_field("_CharacterCommand")
                if type(a) == "number" and a > 0 then
                    local ks = t[a] or {}
                    for _, fn in ipairs({ "_PrimaryKey", "_SecondaryKey", "_ThirdKey" }) do
                        local k = v:get_field(fn)
                        if type(k) == "number" and k > 0 and k < 256 then ks[#ks + 1] = k end
                    end
                    if #ks > 0 then t[a] = ks; sig = sig .. a .. ":" .. table.concat(ks, ",") .. " " end
                end
            end
        end
        if next(t) then
            if R.kbind and R.kbind_sig ~= sig then log_msg("Keyboard layout changed in the game's options") end
            if not R.kbind then
                local function k(a) return table.concat(t[a] or {}, "/") end
                log_msg(string.format("Keyboard layout (from the game, key codes): forward %s, back %s, left %s, right %s, skill modifier %s, dash %s, jump %s",
                    k(44), k(45), k(46), k(47), k(14), k(4), k(3)))
            end
            R.kbind, R.kbind_sig = t, sig
        end
    end)
    if not ok then R.kbind_err = tostring(err) end
end
-- is a key the game has that action on held? (fallback key when the game's table is not read)
R.key_held = function(action, fallback_vk)
    local a = S.ACTION_ENUM and S.ACTION_ENUM[action]
    local ks = a and R.kbind and R.kbind[a]
    if not ks then return fallback_vk ~= nil and S.is_key_down_safe(fallback_vk) end
    for _, k in ipairs(ks) do if S.is_key_down_safe(k) then return true end end
    return false
end
-- the mod's own keys that the game also uses for something (shown in the settings window, logged once)
R.key_clashes = function()
    local out = {}
    if not R.kbind then return out end
    local names = {}
    for nm, v in pairs(S.ACTION_ENUM or {}) do if type(v) == "number" and not names[v] then names[v] = nm end end
    for label, vk in pairs(cfg.keys or {}) do
        if type(vk) == "number" and vk ~= 0 and cfg.keys[tostring(label) .. "_ctrl"] ~= true then
            for a, ks in pairs(R.kbind) do
                for _, k in ipairs(ks) do
                    if k == vk then out[#out + 1] = string.format("%s (key code %d) is also the game's %s", tostring(label), vk, tostring(names[a] or a)) end
                end
            end
        end
    end
    table.sort(out)
    return out
end

-- v0.9.124 the button (mask) the game has an action on; the first one when there are several. nil = not read.
R.bind_mask = function(action)
    local l = R.bind and R.bind.by and R.bind.by[action]
    return l and l[1] or nil
end
-- is that action's button held in this pad state? (any of its buttons; fallback mask when the game's list is not read)
R.bind_held = function(action, btn, fallback)
    local l = R.bind and R.bind.by and R.bind.by[action]
    if not l then return fallback ~= nil and fallback ~= 0 and (btn & fallback) == fallback end
    for _, m in ipairs(l) do if (btn & m) == m then return true end end
    return false
end
R.btn_text = function(mask)
    if not mask or mask == 0 then return nil end
    local pv, parts = coop_pad_values(), {}
    for _, m in ipairs(R.BTN_NAMES) do if pv[m[1]] and (mask & pv[m[1]]) ~= 0 then parts[#parts + 1] = m[2] end end
    if #parts == 0 then return nil end
    return table.concat(parts, "+")
end
R.bind_label = function(slot)
    local t = R.btn_text(R.bind and R.bind.pad[slot])
    if not t then return nil end
    return (R.btn_text(R.bind_mask("Shift1")) or "L1") .. "+" .. t
end
R.PAD_XBOX = { { "Square", "X" }, { "Triangle", "Y" }, { "Circle", "B" }, { "Cross", "A" },
               { "L1", "LB" }, { "R1", "RB" }, { "L2", "LT" }, { "R2", "RT" } }
-- 0.9.172-dev38 (the tester: the skill lists flipped between Xbox and PlayStation names "for everyone not just the
-- applicable controlled pawn"): each player's list follows their own controller. dev_addr = that controller's address
-- (R.tp.p2, a slot's dev); its kind is read once a second per controller. nil / unknown: the last-used controller.
R.dev_style_c = {}
R.dev_style = function(dev_addr)
    if cfg.coop_pad_names == 2 then return "ps" elseif cfg.coop_pad_names == 3 then return "xbox" end
    if not dev_addr or dev_addr == R.KB_ADDR then return R.pad_style() end
    local now = os.clock()
    local c = R.dev_style_c[dev_addr]
    if c and now < c.t then return c.v end
    local v = c and c.v or nil
    pcall(function()
        for _, d in ipairs(R.tp_devs()) do
            if d:get_address() == dev_addr then
                local k = d:call("get_DeviceKindDetails")
                if k == 5 or k == 6 or k == 8 or k == 9 then v = "ps" elseif k and k >= 11 and k <= 23 then v = "xbox" end
            end
        end
    end)
    R.dev_style_c[dev_addr] = { v = v, t = now + 1.0 }
    return v or R.pad_style()
end
R.pad_label = function(lbl, style)
    if (style or R.pad_style()) ~= "xbox" then return lbl end
    for _, m in ipairs(R.PAD_XBOX) do lbl = lbl:gsub(m[1], m[2]) end
    return lbl
end
-- v0.9.38 / 0.9.88 end whatever the pawn's AI is doing. At possession start, and (0.9.88) again whenever a decision is
-- found running while he is possessed: a pawn order given during possession (Go, Come, Help, Wait reach every pawn)
-- started a new one and the possessed pawn ran off on it (reported: a possessed Archer pawn was still running around from an earlier order).
-- 0.9.176-dev1 (tavern hang): one line on what the played pawn is doing, for the per-frame trace
R.trace_pawn_state = function()
    local pc = state.pawn_chara
    if not pc then return nil end
    local out = "?"
    pcall(function()
        local f = pc:call("get_ActionManager"):get_field("Fsm")
        out = tostring(f:call("getCurrentNodeName(System.UInt32)", 0)) .. " | " .. tostring(f:call("getCurrentNodeName(System.UInt32)", 1))
    end)
    pcall(function()
        local aidm = call(pc, "get_AIDecisionMaker")
        local ex = aidm and call(aidm, "get_DecisionModule"):call("get_DecisionExecutor")
        local d = ex and ex:call("get_ExecutingDecision")
        local pk = d and d:call("get_ActionPackData")
        local pn = "none"
        if pk then pcall(function() pn = tostring(pk:call("get_Path") or pk:call("ToString")) end) end
        out = out .. " | decision " .. (d and pn or "none")
    end)
    pcall(function()
        local im = sdk.get_managed_singleton("app.InteractManager")
        out = out .. " | interact " .. ((im and im:call("getActiveInteract(app.Character)", pc)) and "active" or "none")
    end)
    return out
end
R.pawn_ai_try = function(how)
    local pc = state.pawn_chara
    if not pc then return "no pawn played" end
    local ok, err = pcall(function()
        if how == "loco" then
            pc:call("get_ActionManager"):call("requestActionCore(app.ActionManager.Priority, System.String, System.UInt32)", 0, "NormalLocomotion", 0)
        elseif how == "idle" then
            local sel = pc:call("get_HumanActionSelector")
            sel:call("requestIdleImpl(System.Boolean)", true)
        elseif how == "end" then
            local ex = pc:call("get_AIDecisionMaker"):call("get_DecisionModule"):call("get_DecisionExecutor")
            ex:call("endDecision")
        elseif how == "im_cancel" or how == "im_end" then
            local im = sdk.get_managed_singleton("app.InteractManager")
            im:call((how == "im_cancel" and "cancelInteract" or "endInteract") .. "(app.Character)", pc)
        elseif how == "npc_cancel" then
            sdk.find_type_definition("app.NPCUtil"):get_method("cancelInteract(app.Character, System.Boolean, System.Boolean)"):call(nil, pc, false, false)
        else
            error("unknown how " .. tostring(how))
        end
    end)
    log_msg("pawn_ai " .. tostring(how) .. ": " .. (ok and "done" or tostring(err)) .. " | " .. tostring(R.trace_pawn_state and R.trace_pawn_state()))
    return ok and "ok" or tostring(err)
end

-- shared with the modules loaded after this one (see shared.lua)
S.compute_camera_move_angle_deg = compute_camera_move_angle_deg
S.update_pawn_lockon_target, S.pawn_do_draw = update_pawn_lockon_target, pawn_do_draw
S.pawn_do_sheathe, S.node_names = pawn_do_sheathe, node_names
