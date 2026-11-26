-- Direct Pawn Control: soft AI suppression, camera attachment, native skill palette and HUD gauges.
-- Part of DirectPawnControl.lua, which loads the files in this folder in order (this one is 06 of 26).
-- Never run on its own: REFramework only runs the files directly in reframework/autorun.
local S = require("DirectPawnControl/shared")
local dev_error, cfg, R, write_trace, log_msg = S.dev_error, S.cfg, S.R, S.write_trace, S.log_msg
local same_obj, call, field, set_field, get_job = S.same_obj, S.call, S.field, S.set_field, S.get_job
local get_skill_ctx, state, addr_of = S.get_skill_ctx, S.state, S.addr_of

-- ----------------------------------------------------------------------------
-- Soft-Only Pawn AI Suppression (No via.Behavior:set_Enabled(false)!)
-- ----------------------------------------------------------------------------
local function set_pawn_ai_suppressed(chara, pawn_obj, suppress, first_time)
    if not chara then return end

    -- 1. AIDecisionMaker -> DecisionModule.IsSkipThink (Soft boolean flag only)
    local aidm = call(chara, "get_AIDecisionMaker") or field(chara, "<AIDecisionMaker>k__BackingField")
    if aidm then
        local dm = call(aidm, "get_DecisionModule") or field(aidm, "<DecisionModule>k__BackingField")
        if dm then
            call(dm, "set_IsSkipThink(System.Boolean)", suppress)
        end
    end

    -- 2. PawnNavigationController -> IsRequestDisableNavi (Soft boolean flag only)
    local nav = call(chara, "get_NavigationController") or field(chara, "<NavigationController>k__BackingField")
    if nav then
        call(nav, "set_IsRequestDisableNavi(System.Boolean)", suppress)
    end

    -- 3. Clear active AI orders once on initial possession
    if pawn_obj and suppress and first_time then
        set_field(pawn_obj, "_NextOrder", 0)
    end
end

-- ----------------------------------------------------------------------------
-- Camera Attachment (MainCameraController)
-- ----------------------------------------------------------------------------
local function attach_camera_to(go)
    if not go then return false end
    if R.api_claimed and R.api_claimed("camera.follow") then return true end -- v0.9.170: another mod places the views
    local cam_mgr = sdk.get_managed_singleton("app.CameraManager")
    if not cam_mgr then return false end
    local mcc = call(cam_mgr, "getMainCameraController", 0)
    if not mcc then return false end

    local cur_target = call(mcc, "get_TargetObject")
    if not same_obj(cur_target, go) then
        write_trace("attach_camera_to: registerTargetObject + onWarpTarget")
        call(mcc, "registerTargetObject(via.GameObject)", go)
        call(mcc, "onWarpTarget()")
    end
    return true
end

-- ----------------------------------------------------------------------------
-- Sync Native HUD Skill Palette (Mirrors Pawn's Skills onto Native KeyGuide)
-- NEVER calls setSkill on Arisen's HumanSkillContext to prevent save corruption!
-- ----------------------------------------------------------------------------
-- v0.9.134 "Dash" on the guide for a played pawn. Read in a fresh session (probe dash9): with the guide on the
-- Arisen ui010201.BtnDash = 5 (the Circle slot) and IsBtnAssigned = true; with the guide on a played pawn
-- BtnDash = -1 and IsBtnAssigned = false, while setBtnDashText gets the same arguments for both. So the game's
-- own button assignment does not complete for a pawn and the label has no slot to go to. The Arisen's two dash
-- slots are remembered at take-over and written back whenever they read -1 while the guide is on the pawn
-- (switch: hud_dash_slot).
R.dash_slots_keep = function(kg)
    local a, b = kg:get_field("BtnDash"), kg:get_field("BtnDash2")
    if type(a) == "number" and a >= 0 then R.dash_slots = { a, type(b) == "number" and b or -1 } end
end
R.dash_slots_put = function(kg)
    if cfg.hud_dash_slot ~= true or not R.dash_slots then return end
    local ok, err = pcall(function()
        if kg:get_field("BtnDash") == -1 then
            kg:set_field("BtnDash", R.dash_slots[1])
            if R.dash_slots[2] >= 0 and kg:get_field("BtnDash2") == -1 then kg:set_field("BtnDash2", R.dash_slots[2]) end
            R.dash_puts = (R.dash_puts or 0) + 1
        end
    end)
    if not ok then dev_error("dash slots", err) end
end

local function apply_native_hud_skills(enable)
    local gm = sdk.get_managed_singleton("app.GuiManager")
    if not gm then return end
    local kg = gm:get_field("KeyGuide")
    if not kg then return end

    -- v0.9.133: what "give the guide back" means is always the Arisen. Until now the guide's fields were saved as
    -- found at take-over; after Reset Scripts during a possession (or any take-over while the guide still pointed
    -- at a pawn) that saved the pawn, and releasing "restored" the guide to the pawn: bridge probe hud4 with nobody
    -- possessed read PlChara = the main pawn, and it was reported that the Arisen showed no skill list with L1
    -- pressed". Saved now only when the guide really is on the Arisen; otherwise built from the Arisen himself.
    local arisen_job = nil
    if enable and not state.orig_keyguide and state.arisen_chara and state.arisen_human then
        arisen_job = get_job(state.arisen_human, state.arisen_chara)
    end

    S.in_internal_query = true

    if enable and cfg.native_hud_skill_hook and state.pawn_chara and state.pawn_human then
        if not state.orig_keyguide and state.arisen_chara and state.arisen_human then
            local cur = kg:get_field("PlChara")
            if cur and addr_of(cur) == addr_of(state.arisen_chara) then
                R.dash_slots_keep(kg)
                state.orig_keyguide = {
                    PlChara = cur,
                    PlHuman = kg:get_field("PlHuman") or state.arisen_human,
                    SkillContext = kg:get_field("SkillContext") or state.arisen_skill_ctx,
                    Job = kg:get_field("Job"),
                    WeaponJob = kg:get_field("WeaponJob"),
                    PlInput = kg:get_field("PlInput") or state.arisen_input,
                }
            else
                state.orig_keyguide = {
                    PlChara = state.arisen_chara,
                    PlHuman = state.arisen_human,
                    SkillContext = state.arisen_skill_ctx or get_skill_ctx(state.arisen_human),
                    Job = arisen_job or kg:get_field("Job"),
                    WeaponJob = arisen_job or kg:get_field("WeaponJob"),
                    PlInput = state.arisen_input or call(state.arisen_chara, "get_Input"),
                }
                log_msg("Key guide was not on the Arisen at take-over; it will be handed back to the Arisen on release")
            end
        end
        local pawn_sc = get_skill_ctx(state.pawn_human)
        local pawn_job = state.pawn_job or 1
        local pawn_input = call(state.pawn_chara, "get_Input")

        kg:set_field("PlChara", state.pawn_chara)
        kg:set_field("PlHuman", state.pawn_human)
        if pawn_sc then kg:set_field("SkillContext", pawn_sc) end
        kg:set_field("Job", pawn_job)
        kg:set_field("WeaponJob", pawn_job)
        if pawn_input then kg:set_field("PlInput", pawn_input) end

        pcall(kg.call, kg, "setupCustomSkillMsgId")
        pcall(kg.call, kg, "setupCustomSkillButton", true)
        pcall(gm.call, gm, "setupKeyGuideCustomSkill")
        R.dash_slots_put(kg)
    elseif not enable and state.orig_keyguide then
        local orig = state.orig_keyguide
        kg:set_field("PlChara", orig.PlChara)
        kg:set_field("PlHuman", orig.PlHuman)
        kg:set_field("SkillContext", orig.SkillContext)
        kg:set_field("Job", orig.Job)
        kg:set_field("WeaponJob", orig.WeaponJob)
        kg:set_field("PlInput", orig.PlInput)

        pcall(kg.call, kg, "setupCustomSkillMsgId")
        pcall(kg.call, kg, "setupCustomSkillButton", true)
        pcall(gm.call, gm, "setupKeyGuideCustomSkill")
        state.orig_keyguide = nil
    end

    S.in_internal_query = false
end

-- ----------------------------------------------------------------------------
-- Native HUD gauges: HP / stamina (ui020901), player gauge (ui020401), minimap (ui020301)
-- Each widget caches PlChara/PlHuman; pointing them at the pawn and re-running their setup makes the
-- native HUD track the possessed pawn. Verified live 2026-11-08 via the agent bridge.
-- ----------------------------------------------------------------------------
local HUD_GAUGES = {
    { type = "app.ui020901", setup = { "setupHpGauge", "setupStGauge", "setupStatusIcon" } },
    { type = "app.ui020401", setup = { "setupAction" } },
    { type = "app.ui020301", force_field = "NeedForceUpdate" },
}
local hud_widgets = {} -- type name -> component (re-found when missing or destroyed)

local function find_component(type_name)
    local sm = sdk.get_native_singleton("via.SceneManager")
    if not sm then return nil end
    local scene = sdk.call_native_func(sm, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
    if not scene then return nil end
    local ok, arr = pcall(scene.call, scene, "findComponents(System.Type)", sdk.typeof(type_name))
    if not ok or not arr then return nil end
    local n = call(arr, "get_Count") or call(arr, "get_Length") or 0
    if n <= 0 then return nil end
    return arr[0]
end

local function get_hud_widget(type_name)
    local w = hud_widgets[type_name]
    if w and call(w, "get_GameObject") then return w end
    w = find_component(type_name)
    hud_widgets[type_name] = w
    return w
end

local function bind_hud_gauges(chara, human, force)
    if not chara or not human then return end
    local target = addr_of(chara)
    for _, g in ipairs(HUD_GAUGES) do
        local w = get_hud_widget(g.type)
        if w then
            local cur = field(w, "PlChara")
            if force or addr_of(cur) ~= target then
                set_field(w, "PlChara", chara)
                set_field(w, "PlHuman", human)
                if g.setup then
                    for _, m in ipairs(g.setup) do pcall(w.call, w, m) end
                end
                if g.force_field then set_field(w, g.force_field, true) end
            end
        end
    end
end

local function apply_native_hud_gauges(enable)
    if enable then
        if cfg.native_hud_gauges and state.pawn_chara then
            bind_hud_gauges(state.pawn_chara, state.pawn_human, true)
        end
    elseif state.arisen_chara then
        bind_hud_gauges(state.arisen_chara, state.arisen_human, true)
    end
end

-- Re-assert every 0.5 s: menus, area loads and the game's own setupPlChara calls rebind to the Arisen.
local function maintain_native_hud()
    local now = os.clock()
    if now < state.next_hud_check_t then return end
    state.next_hud_check_t = now + 0.5
    if cfg.native_hud_gauges then
        bind_hud_gauges(state.pawn_chara, state.pawn_human, false)
    end
    if cfg.native_hud_skill_hook and state.pawn_chara then
        local kg = get_hud_widget("app.ui010201")
        if kg and addr_of(field(kg, "PlChara")) ~= addr_of(state.pawn_chara) then
            pcall(apply_native_hud_skills, true)
            R.hud_repoints = (R.hud_repoints or 0) + 1
        elseif kg then
            R.dash_slots_put(kg)
        end
    end
end

-- shared with the modules loaded after this one (see shared.lua)
S.set_pawn_ai_suppressed, S.attach_camera_to = set_pawn_ai_suppressed, attach_camera_to
S.apply_native_hud_skills, S.hud_widgets = apply_native_hud_skills, hud_widgets
S.apply_native_hud_gauges, S.maintain_native_hud = apply_native_hud_gauges, maintain_native_hud
