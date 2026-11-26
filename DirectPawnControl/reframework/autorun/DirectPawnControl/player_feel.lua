-- Direct Pawn Control: whoever you play is the player: sound, hit-stop, big-kill slow motion.
-- Part of DirectPawnControl.lua, which loads the files in this folder in order (this one is 23 of 26).
-- Never run on its own: REFramework only runs the files directly in reframework/autorun.
local S = require("DirectPawnControl/shared")
local cfg, R, log_msg, state, coop = S.cfg, S.R, S.log_msg, S.state, S.coop

-- ----------------------------------------------------------------------------
-- v0.9.170 (dev, untested) "Whoever you play is the player": sound, hit-stop and the big-kill slow-motion.
-- See claude/dpc-player-feel-plan.md. Approach B (per-character settings: the Wwise sound settings) and C (scoped
-- swaps: the game's "who is the player" field, CharacterManager.<ManualPlayer>k__BackingField, is set to the played
-- pawn only for the length of one game call, then put back; the method DD2PartySwitcher uses, reused with credit).
-- Never the full swap (A): PartySwitcher's full swap logged 8+ crashes and DPC's own Mode 3 swap crashed.
-- Every part is its own switch (cfg.pf_*) so a test can turn them on one at a time; all off = 0.9.169.
-- ----------------------------------------------------------------------------
R.pf = { n = {}, hooked = {} }
R.pf_played = function() -- the character one player plays alone (not co-op: there player 1 still plays the Arisen)
    if state.active and not coop.active and state.pawn_chara and state.arisen_chara then return state.pawn_chara end
    return nil
end
R.pf_count = function(k)
    if not cfg.pf_scope_log then return end
    local n = R.pf.n
    n[k] = (n[k] or 0) + 1
end

-- Scoped ManualPlayer swap. While one is open R.mp_swapped holds the real player; a nested call (one of these game
-- methods calling another) does not swap again. DPC's own code that must know the real Arisen during a window
-- calls R.real_player().
R.MP_FIELD = "<ManualPlayer>k__BackingField"
R.real_player = function()
    if R.mp_swapped then return R.mp_swapped.old end
    local cm = sdk.get_managed_singleton("app.CharacterManager")
    return cm and cm:call("get_ManualPlayer")
end
R.mp_pre = function(key)
    local st = thread.get_hook_storage()
    st.mp = nil
    if R.mp_swapped then return end
    local p = R.pf_played()
    if not p then return end
    local cm = sdk.get_managed_singleton("app.CharacterManager")
    if not cm then return end
    local old = cm:get_field(R.MP_FIELD)
    -- only when the game's player is the Arisen we know (never stack on someone else's swap)
    if not old or old:get_address() ~= state.arisen_chara:get_address() then return end
    cm:set_field(R.MP_FIELD, p)
    R.mp_swapped = { cm = cm, old = old, key = key }
    st.mp = true
    R.pf_count(key)
end
R.mp_post = function(retval)
    local st = thread.get_hook_storage()
    if st and st.mp then
        st.mp = nil
        local sw = R.mp_swapped
        R.mp_swapped = nil
        if sw then pcall(sw.cm.set_field, sw.cm, R.MP_FIELD, sw.old) end
    end
    return retval
end
-- hooks are installed the first time their switch is on, and stay (they do nothing while it is off)
R.pf_hook_group = function(group, list, cfg_key)
    if R.pf.hooked[group] then return end
    R.pf.hooked[group] = {}
    for _, e in ipairs(list) do
        local td = sdk.find_type_definition(e[1])
        local m = td and td:get_method(e[2])
        if m then
            local key = e[1]:gsub("^app%.", "") .. "." .. e[2]:gsub("%(.*", "")
            local ok = pcall(sdk.hook, m, function(args)
                if cfg[cfg_key] then R.mp_pre(key) end
            end, R.mp_post)
            R.pf.hooked[group][#R.pf.hooked[group] + 1] = key .. (ok and "" or " (hook failed)")
        else
            R.pf.hooked[group][#R.pf.hooked[group] + 1] = e[1] .. "." .. e[2] .. " (not found)"
        end
    end
    log_msg("Player feel: " .. group .. " hooks: " .. table.concat(R.pf.hooked[group], ", "))
end
R.PF_HOOKS = {
    space = { { "app.SoundSpaceManager", "updateFieldAIArea" }, { "app.SoundSpaceManager", "updateSemiEnvPhase1" },
              { "app.SoundSpaceManager", "<updateGlobalParam>g__updatePlayerPosY|259_0" } },
    hitstop = { { "app.HitController", "getHitStopTime" } },
    slow = { { "app.Ch200000", "isEnableWorldSlow" }, { "app.Ch200000", "checkDieWorldSlow" },
             { "app.Ch200000", "requestDieWorldSlow" }, { "app.Ch261000", "isEnableWorldSlow" },
             { "app.Ch255000", "callDieWorldSlow" } },
}

-- Sound part 1: the Wwise sound settings of a character (category Player / Pawn, its RTPC, "treated as player").
R.pf_wc = function(chara)
    local go = chara and chara:call("get_GameObject")
    return go and go:call("getComponent(System.Type)", sdk.typeof("app.WwiseCharacter"))
end
R.pf_wc_get = function(w)
    return { w:call("get_CharacterCategory"), w:call("get_CharacterRTPC"), w:call("get_IsRTPCTreatedAsPlayer") }
end
R.pf_wc_set = function(w, v)
    w:call("set_CharacterCategory", v[1])
    w:call("set_CharacterRTPC", v[2] + 0.0)
    w:call("set_IsRTPCTreatedAsPlayer", v[3])
end
R.pf_voice_restore = function(why)
    local v = R.pf.voice
    if not v then return end
    R.pf.voice = nil
    pcall(R.pf_wc_set, v.wa, v.a)
    pcall(R.pf_wc_set, v.wp, v.p)
    log_msg("Player feel: sound settings back (" .. tostring(why) .. ")")
end
R.pf_voice_tick = function(p)
    local v = R.pf.voice
    if v and (not p or v.paddr ~= p:get_address()) then R.pf_voice_restore("pawn changed"); v = nil end
    if not p then return end
    if not v then
        local wa, wp = R.pf_wc(state.arisen_chara), R.pf_wc(p)
        if not (wa and wp) then R.pf.voice_err = "no WwiseCharacter"; return end
        v = { wa = wa, wp = wp, a = R.pf_wc_get(wa), p = R.pf_wc_get(wp), paddr = p:get_address(), next_t = 0 }
        R.pf.voice = v
        R.pf.voice_seen = string.format("Arisen %s/%.2f/%s, pawn %s/%.2f/%s", tostring(v.a[1]), v.a[2] or -1, tostring(v.a[3]),
            tostring(v.p[1]), v.p[2] or -1, tostring(v.p[3]))
        log_msg("Player feel: sound settings swapped (" .. R.pf.voice_seen .. ")")
    end
    local now = os.clock()
    if now < v.next_t then return end
    v.next_t = now + 0.5
    -- written again twice a second in case the game sets them back (counted, so a test shows whether it does)
    local cur = R.pf_wc_get(v.wp)
    if cur[1] ~= v.a[1] or cur[3] ~= v.a[3] then R.pf_count("sound settings rewritten") end
    R.pf_wc_set(v.wp, v.a)
    R.pf_wc_set(v.wa, v.p)
end

-- Sound part 2: where loudness by distance is worked out from (via.simplewwise.Driver; static).
R.pf_drv = function()
    R.pf.drv = R.pf.drv or sdk.find_type_definition("via.simplewwise.Driver")
    return R.pf.drv
end
R.pf_listener_tick = function(p)
    local mode = p and (cfg.pf_sound_listener or 0) or 0
    local drv = R.pf_drv()
    if not drv then return end
    if mode == 0 then
        if R.pf.dec_old ~= nil then
            pcall(function() drv:get_method("set_CalcDistanceDecayAtPlayerPos(System.Boolean)"):call(nil, R.pf.dec_old) end)
            R.pf.dec_old = nil
            log_msg("Player feel: loudness by distance back to the game's")
        end
        return
    end
    if R.pf.dec_old == nil then
        R.pf.dec_old = drv:get_method("get_CalcDistanceDecayAtPlayerPos"):call(nil) == true
        log_msg("Player feel: loudness by distance from " .. (mode == 1 and "the camera" or "the played pawn") .. " (game had " .. tostring(R.pf.dec_old) .. ")")
    end
    local ear = nil
    if mode == 1 then local oke, e = pcall(R.pf_coop_ear); ear = oke and e or nil end
    R.pf.ear_on = ear ~= nil
    drv:get_method("set_CalcDistanceDecayAtPlayerPos(System.Boolean)"):call(nil, mode == 2 or ear ~= nil)
    if mode == 2 or ear then R.pf_listener_pos(p) end
end
-- 0.9.171: co-op with "the camera": when the camera pulls back to keep both players in view, loudness by distance
-- from the camera made everything quiet. The sound engine works out loudness from one point and left / right from
-- the camera (the game's own split: loudness at the player, panning at the camera). So loudness is worked out from
-- an "ear" on the camera's line of sight, pf_sound_ear_dist from the middle of the two players: both are heard in
-- proportion, as a close camera on that middle would hear them, and panning still follows the camera.
R.pf_coop_ear = function()
    if not cfg.pf_sound_coop_ear then return nil end
    local pl = R.players()
    local a, b = pl[1], pl[2]
    if not (a and b) then return nil end
    local pa = a:call("get_GameObject"):call("get_Transform"):call("get_Position")
    local pb = b:call("get_GameObject"):call("get_Transform"):call("get_Position")
    local cam = R.primary_cam()
    local cp = cam and cam:call("get_GameObject"):call("get_Transform"):call("get_Position")
    if not (pa and pb and cp) then return nil end
    local mx, my, mz = (pa.x + pb.x) * 0.5, (pa.y + pb.y) * 0.5 + 1.5, (pa.z + pb.z) * 0.5
    local dx, dy, dz = cp.x - mx, cp.y - my, cp.z - mz
    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
    local base = math.max(1.0, cfg.pf_sound_ear_dist or 5.0)
    local k = (d > base) and (base / d) or 1.0
    R.pf.ear_cam_d = d
    return Vector3f.new(mx + dx * k, my + dy * k, mz + dz * k)
end
R.pf_listener_pos = function(p) -- also run late in the frame (below): the game may write its own player's position
    p = p or R.pf_played()
    if not p then return end
    local mode = cfg.pf_sound_listener or 0
    local pos
    if mode == 2 then
        pos = p:call("get_GameObject"):call("get_Transform"):call("get_Position")
    elseif mode == 1 and R.pf.ear_on then
        local oke, e = pcall(R.pf_coop_ear)
        pos = oke and e or nil
    end
    if not pos then return end
    local drv = R.pf_drv()
    drv:get_method("set_PlayerPositionForDistanceDecay(via.vec3)"):call(nil, pos)
end

-- dev5: skills with a slow-motion moment (Riotous Fury, ...). Their app.SlowAction has PlayerOnly set, and its start()
-- checks the character's CharacterID against the Arisen's (ch000000_00, 0xac525575 at Character+0xc4c; read from
-- the disassembly of SlowAction.start, 2026-11-19), not who the player is. So it never fires for a played pawn, and
-- would still fire for the Arisen. For a PlayerOnly action whose character is the played pawn, PlayerOnly is off for
-- the length of start() (the game then takes its player path); for the Arisen's while a pawn is played,
-- EnableRequestSlow is cleared after start(). The character is cached on the action, so the very first use of a
-- skill by a given pawn may still miss (the cache is filled inside that start()).
R.pf_slow_hook = function()
    if R.pf.hooked.skillslow then return end
    R.pf.hooked.skillslow = {}
    local td = sdk.find_type_definition("app.SlowAction")
    local m = td and td:get_method("start")
    if not m then R.pf.hooked.skillslow[1] = "SlowAction.start not found"; return end
    sdk.hook(m, function(args)
        local st = thread.get_hook_storage()
        st.sl = nil
        if not cfg.pf_skill_slow then return end
        local p = R.pf_played()
        if not p then return end
        local a = sdk.to_managed_object(args[2])
        if not a or a:get_field("PlayerOnly") ~= true then return end
        local ch = a:get_field("<CachedCharacter>k__BackingField")
        local who = ch and ch:get_address() or 0
        if who == p:get_address() then
            a:set_field("PlayerOnly", false)
            st.sl = { a = a, restore = true }
            R.pf_count("skill slow-mo for the played pawn")
        elseif state.arisen_chara and who == state.arisen_chara:get_address() then
            st.sl = { a = a, arisen = true }
        elseif who == 0 then
            st.sl = { a = a, first = true }
        end
    end, function(r)
        local st = thread.get_hook_storage()
        local s = st.sl
        st.sl = nil
        if s then
            pcall(function()
                if s.restore then s.a:set_field("PlayerOnly", true) end
                if s.arisen then
                    s.a:set_field("EnableRequestSlow", false)
                    R.pf_count("skill slow-mo held back for the Arisen")
                end
                if s.first then -- the character was only cached inside this start(): set the flag the game would have
                    local ch = s.a:get_field("<CachedCharacter>k__BackingField")
                    local p = R.pf_played()
                    local who = ch and ch:get_address() or 0
                    if p and who == p:get_address() then
                        s.a:set_field("EnableRequestSlow", true)
                        R.pf_count("skill slow-mo first use (flag set)")
                    elseif state.arisen_chara and who == state.arisen_chara:get_address() then
                        s.a:set_field("EnableRequestSlow", false)
                    end
                end
            end)
        end
        return r
    end)
    R.pf.hooked.skillslow[1] = "SlowAction.start"
    log_msg("Player feel: skill slow-motion hook on")
end

R.pf_tick = function()
    if R.world_now == false then return end
    if cfg.pf_skill_slow then pcall(R.pf_slow_hook) end
    local p = R.pf_played()
    if cfg.pf_sound_space then R.pf_hook_group("space", R.PF_HOOKS.space, "pf_sound_space") end
    if cfg.pf_hitstop then R.pf_hook_group("hitstop", R.PF_HOOKS.hitstop, "pf_hitstop") end
    if cfg.pf_world_slow then R.pf_hook_group("slow", R.PF_HOOKS.slow, "pf_world_slow") end
    local ok, err = pcall(R.pf_voice_tick, cfg.pf_sound_voice and p or nil)
    if not ok then R.pf.voice_err = tostring(err) end
    ok, err = pcall(R.pf_listener_tick, p)
    if not ok then R.pf.listener_err = tostring(err) end
end
