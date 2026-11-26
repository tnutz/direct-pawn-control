-- Direct Pawn Control: couch co-op: player 2 on a controller.
-- Part of DirectPawnControl.lua, which loads the files in this folder in order (this one is 09 of 26).
-- Never run on its own: REFramework only runs the files directly in reframework/autorun.
local S = require("DirectPawnControl/shared")
local VERSION, dev_error, cfg, save_cfg, R, log_msg = S.VERSION, S.dev_error, S.cfg, S.save_cfg, S.R, S.log_msg
local field, enqueue_game_thread, read_enum = S.field, S.enqueue_game_thread, S.read_enum
local ensure_enums, get_party, state, addr_of, coop = S.ensure_enums, S.get_party, S.state, S.addr_of, S.coop
local COOP_OVERRIDES, coop_event, brain_pos = S.COOP_OVERRIDES, S.coop_event, S.brain_pos
local brain_angdiff, native, quick_arisen = S.brain_angdiff, S.native, S.quick_arisen
local release_possession, start_possession = S.release_possession, S.start_possession

-- ----------------------------------------------------------------------------
-- v0.9 Couch co-op: player 2 plays a pawn on a controller, player 1 plays the Arisen on mouse+keyboard.
-- Built without a live test (2026-11-11 night); every guess below self-checks and reports in the telemetry
-- (data/DPC_arisen_brain.json -> "coop") and the log.
--   * Pawn: DPC's native controls, fed only from the pad (via.hid.GamePad merged device). Pad buttons become
--     CharacterInput actions through the game's own pad assignment (UserInput.getButton(action) on the Arisen's
--     input), else a built-in DualSense layout.
--   * Arisen: runs normally. processButton (the pad path) gets an empty pad for his input; his move stick is
--     replaced by the keyboard axis (UserInput.KeyboardMouseAxisL); any pad-derived actions left in his
--     buttons are masked out.
--   * Camera stays on the Arisen; DPC writes data/DPC_coop.json for CameraDistance's co-op framing.
-- ----------------------------------------------------------------------------
local COOP_SKILLS = { "Skill1", "Skill2", "Skill3", "Skill4" }
-- v0.9.124: player 2's buttons follow the game's own controller assignment (R.bind.list, every binding the options
-- menu shows), whatever the player has remapped. Until 0.9.123 the fixed table here was the layout measured on the
-- user's controller on 2026-11-12, which turned out to be his own remap (R1 / R2 attacks, L2 vocation action,
-- Triangle dash, Circle sheathe), so with the game's default layout player 2 got the wrong action on most buttons.
-- The table below is only the fallback when the game's list cannot be read, and it is now the game's DEFAULT
-- layout (read from the running game on 2026-11-17, the tester's notes):
--   Square light, Triangle heavy, Cross jump, Circle interact / dash, L3 dash, R2 grab, L2 sheathe / draw / cancel,
--   R1 vocation action / aim, L1 skill shift, R3 lock-on, L1 + Square / Triangle / Cross / Circle = skills 1 - 4.
local COOP_SHIFT_L1, COOP_SHIFT_L2 = "LTrigTop", "RTrigTop"
local COOP_BUILTIN = {
    { act = { "AttackS", "Present", "GimmickSpecial2", "GliderDescent" }, pad = { "RLeft" } },
    { act = { "AttackL", "GimmickSpecial1", "GliderAscent", "Job09AstralUp" }, pad = { "RUp" } },
    { act = { "Jump", "GimmickCancel", "Job09AstralDown" }, pad = { "RDown" } },
    { act = { "Interact", "Dash", "Job01GuardLockOnChange" }, pad = { "RRight" } },
    { act = { "Dash" }, pad = { "LStickPush" } },
    { act = { "Grab" }, pad = { "RTrigBottom" } },
    { act = { "ActCancel", "Sheathe", "Draw" }, pad = { "LTrigBottom" } },
    { act = { "AimHold", "JobSpecialAction", "ShootRelease", "ThrowRelease", "Shift1OnlySpecificJob", "GimmickAction" }, pad = { "RTrigTop" } },
    { act = { "Shift1", "Shift2" }, pad = { "LTrigTop" } },
    { act = { "SwitchLockOn", "CameraReset", "SwitchSkill" }, pad = { "RStickPush" } },
    { act = { "Skill1" }, pad = { "RLeft" }, shift = true },
    { act = { "Skill2" }, pad = { "RUp" }, shift = true },
    { act = { "Skill3" }, pad = { "RDown" }, shift = true },
    { act = { "Skill4" }, pad = { "RRight" }, shift = true },
}
-- Not for player 2's pawn: pawn orders and the item shortcuts (the mod handles his D-pad itself), and Skill5 / 6
-- (the chord logic in coop.pad_input adds those).
local COOP_NOT_P2 = { Come = true, Go = true, Help = true, Wait = true, ItemMenu = true, Lantern = true,
    RecoverHpItem = true, RecoverStaminaItem = true, Skill5 = true, Skill6 = true }

local coop_pad_cache = nil
local function coop_pad_values()
    if coop_pad_cache then return coop_pad_cache end
    local _, by_name = read_enum("via.hid.GamePadButton")
    if by_name and next(by_name) then coop_pad_cache = by_name end
    return by_name or {}
end
R.pad_values = coop_pad_values

-- Try the game's own assignment: UserInput.getButton(actionFlag) -> pad button(s) bound to that action.
local function coop_build_game_map()
    local inp = state.arisen_input
    if not (inp and S.ACTION_FLAGS) then return nil end
    local all_pad = 0
    for _, v in pairs(coop_pad_values()) do if type(v) == "number" and v > 0 then all_pad = all_pad | v end end
    local map, n = {}, 0
    for name, flag in pairs(S.ACTION_FLAGS) do
        local ok, b = pcall(inp.call, inp, "getButton(System.UInt64)", flag)
        if ok and type(b) == "number" and b > 0 and (all_pad == 0 or (b & ~all_pad) == 0) then
            map[#map + 1] = { flag = flag, name = name, pad = b }
            n = n + 1
        end
    end
    if n < 6 then return nil, n end
    return map, n
end

-- v0.9.124: the map from the game's assignment list. An entry with `pre` only counts while that shift is held.
local function coop_build_assign_map()
    local l = R.bind and R.bind.list
    if not l or #l < 10 then return nil, l and #l or 0 end
    local map = {}
    for _, e in ipairs(l) do
        if not COOP_NOT_P2[e.name] and e.pad ~= 0 and e.flag and e.flag ~= 0 then
            map[#map + 1] = { flag = e.flag, name = e.name, pad = e.pad, shift = e.pre ~= nil, pre = e.pre }
        end
    end
    return map, #map
end

local function coop_build_builtin_map()
    local pv = coop_pad_values()
    local map = {}
    for _, e in ipairs(COOP_BUILTIN) do
        local pad = 0
        for _, pn in ipairs(e.pad) do pad = pad | (pv[pn] or 0) end
        if pad ~= 0 then
            for _, an in ipairs(e.act) do
                if S.ACTION_FLAGS[an] then map[#map + 1] = { flag = S.ACTION_FLAGS[an], name = an, pad = pad, shift = e.shift } end
            end
        end
    end
    return map
end

local function coop_ensure_map()
    if coop.map then return end
    ensure_enums()
    if cfg.coop_map_assign ~= false then
        pcall(function() R.bind_next = 0; R.bind_read() end)
        local m, n = coop_build_assign_map()
        if m then
            coop.map, coop.map_src = m, "game assignment (" .. n .. " bindings)"
        else
            coop_event("the game's controller assignment could not be read (" .. tostring(n) .. " bindings) -> default layout")
        end
    end
    if not coop.map then
        coop.map = coop_build_builtin_map()
        coop.map_src = "default layout (" .. #coop.map .. " actions)"
    end
    -- v0.9.4: optional overrides in data/DPC_coop_layout.json, read at each co-op start (no script reset needed):
    -- { "map": [ { "pad": "RLeft", "flags": ["0x4000"], "name": "Grab" }, { "pad": "RUp", "act": ["Dash"] } ] }
    -- An entry replaces the built-in non-skill entries for the same button; skill entries (L1/L2 + face) stay.
    -- v0.9.124: off unless coop_layout_file is switched on. The file that shipped until 0.9.123 held three entries
    -- measured on the tester's remapped controller (Grab on Square, Dash on Triangle); with the map now read from
    -- the game it would put those on the wrong buttons for everybody else.
    local okl, lay = false, nil
    if cfg.coop_layout_file then okl, lay = pcall(json.load_file, "DPC_coop_layout.json") end
    if okl and type(lay) == "table" and type(lay.map) == "table" then
        local pv, added = coop_pad_values(), 0
        local is_skill = {}
        for _, sk in ipairs(COOP_SKILLS) do is_skill[sk] = true end
        for _, le in ipairs(lay.map) do
            local pad = type(le.pad) == "number" and le.pad or pv[le.pad] or tonumber(tostring(le.pad or ""))
            if pad and pad ~= 0 then
                local keep = {}
                for _, e in ipairs(coop.map) do
                    if e.pad ~= pad or is_skill[e.name] then keep[#keep + 1] = e end
                end
                coop.map = keep
                for _, f in ipairs(le.flags or {}) do
                    local fv = type(f) == "number" and f or tonumber(tostring(f))
                    if fv and fv ~= 0 then coop.map[#coop.map + 1] = { flag = fv, name = le.name or "custom", pad = pad }; added = added + 1 end
                end
                for _, an in ipairs(le.act or {}) do
                    if S.ACTION_FLAGS[an] then coop.map[#coop.map + 1] = { flag = S.ACTION_FLAGS[an], name = an, pad = pad }; added = added + 1 end
                end
            end
        end
        coop.map_src = coop.map_src .. " + layout file (" .. added .. ")"
    end
    local parts = {}
    for _, e in ipairs(coop.map) do parts[#parts + 1] = string.format("%s=%X", e.name, e.pad) end
    table.sort(parts)
    log_msg("Co-op pad map " .. coop.map_src .. ": " .. table.concat(parts, " "))
end

-- Player 2's input: pad buttons -> action flags, pad left stick (dead zone). Called on the game thread.
coop.pad_input = function()
    coop_ensure_map()
    local btn = S.pad_buttons or 0
    coop.last_btn = btn
    local pv = coop_pad_values()
    if cfg.coop_aim and cfg.coop_auto_target then btn = R.ta_p2_input(btn, pv) end
    -- v0.9.124: the shift buttons come from the game's assignment (Shift1; and Shift1OnlySpecificJob, the vocation
    -- action button, which the game treats as a skill shift for the bow vocations only: see the 0.9.87 note)
    local l1, l2 = pv[COOP_SHIFT_L1] or 0x100, pv[COOP_SHIFT_L2] or 0x400
    local bow = state.pawn_job == 2 or state.pawn_job == 8
    local shift1_held = R.bind_held("Shift1", btn, l1)
    local shift2_held = R.bind_held("Shift2", btn, l1)
    local shift_held = shift1_held or (bow and R.bind_held("Shift1OnlySpecificJob", btn, l2))
    -- v0.9.13 chord skills: shift + two face buttons together fire Skill5 / Skill6 (the tester's layout). Both
    -- buttons rarely land on the same frame, so a face button that belongs to a chord waits coop_chord_window
    -- for its partner before it counts as its own skill. A chord stays latched until both buttons are up, so
    -- letting go of one doesn't fire the single skill.
    local chord_on, pulsing = 0, false
    -- v0.9.22: with a skill in slot 5 or 6 the game moves skills 3 and 4 to L1 + R1 / R2 (the tester's HUD
    -- screenshot, 2026-11-15) and Circle / Cross keep sheathe / jump (they are the chord partners).
    local six = state.pawn_skills and ((state.pawn_skills[5] or 0) ~= 0 or (state.pawn_skills[6] or 0) ~= 0)
    do
        local now = os.clock()
        coop.face_t, coop.face_sh, coop.face_out = coop.face_t or {}, coop.face_sh or {}, coop.face_out or {}
        local sq, cr, ci, tri = pv.RLeft or 0x40, pv.RDown or 0x20, pv.RRight or 0x80, pv.RUp or 0x10
        local faces = { sq, cr, ci, tri }
        -- v0.9.124: "face" buttons = every single button that is (part of) a skill binding in the game's list
        if R.bind and next(R.bind.pad) then
            local seen, fl = {}, {}
            for sl = 1, 6 do
                local m = R.bind.pad[sl] or 0
                for bit = 0, 15 do
                    local one = 1 << bit
                    if (m & one) ~= 0 and not seen[one] then seen[one] = true; fl[#fl + 1] = one end
                end
            end
            if #fl > 0 then faces = fl end
        end
        -- v0.9.76 (co-op Thief, 2026-11-16: "L1 skills do not seem to work"; recording: L1 held, a quick Square
        -- tap gave no Skill flag at all, and Grab for a few frames when L1 came up first):
        --  * the wait for a chord partner (coop_chord_window, 0.16 s) ate every tap shorter than that. It now
        --    only applies when a chord is possible (a skill in slot 5 or 6), and a button released during the
        --    wait still fires its skill (a 0.1 s pulse).
        --  * a face button pressed under L1 never turns into its own action (grab, jump, ...) when L1 is let
        --    go first; it is ignored until released.
        for _, b in ipairs(faces) do
            if (btn & b) ~= 0 then
                if not coop.face_t[b] then coop.face_t[b], coop.face_sh[b], coop.face_out[b] = now, shift_held, false end
            else
                if coop.face_t[b] and coop.face_sh[b] and not coop.face_out[b] then
                    coop.pulse_pad, coop.pulse_until = b, now + 0.10
                    coop.pulses = (coop.pulses or 0) + 1
                end
                coop.face_t[b], coop.face_sh[b], coop.face_out[b] = nil, nil, nil
            end
        end
        local bp = R.bind and R.bind.pad or {}
        local chords = { { bp[6] or (sq | cr), "Skill6" }, { bp[5] or (tri | ci), "Skill5" } } -- 0.9.100: from the game's assignment
        local latch = coop.chord_latch
        if latch and (btn & latch.pads) == 0 then coop.chord_latch, latch = nil, nil end
        if cfg.coop_chord_skills and six and not latch and shift_held then
            for _, c in ipairs(chords) do
                if (btn & c[1]) == c[1] and S.ACTION_FLAGS[c[2]] then
                    latch = { pads = c[1], flag = S.ACTION_FLAGS[c[2]], name = c[2] }
                    coop.chord_latch = latch
                    coop.chords = (coop.chords or 0) + 1
                    coop_event("chord " .. c[2])
                    break
                end
            end
        end
        if latch then
            for _, b in ipairs(faces) do if (latch.pads & b) ~= 0 then coop.face_out[b] = true end end
            btn = btn & ~latch.pads
            if shift_held then chord_on = latch.flag | (S.ACTION_FLAGS.Shift1 or 0) | (S.ACTION_FLAGS.Shift2 or 0) end
        elseif shift_held and cfg.coop_chord_skills and six then
            -- hold back a lone chord button for a moment
            for _, b in ipairs(faces) do
                if (btn & b) ~= 0 and now - (coop.face_t[b] or now) < (cfg.coop_chord_window or 0.09) then
                    btn = btn & ~b
                end
            end
        end
        for _, b in ipairs(faces) do
            if (btn & b) ~= 0 and coop.face_sh[b] then
                if shift_held then coop.face_out[b] = true else btn = btn & ~b end
            end
        end
        if coop.pulse_until and now < coop.pulse_until then
            btn = btn | coop.pulse_pad
            shift_held = true
            pulsing = true
        end
    end
    local is_skill = {}
    for _, sk in ipairs(COOP_SKILLS) do is_skill[sk] = true end
    local on, skill_pads = 0, 0
    for _, e in ipairs(coop.map) do
        local epad = e.pad
        local sn = tonumber(tostring(e.name):match("^Skill(%d)$") or "")
        local gb = sn and R.bind and R.bind.pad[sn]
        if gb then epad = gb end -- 0.9.100: the game's own button for this slot
        -- (0.9.124: the old "skills 3 / 4 move to R1 / R2 with a chord slot in use" rule is gone; that was the
        -- user's remap, not something the game does)
        if epad ~= 0 and (btn & epad) == epad then
            if is_skill[e.name] then
                if shift_held then on = on | e.flag; skill_pads = skill_pads | epad end
            elseif e.pre == 15 then
                if shift2_held then on = on | e.flag; skill_pads = skill_pads | epad end
            elseif e.pre then
                if shift1_held then on = on | e.flag; skill_pads = skill_pads | epad end
            else
                on = on | e.flag
            end
        end
    end
    if skill_pads ~= 0 then
        -- shift + face button is a skill only, not also that button's own action (jump, sheathe, ...)
        for _, e in ipairs(coop.map) do
            if not is_skill[e.name] and not e.pre and (e.pad & skill_pads) ~= 0 then on = on & ~e.flag end
        end
    end
    if pulsing and skill_pads ~= 0 then on = on | (S.ACTION_FLAGS.Shift1 or 0) | (S.ACTION_FLAGS.Shift2 or 0) end -- L1 may already be up
    on = on | chord_on
    coop.last_flags = on
    coop.last_stick = { S.pad_stick_x or 0.0, S.pad_stick_y or 0.0 }
    local ax, ay = S.pad_stick_x or 0.0, S.pad_stick_y or 0.0
    local mag = math.sqrt(ax * ax + ay * ay)
    if mag < (cfg.coop_pad_deadzone or 0.15) then ax, ay, mag = 0.0, 0.0, 0.0 end
    if mag > 1.0 then ax, ay, mag = ax / mag, ay / mag, 1.0 end
    return on, ax + 0.0, ay + 0.0, mag + 0.0
end

-- 0.9.172-dev20 co-op camera turn (two controllers, co-op aiming on). cfg.coop_cam_turn:
--   "p1"     player 1's right stick turns the camera as before; while he has a kept target, his flicks switch it
--            and, with his stick at rest, the camera turns toward him and that target
--   "shared" a slow push on either right stick turns the camera (both add up); quick flicks only switch targets
--   "auto"   right sticks only target; the camera turns by itself toward the players' targets, or the way the
--            group is moving
-- Written into the Arisen's AxisR (what the game's camera reads) in his processor's pre-hook.
R.cct = { g1 = {}, g2 = {}, sign = 1, wrote = false }
R.cam_yaw = function()
    local cm = sdk.get_managed_singleton("app.CharacterManager")
    local cf = cm and field(cm, "<CameraFront>k__BackingField")
    if cf and (cf.x ~= 0 or cf.z ~= 0) then return math.atan(cf.x, cf.z) end
    return nil
end
R.cam_steer = function(want, now)
    local c = R.cct
    local yaw = R.cam_yaw()
    if not (yaw and want) then return 0.0 end
    local err = brain_angdiff(want, yaw)
    -- which way a positive stick turns depends on the player's camera options: learn it from the result
    if c.st_t and now - c.st_t > 0.5 then
        if math.abs(err) > math.abs(c.st_err) + math.rad(5) and math.abs(c.st_x) > 0.2 then
            c.sign = -c.sign
            c.flips = (c.flips or 0) + 1
        end
        c.st_t = nil
    end
    if math.abs(err) < math.rad(cfg.coop_cam_deadband or 8.0) then return 0.0 end
    local x = math.max(-1.0, math.min(1.0, err / math.rad(45.0))) * (cfg.coop_cam_auto_speed or 0.5) * c.sign
    if not c.st_t then c.st_t, c.st_err, c.st_x = now, err, x end
    return x
end
-- dev38: while a controller turns the camera with player 1 on keyboard and mouse, the rotating cameras read stick
-- speed, not mouse speed (app.RotateCameraControllerBase / Root.get_IsMouseInputEnv answers false that frame)
R.cam_env_hooked = false
R.cam_env_hook = function()
    if R.cam_env_hooked then return end
    R.cam_env_hooked = true
    for _, tn in ipairs({ "app.RotateCameraControllerBase", "app.RotateCameraControllerRoot" }) do
        local td = sdk.find_type_definition(tn)
        local m = td and td:get_method("get_IsMouseInputEnv")
        if m then
            sdk.hook(m, function() end, function(r)
                local c = R.cct
                if c and c.pad_now and os.clock() - c.pad_now < 0.1 and R.tp_kb() then
                    R.cam_env_n = (R.cam_env_n or 0) + 1
                    return sdk.to_ptr(0)
                end
                return r
            end)
        end
    end
end
R.cam_turn = function(inp)
    local c = R.cct
    c.wrote = false
    local mode = cfg.coop_cam_turn or "p1"
    local now = os.clock()
    local p1 = R.tp_p1()
    local rx1, ry1 = p1.rx or 0.0, p1.ry or 0.0
    local rx2, ry2 = S.pad_stick_rx or 0.0, S.pad_stick_ry or 0.0
    -- 0.9.172-dev36: player 1 on keyboard and mouse: a frame where the mouse moved keeps the game's own camera input
    -- dev37 (the tester: "the camera seems very very rough" with player 1 on keyboard and mouse): the game smooths the
    -- mouse over the frames after it moves, and those frames were overwritten with the controllers' (zero) share.
    -- Now the game's own camera input is left alone unless some controller's right stick is actually pushed.
    if R.tp_kb() and mode ~= "p1" then
        -- dev44: the get_IsMouseInputEnv hook (dev38) is no longer installed. It never answered once (counter 0), and
        -- the camera getters may run on the game's worker threads, where a Lua hook is a crash risk; the game crashed
        -- in a worker thread (light / haze update, c0000005) at [time] with it installed. The controller-mode switch
        -- (dev39) is what made the sticks work.
        local pushed = math.sqrt(rx2 * rx2 + ry2 * ry2) >= 0.3
        for _, sl in pairs(R.np and R.np.slots or {}) do
            local q = sl.active and sl.pad_cam
            if q and math.sqrt((q.rx or 0) ^ 2 + (q.ry or 0) ^ 2) >= 0.3 then pushed = true end
        end
        c.kb_frames = (c.kb_frames or 0) + 1
        -- dev42 diagnostics (the tester: "P2 camera sometimes doesn't work ... when I do P3 camera, afterwards P2 camera
        -- will work"): the last 60 frames where player 2's stick was pushed, for a bridge read
        -- dev44: 60 frames was half a second ("too short for me to get back here"): now 10 samples a second over
        -- the last 60 s, every player's stick and gate
        if now >= (c.ring_next or 0) then
            local parts = {}
            local function add(n, x, y, g)
                if math.sqrt(x * x + y * y) >= 0.3 then
                    parts[#parts + 1] = string.format("P%d %.2f fl=%s", n, x, tostring(g and g.fl))
                end
            end
            add(2, rx2, ry2, c.g2)
            for n, sl in pairs(R.np and R.np.slots or {}) do
                local q = sl.pad_cam
                if q then add(n, q.rx or 0, q.ry or 0, c.gn and c.gn[n]) end
            end
            if #parts > 0 then
                c.ring_next = now + 0.1
                local hm, mv = nil, nil
                pcall(function() hm = sdk.get_managed_singleton("app.UserInputManager"):call("get_HIDInputMode") end)
                pcall(function() mv = inp:get_field("<IsMouseMovedInFrame>k__BackingField") end)
                local ring = c.p2ring or {}; c.p2ring = ring
                ring[#ring + 1] = { t = now, s = string.format("%.1f %s hid=%s mouse=%s wrote=%.2f", now, table.concat(parts, " "), tostring(hm), tostring(mv), c.last_x or 0) }
                while #ring > 0 and now - ring[1].t > 60.0 do table.remove(ring, 1) end
            end
        end
        if not pushed then
            -- 0.9.177: the controller mode set for a camera stick push (dev39) also turned player 1's button prompts
            -- into controller buttons. 0.4 s after the last push, with player 1 on the keyboard, back to keyboard / mouse.
            if c.hid_forced and now - (c.pad_now or 0) > 0.4 then
                c.hid_forced = nil
                if cfg.coop_kbm_glyphs and R.p1_on_kb and R.p1_on_kb() then
                    pcall(function()
                        local mgr = sdk.get_managed_singleton("app.UserInputManager")
                        if mgr and mgr:call("get_HIDInputMode") ~= 1 then mgr:call("set_HIDInputMode", 1) end
                    end)
                end
            end
            -- dev43, found with the bridge (player 4's gate stuck in "flick" while his stick was at rest): the gates
            -- only see a stick when R.cam_turn gets past this point, i.e. while some stick is pushed. A flick latches
            -- the gate until it sees the stick back at rest, and with nobody pushing it never did: that player's
            -- next slow push read as the same flick and was ignored, until someone else's push let the gate see the
            -- rest ("when I do P3 camera, afterwards P2 camera will work"). Every gate now sees every frame.
            R.cam_gate(c.g1, rx1, ry1, now)
            R.cam_gate(c.g2, rx2, ry2, now)
            c.gn = c.gn or {}
            for n, sl in pairs(R.np and R.np.slots or {}) do
                local q = sl.pad_cam
                if q then c.gn[n] = c.gn[n] or {}; R.cam_gate(c.gn[n], q.rx or 0.0, q.ry or 0.0, now) end
            end
            c.wrote = true
            return
        end
        c.kb_pushed = (c.kb_pushed or 0) + 1
        -- dev38 (the tester: "slow right stick pushes do nothing to the camera when M+KB is P1"): the game is in mouse mode,
        -- so the camera turned the stick's AxisR at the mouse's rate (next to nothing). Say it is a stick frame.
        -- dev39 ("Camera does not move at all with any right stick movement in this m+kb mode"; no frame reached the
        -- hook below): a pushed controller stick now wins over the mouse that frame, and the game is put in controller
        -- mode (UserInputManager.HIDInputMode 0, what it does itself when a controller is touched; the mouse puts it
        -- back). At most every 0.25 s.
        c.pad_now = now
        pcall(function()
            inp:set_field("<IsPadAxisRMovedInFrame>k__BackingField", true)
            inp:set_field("<IsMouseMovedInFrame>k__BackingField", false)
        end)
        if now >= (c.hid_next or 0) then
            c.hid_next = now + 0.25
            pcall(function()
                local mgr = sdk.get_managed_singleton("app.UserInputManager")
                if mgr and mgr:call("get_HIDInputMode") == 1 then
                    mgr:call("set_HIDInputMode", 0)
                    c.hid_sets = (c.hid_sets or 0) + 1
                    c.hid_forced = true -- 0.9.177: put back to keyboard / mouse once the stick is let go (below)
                end
            end)
        end
    end
    -- 0.9.172-dev36: each player's stick can be left out (cfg.coop_cam_from), and players 3+ turn it too
    local from = cfg.coop_cam_from or {}
    if from.p1 == false then rx1, ry1 = 0.0, 0.0 end
    if from.p2 == false then rx2, ry2 = 0.0, 0.0 end
    local function more(x, y)
        c.gn = c.gn or {}
        for n, sl in pairs(R.np and R.np.slots or {}) do
            local q = sl.pad_cam
            if sl.active and q and from["p" .. n] ~= false then
                c.gn[n] = c.gn[n] or {}
                local a, b = R.cam_gate(c.gn[n], q.rx or 0.0, q.ry or 0.0, now)
                x, y = x + a, y + b
                -- dev40 diagnostics: per player, the largest raw right stick seen and how often it reached the camera
                local d = c.np_dbg or {}; c.np_dbg = d
                local e = d[n] or { raw = 0, used = 0, seen = 0 }; d[n] = e
                local m = math.max(math.abs(q.rx or 0), math.abs(q.ry or 0))
                if m > e.raw then e.raw = m end
                if m >= 0.3 then e.seen = e.seen + 1 end
                if a ~= 0.0 or b ~= 0.0 then e.used = e.used + 1 end
            end
        end
        return x, y
    end
    local ax, _, az = brain_pos(state.arisen_chara)
    local function toward(e)
        local ex, _, ez = brain_pos(e)
        if not (ax and ex) then return nil end
        return math.atan(ex - ax, ez - az)
    end
    local x, y
    if mode == "shared" then
        local x1, y1 = R.cam_gate(c.g1, rx1, ry1, now)
        local x2, y2 = R.cam_gate(c.g2, rx2, ry2, now)
        local sx, sy = more(x1 + x2, y1 + y2)
        x, y = math.max(-1.0, math.min(1.0, sx)), math.max(-1.0, math.min(1.0, sy))
    elseif mode == "auto" then
        local want
        local t1, t2 = R.ta.p1, coop.tgt
        local px, _, pz = brain_pos(state.pawn_chara)
        if t1 or t2 then
            local sx, sz, n = 0.0, 0.0, 0
            for _, e in ipairs({ t1, t2 }) do
                local ex, _, ez = brain_pos(e)
                if ex then sx, sz, n = sx + ex, sz + ez, n + 1 end
            end
            local gx, gz = ax, az
            if px and ax then gx, gz = (ax + px) * 0.5, (az + pz) * 0.5 end
            if n > 0 and gx then want = math.atan(sx / n - gx, sz / n - gz) end
        else
            -- the way the group is moving (both characters' displacement over ~0.5 s)
            if ax then
                c.hist = c.hist or {}
                local h = c.hist
                h[#h + 1] = { t = now, ax = ax, az = az, px = px or ax, pz = pz or az }
                while #h > 2 and now - h[1].t > 0.5 do table.remove(h, 1) end
                local o = h[1]
                local dx = ((ax - o.ax) + ((px or ax) - o.px)) * 0.5
                local dz = ((az - o.az) + ((pz or az) - o.pz)) * 0.5
                if dx * dx + dz * dz > 0.5 ^ 2 then want = math.atan(dx, dz) end
            end
        end
        -- dev22: a slow push on either stick still turns the camera ("not enough camera control"); the camera's own
        -- turning waits 1.5 s after the last push
        local x1, y1 = R.cam_gate(c.g1, rx1, ry1, now)
        local x2, y2 = R.cam_gate(c.g2, rx2, ry2, now)
        local sx, sy = more(x1 + x2, y1 + y2)
        if sx ~= 0.0 or sy ~= 0.0 then
            c.push_t = now
            x, y = math.max(-1.0, math.min(1.0, sx)), math.max(-1.0, math.min(1.0, sy))
        else
            if want == nil or now - (c.push_t or -10) < 1.5 then
                inp:set_field("<AxisR>k__BackingField", Vector2f.new(0.0, 0.0))
                c.wrote = true
                c.st_t = nil
                return
            end
            x, y = R.cam_steer(want, now), 0.0
        end
    else -- "p1"
        if not R.ta.p1 then return end -- as before (the old block below handles player 2's stick)
        x, y = R.cam_gate(c.g1, rx1, ry1, now)
        if cfg.coop_cam_p1_steer and x == 0.0 and y == 0.0 and math.sqrt(rx1 * rx1 + ry1 * ry1) < 0.3 then
            x = R.cam_steer(toward(R.ta.p1), now)
        end
    end
    inp:set_field("<AxisR>k__BackingField", Vector2f.new(x + 0.0, y + 0.0))
    c.wrote = true
    c.n = (c.n or 0) + 1
    c.last_x, c.last_y = x, y -- dev42 diagnostics
end

-- 0.9.178-dev8 (test PC: "P2 as pawn still cannot move the camera in this shared screen mode"). Both players on pawns
-- (R.cp "pawns" with R.s2): coop.active is false, so coop.filter / R.cam_turn never run, and the camera reads the
-- Arisen processor's AxisR (the game's active controller, player 1's). Called from brain_inject (read live: the brain
-- runs there, ~80 injections a second). Player 2's stick is read from his own controller (R.tp_p2(); dev5 used
-- R.s2.pad, which the second pawn's tick has already taken by then, so it never turned). Player 1's stick is already in
-- AxisR; player 2's is added while pushed.
R.cp_cam_add = function(inp)
    if not (R.cp and R.cp.on and R.cp.mode == "pawns" and not R.cp.ar2 and not R.cp.kb) then return end
    if coop.active or not (R.s2 and R.s2.active) or not cfg.coop_two_pads or (cfg.coop_cam_turn or "p1") == "p1" then return end
    if R.views_on and R.views_on() then return end -- split screen: every player has a view of their own
    if not (R.tp and R.tp.p1 and R.tp.p2) then return end
    local v2 = R.tp_p2()
    local x2, y2 = v2.rx or 0.0, v2.ry or 0.0
    if math.sqrt(x2 * x2 + y2 * y2) < 0.2 then return end
    local v1 = R.tp_p1()
    local x = math.max(-1.0, math.min(1.0, (v1.rx or 0.0) + x2))
    local y = math.max(-1.0, math.min(1.0, (v1.ry or 0.0) + y2))
    inp:set_field("<AxisR>k__BackingField", Vector2f.new(x + 0.0, y + 0.0))
    R.cp_cam_n = (R.cp_cam_n or 0) + 1
end

-- Player 1's Arisen, in his processor's pre-hook: keyboard stick only, and no pad-derived buttons.
coop.filter = function()
    local inp = state.arisen_input
    if not inp then return end
    if R.robot_p2 and R.robot_p2() then return end -- dev14: robot is player 2; the controller is player 1's
    -- camera: the camera reads this input's AxisR after this point. v0.9.2: KeyboardMouseAxisR is only filled on
    -- some frames, so copying it (v0.9.0) froze the camera; now AxisR is only cleared on frames where player 2's
    -- right stick is pushed and the mouse did not move.
    local two = R.tp_on()
    if R.views_on() then
        -- dev38 (first split-screen test: "right stick turned both cameras"): each player has a view. The main
        -- camera is player 1's: his controller's right stick if he has one, else the mouse; never player 2's.
        R.views_cam_n = (R.views_cam_n or 0) + 1
        pcall(function()
            if two and not R.tp_kb() then
                local p1 = R.tp_p1()
                inp:set_field("<AxisR>k__BackingField", Vector2f.new(p1.rx + 0.0, p1.ry + 0.0))
            elseif not inp:get_field("<IsMouseMovedInFrame>k__BackingField") then
                inp:set_field("<AxisR>k__BackingField", Vector2f.new(0.0, 0.0))
            end
        end)
    elseif two and cfg.coop_aim and pcall(R.cam_turn, inp) and R.cct.wrote then
        -- 0.9.172-dev20: the co-op camera turn mode wrote AxisR this frame
    elseif R.kb_wait and R.kb_wait() then
        -- dev44: waiting for player 2 with player 1 on keyboard: controllers don't turn the camera yet
        local any = false
        for _, d in ipairs(R.tp_devs()) do
            local v = R.tp_read(d)
            if math.abs(v.rx) + math.abs(v.ry) > 0.25 then any = true break end
        end
        if any then
            pcall(function()
                if not inp:get_field("<IsMouseMovedInFrame>k__BackingField") then inp:set_field("<AxisR>k__BackingField", Vector2f.new(0.0, 0.0)) end
            end)
        end
    elseif two and R.tp_kb() then
        -- 0.9.172-dev36: player 1 on keyboard and mouse: only clear the controllers' share when the mouse didn't move
        if math.abs(S.pad_stick_rx) + math.abs(S.pad_stick_ry) > 0.25 then
            pcall(function()
                if not inp:get_field("<IsMouseMovedInFrame>k__BackingField") then inp:set_field("<AxisR>k__BackingField", Vector2f.new(0.0, 0.0)) end
            end)
        end
    elseif two and math.abs(S.pad_stick_rx) + math.abs(S.pad_stick_ry) > 0.25 and (cfg.coop_two_pads_cam or 1) == 1 then
        -- v0.9.170 (dev): two controllers. The game's camera input mixes both right sticks; player 1's alone instead.
        local p1 = R.tp_p1()
        local okr = pcall(inp.set_field, inp, "<AxisR>k__BackingField", Vector2f.new(p1.rx + 0.0, p1.ry + 0.0))
        if okr then R.tp.cam_fixes = (R.tp.cam_fixes or 0) + 1 else cfg.coop_two_pads_cam = 2; coop_event("two controllers: camera write failed -> hold still") end
    elseif cfg.coop_block_p2_camera and math.abs(S.pad_stick_rx) + math.abs(S.pad_stick_ry) > 0.25 then
        local okr = pcall(function()
            if not inp:get_field("<IsMouseMovedInFrame>k__BackingField") then
                inp:set_field("<AxisR>k__BackingField", Vector2f.new(0.0, 0.0))
                coop.cam_fixes = (coop.cam_fixes or 0) + 1
            end
        end)
        if not okr then cfg.coop_block_p2_camera = false; coop_event("camera block write failed -> off") end
    end
    -- buttons: mask what player 2 is pressing (second layer behind the processButton pad zeroing)
    local mask = coop.last_flags or 0
    local on = inp:get_field("ButtonOnFlags") or 0
    -- v0.9.5: off by default. The mask also removed actions player 1 pressed himself: while player 2 held L2
    -- (guard = AimHold bit) the Arisen could not aim with the right mouse button. The processButton pad zeroing
    -- already keeps the controller off the Arisen.
    if mask ~= 0 and cfg.coop_mask_p2_flags then
        inp:set_field("ButtonOnFlags", on & ~mask)
        inp:set_field("ButtonTriggerFlags", (inp:get_field("ButtonTriggerFlags") or 0) & ~mask)
    end
    -- self-check: player 1 holding a mouse button or Space while the Arisen sees no buttons at all means the
    -- pad zeroing also ate the keyboard -> switch it off
    -- v0.9.46: this check switched the zeroing off for good on 2026-11-15 while the tester dragged sliders in the
    -- REFramework window (mouse held, the game sees no buttons), and player 2's L2 then aimed the Arisen's bow. Now it
    -- only runs in the first 20 s of a co-op session, never while the REFramework UI is open, and only switches the
    -- zeroing off for that session (the setting itself is not touched).
    if not two and cfg.coop_zero_pad_for_arisen and not coop.zero_off and os.clock() - (coop.t_start or 0) < 20.0 then
        local ui_open = false
        pcall(function() ui_open = reframework:is_drawing_ui() == true end)
        local p1_btn = not ui_open and (S.is_key_down_safe(0x01) or S.is_key_down_safe(0x02) or S.is_key_down_safe(0x20))
        if p1_btn and on == 0 then coop.kb_dead = coop.kb_dead + 1 else coop.kb_dead = 0 end
        if coop.kb_dead > 45 then
            coop.zero_off = true
            coop_event("pad zeroing also blocked player 1's keys -> off for this session")
            log_msg("Co-op: processButton pad zeroing blocked keyboard/mouse too; off for this co-op session")
        end
    end
    -- stick (v0.9.2): only acts on frames where player 2's left stick is pushed, since otherwise the game's own
    -- input is untouched. v0.9.0 copied KeyboardMouseAxisL every frame, but that field is zero on most frames, so
    -- the Arisen crawled at ~0.5 m/s. Now player 1's direction comes straight from WASD (zero -> stand still).
    -- 0.9.172-dev36: players 3+'s left sticks reach the Arisen through the game's merged controller too
    local other_l = S.pad_stick_x * S.pad_stick_x + S.pad_stick_y * S.pad_stick_y > 0.04
    local kbw = R.kb_wait and R.kb_wait()
    if kbw and not other_l then -- dev44: any controller's left stick, while waiting for player 2 with player 1 on keyboard
        for _, d in ipairs(R.tp_devs()) do
            local v = R.tp_read(d)
            if v.lx * v.lx + v.ly * v.ly > 0.04 then other_l = true break end
        end
    end
    if (two or kbw) and not other_l then
        for _, sl in pairs(R.np and R.np.slots or {}) do
            local q = sl.pad_cam -- dev41: sl.pad is consumed by R.s2_tick before this runs
            if q and (q.lx or 0) ^ 2 + (q.ly or 0) ^ 2 > 0.04 then other_l = true break end
        end
    end
    if (two or kbw) and other_l then
        -- v0.9.170 (dev): two controllers. Player 2's stick is pushed; give the Arisen player 1's stick (plus WASD).
        local p1 = R.tp_p1()
        local kx, ky = p1.lx or 0.0, p1.ly or 0.0
        if R.key_held("MoveForward", 0x57) then ky = ky + 1.0 end
        if R.key_held("MoveBackward", 0x53) then ky = ky - 1.0 end
        if R.key_held("MoveRightward", 0x44) then kx = kx + 1.0 end
        if R.key_held("MoveLeftward", 0x41) then kx = kx - 1.0 end
        local km = math.sqrt(kx * kx + ky * ky)
        if km < (cfg.coop_pad_deadzone or 0.15) then kx, ky, km = 0.0, 0.0, 0.0 end
        if km > 1.0 then kx, ky, km = kx / km, ky / km, 1.0 end
        local ok = pcall(function()
            inp:call("setAxisL(System.Single, System.Single)", kx + 0.0, ky + 0.0)
            inp:call("set_AxisMagnitudeL(System.Single)", km + 0.0)
        end)
        if ok then R.tp.stick_fixes = (R.tp.stick_fixes or 0) + 1 end
    elseif cfg.coop_block_p2_stick and S.pad_stick_x * S.pad_stick_x + S.pad_stick_y * S.pad_stick_y > 0.04 then
        local kx, ky = 0.0, 0.0
        -- v0.9.124: the keys the game has the four directions on (default W / S / D / A)
        if R.key_held("MoveForward", 0x57) then ky = ky + 1.0 end
        if R.key_held("MoveBackward", 0x53) then ky = ky - 1.0 end
        if R.key_held("MoveRightward", 0x44) then kx = kx + 1.0 end
        if R.key_held("MoveLeftward", 0x41) then kx = kx - 1.0 end
        local km = math.sqrt(kx * kx + ky * ky)
        if km > 0 then kx, ky, km = kx / km, ky / km, 1.0 end
        local ok = pcall(function()
            inp:call("setAxisL(System.Single, System.Single)", kx + 0.0, ky + 0.0)
            inp:call("set_AxisMagnitudeL(System.Single)", km + 0.0)
        end)
        if ok then coop.stick_fixes = (coop.stick_fixes or 0) + 1
        else cfg.coop_block_p2_stick = false; coop_event("stick block write failed -> off") end
    end
end

-- v0.9.152 two faults, found when the camera did not keep player 2's Archer in frame:
-- (1) pawn_idx was the pawn co-op STARTED with. Switching player 2 to another pawn (the select key in co-op) changed
--     the name in this file but not the index, so Camera Distance went on framing the first pawn. The index is now
--     the pawn being played.
-- (2) the file was written with R.dump, which only writes in developer mode. A released copy never wrote it, so
--     Camera Distance never learned that co-op was on. It is now always written, but outside developer mode only
--     when co-op starts, stops or changes pawn (three short fields).
local function coop_write_status()
    local idx = (coop.active and state.active and state.pawn_idx) or coop.pawn_idx
    local name = state.active and state.pawn_name or ""
    -- v0.9.171: both players on pawns: Camera Distance frames player 1's pawn (the camera follows it, anchor_idx)
    -- and player 2's (pawn_idx); -1 = the Arisen is the anchor, as before
    local on, anchor = coop.active, -1
    if R.cp and R.cp.on and R.cp.mode == "pawns" and R.s2 and R.s2.active and state.active then
        on, idx, name, anchor = true, R.s2.idx, tostring(R.s2.name or ""), state.pawn_idx
    end
    -- 0.9.171: player 2 on the Arisen: the camera's pawn is player 1's, the other player is the Arisen (pawn_idx -1)
    if R.cp and R.cp.on and R.cp.ar2 and state.active then
        on, idx, name, anchor = true, -1, "the Arisen", state.pawn_idx
    end
    -- 0.9.172: players 3+ (pawn indices) for Camera Distance's framing
    local extra, extra_names, extra_n = {}, {}, {}
    if R.np_charas then for _, e in ipairs(R.np_charas()) do extra[#extra + 1] = e.idx; extra_names[#extra_names + 1] = tostring(e.name or ""); extra_n[#extra_n + 1] = e.player end end
    if #extra > 0 and R.cp and R.cp.on then on = true end
    -- 0.9.173-dev1: each player's colour (0xAABBGGRR) for Camera Distance's off-screen markers
    local colors, ckey = {}, {}
    for n = 1, 6 do colors["p" .. n] = R.player_abgr(n); ckey[n] = R.player_color(n) end
    if R.dev then
        R.dump("DPC_coop.json", {
            active = on, pawn_idx = idx, pawn_name = name, anchor_idx = anchor, players = extra, player_names = extra_names, player_nums = extra_n,
            colors = colors,
            np = R.np and { n = R.np_count(), log = R.np.log, err = R.np.err } or nil,
            cp = R.cp and { on = R.cp.on, mode = R.cp.mode, kb = R.cp.kb, p1 = R.cp.char[1], p2 = R.cp.char[2], arisen_side = R.cp.arisen_side, applies = R.cp.applies, log = R.cp.log } or nil,
            s2 = R.s2 and { active = R.s2.active, idx = R.s2.idx, frames = R.s2.frames, errors = R.s2.errors, err = R.s2.err, in_err = R.s2.in_err, on = R.s2.last_on, mag = R.s2.last_mag, tgt_sets = R.s2.tgt_sets } or nil,
            target = coop.tgt_name, target_dist = coop.tgt_dist, target_sets = coop.tgt_sets or 0,
            chords = coop.chords or 0, glyph_skips = coop.glyph_skips or 0,
            t = os.clock(), version = VERSION,
        })
        return
    end
    local key = tostring(on) .. ":" .. tostring(idx) .. ":" .. tostring(anchor) .. ":" .. table.concat(extra, ",") .. ":" .. table.concat(ckey, ",")
    if key == coop.status_key then return end
    coop.status_key = key
    pcall(json.dump_file, "DPC_coop.json", { active = on, pawn_idx = idx, pawn_name = name, anchor_idx = anchor, players = extra, player_names = extra_names, player_nums = extra_n, colors = colors, version = VERSION })
end

local function coop_apply_overrides()
    if coop.saved then return end
    coop.saved = {}
    for k, v in pairs(COOP_OVERRIDES) do coop.saved[k] = cfg[k]; cfg[k] = v end
    S.coop_saved_for_cfg = coop.saved
end

local function coop_restore_overrides()
    if not coop.saved then return end
    for k, v in pairs(coop.saved) do cfg[k] = v end
    coop.saved = nil
    S.coop_saved_for_cfg = nil
end

-- called from release_possession (unless it is a pawn switch inside co-op)
coop.on_release = function(reason)
    pcall(function() local d = R.rb_dev(); if d and R.rb.power > 0 then R.rb_set(d, 0.0) end; R.rb.power = 0 end)
    local c = R.cr
    if cfg.coop_auto_resume and not R.CR_USER[tostring(reason)] then
        c.want, c.name, c.idx, c.reason = true, state.pawn_name, state.pawn_idx or coop.pawn_idx, tostring(reason)
        c.arr = R.cr_snapshot and R.cr_snapshot() or nil -- dev10: who had which character, players 3+ too
        c.p1, c.p2 = R.tp and R.tp.p1, R.tp and R.tp.p2
        -- dev11 (test PC: after a Ferrystone with player 2 on the Arisen, the two controllers came back swapped): with
        -- player 2 on the Arisen, R.tp.p1 is the Arisen side's controller (player 2's). The classic restart gives player
        -- 1 the Arisen, so it needs each person's own controller (R.cp_dev), not the sides'.
        if R.cp and R.cp.on and R.cp_dev then c.p1, c.p2 = R.cp_dev(1), R.cp_dev(2) end
        c.ok_since, c.tries, c.next, c.noted = nil, 0, os.clock() + 1.0, false
        c.down = tostring(reason):find("downed", 1, true) and state.pawn_chara or nil
    else
        c.want, c.down = false, nil
        -- dev47 (coop-start-1 step 6): ended by a player, so the controller roles end too. They lived on after
        -- co-op (R.tp_tick only runs during co-op), and the next Ctrl + F6 took the old pair at once instead of
        -- waiting for L3 + R3. The auto-resume above keeps its own copy (c.p1 / c.p2).
        if R.tp_reset then
            R.tp_reset()
            R.tp.keep, R.tp.restored, R.tp.snap = nil, true, nil
            pcall(json.dump_file, "DPC_two_pads.json", {})
        end
    end
    -- dev50 (the tester: player 1 solo on a controller, a friend's L3 + R3 "is triggering as Player 1 is M and KB"): the
    -- Ctrl + F6 start flag was only cleared in R.tp_tick, which doesn't run once co-op is off, so after one
    -- keyboard start every later L3 + R3 join gave player 1 the keyboard. It ends with the session now.
    if R.tp then R.tp.start_kb, R.tp.start_t, R.tp.start_pad = nil, nil, nil end
    coop.active = false
    coop_restore_overrides()
    coop_event("co-op ended (" .. tostring(reason) .. ")")
    if R.cp and R.cp.on and not R.cp.busy then pcall(R.cp_end, reason) end -- v0.9.171 (not while rearranging players)
    coop_write_status()
end

-- v0.9.13: the HUD switches its button prompts to the pad the moment player 2 touches the controller
-- (app.UserInputManager.switchingGamePadKeyboardMouse sets HIDInputMode: GamePad 0 / KeyboardMouse 1).
-- In co-op player 1 owns the HUD, so skip that switch and keep it on keyboard/mouse.
-- 0.9.177 (the tester: with the Arisen on keyboard and mouse and player 2 on an Xbox pad, the Arisen's gather prompt
-- turned into Circle when player 2 pressed anything): the guard was skipped whenever two-controller co-op was on,
-- even with player 1 on the keyboard. It now asks who player 1 is: on the keyboard (one-controller co-op, or two-
-- controller co-op with player 1's slot on the keyboard), the prompts stay keyboard / mouse.
R.p1_on_kb = function()
    if not cfg.coop_two_pads then return true end
    -- dev15 regression (the tester: "now everything is controlling the Arisen"): with two-controller co-op on and the
    -- controllers not paired yet (after a script reset), "nobody" was taken for the keyboard and the game was held
    -- in keyboard / mouse mode, which the unpaired routing does not expect. Only an explicit keyboard slot counts.
    local p1 = R.tp and R.tp.p1
    return p1 ~= nil and p1 == R.KB_ADDR
end
local glyph_hooked = false
local function coop_install_glyph_hook()
    if glyph_hooked then return end
    glyph_hooked = true
    local td = sdk.find_type_definition("app.UserInputManager")
    local m = td and td:get_method("switchingGamePadKeyboardMouse")
    if not m then coop_event("glyph hook: method not found"); return end
    local ok, err = pcall(sdk.hook, m, function(args)
        if not ((coop.active or (R.cp and R.cp.on)) and cfg.coop_kbm_glyphs) or not R.p1_on_kb() then return end -- v0.9.171: both on pawns with one controller too; 0.9.177: any co-op with player 1 on the keyboard
        local okm = pcall(function()
            local mgr = sdk.to_managed_object(args[2])
            if mgr and mgr:call("get_HIDInputMode") ~= 1 then mgr:call("set_HIDInputMode", 1) end
        end)
        if not okm then return end
        coop.glyph_skips = (coop.glyph_skips or 0) + 1
        return sdk.PreHookResult.SKIP_ORIGINAL
    end, nil)
    if not ok then dev_error("glyph hook", err) end
end

local function coop_force_kbm_glyphs()
    if not cfg.coop_kbm_glyphs or not R.p1_on_kb() then return end -- v0.9.170 / 0.9.177: only while player 1 is on the keyboard
    pcall(function()
        local mgr = sdk.get_managed_singleton("app.UserInputManager")
        if mgr and mgr:call("get_HIDInputMode") ~= 1 then
            mgr:call("set_HIDInputMode", 1)
            coop_event("HUD prompts switched back to keyboard/mouse")
        end
    end)
end

local function coop_start(idx)
    do
        local it = R.chara_of_idx(idx or cfg.selected_pawn_idx or 0)
        if it and R.unlean_defer({ it }, function() coop_start(idx) end, "Co-op start") then return false end
    end
    if state.active then release_possession("starting co-op") end
    ensure_enums()
    coop_apply_overrides()
    coop.active, coop.pawn_idx = true, idx or cfg.selected_pawn_idx or 0
    coop.map, coop.prev_on, coop.kb_dead, coop.axis_dead, coop.err = nil, 0, 0, 0, nil
    coop.zero_off, coop.t_start = false, os.clock()
    R.ta.pin, R.ta.req, R.ta.r3_t = nil, nil, nil
    coop.ar_input_addr = 0
    if cfg.coop_start_bring then -- dev7 (the tester): start player 2 right next to player 1's character
        pcall(function()
            local ar = quick_arisen()
            local apos = ar and ar:call("get_Transform"):call("get_Position")
            if not apos then return end
            for _, e in ipairs(get_party()) do
                if e.idx == coop.pawn_idx and e.chara then
                    local p = e.chara:call("get_Transform"):call("get_Position")
                    local dx, dz = p.x - apos.x, p.z - apos.z
                    if dx * dx + dz * dz > 36 then
                        local fwd = ar:call("get_Transform"):call("get_AxisZ") -- (the Arisen's right side: across his facing)
                        local rx, rz = 1.8, 0.0
                        if fwd then
                            local l = math.sqrt(fwd.x * fwd.x + fwd.z * fwd.z)
                            if l > 0.01 then rx, rz = fwd.z / l * 1.8, -fwd.x / l * 1.8 end
                        end
                        e.chara:call("warp(via.vec3, app.CharacterWarpOption)", Vector3f.new(apos.x + rx, apos.y + 0.3, apos.z + rz), nil)
                        log_msg(string.format("Co-op: brought %s over (%.0f m away)", tostring(e.name), math.sqrt(dx * dx + dz * dz)))
                    end
                    break
                end
            end
        end)
    end
    local ok = start_possession(coop.pawn_idx)
    if ok == false or not state.active then
        coop.active = false
        coop_restore_overrides()
        log_msg("Co-op: could not take the pawn")
        coop_write_status()
        return false
    end
    coop.ar_input_addr = addr_of(state.arisen_input)
    coop.chord_latch, coop.face_t = nil, nil
    coop_install_glyph_hook()
    coop_force_kbm_glyphs()
    coop_ensure_map()
    coop_event("co-op ON: player 2 -> " .. tostring(state.pawn_name) .. " (native " .. tostring(native.pip ~= nil and not native.failed) .. ")")
    log_msg("CO-OP: player 2 (controller) plays " .. tostring(state.pawn_name) .. "; player 1 keeps the Arisen")
    R.note = { text = "Co-op: player 2 plays " .. tostring(state.pawn_name), t_end = os.clock() + 4.0 }
    coop_write_status()
    if R.api_fire then pcall(R.api_fire, "coop_start", { players = { [1] = "Arisen", [2] = state.pawn_name } }) end -- v0.9.170
    if R.cp_begin then pcall(R.cp_begin) end -- v0.9.171 co-op players model
    return true
end

local function coop_stop()
    -- dev38: player 2's character glows as they leave (players 3+ glow in R.np_leave)
    for n, g in pairs(R.pglow) do if g.kept then pcall(R.cine_glow, g.chara, g.name, false) end; R.pglow[n] = nil end -- dev40
    if R.s2 and R.s2.active then R.leave_glow(R.s2.chara) elseif coop.active and state.active then R.leave_glow(state.pawn_chara) end
    if R.cp and R.cp.on and R.cp.mode == "pawns" then R.cp_end("co-op off"); return end -- v0.9.171
    -- 0.9.177: classic co-op with player 1 on the pawn (player 2 had the Arisen): player 1 keeps the pawn, now as a
    -- single-player possession
    local keep = cfg.coop_end_keep_p1 ~= false and coop.active and state.active and R.cp and R.cp.on
        and R.cp.mode == "classic" and R.cp.arisen_side == 2 and state.pawn_idx
    if coop.active then release_possession("co-op off") end
    if keep then
        local idx = keep
        enqueue_game_thread("co-op off: player 1 keeps his pawn", function() start_possession(idx) end)
    end
end

local function coop_toggle()
    if coop.active or (R.cp and R.cp.on) then coop_stop() else coop_start(cfg.selected_pawn_idx) end
end

R.cr_ok = function(ch)
    if not ch then return false end
    local ok, good = pcall(function()
        if ch:call("get_IsDead") == true then return false end
        if ch:call("get_IsCutSceneMode") == true then return false end
        if ch:call("get_IsDown") == true and (ch:call("get_Hp") or 1) <= 0 then return false end
        return (ch:call("get_Hp") or 1) > 0
    end)
    return ok and good == true
end
R.rb = { until_t = 0, power = 0, last_hp = nil, beat_t = 0, shape = nil, err = nil }
R.rb_dev = function()
    if not (R.tp_on and R.tp_on()) then return nil end
    for _, d in ipairs(R.tp_devs()) do
        if d:get_address() == R.tp.p2 then return d end
    end
    return nil
end
R.rb_set = function(d, power)
    local r = R.rb
    local p = math.max(0.0, math.min(1.0, power)) + 0.0
    local function try(shape)
        if shape == "two" then
            d:call("setMotorPower", 0, p)
            d:call("setMotorPower", 1, p)
        else
            d:call("setMotorPower", p)
        end
    end
    if r.shape then
        local ok = pcall(try, r.shape)
        if not ok then r.shape = nil end
        return ok
    end
    for _, shape in ipairs({ "two", "one" }) do
        local ok, err = pcall(try, shape)
        if ok then r.shape = shape; r.err = nil; return true end
        r.err = tostring(err)
    end
    return false
end
R.rb_pulse = function(power, dur)
    local r = R.rb
    local now = os.clock()
    power = power * (cfg.coop_p2_rumble_power or 1.0)
    if now < r.until_t and power <= r.power then return end
    r.power, r.until_t = power, now + dur
    local d = R.rb_dev()
    if d then R.rb_set(d, power) end
end
R.rb_tick = function()
    local r = R.rb
    local now = os.clock()
    if r.power > 0 and now >= r.until_t then
        r.power = 0
        local d = R.rb_dev()
        if d then R.rb_set(d, 0.0) end
    end
    if not (cfg.coop_p2_rumble and coop.active and state.pawn_chara and R.tp_on and R.tp_on()) then
        r.last_hp = nil
        return
    end
    local hp, mx = nil, nil
    pcall(function()
        local hit = state.pawn_chara:call("get_Hit")
        mx = hit and hit:call("get_OriginalMaxHp") or nil
        hp = hit and hit:call("get_Hp") or nil
    end)
    if not (hp and mx and mx > 0) then return end
    local ratio = hp / mx
    if r.last_hp and hp < r.last_hp - 0.5 then
        local bite = (r.last_hp - hp) / mx
        if hp <= 0 then
            R.rb_pulse(1.0, 0.7)
        else
            R.rb_pulse(math.min(1.0, 0.35 + bite * 4.0), math.min(0.45, 0.12 + bite * 1.5))
        end
    end
    if cfg.coop_rb_status and r.last_hp and hp > r.last_hp + mx * 0.08 then
        R.rb_pulse(r.last_hp <= 0 and 0.5 or 0.2, r.last_hp <= 0 and 0.35 or 0.15)
    end
    r.last_hp = hp
    if ratio > 0 and ratio < 0.25 and now >= r.beat_t then
        r.beat_t = now + 1.1
        R.rb_pulse(0.25, 0.08)
        r.beat2 = now + 0.18
    elseif r.beat2 and now >= r.beat2 then
        r.beat2 = nil
        R.rb_pulse(0.18, 0.06)
    end
    if cfg.coop_rb_status then
        local st = nil
        pcall(function()
            local sm = state.pawn_chara:call("get_StaminaManager")
            local smx = sm and sm:call("get_MaxValue") or 0
            if smx > 0 then st = (sm:call("get_RemainingAmount") or 0) / smx end
        end)
        if st then
            if st <= 0.01 and (r.last_st or 1) > 0.01 then R.rb_pulse(0.35, 0.12); r.beat2 = now + 0.2 end
            r.last_st = st
        end
    end
    if (cfg.coop_rb_skill or cfg.coop_rb_status) and R.node_names then
        local okn, n0, n1 = pcall(R.node_names, state.pawn_chara)
        if okn then
            local nodes = tostring(n0) .. "|" .. tostring(n1)
            if nodes ~= r.last_nodes then
                local prev = r.last_nodes or ""
                r.last_nodes = nodes
                local function has(str, w) return str:find(w, 1, true) ~= nil end
                local skill = has(nodes, "Skill") and not has(nodes, "Cancel")
                local knocked = (has(nodes, "Blown") or has(nodes, "Down") or has(nodes, "Knock")) and not has(nodes, "Cancel")
                local was_skill = has(prev, "Skill") and not has(prev, "Cancel")
                local was_knocked = has(prev, "Blown") or has(prev, "Down") or has(prev, "Knock")
                if cfg.coop_rb_skill and skill and not was_skill then R.rb_pulse(0.22, 0.07) end
                if cfg.coop_rb_status and knocked and not was_knocked then R.rb_pulse(0.6, 0.3) end
                r.nodes_seen = nodes
            end
        end
    end
end

R.rb_hook = function()
    local td = sdk.find_type_definition("app.HitController")
    local m = td and td:get_method("updateDamage")
    if not m then return end
    sdk.hook(m, function(args)
        local st = thread.get_hook_storage()
        st.dpc_rb_di, st.dpc_rb_hc = nil, nil
        if cfg.coop_p2_rumble and coop.active and state.pawn_chara and R.tp_on and R.tp_on() then
            st.dpc_rb_di, st.dpc_rb_hc = args[3], args[2]
        end
    end, function(retval)
        local st = thread.get_hook_storage()
        local p, hcp = st.dpc_rb_di, st.dpc_rb_hc
        st.dpc_rb_di, st.dpc_rb_hc = nil, nil
        if p then
            pcall(function()
                local di = sdk.to_managed_object(p)
                local dmg = di and di.Damage
                if not dmg then return end
                local pgo = state.pawn_chara:call("get_GameObject")
                if not pgo then return end
                local pa = pgo:get_address()
                local owner = di["<AttackOwnerObject>k__BackingField"]
                local hc = hcp and sdk.to_managed_object(hcp)
                local tgo = hc and hc:call("get_GameObject")
                if cfg.coop_rb_dealt and owner and owner:get_address() == pa and tgo and tgo:get_address() ~= pa and dmg > 0 then
                    local mx = hc:call("get_OriginalMaxHp") or 0
                    local hpn = hc:call("get_Hp") or 1
                    if hpn <= 0 then
                        R.rb_pulse(0.85, 0.25)
                    else
                        local frac = mx > 0 and dmg / mx or 0.02
                        R.rb_pulse(math.min(0.75, 0.28 + frac * 6.0), math.min(0.18, 0.06 + frac * 2.0))
                    end
                elseif cfg.coop_rb_status and tgo and tgo:get_address() == pa and dmg <= 0 and owner and owner:get_address() ~= pa then
                    R.rb_pulse(0.4, 0.1)
                end
            end)
        end
        return retval
    end)
end
pcall(R.rb_hook)

R.cr_tick = function()
    local c = R.cr
    -- dev10: a second after the restart, put the arrangement back (R.cr_restore)
    if c.arr_t and os.clock() >= c.arr_t then
        local arr = c.arr_pend
        c.arr_t, c.arr_pend = nil, nil
        if arr and (coop.active or (R.cp and R.cp.on)) then pcall(R.cr_restore, arr) end
    end
    if not c.want then return end
    if coop.active or not cfg.coop_auto_resume then c.want, c.down = false, nil; return end
    local now = os.clock()
    if now < (c.next or 0) then return end
    c.next = now + 0.25
    if R.world ~= true then c.ok_since = nil; return end
    local ar = nil
    pcall(function() ar = sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer") end)
    local entry = nil
    for _, e in ipairs(get_party()) do
        if c.name and c.name ~= "" and e.name == c.name then entry = e; break end
    end
    if not entry then
        for _, e in ipairs(get_party()) do if e.idx == c.idx then entry = e; break end end
    end
    if entry and c.down == nil then
        local okd, downed = pcall(function() return entry.chara:call("get_IsDown") == true and (entry.chara:call("get_Hp") or 1) <= 0 end)
        if okd and downed then c.down = entry.chara end
    end
    if not (entry and R.cr_ok(ar) and R.cr_ok(entry.chara)) then
        c.ok_since = nil
        if not c.noted then
            c.noted = true
            R.note = { text = "Co-op resumes when " .. tostring(c.name or "the pawn") .. " is back", t_end = now + 3.0 }
        end
        return
    end
    c.down = nil
    c.ok_since = c.ok_since or now
    if now - c.ok_since < 2.0 then return end
    c.ok_since = nil
    local ok, started = pcall(coop_start, entry.idx)
    if ok and started ~= false and coop.active then
        c.want = false
        local p1, p2 = c.p1, c.p2
        if p1 and p2 and R.tp then
            local have1, have2 = false, false
            for _, d in ipairs(R.tp_devs()) do
                local a = d:get_address()
                if a == p1 then have1 = true elseif a == p2 then have2 = true end
            end
            if p1 == R.KB_ADDR then have1 = true end
            if have1 and have2 then R.tp.p1, R.tp.p2, R.tp.wait_release, R.tp.p1v = p1, p2, nil, nil end
        end
        R.note = { text = "Co-op resumed: player 2 plays " .. tostring(state.pawn_name), t_end = now + 3.0 }
        if c.arr then c.arr_pend, c.arr_t, c.arr = c.arr, now + 1.0, nil end
        coop_event("co-op resumed (" .. tostring(c.reason) .. ")")
    else
        c.tries = (c.tries or 0) + 1
        c.next = now + 5.0
        if c.tries >= 5 then
            c.want = false
            R.note = { text = "Co-op could not resume - start it again (Ctrl+F6)", t_end = now + 5.0 }
        end
    end
end

local function toggle_possession()
    if state.active then
        release_possession("hotkey toggle")
    else
        start_possession(cfg.selected_pawn_idx)
    end
end

local function switch_control_mode(new_mode)
    if state.active then
        local idx = state.pawn_idx
        release_possession("mode change")
        cfg.control_mode = new_mode
        save_cfg()
        start_possession(idx)
    else
        cfg.control_mode = new_mode
        save_cfg()
    end
end

-- shared with the modules loaded after this one (see shared.lua)
S.coop_pad_values, S.coop_ensure_map, S.coop_write_status = coop_pad_values, coop_ensure_map, coop_write_status
S.coop_start, S.coop_stop, S.coop_toggle, S.toggle_possession = coop_start, coop_stop, coop_toggle, toggle_possession
S.switch_control_mode = switch_control_mode
