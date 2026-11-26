-- Direct Pawn Control: Mode 2 / Mode 3 puppeteer (ActionSelector + locomotion) and the UI cache refresh.
-- Part of DirectPawnControl.lua, which loads the files in this folder in order (this one is 16 of 26).
-- Never run on its own: REFramework only runs the files directly in reframework/autorun.
local S = require("DirectPawnControl/shared")
local dev_error, cfg, R, write_trace, log_msg, call = S.dev_error, S.cfg, S.R, S.write_trace, S.log_msg, S.call
local field, set_field, safe_request_locomotion = S.field, S.set_field, S.safe_request_locomotion
local VOCATION_ACTION_NAMES, SPEED_IDLE, SPEED_WALK = S.VOCATION_ACTION_NAMES, S.SPEED_IDLE, S.SPEED_WALK
local SPEED_RUN, SPEED_DASH, skill_name, get_job = S.SPEED_RUN, S.SPEED_DASH, S.skill_name, S.get_job
local get_skills, get_party, state, ui_cache, brain = S.get_skills, S.get_party, S.state, S.ui_cache, S.brain
local coop, brain_pos, native, native_tick = S.coop, S.brain_pos, S.native, S.native_tick
local coop_pad_values, coop_ensure_map, key_pressed = S.coop_pad_values, S.coop_ensure_map, S.key_pressed
local is_ui_open, read_safe_move_stick = S.is_ui_open, S.read_safe_move_stick
local warp_arisen_to_pawn, compute_camera_move_angle_deg = S.warp_arisen_to_pawn, S.compute_camera_move_angle_deg
local update_pawn_lockon_target, pawn_do_draw = S.update_pawn_lockon_target, S.pawn_do_draw
local pawn_do_sheathe, dbg_event, trace_attack_frames = S.pawn_do_sheathe, S.dbg_event, S.trace_attack_frames
local in_locomotion, pawn_do_attack, pawn_do_skill_slot = S.in_locomotion, S.pawn_do_attack, S.pawn_do_skill_slot
local pawn_do_jump, pawn_set_fighter_guard = S.pawn_do_jump, S.pawn_set_fighter_guard

-- ----------------------------------------------------------------------------
-- Mode 2 & Mode 3: Direct ActionSelector & Locomotion Puppeteer
-- ----------------------------------------------------------------------------
local function update_puppeteer_controls(is_first_frame)
    local live_input = state.arisen_input
    local pawn_chara = state.pawn_chara
    local pawn_human = state.pawn_human
    if not (live_input and pawn_chara and pawn_human) then return end

    local sel = call(pawn_chara, "get_HumanActionSelector")
    if not sel then return end

    -- Keep Arisen's InputProcessor disabled every frame in Mode 2
    -- v0.8.5: keep it ENABLED. The game only writes your buttons into the Arisen's CharacterInput (which DPC
    -- mirrors onto the pawn) while his processor is enabled: with it disabled, 0 of 2,901 frames carried a click
    -- and the possessed pawn could not attack; re-enabling it each frame fixed attacks live (2026-11-10).
    -- He still can't act on your input: hooks 1a/1b skip his processor and sequence buffer unless the brain
    -- drives him with its own input.
    if cfg.control_mode == 2 and cfg.sub_disable_arisen_pip and state.arisen_pip then
        call(state.arisen_pip, "set_IsEnable(System.Boolean)", true)
    end

    -- Refresh pawn job & equipped skills cache (throttled: vocation/skills only change in menus)
    local now_r = os.clock()
    if now_r >= state.next_skill_refresh_t then
        state.next_skill_refresh_t = now_r + 0.5
        local j = get_job(pawn_human, pawn_chara)
        state.pawn_job = j
        state.pawn_skills = get_skills(pawn_human, j)
    end
    local job = state.pawn_job

    -- Read stick / WASD safely as pure Lua numbers
    local ax, ay, mag = read_safe_move_stick(live_input)
    state.last_stick_mag = mag

    -- Read UInt64 button bitmasks from live_input (populated by UserInputManager before UpdateBehavior)
    local on_flags = field(live_input, "ButtonOnFlags") or 0
    local trg_flags = field(live_input, "ButtonTriggerFlags") or 0
    local rel_flags = field(live_input, "ButtonReleaseFlags") or 0
    -- v0.8.6: while the brain runs, this object can hold the brain's buttons at this point in the frame
    -- (user report: brain on -> clicks stop reaching the pawn). Use the snapshot of your buttons the brain took
    -- just before it wrote its own, then open a new snapshot for this frame.
    if brain.on and brain.hw_snap_t and os.clock() - brain.hw_snap_t < 0.25 then
        on_flags = brain.hw_on or 0
        trg_flags = brain.hw_trg or 0
        rel_flags = brain.hw_rel or 0
    end
    brain.hw_saved, brain.hw_restored = false, false
    brain.pawn_native = (cfg.native_controls and native.pip and not native.failed) and true or false
    -- v0.8: the brain overwrites the Arisen's CharacterInput (this live_input) with its synthetic buttons after
    -- this point each frame, so the game's own edge detection compares your keys against the brain's. Rebuild the
    -- trigger/release edges from the hardware on-flags DPC saw last frame instead.
    if brain.on or brain.was_on_last then
        trg_flags = on_flags & ~brain.hw_prev_on
        rel_flags = brain.hw_prev_on & ~on_flags
    end
    brain.hw_prev_on = on_flags
    brain.was_on_last = brain.on
    -- v0.9 co-op: player 2's pawn reads the controller only (buttons through the game's pad assignment)
    -- v0.9.171: with both players on pawns and two controllers, player 1's pawn can read player 1's controller the
    -- same way (cfg.coop_any_p1_route = "pad") instead of the Arisen's game input ("game", default)
    if (coop.active or (R.cp_p1_pad and R.cp_p1_pad())) and coop.pad_input then
        local okc, c_on, c_ax, c_ay, c_mag = pcall(coop.pad_input)
        if okc then
            on_flags = c_on
            trg_flags = c_on & ~coop.prev_on
            rel_flags = coop.prev_on & ~c_on
            coop.prev_on = c_on
            ax, ay, mag = c_ax, c_ay, c_mag
            if R.view_turn then ax, ay = R.view_rot(state.pawn_chara, ax, ay) end -- 1.3
            state.last_stick_mag = mag
        else
            coop.err = "pad: " .. tostring(c_on)
            dev_error("coop.pad_input", c_on)
            on_flags, trg_flags, rel_flags, ax, ay, mag = 0, 0, 0, 0.0, 0.0, 0.0
        end
    end
    if R.rbf then -- 0.9.177-dev6 (developer): robot actions as game input flags for the played pawn
        local rb, now = R.rbf, os.clock()
        if rb.rel then rel_flags = rel_flags | rb.rel; on_flags = on_flags & ~rb.rel; rb.rel = nil end
        if now < rb.until_t and rb.f ~= 0 then
            on_flags = on_flags | rb.f
            if not rb.on then trg_flags = trg_flags | rb.f; rb.on = true end
        else
            if rb.on then rel_flags = rel_flags | rb.f; on_flags = on_flags & ~rb.f end
            R.rbf = nil
        end
    end
    state.last_on_flags = on_flags
    state.last_trg_flags = trg_flags

    -- In Mode 2, mirror raw input bitflags & float stick axes onto pawn_input using primitive methods only
    if cfg.control_mode == 2 and cfg.sub_mirror_input_flags and state.pawn_input then
        if is_first_frame then write_trace("frame1: mirror_input_flags") end
        set_field(state.pawn_input, "ButtonOnFlags", on_flags)
        set_field(state.pawn_input, "ButtonTriggerFlags", trg_flags)
        set_field(state.pawn_input, "ButtonReleaseFlags", rel_flags)
        call(state.pawn_input, "setAxisL(System.Single, System.Single)", ax, ay)
        call(state.pawn_input, "set_AxisMagnitudeL(System.Single)", mag)
    end

    -- Exact bitmask check: flag = (1 << ActionID)
    local function is_trg(act_name)
        local flag = S.ACTION_FLAGS[act_name]
        if not flag then return false end
        return (trg_flags & flag) ~= 0
    end

    local function is_on(act_name)
        local flag = S.ACTION_FLAGS[act_name]
        if not flag then return false end
        return (on_flags & flag) ~= 0
    end

    if cfg.debug_input and trg_flags ~= 0 then
        local names = {}
        for n, f in pairs(S.ACTION_FLAGS) do
            if (trg_flags & f) ~= 0 then names[#names + 1] = n end
        end
        table.sort(names)
        dbg_event("TRG", table.concat(names, "+"))
    end

    local ui_open = is_ui_open()
    -- Keyboard skill keys (Ctrl, 1-6) work even with the REFramework menu open (players keep it open to
    -- watch the DPC window); only mouse buttons stay gated so clicks on the menu don't attack.
    local shift_skill_mod = is_on("Shift1") or R.key_held("Shift1", 0x11) -- v0.9.124: the game's skill modifier key (default Ctrl)
    state.hud_shift_held = shift_skill_mod and true or false

    -- v0.7: number keys 1-6 (row or numpad) were DPC-puppeteer hotkeys. For the native processor, turn them
    -- into the same input the game produces for a skill press: SkillN + Shift1 + Shift2 (seen live).
    if cfg.native_controls and native.pip and not native.failed and state.pawn_input and not coop.active then
        local add_on, add_trg, add_rel = 0, 0, 0
        for n = 1, 6 do
            local f = S.ACTION_FLAGS["Skill" .. n]
            if f then
                -- v0.9.90: the numpad is for orders to someone else now; only the number row (when it is set to
                -- skills) still drives the possessed pawn
                local row = 0x30 + n
                if R.row_down(row) then
                    add_on = add_on | f | (S.ACTION_FLAGS.Shift1 or 0) | (S.ACTION_FLAGS.Shift2 or 0)
                end
                if R.row_pressed(row) then add_trg = add_trg | f end
                if state["native_k" .. n] and not R.row_down(row) then add_rel = add_rel | f end
                state["native_k" .. n] = R.row_down(row)
            end
        end
        -- 0.9.176-dev9: L2 / LT cancels a chant. The flags come from the ARISEN's input, built for his vocation, so a
        -- played mage never gets the game's cancel (report: "can't cancel spells"; Levin on a played Mage). dev8 added
        -- ActCancel to the pawn's flags: it never cancelled and made the button guide show follow-up attacks, so the
        -- flags are left alone now. On the press, while the played pawn is in a skill, end the action directly (the
        -- same calls DPC's jump-cancel uses) and check 0.25 s later whether the skill ended.
        local src = (S.ACTION_FLAGS.Sheathe or 0) | (S.ACTION_FLAGS.Draw or 0) | (S.ACTION_FLAGS.ActCancel or 0)
        if R.ct_press then -- dev chant_test: one frame of the L2 triggers, as the Arisen's input would carry them
            R.ct_press = nil
            trg_flags, on_flags = trg_flags | src, on_flags | src
            add_trg, add_on = add_trg | src, add_on | src
        end
        local l2 = ((R.pad_values and R.pad_values() or {}).LTrigBottom) or 0x200
        local l2_trg = (S.pad_buttons & l2) ~= 0 and (S.pad_prev & l2) == 0
        -- Mage / Sorcerer only: on other vocations the same button aims (Archer) or sheathes, and vanilla doesn't cancel
        -- their skills with it.
        if ((trg_flags & src) ~= 0 or l2_trg) and state.pawn_human and (state.pawn_job == 3 or state.pawn_job == 6) then
            local sk = call(state.pawn_human, "get_CustomSkillState") or 0
            if type(sk) == "number" and sk ~= 0 then
                if R.dev then
                    R.cprobe.until_t, R.cprobe.n, R.cprobe.vals = os.clock() + 1.5, 0, 0
                    pcall(R.cancel_gates, sk)
                    -- dev: wait 0.3 s first, so the log shows whether the game cancels by itself
                    R.cancel_pending = { t = os.clock() + 0.3, sk = sk }
                else
                    -- 0.9.177: with the input state fix the game cancels by itself; DPC ends the action only if the
                    -- skill is still running 0.25 s later (fallback, e.g. with pawn_prev_state off)
                    R.cancel_pending = { t = os.clock() + 0.25, sk = sk }
                end
            end
        end
        if add_on ~= 0 or add_trg ~= 0 or add_rel ~= 0 then
            set_field(state.pawn_input, "ButtonOnFlags", on_flags | add_on)
            set_field(state.pawn_input, "ButtonTriggerFlags", trg_flags | add_trg)
            set_field(state.pawn_input, "ButtonReleaseFlags", rel_flags | add_rel)
        end
    end

    -- v0.9.87 / 0.9.88 aimed skills for bow vocations. While aiming the skill buttons fire the aimed versions. The
    -- game only builds those Skill flags when the ARISEN is a bow vocation (the flags the pawn receives are made for
    -- the Arisen's layout), so with any other Arisen the possessed Archer got each button's ordinary action.
    --  Controller (L2 held): Square / Triangle / Circle / Cross = skills 1 - 4; with a skill in slot 5 or 6 the
    --   chords Square + Cross and Triangle + Circle fire Skill6 / Skill5 (0.9.99; 0.9.87 had Circle + Cross), and a lone chord button waits
    --   0.09 s for its partner (a shorter tap still fires on release).
    -- Always SkillN without Shift1 / Shift2, and without the button's own action.
    if cfg.pawn_aim_skills and cfg.native_controls and native.pip and not native.failed and state.pawn_input
       and not coop.active and (state.pawn_job == 2 or state.pawn_job == 8) then
        local now = os.clock()
        local A = R.as or { t = {}, out = {}, prev = 0 }
        R.as = A
        local pv = coop_pad_values()
        -- v0.9.124: the aim button is the one the game has AimHold on (default R1; it was fixed to L2, the tester's remap)
        local btn = S.pad_buttons or 0
        local pad_aim = R.bind_held("AimHold", btn, pv.RTrigTop or 0x400)
        local sq, tri, ci, cr = pv.RLeft or 0x40, pv.RUp or 0x10, pv.RRight or 0x80, pv.RDown or 0x20
        -- 0.9.100: slot -> button from the game's assignment. Only face buttons count under L2: a slot the game
        -- has on R1 / R2 stays a shot while aiming and is used with L1 as usual.
        local bp = R.bind and R.bind.pad or {}
        local facemask = sq | tri | ci | cr
        local faces = { sq, tri, cr, ci } -- fallback = the game's default slots 1 - 4 (0.9.124; was Circle before Cross)
        if next(bp) then
            for n = 1, 4 do
                local b = bp[n]
                faces[n] = (b and (b & ~facemask) == 0 and b ~= 0) and b or 0
            end
        end
        local six = state.pawn_skills and ((state.pawn_skills[5] or 0) ~= 0 or (state.pawn_skills[6] or 0) ~= 0)
        local want, strip = 0, 0
        if pad_aim or A.prev ~= 0 or A.latch then
            pcall(coop_ensure_map)
            local function own_flags(b)
                local f = 0
                for _, e in ipairs(coop.map or {}) do
                    if e.pad == b and not tostring(e.name):find("^Skill") then f = f | (e.flag or 0) end
                end
                return f
            end
            if A.latch and (btn & A.latch.pads) == 0 then A.latch = nil end
            if pad_aim and six and not A.latch then
                for _, c in ipairs({ { bp[6] or (sq | cr), "Skill6" }, { bp[5] or (tri | ci), "Skill5" } }) do -- 0.9.100: from the game's assignment
                    if (btn & c[1]) == c[1] and S.ACTION_FLAGS[c[2]] then A.latch = { pads = c[1], flag = S.ACTION_FLAGS[c[2]] }; break end
                end
            end
            for n, b in ipairs(faces) do
                local down = b ~= 0 and (btn & b) ~= 0
                if down and pad_aim then
                    strip = strip | own_flags(b)
                    if not A.t[b] then A.t[b], A.out[b] = now, false end
                    if A.latch and (A.latch.pads & b) ~= 0 then
                        A.out[b] = true -- part of a chord: never also a single skill
                    elseif not (six and now - A.t[b] < 0.09) then
                        want = want | (S.ACTION_FLAGS["Skill" .. n] or 0)
                        A.out[b] = true
                    end
                else
                    if A.t[b] and not A.out[b] and not A.latch then A.pulse_f, A.pulse_until = S.ACTION_FLAGS["Skill" .. n] or 0, now + 0.10 end
                    A.t[b], A.out[b] = nil, nil
                end
            end
            if A.latch and pad_aim then want = want | A.latch.flag end
            if A.pulse_until and now < A.pulse_until then want = want | (A.pulse_f or 0) end
        end
        -- v0.9.89: the 0.9.88 keyboard path (numpad keys while aiming) is gone. Clarified: number-pad skills are orders for a character that is not being played, so they are never the aimed versions. Which keys fire
        -- aimed skills on keyboard is still to be settled.
        local kb_strip = 0
        local trg_s, rel_s = want & ~A.prev, A.prev & ~want
        A.prev = want
        if want ~= 0 or trg_s ~= 0 or rel_s ~= 0 or strip ~= 0 then
            local on0 = field(state.pawn_input, "ButtonOnFlags") or 0
            local trg0 = field(state.pawn_input, "ButtonTriggerFlags") or 0
            local rel0 = field(state.pawn_input, "ButtonReleaseFlags") or 0
            set_field(state.pawn_input, "ButtonOnFlags", ((on0 & ~strip) & ~kb_strip) | want)
            set_field(state.pawn_input, "ButtonTriggerFlags", ((trg0 & ~strip) & ~kb_strip) | trg_s)
            set_field(state.pawn_input, "ButtonReleaseFlags", rel0 | rel_s)
            if trg_s ~= 0 then R.aim_skill_n = (R.aim_skill_n or 0) + 1 end
        end
    end

    -- v0.9.167 bow skills used from the hip. Measured on 0.9.166 (archer-chord-1, Archer pawn, skill-shift chords): a
    -- skill started while the aim button was held always fired; started from the hip it began (Prepare node) and the
    -- game cancelled it: Whirling Arrow went to Job02_AimCancel after 1.2 s, Full Blast to CrouchShotCancel after 0.4 s.
    -- For the player the game keeps a hip skill's aim up by itself; the pawn's input processor does not. So while the
    -- played Archer is in a skill's Prepare / Ready / charge stage, the aim flags are held for him, as if the aim
    -- button were down, until the skill leaves that stage. (The Arisen brain fires its bow skills the same way.)
    -- 0.9.172-dev18: also in co-op (reported: player 2's Archer "almost fires Spiral Arrow then aborts it, unless I
    -- also hold R1"; the block skipped co-op), and for player 2's / players 3+'s extra played pawns (R.s2_pre).
    if cfg.pawn_hip_skill_aim and cfg.native_controls and native.pip and not native.failed and state.pawn_input
       and state.pawn_job == 2 and state.pawn_chara then
        R.hip_aim_hold(state.pawn_input, state.pawn_chara, R.hip_main)
    end

    -- v0.9.26 the possessed pawn gathers and loots by himself. The game's Gather / Loot prompt is computed for the
    -- player character only (InteractManager.HighestPriorityObjectForPlayer). Verified live 2026-11-15 on a corpse:
    -- addActiveInteract(pawn, InteractPoint{object, 0}) + executeInteract(pawn) makes the pawn loot it and the
    -- item goes to the pawn's inventory. (requestInteractFromAI is not acted on while his AI is suspended.)
    -- Scan 5x a second for the nearest interactive object within pawn_interact_range; DPC draws the prompt; the
    -- game's own Interact button then triggers it, and that press is kept away from the pawn (it is also dash).
    if cfg.pawn_interact and state.pawn_input and state.pawn_chara then
        local now = os.clock()
        if now >= (R.int_next or 0) then
            R.int_next = now + 0.2
            local best, bn, bdead, bd, bpos = R.int_scan(state.pawn_chara) -- 0.9.177: shared with the other played pawns
            -- 0.9.177: a dead person who can be revived with a Wakestone, for player 1 only (R.rev_npc_press)
            R.int_rev = (cfg.pawn_revive_npc ~= false and not best and R.int_rev_best) or nil
            R.int_obj, R.int_name, R.int_dead, R.int_dist = best, bn, bdead, bd
            R.int_pos = bpos
            R.int_item = bn ~= nil and bn:find("^gm82_000") ~= nil
            -- v0.9.63 wake a sleeping companion. Requested: a possessed pawn can wake a sleeping pawn or the Arisen. A party member or the Arisen within range with the Sleep status (flag 4) takes the prompt.
            -- Done by curing the status directly (StatusConditionCtrl.reqStatusConditionCure), not through the
            -- game's rescue interact, after the forced-interact crash of 0.9.57.
            R.int_wake, R.int_wake_name = nil, nil
            if cfg.pawn_wake then
                pcall(function()
                    local px, py, pz = brain_pos(state.pawn_chara)
                    if not px then return end
                    local me = state.pawn_chara:get_address()
                    local list = {}
                    if state.arisen_chara then list[#list + 1] = { chara = state.arisen_chara, name = "the Arisen" } end
                    for _, e in ipairs(get_party()) do list[#list + 1] = e end
                    local wd
                    for _, e in ipairs(list) do
                        if e.chara:get_address() ~= me then
                            local sc = e.chara:call("get_StatusConditionCtrl")
                            local fl = sc and sc:call("get_ActiveStatusConditionFlagProp")
                            -- v0.9.68: a downed party pawn (not the Arisen) can be revived the same way
                            local down = cfg.pawn_revive and e.name ~= "the Arisen" and e.chara:call("get_IsDead") == true
                            if down or (type(fl) == "number" and (fl & 4) ~= 0) then
                                local x, y, z = brain_pos(e.chara)
                                local d = x and math.sqrt((x - px) ^ 2 + (y - py) ^ 2 + (z - pz) ^ 2)
                                if d and d <= (cfg.pawn_interact_range or 2.2) + 0.6 and (not wd or d < wd) then
                                    wd = d
                                    R.int_wake, R.int_wake_name = e.chara, tostring(e.name)
                                    R.int_wake_kind = down and "Revive" or "Wake"
                                    R.int_pos = { x, y + 0.4, z }
                                    R.int_obj = nil
                                end
                            end
                        end
                    end
                end)
            end
        end
        local f = S.ACTION_FLAGS.Interact or 0
        local strip = f | (S.ACTION_FLAGS.Dash or 0) | (S.ACTION_FLAGS.Sprint or 0)
        local on = field(state.pawn_input, "ButtonOnFlags") or 0
        local trg = field(state.pawn_input, "ButtonTriggerFlags") or 0
        if coop.active then f = S.ACTION_FLAGS.Dash or f end -- co-op: player 2's Triangle arrives as Dash (no Interact flag)
        -- v0.9.69: reviving needs the button held, like the Arisen's own revive; a ring fills while it is held
        -- (drawn with the prompt). Letting go, or the target changing, starts over. Waking stays a single press.
        local fire = (trg & f) ~= 0
        if R.int_wake and R.int_wake_kind == "Revive" and f ~= 0 and (cfg.pawn_revive_hold or 0) > 0 then
            fire = false
            local ad = R.int_wake:get_address()
            if (on & f) ~= 0 and now >= (R.int_cool or 0) then
                if R.rev_of ~= ad then R.rev_of, R.rev_t0 = ad, now end
                R.int_hold = true
                R.rev_prog = math.min(1.0, (now - R.rev_t0) / cfg.pawn_revive_hold)
                if R.rev_prog >= 1.0 then fire = true; R.rev_of, R.rev_prog = nil, nil end
            else
                R.rev_of, R.rev_prog = nil, nil
            end
        else
            R.rev_of, R.rev_prog = nil, nil
        end
        if R.int_wake and f ~= 0 and fire and now >= (R.int_cool or 0) then
            R.int_cool = now + 1.0
            R.int_hold = true
            R.wake_n = (R.wake_n or 0) + 1
            local okw, errw = pcall(function()
                if R.int_wake_kind == "Revive" then
                    -- Found live on a downed pawn (2026-11-15): PawnManager.getPartyPawn(chara) gives the app.Pawn,
                    -- setPawnRevive(hp, false, false) stands him up with that many health points (0.5 gave 0.5 hp),
                    -- so ask for half of his current maximum and set it again in case the first value is ignored.
                    local pm = sdk.get_managed_singleton("app.PawnManager")
                    local pw = pm and pm:call("getPartyPawn(app.Character, System.Boolean)", R.int_wake, false)
                    if not pw then error("no app.Pawn for the downed character") end
                    local hit = R.int_wake:call("get_Hit")
                    local mx = hit:call("get_ReducedMaxHp")
                    if type(mx) ~= "number" or mx <= 0 then mx = hit:call("get_OriginalMaxHp") or 100 end
                    local hp = mx * (cfg.pawn_revive_health or 0.5)
                    pw:call("setPawnRevive(System.Single, System.Boolean, System.Boolean)", hp, false, false)
                    if (hit:call("get_Hp") or 0) < hp * 0.9 then hit:call("setHpValue(System.Single, System.Boolean)", hp, false) end
                    return
                end
                local sc = R.int_wake:call("get_StatusConditionCtrl")
                -- the second press (if the first did not wake him) uses the flag overload instead
                if R.wake_n % 2 == 1 then
                    sc:call("reqStatusConditionCure(app.StatusConditionDef.StatusConditionEnum, System.Boolean)", 2, true)
                else
                    sc:call("reqStatusConditionCure(app.StatusConditionDef.StatusConditionFlag)", 4)
                end
            end)
            if okw and R.int_wake_kind == "Revive" then log_msg(string.format("%s: revived %s", tostring(state.pawn_name), tostring(R.int_wake_name)))
            elseif okw then log_msg(string.format("%s: woke %s (%s)", tostring(state.pawn_name), tostring(R.int_wake_name), (R.wake_n % 2 == 1) and "enum" or "flag"))
            else dev_error("pawn wake", errw) end
            R.int_wake = nil
            R.int_next = now + 0.6
        elseif R.int_rev and not R.int_obj and not R.int_wake and f ~= 0 and (trg & f) ~= 0 and now >= (R.int_cool or 0) then
            R.int_cool = now + 0.4
            R.int_hold = true
            pcall(R.rev_npc_press, now)
        elseif not R.int_obj and not R.int_wake and f ~= 0 and (trg & f) ~= 0 and now >= (R.int_miss_t or 0) and cfg.pawn_interact_log ~= false then
            R.int_miss_t = now + 3.0
            log_msg(string.format("%s: interact pressed, nothing DPC can use within %.1f m (dead people left to the Arisen so far: %d, last %s)",
                tostring(state.pawn_name), cfg.pawn_interact_range or 2.2, R.int_skipped_people or 0, tostring(R.int_skipped_last)))
        elseif R.int_obj and f ~= 0 and (trg & f) ~= 0 and now >= (R.int_cool or 0) then
            R.int_cool = now + 1.0
            R.int_hold = true
            local obj = R.int_obj
            local okx, errx = pcall(function()
                local im = sdk.get_managed_singleton("app.InteractManager")
                if im:call("isInteracting(app.Character)", state.pawn_chara) then
                    -- v0.9.29: an interact that never finished (seen with a dropped item) blocked every later press
                    if now - (R.int_last_t or 0) < 3.0 then return end
                    im:call("endInteract(app.Character)", state.pawn_chara)
                end
                R.int_last_t = now
                R.loot_window_open() -- 0.9.174: hand what this gives to the Arisen, if that option is on
                local pt = sdk.create_instance("app.InteractManager.InteractPoint"):add_ref()
                pt:set_field("Object", obj)
                pt:set_field("PointNo", 0) -- 0.9.177: 0.9.176-dev5 put the lean lab's `sp.pno` here by mistake (nil global: every pick-up failed)
                im:call("addActiveInteract(app.Character, app.InteractManager.InteractPoint)", state.pawn_chara, pt)
                im:call("executeInteract(app.Character)", state.pawn_chara)
                if R.int_item then
                    -- v0.9.29 dropped items (gm82_000_*): execute alone does nothing (item still there, pawn left
                    -- "interacting"); the object's Start handler is what takes it (bridge test 2026-11-15).
                    obj:get_field("StartInteractHandler"):call("Invoke", 0, state.pawn_chara)
                end
            end)
            R.int_n = (R.int_n or 0) + 1
            local to_ar = (R.loot_win and R.loot_win.n > 0) and string.format(" (%d to the Arisen)", R.loot_win.n) or ""
            if okx then log_msg(string.format("%s: %s %s%s", tostring(state.pawn_name), R.int_dead and "looted" or "used", tostring(R.int_name), to_ar))
            else dev_error("pawn interact", errx) end
            R.int_obj = nil
            R.int_next = now + 0.6
        end
        if R.int_hold then
            if f == 0 or (on & f) == 0 then R.int_hold = false
            else
                set_field(state.pawn_input, "ButtonOnFlags", on & ~strip)
                set_field(state.pawn_input, "ButtonTriggerFlags", trg & ~strip)
            end
        end
    else
        R.int_obj, R.int_wake = nil, nil
    end

    R.ai_watch() -- v0.9.88 a possessed pawn does not run off on an order
    R.item_tick() -- v0.9.77 the game's quick-use item shortcut, for the pawn being played
    R.aim_tick() -- v0.9.29 bow aim camera for the possessed Archer
    R.gyro_tick() -- v0.9.39 co-op: player 2's controller must not gyro-aim the Arisen

    -- v0.9.24 interact helper. Looting, gathering, chests and talking belong to the Arisen even while a pawn is
    -- possessed, so they only work where he stands. Out of battle, pressing Interact while he is more than
    -- interact_bring_dist away brings him to the pawn (the same warp as F8); press again to interact.
    if cfg.interact_bring and state.pawn_input and not coop.active and state.arisen_chara and state.pawn_chara then
        local f = S.ACTION_FLAGS.Interact or 0
        local trg = field(state.pawn_input, "ButtonTriggerFlags") or 0
        local now = os.clock()
        if f ~= 0 and (trg & f) ~= 0 and now >= (R.bring_next or 0) and not brain.in_battle() then
            local ax, _, az = brain_pos(state.arisen_chara)
            local px, _, pz = brain_pos(state.pawn_chara)
            if ax and px then
                local d = math.sqrt((ax - px) ^ 2 + (az - pz) ^ 2)
                if d > (cfg.interact_bring_dist or 2.0) then
                    R.bring_next = now + 1.5
                    R.brings = (R.brings or 0) + 1
                    log_msg(string.format("Interact: Arisen was %.1f m away -> brought to %s", d, tostring(state.pawn_name)))
                    warp_arisen_to_pawn()
                end
            end
        end
    end

    -- v0.9.21 chorded skills on the possessed pawn. TestGuide chord-flags-2: on the controller the game raises
    -- the chord flag together with the single-button flags (L1 + Square+Cross -> Skill1 + Jump + ... + Skill6;
    -- L1 + Triangle+Circle -> Skill2 + ActCancel + ... + Skill5). The Arisen does the chord skill; the possessed
    -- pawn's processor got the same flags and did the single skill (Blink Strike / Full Moon Guard). While a chord
    -- flag is on, take the single-button actions out of the pawn's input so only the chord is left (that form is
    -- what co-op sends, and it fires).
    if cfg.native_controls and native.pip and not native.failed and state.pawn_input and not coop.active then
        local chord = (S.ACTION_FLAGS.Skill5 or 0) | (S.ACTION_FLAGS.Skill6 or 0)
        local on = field(state.pawn_input, "ButtonOnFlags") or 0
        if chord ~= 0 and (on & chord) ~= 0 then
            local strip = 0
            for _, n in ipairs({ "Skill1", "Skill2", "Skill3", "Skill4", "Jump", "ActCancel", "Sheathe", "Draw", "Descent",
                                 "GimmickCancel", "Job09AstralDown", "Grab", "Interact", "Dash" }) do
                strip = strip | (S.ACTION_FLAGS[n] or 0)
            end
            strip = strip & ~chord
            set_field(state.pawn_input, "ButtonOnFlags", on & ~strip)
            set_field(state.pawn_input, "ButtonTriggerFlags", (field(state.pawn_input, "ButtonTriggerFlags") or 0) & ~strip)
            set_field(state.pawn_input, "ButtonReleaseFlags", (field(state.pawn_input, "ButtonReleaseFlags") or 0) & ~strip)
            R.chord_strips = (R.chord_strips or 0) + 1
        end
    end

    if native.pip and (field(state.pawn_input, "ButtonOnFlags") or 0) ~= 0 then
        native.mirror_input_frames = native.mirror_input_frames + 1
    end
    -- v0.7: the game's own player controls drive the pawn; skip the hand-built puppeteer below.
    if native_tick() then
        state.last_action_str = "Native controls"
        return
    end

    -- Check whether a given skill slot (1..4) is currently held down by the player
    local function is_skill_slot_held(slot)
        if slot == 1 and (is_on("Skill1") or (shift_skill_mod and is_on("AttackS")) or ((R.row_down(0x31) or S.is_key_down_safe(0x61)))) then return true end
        if slot == 2 and (is_on("Skill2") or (shift_skill_mod and is_on("AttackL")) or ((R.row_down(0x32) or S.is_key_down_safe(0x62)))) then return true end
        if slot == 3 and (is_on("Skill3") or (shift_skill_mod and is_on("Jump"))    or ((R.row_down(0x33) or S.is_key_down_safe(0x63)))) then return true end
        if slot == 4 and (is_on("Skill4") or (shift_skill_mod and (is_on("Grab") or is_on("Interact") or is_on("ActCancel") or is_on("Dash"))) or ((R.row_down(0x34) or S.is_key_down_safe(0x64)))) then return true end
        if slot == 5 and (is_on("Skill5") or ((R.row_down(0x35) or S.is_key_down_safe(0x65)))) then return true end
        if slot == 6 and (is_on("Skill6") or ((R.row_down(0x36) or S.is_key_down_safe(0x66)))) then return true end
        return false
    end

    -- Fix Issue 4: Full-Speed Sprinting (app.LocomotionSpeedTypeEnum: Idle=0, Walk=1, Run=2, Dash=3)
    -- Sprint latches when Dash / KeepDash / Left Shift is pressed while moving, and clears when stopping
    local is_strafe = (state.is_guarding or state.is_aiming)
    local dash_pressed = (not shift_skill_mod) and (is_trg("Dash") or is_on("Dash") or is_on("KeepDash") or R.key_held("Dash", 0x10))
    if mag > 0.20 and dash_pressed and not is_strafe then
        state.is_sprinting = true
    elseif mag <= 0.15 or is_strafe then
        state.is_sprinting = false
    end

    local is_dash = state.is_sprinting and not is_strafe
    local speed_type = SPEED_IDLE
    if mag > 0.12 then
        if is_dash then
            speed_type = SPEED_DASH -- 3 = Full Sprint!
        elseif mag > 0.50 then
            speed_type = SPEED_RUN  -- 2 = Normal Run
        else
            speed_type = SPEED_WALK -- 1 = Walk
        end
    end

    local now = os.clock()
    local cur_sk = call(pawn_human, "get_CustomSkillState") or 0
    local in_skill = (type(cur_sk) == "number" and cur_sk ~= 0)

    if cfg.sub_puppeteer_combat or cfg.native_controls then -- native fallback (Thief / errors) always needs it
        -- 0a. Process pending skill retry window (PawnCommander pattern: ensures skill fires after weapon draw)
        if state.pending_skill then
            local ps = state.pending_skill
            if cur_sk == ps.id and cur_sk ~= 0 then
                state.pending_skill = nil
                R.skill_ok_n = (R.skill_ok_n or 0) + 1
            elseif now > ps.until_t then
                state.pending_skill = nil
                pcall(R.skill_fail_note, ps, cur_sk) -- 0.9.175: say why a skill didn't start
            else
                pcall(sel.call, sel, "requestCustomSkill", ps.id, ps.speed_type)
                ps.tries = ps.tries + 1
            end
        end

        -- 0b. Fix Issue 3: Process Active Spell / Chanting Completion (Mage, Sorcerer, Magick Archer, etc.)
        if in_skill then
            if not state.active_cast or state.active_cast.id ~= cur_sk then
                -- Find which equipped slot this skill lives in (was hard-coded to slot 1)
                local slot = 1
                for s = 1, 6 do
                    if state.pawn_skills and state.pawn_skills[s] == cur_sk then slot = s break end
                end
                state.active_cast = {
                    id = cur_sk,
                    slot = slot,
                    start_t = now,
                    released = false,
                    is_ready = false,
                    release_tries = 0,
                    next_release_t = 0.0,
                }
            end
            local cast = state.active_cast
            update_pawn_lockon_target()

            -- Check if CurrentSelector reports the spell chant is ready to release
            local cur_sel = field(sel, "CurrentSelector")
            local ready_flag = false
            if cur_sel then
                local ok_r, r_val = pcall(cur_sel.call, cur_sel, "isReadySpellAction")
                if ok_r and r_val == true then
                    ready_flag = true
                end
            end
            cast.is_ready = ready_flag

            -- Mage / Sorcerer Quickspell while chanting (hold JobSpecialAction / Left Trigger / Right Click)
            if (job == 3 or job == 6) and is_on("JobSpecialAction") then
                call(sel, "requestAction(System.String, System.UInt32)", "Concentrate", 0)
                call(sel, "setAction(System.String, System.Boolean, System.UInt32)", "Concentrate", true, 0)
                state.is_quickspelling = true
            elseif state.is_quickspelling then
                state.is_quickspelling = false
                call(sel, "setAction(System.String, System.Boolean, System.UInt32)", "Concentrate", false, 0)
            end

            -- Release rules (v0.6.0: fire ONCE, with up to 3 spaced retries, never every frame):
            --   * Spell jobs (Mage/Sorcerer): release when the chant reports ready and the player isn't
            --     holding the slot to store it (AttackS fires a stored spell). Fallback after
            --     cfg.spell_release_fallback seconds if isReadySpellAction never reports ready.
            --   * Other jobs (charge skills): release when the player lets go of the slot button (>0.35 s).
            local holding_slot = is_skill_slot_held(cast.slot)
            local elapsed = now - cast.start_t
            local is_spell_job = (job == 3 or job == 6)
            local want_release
            if is_spell_job then
                want_release = (ready_flag and (not holding_slot or is_trg("AttackS")))
                    or (not holding_slot and elapsed > (cfg.spell_release_fallback or 2.5))
            else
                want_release = (elapsed > 0.35 and not holding_slot)
            end
            local can_retry = (not cast.released) or (cast.release_tries < 4 and now >= cast.next_release_t)
            if want_release and can_retry then
                call(sel, "requestRelease()")
                call(sel, "requestShoot()")
                cast.released = true
                cast.release_tries = cast.release_tries + 1
                cast.next_release_t = now + 0.4
                state.last_action_str = string.format("Casting %s", skill_name(cur_sk))
            elseif cast.released then
                state.last_action_str = string.format("Casting %s", skill_name(cur_sk))
            elseif ready_flag and holding_slot then
                state.last_action_str = string.format("Spell Ready (Holding): %s", skill_name(cur_sk))
            else
                state.last_action_str = string.format("Chanting%s: %s",
                    state.is_quickspelling and " (Quickspell)" or "", skill_name(cur_sk))
            end
        else
            state.active_cast = nil
            state.is_quickspelling = false
        end

        -- 0b2. Combo buffer: fire the queued light attack once the combo window opens
        trace_attack_frames(sel)
        if state.combo_buffer then
            local cb = state.combo_buffer
            local nxt = call(sel, "get_NextComboAction")
            local window_open = type(nxt) == "string" and nxt ~= ""
            if window_open or now > cb.until_t or in_locomotion(pawn_chara) then
                state.combo_buffer = nil
                dbg_event("ATK", window_open and ("fire(window " .. nxt .. ")") or (now > cb.until_t and "fire(timeout)" or "fire(locomotion)"))
                call(sel, "requestNormalAttack(app.LocomotionSpeedTypeEnum)", cb.speed_type)
                call(sel, "requestComboAction(app.LocomotionSpeedTypeEnum)", cb.speed_type)
                -- Same as a direct press: keep locomotion requests from overriding the attack this frame
                state.suppress_loco_until = math.max(state.suppress_loco_until, now + 0.35)
                return
            end
        end

        -- 0c. Process pending attack retry window (ensures attack fires if triggered while weapon was sheathed)
        if state.pending_attack then
            local pa = state.pending_attack
            if now > pa.until_t or not in_locomotion(pawn_chara) then
                state.pending_attack = nil
            elseif call(pawn_chara, "get_IsDrawedWeapon") then
                if pa.heavy then
                    call(sel, "requestSubNormalAttack(app.LocomotionSpeedTypeEnum)", pa.speed_type)
                else
                    call(sel, "requestNormalAttack(app.LocomotionSpeedTypeEnum)", pa.speed_type)
                end
                pa.tries = pa.tries + 1
            end
        end

        -- 1. Check Custom Skills (Skill1..Skill4, Shift1 + Face Buttons, or Keyboard 1..4 / Numpad 1..4)
        local skill_slot_triggered = nil

        if is_trg("Skill1") then skill_slot_triggered = 1
        elseif is_trg("Skill2") then skill_slot_triggered = 2
        elseif is_trg("Skill3") then skill_slot_triggered = 3
        elseif is_trg("Skill4") then skill_slot_triggered = 4
        elseif is_trg("Skill5") then skill_slot_triggered = 5
        elseif is_trg("Skill6") then skill_slot_triggered = 6
        elseif shift_skill_mod then
            if is_trg("AttackS") then skill_slot_triggered = 1
            elseif is_trg("AttackL") then skill_slot_triggered = 2
            elseif is_trg("Jump") then skill_slot_triggered = 3
            elseif is_trg("Grab") or is_trg("Interact") or is_trg("ActCancel") or is_trg("Dash") then skill_slot_triggered = 4
            end
        end

        -- Direct keyboard number row 1-4 (0x31..0x34) & Numpad 1-4 (0x61..0x64) skill hotkeys
        if cfg.debug_input then
            for vk = 0x31, 0x36 do
                local d = S.is_key_down_safe(vk)
                if d and not state["dbg_k" .. vk] then dbg_event("KEY", tostring(vk - 0x30) .. " ui_open=" .. tostring(ui_open)) end
                state["dbg_k" .. vk] = d
            end
        end
        if not skill_slot_triggered then
            if R.row_pressed(0x31) or key_pressed(0x61) then skill_slot_triggered = 1
            elseif R.row_pressed(0x32) or key_pressed(0x62) then skill_slot_triggered = 2
            elseif R.row_pressed(0x33) or key_pressed(0x63) then skill_slot_triggered = 3
            elseif R.row_pressed(0x34) or key_pressed(0x64) then skill_slot_triggered = 4
            elseif R.row_pressed(0x35) or key_pressed(0x65) then skill_slot_triggered = 5
            elseif R.row_pressed(0x36) or key_pressed(0x66) then skill_slot_triggered = 6
            end
        end

        if skill_slot_triggered then
            if state.is_guarding then
                pawn_set_fighter_guard(false, ax, ay, mag)
            end
            pawn_do_skill_slot(skill_slot_triggered, speed_type, ax, ay, mag)
            return
        end

        -- In Mode 2 (ActionSelector Puppeteer), handle Vocation Action (Defend/Aim/Dodge), Jump, Attacks, Draw/Sheathe
        if cfg.control_mode == 2 then
            -- 2. Fix Issue 2: Vocation Action (Defend / Aim / Quickspell / Dodge)
            local rmb_down = (not ui_open) and R.key_held("JobSpecialAction", 0x02) -- v0.9.124: the game's vocation action key
            local rmb_trg = (not ui_open) and key_pressed(0x02)
            local pad_lt_down = R.bind_held("JobSpecialAction", S.pad_buttons or 0, 0x0400) -- v0.9.124: the game's vocation action button (default R1; was fixed to L2)
            local voc_on = is_on("JobSpecialAction") or is_on("AimHold") or is_on("Shift1OnlySpecificJob") or rmb_down or pad_lt_down
            local voc_trg = is_trg("JobSpecialAction") or is_trg("AimHold") or is_trg("Shift1OnlySpecificJob") or rmb_trg

            if job == 1 then
                -- Fighter: Hold JobSpecialAction / RMB / LT to Defend (Shield Guard)
                local guard_down = voc_on and not shift_skill_mod
                if guard_down and not in_skill then
                    pawn_set_fighter_guard(true, ax, ay, mag)
                elseif state.is_guarding and not guard_down then
                    pawn_set_fighter_guard(false, ax, ay, mag)
                end
            elseif job == 2 or job == 8 then
                -- Archer / Magick Archer: Hold JobSpecialAction / AimHold to Aim Bow
                if voc_on and not in_skill then
                    if not call(pawn_chara, "get_IsDrawedWeapon") then
                        call(sel, "requestDrawWeapon()")
                    end
                    local aim_deg = compute_camera_move_angle_deg(0.0, 1.0)
                    call(pawn_chara, "set_TargetFrontAngleDeg(System.Single)", aim_deg)
                    -- v0.9.126: a requestAimAction(app.LocomotionSpeedTypeEnum) call was removed here. The real
                    -- method takes no arguments, so that signature never matched and the call never ran: the
                    -- aim the pawn does enter (Job02_StartAim) comes from the mirrored AimHold input.
                    state.is_aiming = true
                    state.last_action_str = "Aiming Bow"
                elseif state.is_aiming and not voc_on then
                    state.is_aiming = false
                    call(sel, "requestEndAction()")
                end
            elseif job == 4 then
                -- Thief: Swift Step (Dodge)
                if voc_trg then
                    if mag > 0.12 then
                        local move_deg = compute_camera_move_angle_deg(ax, ay)
                        call(pawn_chara, "set_TargetMoveAngleDeg(System.Single)", move_deg)
                        call(pawn_chara, "set_TargetFrontAngleDeg(System.Single)", move_deg)
                    end
                    call(sel, "requestAction(System.String, System.UInt32)", "DodgeOfRing", 0)
                    state.suppress_loco_until = math.max(state.suppress_loco_until, now + 0.30)
                    state.last_action_str = "Swift Step"
                    return
                end
            elseif (job == 3 or job == 6) then
                -- Mage / Sorcerer: When not chanting, JobSpecialAction triggers Anodyne / Galvanize
                if voc_trg and not in_skill then
                    pawn_do_attack(true, speed_type, ax, ay, mag)
                    state.last_action_str = (job == 3) and "Anodyne" or "Galvanize"
                    return
                end
            else
                -- Warrior (Barge) & other vocations
                if voc_trg and not in_skill then
                    pawn_do_attack(true, speed_type, ax, ay, mag)
                    state.last_action_str = VOCATION_ACTION_NAMES[job] or "Vocation Action"
                    return
                end
            end

            -- 3. Jump (Action bitflag or Spacebar 0x20 when UI closed)
            if is_trg("Jump") or key_pressed(0x20) then
                if state.is_guarding then pawn_set_fighter_guard(false, ax, ay, mag) end
                pawn_do_jump(speed_type, ax, ay, mag)
                return
            end

            -- 4. Light Attack (AttackS bitflag, or optional raw LMB fallback)
            local lmb_trg = cfg.raw_mouse_fallback and (not ui_open) and key_pressed(0x01)
            if (not shift_skill_mod) and (is_trg("AttackS") or lmb_trg) then
                if state.is_guarding then pawn_set_fighter_guard(false, ax, ay, mag) end
                pawn_do_attack(false, speed_type, ax, ay, mag)
                return
            end

            -- 5. Heavy Attack (AttackL bitflag ONLY — never hijacks JobSpecialAction!)
            if (not shift_skill_mod) and is_trg("AttackL") then
                if state.is_guarding then pawn_set_fighter_guard(false, ax, ay, mag) end
                pawn_do_attack(true, speed_type, ax, ay, mag)
                return
            end

            -- 6. Draw / Sheathe / Lantern
            if is_trg("Sheathe") then
                if state.is_guarding then pawn_set_fighter_guard(false, ax, ay, mag) end
                pawn_do_sheathe(pawn_chara, sel)
                return
            elseif is_trg("Draw") then
                pawn_do_draw(pawn_chara, sel)
                return
            elseif is_trg("Lantern") then
                call(sel, "requestToggleLanternAction()")
                state.last_action_str = "Toggle Lantern"
                return
            end
        end
    end

    -- 7. Camera-Relative Locomotion
    --    Do NOT call requestLocomotionImpl during attack/skill/draw startup (suppress_loco_until),
    --    while guarding as Fighter, or while a Custom Skill is actively executing!
    if cfg.sub_puppeteer_move or cfg.native_controls then
        -- Player-like: while the full-body layer is in an attack / action node, movement input only steers
        -- (TargetMoveAngle) and never requests locomotion or idle, which would cancel the swing. The
        -- action tree returns to Locomotion on its own when the move ends.
        local in_action_startup = (now < state.suppress_loco_until) or (state.pending_skill ~= nil)
            or not in_locomotion(pawn_chara)

        if mag > 0.12 then
            local move_deg = compute_camera_move_angle_deg(ax, ay)
            state.last_move_deg = move_deg
            -- Always update target angle so attacks/skills/guard can steer toward stick direction
            call(pawn_chara, "set_TargetMoveAngleDeg(System.Single)", move_deg)

            -- Fighter Defend guard-walk (player-like): native guard puts layer 0 into Locomotion.Strafe
            -- and layer 1 into Job01.Job01_Guard. Locomotion requests only touch layer 0, so keep
            -- driving Strafe at walk speed while the shield stays up, facing camera-forward.
            if state.is_guarding and not in_skill and not in_action_startup then
                call(pawn_chara, "set_TargetFrontAngleDeg(System.Single)", compute_camera_move_angle_deg(0.0, 1.0))
                call(pawn_human, "set_IsDash(System.Boolean)", false)
                call(pawn_human, "set_IsPrevDash(System.Boolean)", false)
                safe_request_locomotion(sel, SPEED_WALK, true)
                state.was_moving = true
                state.last_action_str = "Defend (Guard Walk)"
            end

            if not in_skill and not in_action_startup and not state.is_guarding then
                if not state.is_aiming then
                    call(pawn_chara, "set_TargetFrontAngleDeg(System.Single)", move_deg)
                end

                -- Native Human & Character dash flags (Player Mirror)
                if is_dash then
                    call(pawn_human, "set_IsDash(System.Boolean)", true)
                    call(pawn_human, "set_IsPrevDash(System.Boolean)", true)
                    call(pawn_human, "notifyKeepDash")
                    call(pawn_human, "setLocomotionSpeedType(app.LocomotionSpeedTypeEnum)", SPEED_DASH)
                    call(pawn_chara, "setLocomotionSpeed(app.LocomotionSpeedTypeEnum)", SPEED_DASH)
                    call(pawn_chara, "set_DiscreteLocomotionSpeedType(app.LocomotionSpeedTypeEnum)", SPEED_DASH)
                else
                    call(pawn_human, "set_IsDash(System.Boolean)", false)
                    call(pawn_human, "set_IsPrevDash(System.Boolean)", false)
                end

                local hcac = call(pawn_human, "get_HumanCommonActionCtrl")
                if hcac then
                    call(hcac, "set_IsEnableDashToRequestedMoveSpeedOfNormalLocomotion(System.Boolean)", is_dash)
                    pcall(hcac.call, hcac, "requestMoveSpeedOfNormalLocomotion(System.Single, System.Boolean)", 1.0, is_dash)
                end

                -- Note: Second argument is is_strafe!
                -- false = NormalLocomotion (forward run/sprint), true = Strafe (combat sidestep)
                safe_request_locomotion(sel, speed_type, is_strafe)
                state.was_moving = true
                state.last_action_str = is_dash and "Sprint (Dash)" or (speed_type == SPEED_RUN and "Run" or "Walk")
            end
        elseif cfg.control_mode == 2 and state.was_moving and not in_skill and not in_action_startup and not state.is_guarding then
            state.was_moving = false
            state.is_sprinting = false
            call(pawn_human, "set_IsDash(System.Boolean)", false)
            call(pawn_human, "set_IsPrevDash(System.Boolean)", false)
            if call(sel, "isEnableRequestIdle") then
                call(sel, "requestIdleImpl(System.Boolean)", false)
            end
            state.last_action_str = "Idle"
        elseif cfg.control_mode == 2 and state.was_moving and state.is_guarding and not in_skill and not in_action_startup then
            -- Stopped while guarding: hold Strafe in place (speed Idle) so the guard-walk doesn't keep drifting
            state.was_moving = false
            call(pawn_chara, "set_TargetFrontAngleDeg(System.Single)", compute_camera_move_angle_deg(0.0, 1.0))
            safe_request_locomotion(sel, SPEED_IDLE, true)
            state.last_action_str = "Defend (Shield Guard)"
        end
    end
end

-- ----------------------------------------------------------------------------
-- Main Per-Frame Update Loop (Game Thread: UpdateBehavior)
-- ----------------------------------------------------------------------------
-- Fill the render-thread snapshot (party list for the UI, HUD values, diagnostics).
local function refresh_ui_cache()
    local now = os.clock()
    if cfg.window_open and now >= ui_cache.next_party_t then
        ui_cache.next_party_t = now + 0.5
        ui_cache.party = get_party()
        if cfg.window_open then
            local cam_mgr = sdk.get_managed_singleton("app.CameraManager")
            local mcc = cam_mgr and call(cam_mgr, "getMainCameraController", 0)
            local cam_tc = mcc and call(mcc, "get_TargetCharacter")
            ui_cache.cam_id = tostring(cam_tc and call(cam_tc, "get_CharaIDString") or "nil")
        end
    end
    if state.active and state.pawn_chara then
        ui_cache.hp = call(state.pawn_chara, "get_Hp") or 0
        ui_cache.max_hp = call(state.pawn_chara, "get_OriginalMaxHp") or 1
        ui_cache.active_sk = (state.pawn_human and call(state.pawn_human, "get_CustomSkillState")) or 0
        ui_cache.weapon_drawn = call(state.pawn_chara, "get_IsDrawedWeapon") == true
    end
end

-- shared with the modules loaded after this one (see shared.lua)
S.update_puppeteer_controls, S.refresh_ui_cache = update_puppeteer_controls, refresh_ui_cache
