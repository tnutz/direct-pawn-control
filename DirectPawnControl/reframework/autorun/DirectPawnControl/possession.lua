-- Direct Pawn Control: input processor rebinding, start / stop possession.
-- Part of DirectPawnControl.lua, which loads the files in this folder in order (this one is 08 of 26).
-- Never run on its own: REFramework only runs the files directly in reframework/autorun.
local S = require("DirectPawnControl/shared")
local dev_error, cfg, R, write_trace, log_msg, call = S.dev_error, S.cfg, S.R, S.write_trace, S.log_msg, S.call
local field, set_field, ensure_enums, get_skill_ctx = S.field, S.set_field, S.ensure_enums, S.get_skill_ctx
local get_party, state, addr_of, arg_addr, brain, coop = S.get_party, S.state, S.addr_of, S.arg_addr, S.brain, S.coop
local set_pawn_ai_suppressed, attach_camera_to = S.set_pawn_ai_suppressed, S.attach_camera_to
local apply_native_hud_skills, hud_widgets = S.apply_native_hud_skills, S.hud_widgets
local apply_native_hud_gauges, native_release = S.apply_native_hud_gauges, S.native_release
local native_build = S.native_build

-- ----------------------------------------------------------------------------
-- InputProcessor Rebinding Helpers (Angle B - Experimental Mode 1 / Mode 3)
-- ----------------------------------------------------------------------------
local function apply_native_processor_binding(bind_to_pawn)
    local pip = state.arisen_pip
    if not pip then return end

    local param = field(pip, "Param")
    if bind_to_pawn and state.pawn_chara and state.pawn_human then
        write_trace("apply_native_processor_binding(true) begin")

        if cfg.exp_swap_inputs and state.arisen_input and state.pawn_input then
            write_trace("Step 1: swap CharacterInput")
            call(state.pawn_chara, "set_Input", state.arisen_input)
            call(state.arisen_chara, "set_Input", state.pawn_input)
            call(state.pawn_input, "resetAllInputsCore")
            call(state.pawn_input, "resetAxisL")
            call(state.pawn_input, "resetAxisR")
        end

        write_trace("Step 2: set IsPlayer on HumanCommonActionCtrl")
        local hcac = call(state.pawn_human, "get_HumanCommonActionCtrl") or field(state.pawn_human, "<HumanCommonActionCtrl>k__BackingField")
        if hcac then
            set_field(hcac, "IsPlayer", true)
        end
        if cfg.set_human_is_arisen then
            write_trace("Step 2b: set Pawn Human.IsArisen = true")
            set_field(state.pawn_human, "IsArisen", true)
        end

        if cfg.exp_rebind_lockon and state.arisen_lockon_ctrl then
            write_trace("Step 4: rebind LockOnCtrl.Chara to Pawn")
            set_field(state.arisen_lockon_ctrl, "Chara", state.pawn_chara)
            call(state.arisen_lockon_ctrl, "clearLockOn")
        end

        write_trace("Step 5: rebind PlayerInputProcessor & Param")
        local pawn_track = field(state.pawn_human, "Track")
        call(pip, "set_IsEnable", true)
        call(pip, "set_Chara", state.pawn_chara)
        call(pip, "set_Human", state.pawn_human)
        if pawn_track then call(pip, "set_PlayerTrack", pawn_track) end

        if param then
            set_field(param, "Chara", state.pawn_chara)
            set_field(param, "Human", state.pawn_human)
            if pawn_track then set_field(param, "PlayerTrack", pawn_track) end
            call(param, "updateIsMultiButtonSkill")
        end

        if cfg.exp_call_select_proc then
            write_trace("Step 6: pip:selectProcessor()")
            call(pip, "selectProcessor")
        end

        write_trace("Step 7: setInputProcessor on Pawn")
        call(state.arisen_chara, "setInputProcessor", nil)
        call(state.pawn_chara, "setInputProcessor", pip)

        if cfg.swap_player_comp_refs and state.arisen_player_comp then
            write_trace("Step 8: swap app.Player.Chara/Human")
            set_field(state.arisen_player_comp, "Chara", state.pawn_chara)
            set_field(state.arisen_player_comp, "Human", state.pawn_human)
        end
        if cfg.swap_manual_player then
            write_trace("Step 9: CharacterManager:setManualPlayer(pawn)")
            local cm = sdk.get_managed_singleton("app.CharacterManager")
            if cm then
                call(cm, "setManualPlayer", state.pawn_chara)
            end
        end
        write_trace("apply_native_processor_binding(true) complete")
    else
        write_trace("apply_native_processor_binding(false) begin")
        if state.arisen_chara and state.arisen_input then
            call(state.arisen_chara, "set_Input", state.arisen_input)
        end
        if state.pawn_chara and state.pawn_input then
            call(state.pawn_chara, "set_Input", state.pawn_input)
        end

        if state.pawn_human then
            local hcac = call(state.pawn_human, "get_HumanCommonActionCtrl") or field(state.pawn_human, "<HumanCommonActionCtrl>k__BackingField")
            if hcac then
                set_field(hcac, "IsPlayer", state.pawn_orig_is_player or false)
            end
            set_field(state.pawn_human, "IsArisen", state.pawn_orig_is_arisen or false)
        end
        if state.pawn_chara then
            call(state.pawn_chara, "setInputProcessor", nil)
            if cfg.exp_add_player_sel then
                local sel = call(state.pawn_chara, "get_HumanActionSelector")
                if sel then call(sel, "updateCurrentSelector") end
            end
        end

        if state.arisen_lockon_ctrl and state.arisen_chara then
            set_field(state.arisen_lockon_ctrl, "Chara", state.arisen_chara)
            call(state.arisen_lockon_ctrl, "clearLockOn")
        end

        if state.arisen_chara and state.arisen_human then
            call(pip, "set_Chara", state.arisen_chara)
            call(pip, "set_Human", state.arisen_human)
            if state.arisen_track then call(pip, "set_PlayerTrack", state.arisen_track) end
            if param then
                set_field(param, "Chara", state.arisen_chara)
                set_field(param, "Human", state.arisen_human)
                if state.arisen_track then set_field(param, "PlayerTrack", state.arisen_track) end
                call(param, "updateIsMultiButtonSkill")
            end
            if cfg.exp_call_select_proc then
                call(pip, "selectProcessor")
            end
            call(pip, "set_IsEnable", true)
            call(state.arisen_chara, "setInputProcessor", pip)
        end

        if state.arisen_player_comp and state.arisen_chara and state.arisen_human then
            set_field(state.arisen_player_comp, "Chara", state.arisen_chara)
            set_field(state.arisen_player_comp, "Human", state.arisen_human)
        end
        if cfg.swap_manual_player then
            local cm = sdk.get_managed_singleton("app.CharacterManager")
            if cm and state.arisen_chara then
                call(cm, "setManualPlayer", state.arisen_chara)
            end
        end
        write_trace("apply_native_processor_binding(false) complete")
    end
end

-- ----------------------------------------------------------------------------
-- Start / Stop Pawn Possession
-- ----------------------------------------------------------------------------
-- v0.9.169 switch transition (requested: "establish the pawn we're about to control, maybe a bit of a slowdown, and a
-- nice transition to them ... highlight the pawn ... something that matches the native game's aesthetic").
-- Until now the camera was retargeted with registerTargetObject + onWarpTarget: an instant cut. Now, when control
-- changes hands, the camera first turns (from where it is) to look at the character you are about to play, then
-- glides to wherever the game's own camera wants to be behind them, while the game runs slowed and eases back to
-- full speed. The game's camera is retargeted at once as before; DPC only overrides the drawn camera pose for the
-- length of the transition (on the camera joint, in a post-hook on MainCameraController.lateUpdate), so
-- when it ends the game's camera is simply where it already was. Timings run on real time, not game time.
-- Glow: the game's own rim lights (app.MIRimLightHash, e.g. PawnRimStone) requested on each of the character's
-- MaterialInterpolationRimLight parts and finished after switch_cine_glow_s. Slow-down: each object's app.WorkRate (see R.cine_timescale).
-- Never in co-op, never on a load / teardown release; anything left (time scale, glow) is undone on release,
-- world loading and Reset Scripts.
R.CINE_GLOWS = {
    { "", "No glow" },
    { "RimLightRevival", "Revival (sky blue / pale gold)", 0xFFFFC828, 0xFFA0FFE6 },
    { "RimLightInteractLarge", "Can interact (amber / blue, subtle)", 0xFF64B4FF, 0xFFF08C3C },
    { "PawnRimStone", "Riftstone (blue / cyan)", 0xFFFF7850, 0xFFFFFF78 },
    { "RimLightSummon", "Summon (violet)", 0xFFFF1E50, 0xFFFF3C64 },
    { "ChRecovery", "Healing (green)", 0xFF328069, 0xFF64FFD2 },
    { "AstralPlayer", "Astral (soft blue)", 0xFFFF463C, 0xFFFF6E64 },
    { "RimLightPawnLift", "Pawn lift (green / deep blue)", 0xFF20FF40, 0xFFB44000 },
}
R.CINE_PROFILES = { "Instant (cut)", "Establish (pull back, then in)", "Bird's-eye (up into the sky, then down)", "Custom" }
R.cine_params = function()
    local pr = cfg.switch_cine_profile or 2
    if pr == 2 then return { look = 0.75, hold = 0.20, glide = 0.95, pull = 3.0, rise = 2.0, slow = cfg.switch_cine_slowmo or 0.4 } end
    if pr == 3 then return { look = 1.10, hold = 0.35, glide = 1.30, pull = 4.0, rise = 14.0, slow = cfg.switch_cine_slowmo or 0.4 } end
    return { look = cfg.switch_cine_look_s or 0.45, hold = cfg.switch_cine_hold_s or 0.15, glide = cfg.switch_cine_glide_s or 0.8,
             pull = cfg.switch_cine_pull and (cfg.switch_cine_pull_m or 2.0) or nil, rise = cfg.switch_cine_rise_m or 1.2, slow = cfg.switch_cine_slowmo or 0.4 }
end
R.cine_ease = function(x) x = math.max(0, math.min(1, x)); return x * x * (3 - 2 * x) end
R.cine_slerp = function(a, b, t)
    local ax, ay, az, aw = a[1], a[2], a[3], a[4]
    local bx, by, bz, bw = b[1], b[2], b[3], b[4]
    local d = ax * bx + ay * by + az * bz + aw * bw
    if d < 0 then bx, by, bz, bw, d = -bx, -by, -bz, -bw, -d end
    local k0, k1
    if d > 0.9995 then k0, k1 = 1 - t, t
    else
        local th = math.acos(d); local sn = math.sin(th)
        k0, k1 = math.sin((1 - t) * th) / sn, math.sin(t * th) / sn
    end
    local x, y, z, w = ax * k0 + bx * k1, ay * k0 + by * k1, az * k0 + bz * k1, aw * k0 + bw * k1
    local n = math.sqrt(x * x + y * y + z * z + w * w)
    return { x / n, y / n, z / n, w / n }
end
-- rotation of a camera at p looking at q (the engine's cameras look along their -Z axis)
R.cine_look = function(p, q)
    local dx, dy, dz = q[1] - p[1], q[2] - p[2], q[3] - p[3]
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if len < 0.01 then return nil end
    dx, dy, dz = dx / len, dy / len, dz / len
    local yaw = math.atan(-dx, -dz)
    local pitch = math.asin(math.max(-1, math.min(1, dy)))
    local sy, cy = math.sin(yaw / 2), math.cos(yaw / 2)
    local sx, cx = math.sin(pitch / 2), math.cos(pitch / 2)
    return { cy * sx, sy * cx, -sy * sx, cy * cx }
end
-- v0.9.169b: the pose comes from MainCameraController._Position / _Rotation and goes to its _CameraJoint, inside
-- a post-hook on its lateUpdate (the way Camera Distance does it). 0.9.169 wrote the camera GameObject's own
-- transform at BeginRendering: that transform is not rewritten by the game, can read ~2 km off (a different
-- coordinate frame, seen in the logs before this feature), and after a few switches the camera and the nametags
-- came apart (the tester, [time]). The joint is rewritten by the controller every frame, so nothing can stick.
R.cine_mcc = function()
    local cm = sdk.get_managed_singleton("app.CameraManager")
    return cm and cm:call("getMainCameraController", 0)
end
-- Game speed while switching. v0.9.169 first used app.TimeManager.setTimeScale: that is the speed of the in-game
-- day clock, not of the action (the tester caught it). The real slow motion is each object's app.WorkRate
-- (NextRateValue / NextApplyRate), the way Pawn Tactical Wheel does it: the player, the party, every enemy and every
-- shell (arrows, spells), the list gathered again every 0.15 s and written every frame while it lasts.
R.cine_rates_gather = function()
    local out, seen = {}, {}
    local function add_chara(c)
        if not c then return end
        local ok, a = pcall(c.get_address, c)
        if not ok or not a or seen[a] then return end
        seen[a] = true
        local okw, wr = pcall(c.get_field, c, "<WorkRate>k__BackingField")
        if okw and wr then out[#out + 1] = wr end
    end
    pcall(function() add_chara(sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer")) end)
    pcall(function() add_chara(state.arisen_chara) end)
    pcall(function()
        local l = sdk.get_managed_singleton("app.PawnManager"):call("get_PawnCharacterList")
        for i = 0, l:call("get_Count") - 1 do add_chara(l:call("get_Item", i)) end
    end)
    pcall(function()
        local arr = sdk.get_managed_singleton("app.EnemyManager"):call("getAllEnemies")
        for i = 0, arr:call("get_Count") - 1 do
            local e = arr:call("get_Item", i)
            add_chara(e and e:get_field("_Chara"))
        end
    end)
    pcall(function()
        local list = sdk.get_managed_singleton("app.ShellManager"):get_field("ShellList")
        local items, size = list:get_field("_items"), list:get_field("_size") or 0
        local wt = sdk.typeof("app.WorkRate")
        for i = 0, size - 1 do
            local sh = items:get_element(i)
            local okw, wr = pcall(function() return sh and sh:call("get_GameObject"):call("getComponent(System.Type)", wt) end)
            if okw and wr then out[#out + 1] = wr end
        end
    end)
    return out
end
R.cine_rates_write = function(v)
    local r = math.max(0.005, v)
    for _, wr in ipairs(R.cine_rates or {}) do
        pcall(function() wr:set_field("NextRateValue", r); wr:set_field("NextApplyRate", r) end)
    end
end
R.cine_timescale = function(v)
    if v == nil then
        if R.cine_ts_set then R.cine_rates_write(1.0) end
        R.cine_ts_set, R.cine_rates, R.cine_rates_t = false, nil, nil
        return
    end
    local now = os.clock()
    if not R.cine_rates or now - (R.cine_rates_t or 0) >= 0.15 then
        R.cine_rates, R.cine_rates_t = R.cine_rates_gather(), now
    end
    R.cine_ts_set = true
    R.cine_rates_write(v)
end
R.cine_glow = function(chara, name, on)
    if not chara or not name or name == "" then return end
    pcall(function()
        local f = sdk.find_type_definition("app.MIRimLightHash"):get_field(name)
        if not f then return end
        local h = f:get_data(nil)
        local rm = chara:call("get_GameObject"):call("getComponent(System.Type)", sdk.typeof("app.MaterialInterpolationRequestManager"))
        if not rm then return end
        -- as the game calls it (logged 2026-11-19): category RimLight (8), then -1, -1 = all materials. 0, 0 drew nothing.
        local sig = on and "requestMaterialMode(System.UInt32, app.MaterialInterpolationRequestManager.RequestListCategory, System.Int32, System.Int32)"
            or "finishMaterialMode(System.UInt32, app.MaterialInterpolationRequestManager.RequestListCategory, System.Int32, System.Int32)"
        rm:call(sig, h, 8, -1, -1)
    end)
end
-- 0.9.172-dev38: timed glows besides the switch glow (a player leaving co-op), each finished after switch_cine_glow_s
R.glows_timed = {}
R.glow_for = function(chara, name, secs)
    if not chara or not name or name == "" then return end
    R.cine_glow(chara, name, true)
    R.glows_timed[#R.glows_timed + 1] = { chara = chara, name = name, t_end = os.clock() + (secs or cfg.switch_cine_glow_s or 1.8) }
end
-- 0.9.172-dev40 (the tester: "use one of the brighter highlights like astral for when a co-op player joins. Bonus points if
-- we can color a highlight the color of their character target reticles/bookmarks (and maybe even leave that on)").
-- The game's rim lights come in fixed colours, so each player gets the one closest to their marker colour: player 2
-- light blue (Astral), 3 green (Healing), 4 magenta / violet (Summon), 5 red (Berserker), 6+ Astral.
-- dev42: player 1 (the tester: "make arisen glow his orange when co-op starts") gets the amber "can interact" light
R.PLAYER_GLOWS = { [1] = "RimLightInteractLarge", [2] = "AstralPlayer", [3] = "ChRecovery", [4] = "RimLightSummon", [5] = "Berserker" }
R.pglow = {}
-- dev45: the kept glow per player: the "keep glowing" tick for everyone, then each player's own tick under it
R.glow_keep_for = function(n)
    if not cfg.coop_glow_split and R.views_now and R.views_now() then return false end -- dev56 / dev57: no kept glow in split screen
    return cfg.coop_glow_keep == true and (cfg.coop_glow_keep_p or {})["p" .. n] ~= false
end
R.pglow_now = function()
    local cur = {}
    if coop.active and state.arisen_chara and not (R.cp and R.cp.ar2) then cur[1] = state.arisen_chara end -- dev42: player 1's Arisen
    if R.s2 and R.s2.active and R.s2.chara then cur[R.s2.player or 2] = R.s2.chara
    elseif coop.active and state.active and state.pawn_chara and not (R.tp.start_kb and not R.tp.p2) then
        cur[2] = state.pawn_chara -- dev48: not while Ctrl + F6 waits for player 2's L3 + R3; dev49: lit the moment the controller is claimed, not on release (the tester: "it wasn't clear when they actually joined")
    end
    -- dev52: player 1 on a pawn (both-pawns arrangement, or player 2 on the Arisen)
    if R.cp and R.cp.on and R.cp.mode == "pawns" and state.active and state.pawn_chara then
        cur[1] = state.pawn_chara
        if R.cp.ar2 and state.arisen_chara then cur[2] = state.arisen_chara end
    end
    for n, sl in pairs(R.np and R.np.slots or {}) do if sl.active and sl.chara then cur[n] = sl.chara end end
    return cur
end
R.pglow_tick = function()
    local now = os.clock()
    if now < (R.pglow_next or 0) then return end
    R.pglow_next = now + 0.25
    -- dev56 (the tester: in split screen "the players know who they are and it's clear that co-op has started"; the glow
    -- is a shared-screen feature): no join or kept glow while the screen is split, unless coop_glow_split
    -- dev57 (the tester: player 2 "will need to flash when they take over from a ctrl+F6 split screen since they can't
    -- really tell they've taken over until then"): the short join glow stays; only the kept glow is off when split
    local cur = (cfg.coop_join_glow ~= false) and R.pglow_now() or {}
    for n, g in pairs(R.pglow) do
        local c = cur[n]
        if not c or c:get_address() ~= g.addr then
            if g.kept then pcall(R.cine_glow, g.chara, g.name, false) end
            R.pglow[n] = nil
        elseif g.kept and not R.glow_keep_for(n) then -- unticked: out, no fresh join glow
            pcall(R.cine_glow, g.chara, g.name, false)
            g.kept = false
        end
    end
    for n, c in pairs(cur) do
        -- dev41 (the tester: the kept glow "needs to come back on if the checkbox is turned on while already playing"):
        -- a player with only the short join glow gets the kept one as soon as the box is ticked
        local g0 = R.pglow[n]
        -- 0.9.173-dev1: a new colour picked mid-play: the old light goes out and the new one comes on
        if g0 and g0.name ~= R.player_glow(n) then
            if g0.kept then pcall(R.cine_glow, g0.chara, g0.name, false) end
        end
        if g0 and (g0.name ~= R.player_glow(n) or (R.glow_keep_for(n) and not g0.kept)) then
            local recolour = g0.name ~= R.player_glow(n)
            for i = #R.glows_timed, 1, -1 do
                local t = R.glows_timed[i]
                if t.name == g0.name and t.chara:get_address() == g0.addr then
                    table.remove(R.glows_timed, i)
                    if recolour then pcall(R.cine_glow, t.chara, t.name, false) end
                end
            end
            R.pglow[n] = nil
        end
        if not R.pglow[n] then
            local name = R.player_glow(n)
            if R.glow_keep_for(n) then
                pcall(R.cine_glow, c, name, true)
                R.pglow[n] = { chara = c, addr = c:get_address(), name = name, kept = true }
            else
                pcall(R.glow_for, c, name, math.max(cfg.switch_cine_glow_s or 1.8, 2.5))
                R.pglow[n] = { chara = c, addr = c:get_address(), name = name }
            end
        end
    end
end
re.on_frame(function() pcall(R.pglow_tick) end)
re.on_script_reset(function() for _, g in pairs(R.pglow) do if g.kept then pcall(R.cine_glow, g.chara, g.name, false) end end end)
-- 0.9.173-dev1: the Preview button beside each player's colour. Not on a character already lit in that light (the
-- preview's end would put the kept glow out too).
R.color_preview = function(n)
    local cur = R.pglow_now()
    -- dev4: state.arisen_chara is only set while a pawn is played, so with nobody taken over there was nothing to light
    local ch = cur[n] or (state.active and state.pawn_chara) or state.arisen_chara or R.real_player()
    if not ch then return end
    local name = R.player_glow(n)
    for _, g in pairs(R.pglow) do
        if g.name == name and g.addr == ch:get_address() then R.ta_note("Already glowing in that colour"); return end
    end
    R.glow_for(ch, name, 2.5)
end
R.leave_glow = function(chara)
    if cfg.coop_leave_glow and cfg.coop_leave_glow ~= "" then pcall(R.glow_for, chara, cfg.coop_leave_glow) end
end
re.on_frame(function()
    local now = os.clock()
    for i = #R.glows_timed, 1, -1 do
        local g = R.glows_timed[i]
        if now >= g.t_end then table.remove(R.glows_timed, i); R.cine_glow(g.chara, g.name, false) end
    end
end)
re.on_script_reset(function() for _, g in ipairs(R.glows_timed) do R.cine_glow(g.chara, g.name, false) end end)
R.cine_glow_off = function()
    local g = R.cine_glowing
    if g then R.cine_glowing = nil; R.cine_glow(g.chara, g.name, false) end
end
R.cine_stop = function(why)
    if R.cine and R.api_fire then pcall(R.api_fire, "transition_end", { to_name = state.active and state.pawn_name or "Arisen" }) end
    R.cine = nil
    R.cine_timescale(nil)
    if why ~= "keep glow" then R.cine_glow_off() end
end
R.cine_begin = function(chara)
    if coop.active or not chara then return end
    if R.ferry_on and R.ferry_on() then return end -- 0.9.178-dev3: never during a Ferrystone (fixes_world.lua)
    if R.api_claimed and R.api_claimed("camera.transition") then return end -- v0.9.170: another mod does the transition
    -- 0.9.173: a mod that holds camera.follow places the camera itself, so the transition does not move it either
    -- (only the glow plays). Seen as a question from a mod author: holding follow alone left DPC's glide fighting his camera.
    local follow_claimed = R.api_claimed and R.api_claimed("camera.follow")
    if follow_claimed or not cfg.switch_cine or (cfg.switch_cine_profile or 2) == 1 then -- no camera move; the glow still plays
        if cfg.switch_glow and cfg.switch_glow ~= "" then
            R.cine_glow_off()
            R.cine_glow(chara, cfg.switch_glow, true)
            R.cine_glowing = { chara = chara, name = cfg.switch_glow, t_end = os.clock() + (cfg.switch_cine_glow_s or 1.4) }
        end
        return
    end
    local P = R.cine_params()
    local ok, err = pcall(function()
        local mcc = R.cine_mcc()
        local joint = mcc and mcc:get_field("_CameraJoint")
        if not joint then return end
        local p, r = joint:call("get_Position"), joint:call("get_Rotation")
        R.cine_install()
        R.cine_glow_off()
        if R.api_fire then
            -- dev6: a switch during a running transition ends that one first (api-1: starts without ends)
            if R.cine then pcall(R.api_fire, "transition_end", { to_name = state.active and state.pawn_name or "Arisen", interrupted = true }) end
            pcall(R.api_fire, "transition_start", { style = cfg.switch_cine_profile, chara = chara })
        end
        R.cine = { t0 = os.clock(), chara = chara, p0 = { p.x, p.y, p.z }, q0 = { r.x, r.y, r.z, r.w }, P = P }
        -- pull-out point: back and up from the midpoint between who the camera follows now and who comes next
        pcall(function()
            if not P.pull then return end
            local c = R.cine
            local og = mcc:call("get_TargetObject")
            local a = og and og:call("get_Transform"):call("get_Position")
            local b = chara:call("get_GameObject"):call("get_Transform"):call("get_Position")
            if not (a and b) then return end
            local A, B = { a.x, a.y + 1.2, a.z }, { b.x, b.y + 1.2, b.z }
            -- skip it when the new character is already near the middle of the view
            local fx, fy, fz = -2 * (r.x * r.z + r.w * r.y), -2 * (r.y * r.z - r.w * r.x), -(1 - 2 * (r.x * r.x + r.y * r.y))
            local dx, dy, dz = B[1] - p.x, B[2] - p.y, B[3] - p.z
            local dl = math.sqrt(dx * dx + dy * dy + dz * dz)
            if P.rise < 5 and dl > 0.1 and (fx * dx + fy * dy + fz * dz) / dl > math.cos(math.rad(20)) then return end
            local M = { (A[1] + B[1]) / 2, (A[2] + B[2]) / 2, (A[3] + B[3]) / 2 }
            local vx, vz = p.x - M[1], p.z - M[3]
            local vl = math.sqrt(vx * vx + vz * vz)
            if vl < 0.5 then vx, vz, vl = -fx, -fz, math.sqrt(fx * fx + fz * fz) end
            if vl < 0.01 then return end
            vx, vz = vx / vl, vz / vl
            local sep = math.sqrt((A[1] - B[1]) ^ 2 + (A[3] - B[3]) ^ 2)
            local rad = math.max(vl, sep * 0.6 + 3.0) + P.pull
            c.pp = { M[1] + vx * rad, math.max(p.y, M[2]) + P.rise, M[3] + vz * rad }
        end)
        R.cine_n = (R.cine_n or 0) + 1
        if (P.slow or 1) < 0.99 then R.cine_timescale(math.max(0.05, P.slow)) end
        if cfg.switch_glow and cfg.switch_glow ~= "" then
            R.cine_glow(chara, cfg.switch_glow, true)
            local whole = (P.look or 0) + (P.hold or 0) + (P.glide or 0) + 0.3 -- v0.9.169: on for the whole transition
            R.cine_glowing = { chara = chara, name = cfg.switch_glow, t_end = os.clock() + math.max(cfg.switch_cine_glow_s or 1.4, whole) }
        end
    end)
    if not ok then R.cine_stop(); dev_error("switch transition", err) end
end
R.cine_frame = function(mcc)
    local c = R.cine
    if not c then return end
    local ok, err = pcall(function()
        local now = os.clock()
        local P = c.P or R.cine_params()
        local look_s = math.max(0.0, P.look or 0.35)
        local hold_s = math.max(0.0, P.hold or 0.0)
        local glide_s = math.max(0.05, P.glide or 0.8)
        local t = now - c.t0
        if t >= look_s + hold_s + glide_s or coop.active then R.cine_stop("keep glow"); return end
        local joint = mcc and mcc:get_field("_CameraJoint")
        if not joint then R.cine_stop("keep glow"); return end
        -- where the game's camera is this frame (its final pose, incl. Camera Distance when its hook ran first)
        local gp, gr = joint:call("get_Position"), joint:call("get_Rotation")
        local pg, qg = { gp.x, gp.y, gp.z }, { gr.x, gr.y, gr.z, gr.w }
        -- the look-at point: the new character's chest
        local tp
        pcall(function()
            local cp = c.chara:call("get_GameObject"):call("get_Transform"):call("get_Position")
            tp = { cp.x, cp.y + 1.4, cp.z }
        end)
        -- game speed: slow, then eased back to full speed_back_s before the camera lands (the tester: it felt sluggish;
        -- the move is still going but it is good enough to take control)
        if R.cine_ts_set then
            local total = look_s + hold_s + glide_s
            local t_full = math.max(0, total - (cfg.switch_cine_speed_back_s or 0.95))
            local t_ramp = math.max(0, t_full - math.max(0.01, cfg.switch_cine_speed_ramp_s or 0.5))
            local s0 = math.max(0.05, P.slow or 1)
            if t >= t_full then R.cine_timescale(nil) -- full speed: let go of the game's rates
            elseif t >= t_ramp then R.cine_timescale(s0 + (1 - s0) * R.cine_ease((t - t_ramp) / math.max(0.01, t_full - t_ramp)))
            else R.cine_timescale(s0) end
        end
        local pp = c.pp or c.p0 -- where the look phase ends (the pull-out point, or where the camera was)
        local pos, rot
        if t < look_s then
            local e = R.cine_ease(t / math.max(look_s, 0.001))
            pos = { c.p0[1] + (pp[1] - c.p0[1]) * e, c.p0[2] + (pp[2] - c.p0[2]) * e, c.p0[3] + (pp[3] - c.p0[3]) * e }
            local qn = (tp and R.cine_look(pos, tp)) or qg
            rot = R.cine_slerp(c.q0, qn, e)
        elseif t < look_s + hold_s then
            pos = pp
            rot = (tp and R.cine_look(pp, tp)) or qg
        else
            local ql = (tp and R.cine_look(pp, tp)) or qg
            local u = R.cine_ease((t - look_s - hold_s) / glide_s)
            pos = { pp[1] + (pg[1] - pp[1]) * u, pp[2] + (pg[2] - pp[2]) * u, pp[3] + (pg[3] - pp[3]) * u }
            rot = R.cine_slerp(ql, qg, u)
        end
        gp.x, gp.y, gp.z = pos[1], pos[2], pos[3]
        joint:call("set_Position", gp)
        gr.x, gr.y, gr.z, gr.w = rot[1], rot[2], rot[3], rot[4]
        joint:call("set_Rotation", gr)
        c.frames = (c.frames or 0) + 1
        R.cine_last = { t = t, frames = c.frames }
    end)
    if not ok then R.cine_stop(); R.cine_err = tostring(err); dev_error("switch transition", err) end
end
-- installed at the first switch, so it is registered after Camera Distance's own lateUpdate hook and runs after it
R.cine_install = function()
    if R.cine_hooked then return end
    R.cine_hooked = true
    local td = sdk.find_type_definition("app.MainCameraController")
    local m = td and td:get_method("lateUpdate")
    if not m then return end
    sdk.hook(m, function(args)
        if R.cine then thread.get_hook_storage().cine_mcc = sdk.to_managed_object(args[2]) end
    end, function(retval)
        if R.cine then
            local mcc = thread.get_hook_storage().cine_mcc
            if mcc then R.cine_frame(mcc) end
        end
        return retval
    end)
end
re.on_frame(function() local g = R.cine_glowing; if g and os.clock() >= g.t_end then R.cine_glow_off() end end)

local function release_possession(reason)
    if not state.active then return end
    R.cp_last_rel = reason -- v0.9.171: why the main played pawn was let go (co-op, both on pawns)
    write_trace("release_possession begin", reason)
    log_msg("Releasing possession (" .. tostring(reason or "manual") .. ") -> Returning to Arisen")
    R.note = { text = "Back to the Arisen", t_end = os.clock() + 3.0 }
    if R.aim_stop then pcall(R.aim_stop) end -- v0.9.29: hand the aim camera back
    if R.ar_lock then pcall(R.ar_lock_remove, "release") end -- v0.9.168: the Arisen takes the game's lock-on back
    R.ar_lock_failed = nil
    -- v0.9.81: the brain sprints (a toggle) when its target is far. Handing the Arisen back with the sprint state
    -- still set left him unable to regain stamina until he ran dry (the tester, 2026-11-16). Clear it.
    pcall(function()
        local hu = state.arisen_chara and state.arisen_chara:call("get_Human")
        if hu and hu:call("get_IsDash") then
            hu:call("set_IsDash", false)
            hu:call("set_IsPrevDash", false)
            log_msg("Release: cleared the Arisen's sprint state")
        end
    end)

    local teardown = type(reason) == "string" and reason:find("^teardown") ~= nil
    if R.pf_restore_all then pcall(R.pf_restore_all, reason) end -- v0.9.170: sound settings etc. back to the Arisen
    if R.api_fire then -- v0.9.170 mod API
        local was_coop = coop.active
        pcall(R.api_fire, "release", { player = was_coop and 2 or 1, name = state.pawn_name, reason = tostring(reason or "manual") })
        if reason == "switching pawn" then R.api_switch_from = state.pawn_name end
        if was_coop and reason ~= "switching pawn" then R.api_coop_stop = true end
    end
    if coop.active and reason ~= "switching pawn" and coop.on_release then pcall(coop.on_release, reason) end
    if not brain.solo then brain.on = false; brain.target = nil end -- v0.8: hand the Arisen's input back now
    brain.pawn_native = false -- v0.8.10: never carry the previous pawn's control path into the next possession
    -- 0. End any active guard / aim / sprint on the pawn before releasing (skipped while the scene is unloading)
    if state.pawn_chara and not teardown then
        local sel = call(state.pawn_chara, "get_HumanActionSelector")
        if sel and (state.is_guarding or state.is_aiming or state.is_quickspelling) then
            if state.is_guarding then
                call(sel, "requestAction(System.String, System.UInt32)", "Job01_GuardEnd", 1)
            end
            call(sel, "requestEndAction()")
        end
        call(state.pawn_chara, "setLocomotionSpeed(app.LocomotionSpeedTypeEnum)", 0)
        call(state.pawn_chara, "set_DiscreteLocomotionSpeedType(app.LocomotionSpeedTypeEnum)", 0)
    end
    if state.pawn_human then
        call(state.pawn_human, "set_IsDash(System.Boolean)", false)
        call(state.pawn_human, "set_IsPrevDash(System.Boolean)", false)
        -- 0.9.172: the puppeteer (Thief fallback) turns dash-to-requested-speed on every frame; put back what the game had
        if type(state.pawn_orig_dash_req) == "boolean" then
            pcall(function()
                local hcac = call(state.pawn_human, "get_HumanCommonActionCtrl")
                if hcac then call(hcac, "set_IsEnableDashToRequestedMoveSpeedOfNormalLocomotion(System.Boolean)", state.pawn_orig_dash_req) end
            end)
        end
        state.pawn_orig_dash_req = nil
    end
    R.dash_opt_put(state.pawn_input, state.pawn_dash_opt0)
    state.pawn_dash_opt0 = nil

    -- 1. Restore Native HUD Skills, gauges, minimap & LockOnCtrl
    pcall(apply_native_hud_skills, false)
    pcall(apply_native_hud_gauges, false)
    pcall(native_release)
    state.pawn_sel_addr = 0
    state.hud_shift_held = false
    if state.arisen_lockon_ctrl and state.arisen_chara then
        set_field(state.arisen_lockon_ctrl, "Chara", state.arisen_chara)
        call(state.arisen_lockon_ctrl, "clearLockOn")
    end

    -- 2. Restore InputProcessor & CharacterInput bindings
    if cfg.control_mode == 1 or cfg.control_mode == 3 then
        apply_native_processor_binding(false)
    elseif state.arisen_pip then
        call(state.arisen_pip, "set_IsEnable(System.Boolean)", true)
    end

    -- 3. Re-enable Pawn AI
    set_pawn_ai_suppressed(state.pawn_chara, state.pawn_obj, false, true)

    -- 4. Re-attach MainCameraController to Arisen (not if the Arisen / managers are the ones being destroyed)
    if state.arisen_go and not (teardown and (reason:find("arisen") or reason:find("Manager"))) then
        -- 0.9.178-dev3: no transition on a cutscene or Ferrystone release either (the game's own direction has the
        -- camera, and the slow motion wrote to characters the Ferrystone teleport moves and the area unload frees)
        local quiet = teardown or reason == "loading" or reason == "script reset" or tostring(reason):find("^cutscene") ~= nil
            or (R.ferry_on and R.ferry_on())
        if not quiet then R.cine_begin(state.arisen_chara) else R.cine_stop() end -- v0.9.169
        attach_camera_to(state.arisen_go)
    end

    state.active = false
    R.session_write(false)
    if R.api_coop_stop then R.api_coop_stop = nil; pcall(R.api_fire, "coop_stop", {}) end
    state.frames_since_start = 0
    state.arisen_chara_addr = 0
    state.arisen_skill_ctx_addr = 0
    state.arisen_job_ctx_addr = 0
    state.arisen_pip_addr = 0
    state.far_since_t = nil
    state.pawn_chara = nil
    state.pawn_human = nil
    state.pawn_go = nil
    state.pawn_input = nil
    state.pawn_obj = nil
    state.pending_skill = nil
    state.pending_attack = nil
    state.combo_buffer = nil
    state.active_cast = nil
    state.suppress_loco_until = 0.0
    state.was_moving = false
    state.is_sprinting = false
    state.is_guarding = false
    state.is_aiming = false
    state.is_quickspelling = false
    state.arisen_was_following = false
    state.last_action_str = "Returned to Arisen"
    write_trace("release_possession complete")
end

-- v0.7.6: release BEFORE the scene tears down. Returning to title while possessed crashed twice
-- (DD2.exe+0x5246c38, worker thread): the pawn was destroyed while the camera, the Arisen's LockOnController,
-- HUD widgets and the Arisen's disabled PlayerInputProcessor still pointed at it. The first onDestroy of the
-- possessed pawn, the Arisen, or the Character/Pawn managers now releases possession and restores those.
local function install_teardown_hooks()
    local function chara_hook(type_name, field_names)
        local td = sdk.find_type_definition(type_name)
        local m = td and td:get_method("onDestroy")
        if not m then return end
        sdk.hook(m, function(args)
            if R.s2 and R.s2.active then -- v0.9.171: the second played pawn lets go before it is destroyed
                local a2 = arg_addr(args[2])
                if a2 == R.s2.chara_addr or a2 == R.s2.human_addr then pcall(R.s2_stop, "teardown: " .. type_name .. ".onDestroy") end
            end
            if R.np then -- 0.9.172: players 3+
                for _, sl in pairs(R.np.slots) do
                    if sl.active and (a2 == sl.chara_addr or a2 == sl.human_addr) then pcall(R.s2_stop, "teardown: " .. type_name .. ".onDestroy", sl) end
                end
            end
            if not state.active then return end
            local a = arg_addr(args[2])
            for _, f in ipairs(field_names) do
                local o = state[f]
                if o and addr_of(o) == a then
                    pcall(release_possession, "teardown: " .. type_name .. ".onDestroy (" .. f .. ")")
                    return
                end
            end
        end, function(r) return r end)
    end
    chara_hook("app.Character", { "pawn_chara", "arisen_chara" })
    chara_hook("app.Human", { "pawn_human", "arisen_human" })
    for _, mgr in ipairs({ "app.PawnManager", "app.CharacterManager" }) do
        local td = sdk.find_type_definition(mgr)
        local m = td and td:get_method("onDestroy")
        if m then
            sdk.hook(m, function(args)
                if R.s2 and R.s2.active then pcall(R.s2_stop, "teardown: " .. mgr .. ".onDestroy") end -- v0.9.171
                if R.np then for _, sl in pairs(R.np.slots) do if sl.active then pcall(R.s2_stop, "teardown: " .. mgr .. ".onDestroy", sl) end end end
                if state.active then pcall(release_possession, "teardown: " .. mgr .. ".onDestroy") end
            end, function(r) return r end)
        end
    end
end
install_teardown_hooks()

-- 0.9.176 Leaning pawns (tavern freeze report). A pawn leaning on a wall is in an object interaction
-- (AI pack Common/InteractingWithObject, gimmick Gm80_079 / app.GmAIInteract_02) and its body is held by a motion
-- jack. Ending it from outside (DecisionExecutor.forceEndDecision at take-over, or InteractManager.cancelInteract)
-- runs GmAIInteract_02.onCancelInteractBase -> Gm80_079_interact.requestEndJack -> AdjustJack.reject, which hit an
-- access violation in the engine on a played pawn and froze the game (tavern-lean-3/4/6; the stack is in
-- REFramework's log). Not ending it left the pawn stuck in the lean (tavern-lean-4/5). The game's own way out is an
-- abort: ActiveInteract.IsNeedAbort, which InteractManager handles in its update (onAbortInteractBase). So before a
-- take-over, a pawn in an object interaction is asked to abort and the take-over waits (up to 3 s) until it is
-- free; and the "pawn runs off on an order" guard never force-ends a decision while an interaction is active.
R.busy_interact = function(ch)
    local im = ch and sdk.get_managed_singleton("app.InteractManager")
    if not im then return nil end
    local ok, ai = pcall(im.call, im, "getActiveInteract(app.Character)", ch)
    return ok and ai or nil
end
R.abort_interact = function(ch)
    local ai = R.busy_interact(ch)
    if not ai then return false end
    local ok = pcall(ai.set_field, ai, "IsNeedAbort", true)
    return ok
end
-- 0.9.176-dev7 co-op: the same stand-up-first for co-op take-overs (co-op start, the co-op character change,
-- players 2+ taking a pawn). R.unlean_defer(list of {chara, name}, fn, label): if any of them is in an object
-- interaction, ask it to abort, run fn once all are free (checked every frame, up to 3 s) and return true; else false.
R.unlean_q = {}
R.unlean_defer = function(list, fn, label)
    if not cfg.possess_unlean then return false end
    local busy = {}
    for _, it in ipairs(list) do
        if it.chara and R.busy_interact(it.chara) then R.abort_interact(it.chara); busy[#busy + 1] = it end
    end
    if #busy == 0 then return false end
    local now = os.clock()
    for _, q in ipairs(R.unlean_q) do if q.label == label then return true end end -- already waiting for this
    local names = {}
    for _, it in ipairs(busy) do names[#names + 1] = tostring(it.name) end
    R.unlean_q[#R.unlean_q + 1] = { list = busy, fn = fn, label = label, t0 = now, t_end = now + 3.0, names = table.concat(names, ", ") }
    log_msg(label .. ": " .. table.concat(names, ", ") .. " in an object interaction (leaning, sitting...): asked to stop first")
    R.note = { text = table.concat(names, ", ") .. " stands up...", t_end = now + 1.5 }
    return true
end
R.unlean_tick = function()
    if #R.unlean_q == 0 then return end
    local now = os.clock()
    local q = R.unlean_q[1]
    local free = true
    for _, it in ipairs(q.list) do if R.busy_interact(it.chara) then free = false end end
    if free then
        table.remove(R.unlean_q, 1)
        log_msg(q.label .. ": " .. q.names .. " free after " .. string.format("%.2f", now - q.t0) .. " s")
        local ok, err = pcall(q.fn)
        if not ok then log_msg(q.label .. " after stand-up failed: " .. tostring(err)) end
    elseif now > q.t_end then
        table.remove(R.unlean_q, 1)
        log_msg(q.label .. " cancelled: " .. q.names .. " still in an object interaction after 3 s")
        R.note = { text = q.names .. " is busy, try again", t_end = now + 2.5 }
    end
end
R.chara_of_idx = function(idx)
    if type(idx) ~= "number" then return nil end
    for _, e in ipairs((R.party_all and R.party_all()) or get_party()) do
        if e.idx == idx then return { chara = e.chara, name = e.name } end
    end
    return nil
end
R.possess_wait_tick = function()
    local w = R.possess_wait
    if not w then return end
    local now = os.clock()
    if not R.busy_interact(w.chara) then
        R.possess_wait = nil
        log_msg(tostring(w.name) .. " is free of the interaction after " .. string.format("%.2f", now - w.t0) .. " s; taking control")
        R.possess_retry = true
        R.start_possession(w.idx)
        R.possess_retry = nil
    elseif now > w.t_end then
        R.possess_wait = nil
        log_msg("Take-over of " .. tostring(w.name) .. " cancelled: still in an object interaction after 3 s")
        R.note = { text = tostring(w.name) .. " is busy, try again", t_end = now + 2.5 }
    end
end
-- 0.9.176-dev4 (dev) lean lab: find lean spots, make a pawn use one, abort it. {"cmd":"lean","how":...,"idx":n}
R.lean_lab = function(how, idx)
    local pm = sdk.get_managed_singleton("app.PawnManager")
    local list = pm and pm:call("get_PawnCharacterList")
    if idx and idx < 0 and list then -- -1: the first pawn that is in an object interaction (leaning...)
        for i = 0, list:call("get_Count") - 1 do
            if R.busy_interact(list:call("get_Item", i)) then idx = i; break end
        end
        if idx < 0 then return "no pawn is in an interaction" end
    end
    local ch = list and idx and idx < list:call("get_Count") and list:call("get_Item", idx) or nil
    if how == "coop" then
        log_msg("lean lab: co-op start on pawn " .. tostring(idx) .. (R.busy_interact(ch) and " (in an interaction)" or ""))
        local party = get_party and get_party() or {}
        for _, e in ipairs(party) do
            if e.chara and ch and e.chara:get_address() == ch:get_address() then R.coop_start(e.idx); return "ok" end
        end
        return "pawn not in the party list"
    end
    if how == "possess" then
        log_msg("lean lab: taking control of pawn " .. tostring(idx) .. (R.busy_interact(ch) and " (in an interaction)" or ""))
        local party = get_party and get_party() or {}
        for _, e in ipairs(party) do
            if e.chara and ch and e.chara:get_address() == ch:get_address() then R.start_possession(e.idx); return "ok" end
        end
        return "pawn not in the party list"
    end
    local im = sdk.get_managed_singleton("app.InteractManager")
    if how == "abort" then
        local ok = R.abort_interact(ch)
        log_msg("lean lab abort pawn " .. tostring(idx) .. ": " .. tostring(ok))
        return ok and "ok" or "not in an interaction"
    end
    -- find lean gimmicks in the scene
    local scene = sdk.call_native_func(sdk.get_native_singleton("via.SceneManager"), sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
    local comps = scene:call("findComponents(System.Type)", sdk.typeof("app.GmAIInteract_02"))
    local spots = {}
    local cpos = ch and ch:call("get_GameObject"):call("get_Transform"):call("get_Position")
    local n = 0
    pcall(function() n = comps:get_size() end)
    if n == 0 then pcall(function() n = comps:call("get_Length") end) end
    for i = 0, n - 1 do
        local c = comps[i]
        local go = c and c:call("get_GameObject")
        local io = c and c:get_field("InteractiveObject") -- GimmickBase.InteractiveObject (+0x288), not a component
        local pno = 0
        pcall(function() local l = c:get_field("InteractNoList"); if l and l:call("get_Count") > 0 then pno = l:call("get_Item", 0) end end)
        local busy = false
        pcall(function() busy = c:call("IsInteract()") end)
        local pos = go and go:call("get_Transform"):call("get_Position")
        local d = (cpos and pos) and (pos - cpos):length() or -1
        spots[#spots + 1] = { go = go, io = io, d = d, name = go and go:call("get_Name"), pno = pno, busy = busy }
    end
    table.sort(spots, function(a, b) return a.d < b.d end)
    local names = {}
    for i = 1, math.min(6, #spots) do names[#names + 1] = string.format("%s %.1fm pt%s%s%s", tostring(spots[i].name), spots[i].d, tostring(spots[i].pno), spots[i].io and "" or " (no InteractiveObject)", spots[i].busy and " (in use)" or "") end
    if how == "find" then
        R.lean_spots = table.concat(names, ", ")
        log_msg("lean lab: " .. #spots .. " AI interact spots near pawn " .. tostring(idx) .. ": " .. R.lean_spots)
        return "ok"
    end
    if how == "force" and ch and im then
        for _, sp in ipairs(spots) do
            if sp.io and not sp.busy and sp.d >= 0 and sp.d < 25 then
                local pt = sdk.create_instance("app.InteractManager.InteractPoint"):add_ref()
                pt:set_field("Object", sp.io)
                pt:set_field("PointNo", sp.pno or 0)
                im:call("addActiveInteract(app.Character, app.InteractManager.InteractPoint)", ch, pt)
                im:call("executeInteract(app.Character)", ch)
                log_msg(string.format("lean lab force: pawn %d -> %s (%.1f m)", idx, tostring(sp.name), sp.d))
                return "ok"
            end
        end
        return "no spot within 25 m"
    end
    return "unknown how"
end
local function start_possession(target_pawn_idx)
    write_trace("start_possession begin", tostring(target_pawn_idx))
    if R.ferry_on and R.ferry_on() then -- 0.9.178-dev3: no take-over while a Ferrystone teleports the party
        log_msg("Cannot possess during a Ferrystone teleport")
        R.note = { text = "Not during a Ferrystone", t_end = os.clock() + 2.0 }
        return false
    end
    ensure_enums()
    R.kbind_next = 0 -- v0.9.125: read the game's key table again (see R.kbind_read)
    local party = get_party()
    if #party == 0 then
        log_msg("Cannot possess: No party pawns found.")
        return false
    end

    -- Find requested pawn entry (or fallback to first available pawn)
    local entry = nil
    for _, e in ipairs(party) do
        if e.idx == target_pawn_idx then
            entry = e
            break
        end
    end
    if not entry then entry = party[1] end
    if R.s2 and R.s2.active and entry.idx == R.s2.idx then -- v0.9.171: player 2 plays that pawn
        log_msg("Cannot possess " .. tostring(entry.name) .. ": player 2 plays it")
        R.note = { text = tostring(entry.name) .. " is player 2's", t_end = os.clock() + 2.0 }
        return false
    end
    if R.np then -- 0.9.172: players 3+
        for n, sl in pairs(R.np.slots) do
            if sl.active and sl.idx == entry.idx then
                log_msg("Cannot possess " .. tostring(entry.name) .. ": player " .. n .. " plays it")
                R.note = { text = tostring(entry.name) .. " is player " .. n .. "'s", t_end = os.clock() + 2.0 }
                return false
            end
        end
    end

    if call(entry.chara, "get_IsDead") or call(entry.chara, "get_IsDown") then
        log_msg("Cannot possess " .. entry.name .. ": Pawn is currently downed/dead.")
        return false
    end
    if cfg.possess_unlean and R.busy_interact(entry.chara) then
        R.abort_interact(entry.chara)
        if not R.possess_wait then
            R.possess_wait = { idx = entry.idx, chara = entry.chara, name = entry.name, t0 = os.clock(), t_end = os.clock() + 3.0 }
            log_msg(tostring(entry.name) .. " is in an object interaction (leaning, sitting...): asked it to stop before taking control")
            R.note = { text = tostring(entry.name) .. " stands up...", t_end = os.clock() + 1.5 }
        end
        return false
    end

    -- If already possessing a pawn, cleanly release first
    if state.active then
        release_possession("switching pawn")
    end

    local cm = sdk.get_managed_singleton("app.CharacterManager")
    if not cm then return false end
    local arisen = call(cm, "get_ManualPlayer")
    if not arisen then return false end
    local arisen_human = call(arisen, "get_Human")
    local arisen_go = call(arisen, "get_GameObject")
    local arisen_pip = call(arisen, "get_InputProcessor")
    local arisen_input = call(arisen, "get_Input")
    local arisen_player_comp = call(cm, "get_ManualPlayerPlayer")
    local arisen_lockon_ctrl = arisen_player_comp and (call(arisen_player_comp, "get_LockOnCtrl") or field(arisen_player_comp, "<LockOnCtrl>k__BackingField"))

    local pawn_chara = entry.chara
    local pawn_human = entry.human
    local pawn_go = call(pawn_chara, "get_GameObject")
    local pawn_input = call(pawn_chara, "get_Input")

    if not (arisen_human and arisen_go and arisen_pip and pawn_human and pawn_go) then
        log_msg("Cannot possess: Missing required Character/Human/InputProcessor components.")
        return false
    end

    -- Snapshot original references
    state.arisen_chara = arisen
    state.arisen_human = arisen_human
    state.arisen_go = arisen_go
    state.arisen_input = arisen_input
    state.arisen_pip = arisen_pip
    state.arisen_track = field(arisen_human, "Track")
    state.arisen_player_comp = arisen_player_comp
    state.arisen_lockon_ctrl = arisen_lockon_ctrl
    state.arisen_skill_ctx = get_skill_ctx(arisen_human)
    state.arisen_job_ctx = call(arisen_human, "get_JobContext")
    state.arisen_chara_addr = addr_of(arisen)
    state.arisen_skill_ctx_addr = addr_of(state.arisen_skill_ctx)
    state.arisen_job_ctx_addr = addr_of(state.arisen_job_ctx)
    state.arisen_pip_addr = addr_of(arisen_pip)
    state.far_since_t = nil
    state.next_auto_warp_t = os.clock() + (cfg.arisen_warp_cooldown or 4.0)
    state.arisen_stay = false
    state.warp_check = nil
    state.next_skill_refresh_t = 0.0

    state.pawn_idx = entry.idx
    state.pawn_name = entry.name
    state.pawn_job = entry.job
    state.pawn_skills = entry.skills
    state.pawn_chara = pawn_chara
    state.pawn_human = pawn_human
    state.pawn_go = pawn_go
    state.pawn_input = pawn_input
    state.pawn_dash_opt0 = R.dash_opt_take(pawn_input)
    state.pawn_obj = entry.pawn
    state.pending_skill = nil
    state.pending_attack = nil
    state.combo_buffer = nil
    state.active_cast = nil
    state.suppress_loco_until = 0.0
    state.was_moving = false
    state.is_sprinting = false
    state.is_guarding = false
    state.is_aiming = false
    state.is_quickspelling = false
    state.arisen_was_following = false
    state.frames_since_start = 0
    state.arisen_pip_blocked_count = 0

    local hcac = call(pawn_human, "get_HumanCommonActionCtrl") or field(pawn_human, "<HumanCommonActionCtrl>k__BackingField")
    state.pawn_orig_is_player = hcac and field(hcac, "IsPlayer") or false
    state.pawn_orig_is_arisen = field(pawn_human, "IsArisen") or false

    -- Dash-to-requested-move-speed: v0.6 forced it on for the puppeteer (which also requests the speed every frame).
    -- 0.9.172: reported 2026-11-20, a played pawn's sprint drops back to run speed after a moment while the Arisen's
    -- doesn't; with this on, the dash follows RequestedMoveSpeedOfNormalLocomotion, which nothing sets under native
    -- controls. Left as the game has it unless cfg.native_dash_to_req; restored at release.
    state.pawn_orig_dash_req = hcac and call(hcac, "get_IsEnableDashToRequestedMoveSpeedOfNormalLocomotion")
    if hcac and cfg.native_dash_to_req then
        call(hcac, "set_IsEnableDashToRequestedMoveSpeedOfNormalLocomotion(System.Boolean)", true)
    end

    -- Rebind LockOnCtrl.Chara to Pawn so spells & ranged attacks lock onto enemies from the Pawn's perspective
    -- (not in co-op: player 1 keeps his lock-on; the pawn's native processor gets its own)
    if arisen_lockon_ctrl and not coop.active then
        set_field(arisen_lockon_ctrl, "Chara", pawn_chara)
        call(arisen_lockon_ctrl, "clearLockOn")
    end

    -- 1. Suppress Pawn AI & Navigation (soft flags only)
    if cfg.sub_suppress_ai then
        write_trace("start_possession: set_pawn_ai_suppressed")
        set_pawn_ai_suppressed(pawn_chara, entry.pawn, true, true)
    end
    -- v0.9.38: the flags above only stop NEW thinking; whatever the pawn's AI was already doing (running to a
    -- spot, an order) kept playing and fought the player's input for a while. End the decision in progress and,
    -- when the game allows it, drop him to idle. Each step is the game's own call and is skipped on error.
    R.ping = nil -- v0.9.112: the selection arrow goes the moment a character is taken over
    if R.dev then R.tk = { t0 = os.clock(), next = 0, log = {} } end
    if cfg.possess_interrupt_ai then R.guide_t0 = nil; R.guide_stop(pawn_chara, entry.name); R.interrupt_ai(pawn_chara, entry.name, true) end

    -- 2. Apply selected Control Mode
    write_trace("start_possession: apply control_mode", tostring(cfg.control_mode))
    if cfg.control_mode == 1 or cfg.control_mode == 3 then
        apply_native_processor_binding(true)
    elseif cfg.sub_disable_arisen_pip then
        -- v0.8.5: not disabled any more (that cut your buttons off from the pawn); hooks 1a/1b block him instead
        call(arisen_pip, "set_IsEnable(System.Boolean)", true)
        -- Ensure Arisen stops walking if they were moving when F6 was pressed
        local ar_sel = call(arisen, "get_HumanActionSelector")
        if ar_sel and call(ar_sel, "isEnableRequestIdle") then
            call(ar_sel, "requestIdleImpl(System.Boolean)", false)
        end
    end

    -- 3. Attach Camera to Pawn
    if cfg.sub_camera_attach then
        write_trace("start_possession: attach_camera_to")
        R.cine_begin(pawn_chara) -- v0.9.169: look at them, then glide behind them
        attach_camera_to(pawn_go)
    end

    for k in pairs(hud_widgets) do hud_widgets[k] = nil end
    state.pawn_sel_addr = addr_of(call(pawn_chara, "get_HumanActionSelector"))
    state.active = true
    R.session_write(true, state.pawn_job, state.pawn_name)
    pcall(native_build)
    pcall(apply_native_hud_skills, true)
    pcall(apply_native_hud_gauges, true)
    state.next_hud_check_t = os.clock() + 0.5
    state.last_action_str = "Possessed " .. entry.name .. " (" .. entry.job_name .. ")"
    log_msg(string.format("NOW CONTROLLING: %s (%s) [Mode %d]", entry.name, entry.job_name, cfg.control_mode))
    R.note = { text = "Playing as " .. tostring(entry.name), t_end = os.clock() + 3.0 }
    if R.api_fire then -- v0.9.170 mod API
        pcall(R.api_fire, "possess", { player = coop.active and 2 or 1, name = entry.name, job = entry.job, chara = pawn_chara, from_name = R.api_switch_from })
        if R.api_switch_from then pcall(R.api_fire, "switch", { player = coop.active and 2 or 1, from_name = R.api_switch_from, to_name = entry.name }) end
        R.api_switch_from = nil
    end
    write_trace("start_possession complete")
    return true
end

-- shared with the modules loaded after this one (see shared.lua)
S.release_possession, S.start_possession = release_possession, start_possession
