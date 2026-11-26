-- Direct Pawn Control: Arisen follow / tether and warp helpers.
-- Part of DirectPawnControl.lua, which loads the files in this folder in order (this one is 11 of 26).
-- Never run on its own: REFramework only runs the files directly in reframework/autorun.
local S = require("DirectPawnControl/shared")
local cfg, R, log_msg, call, safe_request_locomotion = S.cfg, S.R, S.log_msg, S.call, S.safe_request_locomotion
local SPEED_RUN, SPEED_DASH, state, brain, coop = S.SPEED_RUN, S.SPEED_DASH, S.state, S.brain, S.coop
local brain_event = S.brain_event

-- ----------------------------------------------------------------------------
-- Arisen Follow / Tether & Warp Helpers
-- ----------------------------------------------------------------------------
local function local_warp_arisen_near(pawn_pos)
    local offset_pos = Vector3f.new(pawn_pos.x + 1.5, pawn_pos.y + 0.5, pawn_pos.z + 1.5)
    pcall(state.arisen_chara.call, state.arisen_chara, "warp(via.vec3, app.CharacterWarpOption)", offset_pos, nil)
end

local function warp_arisen_to_pawn()
    if not (state.active and state.arisen_chara and state.pawn_chara) then return end
    local pawn_xf = call(state.pawn_chara, "get_Transform")
    local pawn_pos = pawn_xf and call(pawn_xf, "get_Position")
    if not pawn_pos then return end
    -- safeWarp takes a via.Position = UNIVERSAL (double) position. Passing get_Position() (float vec3)
    -- is silently reinterpreted and sends the Arisen to x~7e12 -> crash (v0.6.0 CTD).
    local pawn_upos = call(pawn_xf, "get_UniversalPosition")

    local pm = sdk.get_managed_singleton("app.PawnManager")
    local ok = false
    if pm and pawn_upos then
        ok = pcall(pm.call, pm, "safeWarp(app.Character, via.Position)", state.arisen_chara, pawn_upos)
    end
    if ok then
        log_msg("Warped Arisen to " .. state.pawn_name .. " (safeWarp)")
    else
        local_warp_arisen_near(pawn_pos)
        log_msg("Warped Arisen near " .. state.pawn_name .. " (local warp)")
    end
    state.warp_check = { t = os.clock() + 0.3, pawn_pos = Vector3f.new(pawn_pos.x, pawn_pos.y, pawn_pos.z) }
end
R.warp_arisen = warp_arisen_to_pawn -- 0.9.177: for the party warp (defined earlier in the file)

-- Runs 0.3 s after a warp: if the Arisen landed somewhere absurd, put it next to the pawn instead.
local function verify_last_warp()
    local wc = state.warp_check
    if not wc or os.clock() < wc.t then return end
    state.warp_check = nil
    local axf = call(state.arisen_chara, "get_Transform")
    local apos = axf and call(axf, "get_Position")
    local bad = (not apos)
    if apos then
        local dx, dy, dz = apos.x - wc.pawn_pos.x, apos.y - wc.pawn_pos.y, apos.z - wc.pawn_pos.z
        local d = math.sqrt(dx * dx + dy * dy + dz * dz)
        bad = (d ~= d) or d > 60.0 -- NaN or nowhere near the pawn
        if bad then log_msg(string.format("ERROR: warp check failed (Arisen %.0fm from target) - correcting", d)) end
    end
    if bad then local_warp_arisen_near(wc.pawn_pos) end
end

-- Wait / Come pawn-command inputs control the Arisen while possessing (names resolved once from the enum)
local CMD_FLAG_CACHE = nil
local function cmd_flags()
    if CMD_FLAG_CACHE then return CMD_FLAG_CACHE end
    if not next(S.ACTION_FLAGS) then return nil end
    local c = {}
    for name, flag in pairs(S.ACTION_FLAGS) do
        local n = string.lower(name)
        if n == "wait" or n == "pawnwait" or n == "order_wait" then c.wait = flag end
        if n == "come" or n == "pawncome" or n == "order_come" then c.come = flag end
        if n == "help" or n == "pawnhelp" or n == "order_help" then c.help = flag end
    end
    log_msg(string.format("Pawn command flags: wait=%s come=%s help=%s", tostring(c.wait), tostring(c.come), tostring(c.help)))
    CMD_FLAG_CACHE = c
    return c
end

local function update_arisen_stay()
    local c = cmd_flags()
    local trg = state.last_trg_flags or 0
    if not c then return end
    -- v0.9.98: while a D-pad direction the mod owns is held, keep the order's press back; a tap gets it on release
    if cfg.pad_hold_select and not coop.active then
        local mask = (c.wait or 0) | (c.come or 0) | (c.help or 0)
        if R.dpad_dir(S.pad_buttons or 0) or (R.dh and R.dh.fired) then
            R.dh_cmd = (R.dh_cmd or 0) | (trg & mask)
            trg = trg & ~mask
        end
        if R.cmd_replay then trg, R.cmd_replay = trg | R.cmd_replay, nil end
    end
    if trg == 0 then return end
    -- v0.9.64: the Help order asks a caster Arisen to come and heal the possessed pawn now
    if c.help and (trg & c.help) ~= 0 and brain.style == "caster" and cfg.arisen_brain_heal then
        brain.help_until = os.clock() + 20.0
        brain.hurt_next = 0
        brain_event("Help order -> heal the possessed pawn")
    end
    if c.wait and (trg & c.wait) ~= 0 and not state.arisen_stay then
        state.arisen_stay = true
        log_msg("Arisen: WAIT (stays here; Come to resume following)")
        local sel = call(state.arisen_chara, "get_HumanActionSelector")
        if state.arisen_human then
            call(state.arisen_human, "set_IsDash(System.Boolean)", false)
            call(state.arisen_human, "set_IsPrevDash(System.Boolean)", false)
        end
        if sel and call(sel, "isEnableRequestIdle") then call(sel, "requestIdleImpl(System.Boolean)", false) end
        state.arisen_was_following = false
    elseif c.come and (trg & c.come) ~= 0 and state.arisen_stay then
        state.arisen_stay = false
        log_msg("Arisen: COME (following again)")
    end
end

local function update_arisen_tether()
    if not (state.active and state.arisen_chara and state.pawn_chara) then return end
    if coop.active then return end -- player 1 drives the Arisen
    verify_last_warp()
    update_arisen_stay()
    local axf = call(state.arisen_chara, "get_Transform")
    local pxf = call(state.pawn_chara, "get_Transform")
    local apos = axf and call(axf, "get_Position")
    local ppos = pxf and call(pxf, "get_Position")
    if not (apos and ppos) then return end

    local ok_dist, dist_xz, dy, dx, dz = pcall(function()
        local _dx = ppos.x - apos.x
        local _dy = ppos.y - apos.y
        local _dz = ppos.z - apos.z
        return math.sqrt(_dx * _dx + _dz * _dz), _dy, _dx, _dz
    end)
    if not ok_dist then return end

    -- Prevent party distance-leash from snapping the controlled pawn back to Arisen.
    -- v0.6.0: the condition must persist for arisen_warp_delay (so jumps, falls and monster climbs
    -- don't trigger it) and automatic warps are rate-limited. Previously this re-warped every frame
    -- until the warp settled - the prime suspect for the "far from Arisen" CTD.
    local now = os.clock()
    -- v0.9.28: while the Arisen was told to Wait he stays put; the auto-warp only fires past arisen_warp_dist_wait
    -- (beta-check-1: 60 m apart with the warp off, the game never pulled the possessed pawn back).
    local warp_d = cfg.arisen_warp_dist
    if state.arisen_stay and warp_d > 0 then warp_d = math.max(warp_d, cfg.arisen_warp_dist_wait or 120.0) end
    local too_far = warp_d > 0 and (dist_xz > warp_d or (math.abs(dy) > 25.0 and not state.arisen_stay))
    if too_far then
        state.far_since_t = state.far_since_t or now
        if (now - state.far_since_t) >= (cfg.arisen_warp_delay or 1.0) and now >= state.next_auto_warp_t then
            state.next_auto_warp_t = now + (cfg.arisen_warp_cooldown or 4.0)
            state.far_since_t = nil
            log_msg(string.format("Auto-warping Arisen (dist %.1fm, dy %.1fm)", dist_xz, dy))
            warp_arisen_to_pawn()
        end
        return
    end
    state.far_since_t = nil

    if brain.on then return end -- v0.8: the brain follows with the stick (pawn-style)
    if not cfg.arisen_auto_follow or state.arisen_stay then return end
    local arisen_sel = call(state.arisen_chara, "get_HumanActionSelector")
    if not arisen_sel then return end

    if dist_xz > cfg.arisen_follow_dist then
        local angle_rad = math.atan(dx, dz)
        local angle_deg = math.deg(angle_rad)
        call(state.arisen_chara, "set_TargetMoveAngleDeg(System.Single)", angle_deg)
        call(state.arisen_chara, "set_TargetFrontAngleDeg(System.Single)", angle_deg)
        local is_dash = (dist_xz > 14.0)
        local speed_type = is_dash and SPEED_DASH or SPEED_RUN
        -- 2nd arg is is_strafe (NOT is_dash): true would cap the Arisen at strafe speed (~3.5 m/s)
        if is_dash and state.arisen_human then
            call(state.arisen_human, "set_IsDash(System.Boolean)", true)
            call(state.arisen_human, "set_IsPrevDash(System.Boolean)", true)
            call(state.arisen_human, "notifyKeepDash")
        end
        safe_request_locomotion(arisen_sel, speed_type, false)
        state.arisen_was_following = true
    elseif state.arisen_was_following and dist_xz < (cfg.arisen_follow_dist - 1.5) then
        state.arisen_was_following = false
        if state.arisen_human then
            call(state.arisen_human, "set_IsDash(System.Boolean)", false)
            call(state.arisen_human, "set_IsPrevDash(System.Boolean)", false)
        end
        if call(arisen_sel, "isEnableRequestIdle") then
            call(arisen_sel, "requestIdleImpl(System.Boolean)", false)
        end
    end
end

-- shared with the modules loaded after this one (see shared.lua)
S.warp_arisen_to_pawn, S.update_arisen_tether = warp_arisen_to_pawn, update_arisen_tether
