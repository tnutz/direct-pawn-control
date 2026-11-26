-- Direct Pawn Control: native Arisen controls: a per-pawn PlayerInputProcessor driven from DPC.
-- Part of DirectPawnControl.lua, which loads the files in this folder in order (this one is 07 of 26).
-- Never run on its own: REFramework only runs the files directly in reframework/autorun.
local S = require("DirectPawnControl/shared")
local dev_error, cfg, R, log_msg, same_obj, call = S.dev_error, S.cfg, S.R, S.log_msg, S.same_obj, S.call
local field, set_field, JOB_NAMES, get_party, state = S.field, S.set_field, S.JOB_NAMES, S.get_party, S.state
local brain, coop, brain_pos, brain_facing = S.brain, S.coop, S.brain_pos, S.brain_facing
local brain_angdiff, brain_alive, SET_TARGET_SIG = S.brain_angdiff, S.brain_alive, S.SET_TARGET_SIG
local REMOVE_TARGET_SIG, brain_lock_apply = S.REMOVE_TARGET_SIG, S.brain_lock_apply
local brain_lock_restore, brain_restore_input = S.brain_lock_restore, S.brain_restore_input

-- ----------------------------------------------------------------------------
-- Native Arisen controls (v0.7.0): a per-pawn app.PlayerInputProcessor driven from DPC
-- ----------------------------------------------------------------------------
local native = { pip = nil, param = nil, lock = nil, job = nil, errors = 0, failed = false, frames = 0,
    drive = "player", hook_frames = 0, hook_input_frames = 0, mirror_input_frames = 0, t_start = 0 }

local function native_release()
    -- Just drop the references. (o:release() logged "not managed by our Lua state" warnings.)
    native.pip, native.lock = nil, nil
    native.param, native.job, native.errors, native.failed, native.frames = nil, nil, 0, false, 0
    native.hook_frames, native.hook_input_frames, native.mirror_input_frames = 0, 0, 0
end

local function native_build()
    native_release()
    if not cfg.native_controls then return false end
    if cfg.native_skip_thief and state.pawn_job == 4 then
        log_msg("Native controls skipped for Thief (native_skip_thief) -> Mode 2 puppeteer")
        return false
    end
    local pw, hu, apip = state.pawn_chara, state.pawn_human, state.arisen_pip
    if not (pw and hu and apip) then return false end
    local ok, err = pcall(function()
        local pip = sdk.create_instance("app.PlayerInputProcessor"):add_ref()
        local track = hu:get_field("Track")
        pip:call("set_Chara", pw)
        pip:call("set_Human", hu)
        pip:call("set_PlayerTrack", track)
        pip:set_field("Camera", apip:get_field("Camera"))
        -- setup takes (Character, PlayerTrack). A bare setup() is rejected by REFramework ("Invalid number of
        -- arguments") and silently skipped, leaving the processor half-initialised (suspected Thief crash).
        pip:call("setup(app.Character, app.PlayerTrack)", pw, track)
        if not pip:get_field("Camera") then pip:set_field("Camera", apip:get_field("Camera")) end
        pip:call("selectProcessor")
        -- Lock-on: by default use the Arisen's own LockOnController, which DPC already rebinds to the pawn
        -- (Chara = pawn) at possession and which app.Player keeps updating. v0.7.0/0.7.1 built an orphan
        -- controller nobody else updates; LockOnController does async target finding (FindTargetMutex), and
        -- both Thief crashes were on engine worker threads during target-seeking skills.
        local alock = apip:get_field("Param"):get_field("LockOnCtrl")
        local lock = alock
        if cfg.native_own_lockon or not alock then
            lock = sdk.create_instance("app.LockOnController"):add_ref()
            lock:call("setup", pw, alock and alock:get_field("<ParamList>k__BackingField"))
        end
        local param = pip:get_field("Param")
        param:set_field("Chara", pw)
        param:set_field("Human", hu)
        param:set_field("PlayerTrack", track)
        param:set_field("LockOnCtrl", lock)
        -- The Arisen's Details all share pip.Param; a fresh pip leaves theirs nil.
        local di = pip:get_field("DetailInstances")
        for i = 0, di:get_Length() - 1 do
            local d = di[i]
            if d then d:set_field("Param", param) end
        end
        native.pip, native.param, native.lock = pip, param, lock
    end)
    if not ok then
        log_msg("Native controls: build failed (" .. tostring(err) .. ") -> using Mode 2 puppeteer")
        native_release()
        native.failed = true
        return false
    end
    native.job = state.pawn_job
    native.drive = cfg.native_drive or "player"
    native.t_start = os.clock()
    log_msg("Native controls ON for " .. tostring(state.pawn_name) .. " (" .. tostring(native.pip:get_field("Detail") and native.pip:get_field("Detail"):get_type_definition():get_name()) .. ")")
    return true
end

-- 0.9.172-dev13 played pawn sprint. pawn-dash-2 (2026-11-20): Dash held on the pawn's input, the pawn's processor
-- set DashSwitch + IsDash on the press with DashTriggerKeepTime 30, and dropped both when that ran out although
-- Dash was still held; the Arisen kept sprinting on the same held Dash. app.CharacterInput has DashOptionHandle (an
-- EnumOptionHandle<app.OptionTriggerType>: Trigger 0 / Hold 1, the game's Dash option) and isConvertDashToKeepDash;
-- the pawn's own CharacterInput carries no such handle from the player's options. Give it the Arisen's.
R.dash_opt_take = function(inp)
    if not (cfg.native_dash_opt and inp and state.arisen_input) then return nil end
    local orig
    local ok, err = pcall(function()
        orig = inp:get_field("DashOptionHandle")
        local h = state.arisen_input:get_field("DashOptionHandle")
        if h then inp:set_field("DashOptionHandle", h) end
    end)
    if not ok then dev_error("dash option", err) end
    return { v = orig }
end
R.dash_opt_put = function(inp, saved)
    if not (inp and type(saved) == "table") then return end
    pcall(function() inp:set_field("DashOptionHandle", saved.v) end)
end
-- v0.9.167 hip bow skills (see the main-loop block): hold the aim flags while a played Archer's skill is in its
-- Prepare / Ready / charge stage. st keeps whether it was holding (counted once per hold).
R.hip_main = {}
R.hip_aim_hold = function(inp, chara, st)
    local _, up = R.node_names(chara) -- node_names is defined further down
    up = up or ""
    local hold = up:find("Job02_SkillAttack", 1, true) ~= nil and up:find("Cancel", 1, true) == nil
        and (up:find("Prepare", 1, true) or up:find("Ready", 1, true) or up:find("Charge", 1, true)) ~= nil
    local AIMF = (S.ACTION_FLAGS["AimHold"] or 0) | (S.ACTION_FLAGS["JobSpecialAction"] or 0)
    if hold and AIMF ~= 0 then
        local on0 = field(inp, "ButtonOnFlags") or 0
        if (on0 & AIMF) ~= AIMF then
            set_field(inp, "ButtonOnFlags", on0 | AIMF)
            if not st.on then R.hip_aim_n = (R.hip_aim_n or 0) + 1 end
        end
        st.on = true
    else
        st.on = false
    end
end
-- right before an extra played pawn's processor update (player 2's R.s2, players 3+)
R.s2_pre = function(s)
    R.dash_keep(s.input)
    if cfg.pawn_hip_skill_aim and s.job == 2 and s.input and s.chara then
        s.hip = s.hip or {}
        pcall(R.hip_aim_hold, s.input, s.chara, s.hip)
    end
end
R.dash_keep = function(inp)
    if not (cfg.native_dash_keep and inp) then return end
    local fd, fk = S.ACTION_FLAGS.Dash or 0, S.ACTION_FLAGS.KeepDash or 0
    if fd == 0 or fk == 0 then return end
    pcall(function()
        local on = inp:get_field("ButtonOnFlags") or 0
        if (on & fd) ~= 0 then inp:set_field("ButtonOnFlags", on | fk) end
    end)
end

local coop_target_tick -- v0.9.12, defined below (after native_release / native_build)
-- Returns true when the native processor handled this frame (DPC's puppeteer is then skipped).
local function native_tick()
    local pip = native.pip
    if not (cfg.native_controls and pip and not native.failed) then return false end
    if native.job ~= state.pawn_job then
        native.job = state.pawn_job
        if cfg.native_skip_thief and state.pawn_job == 4 then
            native_release()
            return false
        end
        pcall(pip.call, pip, "selectProcessor") -- vocation changed: pick that job's Detail
    end
    -- Self-check for the app.Player.update slot (see native_player_hook): fall back if it never fires or never
    -- sees the input DPC mirrored this frame.
    if native.drive == "player" then
        local age = os.clock() - native.t_start
        if age > 1.0 and native.hook_frames == 0 then
            native.drive = "pre"
            log_msg("Native controls: app.Player.update slot never fired -> driving at pre-UpdateBehavior")
        elseif native.mirror_input_frames > 120 and native.hook_input_frames == 0 then
            native.drive = "pre"
            log_msg("Native controls: input already cleared at app.Player.update -> driving at pre-UpdateBehavior")
        else
            return true -- the hook runs pip:update() this frame
        end
    end
    coop_target_tick()
    R.dash_keep(state.pawn_input)
    local ok, err = pcall(pip.call, pip, "update")
    native.frames = native.frames + 1
    if R.aim_point then R.aim_point() end
    if ok then return true end
    return false
end


-- v0.9.12 co-op auto-target. In co-op player 2's pawn gets a LockOnController of its own (so it can't steal player 1's
-- lock-on), but nothing updates that controller, so it never had a target: skills like Burst Strike and pawn shots
-- went straight ahead with no homing. Each frame, right before the pawn's processor runs, pick the best enemy
-- (nearest, weighted by how far off the pawn's facing it is) and set it as that controller's target, the same call
-- the Arisen brain uses on his own lock-on (verified live 2026-11-10). No finder is called or hooked.
-- v0.9.140 the game's own lock-on ranges, read once per vocation and kept (requested: read the ranges from the game once and keep them). app.LockOnRangeParameterList (the lock-on
-- controller's ParamList): per vocation a list of entries (Default, NormalAttack, SubNormalAttack, CustomSkill per
-- skill, Special), each with distance / angle tiers. Kept as plain numbers: the longest distance of the vocation's
-- Default and attack entries, and the longest per skill. Read live 2026-11-17: Archer default 30 m (Meteor Shot 40),
-- Mystic Spearhand default 5 m, attacks 7 - 12.5 m. Normal possession needs no number at all (the game's own search
-- runs for the pawn with these ranges); co-op's auto-target uses them in place of the fixed 15 m.
R.lock_ranges = function(job)
    R.lock_range_cache = R.lock_range_cache or {}
    local c = R.lock_range_cache[job]
    if c ~= nil then return c or nil end
    R.lock_range_cache[job] = false -- one attempt per vocation, whatever happens
    local ok, err = pcall(function()
        local lk = native.lock or state.arisen_lockon_ctrl
        local pl = lk and lk:call("get_ParamList")
        local arr = pl and pl:get_field("Parameters")
        if not arr then return end
        local function longest(tp)
            local m, rs = 0, tp:get_field("Ranges")
            if rs then
                for i = 0, rs:call("get_Length") - 1 do
                    local rg = rs:call("Get", i)
                    local d = rg:get_field("Distance")
                    if rg:get_field("IsDisable") ~= true and type(d) == "number" and d > m then m = d end
                end
            end
            return m
        end
        for i = 0, arr:call("get_Length") - 1 do
            local jp = arr:call("Get", i)
            if jp:get_field("Job") == job then
                local out = { base = 0, skill = {}, n = 0 }
                local tps = jp:get_field("Parameters")
                for k = 0, tps:call("get_Length") - 1 do
                    local tp = tps:call("Get", k)
                    if tp:get_field("IsDisable") ~= true then
                        local at, d = tp:get_field("ActionType"), longest(tp)
                        out.n = out.n + 1
                        if at == 3 then
                            local id = tp:get_field("CustomSkillID")
                            if type(id) == "number" and d > (out.skill[id] or 0) then out.skill[id] = d end
                        elseif at ~= 4 and d > out.base then
                            out.base = d
                        end
                    end
                end
                if out.base > 0 then
                    R.lock_range_cache[job] = out
                    log_msg(string.format("Lock-on ranges from the game for %s: %.1f m (%d entries)", JOB_NAMES[job] or ("job " .. tostring(job)), out.base, out.n))
                end
                return
            end
        end
    end)
    if not ok then dev_error("lock ranges", err) end
    return R.lock_range_cache[job] or nil
end
-- the longest range the played pawn can use right now: its vocation's own, or a longer one of an equipped skill
R.lock_range_now = function()
    local c = state.pawn_job and R.lock_ranges(state.pawn_job)
    if not c then return nil end
    local r = c.base
    for _, id in ipairs(state.pawn_skills or {}) do
        local d = c.skill[id]
        if d and d > r then r = d end
    end
    return r
end

R.OVERLAY_CAMS = { [0] = true, [1] = true, [2] = true, [3] = true, [5] = true, [6] = true, [7] = true, [8] = true, [9] = true, [15] = true }

-- 0.9.172-dev24: an enemy's body radius (its character controller's, capped at 8 m), cached per object
R.radius_cache = setmetatable({}, { __mode = "k" })
R.body_radius = function(e)
    local v = R.radius_cache[e]
    if v == nil then
        local ok, r = pcall(function() return e:call("get_OriginalCharaControllerRadius") end)
        v = (ok and type(r) == "number" and r > 0) and math.min(r, 8.0) or 0.0
        R.radius_cache[e] = v
    end
    return v
end

R.ta_colors = { { "Gold", 0x20B0FF }, { "Cyan", 0xFFD040 }, { "Green", 0x50E050 }, { "Magenta", 0xF050E0 },
                 { "Red", 0x4040FF }, { "White", 0xF0F0F0 } }
R.ta = { pin = nil, r3_t = nil, flick = 0, req = nil }
-- 0.9.173 (the tester: "Gold is probably the weakest one. Let's make them in order of Cyan, White, Green, Magenta, Red,
-- Gold"): the default per player and the menu order. The numbers in R.ta_colors stay as they were, because saved
-- settings store them; only the order shown and the defaults change.
R.COLOR_ORDER = { 2, 6, 3, 4, 5, 1 }
R.np_color = function(n) return R.COLOR_ORDER[n] or 1 end -- index into R.ta_colors
-- 0.9.173-dev1 (the tester: "let them each choose a color there and match it to their target circle/bookmark"): one colour
-- per player drives their target dot, their join / kept glow and Camera Distance's off-screen marker. Players 1 and 2
-- keep the marker-colour settings they already had; players 3+ are in cfg.coop_colors["p<n>"].
R.player_color = function(n)
    local v
    if n == 1 then v = cfg.coop_aim_p1_color elseif n == 2 then v = cfg.coop_aim_p2_color
    else v = (cfg.coop_colors or {})["p" .. n] end
    v = math.tointeger(tonumber(v) or 0)
    if not v or not R.ta_colors[v] then v = R.np_color(n) end
    return v
end
R.set_player_color = function(n, v)
    if n == 1 then cfg.coop_aim_p1_color = v elseif n == 2 then cfg.coop_aim_p2_color = v
    else cfg.coop_colors = cfg.coop_colors or {}; cfg.coop_colors["p" .. n] = v end
end
R.player_abgr = function(n) return 0xFF000000 | R.ta_colors[R.player_color(n)][2] end
-- The game's rim lights come in fixed colours: each marker colour gets the closest one. White: Counterslash, "a perfect
-- white" and steady (the tester, white-glow-2, 2026-11-22). Tried before: AstralBody (not white), RimLightInteractGimmic
-- (white but flashing, too much for co-op). The Preview button in the settings shows each one.
R.COLOR_GLOWS = { [1] = "RimLightInteractLarge", [2] = "AstralPlayer", [3] = "ChRecovery", [4] = "RimLightSummon",
                  [5] = "Berserker", [6] = "Counterslash" }
R.player_glow = function(n) return R.COLOR_GLOWS[R.player_color(n)] or "AstralPlayer" end
R.ta_note = function(text) R.note = { text = text, t_end = os.clock() + 1.5 } end
R.ta_p1_target = function()
    local c = nil
    pcall(function()
        local t = state.arisen_lockon_ctrl and state.arisen_lockon_ctrl:call("get_Target")
        c = t and t:call("get_Character")
    end)
    if c and brain_alive(c) then return c end
    return nil
end
R.ta_p2_input = function(btn, pv)
    local a = R.ta
    local r3 = pv.RStickPush or 0x2000
    local now = os.clock()
    if (btn & r3) ~= 0 then
        if not a.r3_t then a.r3_t, a.r3_long = now, false end
        if not a.r3_long and now - a.r3_t >= 0.6 then a.r3_long = true; a.req = "p1" end
    elseif a.r3_t then
        if not a.r3_long then a.req = "toggle" end
        a.r3_t = nil
    end
    local rx, ry = S.pad_stick_rx or 0.0, S.pad_stick_ry or 0.0
    if cfg.coop_aim_flick == "quick" then
        if a.flick == 0 then
            if not state.is_aiming and math.abs(rx) > 0.7 and math.abs(rx) > math.abs(ry) * 1.2 then
                a.flick = rx > 0 and 1 or -1
                a.req = a.flick > 0 and "right" or "left"
            end
        elseif math.abs(rx) < 0.3 then
            a.flick = 0
        end
        return btn & ~r3
    end
    -- 0.9.172 (the tester: "the ring didn't seem to prevent changing target with right stick"): a deliberate flick only.
    -- From rest, the stick reaches near-full sideways within 0.2 s, then comes back to rest within 0.5 s; the switch
    -- happens on the way back. Resting a thumb on the stick, a slow push or holding it out does nothing.
    -- dev11: coop-aim-2 counted flicks in pairs 0.2 - 0.4 s apart: the stick springs back past centre and the
    -- rebound read as a second flick. A new flick now needs the stick at rest for 0.12 s first, and none starts
    -- within 0.3 s of the last one.
    local d = R.flick_step(a, rx, ry, now)
    if d and not state.is_aiming then a.req = d > 0 and "right" or "left" end
    return btn & ~r3
end
-- 0.9.172-dev20: the deliberate-flick detector (was inline for player 2), shared with player 1. State a; returns
-- 1 / -1 on the frame a flick completes (stick back at rest), else nil.
R.flick_step = function(a, rx, ry, now)
    local m = math.sqrt(rx * rx + ry * ry)
    local out = nil
    if m < 0.3 then
        if a.fl_t0 and a.fl_hit and now - (a.fl_hit_t or 0) <= 0.5 then
            out = a.fl_dir
            a.flick_n = (a.flick_n or 0) + 1
            a.fl_last = now
        end
        if a.fl_t0 or not a.fl_rest then a.fl_rest = now end
        a.fl_t0, a.fl_hit, a.fl_dir = nil, false, 0
    else
        local ready = a.fl_rest and now - a.fl_rest >= 0.12 and now - (a.fl_last or -10) >= 0.3
        if not a.fl_t0 then a.fl_t0, a.fl_hit, a.fl_dir, a.fl_ok = now, false, 0, ready end
        if not a.fl_ok then a.fl_rest = nil end
        if a.fl_ok and not a.fl_hit and math.abs(rx) >= 0.85 and math.abs(rx) > math.abs(ry) * 1.5 then
            if now - a.fl_t0 <= 0.2 then
                a.fl_hit, a.fl_hit_t, a.fl_dir = true, now, (rx > 0) and 1 or -1
            end
        end
        if a.fl_hit and (rx > 0 and 1 or -1) ~= a.fl_dir and math.abs(rx) > 0.5 then a.fl_hit = false end -- swung through
    end
    return out
end
-- 0.9.172-dev20: camera share of a right stick when flicks are targeting: nothing for the first 0.12 s after it
-- leaves rest, and nothing at all for a push that reaches full sideways within 0.2 s (a flick) until it is back at
-- rest. A slow push turns the camera after that short delay.
R.cam_gate = function(g, rx, ry, now)
    if math.sqrt(rx * rx + ry * ry) < 0.3 then g.t0, g.fl = nil, false; return 0.0, 0.0 end
    if not g.t0 then g.t0, g.fl = now, false end
    if not g.fl and math.abs(rx) >= 0.85 and now - g.t0 <= 0.2 then g.fl = true end
    if g.fl or now - g.t0 < 0.12 then return 0.0, 0.0 end
    return rx, ry
end
R.ta_sx = function(c)
    local ok, sp = pcall(draw.world_to_screen, Vector3f.new(c.x, c.y + 1.2, c.z))
    if ok and sp then return sp.x end
    return nil
end
R.ta_resolve = function(req, best, bd, cands)
    local a = R.ta
    local function find(ch)
        for _, c in ipairs(cands) do if same_obj(c.e, ch) then return c end end
        return nil
    end
    if req == "toggle" then
        if a.pin then
            a.pin = nil
            R.ta_note("Player 2: automatic target")
        else
            a.pin = coop.tgt or best
            if a.pin then R.ta_note("Player 2: target kept") end
        end
    elseif req == "p1" then
        local t = R.ta.p1 or R.ta_p1_target()
        if t and find(t) then
            a.pin = t
            R.ta_note("Player 2: same target as player 1")
        else
            R.ta_note("Player 1 has no target in range")
        end
    elseif req == "left" or req == "right" then
        local cur = find(a.pin or coop.tgt)
        local ds = imgui.get_display_size()
        local cx = (cur and R.ta_sx(cur)) or (ds and ds.x * 0.5) or 960
        local pick, gap = nil, nil
        for _, c in ipairs(cands) do
            if not (cur and same_obj(c.e, cur.e)) then
                local sx = R.ta_sx(c)
                if sx then
                    local dx = sx - cx
                    if (req == "right" and dx > 1) or (req == "left" and dx < -1) then
                        if not gap or math.abs(dx) < gap then pick, gap = c, math.abs(dx) end
                    end
                end
            end
        end
        if pick then a.pin = pick.e end
    end
    if a.pin then
        local c = find(a.pin)
        if c and brain_alive(a.pin) then return a.pin, c.d end
        a.pin = nil
    end
    return best, bd
end
R.ta_bones = { "Spine_2", "Spine_1", "Spine_0", "Hip" }
R.ta_joints, R.ta_last = {}, {}
R.ta_screen = function(ch)
    local okad, a = pcall(ch.get_address, ch)
    if not okad then return nil end
    local now = os.clock()
    local x, y
    pcall(function()
        local tf = ch:call("get_Transform")
        local body = tf:call("get_Position")
        if not body then return end
        local j = R.ta_joints[a]
        if j == nil then
            j = false
            for _, bn in ipairs(R.ta_bones) do
                local okj, jj = pcall(tf.call, tf, "getJointByName(System.String)", bn)
                if okj and jj then j = jj; break end
            end
            R.ta_joints[a] = j
        end
        local px, py, pz = body.x, body.y + 1.2, body.z
        if j then
            local okp, jp = pcall(j.call, j, "get_Position")
            if okp and jp then
                local dx, dy, dz = jp.x - body.x, jp.y - body.y, jp.z - body.z
                if dx * dx + dy * dy + dz * dz < 144 then px, py, pz = jp.x, jp.y, jp.z else R.ta_joints[a] = nil end
            end
        end
        local sp = draw.world_to_screen(Vector3f.new(px, py, pz))
        if sp then x, y = sp.x, sp.y end
    end)
    if x then
        R.ta_last[a] = { x = x, y = y, t = now }
        return x, y
    end
    local l = R.ta_last[a]
    if l and now - l.t < 0.4 then return l.x, l.y end
    return nil
end
R.ta_calc = function() end
R.ta_draw = function(hh)
    R.ta_dbg = nil
    -- dev58: the split screen has its own switch (off by default)
    local split_now = R.views_now and R.views_now()
    local mk_on = split_now and cfg.coop_aim_markers_split or (not split_now and cfg.coop_aim_markers)
    if not (cfg.coop_aim and mk_on and coop.active and state.active) then return end
    local t1 = R.ta.p1 or R.ta_p1_target()
    local t2 = coop.tgt
    if t2 and not brain_alive(t2) then t2 = nil end
    local same = t1 and t2 and same_obj(t1, t2)
    local k = hh / 2160.0 * (cfg.coop_aim_size or 1.0)
    local r = 13.0 * k
    local drawn = 0
    local function dot(ch, colix, dx, pin)
        local x, y = R.ta_screen(ch)
        if not x then return end
        local c = (R.ta_colors[colix or 1] or R.ta_colors[1])[2]
        x, y = x + dx * k, y - 70.0 * k
        draw.filled_circle(x, y, r + 3.0 * k, 0xD0000000, 20)
        draw.filled_circle(x, y, r, 0xF0000000 | c, 20)
        draw.filled_circle(x, y, r * 0.35, 0xF0FFFFFF, 12)
        if pin then
            draw.outline_circle(x, y, r + 7.0 * k, 0xD0000000, 24)
            draw.outline_circle(x, y, r + 6.0 * k, 0xF0000000 | c, 24)
        end
        drawn = drawn + 1
    end
    -- 0.9.172-dev36: players 3+ get their dots too (P3 green, P4 magenta, P5 red, then white); dots on the same
    -- enemy sit side by side
    local list = {}
    if t1 then list[#list + 1] = { t1, R.player_color(1), false } end
    if t2 then list[#list + 1] = { t2, R.player_color(R.s2 and R.s2.active and R.s2.player or 2), R.ta.pin ~= nil } end
    for n, sl in pairs(R.np and R.np.slots or {}) do
        if sl.active and sl.tgt and brain_alive(sl.tgt) then list[#list + 1] = { sl.tgt, R.player_color(n), sl.pin ~= nil } end
    end
    local per = {}
    for _, it in ipairs(list) do
        local a = it[1]:get_address()
        per[a] = (per[a] or 0) + 1
        it[4] = per[a]
    end
    for _, it in ipairs(list) do
        local cnt = per[it[1]:get_address()]
        dot(it[1], it[2], (it[4] - (cnt + 1) * 0.5) * 36, it[3])
    end
    R.ta_dbg = string.format("aim: P1 %s | P2 %s%s | dots %d", t1 and "locked" or "none",
        t2 and tostring(coop.tgt_name or "?") or "none", R.ta.pin and " (kept)" or "", drawn)
end

R.ta_p1_pick = function()
    local ds = imgui.get_display_size()
    local cx, cy = (ds and ds.x or 1920) * 0.5, (ds and ds.y or 1080) * 0.5
    local ax, _, az = brain_pos(state.arisen_chara)
    if not ax then return nil end
    local best, bs, cur_sc = nil, nil, nil
    local em = sdk.get_managed_singleton("app.EnemyManager")
    local arr = em and call(em, "getAllEnemies")
    local n = arr and call(arr, "get_Count") or 0
    for i = 0, n - 1 do
        local ok, e = pcall(function() return arr[i]:get_field("_Chara") end)
        if ok and e and brain_alive(e) then
            local ex, ey, ez = brain_pos(e)
            if ex and (ex - ax) ^ 2 + (ez - az) ^ 2 <= 45.0 ^ 2 then
                local oks, sp = pcall(draw.world_to_screen, Vector3f.new(ex, ey + 1.2, ez))
                if oks and sp and sp.x > 0 and sp.y > 0 and sp.x < cx * 2 and sp.y < cy * 2 then
                    local sc = (sp.x - cx) ^ 2 + (sp.y - cy) ^ 2
                    if R.ta.p1 and same_obj(e, R.ta.p1) then cur_sc = sc end
                    if not bs or sc < bs then best, bs = e, sc end
                end
            end
        end
    end
    -- 0.9.172-dev11: R3 "on the same goblin" picked its neighbour in coop-aim-2 (goblins 2.5 m apart), so the target
    -- never released. The current target counts as picked when it is nearly as central as the best one, or within
    -- 12 % of the screen height of the centre.
    if cur_sc and bs and (cur_sc <= bs * 2.25 or cur_sc <= (cy * 0.24) ^ 2) then return R.ta.p1 end
    return best
end
R.ta_p1_side = function(dir)
    local ds = imgui.get_display_size()
    local w = ds and ds.x or 1920
    local ax, _, az = brain_pos(state.arisen_chara)
    if not ax then return nil end
    local cx = w * 0.5
    if R.ta.p1 then
        local x, y, z = brain_pos(R.ta.p1)
        local sx = x and R.ta_sx({ x = x, y = y, z = z })
        if sx then cx = sx end
    end
    local best, gap = nil, nil
    local em = sdk.get_managed_singleton("app.EnemyManager")
    local arr = em and call(em, "getAllEnemies")
    local n = arr and call(arr, "get_Count") or 0
    for i = 0, n - 1 do
        local ok, e = pcall(function() return arr[i]:get_field("_Chara") end)
        if ok and e and brain_alive(e) and not (R.ta.p1 and same_obj(e, R.ta.p1)) then
            local ex, ey, ez = brain_pos(e)
            if ex and (ex - ax) ^ 2 + (ez - az) ^ 2 <= 45.0 ^ 2 then
                local sx = R.ta_sx({ x = ex, y = ey, z = ez })
                if sx and sx > 0 and sx < w then
                    local dx = sx - cx
                    if (dir > 0 and dx > 1) or (dir < 0 and dx < -1) then
                        if not gap or math.abs(dx) < gap then best, gap = e, math.abs(dx) end
                    end
                end
            end
        end
    end
    return best
end
R.ta_p1_release = function()
    local t = R.ta
    if t.p1_set and state.arisen_lockon_ctrl then
        pcall(function()
            if t.p1_work then state.arisen_lockon_ctrl:call(REMOVE_TARGET_SIG, t.p1_work) end
            state.arisen_lockon_ctrl:call("clearLockOn")
        end)
    end
    t.p1, t.p1_work, t.p1_set = nil, nil, false
end
R.ta_p1_tick = function()
    local t = R.ta
    if not (coop.active and cfg.coop_aim and cfg.coop_aim_p1 and state.arisen_chara) then
        if t.p1 or t.p1_set then R.ta_p1_release() end
        return
    end
    if t.p1_frame == os.clock() then return end
    t.p1_frame = os.clock()
    local pv = (R.pad_values and R.pad_values() or {})
    local r3 = pv.RStickPush or 0x2000
    local down = R.tp_on() and (R.tp_p1().b & r3) ~= 0 or false
    if not down then down = S.is_key_down_safe(0x04) == true end
    local edge = down and not t.p1_was
    t.p1_was = down
    if t.p1 and not brain_alive(t.p1) then R.ta_p1_release() end
    if t.p1 then
        local ax, _, az = brain_pos(state.arisen_chara)
        local ex, _, ez = brain_pos(t.p1)
        if not (ax and ex) or (ex - ax) ^ 2 + (ez - az) ^ 2 > 60.0 ^ 2 then R.ta_p1_release() end
    end
    -- 0.9.172-dev20: player 1 flicks like player 2 (next enemy on that side of his current target, or of the screen
    -- centre). With coop_cam_turn "p1" only while he has a target (his stick is the camera otherwise).
    if R.tp_on() and cfg.coop_aim_p1_flick ~= false then
        local p = R.tp_p1()
        t.f1 = t.f1 or {}
        local d = R.flick_step(t.f1, p.rx or 0.0, p.ry or 0.0, os.clock())
        if d and ((cfg.coop_cam_turn or "p1") ~= "p1" or t.p1) then
            local pick = R.ta_p1_side(d)
            if pick then
                R.ta_p1_release()
                t.p1 = pick
                pcall(function() t.p1_work = pick:call("get_LockOnTarget"):call("get_work") end)
                R.ta_note("Player 1: next target")
            end
        end
    end
    if edge then
        local pick = R.ta_p1_pick()
        if not pick or (t.p1 and same_obj(pick, t.p1)) then
            local had = t.p1 ~= nil
            R.ta_p1_release()
            if had then R.ta_note("Player 1: target released") end
        else
            R.ta_p1_release()
            t.p1 = pick
            pcall(function() t.p1_work = pick:call("get_LockOnTarget"):call("get_work") end)
            R.ta_note("Player 1: target")
        end
    end
    -- 0.9.172: the Arisen's lock-on only while player 1 fights (a button other than sprint, or a mouse button,
    -- within the last second). Held all the time, the game's lock-on turned "up" into "toward the target": in
    -- coop-aim-1 the Arisen walked off screen toward a goblin while the tester pushed up. The marker stays regardless.
    local fighting = false
    pcall(function()
        local b = (R.tp_on() and R.tp_p1().b) or S.pad_buttons or 0
        -- 0.9.172-dev11: face buttons and shoulders / triggers only. coop-aim-2 showed the lock-on held while only
        -- walking: the merged pad word also carries the stick as Emu* direction bits (EmuLup 0x100000 ...) and the d-pad.
        b = b & ((pv.RUp or 0x10) | (pv.RDown or 0x20) | (pv.RLeft or 0x40) | (pv.RRight or 0x80)
            | (pv.LTrigTop or 0x100) | (pv.LTrigBottom or 0x200) | (pv.RTrigTop or 0x400) | (pv.RTrigBottom or 0x800))
        if b ~= 0 or S.is_key_down_safe(0x01) or S.is_key_down_safe(0x02) then t.p1_fight_t = os.clock() end
        fighting = os.clock() - (t.p1_fight_t or -10) < (cfg.coop_aim_p1_assist_secs or 1.0)
    end)
    if t.p1 and t.p1_work and cfg.coop_aim_p1_assist and state.arisen_lockon_ctrl and (fighting or cfg.coop_aim_p1_assist_always) then
        local ok = pcall(function()
            state.arisen_lockon_ctrl:call(SET_TARGET_SIG, t.p1_work, false, false)
            state.arisen_lockon_ctrl:call("setAimTargetInfoToCharacter")
        end)
        t.p1_set = ok
    elseif t.p1_set and state.arisen_lockon_ctrl then
        pcall(function()
            if t.p1_work then state.arisen_lockon_ctrl:call(REMOVE_TARGET_SIG, t.p1_work) end
            state.arisen_lockon_ctrl:call("clearLockOn")
        end)
        t.p1_set = false
    end
end

coop_target_tick = function()
    pcall(R.ta_p1_tick)
    if not (coop.active and cfg.coop_auto_target and native.lock and state.pawn_chara) then return end
    if state.pawn_job == 4 and not cfg.coop_target_thief then return end
    local lk, pw = native.lock, state.pawn_chara
    if state.arisen_lockon_ctrl and same_obj(lk, state.arisen_lockon_ctrl) then return end -- never player 1's
    local now = os.clock()
    local areq = cfg.coop_aim and R.ta.req
    if areq then R.ta.req = nil; coop.tgt_next = 0 end
    if now >= (coop.tgt_next or 0) then
        coop.tgt_next = now + 0.1
        local px, _, pz = brain_pos(pw)
        if not px then return end
        local face = brain_facing(pw)
        local r, cone = cfg.coop_target_range or 15.0, math.rad(cfg.coop_target_cone or 75.0)
        if cfg.coop_target_game_ranges then r = R.lock_range_now() or r end
        coop.tgt_range = r
        local best, bs, bd = nil, nil, nil
        local cands = {}
        local em = sdk.get_managed_singleton("app.EnemyManager")
        local arr = em and call(em, "getAllEnemies")
        local n = arr and call(arr, "get_Count") or 0
        for i = 0, n - 1 do
            local ok, e = pcall(function() return arr[i]:get_field("_Chara") end)
            if ok and e and brain_alive(e) then
                local ex, ey, ez = brain_pos(e)
                if ex then
                    -- 0.9.172-dev24: measured to the body's edge, not its centre: coop-climb-2 had no automatic target
                    -- on a cyclops right next to player 2 (its centre is metres inside it) until he was very close
                    local dc = math.sqrt((ex - px) ^ 2 + (ez - pz) ^ 2)
                    local rad = R.body_radius(e)
                    local d = math.max(0.0, dc - rad)
                    -- 0.9.172-dev15: kept / flick targets come from this list. At r * 1.5 a short-range vocation (5 m
                    -- lock-on) lost its kept goblin 9 - 13 m away the moment it moved (coop-aim-3: the ring jumped to
                    -- the nearest enemy). Kept and flicked targets may be up to coop_aim_keep_range away.
                    local cr = r * 1.5
                    if cfg.coop_aim then cr = math.max(cr, cfg.coop_aim_keep_range or 30.0) end
                    if d <= cr then cands[#cands + 1] = { e = e, x = ex, y = ey, z = ez, d = d } end
                    local off = math.abs(brain_angdiff(math.atan(ex - px, ez - pz), face))
                    -- dev25: a big body fills more of the view: the cone counts from its nearest edge
                    if rad > 0.0 then off = math.max(0.0, off - math.atan(rad, math.max(dc, 0.1))) end
                    local keep = same_obj(e, coop.tgt) and 0.7 or 1.0 -- stickiness: don't flick between two enemies
                    if d <= r and (off <= cone or d <= 5.0) then
                        local score = d * (1.0 + off / math.pi * 2.0) * keep
                        if not bs or score < bs then best, bs, bd = e, score, d end
                    end
                end
            end
        end
        -- 0.9.172: the automatic target stays a moment after leaving the pawn's view cone (it turned to attack): the
        -- marker blinked off and on in coop-aim-1 (0.1-0.2 s gaps)
        if not best and coop.tgt and brain_alive(coop.tgt) then
            local held = nil
            for _, c in ipairs(cands) do if same_obj(c.e, coop.tgt) then held = c end end
            if held and held.d <= r * 1.2 then
                -- dev25: the markers "popped in and out" on a cyclops (coop-climb-2): the automatic target was dropped
                -- 0.6 s after the archer turned away to shoot or move. It now stays while it is in range and not
                -- behind her (within 150 degrees of where she faces), and coop_target_grace (1.5 s) more when behind.
                local off = math.abs(brain_angdiff(math.atan(held.x - px, held.z - pz), face))
                if off <= math.rad(150) then
                    best, bd = coop.tgt, held.d
                    coop.tgt_miss_t = nil
                else
                    coop.tgt_miss_t = coop.tgt_miss_t or now
                    if now - coop.tgt_miss_t < (cfg.coop_target_grace or 1.5) then best, bd = coop.tgt, held.d end
                end
            end
        else
            coop.tgt_miss_t = nil
        end
        if cfg.coop_aim then best, bd = R.ta_resolve(areq, best, bd, cands) end
        if not same_obj(best, coop.tgt) then
            coop.tgt, coop.tgt_work = best, nil
            if best then pcall(function() coop.tgt_work = best:call("get_LockOnTarget"):call("get_work") end) end
            coop.tgt_name = best and tostring(call(best, "get_CharaIDString")) or nil
            coop.tgt_dist = bd
            if coop.tgt_set and not best then
                pcall(lk.call, lk, "clearLockOn")
                coop.tgt_set = false
            end
        end
        coop.tgt_dist = bd
        if now >= (coop.tgt_status_t or 0) then coop.tgt_status_t = now + 0.5; coop.tgt_status_due = true end
    end
    if coop.tgt_work then
        local ok, err = pcall(function()
            lk:call(SET_TARGET_SIG, coop.tgt_work, false, false)
            lk:call("setAimTargetInfoToCharacter")
        end)
        if ok then
            coop.tgt_set = true
            coop.tgt_sets = (coop.tgt_sets or 0) + 1
        else
            coop.tgt_errs = (coop.tgt_errs or 0) + 1
            dev_error("co-op target", err)
            if coop.tgt_errs >= 20 then cfg.coop_auto_target = false; dev_error("co-op target", "20 errors -> off") end
        end
    end
end

-- v0.9.14 quick skills: Numpad 1-6 make the selected pawn (the one F6 would possess) use skill slot 1-6 while
-- nobody is possessed. HumanActionSelector.requestCustomSkill does nothing on an AI pawn (bridge test
-- 2026-11-14: 1.5 s of requests, AI off, no change), so this hands the pawn's AI the skill's own action pack
-- with a target (bridge test: Blink Strike started 0.47 s after the request). Ordering a pawn skill this way is
-- the idea of the mod Pawn Tactical Wheel, whose table got this feature started; it is credited in the README.
-- v0.9.115: that borrowed table is gone. Which action pack belongs to which skill is read from the game itself
-- (quick.game_table below), so nothing about it ships with the mod.
local quick = { packs = {}, n = 0, last = nil, holds = {} }

-- v0.9.115 the game's own skill table. Every pawn's AI planner (app.goalplanning.AIGoalPlanning) points at the
-- same game asset, AppSystem/AI/GoalPlanning/CustomSkillDecisionRefData.user: one entry per weapon skill
-- (82, all six pawn vocations), each a list of decision packs whose decisions carry the skill ids they are for
-- (_HumanCustomSkillIDs), the action pack (_ActInterPack) and the kind of target (_Target, AITargetFlag: My 1,
-- Player 2, Enemy 4, Gimmick 16, Party 64). Found and read with the bridge on 2026-11-17 (dev/bridge/skills/
-- hv8, hv9). A skill usually has several packs (on a ledge, while climbing, charged, for one quest NPC ...);
-- the plain one is taken: file name contains the skill's own enum name, no situational marker, shortest name.
quick.SITUATIONAL = { "_npc", "_ch%d", "_gm%d", "cnt%d", "quest", "climb", "_spot", "_air", "_break", "_tired",
    "combo", "_multiple", "_concentrate", "_charged", "keepdistance", "_release", "_ground", "_around", "jumpatt",
    "gimmick", "_ex$", "_ex_", "_lv2", "_lvex", "_nrd", "neutral", "^common/", "^grimoire/", "^npc/", "^ch%d" }

function quick.elems(x)
    if not x then return {} end
    local ok, e = pcall(x.get_elements, x)
    return (ok and e) or {}
end

-- reads the asset once: quick.rows[skill id] = { { rel, file, flag, named, obj }, ... }
function quick.game_rows()
    if quick.rows then return quick.rows end
    local now = os.clock()
    if quick.rows_try_t and now - quick.rows_try_t < 5.0 then return nil end
    quick.rows_try_t = now
    local rows, n = {}, 0
    local ok, err = pcall(function()
        local gp_t = sdk.typeof("app.goalplanning.AIGoalPlanning")
        local cs = nil
        for _, e in ipairs(get_party()) do
            local go = e.chara and e.chara:call("get_GameObject")
            local gp = go and go:call("getComponent(System.Type)", gp_t)
            local gd = gp and gp:get_field("_AIGoalData")
            cs = gd and gd:get_field("_CSDecisions")
            if cs then break end
        end
        if not cs then return end
        for _, set in ipairs(quick.elems(cs:get_field("_CustomSkillDecisions"))) do
            local sid = set:get_field("_SKillID")
            if type(sid) == "number" then
                local list = rows[sid] or {}
                rows[sid] = list
                for _, pack in ipairs(quick.elems(set:get_field("_DecisionPackList"))) do
                    for _, d in ipairs(quick.elems(pack and pack:get_field("_Decisions"))) do
                        local ap = d:get_field("_ActInterPack")
                        local path = ap and ap:call("get_Path")
                        if path then
                            path = tostring(path)
                            local named = false
                            for _, v in ipairs(quick.elems(d:get_field("_HumanCustomSkillIDs"))) do
                                local x = (type(v) == "userdata") and v:get_field("value__") or v
                                if x == sid then named = true end
                            end
                            local rel = path:lower():gsub("\\", "/"):gsub("^.*actinterpackdata/", ""):gsub("%.user$", "")
                            list[#list + 1] = { path = path, rel = rel, file = rel:match("([^/]+)$") or rel,
                                flag = tonumber(d:get_field("_Target")) or 0, named = named, obj = ap }
                            n = n + 1
                        end
                    end
                end
            end
        end
    end)
    if not ok then dev_error("quick skill table", err); return nil end
    if n == 0 then return nil end
    quick.rows, quick.defs = rows, {}
    log_msg(string.format("Quick skills: read the game's skill table (%d action packs)", n))
    if R.dev then
        local out = {}
        for id in pairs(rows) do
            local d = quick.table_def(id)
            out[tostring(id)] = d and { name = S.SKILL_NAMES[id], pack = d.path, kind = d.kind, alt = d.alt, flag = d.flag, how = d.how } or { name = S.SKILL_NAMES[id], pack = false }
        end
        R.dump("DPC_skill_table.json", { note = "Read from the game: CustomSkillDecisionRefData.user", rows = n, skills = out }, 2)
    end
    return rows
end

function quick.situational(rel)
    for _, pat in ipairs(quick.SITUATIONAL) do if rel:find(pat) then return true end end
    return false
end

-- the plain action pack of one skill: { path, obj, flag, kind, alt, how } or nil
function quick.table_def(id)
    local rows = quick.game_rows()
    if not rows then return nil end
    if quick.defs[id] ~= nil then return quick.defs[id] or nil end
    local set = rows[id] or {}
    local name = S.SKILL_NAMES and S.SKILL_NAMES[id]
    name = (type(name) == "string" and name ~= "") and name:lower() or nil
    local cand, how = {}, "name"
    if name then for _, r in ipairs(set) do if r.file:find(name, 1, true) then cand[#cand + 1] = r end end end
    if #cand == 0 then how = "named"; for _, r in ipairs(set) do if r.named then cand[#cand + 1] = r end end end
    if #cand == 0 and name then
        how = "other entry"
        for _, s2 in pairs(rows) do for _, r in ipairs(s2) do if r.file:find(name, 1, true) then cand[#cand + 1] = r end end end
    end
    if #cand == 0 then
        local distinct, k = {}, 0
        for _, r in ipairs(set) do if not distinct[r.rel] then distinct[r.rel] = true; k = k + 1 end end
        if k >= 1 and k <= 6 then how = "only packs"; cand = set end
    end
    if #cand == 0 then quick.defs[id] = false; return nil end
    local plain = {}
    for _, r in ipairs(cand) do if not quick.situational(r.rel) then plain[#plain + 1] = r end end
    if #plain > 0 then cand = plain end
    local best = nil
    for _, r in ipairs(cand) do
        if not best or #r.rel < #best.rel or (#r.rel == #best.rel and r.rel < best.rel) then best = r end
    end
    local f = 0
    for _, r in ipairs(cand) do if r.rel == best.rel then f = f | r.flag end end
    local d = { path = best.path, obj = best.obj, flag = f, how = how }
    if (f & 4) ~= 0 or (f & 67) == 0 then
        d.kind = "enemy"
        -- the game also uses it without an enemy: on the pawn itself, or on an ally
        if (f & 1) ~= 0 then d.alt = "self" elseif (f & 66) ~= 0 then d.alt = "player" end
    elseif (f & 66) ~= 0 then d.kind = "player" else d.kind = "self" end
    quick.defs[id] = d
    return d
end

local function quick_arisen()
    local cm = sdk.get_managed_singleton("app.CharacterManager")
    return cm and call(cm, "get_ManualPlayer")
end

-- The enemy the player means: the Arisen's lock-on target, else the enemy nearest the middle of the screen
-- (within 35 deg and 45 m of the camera), else the enemy nearest the pawn within 25 m.
local function quick_pick_enemy(pawn)
    local ar = quick_arisen()
    local okl, locked = pcall(function()
        local pl = ar:get_GameObject():call("getComponent(System.Type)", sdk.typeof("app.Player"))
        local t = pl and pl:call("get_LockOnCtrl"):call("get_Target")
        return t and t:call("get_Character")
    end)
    if okl and locked and brain_alive(locked) then return locked, "lock-on" end
    local em = sdk.get_managed_singleton("app.EnemyManager")
    local arr = em and call(em, "getAllEnemies")
    local n = arr and call(arr, "get_Count") or 0
    local cx, cy, cz, fx, fy, fz
    pcall(function()
        local tr = R.primary_cam():call("get_GameObject"):call("get_Transform")
        local p, q = tr:call("get_Position"), tr:call("get_Rotation")
        cx, cy, cz = p.x, p.y, p.z
        fx, fy, fz = -2.0 * (q.x * q.z + q.w * q.y), -2.0 * (q.y * q.z - q.w * q.x), -(1.0 - 2.0 * (q.x * q.x + q.y * q.y))
    end)
    local px, _, pz = brain_pos(pawn)
    local best, bs, near, nd = nil, nil, nil, nil
    for i = 0, n - 1 do
        local ok, e = pcall(function() return arr[i]:get_field("_Chara") end)
        if ok and e and brain_alive(e) then
            local ex, ey, ez = brain_pos(e)
            if ex and cx then
                local vx, vy, vz = ex - cx, (ey + 1.0) - cy, ez - cz
                local d = math.sqrt(vx * vx + vy * vy + vz * vz)
                if d > 0.1 and d < 45.0 then
                    local c = (vx * fx + vy * fy + vz * fz) / d
                    local off = math.deg(math.acos(math.max(-1.0, math.min(1.0, c))))
                    if off < 35.0 then
                        local score = off + d * 0.5
                        if not bs or score < bs then best, bs = e, score end
                    end
                end
            end
            if ex and px then
                local dp = math.sqrt((ex - px) ^ 2 + (ez - pz) ^ 2)
                if dp < 25.0 and (not nd or dp < nd) then near, nd = e, dp end
            end
        end
    end
    if best then return best, "screen" end
    if near then return near, "nearest" end
    return nil, nil
end

-- The pawn's own blackboard entry for the target (it carries weak points / body parts), else a fresh one.
local function quick_ai_target(pawn, tgt)
    local found = nil
    pcall(function()
        local bb = call(pawn, "get_AIBlackBoardController")
        local list = bb and bb:call("getTargetsOfType(app.AIDecisionDefine.AITargetFlag, app.ActionTargetUniqueTypeFlag, app.AIDecisionDefine.AIPositionFlag)", 8, 0, 0)
        local cnt = list and (tonumber(list:call("get_Count")) or 0) or 0
        local by = -1e9
        for i = 0, cnt - 1 do
            local at = list:call("get_Item", i)
            local oc = at and (at:get_field("<OwnerCharacter>k__BackingField") or at:get_field("<Character>k__BackingField"))
            if oc and same_obj(oc, tgt) then
                local y = 0
                pcall(function() y = at:get_field("<Transform>k__BackingField"):call("get_Position").y end)
                if not found or y > by then found, by = at, y end
            end
        end
    end)
    if found then return found end
    local at = sdk.create_instance("app.AITargetGameObject", true)
    if not at then return nil end
    at["<GameObject>k__BackingField"] = tgt:get_GameObject()
    at["<Character>k__BackingField"] = tgt
    at["<Owner>k__BackingField"] = tgt:get_GameObject()
    at["<OwnerCharacter>k__BackingField"] = tgt
    at["<ContextHolder>k__BackingField"] = tgt:get_Context()
    at["<Transform>k__BackingField"] = tgt:get_Transform()
    return at
end

-- v0.9.17: ask the pawn's own AI first. In battle it holds, for each equipped skill, decisions that name the
-- skill (AIDecision.HumanCustomSkillIDs), its action pack and the kind of target. Verified live 2026-11-15 on a
-- Fighter, a Thief and a Mage. Out of battle (or for a skill with no such decision) the game's table above is used.
function quick.game_def(pw, id)
    local best = nil
    pcall(function()
        local dm = pw:get_field("<AIDecisionMaker>k__BackingField")
        local list = dm:call("get_DecisionModule"):get_field("<MainDecisions>k__BackingField")
        local n = list:call("get_Count")
        for i = 0, n - 1 do
            local d = list:call("get_Item", i)
            local ids = d and d:get_field("<HumanCustomSkillIDs>k__BackingField")
            local hit = false
            if ids then
                for _, v in ipairs(ids:get_elements()) do
                    local x = (type(v) == "userdata") and v:get_field("value__") or v
                    if x == id then hit = true end
                end
            end
            if hit then
                local ap = d:get_field("<ActionPack>k__BackingField")
                local path = ap and tostring(ap:call("get_Path"))
                -- several variants can exist (e.g. _Ex, _COMEPL, _02): take the plainest (shortest) name
                if path and (not best or #path < #best.path) then
                    best = { obj = ap, path = path, flag = d:get_field("<Target>k__BackingField") or 0 }
                end
            end
        end
    end)
    if not best then return nil end
    local f = best.flag
    best.kind = ((f & 4) ~= 0) and "enemy" or ((((f & 2) ~= 0) or ((f & 64) ~= 0)) and "player" or "self")
    return best
end

-- v0.9.151 an ordered skill is kept. The order (blackboard values + ReqMainActInterPackData) was only a request:
-- the pawn's own decision maker stayed on and replaced it at its next evaluation, so a Fighter's Launchboard was
-- dropped almost at once. Pawn Tactical Wheel gives the same order and holds far longer; read in its script
-- (ai_engine.lua, fire_order): after the order it switches the pawn's AIDecisionMaker off (set_Enabled(false)) until
-- the action is over. The same is done here: decision maker off after the order, on again when the pawn's action
-- nodes are back at plain locomotion, when the action never started (2.5 s), at a time limit (8 s; 20 s for the
-- launch stances, skills 5 and 60), when the pawn goes down, is taken over, co-op starts, or scripts are reset.
-- Ordering a launch stance again while it is held ends it.
quick.STANCE = { [5] = true, [60] = true }
function quick.nodes(pw)
    local a, b = "", ""
    pcall(function()
        local fsm = pw:call("get_ActionManager"):get_field("Fsm")
        a = tostring(fsm:call("getCurrentNodeName(System.UInt32)", 0))
        b = tostring(fsm:call("getCurrentNodeName(System.UInt32)", 1))
    end)
    return a, b
end
function quick.hold_end(addr, why)
    local h = quick.holds[addr]
    if not h then return end
    quick.holds[addr] = nil
    pcall(function() h.dm:call("set_Enabled", true) end)
    log_msg(string.format("Quick skill: %s's own AI back on after %.1f s (%s)", tostring(h.name), os.clock() - h.t0, tostring(why)))
end
function quick.hold_start(pw, id, name)
    if not cfg.quick_skill_hold_ai then return end
    local addr = pw:get_address()
    quick.hold_end(addr, "new order")
    local dm = pw:get_field("<AIDecisionMaker>k__BackingField")
    if not dm then return end
    local n0, n1 = quick.nodes(pw)
    dm:call("set_Enabled", false)
    quick.holds[addr] = { pw = pw, dm = dm, id = id, name = name, t0 = os.clock(), n0 = n0, n1 = n1 }
end
function quick.hold_tick()
    if not next(quick.holds) then return end
    local now = os.clock()
    for addr, h in pairs(quick.holds) do
        local why
        if coop.active then why = "co-op"
        elseif state.active and state.pawn_chara and state.pawn_chara:get_address() == addr then why = "taken over"
        elseif call(h.pw, "get_IsDead") or call(h.pw, "get_IsDown") then why = "pawn down"
        else
            local a, b = quick.nodes(h.pw)
            local idle = a:find("Locomotion", 1, true) ~= nil and (b == "" or b:find("UpperBodyDefault", 1, true) ~= nil or b:find("Locomotion", 1, true) ~= nil)
            if not h.started then
                if not idle and (a ~= h.n0 or b ~= h.n1) then h.started = now
                elseif now - h.t0 > 2.5 then why = "the action did not start" end
            elseif idle then why = "action over"
            elseif now - h.t0 > (quick.STANCE[h.id] and 20.0 or 8.0) then why = "time limit" end
        end
        if why then quick.hold_end(addr, why); break end
    end
end
function quick.hold_end_all(why)
    for addr in pairs(quick.holds) do quick.hold_end(addr, why); if not next(quick.holds) then break end end
    for addr in pairs(quick.holds) do quick.hold_end(addr, why) end
end

local function quick_write(info)
    quick.last = info
    R.dump("DPC_quick.json", { n = quick.n, t = os.clock(), slot = info.slot, skill = info.skill,
        name = info.name, pawn = info.pawn, target = info.target, how = info.how, result = info.result, source = info.source })
end

local function quick_skill(slot, idx)
    -- v0.9.90: idx = an explicit party pawn (the selected one while another pawn is possessed)
    if coop.active or (state.active and idx == nil) then return end
    local party = get_party()
    local entry = nil
    for _, e in ipairs(party) do if e.idx == (idx or cfg.selected_pawn_idx) then entry = e end end
    if idx == nil then entry = entry or party[1] end
    if not entry then log_msg("Quick skill: no pawn"); return end
    local info = { slot = slot, pawn = entry.name }
    local pw = entry.chara
    if call(pw, "get_IsDead") or call(pw, "get_IsDown") then
        info.result = "pawn is down"; quick_write(info); log_msg("Quick skill: " .. entry.name .. " is down"); return
    end
    local id = entry.skills[slot] or 0
    info.skill = id
    info.name = (S.SKILL_NAMES and S.SKILL_NAMES[id]) or tostring(id)
    if id == 0 then info.result = "slot empty"; quick_write(info); log_msg("Quick skill: " .. entry.name .. " has nothing in slot " .. slot); return end
    local held = quick.holds[pw:get_address()]
    if held and held.id == id and quick.STANCE[id] then -- the stance is ordered again: end it
        quick.hold_end(pw:get_address(), "ordered again")
        pcall(function()
            -- 0.9.178-dev2 (from 0.9.177-dev1): not inside an object interaction (lean / sit / bathe: freeze, rule 24);
            -- the stance has already been let go above, the pawn's AI ends it once the interaction is over
            if R.busy_interact and R.busy_interact(pw) then R.abort_interact(pw); return end
            local ex = pw:call("get_AIDecisionMaker"):call("get_DecisionModule"):call("get_ActionInterface"):call("get_Executor")
            ex:call("forceEndAction")
        end)
        info.result = "stance ended"; quick_write(info); log_msg("Quick skill: " .. entry.name .. " leaves " .. info.name); return
    end
    local live = quick.game_def(pw, id)
    local def, pack_obj, pack_path, alt = nil, nil, nil, nil
    if live then
        def, pack_obj, pack_path, info.source = { live.path, live.kind }, live.obj, live.path, "game (live)"
    else
        local g = quick.table_def(id)
        if g then def, pack_obj, pack_path, alt, info.source = { g.path, g.kind }, g.obj, g.path, g.alt, "game (table)" end
    end
    if not def then info.result = "no pack for skill " .. id; quick_write(info); log_msg("Quick skill: no action pack known for skill " .. tostring(id)); return end
    local tgt, how
    if def[2] == "enemy" then
        tgt, how = quick_pick_enemy(pw)
        if not tgt and alt == "self" then tgt, how = pw, "self (no enemy)"
        elseif not tgt and alt == "player" then tgt, how = quick_arisen(), "Arisen (no enemy)" end
        -- v0.9.151 requested: with no enemy about the skill is still performed, on the spot (target = the pawn himself)
        if not tgt and cfg.quick_skill_no_target then tgt, how = pw, "self (no enemy about)" end
        if not tgt then info.result = "no enemy"; quick_write(info); log_msg("Quick skill: no enemy in view or near " .. entry.name); return end
    elseif def[2] == "self" then
        tgt, how = pw, "self"
    else
        tgt, how = quick_arisen(), "Arisen"
    end
    info.how = how
    info.target = tgt and tostring(call(tgt, "get_CharaIDString")) or "?"
    local ok, err = pcall(function()
        quick.exec = quick.exec or sdk.find_type_definition("app.AIBlackBoardExtensions"):get_method(
            "setBBValuesToExecuteActInter(app.AIBlackBoardController, app.ActInterPackData, app.AITarget)")
        local path = pack_path
        local u = pack_obj or quick.packs[path]
        if not u then u = sdk.create_userdata("app.ActInterPackData", path); quick.packs[path] = u end
        local bb = call(pw, "get_AIBlackBoardController")
        local at = quick_ai_target(pw, tgt)
        if not (u and bb and at) then error("pack/blackboard/target missing") end
        quick.exec:call(nil, bb, u, at)
        bb:call("set_ReqMainActInterPackData(app.ActInterPackData)", u)
        quick.last_addr, quick.last_t = pw:get_address(), os.clock()
        quick.hold_start(pw, id, entry.name)
    end)
    quick.n = quick.n + 1
    info.result = ok and "ordered" or ("error: " .. tostring(err))
    if not ok then dev_error("quick skill", err) end
    quick_write(info)
    log_msg(string.format("Quick skill %d: %s -> %s (%s, %s, %s)", slot, entry.name, info.name, info.target, info.result, tostring(info.source)))
end

-- v0.9.15 heal / revive and warp-to-me for the party, moved over from PawnCommander (its v2.4 code, which
-- which was played with). Every pawn; while a pawn is possessed, "me" is the possessed pawn and he isn't moved.
local function party_heal()
    local n = 0
    for _, e in ipairs(get_party()) do
        local ok = pcall(function()
            e.chara:call("recoverAll")
            if e.human then e.human:set_field("IsStartRecoverHpAndMaxHpCompletely", true) end
            local sm = e.chara:call("get_StaminaManager")
            if sm then sm:call("recoverAll") end
            if e.pawn then
                e.pawn:call("setPawnRevive", 0.0, false, false)
                e.pawn:call("cureAllScar")
            end
        end)
        if ok then n = n + 1 end
    end
    -- v0.9.80: the Arisen too (reported: it should heal the Arisen too and does not), unless switched off
    local ar_done = false
    if cfg.party_heal_arisen then
        ar_done = pcall(function()
            local ar = sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer")
            ar:call("recoverAll")
            local hu = ar:call("get_Human")
            if hu then hu:set_field("IsStartRecoverHpAndMaxHpCompletely", true) end
            local sm = ar:call("get_StaminaManager")
            if sm then sm:call("recoverAll") end
        end)
    end
    log_msg("Healed / revived " .. n .. " pawn" .. (n == 1 and "" or "s") .. (ar_done and " and the Arisen" or ""))
end

local WARP_RING = { { 1.8, 0.5, 0.0 }, { -1.8, 0.5, 0.0 }, { 0.0, 0.5, -2.0 }, { 0.0, 0.5, 2.0 } }
local warp_checks = {}

local function warp_ring(e, pos, slot)
    pcall(e.chara.call, e.chara, "warp(via.vec3, app.CharacterWarpOption)",
        Vector3f.new(pos.x + slot[1], pos.y + slot[2], pos.z + slot[3]), nil)
end

local function party_warp_to_me()
    -- v0.9.40: it is a keyboard command, so "me" is whoever the keyboard drives: the possessed pawn in normal
    -- possession, the Arisen in co-op. v0.9.41: in co-op player 2's pawn comes too (coop_warp_p2, default on).
    local me = (state.active and not coop.active and state.pawn_chara) or quick_arisen()
    local xf = me and call(me, "get_Transform")
    local pos = xf and call(xf, "get_Position")
    if not pos then log_msg("Warp: no position for you"); return end
    -- safeWarp wants the universal (double) position; get_Position() sent pawns to garbage coordinates (PawnCommander)
    local upos = call(xf, "get_UniversalPosition")
    local pm = sdk.get_managed_singleton("app.PawnManager")
    local i = 0
    for _, e in ipairs(get_party()) do
        if not (state.active and same_obj(e.chara, state.pawn_chara) and not (coop.active and cfg.coop_warp_p2)) then
            i = i + 1
            local slot = WARP_RING[(i - 1) % #WARP_RING + 1]
            local ok = upos and pm and pcall(pm.call, pm, "safeWarp(app.Character, via.Position)", e.chara, upos)
            if not ok then warp_ring(e, pos, slot) end
            warp_checks[#warp_checks + 1] = { e = e, t = os.clock() + 0.3, pos = Vector3f.new(pos.x, pos.y, pos.z), slot = slot }
        end
    end
    -- 0.9.177 (the tester: "7 key warp should warp the Arisen to us too by default if possessing a pawn")
    local ar = ""
    if state.active and not coop.active and cfg.party_warp_arisen ~= false and R.warp_arisen then
        if pcall(R.warp_arisen) then ar = " and the Arisen" end
    end
    log_msg("Warped " .. i .. " pawn" .. (i == 1 and "" or "s") .. ar .. " to you")
end

local function verify_warps()
    if #warp_checks == 0 then return end
    local now, keep = os.clock(), {}
    for _, w in ipairs(warp_checks) do
        if now < w.t then
            keep[#keep + 1] = w
        else
            local p = brain_pos(w.e.chara) and Vector3f.new(brain_pos(w.e.chara))
            local d = p and math.sqrt((p.x - w.pos.x) ^ 2 + (p.y - w.pos.y) ^ 2 + (p.z - w.pos.z) ^ 2)
            if not d or d ~= d or d > 60.0 then
                log_msg("Warp check failed for " .. tostring(w.e.name) .. " -> ring warp")
                warp_ring(w.e, w.pos, w.slot)
            end
        end
    end
    warp_checks = keep
end

-- v0.7.5: run the possessed pawn's PlayerInputProcessor inside the Arisen's app.Player.update, the point in the
-- frame where the game normally processes player input. (Defined after `native`; installed once at load.)
local function install_native_hook()
    local player_td = sdk.find_type_definition("app.Player")
    local player_upd = player_td and player_td:get_method("update")
    if player_upd then
        sdk.hook(
            player_upd,
            function(args)
                local pip = native.pip
                if not (state.active and pip and not native.failed and native.drive == "player") then return end
                native.hook_frames = native.hook_frames + 1
                if state.pawn_input and (field(state.pawn_input, "ButtonOnFlags") or 0) ~= 0 then
                    native.hook_input_frames = native.hook_input_frames + 1
                end
                if native.io_ran == R.io_frame then return end -- dev24: already run before the pawn's Human.update
                coop_target_tick()
                R.dash_keep(state.pawn_input)
                local ok, err = pcall(pip.call, pip, "update")
                native.frames = native.frames + 1
                if R.aim_point then R.aim_point() end
                if not ok then
                    native.errors = native.errors + 1
                    if native.errors >= 5 then native.failed = true end
                end
            end,
            function(retval) return retval end
        )
    end

end
install_native_hook()

-- v0.8.2: the brain's app.Player.update hook (registered after the native hook, so the possessed pawn's processor
-- has already run this frame when it fires):
--   * lock his lock-on onto the brain's target for the duration of app.Player.update (restored in the post-hook)
--   * while a pawn is possessed, run his PlayerInputProcessor ourselves: app.Player.update stops calling it during
--     possession (verified: 0 calls in 584 frames even with IsEnable true). Skipped if the game itself ran it in
--     the last 0.25 s, so it can never double-update.
local function install_brain_player_hook()
    local player_td = sdk.find_type_definition("app.Player")
    local player_upd = player_td and player_td:get_method("update")
    if not player_upd then return end
    sdk.hook(
        player_upd,
        function(args)
            if coop.active and state.arisen_chara then
                -- co-op: player 1's Arisen must keep his own controls even if app.Player.update skips his
                -- processor while a pawn is possessed (seen with the brain)
                if os.clock() - (brain.game_pip_t or 0) < 0.25 then return end
                local pip = state.arisen_pip
                if pip then
                    brain.self_driving = true
                    local ok, err = pcall(pip.call, pip, "update")
                    brain.self_driving = false
                    coop.driven = (coop.driven or 0) + 1
                    if not ok then coop.err = "drive: " .. tostring(err); dev_error("coop.drive", err) end
                end
                return
            end
            if not brain.on then return end
            brain_lock_apply()
            if state.active and brain.ar then
                if os.clock() - (brain.game_pip_t or 0) < 0.25 then return end
                local pip = call(brain.ar, "get_InputProcessor")
                if pip then
                    brain.self_driving = true
                    local ok, err = pcall(pip.call, pip, "update")
                    brain.self_driving = false
                    brain.driven = (brain.driven or 0) + 1
                    if not ok then
                        brain.errs = brain.errs + 1
                        brain.err = "drive: " .. tostring(err)
                    end
                end
            end
        end,
        function(retval)
            if brain.lock_swapped then brain_lock_restore() end
            if state.active then brain_restore_input() end
            return retval
        end
    )
end
install_brain_player_hook()

-- shared with the modules loaded after this one (see shared.lua)
S.native, S.native_release, S.native_build = native, native_release, native_build
S.coop_target_tick, S.native_tick, S.quick, S.quick_arisen = coop_target_tick, native_tick, quick, quick_arisen
S.quick_pick_enemy, S.quick_skill, S.party_heal = quick_pick_enemy, quick_skill, party_heal
S.party_warp_to_me, S.verify_warps = party_warp_to_me, verify_warps
