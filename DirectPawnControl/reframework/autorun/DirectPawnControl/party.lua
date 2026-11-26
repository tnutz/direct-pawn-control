-- Direct Pawn Control: live party discovery, possession state and saved originals.
-- Part of DirectPawnControl.lua, which loads the files in this folder in order (this one is 03 of 26).
-- Never run on its own: REFramework only runs the files directly in reframework/autorun.
local S = require("DirectPawnControl/shared")
local log_msg, same_obj, call, field, JOB_NAMES = S.log_msg, S.same_obj, S.call, S.field, S.JOB_NAMES
local localize_skill = S.localize_skill

-- ----------------------------------------------------------------------------
-- Live Party Discovery (from PawnCommander patterns)
-- ----------------------------------------------------------------------------
local function get_pawn_component(chara, idx)
    local pm = sdk.get_managed_singleton("app.PawnManager")
    if not pm then return nil end
    if idx == 0 then
        local mp = field(pm, "_MainPawn") or call(pm, "get_MainPawn")
        if mp then return mp end
    end
    local party_list = call(pm, "get_PartyPawnList")
    if party_list then
        local count = call(party_list, "get_Count") or 0
        for i = 0, count - 1 do
            local p = call(party_list, "get_Item", i)
            if p then
                local c = call(p, "get_CachedCharacter")
                if same_obj(c, chara) then return p end
            end
        end
    end
    return nil
end

local function get_job(human, chara)
    S.in_internal_query = true
    local jc = human and call(human, "get_JobContext")
    local j = jc and (call(jc, "get_Job") or field(jc, "CurrentJob"))
    if type(j) ~= "number" or j <= 0 then
        j = chara and (call(chara, "getWeaponJob") or field(chara, "WeaponJob"))
    end
    S.in_internal_query = false
    if type(j) == "number" and j > 0 then return j end
    return 1
end

-- Docs and working code disagree on the getter name (get_SkillContext vs get_HumanCustomSkillContext);
-- probe both once and cache whichever returns a context that answers getSkillID.
local SKILL_CTX_GETTERS = { "get_SkillContext", "get_HumanCustomSkillContext" }
local skill_ctx_getter = nil
local function get_skill_ctx(human)
    if not human then return nil end
    if skill_ctx_getter then return call(human, skill_ctx_getter) end
    for _, g in ipairs(SKILL_CTX_GETTERS) do
        local sc = call(human, g)
        if sc then
            skill_ctx_getter = g
            log_msg("Skill context getter resolved: " .. g)
            return sc
        end
    end
    return nil
end

local function get_skills(human, job)
    local s = { 0, 0, 0, 0, 0, 0 }
    if not human or not job or job == 0 then return s end
    S.in_internal_query = true
    local sc = get_skill_ctx(human)
    if sc then
        for slot = 0, 5 do -- slots 5/6 = the extra Skill5 / Skill6 palette
            local id = call(sc, "getSkillID", job, slot)
            if type(id) == "number" then
                s[slot + 1] = id
                localize_skill(sc, job, id)
            end
        end
    end
    S.in_internal_query = false
    return s
end

local function get_party()
    local out = {}
    local pm = sdk.get_managed_singleton("app.PawnManager")
    if not pm then return out end
    local list = call(pm, "get_PawnCharacterList")
    if not list then return out end
    local n = call(list, "get_Count") or 0
    for i = 0, n - 1 do
        local chara = call(list, "get_Item", i)
        if chara then
            local human = call(chara, "get_Human")
            local pdc = human and call(human, "get_PawnDataContext")
            local name = pdc and call(pdc, "get_Name")
            -- v0.9.110: a name the overlay font cannot draw (non-Latin) -> the pawn's moniker, which is what the
            -- game's own name plate shows for it (read live: a Name in non-Latin characters, a Nickname in Latin ones)
            if name and tostring(name):find("[\128-\255]") then
                local nick = pdc and call(pdc, "get_Nickname")
                if nick and nick ~= "" then name = nick end
            end
            local job = get_job(human, chara)
            table.insert(out, {
                idx = i,
                chara = chara,
                human = human,
                pawn = get_pawn_component(chara, i),
                name = (name and name ~= "") and name or (i == 0 and "Main Pawn" or ("Hired Pawn " .. i)),
                job = job,
                job_name = JOB_NAMES[job] or ("Job#" .. tostring(job)),
                skills = get_skills(human, job),
            })
        end
    end
    return out
end

-- ----------------------------------------------------------------------------
-- Possession State & Saved Original References
-- ----------------------------------------------------------------------------
local state = {
    active = false,
    frames_since_start = 0,
    pawn_idx = 0,
    pawn_name = "",
    pawn_job = 1,
    pawn_skills = { 0, 0, 0, 0, 0, 0 },
    -- Saved Arisen objects for 100% clean restoration
    arisen_chara = nil,
    arisen_human = nil,
    arisen_go = nil,
    arisen_input = nil,
    arisen_pip = nil,
    arisen_track = nil,
    arisen_player_comp = nil,
    arisen_lockon_ctrl = nil,
    arisen_skill_ctx = nil,
    arisen_job_ctx = nil,
    orig_keyguide = nil,            -- Cached native KeyGuide widget pointers while possessing
    hud_shift_held = false,         -- Skill-shift modifier held this frame (drives the native skill guide)
    next_hud_check_t = 0.0,
    -- Saved Pawn objects
    pawn_chara = nil,
    pawn_human = nil,
    pawn_go = nil,
    pawn_input = nil,
    pawn_obj = nil,
    pawn_orig_is_player = false,
    pawn_orig_is_arisen = false,
    -- Track which pawn addresses already had addPlayerSelectors() called
    added_player_selectors = {},
    -- PawnCommander retry windows (ensures skills & attacks fire cleanly even if weapon was sheathed)
    pending_skill = nil,            -- { id, slot, speed_type, until_t, tries }
    pending_attack = nil,           -- { heavy, speed_type, until_t, tries }
    combo_buffer = nil,             -- { speed_type, until_t, next_t, tries } light-attack combo continuation
    input_log = {},                 -- cfg.debug_input ring buffer (see dbg_event), flushed to data/DPC_input_log.json
    input_log_dirty = false,
    next_input_log_flush = 0.0,
    atk_trace_until = 0.0,
    atk_trace_last = "",
    active_cast = nil,              -- { id, slot, start_t, released, is_ready }
    suppress_loco_until = 0.0,      -- Brief window after attack/skill/jump so locomotion doesn't cancel startup
    -- Movement, Sprint & Guard state
    was_moving = false,
    is_sprinting = false,
    is_guarding = false,
    is_aiming = false,
    is_quickspelling = false,
    arisen_was_following = false,
    -- Diagnostics
    live_speed_mps = 0.0,
    last_speed_time = 0.0,
    last_pawn_pos = nil,
    arisen_pip_blocked_count = 0,
    last_trg_flags = 0,
    last_on_flags = 0,
    last_action_str = "Idle",
    last_move_deg = 0.0,
    last_stick_mag = 0.0,
    last_cam_deg = 0.0,
    -- Raw native addresses for allocation-free hot-hook comparisons
    arisen_chara_addr = 0,
    arisen_skill_ctx_addr = 0,
    arisen_job_ctx_addr = 0,
    arisen_pip_addr = 0,
    pawn_sel_addr = 0,              -- possessed pawn's HumanActionSelector (sit-request filter)
    -- Throttles & warp bookkeeping
    next_skill_refresh_t = 0.0,
    far_since_t = nil,
    next_auto_warp_t = 0.0,
    last_tick_err_t = 0.0,
    arisen_stay = false,      -- Wait command: Arisen holds position (auto-warp still applies past arisen_warp_dist)
    warp_check = nil,         -- { t = os.clock() deadline, pawn_pos = Vector3f } pending post-warp verification
}

-- Snapshot read by re.on_frame / ImGui. Only the game thread (UpdateBehavior) writes it,
-- so the render thread never calls into the SDK or toggles in_internal_query.
local ui_cache = {
    party = {},
    next_party_t = 0.0,
    hp = 0, max_hp = 1,
    active_sk = 0,
    weapon_drawn = false,
    cam_id = "nil",
}

local function addr_of(obj)
    if not obj then return 0 end
    local ok, a = pcall(obj.get_address, obj)
    if ok and type(a) == "number" then return a end
    return 0
end

-- Hook args are raw void* userdata; to_int64 is allocation-free (unlike to_managed_object)
local function arg_addr(arg)
    return arg and sdk.to_int64(arg) or 0
end

-- shared with the modules loaded after this one (see shared.lua)
S.get_job, S.get_skill_ctx, S.get_skills, S.get_party, S.state = get_job, get_skill_ctx, get_skills, get_party, state
S.ui_cache, S.addr_of, S.arg_addr = ui_cache, addr_of, arg_addr
