-- Direct Pawn Control: game hooks: input, skills, HUD queries, teardown.
-- Part of DirectPawnControl.lua, which loads the files in this folder in order (this one is 05 of 26).
-- Never run on its own: REFramework only runs the files directly in reframework/autorun.
local S = require("DirectPawnControl/shared")
local dev_error, cfg, R, log_msg, call, get_skill_ctx = S.dev_error, S.cfg, S.R, S.log_msg, S.call, S.get_skill_ctx
local state, addr_of, arg_addr, brain, coop = S.state, S.addr_of, S.arg_addr, S.brain, S.coop
local brain_inject = S.brain_inject

-- ----------------------------------------------------------------------------
-- Hooks:
--   1. Block Arisen PlayerInputProcessor & SequenceBuffer While Possessing
--   2. Redirect Arisen HumanSkillContext:getSkillID & JobContext:get_Job to Pawn
--      so native DD2 HUD skill labels reflect the possessed pawn's skills!
-- ----------------------------------------------------------------------------
local hooks_installed = false
local hook_last_slot = nil

local function install_hooks()
    if hooks_installed then return end

    -- 1a. Block Arisen PlayerInputProcessor:update
    local pip_td = sdk.find_type_definition("app.PlayerInputProcessor")
    if pip_td then
        local upd_m = pip_td:get_method("update")
        if upd_m then
            sdk.hook(
                upd_m,
                function(args)
                    -- v0.9 co-op: player 1's Arisen runs normally; strip player 2's controller out of his input
                    if coop.active and state.arisen_pip_addr ~= 0 and arg_addr(args[2]) == state.arisen_pip_addr then
                        if not brain.self_driving then brain.game_pip_t = os.clock() end
                        if coop.filter then
                            local okf, ferr = pcall(coop.filter)
                            if not okf then dev_error("coop.filter", ferr) end
                        end
                        return
                    end
                    -- v0.8: the Arisen combat brain lets his processor run on synthetic input instead
                    if brain.on and brain.pip_addr ~= 0 and arg_addr(args[2]) == brain.pip_addr then
                        if not brain.self_driving then brain.game_pip_t = os.clock() end
                        brain_inject()
                        return
                    end
                    if state.active and cfg.control_mode == 2 and cfg.sub_disable_arisen_pip then
                        if state.arisen_pip_addr ~= 0 and arg_addr(args[2]) == state.arisen_pip_addr then
                            state.arisen_pip_blocked_count = state.arisen_pip_blocked_count + 1
                            return sdk.PreHookResult.SKIP_ORIGINAL
                        end
                    end
                end,
                function(retval) return retval end
            )
        end
    end

    -- 1a-coop. app.UserInput.processButton(UInt64, via.hid.GamePadButton) is the pad path of the game's input
    -- update (processKeyboardMouse is the keyboard/mouse path). During co-op, give the Arisen's input an empty
    -- pad so player 2's controller never drives him. Unverified live: auto-disabled if it kills player 1's keys.
    do
        local ui_td = sdk.find_type_definition("app.UserInput")
        local pb = ui_td and ui_td:get_method("processButton")
        if pb then
            sdk.hook(pb, function(args)
                if R.kb_wait and R.kb_wait() and coop.ar_input_addr ~= 0 and arg_addr(args[2]) == coop.ar_input_addr then
                    args[4] = sdk.to_ptr(0) -- dev44: waiting for player 2, player 1 on keyboard: no controller drives him
                    return
                end
                -- dev28 (release-177-1: "controller is controlling both players, jump jumps both"; flight recorder: the
                -- same flags on the Arisen's and player 1's pawn's input). Both-on-characters mode with player 1 on a pawn
                -- and player 2 on the Arisen ("pawns" + ar2): player 1's pawn reads the game's player input, which merges
                -- every controller. Zeroing below only ran with one controller (R.cp.kb); with the keyboard paired as
                -- player 1's slot (two-controller co-op) R.cp.kb is false and nothing was taken out.
                local cpp = R.cp_pawns and R.cp_pawns()
                -- the game's player input object (coop.ar_input_addr is only set when classic co-op starts)
                local ain = cpp and state.arisen_input and addr_of(state.arisen_input) or 0
                -- read live: player 1's pawn has its own CharacterInput; cover it too, in case the game fills it directly
                local pin = cpp and state.pawn_input and addr_of(state.pawn_input) or 0
                local a2 = cpp and arg_addr(args[2]) or 0
                local mine = cpp and ((ain ~= 0 and a2 == ain) or (pin ~= 0 and a2 == pin))
                if mine and cfg.coop_zero_pad_for_arisen
                   and not coop.zero_off and (R.cp.kb or (R.tp and R.tp.p1 == R.KB_ADDR)) then
                    args[4] = sdk.to_ptr(0) -- player 1 is on the keyboard: no controller drives player 1's character
                    coop.pb_zeroed = coop.pb_zeroed + 1
                    return
                end
                if ((coop.active and coop.ar_input_addr ~= 0 and arg_addr(args[2]) == coop.ar_input_addr)
                    or mine) and R.tp_on and R.tp_on() then
                    -- v0.9.170 (dev): two controllers. Player 1's pad drives the Arisen; only player 2's buttons
                    -- are taken out (see R.tp_arisen_buttons for the three ways tried).
                    local okb, v = pcall(R.tp_arisen_buttons, args[4])
                    if okb and v ~= nil then args[4] = sdk.to_ptr(v) end
                    return
                end
                if ((coop.active and not (R.robot_p2 and R.robot_p2()) and coop.ar_input_addr ~= 0 and arg_addr(args[2]) == coop.ar_input_addr)
                    or (mine and R.cp.kb))
                   and cfg.coop_zero_pad_for_arisen and not coop.zero_off then -- v0.9.171: both on pawns, one controller: the controller is player 2's
                    args[4] = sdk.to_ptr(0)
                    coop.pb_zeroed = coop.pb_zeroed + 1
                end
            end, function(retval) return retval end)
        end
    end

    -- 1a2. Pawns get periodic idle "LivSitOnTheGround" requests (~every 3 s while standing) that the Arisen
    -- never gets. Drop them for the possessed pawn. Address check first: requestAction runs for everyone.
    local sel_td = sdk.find_type_definition("app.HumanActionSelector")
    local req_m = sel_td and sel_td:get_method("requestAction(System.String, System.UInt32)")
    if req_m then
        sdk.hook(
            req_m,
            function(args)
                local a_sel = arg_addr(args[2])
                if not ((state.active and state.pawn_sel_addr ~= 0 and a_sel == state.pawn_sel_addr)
                    or (R.s2 and R.s2.active and a_sel == (R.s2.sel_addr or -1))
                    or (R.np_sel and R.np_sel(a_sel))) then return end -- v0.9.171: and player 2's second pawn; 0.9.172 players 3+
                local ok, name = pcall(function()
                    local so = sdk.to_managed_object(args[3])
                    return so and so:call("ToString")
                end)
                if ok and type(name) == "string" and name:find("^LivSit") then
                    return sdk.PreHookResult.SKIP_ORIGINAL
                end
            end,
            function(retval) return retval end
        )
    end

    -- 1b. Block Arisen Player:updateSequenceBuffer
    local pl_td = sdk.find_type_definition("app.Player")
    if pl_td then
        local seq_m = pl_td:get_method("updateSequenceBuffer")
        if seq_m then
            sdk.hook(
                seq_m,
                function(args)
                    if brain.on then return end -- v0.8: the brain's synthetic input drives the Arisen
                    if state.active and cfg.control_mode == 2 and cfg.sub_disable_arisen_pip then
                        return sdk.PreHookResult.SKIP_ORIGINAL
                    end
                end,
                function(retval) return retval end
            )
        end
    end

    -- 2a. Hook app.HumanSkillContext:getSkillID(job, slot) for native HUD Skill Labels
    local sc_td = sdk.find_type_definition("app.HumanSkillContext")
    if sc_td then
        local get_sk_m = sc_td:get_method("getSkillID")
        if get_sk_m then
            sdk.hook(
                get_sk_m,
                function(args)
                    local hs = thread.get_hook_storage()
                    hs.slot = nil
                    if state.active and cfg.native_hud_skill_hook and not S.in_internal_query and not (brain.on and not cfg.arisen_brain_keep_hud_redirect) and state.arisen_skill_ctx_addr ~= 0 then
                        if arg_addr(args[2]) == state.arisen_skill_ctx_addr then
                            local slot_int = sdk.to_int64(args[4]) & 0xFFFFFFFF
                            if slot_int >= 0 and slot_int <= 3 then
                                hs.slot = slot_int
                            end
                        end
                    end
                end,
                function(retval)
                    local hs = thread.get_hook_storage()
                    if hs.slot ~= nil and state.active and state.pawn_skills then
                        local p_skill = state.pawn_skills[hs.slot + 1] or 0
                        return sdk.to_ptr(p_skill)
                    end
                    return retval
                end
            )
        end
    end

    -- 2b. Hook app.JobContext:get_Job() so the native HUD displays the possessed pawn's vocation
    local jc_td = sdk.find_type_definition("app.JobContext")
    if jc_td then
        local get_job_m = jc_td:get_method("get_Job")
        if get_job_m then
            sdk.hook(
                get_job_m,
                function(args)
                    local hs = thread.get_hook_storage()
                    hs.is_arisen_jc = false
                    if state.active and cfg.native_hud_skill_hook and not S.in_internal_query and not (brain.on and not cfg.arisen_brain_keep_hud_redirect) and state.arisen_job_ctx_addr ~= 0 then
                        if arg_addr(args[2]) == state.arisen_job_ctx_addr then
                            hs.is_arisen_jc = true
                        end
                    end
                end,
                function(retval)
                    local hs = thread.get_hook_storage()
                    if hs.is_arisen_jc and state.active and state.pawn_job then
                        return sdk.to_ptr(state.pawn_job)
                    end
                    return retval
                end
            )
        end
    end

    -- 2c. Hook app.Character:getWeaponJob() so the HUD gets the possessed pawn's weapon vocation
    local chara_td = sdk.find_type_definition("app.Character")
    if chara_td then
        local gwj_m = chara_td:get_method("getWeaponJob")
        if gwj_m then
            sdk.hook(
                gwj_m,
                function(args)
                    local hs = thread.get_hook_storage()
                    hs.is_arisen_chara = false
                    if state.active and cfg.native_hud_skill_hook and not S.in_internal_query and not (brain.on and not cfg.arisen_brain_keep_hud_redirect) and state.arisen_chara_addr ~= 0 then
                        if arg_addr(args[2]) == state.arisen_chara_addr then
                            hs.is_arisen_chara = true
                        end
                    end
                end,
                function(retval)
                    local hs = thread.get_hook_storage()
                    if hs.is_arisen_chara and state.active and state.pawn_job then
                        return sdk.to_ptr(state.pawn_job)
                    end
                    return retval
                end
            )
        end
    end

    -- 2d. Hook app.ui010201:isDisableCustomSkill so possessed pawn skills are never grayed out in native HUD
    local ui_td = sdk.find_type_definition("app.ui010201")
    if ui_td then
        local dis_m = ui_td:get_method("isDisableCustomSkill")
        if dis_m then
            sdk.hook(
                dis_m,
                function(args) end,
                function(retval)
                    if state.active and cfg.native_hud_skill_hook then
                        if R.cling and cfg.hud_cling_grey ~= false then -- v0.9.119: on a monster the game decides
                            if R.cling_grey and (sdk.to_int64(retval) & 1) == 1 then R.cling_grey = R.cling_grey + 1 end
                            return retval
                        end
                        return sdk.to_ptr(0) -- false: never grayed out while possessing!
                    end
                    return retval
                end
            )
        end

        -- setupPlChara rebinds the guide to the Arisen; re-point it at the pawn afterwards.
        -- (Post-hooks only receive retval, so `this` is carried over in hook storage.)
        local setup_pl_m = ui_td:get_method("setupPlChara")
        if setup_pl_m then
            sdk.hook(
                setup_pl_m,
                function(args)
                    thread.get_hook_storage()["this"] = args[2]
                end,
                function(retval)
                    if state.active and cfg.native_hud_skill_hook and state.pawn_chara and state.pawn_human then
                        local this_ptr = thread.get_hook_storage()["this"]
                        local this_ui = this_ptr and sdk.to_managed_object(this_ptr)
                        if this_ui then
                            local pawn_sc = get_skill_ctx(state.pawn_human)
                            local pawn_job = state.pawn_job or 1
                            local pawn_input = call(state.pawn_chara, "get_Input")
                            this_ui:set_field("PlChara", state.pawn_chara)
                            this_ui:set_field("PlHuman", state.pawn_human)
                            if pawn_sc then this_ui:set_field("SkillContext", pawn_sc) end
                            this_ui:set_field("Job", pawn_job)
                            this_ui:set_field("WeaponJob", pawn_job)
                            if pawn_input then this_ui:set_field("PlInput", pawn_input) end
                        end
                    end
                    return retval
                end
            )
        end

        -- v0.9.129 the "Dash" label. Reported 2026-11-17: the played pawn's guide lacks the second Dash label on Circle that the Arisen's has; dashing itself works. The game blanks that
        -- label for a played pawn (ui010201.setBtnDashTextEmpty) although its own isDisableDash / isRestrictedDash
        -- say false; why is not known. So: remember what the game writes there while the Arisen is played
        -- (setBtnDashText), and during a normal possession skip the blanking while dashing is allowed and the
        -- pawn is not on a monster (R.dash_ok, worked out twice a second in maintain_native_hud).
        -- v0.9.130: 0.9.129 assumed the blanking went through setBtnDashTextEmpty. Counters after one minute:
        -- setBtnDashText 3120 calls, setBtnDashTextEmpty 0. So the game calls setBtnDashText every frame and its
        -- arguments decide what shows. The skip / write-once of 0.9.129 is removed; this only records, per played
        -- character, which argument combinations arrive (dev status aim.dash_label.seen), to learn the rule.
        local dash_set_m = ui_td:get_method("setBtnDashText(System.Guid, System.Boolean, System.Boolean)")
        if dash_set_m and R.dev then
            R.dash_seen = {}
            sdk.hook(dash_set_m, function(args)
                R.dash_n_text = (R.dash_n_text or 0) + 1
                local a, b = sdk.to_int64(args[4]) & 1, sdk.to_int64(args[5]) & 1
                local key = (coop.active and "coop" or (state.active and "pawn" or "arisen")) .. " " .. a .. b
                if not R.dash_seen[key] then
                    local g = "?"
                    pcall(function()
                        local vt = sdk.to_valuetype(args[3], "System.Guid")
                        g = string.format("%08x", (vt:get_field("mData1") or 0) & 0xFFFFFFFF)
                    end)
                    R.dash_seen[key] = { n = 0, guid = g }
                end
                local e = R.dash_seen[key]
                e.n, e.last = e.n + 1, os.clock()
            end, function(retval) return retval end)
        end

        -- The guide only lists the 4 custom skills while the skill-shift button is held. It reads that from
        -- PlInput (the pawn's AI-driven input), so feed it the player's modifier state instead.
        local shift_m = ui_td:get_method("isInputCustomSkillShift(System.Boolean)")
        if shift_m then
            sdk.hook(
                shift_m,
                function(args) end,
                function(retval)
                    if state.active and cfg.native_hud_skill_hook and state.hud_shift_held then
                        return sdk.to_ptr(1)
                    end
                    return retval
                end
            )
        end
    end

    -- v0.9.139 the game's cinematic action camera (camera control type 10, app.CinematicActionCameraController).
    -- Reported twice, playing an Archer pawn against a Cyclops: the camera was pulled away from the played pawn.
    -- The 0.9.137 camera watch at that moment: "Camera: Combat (2) -> CinematicAction (10), player camera false".
    -- Any action with such a track asks for it through the static requestPlay; the game places that camera itself,
    -- not by the camera's target object, so it left the played pawn. While a pawn is played (possession or co-op)
    -- the request is dropped (switch: possess_no_cinematic_cam).
    pcall(function()
        local ctd = sdk.find_type_definition("app.CinematicActionCameraController")
        local m = ctd and ctd:get_method("requestPlay(System.UInt32, System.Nullable`1<System.UInt32>)")
        if not m then log_msg("Cinematic camera hook: requestPlay not found"); return end
        sdk.hook(m, function(args)
            if state.active and cfg.possess_no_cinematic_cam then
                R.cine_blocked = (R.cine_blocked or 0) + 1
                return sdk.PreHookResult.SKIP_ORIGINAL
            end
        end, function(retval) return retval end)
    end)

    hooks_installed = true
    log_msg("Installed Arisen input suppression & SkillContext UI hooks")
end
pcall(install_hooks)
