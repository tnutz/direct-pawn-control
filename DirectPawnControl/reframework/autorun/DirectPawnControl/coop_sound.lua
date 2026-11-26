-- Direct Pawn Control: co-op sound listener.
-- Part of DirectPawnControl.lua, which loads the files in this folder in order (this one is 24 of 26).
-- Never run on its own: REFramework only runs the files directly in reframework/autorun.
local S = require("DirectPawnControl/shared")
local cfg, R, log_msg, call, field, state, addr_of = S.cfg, S.R, S.log_msg, S.call, S.field, S.state, S.addr_of
local coop, native, coop_target_tick, start_possession = S.coop, S.native, S.coop_target_tick, S.start_possession
local coop_start = S.coop_start

-- ----------------------------------------------------------------------------
-- 0.9.172 co-op sound listener. With the camera pulled back to keep the players in view, sounds cut off hard (the tester,
-- 2026-11-20): also in classic co-op, where loudness is already worked out at the Arisen, so it is the distance from
-- the LISTENER (soundlib.SoundListener on MainCamera; Driver.getListenerPosition(0) = the camera's position) that
-- drops them. The listener is moved toward the players along the camera's line of sight, to pf_sound_ear_dist from the
-- middle of all players; its orientation (left / right) stays the camera's.
-- How the game reads SoundListener._Offset (world or camera space; or whether it reads it at all) is not known, so
-- the way is found in play: each candidate is tried for 20 frames while Driver.getListenerPosition is compared with
-- the target point; the first that lands within 1 m is kept. Candidates: _Offset in world space, _Offset in the
-- camera's space, then the component's own setListenerPosition(Transform, vec3) after its lateUpdate (world, camera
-- space). If none lands, nothing more is written ("no way found") and the offset is put back.
-- 0.9.172-dev6, from coop-sound-1 (2026-11-20): setListenerPosition(Transform, vec3) puts the listener AT the vec3
-- (an absolute position: an offset there sent it ~170 m off), and _Offset in camera space moved it the right
-- distance the opposite way (6.0 m off on a 3.1 m move). Candidates now: the setter with the target point, the
-- camera-space offset reversed, then the two that did not land, in case a camera angle tells them apart.
R.lis = { ways = { "set_abs", "off_local_neg", "off_world", "off_local" }, way_i = 1, found = nil, failed = false,
    n = 0, err_sum = 0.0, active = false, want = nil, errs = 0 }
R.lis_comp = function()
    local L = R.lis
    if L.comp and (os.clock() - (L.comp_t or 0)) < 5.0 then return L.comp end
    L.comp_t = os.clock()
    L.comp = nil
    pcall(function()
        local sm = sdk.get_native_singleton("via.SceneManager")
        local scene = sdk.call_native_func(sm, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
        local arr = scene:call("findComponents(System.Type)", sdk.typeof("soundlib.SoundListener"))
        local n = arr and (arr:call("get_Count") or arr:call("get_Length")) or 0
        for i = 0, n - 1 do
            local c = arr:call("get_Item", i)
            if c and (c:get_field("_ListenerIdx") or 0) == 0 then L.comp = c break end
        end
    end)
    return L.comp
end
R.lis_dot = function(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
-- every frame, before the game's update: where the listener should be (nil = leave it at the camera)
-- dev50 (the tester: "does split screen sound have options to play from a central spot vs P1 alone?"): while the Split
-- Screen add-on shows several views and its "Sound heard from" is "the middle of the players" (its cfg.sound_from 2,
-- the default), the listener sits right at the players' middle (no 5 m ear distance), facing as player 1's camera.
R.lis_split_mid = function()
    local SS = rawget(_G, "DPC_SplitScreen")
    return SS and SS.active and SS.cfg and (SS.cfg.sound_from or 2) == 2 or false
end
R.lis_target = function()
    local mid = R.lis_split_mid()
    if not ((cfg.coop_listener_move or mid) and R.world_now ~= false) then return nil end
    if not ((coop.active and state.active) or (R.cp and R.cp.on)) then return nil end
    local pl = R.players()
    local n, sx, sy, sz = 0, 0.0, 0.0, 0.0
    for _, ch in pairs(pl) do
        local okp, p = pcall(function() return ch:call("get_GameObject"):call("get_Transform"):call("get_Position") end)
        if okp and p then n = n + 1; sx, sy, sz = sx + p.x, sy + p.y, sz + p.z end
    end
    -- (players 3+ are in R.players)
    if n < 2 then return nil end
    local mx, my, mz = sx / n, sy / n + 1.5, sz / n
    local tr = R.primary_cam():call("get_GameObject"):call("get_Transform")
    local cp = tr:call("get_Position")
    local dx, dy, dz = mx - cp.x, my - cp.y, mz - cp.z
    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
    local base = mid and 0.0 or math.max(1.0, cfg.pf_sound_ear_dist or 5.0)
    if d <= base + 0.5 or d > 120.0 then return nil end -- close enough already; or the camera is somewhere else (a menu)
    local k = (d - base) / d
    local w = { x = dx * k, y = dy * k, z = dz * k } -- world offset from the camera
    return { w = w, wlen = d - base, cam = cp, tr = tr, ear = { x = cp.x + w.x, y = cp.y + w.y, z = cp.z + w.z }, d = d }
end
R.lis_local = function(tr, w)
    local ax, ay, az = tr:call("get_AxisX"), tr:call("get_AxisY"), tr:call("get_AxisZ")
    return Vector3f.new(R.lis_dot(w, ax), R.lis_dot(w, ay), R.lis_dot(w, az))
end
R.lis_way = function() local L = R.lis; return L.found or (not L.failed and L.ways[L.way_i]) or nil end
R.lis_pre = function(args) -- before SoundListener.lateUpdate
    local L = R.lis
    -- the component the game is updating right now (never a cached one that a load may have destroyed)
    local c = args and args[2] and sdk.to_managed_object(args[2]) or nil
    if not c then return end
    if (c:get_field("_ListenerIdx") or 0) ~= 0 then return end
    if L.comp_addr ~= c:get_address() then L.comp_addr, L.off0, L.wrote = c:get_address(), nil, false end
    L.comp = c
    local t, way = L.want, R.lis_way()
    if L.off0 == nil then local o = c:get_field("_Offset"); L.off0 = o and Vector3f.new(o.x, o.y, o.z) or Vector3f.new(0.0, 0.0, 0.0) end
    if not (t and way) then
        if L.wrote then c:set_field("_Offset", L.off0); L.wrote = false end
        return
    end
    if way == "off_world" then c:set_field("_Offset", Vector3f.new(t.w.x, t.w.y, t.w.z)); L.wrote = true
    elseif way == "off_local" then c:set_field("_Offset", R.lis_local(t.tr, t.w)); L.wrote = true
    elseif way == "off_local_neg" then
        local o = R.lis_local(t.tr, t.w)
        c:set_field("_Offset", Vector3f.new(-o.x, -o.y, -o.z)); L.wrote = true
    elseif L.wrote then c:set_field("_Offset", L.off0); L.wrote = false end
end
R.lis_post = function() -- after SoundListener.lateUpdate (the component its pre-hook saw this frame)
    local L = R.lis
    local c = L.comp
    local t, way = L.want, R.lis_way()
    if not (c and t and way) then return end
    if way == "set_abs" then
        c:call("setListenerPosition(via.Transform, via.vec3)", t.tr, Vector3f.new(t.ear.x, t.ear.y, t.ear.z))
    end
end
-- measured once a frame (the engine's listener may lag a frame: compared with last frame's target)
R.lis_measure = function()
    local L = R.lis
    local t = L.want_prev
    L.want_prev = L.want
    -- 0.9.172-dev6: loudness from the same point (the game works it out from the Arisen in classic co-op, so a far
    -- player's swings stayed quiet). Late in the frame, after the game wrote its own player position.
    if L.want and cfg.coop_listener_loudness then
        pcall(function()
            local d = R.pf_drv()
            d:get_method("set_CalcDistanceDecayAtPlayerPos(System.Boolean)"):call(nil, true)
            d:get_method("set_PlayerPositionForDistanceDecay(via.vec3)"):call(nil, Vector3f.new(L.want.ear.x, L.want.ear.y, L.want.ear.z))
            L.loud = true
        end)
    elseif L.loud then
        L.loud = false -- the game (or the played-pawn setting) writes its own point again from the next frame
    end
    if not t then return end
    local drv = R.pf_drv()
    local lp = drv and drv:get_method("getListenerPosition"):call(nil, 0)
    if not lp then return end
    local ex, ey, ez = lp.x - t.ear.x, lp.y - t.ear.y, lp.z - t.ear.z
    local err = math.sqrt(ex * ex + ey * ey + ez * ez)
    local cx, cy, cz = lp.x - t.cam.x, lp.y - t.cam.y, lp.z - t.cam.z
    L.err, L.from_cam = err, math.sqrt(cx * cx + cy * cy + cz * cz)
    if L.found or L.failed then
        if L.found and (t.wlen or 0) >= 3.0 then
            -- the way found keeps landing? (a camera lined up with the world's axes cannot tell world from camera
            -- space apart; it shows once the camera turns): 30 frames in a row off target -> find the way again
            if err > math.max(1.5, 0.15 * t.wlen) then L.bad_run = (L.bad_run or 0) + 1 else L.bad_run = 0 end
            if L.bad_run >= 30 then
                log_msg(string.format("Co-op sound: %s stopped landing (%.1f m off), finding the way again", L.found, err))
                L.drifts = (L.drifts or 0) + 1
                local was = L.found
                L.found, L.bad_run, L.n, L.err_sum, L.wsum = nil, 0, 0, 0.0, 0.0
                L.way_i = 1
                for i, w in ipairs(L.ways) do if w == was then L.way_i = (i % #L.ways) + 1 end end
                L.tried = { "(again after " .. was .. ")" }
                L.left = #L.ways -- tries before giving up
            end
        end
        return
    end
    -- a candidate that throws the listener far away is dropped at once (do not leave it there 20 frames)
    if err > 30.0 then L.n, L.err_sum = 19, err * 19 end
    -- only frames where the listener has to move a fair way tell the candidates apart
    if (t.wlen or 0) < 3.0 and err <= 30.0 then return end
    L.n, L.err_sum = L.n + 1, L.err_sum + err
    L.wsum = (L.wsum or 0.0) + t.wlen
    if L.n >= 20 then
        local avg = L.err_sum / L.n
        local wavg = L.wsum / L.n
        L.wsum = 0.0
        L.tried = L.tried or {}
        L.tried[#L.tried + 1] = string.format("%s %.1f of %.1f m", L.ways[L.way_i], avg, wavg)
        if avg < math.max(1.0, 0.15 * wavg) then
            L.found, L.left = L.ways[L.way_i], nil
            log_msg(string.format("Co-op sound: listener moved by %s (off by %.2f m on average)", L.found, avg))
        else
            L.way_i = L.way_i + 1
            if L.left then -- a second round after a drift: wraps round the list, each way once
                L.left = L.left - 1
                if L.way_i > #L.ways then L.way_i = 1 end
            end
            if (L.left and L.left <= 0) or (not L.left and L.way_i > #L.ways) then
                L.failed = true
                log_msg("Co-op sound: no way found to move the listener (" .. table.concat(L.tried, ", ") .. ")")
            end
        end
        L.n, L.err_sum = 0, 0.0
    end
end
R.lis_hook = function()
    local L = R.lis
    if L.hooked then return end
    L.hooked = true
    local td = sdk.find_type_definition("soundlib.SoundListener")
    local m = td and td:get_method("lateUpdate")
    if not m then L.hook_err = "SoundListener.lateUpdate not found"; return end
    sdk.hook(m, function(args)
        local ok, e = pcall(R.lis_pre, args)
        if not ok then L.errs = L.errs + 1; L.err_msg = tostring(e) end
    end, function(retval)
        local ok, e = pcall(R.lis_post)
        if not ok then L.errs = L.errs + 1; L.err_msg = tostring(e) end
        return retval
    end)
end
R.lis_tick = function() -- before UpdateBehavior, every frame
    local L = R.lis
    local okt, t = pcall(R.lis_target)
    L.want = okt and t or nil
    if not okt then L.target_err = tostring(t) end
    L.active = L.want ~= nil
    L.d = L.want and L.want.d or nil
    if (L.want or L.wrote) and (cfg.coop_listener_move or R.lis_split_mid()) then pcall(R.lis_hook) end
end
re.on_application_entry("LateUpdateBehavior", function() if R.lis.want or R.lis.want_prev then pcall(R.lis_measure) end end)
re.on_pre_application_entry("UpdateBehavior", function() pcall(R.lis_tick) end)
R.start_possession = start_possession
R.coop_start = coop_start
re.on_pre_application_entry("UpdateBehavior", function() pcall(R.possess_wait_tick) end)
re.on_pre_application_entry("UpdateBehavior", function() pcall(R.unlean_tick) end)
re.on_pre_application_entry("UpdateBehavior", function() if R.cancel_check then pcall(R.cancel_check_tick) end end)
re.on_pre_application_entry("UpdateBehavior", function() if R.cancel_pending then pcall(R.cancel_pending_tick) end end)
re.on_pre_application_entry("UpdateBehavior", function() if R.chant_t then local ok, e = pcall(R.chant_test_tick); if not ok then log_msg("chant_test error: " .. tostring(e)); R.chant_t = nil end end end)
re.on_pre_application_entry("UpdateBehavior", function() pcall(R.galv_tick) end) -- 0.9.178-dev2, actions.lua
re.on_pre_application_entry("UpdateBehavior", function() pcall(R.stale_dash_tick) end) -- 0.9.178-dev2, actions.lua

-- 0.9.177 the root of "a played pawn's controls feel slightly off" (chant cancel, combos, follow-ups, any vocation).
-- Measured on the test bench (order probe, 2026-11-24): every frame the ARISEN's PlayerInputProcessor.update runs
-- BEFORE his Human.update, so the processor sees last frame's AttackState / CustomSkillState / MoveState. For a played
-- pawn it runs AFTER the pawn's Human.update, which (DD2.exe 4.1, Human.update) copies those three into their Prev*
-- fields and resets them to 0 until the action graph sets them again later in the frame. So every input rule that
-- asks "is this character attacking / in a skill" got "no" on a played pawn: the game's own chant cancel
-- (isSkillCancelable needs AttackState == 3) never passed. Here: while a played pawn's processor runs, those three
-- fields hold last frame's values (the Prev* copies), exactly the Arisen's view; afterwards the reset value goes
-- back unless the processor changed the field itself.
R.pipfix_map = {}
R.pipfix_n = 0
R.PIPFIX_FIELDS = {
    { "<AttackState>k__BackingField", "<PrevAttackState>k__BackingField" },
    { "<CustomSkillState>k__BackingField", "<PrevCustomSkillState>k__BackingField" },
    { "MoveStateInternal", "<PrevMoveState>k__BackingField" },
}
function R.pipfix_tick()
    local m = {}
    if cfg.pawn_prev_state ~= false and not cfg.pawn_input_order then
        if state.active and native.pip and not native.failed and state.pawn_human then
            local a = addr_of(native.pip)
            if a and a ~= 0 then m[a] = state.pawn_human end
        end
        local function add(sl)
            if sl and sl.active and sl.pip and not sl.failed and sl.human then
                local a = addr_of(sl.pip)
                if a and a ~= 0 then m[a] = sl.human end
            end
        end
        add(R.s2)
        if R.np and R.np.slots then for _, sl in pairs(R.np.slots) do add(sl) end end
    end
    R.pipfix_map = m
end
function R.pipfix_install()
    local td = sdk.find_type_definition("app.PlayerInputProcessor")
    local m = td and td:get_method("update")
    if not m then log_msg("pawn input state fix: PlayerInputProcessor.update not found (game update?)"); return end
    sdk.hook(m, function(args)
        local hu = R.pipfix_map[sdk.to_int64(args[2])]
        if not hu then return end
        local hs = thread.get_hook_storage()
        local saved = {}
        local nf = (cfg.pawn_prev_move == false) and 2 or 3 -- 0.9.177-dev21: the move state can be left out (feel A/B)
        for i, f in ipairs(R.PIPFIX_FIELDS) do
            if i > nf then break end
            local cur, prev = hu:get_field(f[1]), hu:get_field(f[2])
            if type(cur) == "number" and type(prev) == "number" and cur ~= prev then
                hu:set_field(f[1], prev)
                saved[i] = { cur, prev }
            end
        end
        hs.pf_h, hs.pf_saved = hu, saved
    end, function(retval)
        local hs = thread.get_hook_storage()
        local hu, saved = hs and hs.pf_h, hs and hs.pf_saved
        if hu and saved then
            hs.pf_h, hs.pf_saved = nil, nil
            for i, sv in pairs(saved) do
                local f = R.PIPFIX_FIELDS[i][1]
                if hu:get_field(f) == sv[2] then hu:set_field(f, sv[1]) end -- unchanged by the processor: put the reset value back
            end
            R.pipfix_n = R.pipfix_n + 1
        end
        return retval
    end)
    log_msg("pawn input state fix: hooked PlayerInputProcessor.update")
end
pcall(R.pipfix_install)

-- 0.9.177-dev24 the root fix: run a played pawn's input where the Arisen's runs. Read live (agent bridge, 2026-11-24):
-- the Arisen and every pawn carry the same components in the same order (Character 6, ActionManager 7, Human 16);
-- the game runs a character's input processor from Character.update, so the Arisen's input sees his state before
-- his Human.update clears it. DPC runs a played pawn's processor from the Arisen's app.Player.update (component 91,
-- v0.7.5), which comes after the pawn's Human.update: the processor saw the cleared state, and dev5's fix put three
-- saved values back (the move state among them put targeting off, by the blind tests). Here the processor runs in a
-- pre-hook on the pawn's own Human.update instead, so it sees everything the Arisen's would, nothing faked; the
-- app.Player.update slot then skips that pawn for the frame. Main played pawn, player 2's pawn and players 3+.
R.io_frame, R.io_map, R.io_n = 0, {}, 0
R.io_tick = function()
    R.io_frame = R.io_frame + 1
    local m = {}
    if cfg.pawn_input_order and cfg.pawn_prev_state ~= false then
        if state.active and native.pip and not native.failed and native.drive == "player" and state.pawn_human then
            local a = addr_of(state.pawn_human)
            if a and a ~= 0 then m[a] = "main" end
        end
        local function add(sl)
            if sl and sl.active and sl.pip and not sl.failed and not sl.drive_pre and sl.human then
                local a = addr_of(sl.human)
                if a and a ~= 0 then m[a] = sl end
            end
        end
        add(R.s2)
        if R.np and R.np.slots then for _, sl in pairs(R.np.slots) do add(sl) end end
    end
    R.io_map = m
    R.io_any = next(m) ~= nil
end
R.io_run = function(e)
    if e == "main" then
        local pip = native.pip
        if not (state.active and pip and not native.failed) or native.io_ran == R.io_frame then return end
        native.io_ran = R.io_frame
        coop_target_tick()
        R.dash_keep(state.pawn_input)
        local ok, err = pcall(pip.call, pip, "update")
        native.frames = native.frames + 1
        if R.aim_point then R.aim_point() end
        if not ok then
            native.errors = native.errors + 1
            if native.errors >= 5 then native.failed = true end
        end
    else
        local s = e
        if not (s.active and s.pip and not s.failed) or s.io_ran == R.io_frame then return end
        s.io_ran = R.io_frame
        pcall(R.s2_target, s)
        R.s2_pre(s)
        local ok, err = pcall(s.pip.call, s.pip, "update")
        s.frames = s.frames + 1
        if not ok then
            s.errors = s.errors + 1
            s.err = tostring(err)
            if s.errors >= 5 then
                s.failed = true
                R.cp_event(R.cp_label(s.player or 2) .. "'s controls failed: " .. s.err)
            end
        end
    end
    R.io_n = R.io_n + 1
end
R.io_install = function()
    local td = sdk.find_type_definition("app.Human")
    local m = td and td:get_method("update")
    if not m then log_msg("pawn input order: Human.update not found (game update?)"); return end
    sdk.hook(m, function(args)
        if not R.io_any then return end -- the common path: one flag
        local e = R.io_map[sdk.to_int64(args[2])]
        if e then R.io_run(e) end
    end, function(r) return r end)
    log_msg("pawn input order: hooked Human.update")
end
pcall(R.io_install)

-- 0.9.177-dev25 (reported: "while I control the main pawn, the main pawn is definitely seeming to try to attack the
-- Arisen's target"; normal attacks "turn away from goblins half the time", Blink Strike to far targets). Read in
-- DD2.exe 4.1: every enemy's lock-on entry (app.LockOnTargetWork: DirectionFromPlayer, DistanceSQFromPlayer,
-- DistanceXZSQFromPlayer) is measured from LockOnTargetManager.calcPlayerPos, which reads CharacterManager.ManualPlayer
-- (+0x160, the Arisen) and adds 1.3 m. A played pawn's lock-on ranks and range-checks its candidates with those, so
-- it took enemies near and in front of the Arisen. For that one call, ManualPlayer is the played pawn (single
-- player only; in co-op player 1 is the Arisen). A spy the same day showed the pawn AI's attack commands
-- (actinter AttackBase.updateTarget and the rest) never ran on the played pawn: not the cause.
-- dev26: dev25 hooked only calcPlayerPos, which never ran in play (counter 0). The per-enemy pass,
-- LockOnTarget.updateWorks, reads ManualPlayer itself (the CharacterManager static, +0x160, its Transform +0x850) and
-- passes that position to each LockOnTargetWork.update. Both get the swap now.
R.lop_n, R.lop_calls = 0, {}
R.lop_pre = function(key)
    if not (cfg.pawn_lockon_from_pawn and state.active and not coop.active) then return end
    local pw = state.pawn_chara
    if not pw then return end
    local cm = R.lop_cm
    if not cm then cm = sdk.get_managed_singleton("app.CharacterManager"); R.lop_cm = cm end
    if not cm then return end
    local cur = cm:get_field("<ManualPlayer>k__BackingField")
    if not cur or cur:get_address() == pw:get_address() then return end
    cm:set_field("<ManualPlayer>k__BackingField", pw)
    local hs = thread.get_hook_storage()
    hs.lop_cm, hs.lop_cur, hs.lop_key = cm, cur, key
end
R.lop_post = function(retval)
    local hs = thread.get_hook_storage()
    local cm, cur = hs and hs.lop_cm, hs and hs.lop_cur
    if cm and cur then
        cm:set_field("<ManualPlayer>k__BackingField", cur)
        R.lop_n = R.lop_n + 1
        local k = hs.lop_key or "?"
        R.lop_calls[k] = (R.lop_calls[k] or 0) + 1
        hs.lop_cm, hs.lop_cur, hs.lop_key = nil, nil, nil
    end
    return retval
end
R.lop_install = function()
    local hooked = 0
    -- dev27: counted live, neither calcPlayerPos nor updateWorks is ever entered as a call (both are inlined);
    -- LockOnTarget.lateUpdate (each enemy, every frame) and LockOnTargetManager.update (once a frame) are, and
    -- LockOnTargetWork.update(vec3) under them. The swap covers those two.
    for _, e in ipairs({ { "app.LockOnTargetManager", "calcPlayerPos" }, { "app.LockOnTarget", "updateWorks" },
                         { "app.LockOnTarget", "lateUpdate" }, { "app.LockOnTargetManager", "update" } }) do
        local td = sdk.find_type_definition(e[1])
        local m = td and td:get_method(e[2])
        if m then
            local key = e[2]
            sdk.hook(m, function(args) R.lop_pre(key) end, R.lop_post)
            hooked = hooked + 1
        else
            log_msg("lock-on from the pawn: " .. e[1] .. "." .. e[2] .. " not found (game update?)")
        end
    end
    log_msg("lock-on from the pawn: " .. hooked .. " hook(s)")
end
pcall(R.lop_install)

-- 0.9.177-dev31 pilot (hooks installed only once it is switched on): the played pawn is "the player" for its own code (cfg.pawn_player_identity, off by default).
-- Player-identity audit (claude/player-identity-audit.md, tools/audit): 316 methods in DD2.exe 4.1 compare something
-- with CharacterManager.ManualPlayer right after reading it ("am I the player?"), the rest only use the player as a
-- reference point. The ones below run for one character (the played pawn's input processor, movement selector,
-- actions, hit controller, stamina / catch / door controllers, its Human); while one of them runs FOR the played pawn,
-- ManualPlayer is the pawn and is put back right after (the dev27 swap, scoped). Not swapped, on purpose: the world
-- around the player (weather, fog, terrain loading, spawning), quests, talk, menus and the pawns' AI. Single player
-- only (in co-op player 1 is the Arisen). Each hook counts its swaps (R.pid.n) so a hook that is never entered
-- (inlined) shows as 0 (debugging lesson 4).
R.PID_TARGETS = {
    -- input: left out, decided 2026-11-24 ("we need our own quick items handler to be able to use curatives the way we
    -- want"). PlayerInputProcessor.update's player branch runs the game's own D-pad item shortcuts
    -- (ItemShortcutProcessor.update); DPC's quick items (R.item_tick) stay the only ones for a played pawn.
    input = {},
    move = { { "app.HumanActionSelector", "requestLocomotionImpl" }, { "app.HumanActionSelector", "requestEndUpperBodyLivOrRolOnRun" },
             { "app.HumanNormalLocomotionAction", "updateSpeedUpOnStartDash" }, { "app.HumanStrafeAction", "update" },
             { "app.HumanStrafeAction", "isRunSpeed" }, { "app.HumanPreventFallController", "updatePreventFallSetting" },
             { "app.StartClimbLadder", "update" }, { "app.StartClimbRope", "update" }, { "app.PrepareSpringboard", "update" },
             { "app.DodgeOfRing", "update" }, { "app.HumanInterruptActionRequester", "processLandingAction" },
             { "app.HumanStaminaController", "calcAdditionalConsumeFactorByEquipment" }, { "app.HumanStaminaController", "callStaminaSE" } },
    spell = { { "app.HumanPrepareSpell", "updateStatusForPlayer" }, { "app.HumanPrepareSpell", "checkAttackRange" },
              { "app.HumanPrepareSpell", "getSpellEffectOffset" }, { "app.HumanReadySpell", "updateStatusForPlayer" },
              { "app.HumanReadySpell", "getSpellEffectOffset" }, { "app.CastFrigor", "calcTargetPosition" },
              { "app.CastFirestorm", "update" }, { "app.CastFirestorm", "updateStatusOnPlayer" }, { "app.HumanCastMagicBook", "createShell" },
              { "app.CharacterAction", "createShellRequestInfo" }, { "app.JobMagicUserNormalShot", "requestShell" },
              { "app.Job03ActionController", "updateSpellBreakPos" } },
    skill = { { "app.JobArcherArrowShooter", "setup" }, { "app.JobArcherArrowShooter", "shoot" },
              { "app.Job02DashJumpShootFullBodyAction", "start" }, { "app.Job02FullBlast", "updateShoot" }, { "app.Job02PrepareFullBend", "start" },
              { "app.Job02ReadyFullBlast", "start" }, { "app.Job02ShootHeavyRain", "start" }, { "app.Job02_PrepareMeteorShot", "start" },
              { "app.Job02_PrepareMeteorShot", "end" }, { "app.Job04CastSnatch", "onAttackCheckHit" }, { "app.Job04CreateShell", "execute" },
              { "app.Job05CanFinishingMove", "start" }, { "app.Job05ParryController", "setup" }, { "app.Job05ScarletVowController", "start" },
              { "app.Job07DragonStingerCommon", "isTargetPress" }, { "app.Job07GungnirShoot", "start" }, { "app.Job07PsychoShoot", "getTargetPosition" },
              { "app.Job07QuickShield", "addList" }, { "app.Job08ActionController", "setup" }, { "app.Job08ChangeArrow", "update" },
              { "app.Job08HumanShootArrowAim", "start" }, { "app.Job08ReadySeriesArrow", "start" }, { "app.Job08SeriesArrowShootArrow", "start" },
              { "app.Job09ActionController", "setup" }, { "app.Job09CastAttackSmoke", "onAttackHit" }, { "app.Job09CreateShell", "execute" },
              { "app.Job09PrepareSmokeGiants", "getTargetPos" } },
    combat = { { "app.HitController", "checkGuard" }, { "app.HitController", "checkGuardBit" }, { "app.HitController", "checkQuickShield" },
               { "app.HitController", "checkAttackCollisionHit" }, { "app.HitController", "requestCollider" }, { "app.HitController", "requestSeqCollider" },
               { "app.HitController", "setDamageReaction" }, { "app.GuardSuccess", "start" }, { "app.GuardBreak", "start" },
               { "app.HumanJustGuardSuccess", "start" }, { "app.CommonDamageReaction", "setDamageReaction" },
               { "app.CommonDamageReaction", "checkForFinishingMove" }, { "app.CommonDamageReaction", "setDieReaction" },
               { "app.DamageDownDamage", "start" }, { "app.DamageShirnkAir", "getShrinkType" }, { "app.DamageRagdollBlow", "onBumpCommon" },
               { "app.HumanCatchProcessor", "isEnableFinishingMoveCharacter" }, { "app.HumanCatchProcessor", "processFinishingMove" },
               { "app.HumanCatchProcessor", "startHoldDown" }, { "app.ChangeActionOnAttackHit", "Hit_AttackHitHandler" },
               -- dev36 (decided: "a pawn should be able to hit friendly and neutral characters where appropriate just like
               -- the arisen"): the Arisen's rules for hitting friends / neutrals, on the played pawn's own Human
               { "app.Human", "isEnableFriendOrNeutralHitCommon" }, { "app.Human", "Hit_AtkCalcDamageEndHandlerOnParty" } },
    interact = { { "app.OpenDoorController", "update" }, { "app.OpenDoorController", "processDoor" }, { "app.OpenDoorController", "calcResults" },
                 { "app.Human", "Chara_CanInteractHandler" }, { "app.Character", "updateStandGimmick" } },
    human = { { "app.Human", "update" }, { "app.Human", "lateUpdate" } },
    -- dev35 feedback to the human (tools/audit/identity_status_4.1.0.0.md): "the player" here means whoever the human
    -- plays, whichever character the call is for. ManualPlayer is the played pawn for the whole call, so the Arisen's
    -- calls take the non-player path (no feedback) and the pawn's take the player path. any = true: no owner check.
    feedback = { { "app.DepthOcclusionController", "update", any = true }, { "app.BrineEffectGenerator", "callPadSE", any = true },
                 { "app.ActionShakeReticleController", "start", any = true }, { "app.Player", "statusConditionVibration", any = true },
                 { "app.VibrationRequestAction", "start", any = true }, { "app.ResetCameraToLockOnTarget", "setCameraAngle", any = true },
                 { "app.HumanDisableGetUpCommon", "callUIEffectIfNeeded", any = true } },
}
R.pid = { on = false, pawn = 0, human = 0, sel = 0, pip = 0, cache = {}, n = {}, hooked = 0, missing = {} }
R.PID_CHARA_FIELDS = { "Chara", "<Chara>k__BackingField", "<Character>k__BackingField", "<CachedCharacter>k__BackingField" }
R.PID_HUMAN_FIELDS = { "Human", "<Human>k__BackingField" }
R.pid_owns = function(a)
    local P = R.pid
    if a == P.pawn or a == P.human or a == P.sel or a == P.pip then return true end
    local okr, res = pcall(function()
        local o = sdk.to_managed_object(a)
        if not o then return false end
        for _, f in ipairs(R.PID_CHARA_FIELDS) do
            local v = o:get_field(f)
            if v then return v:get_address() == P.pawn end
        end
        for _, f in ipairs(R.PID_HUMAN_FIELDS) do
            local v = o:get_field(f)
            if v then return v:get_address() == P.human end
        end
        return false
    end)
    return okr and res or false
end
R.pid_tick = function()
    local P = R.pid
    if cfg.pawn_player_identity and not P.installed then P.installed = true; pcall(R.pid_install) end
    local on = cfg.pawn_player_identity and state.active and not coop.active and not (R.cp and R.cp.on) and state.pawn_chara ~= nil
    P.on = on and true or false
    if not P.on then return end
    -- the swap changes a field the whole game reads: only ever on the main (script) thread (thread.get_id, REFramework)
    if thread.get_id then P.tid = thread.get_id() end
    local pw = addr_of(state.pawn_chara) or 0
    if pw ~= P.pawn then P.pawn, P.cache = pw, {} end
    P.human = state.pawn_human and addr_of(state.pawn_human) or 0
    P.sel = state.pawn_sel_addr or 0
    P.pip = native.pip and addr_of(native.pip) or 0
    if not P.cm then P.cm = sdk.get_managed_singleton("app.CharacterManager") end
end
R.pid_install = function()
    local P = R.pid
    for grp, list in pairs(R.PID_TARGETS) do
        for _, e in ipairs(list) do
            local td = sdk.find_type_definition(e[1])
            local m = td and td:get_method(e[2])
            if m then
                local key = e[1]:gsub("^app%.", "") .. "." .. e[2]
                local any = e.any
                P.n[key] = 0
                sdk.hook(m, function(args)
                    if not P.on or (cfg.pid_groups and cfg.pid_groups[grp] == false) then return end
                    if P.tid and thread.get_id() ~= P.tid then P.off_thread = (P.off_thread or 0) + 1; return end
                    if not any then
                        local a = sdk.to_int64(args[2])
                        local c = P.cache[a]
                        if c == nil then c = R.pid_owns(a); P.cache[a] = c end
                        if not c then return end
                    end
                    local cm = P.cm
                    if not cm then return end
                    local cur = cm:get_field("<ManualPlayer>k__BackingField")
                    if not cur or cur:get_address() == P.pawn then return end -- already swapped further up the stack
                    cm:set_field("<ManualPlayer>k__BackingField", state.pawn_chara)
                    local hs = thread.get_hook_storage()
                    hs.pid_cur = cur
                    P.n[key] = P.n[key] + 1
                end, function(retval)
                    local hs = thread.get_hook_storage()
                    local cur = hs and hs.pid_cur
                    if cur then
                        hs.pid_cur = nil
                        pcall(P.cm.set_field, P.cm, "<ManualPlayer>k__BackingField", cur)
                    end
                    return retval
                end)
                P.hooked = P.hooked + 1
            else
                P.missing[#P.missing + 1] = e[1] .. "." .. e[2]
            end
        end
    end
    log_msg(string.format("player identity pilot: %d hooks, %d not found%s", P.hooked, #P.missing,
        #P.missing > 0 and (" (" .. table.concat(P.missing, ", ") .. ")") or ""))
end
re.on_pre_application_entry("UpdateBehavior", function() pcall(R.pid_tick) end)
re.on_pre_application_entry("UpdateBehavior", function() pcall(R.io_tick) end)

-- 0.9.177 (the tester: "the native pickup prompt still shows, and I think applies, when the script-controlled Arisen walks
-- near loot and conversations"). The game computes its interact prompt for the player character in
-- InteractManager.updateHighestPriorityObjectForPlayer, gated by isEnablePlayerInteract (its only caller, DD2.exe 4.1).
-- While a pawn is played in single player, that gate answers false: no prompt, and the interact button can't make the
-- Arisen loot, talk or examine. DPC's own pawn prompt doesn't use it. In co-op the Arisen is player 1's, so it stays.
function R.arisen_interact_install()
    local td = sdk.find_type_definition("app.InteractManager")
    local m = td and td:get_method("isEnablePlayerInteract")
    if not m then log_msg("Arisen interact block: isEnablePlayerInteract not found (game update?)"); return end
    sdk.hook(m, nil, function(retval)
        if state.active and not coop.active and cfg.arisen_no_interact ~= false then return sdk.to_ptr(0) end
        return retval
    end)
end
pcall(R.arisen_interact_install)
re.on_pre_application_entry("UpdateBehavior", function() pcall(R.pipfix_tick) end)

-- 0.9.177-dev4 (dev): order probe hooks. Only active while R.op is set (a few seconds); one integer compare otherwise.
function R.op_install()
    local function who(addr_h)
        local ph = state.pawn_human and addr_of(state.pawn_human)
        if ph and addr_h == ph then return "pawn" end
        local ah = R.op and R.op.arisen_h
        if ah and addr_h == ah then return "Arisen" end
        return nil
    end
    local function note(kind, name, extra)
        local o = R.op
        o.seq = o.seq + 1
        local f = R.op_frame or 0
        local row = o.rows[f] or {}
        o.rows[f] = row
        row[#row + 1] = string.format("%s:%s%s#%d", name, kind, extra or "", o.seq)
    end
    local tdh = sdk.find_type_definition("app.Human")
    local mh = tdh and tdh:get_method("update")
    if mh then
        sdk.hook(mh, function(args)
            local o = R.op
            if not o or os.clock() > o.until_t then return end
            local h = sdk.to_int64(args[2])
            local w = who(h)
            if w then
                local hu = sdk.to_managed_object(args[2])
                note("Human.update", w, "(atk " .. tostring(field(hu, "<AttackState>k__BackingField")) .. ")")
            end
        end, function(r) return r end)
    end
    local tdp = sdk.find_type_definition("app.PlayerInputProcessor")
    local mp = tdp and tdp:get_method("update")
    if mp then
        sdk.hook(mp, function(args)
            local o = R.op
            if not o or os.clock() > o.until_t then return end
            local this = sdk.to_int64(args[2])
            local w = (native.pip and this == addr_of(native.pip)) and "pawn" or "Arisen" -- the only other pip outside co-op
            if w then
                local hu = (w == "pawn") and state.pawn_human or nil
                if w == "Arisen" and o.arisen_h then hu = sdk.to_managed_object(o.arisen_h) end
                note("pip.update", w, hu and ("(atk " .. tostring(field(hu, "<AttackState>k__BackingField")) .. ")") or "")
            end
        end, function(r) return r end)
    end
    re.on_pre_application_entry("UpdateBehavior", function()
        local o = R.op
        if not o then return end
        R.op_frame = (R.op_frame or 0) + 1
        if not o.arisen_h then
            pcall(function()
                local cm = sdk.get_managed_singleton("app.CharacterManager")
                local pl = cm and call(cm, "get_ManualPlayer")
                local hu = pl and call(pl, "get_Human")
                o.arisen_h = hu and addr_of(hu)
            end)
        end
        if os.clock() > o.until_t then
            local keys = {}
            for f in pairs(o.rows) do keys[#keys + 1] = f end
            table.sort(keys)
            log_msg(string.format("order probe: %d frames (played pawn: %s)", #keys, tostring(state.active and state.pawn_name)))
            for i, f in ipairs(keys) do
                if i > 12 then break end
                log_msg("order probe f" .. f .. ": " .. table.concat(o.rows[f], "  "))
            end
            R.op = nil
        end
    end)
end
if R.dev then pcall(R.op_install) end

-- 0.9.176-dev11 the root of "the pawn's buttons are the Arisen's". The game builds a character's input flags in
-- CharacterInput.processPadAssign: every binding of a pressed button (L2 = Sheathe, Draw, ActCancel, AimHold ...)
-- goes through CustomizeButtonTriggerHandler, which is the owner's PlayerInputProcessor.customizeButtonTrigger, and
-- that processor keeps what fits ITS vocation and state (a chanting mage keeps ActCancel). DPC mirrors the Arisen's
-- flags onto the played pawn, so they were always filtered by the Arisen's job: a played mage couldn't cancel, a
-- played archer couldn't aim with a non-bow Arisen, and any vocation added by another mod depends on luck.
-- While a pawn is played (single player), the Arisen's call runs on the pawn's processor instead, so the flags are
-- the ones the game would build if the pawn were the player. The Arisen's own processor is muted meanwhile anyway.
R.cbt = { src = 0, dst = 0, log = true, seen = {}, n = 0 }
R.cbt_tick = function()
    local c = R.cbt
    if cfg.exp_pawn_cbt and state.active and not coop.active and native.pip and not native.failed
        and state.arisen_pip_addr and state.arisen_pip_addr ~= 0 then
        c.src, c.dst = state.arisen_pip_addr, addr_of(native.pip) or 0
    else
        c.src, c.dst = 0, 0
    end
end
if R.dev then -- dev builds only (experiment, off by default)
    local td = sdk.find_type_definition("app.PlayerInputProcessor")
    local m = td and td:get_method("customizeButtonTrigger(System.UInt64, System.UInt64, via.hid.GamePadButton, System.Collections.Generic.IReadOnlyList`1<app.CharacterPadAssign.Info>)")
    m = m or (td and td:get_method("customizeButtonTrigger"))
    if m then
        sdk.hook(m, function(args)
            local c = R.cbt
            if c.src == 0 then return end
            local this = sdk.to_int64(args[2])
            if this ~= c.src or c.dst == 0 then return end
            args[2] = sdk.to_ptr(c.dst)
            if c.log and c.n < 300 then
                local hs = thread.get_hook_storage()
                hs.a, hs.b, hs.btn = sdk.to_int64(args[3]), sdk.to_int64(args[4]), sdk.to_int64(args[5]) & 0xFFFFFFFF
                hs.on = true
            end
        end, function(retval)
            local c = R.cbt
            if c.log and c.n < 300 and c.src ~= 0 then
                local hs = thread.get_hook_storage()
                if hs and hs.on then
                    hs.on = false
                    local r = sdk.to_int64(retval)
                    local k = string.format("%x|%x|%x|%x", hs.a, hs.b, hs.btn, r)
                    if not c.seen[k] then
                        c.seen[k] = true
                        c.n = c.n + 1
                        log_msg(string.format("cbt job%s: a=%x b=%x btn=%x -> %x", tostring(state.pawn_job), hs.a, hs.b, hs.btn, r))
                    end
                end
            end
            return retval
        end)
        log_msg("Pawn input by the pawn's vocation: hooked customizeButtonTrigger")
    else
        log_msg("Pawn input by the pawn's vocation: customizeButtonTrigger not found (game update?)")
    end
end
re.on_pre_application_entry("UpdateBehavior", function() pcall(R.cbt_tick) end)

-- 0.9.176-dev13 probe: does the played pawn's processor ever take the game's cancel path? For 1.5 s after an L2
-- press during a skill, log every call (with its result) to the methods the game uses to cancel a skill.
R.cprobe = { until_t = 0, n = 0 }
if R.dev then -- dev builds only
    local function probe(tn, sig, label)
        local td = sdk.find_type_definition(tn)
        local m = td and td:get_method(sig)
        if not m then log_msg("cancel probe: " .. tn .. "." .. sig .. " not found"); return end
        sdk.hook(m, function(args)
            if os.clock() > R.cprobe.until_t then return end
            local hs = thread.get_hook_storage()
            hs.cp_this = sdk.to_int64(args[2])
            hs.cp_a = args[3] and sdk.to_int64(args[3]) or nil
        end, function(retval)
            if os.clock() > R.cprobe.until_t or R.cprobe.n > 200 then return retval end
            local hs = thread.get_hook_storage()
            if not hs or not hs.cp_this then return retval end
            R.cprobe.n = R.cprobe.n + 1
            local who = (native.pip and hs.cp_this == addr_of(native.pip)) and "pawn pip"
                or (hs.cp_this == state.arisen_pip_addr) and "Arisen pip" or string.format("%x", hs.cp_this)
            log_msg(string.format("cancel probe: %s by %s arg=%s -> %s", label, who,
                hs.cp_a and string.format("%x", hs.cp_a) or "-", tostring(sdk.to_int64(retval) & 0xFF)))
            hs.cp_this = nil
            return retval
        end)
    end
    probe("app.PlayerInputProcessor", "processCancelSkill", "processCancelSkill")
    probe("app.PlayerInputProcessorDetail", "acceptCancel", "acceptCancel")
    probe("app.PlayerInputProcessorDetail", "isSkillCancelableMagic", "isSkillCancelableMagic")
    probe("app.PlayerInputProcessorDetail", "isSkillCancelable", "isSkillCancelable")
    -- dev2: the exact values isSkillCancelable reads (DD2.exe 4.1), read inside the call: Detail.Param.Human.AttackState
    -- must be 3 (Skill) and Character.EachTempStatus.PrevData bit 38 (PrepareSkill) set. Job03 first checks two action
    -- hashes. Logged once per L2 press window.
    do
        local td = sdk.find_type_definition("app.PlayerInputProcessorDetail")
        local m = td and td:get_method("isSkillCancelable")
        if m then
            sdk.hook(m, function(args)
                if os.clock() > R.cprobe.until_t or (R.cprobe.vals or 0) > 6 then return end
                pcall(function()
                    local det = sdk.to_managed_object(args[2])
                    local hu = field(field(det, "Param"), "Human")
                    local ch = hu and field(hu, "<Chara>k__BackingField")
                    local ts = ch and field(ch, "<EachTempStatus>k__BackingField")
                    local d, pd = ts and field(ts, "Data") or 0, ts and field(ts, "PrevData") or 0
                    local am = ch and field(ch, "<ActionManager>k__BackingField")
                    local h1 = am and call(am, "getCurrentActionHash", 1)
                    R.cprobe.vals = (R.cprobe.vals or 0) + 1
                    log_msg(string.format("in isSkillCancelable: pawn=%s AttackState=%s PrevData38=%d Data38=%d Data37=%d L1hash=%x",
                        tostring(ch and state.pawn_chara and addr_of(ch) == addr_of(state.pawn_chara)), tostring(field(hu, "<AttackState>k__BackingField")),
                        (pd >> 38) & 1, (d >> 38) & 1, (d >> 37) & 1, (h1 or 0) & 0xFFFFFFFF))
                end)
            end, function(r) return r end)
        end
    end
    probe("app.Job03InputProcessor", "isSkillCancelable", "Job03.isSkillCancelable")
    probe("app.PlayerInputProcessor", "processSheathe", "processSheathe")
    probe("app.HumanActionSelector", "requestSheatheWeapon", "requestSheatheWeapon")
end

R.pf_restore_all = function(why)
    pcall(function() -- 0.9.172: the listener's offset back (not during a load: the object may be gone; a new one starts clean)
        local L = R.lis
        local loading = tostring(why or ""):find("loading") ~= nil
        if L.wrote and L.comp and L.off0 and not loading and sdk.is_managed_object(L.comp) then L.comp:set_field("_Offset", L.off0) end
        L.wrote = false
        if loading then L.comp, L.comp_addr = nil, nil end
        L.want, L.want_prev = nil, nil
    end)
    pcall(R.pf_voice_restore, why)
    pcall(R.pf_listener_tick, nil)
    if R.mp_swapped then -- a window left open (should not happen): put the Arisen back
        local sw = R.mp_swapped
        R.mp_swapped = nil
        pcall(sw.cm.set_field, sw.cm, R.MP_FIELD, sw.old)
    end
end
re.on_pre_application_entry("UpdateBehavior", function() pcall(R.pf_tick) end)
re.on_application_entry("LateUpdateBehavior", function() pcall(R.pf_listener_pos) end)
