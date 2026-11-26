-- Direct Pawn Control: test bench: test enemies, test marks, test hotkeys.
-- Part of DirectPawnControl.lua, which loads the files in this folder in order (this one is 17 of 26).
-- Never run on its own: REFramework only runs the files directly in reframework/autorun.
local S = require("DirectPawnControl/shared")
local dev, robot, dev_error, cfg, save_cfg, R = S.dev, S.robot, S.dev_error, S.cfg, S.save_cfg, S.R
local log_msg, call, field, get_party, state, brain = S.log_msg, S.call, S.field, S.get_party, S.state, S.brain
local coop, brain_event, brain_alive, hud_widgets = S.coop, S.brain_event, S.brain_alive, S.hud_widgets
local quick, quick_skill, party_heal, release_possession = S.quick, S.quick_skill, S.party_heal, S.release_possession
local start_possession, coop_pad_values, coop_start = S.start_possession, S.coop_pad_values, S.coop_start
local coop_stop, key_pressed = S.coop_stop, S.key_pressed

-- ----------------------------------------------------------------------------
-- v0.8.1 Test bench: test-enemy spawner, test marks and hotkeys
-- Spawn path = EncounterDirector's waveEngine: GenerateManager.requestCreateInstance(PrefabController,
-- GenerateInfoContainer, requestID, InstanceInfo, nil, nil) once the enemy catalog's prefab is ready.
-- ----------------------------------------------------------------------------
local TEST_ENEMIES = {
    { cid = "ch220000_00", name = "Goblin" },
    { cid = "ch220000_03", name = "Goblin thrower" },
    { cid = "ch220001_10", name = "Hobgoblin" },
    { cid = "ch223000_00", name = "Wolf" },
    { cid = "ch222000_00", name = "Harpy (flying)" },
    { cid = "ch221000_00", name = "Saurian" },
    { cid = "ch226001_01", name = "Skeleton fighter" },
    { cid = "ch251000_00", name = "Ogre" },
    { cid = "ch250000_00", name = "Cyclops" },
    { cid = "ch256000_00", name = "Minotaur" },
    { cid = "ch254000_00", name = "Chimera" },
    -- v0.9.101 (ids from EncounterDirector's charRef). Added at the end so saved selections keep their meaning.
    { cid = "ch253000_00", name = "Griffin (flying, large)" },
    { cid = "ch252000_00", name = "Golem (large)" },
    { cid = "ch257000_00", name = "Drake (very large)" },
    { cid = "ch251001_00", name = "Grim Ogre" },
    { cid = "ch254001_00", name = "Gore Chimera" },
    { cid = "ch256001_00", name = "Gore Minotaur" },
    { cid = "ch220000_10", name = "Goblin (strong)" },
    { cid = "ch220002_00", name = "Chopper" },
    { cid = "ch221001_00", name = "Asp (poison)" },
    { cid = "ch221002_00", name = "Rattler" },
    { cid = "ch222003_00", name = "Succubus (flying)" },
}
local TEST_ENEMY_NAMES = {}
for i, e in ipairs(TEST_ENEMIES) do TEST_ENEMY_NAMES[i] = e.name end

-- The standard battery. "still" enemies are target dummies (_IsThinkStop): they stand there and pawns mostly
-- ignore them, so any damage is the Arisen's.
local TEST_PRESETS = {
    { label = "Dummy ahead 14m",   enemy = 1, count = 1, dist = 14.0, angle = 0,   still = true,  note = "brain: turn + shoot" },
    { label = "Dummy beside 10m",  enemy = 1, count = 1, dist = 10.0, angle = 100, still = true,  note = "brain: turn first" },
    { label = "Dummy too close 4m", enemy = 1, count = 1, dist = 4.0, angle = -30, still = true,  note = "brain: back off to 7m" },
    { label = "Dummy far 28m",     enemy = 1, count = 1, dist = 28.0, angle = 0,   still = true,  note = "brain: approach to 20m" },
    { label = "Goblin pack x3",    enemy = 1, count = 3, dist = 18.0, angle = 0,   still = false, note = "real fight" },
    { label = "Wolves x3",         enemy = 4, count = 3, dist = 20.0, angle = 0,   still = false, note = "fast movers" },
    { label = "Harpies x2",        enemy = 5, count = 2, dist = 18.0, angle = 0,   still = false, note = "airborne targets" },
    { label = "Ogre",              enemy = 8, count = 1, dist = 25.0, angle = 0,   still = false, note = "large enemy" },
    { label = "Cyclops",           enemy = 9, count = 1, dist = 28.0, angle = 0,   still = false, note = "large: climbing, weak point" },
    { label = "Cyclops dummy",     enemy = 9, count = 1, dist = 20.0, angle = 0,   still = true,  note = "large, stands still: aim / climb practice" },
    { label = "Minotaur",          enemy = 10, count = 1, dist = 28.0, angle = 0,  still = false, note = "large charger" },
    { label = "Chimera",           enemy = 11, count = 1, dist = 28.0, angle = 0,  still = false, note = "large, three heads" },
    { label = "Griffin",           enemy = 12, count = 1, dist = 30.0, angle = 0,  still = false, note = "large flyer" },
    { label = "Golem",             enemy = 13, count = 1, dist = 30.0, angle = 0,  still = false, note = "large, weak points only" },
    { label = "Drake",             enemy = 14, count = 1, dist = 35.0, angle = 0,  still = false, note = "very large (dangerous)" },
    { label = "Saurians x3",       enemy = 6, count = 3, dist = 20.0, angle = 0,   still = false, note = "medium pack" },
    { label = "Asps x2 (poison)",  enemy = 20, count = 2, dist = 18.0, angle = 0,  still = false, note = "poison: cure tests" },
    { label = "Ogre + behind you", enemy = 8, count = 1, dist = 20.0, angle = 180, still = false, note = "large enemy from behind" },
}

local spawner = { charmap = nil, mreq = nil, pending = {}, units = {}, alive = 0, spawned = 0, next_prune = 0, marks = 0 }

local function spawner_init()
    if not spawner.charmap then
        local m = {}
        local td = sdk.find_type_definition("app.CharacterID")
        for _, f in ipairs(td and td:get_fields() or {}) do
            if f:is_static() then
                local ok, v = pcall(f.get_data, f, nil)
                if ok and type(v) == "number" then m[f:get_name()] = v end
            end
        end
        spawner.charmap = m
    end
    if not spawner.mreq then
        local td = sdk.find_type_definition("app.GenerateManager")
        for _, m in ipairs(td and td:get_methods() or {}) do
            if m:get_name() == "requestCreateInstance" then
                local pt = m:get_param_types()
                if #pt == 6 and pt[1]:get_name() == "PrefabController" then spawner.mreq = m end
            end
        end
    end
    return spawner.charmap and spawner.mreq
end

local function spawner_prefab(char_id)
    local gm = sdk.get_managed_singleton("app.GenerateManager")
    local cc = gm and field(gm, "_CatalogCtrl")
    local ec = cc and field(cc, "_EnemyCatalog")
    local merged = ec and field(ec, "<MergedCatalog>k__BackingField")
    local item = merged and call(merged, "get_Item", char_id)
    return item and call(item, "get_Item")
end

local function test_mark(label)
    spawner.marks = spawner.marks + 1
    local s = string.format("=== TEST MARK %d%s ===", spawner.marks, label and (": " .. label) or "")
    log_msg(s)
    brain_event(s)
end

-- spec = { enemy = index into TEST_ENEMIES (or cid = "ch..."), count, dist, angle (deg, + = right), still,
--          around = "arisen" | "pawn" }
local function spawn_test(spec)
    if not spawner_init() then log_msg("Test spawn: GenerateManager API not found"); return false end
    local cid = spec.cid or (TEST_ENEMIES[spec.enemy or 1] or TEST_ENEMIES[1]).cid
    local char_id = spawner.charmap[cid]
    local pctrl = char_id and spawner_prefab(char_id)
    if not pctrl then log_msg("Test spawn: no prefab for " .. tostring(cid)); return false end
    local cm = sdk.get_managed_singleton("app.CharacterManager")
    local anchor = cm and call(cm, "get_ManualPlayer")
    if spec.around == "pawn" and state.active and state.pawn_chara then anchor = state.pawn_chara end
    local xf = anchor and call(anchor, "get_Transform")
    local pos = xf and call(xf, "get_Position")
    local rot = xf and call(xf, "get_Rotation")
    local wos = sdk.get_managed_singleton("app.WorldOffsetSystem")
    local gm = sdk.get_managed_singleton("app.GenerateManager")
    if not (pos and rot and wos and gm) then log_msg("Test spawn: no anchor position"); return false end
    pcall(function() pctrl:get_Item():set_Standby(true) end)
    local f = rot * Vector3f.new(0, 0, 1)
    local a = math.rad(spec.angle or 0)
    local fx, fz = f.x * math.cos(a) + f.z * math.sin(a), -f.x * math.sin(a) + f.z * math.cos(a)
    local dist, count = spec.dist or 14.0, math.max(1, math.min(8, spec.count or 1))
    for i = 1, count do
        local side = (i - (count + 1) / 2) * 2.5
        local lp = Vector3f.new(pos.x + fx * dist + fz * side, pos.y + 0.5, pos.z + fz * dist - fx * side)
        local ok, err = pcall(function()
            local up = wos:call("toUniversalPosition", lp)
            local inst = sdk.create_instance("app.InstanceInfo"):add_ref()
            local cont = inst:get_Container()
            local idw = gm:getIdWrapper(char_id)
            pcall(function() cont._CommonInfo:set_ObjectID(sdk.to_ptr(idw)) end)
            pcall(function() cont._CommonInfo._ObjectID._SelectedCharacterID = char_id end)
            cont._CommonInfo:setContextPosition(up)
            cont._CommonInfo:setContextAngle(rot)
            cont._CharaInfo._IsThinkStop = spec.still and true or false
            -- tough: can't die and is topped up when low, so pawns can't kill a test dummy (default for "still")
            local tough = spec.tough; if tough == nil then tough = spec.still and true or false end
            spawner.pending[#spawner.pending + 1] = { cid = cid, pctrl = pctrl, cont = cont, inst = inst, tough = tough,
                rid = math.random(20000, 89999), status = 1, t0 = os.clock() }
        end)
        if not ok then log_msg("Test spawn error: " .. tostring(err)) end
    end
    local s = string.format("Test spawn: %d x %s at %.0fm, %d deg%s", count, cid, dist, spec.angle or 0, spec.still and " (dummy)" or "")
    log_msg(s)
    brain_event(s)
    return true
end

local function despawn_tests()
    local n = 0
    for _, u in ipairs(spawner.units) do
        -- v0.9.15: a tough dummy that outlives its despawn (2026-11-14: the GameObject wasn't destroyed) must not
        -- stay unkillable
        pcall(function() local hit = u.chara:call("get_Hit"); if hit then hit:call("set_IsNoDie", false) end end)
        pcall(function()
            local go = u.inst:get_Instance()
            -- same guard as EncounterDirector: a dissolved corpse's GameObject may already be freed
            if go and sdk.is_managed_object(go) then
                local okV, valid = pcall(go.call, go, "get_Valid")
                if not okV or valid ~= false then go:destroy(go); n = n + 1 end
            end
        end)
    end
    spawner.units, spawner.pending, spawner.alive = {}, {}, 0
    log_msg("Despawned " .. n .. " test enemies")
end

local function spawner_tick()
    if #spawner.pending > 0 then
        local gm = sdk.get_managed_singleton("app.GenerateManager")
        for i = #spawner.pending, 1, -1 do
            local p = spawner.pending[i]
            local ok, err = pcall(function()
                if p.status == 1 then
                    if p.pctrl:get_Item():get_Ready() then
                        spawner.mreq:call(gm, p.pctrl, p.cont, p.rid, p.inst, nil, nil)
                        p.status = 4
                    end
                elseif p.status == 4 then
                    local ch = p.inst:get_Chara()
                    if ch then
                        spawner.units[#spawner.units + 1] = { inst = p.inst, chara = ch, cid = p.cid, tough = p.tough }
                        spawner.spawned = spawner.spawned + 1
                        table.remove(spawner.pending, i)
                    end
                end
            end)
            if not ok or os.clock() - p.t0 > 20 then
                log_msg("Test spawn dropped: " .. tostring(err or "timeout"))
                table.remove(spawner.pending, i)
            end
        end
    end
    for _, u in ipairs(spawner.units) do
        if u.tough then
            local ok, err = pcall(function()
                local hit = u.chara:call("get_Hit")
                if not hit then return end
                if not hit:call("get_IsNoDie") then hit:call("set_IsNoDie", true) end
                local hp, mx = hit:call("get_Hp") or 0, hit:call("get_OriginalMaxHp") or 0
                if mx > 0 and hp < mx * 0.3 then hit:call("recoverHpAndMaxHpCompletely", false) end
            end)
            if not ok and not u.tough_err then u.tough_err = true; dev_error("tough dummy", err) end
        end
    end
    local now = os.clock()
    if now >= spawner.next_prune then
        spawner.next_prune = now + 0.5
        local alive = 0
        for _, u in ipairs(spawner.units) do
            if brain_alive(u.chara) then alive = alive + 1 end
        end
        spawner.alive = alive
    end
end

-- v0.9.121 developer tool, requested: a debug key that downs a pawn (to practise the Remedy Arrow). Shift+F10,
-- the Test bench button or {"cmd":"down","idx":N} puts the selected pawn down.
-- v0.9.122: the 0.9.121 ladder (HitController.setHpValue / setHp to zero) changed the number and nothing else:
-- reported: the pawn-downer key did nothing; log: four runs, "none of the three ways". Death runs in the damage
-- path. What works (bridge test dn5, 2026-11-17, ch111011: hp 1517 -> 0, IsDead true): a HitController.DamageInfo
-- of our own handed to HitController.updateDamageHp(info, damage, false).
R.down_pawn = function(idx)
    local entry = nil
    -- 0.9.172-dev31: idx "other" = the first pawn nobody plays (coop-checks-1 asked for idx 1, which was the played
    -- pawn after the party order changed, so nobody was downed)
    if idx == "other" then
        for _, e in ipairs(get_party()) do
            if not entry and not R.held_by(e.idx) and not (state.active and state.pawn_chara and e.chara:get_address() == state.pawn_chara:get_address()) then entry = e end
        end
    end
    for _, e in ipairs(get_party()) do if e.idx == (idx or cfg.selected_pawn_idx) then entry = e end end
    if not entry then log_msg("Down a pawn: nobody selected (F7 picks a pawn)"); return false end
    if state.active and state.pawn_chara and entry.chara:get_address() == state.pawn_chara:get_address() then
        log_msg("Down a pawn: " .. entry.name .. " is the one you are playing; select another"); return false
    end
    if call(entry.chara, "get_IsDead") == true then log_msg("Down a pawn: " .. entry.name .. " is down already"); return false end
    local ok, err = pcall(function()
        local hit = entry.chara:call("get_Hit")
        local di = sdk.create_instance("app.HitController.DamageInfo")
        if not (hit and di) then error("no hit controller / damage info") end
        di = di:add_ref()
        di:set_field("Damage", 99999.0)
        di:set_field("FixedDamage", 99999.0)
        di:set_field("IsDirectDamage", true)
        di:set_field("<DamageHitController>k__BackingField", hit)
        di:set_field("<DamageOwnerHitController>k__BackingField", hit)
        hit:call("updateDamageHp(app.HitController.DamageInfo, System.Single, System.Boolean)", di, 99999.0, false)
        -- 0.9.172-dev32: the pawn was "down" (0 HP, IsDead) but stood there calmly. The game's own die handlers on
        -- the Human start the down reaction (motion, dying state), as a real fatal hit does.
        local hu = entry.chara:call("get_Human")
        if hu then
            pcall(function() hu:call("Hit_DieHandler(app.HitController.DamageInfo)", di) end)
            pcall(function() hu:call("Hit_DieReactionHandler(app.HitController.DamageInfo)", di) end)
        end
    end)
    -- 0.9.172-dev33/34: even with the die handlers the pawn counted as down (skull, red bar) but kept standing.
    -- dev33's HumanActionSelector.requestAction("DieCollapse") lost to his sit-to-stand (coop-checks-4 ended in
    -- Liv.LivManual.LivSitOnTheGroundToStand). dev34 asks the ActionManager directly at the Highest priority and
    -- walks a list (DieCollapse, DieDown, DieLoop: app.HumanActionID) until layer 0 shows a Die action.
    local node0 = ""
    pcall(function()
        local fsm = entry.chara:call("get_ActionManager"):get_field("Fsm")
        node0 = tostring(fsm:call("getCurrentNodeName(System.UInt32)", 0))
    end)
    R.down_check = { chara = entry.chara, name = entry.name, t = os.clock(), before = node0, i = 0, tried = {} }
    local dead = call(entry.chara, "get_IsDead") == true
    log_msg(string.format("Down a pawn: %s -> %s%s (action was %s)", entry.name, dead and "down" or "NOT down", ok and "" or (" (" .. tostring(err) .. ")"), node0))
    return dead
end
-- dev34: make the downed pawn's body go down. Every 0.4 s: if layer 0 isn't a Die action yet, request the next
-- name from the list at the Highest priority; log what each try led to (R.down_node, R.down_tries for tests).
R.DOWN_ACTIONS = { "DieCollapse", "DieDown", "DieLoop" }
R.down_tick = function()
    local c = R.down_check
    if not c or os.clock() < c.t then return end
    local node = ""
    pcall(function()
        local fsm = c.chara:call("get_ActionManager"):get_field("Fsm")
        node = tostring(fsm:call("getCurrentNodeName(System.UInt32)", 0))
    end)
    R.down_node = node
    if c.i > 0 then c.tried[#c.tried + 1] = R.DOWN_ACTIONS[c.i] .. "->" .. node end
    R.down_tries = table.concat(c.tried, ", ")
    if node:find("Die") or call(c.chara, "get_IsDead") ~= true or c.i >= #R.DOWN_ACTIONS then
        R.down_check = nil
        log_msg("Down a pawn: " .. c.name .. ": " .. (R.down_tries ~= "" and R.down_tries or node))
        return
    end
    c.i = c.i + 1
    pcall(function()
        c.chara:call("get_ActionManager"):call("requestActionCore(app.ActionManager.Priority, System.String, System.UInt32)", 0, R.DOWN_ACTIONS[c.i], 0)
    end)
    c.t = os.clock() + 0.4
end

-- Test hotkeys (cfg.test_hotkeys): F9 spawn the selected test, Ctrl+F9 the custom spawn (0.9.101), Shift+F9 mark,
-- F10 despawn, Ctrl+F10 down the selected pawn (0.9.121; was Shift+F10 until 0.9.127), F11 brain on/off
local function test_hotkeys()
    if not R.dev then return end
    R.down_tick()
    if not cfg.test_hotkeys then return end -- v0.9.114: never for players (F9 spawned enemies)
    local k = cfg.test_keys
    local shift = S.is_key_down_safe(0x10)
    if key_pressed(k.spawn) then
        if shift then test_mark("hotkey")
        elseif S.is_key_down_safe(0x11) then spawn_test(cfg.test_custom)
        else
            local p = TEST_PRESETS[cfg.test_preset]
            if p then
                spawn_test({ enemy = p.enemy, count = p.count, dist = p.dist, angle = p.angle, still = p.still, around = cfg.test_custom.around })
            else
                spawn_test(cfg.test_custom)
            end
        end
    end
    if key_pressed(k.despawn) then
        -- v0.9.128: Ctrl+F10, not Shift+F10. Shift+F10 is Windows' own "context menu" shortcut; after it the
        -- script side went on seeing Shift as held, and TestGuide took the next End for Shift+End (abort).
        if S.is_key_down_safe(0x11) then R.down_pawn() else despawn_tests() end
    end
    if key_pressed(k.toggle_brain) then
        cfg.arisen_brain = not cfg.arisen_brain
        save_cfg()
        log_msg("Arisen brain " .. (cfg.arisen_brain and "ON" or "OFF") .. " (hotkey)")
    end
end

-- v0.8 dev: data/DPC_cmd.json lets a tester (or an agent through the file system) drive DPC without the keyboard:
--   {"id":"any-new-string","cmd":"possess","idx":0} | {"id":"..","cmd":"release"} | {"id":"..","cmd":"solo","on":true}
--   {"id":"..","cmd":"set","key":"arisen_brain_skills","value":false,"save":false}
-- Each new id runs once; the result goes to data/DPC_cmd_ack.json.
local cmd_state = { last_id = nil, next_t = 0 }
local function poll_cmd_file()
    if not (R.dev and cfg.cmd_file) then return end
    local now = os.clock()
    if now < cmd_state.next_t then return end
    cmd_state.next_t = now + 0.5
    local ok, d = pcall(json.load_file, "DPC_cmd.json")
    if not ok or type(d) ~= "table" then
        -- json.load_file logs an error every poll while the file is missing: create an empty one once
        if not cmd_state.created then cmd_state.created = true; pcall(json.dump_file, "DPC_cmd.json", {}) end
        return
    end
    if d.id == nil or d.id == cmd_state.last_id then return end
    if cmd_state.last_id == nil and d.stale_ok ~= true and cmd_state.seen_first == nil then
        -- first file seen after (re)load is a leftover from before: remember it, don't run it
        cmd_state.seen_first = true
        cmd_state.last_id = d.id
        return
    end
    cmd_state.last_id = d.id
    local res = "ok"
    if d.cmd == "possess" then
        start_possession(tonumber(d.idx) or 0)
    elseif d.cmd == "release" then
        release_possession("cmd file")
    elseif d.cmd == "spawn" then
        local p = TEST_PRESETS[tonumber(d.preset) or 0]
        local spec = p and { enemy = p.enemy, count = p.count, dist = p.dist, angle = p.angle, still = p.still }
            or { cid = d.cid, enemy = tonumber(d.enemy) or 1, count = tonumber(d.count) or 1, dist = tonumber(d.dist) or 14.0,
                 angle = tonumber(d.angle) or 0, still = d.still ~= false }
        spec.around = d.around
        -- v0.9.136 "tough": true = cannot die and is topped up when low, also for enemies that fight ("still": false),
        -- so a test fight lasts as long as its step (requested: unkillable but weak test enemies). Despawn clears it.
        if d.tough ~= nil then spec.tough = d.tough and true or false end
        if not spawn_test(spec) then res = "spawn failed" end
    elseif d.cmd == "coop" then
        if d.on == false then coop_stop() else coop_start(tonumber(d.idx) or cfg.selected_pawn_idx) end
    elseif d.cmd == "cp" then
        -- v0.9.171 {"cmd":"cp","p1":"arisen"|<pawn idx>,"p2":"arisen"|<pawn idx>}: who each co-op player controls
        local function ch(v) if v == "arisen" then return "arisen" end return tonumber(v) end
        if not (R.cp and R.cp.on) then res = "co-op is not on"
        elseif not R.cp_apply({ [1] = ch(d.p1), [2] = ch(d.p2) }, "cmd file") then res = "not applied (see log)" end
    elseif d.cmd == "cp_next" then
        if not (R.cp and R.cp.on) then res = "co-op is not on"
        elseif not R.cp_next(tonumber(d.player) or 1) then res = "no change (see log)" end
    elseif d.cmd == "despawn" then
        despawn_tests()
    elseif d.cmd == "down" then
        if not R.down_pawn(d.idx == "other" and "other" or tonumber(d.idx)) then res = "not started (see log)" end
    elseif d.cmd == "quick" then
        -- v0.9.125 {"cmd":"quick","slot":1,"idx":0}: the numpad skill order, for test plans
        local okq, errq = pcall(quick_skill, tonumber(d.slot) or 1, tonumber(d.idx))
        if not okq then res = "quick: " .. tostring(errq) end
    elseif d.cmd == "rearm" then
        -- v0.9.145 {"cmd":"rearm"}: the Warfarer Arisen presses Rearmament now (for test plans)
        local okr, errr = brain.rearm(os.clock(), "command")
        if not okr then res = "rearm: " .. tostring(errr) end
    elseif d.cmd == "heal" then
        -- v0.9.125: heal / revive the party (the Numpad . cheat), so a test never leaves a pawn down
        local okh, errh = pcall(party_heal)
        if not okh then res = "heal: " .. tostring(errh) end
    elseif d.cmd == "scene" then
        -- v0.9.170 (developer, test bench): a known start for a test. Releases any pawn, ends co-op, clears test
        -- enemies, heals the party, turns the experimental switches off (this session only) and, with "anchor":
        -- "set" remembers where the Arisen stands, with "anchor": "go" brings him and the party back there when he
        -- is more than 15 m away (the game's own warp, as Warp to me does).
        if coop.active or (R.cp and R.cp.on) then pcall(coop_stop) end -- v0.9.171: both-on-pawns too
        if state.active then pcall(release_possession, "scene reset") end
        pcall(despawn_tests)
        for _, k in ipairs({ "pf_hitstop", "pf_world_slow", "coop_two_pads" }) do cfg[k] = false end
        cfg.pf_sound_voice, cfg.pf_sound_listener, cfg.pf_sound_space = true, 1, true -- (dev4: the defaults)
        local ar = sdk.get_managed_singleton("app.CharacterManager")
        ar = ar and ar:call("get_ManualPlayer")
        local pos = ar and ar:call("get_Transform"):call("get_Position")
        if pos and d.anchor == "set" then
            R.scene_anchor = { pos.x, pos.y, pos.z }
            pcall(json.dump_file, "bench/anchor.json", { pos = R.scene_anchor })
        elseif pos and d.anchor == "go" then
            local a = R.scene_anchor
            if not a then
                local oka, f = pcall(json.load_file, "bench/anchor.json")
                a = oka and type(f) == "table" and f.pos or nil
            end
            if a then
                local dx, dz = pos.x - a[1], pos.z - a[3]
                if dx * dx + dz * dz > 225 then
                    pcall(ar.call, ar, "warp(via.vec3, app.CharacterWarpOption)", Vector3f.new(a[1], a[2] + 0.3, a[3]), nil)
                    R.scene_warp_t = os.clock() + 1.5 -- the party follows a moment later (see the frame callback)
                    res = "ok (warped back)"
                end
            else
                res = "ok (no anchor yet)"
            end
        end
        local okh = pcall(party_heal)
        if not okh then res = res .. ", heal failed" end
        R.scene_t = os.clock()
    elseif d.cmd == "mark" then
        test_mark(d.label)
    elseif d.cmd == "robot" then
        -- {"cmd":"robot","who":"pad","secs":2,"buttons":["RTrigTop"],"stick":[0,1],"rstick":[1,0]}
        -- {"cmd":"robot","who":"arisen","secs":3,"actions":["AttackS"],"stick":[0,1]}   or "yaw_deg": 90 (world)
        -- {"cmd":"robot","who":"all","stop":true}
        local secs = math.min(tonumber(d.secs) or 1.0, 30.0)
        local function vec(v) if type(v) == "table" and tonumber(v[1]) and tonumber(v[2]) then return v[1] + 0.0, v[2] + 0.0 end end
        if d.stop then
            if d.who ~= "arisen" then robot.pad = nil; if R.rbf then R.rbf.until_t = 0 end end
            if d.who ~= "pad" then robot.arisen = nil end
        elseif d.who == "pad" then
            local mask, pv = 0, coop_pad_values()
            if type(d.buttons) == "table" then
                for _, b in ipairs(d.buttons) do mask = mask | (type(b) == "number" and b or pv[b] or 0) end
            elseif type(d.buttons) == "number" then mask = d.buttons end
            -- v0.9.124 {"who":"pad","actions":["AttackS","Skill1"]}: the buttons the game has those actions on
            -- right now (with the shift button a skill needs), so a test plan works with any controller layout
            for _, a in ipairs(type(d.actions) == "table" and d.actions or {}) do
                local m = R.bind_mask(a)
                if m then
                    mask = mask | m
                    for _, e in ipairs(R.bind.list) do
                        if e.name == a and e.pad == m and e.pre and not d.noshift then -- "noshift": the button alone
                            for _, e2 in ipairs(R.bind.list) do if e2.a == e.pre then mask = mask | e2.pad; break end end
                        end
                    end
                else
                    res = "robot: no button known for action " .. tostring(a)
                end
            end
            local lx, ly = vec(d.stick); local rx, ry = vec(d.rstick)
            robot.pad = { btn = mask, lx = lx, ly = ly, rx = rx, ry = ry, until_t = os.clock() + secs, fight = d.fight == true, antics = d.antics == true }
            robot.uses = robot.uses + 1
            -- 0.9.177-dev6: with native controls the played pawn's buttons come from the game's input flags, not the
            -- pad DPC reads, so robot buttons never reached it (fix-regress-bench-1: every press did nothing). The
            -- robot's actions also go in as game flags (SkillN with the skill shift, as a real press carries).
            local fl = 0
            for _, a in ipairs(type(d.actions) == "table" and d.actions or {}) do
                local f = S.ACTION_FLAGS[a]
                if f then
                    fl = fl | f
                    if tostring(a):match("^Skill%d$") and not d.noshift then fl = fl | (S.ACTION_FLAGS.Shift1 or 0) | (S.ACTION_FLAGS.Shift2 or 0) end
                end
            end
            if R.rbf and R.rbf.on then R.rbf.rel = (R.rbf.rel or 0) | R.rbf.f end
            R.rbf = fl ~= 0 and { f = fl, until_t = os.clock() + secs, rel = R.rbf and R.rbf.rel } or (R.rbf and R.rbf.rel and { f = 0, until_t = 0, rel = R.rbf.rel }) or nil
        elseif d.who == "arisen" then
            local want = 0
            for _, a in ipairs(type(d.actions) == "table" and d.actions or {}) do want = want | (S.ACTION_FLAGS[a] or 0) end
            local sx, sy = vec(d.stick)
            local mag = sx and math.min(1.0, math.sqrt(sx * sx + sy * sy)) or nil
            if sx and mag > 0 then sx, sy = sx / mag, sy / mag end
            robot.arisen = { want = want, sx = sx, sy = sy, mag = mag, yaw = tonumber(d.yaw_deg) and math.rad(d.yaw_deg) or nil,
                             until_t = os.clock() + secs }
            robot.uses = robot.uses + 1
        else
            res = "robot: who must be pad, arisen or all"
        end
    elseif d.cmd == "order_probe" and R.dev then
        -- 0.9.177-dev4 (dev): {"cmd":"order_probe","secs":3}. Per frame: does Human.update (which resets AttackState
        -- to 0) run before or after that character's PlayerInputProcessor.update, for the Arisen and the played pawn.
        R.op = { until_t = os.clock() + (tonumber(d.secs) or 3), seq = 0, rows = {}, n = 0 }
        res = "order probe on"
    elseif d.cmd == "chant_test" and R.dev then
        -- 0.9.177-dev3 (dev, for the test bench): {"cmd":"chant_test","rounds":2}. Takes the first Mage / Sorcerer in
        -- the party (unless one is already played), casts each skill slot in turn and, mid-chant, presses the
        -- cancel button the way the game delivers L2 (one frame of ActCancel | Sheathe | Draw triggers on the pawn's
        -- input), so the game's own cancel path runs with the in-check probe. No controller needed.
        res = R.chant_test_start(tonumber(d.rounds) or 1, tonumber(d.press_after) or 0.8)
    elseif d.cmd == "lean" then
        local ok, r = pcall(R.lean_lab, tostring(d.how), tonumber(d.idx) or 0)
        res = ok and tostring(r) or ("error: " .. tostring(r))
        if not ok then log_msg("lean lab error: " .. tostring(r)) end
    elseif d.cmd == "pawn_ai" then
        -- 0.9.176-dev2 (dev, tavern hang): ways to get the played pawn out of a lean without forceEndDecision,
        -- which froze the game twice on a pawn leaning on a tavern wall. {"cmd":"pawn_ai","how":"loco"|"idle"|"end"}
        res = R.pawn_ai_try(tostring(d.how))
    elseif d.cmd == "set" and type(d.key) == "string" and cfg[d.key] ~= nil and type(cfg[d.key]) == type(d.value) then
        -- 0.9.176-dev17: a test plan's settings last for the session only. tavern-lean-4..7 switched
        -- possess_interrupt_ai off for a step; the plans were stopped before their restore step, and the next menu
        -- save kept it off, so taken-over pawns ran on with their AI's last move (found in the player's config).
        -- Unless the plan asks to save, the value saved stays the player's (same path as DPC_API overrides).
        if not d.save then
            dev.api_overrides = dev.api_overrides or {}
            local reg = dev.api_overrides[d.key]
            if not reg then dev.api_overrides[d.key] = { saved = cfg[d.key], value = d.value, by = "test plan" }
            else reg.value = d.value end
        end
        cfg[d.key] = d.value
        if d.save then save_cfg() end
    else
        res = "unknown or invalid command"
    end
    log_msg("cmd file: " .. tostring(d.cmd) .. " -> " .. res)
    pcall(json.dump_file, "DPC_cmd_ack.json", { id = d.id, cmd = d.cmd, result = res, t = now, active = state.active, brain = brain.mode,
        test_enemies_alive = spawner.alive, test_enemies_spawned = spawner.spawned })
end

local function guarded_tick(tag, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        local now = os.clock()
        if now - state.last_tick_err_t > 5.0 then -- don't flood the log every frame
            state.last_tick_err_t = now
            log_msg("ERROR in " .. tag .. ": " .. tostring(err))
        end
    end
end

-- v0.9.113 world guard. Log of 2026-11-16: during a save load ("Scene changed") some script kept calling
-- into characters that were being destroyed: 77 access violations in one second, all caught by REFramework, none
-- attributable to a particular mod from the log. As a precaution nothing in this mod touches the game world
-- while it is not in the game phase (MainFlowManager.IsInGamePhase false) or there is no player character.
-- A possession is released first; cached objects are dropped; work resumes one second after the world is back.
R.world_check = function()
    local now = os.clock()
    local okc, good = pcall(function()
        local mf = sdk.get_managed_singleton("app.MainFlowManager")
        if mf and mf:call("get_IsInGamePhase") == false then
            -- 0.9.177: a played pawn was dropped twice in one fight (a level-up / event moment, 1.2 s each, the world
            -- stayed). Only the flow phases that really load, unload or restart count; anything else is logged once.
            local ph = mf:get_field("<FlowPhase>k__BackingField")
            if type(ph) ~= "number" or ph < 27 or (ph >= 41 and ph <= 50) then return false end
            if R.world_odd_ph ~= ph then
                R.world_odd_ph = ph
                log_msg("World guard: the game left its in-game phase (flow phase " .. tostring(ph) .. "); the world stays, so DPC carries on")
            end
        else
            R.world_odd_ph = nil
        end
        -- (not the load icon or SaveDataManager.IsBusy: those may also be up during an ordinary autosave, and
        -- pausing or dropping a possession on every autosave would be far worse than what this guards against)
        local cm = sdk.get_managed_singleton("app.CharacterManager")
        return cm ~= nil and cm:call("get_ManualPlayer") ~= nil
    end)
    good = okc and good == true
    if not good then
        if R.world ~= false then
            R.world_losses = (R.world_losses or 0) + 1
            if state.active then pcall(release_possession, "loading") end
            -- 0.9.171: before the list is forgotten, test enemies that still exist become killable again. This also
            -- fires on screens where the world stays (a menu), and three unkillable goblins were left that way.
            for _, u in ipairs(spawner.units) do
                pcall(function() local hit = u.chara:call("get_Hit"); if hit then hit:call("set_IsNoDie", false) end end)
            end
            spawner.units, spawner.pending, spawner.alive = {}, {}, 0
            for k in pairs(hud_widgets) do hud_widgets[k] = nil end
            R.ping, R.dh, R.tk = nil, nil, nil
            brain.target, brain.lock, brain.lock_work = nil, nil, nil
            coop.tgt, coop.tgt_work = nil, nil
            quick.rows, quick.defs, quick.packs, quick.rows_try_t = nil, nil, {}, nil -- v0.9.115: game objects, read again later
            R.aim_pick, R.aim_pick_idx, R.aim_asset_addr = nil, nil, nil -- v0.9.168: aim setting, read again later
            pcall(R.cine_stop) -- v0.9.169
            if R.pf_restore_all then pcall(R.pf_restore_all, "loading") end -- v0.9.170
            if R.cp_world_lost then pcall(R.cp_world_lost) end -- v0.9.171
            if R.api_fire then pcall(R.api_fire, "world_loading", {}) end
            log_msg("World is loading: the mod pauses until it is back")
        end
        R.world, R.world_back_t = false, nil
        return false
    end
    if R.world == false then
        R.world_back_t = R.world_back_t or now
        if now - R.world_back_t < 1.0 then return false end
        log_msg("World is back: the mod resumes")
        if R.api_fire then pcall(R.api_fire, "world_back", {}) end
    end
    R.world = true
    return true
end

-- shared with the modules loaded after this one (see shared.lua)
S.TEST_ENEMY_NAMES, S.TEST_PRESETS, S.spawner, S.test_mark = TEST_ENEMY_NAMES, TEST_PRESETS, spawner, test_mark
S.spawn_test, S.despawn_tests, S.spawner_tick, S.test_hotkeys = spawn_test, despawn_tests, spawner_tick, test_hotkeys
S.poll_cmd_file, S.guarded_tick = poll_cmd_file, guarded_tick
