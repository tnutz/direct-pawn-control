-- Direct Pawn Control: game fixes in combat: AI interrupts, arrows, downed pawns, hints, HUD, boons.
-- Part of DirectPawnControl.lua, which loads the files in this folder in order (this one is 13 of 26).
-- Never run on its own: REFramework only runs the files directly in reframework/autorun.
local S = require("DirectPawnControl/shared")
local dev_error, cfg, save_cfg, R, log_msg, same_obj = S.dev_error, S.cfg, S.save_cfg, S.R, S.log_msg, S.same_obj
local call, field, get_party, state, addr_of, coop = S.call, S.field, S.get_party, S.state, S.addr_of, S.coop
local brain_pos, brain_angdiff, release_possession = S.brain_pos, S.brain_angdiff, S.release_possession
local start_possession, coop_pad_values = S.start_possession, S.coop_pad_values

R.interrupt_ai = function(chara, name, with_idle)
    local did = {}
    -- 0.9.176-dev16: the pack the AI was running (its move to a target, ch1_Move_Run_Target) kept steering a pawn
    -- after the take-over: ending the DECISION doesn't stop it, and with the pawn's thinking held off nothing else
    -- does. The pack runs in the decision module's ActionInterface; its executor (app.actinter.Executor, read from
    -- DD2.exe: _State 2 = done) is told to end it, which is what forceEndActionForState does (sets _State 3, the
    -- executor finishes it on its own next update).
    local okx, errx = pcall(function()
        local aidm = call(chara, "get_AIDecisionMaker") or field(chara, "<AIDecisionMaker>k__BackingField")
        local dm = aidm and (call(aidm, "get_DecisionModule") or field(aidm, "<DecisionModule>k__BackingField"))
        local ai = dm and field(dm, "<ActionInterface>k__BackingField")
        local ex = ai and field(ai, "<Executor>k__BackingField")
        local st = ex and field(ex, "_State")
        if ex and type(st) == "number" and st ~= 2 and field(ex, "_CurrentNode") ~= nil and not R.busy_interact(chara) then
            ex:call("forceEndActionForState")
            did[#did + 1] = "action pack ended (state " .. st .. ")"
        end
    end)
    if not okx then dev_error("interrupt_ai pack", errx) end
    local okd, errd = pcall(function()
        local aidm = call(chara, "get_AIDecisionMaker") or field(chara, "<AIDecisionMaker>k__BackingField")
        local dm = aidm and (call(aidm, "get_DecisionModule") or field(aidm, "<DecisionModule>k__BackingField"))
        local ex = dm and dm:call("get_DecisionExecutor")
        if ex and ex:call("get_ExecutingDecision") ~= nil then
            if R.busy_interact(chara) then
                -- 0.9.176: never force-end while an object interaction holds the pawn (freeze); abort it instead
                if R.abort_interact(chara) then did[#did + 1] = "interaction abort asked" end
            else
                ex:call("forceEndDecision")
                did[#did + 1] = "decision ended"
            end
        end
    end)
    if not okd then dev_error("interrupt_ai decision", errd) end
    if with_idle or #did > 0 then
        pcall(function()
            local sel = call(chara, "get_HumanActionSelector")
            if with_idle and sel and sel:call("isEnableRequestIdle") then
                sel:call("requestIdleImpl(System.Boolean)", false)
                did[#did + 1] = "idle requested"
            end
        end)
    end
    if #did > 0 then
        R.ai_ends = (R.ai_ends or 0) + 1
        local now = os.clock()
        if with_idle or now >= (R.ai_log_next or 0) then
            R.ai_log_next = now + 5.0
            log_msg("Interrupted " .. tostring(name) .. "'s AI action: " .. table.concat(did, ", "))
        end
    end
    return #did > 0
end
-- v0.9.93 the pawn being played stops guiding. A pawn that "knows the way" to a quest runs ahead as the party's guide
-- (PawnManager.PawnConcierge, an app.Concierge with _ConciergeCharacter = that pawn). That is not a decision, so
-- ending decisions did not stop it: the played pawn kept being steered toward the destination and fought the
-- player's input. Ask the game to end the guidance (the same request a "Come" order makes); if it is still
-- guiding 1.5 s later, end the navigation outright.
R.guide_stop = function(chara, name)
    local ok, err = pcall(function()
        local pm = sdk.get_managed_singleton("app.PawnManager")
        local con = pm and pm:call("get_PawnConcierge")
        if not con or con:call("get_IsConcierge") ~= true then R.guide_t0 = nil; return end
        local cc = con:call("get_ConciergeCharacter")
        if not (cc and same_obj(cc, chara)) then R.guide_t0 = nil; return end
        local now = os.clock()
        if not R.guide_t0 then
            R.guide_t0 = now
            con:call("requestEndGuidancePawn")
            R.guide_stops = (R.guide_stops or 0) + 1
            log_msg("Guide: " .. tostring(name) .. " was leading the way to a quest; asked the game to end the guidance")
        elseif now - R.guide_t0 > 1.5 then
            R.guide_t0 = now
            con:call("endNavigation")
            R.guide_forced = (R.guide_forced or 0) + 1
            log_msg("Guide: " .. tostring(name) .. " was still guiding after 1.5 s; navigation ended")
        end
    end)
    if not ok then dev_error("guide stop", err) end
end
-- v0.9.94 dev only: the first 15 s of every possession, 10 samples a second, to data/DPC_takeover.json: where the
-- pawn is, how hard the player pushes the stick, the pawn's action nodes, the decision being executed, the guide
-- (Concierge) state and the navigation state. Shows what moves a pawn the player is not moving.
-- v0.9.149 controls the player can change, and the on-screen hint that names them.
R.VK = { [0x08] = "Backspace", [0x09] = "Tab", [0x0D] = "Enter", [0x13] = "Pause", [0x14] = "Caps Lock", [0x20] = "Space", [0x21] = "Page Up",
         [0x22] = "Page Down", [0x23] = "End", [0x24] = "Home", [0x25] = "Left", [0x26] = "Up", [0x27] = "Right", [0x28] = "Down",
         [0x2D] = "Insert", [0x2E] = "Delete", [0x6A] = "Numpad *", [0x6B] = "Numpad +", [0x6D] = "Numpad -", [0x6E] = "Numpad .",
         [0x6F] = "Numpad /", [0x90] = "Num Lock", [0x91] = "Scroll Lock", [0xBA] = ";", [0xBB] = "=", [0xBC] = ",", [0xBD] = "-",
         [0xBE] = ".", [0xBF] = "/", [0xC0] = "`", [0xDB] = "[", [0xDC] = "\\", [0xDD] = "]", [0xDE] = "'" }
R.vk_name = function(vk)
    if not vk or vk == 0 then return "none" end
    if R.VK[vk] then return R.VK[vk] end
    if (vk >= 0x30 and vk <= 0x39) or (vk >= 0x41 and vk <= 0x5A) then return string.char(vk) end
    if vk >= 0x60 and vk <= 0x69 then return "Numpad " .. (vk - 0x60) end
    if vk >= 0x70 and vk <= 0x87 then return "F" .. (vk - 0x6F) end
    return "key " .. vk
end
R.KEY_DEFAULTS = { toggle_possess = 0x75, cycle_pawn = 0x76, warp_arisen = 0x77, party_heal = 0x6E, party_warp = 0x67, coop = 0x75, coop_ctrl = true,
                   skill1 = 0x61, skill2 = 0x62, skill3 = 0x63, skill4 = 0x64, skill5 = 0x65, skill6 = 0x66,
                   jump_arisen = 0x70, jump_arisen_ctrl = true, jump_pawn1 = 0x71, jump_pawn1_ctrl = true,
                   jump_pawn2 = 0x72, jump_pawn2_ctrl = true, jump_pawn3 = 0x73, jump_pawn3_ctrl = true,
                   jump_pawn4 = 0, jump_pawn5 = 0, jump_pawn6 = 0, jump_pawn7 = 0, jump_pawn8 = 0 }
-- 0.9.172: go straight to a character. Pawn n = the n-th party member in party order (pawn 1 = the main pawn).
R.JUMP_MAX = 8
R.jump_names = {}
R.jump_party = function()
    local party = get_party()
    table.sort(party, function(a, b) return a.idx < b.idx end)
    return party
end
R.jump_to = function(want, label)
    local note = function(t) R.note = { text = t, t_end = os.clock() + 2.5 } end
    if want == nil then note("No " .. tostring(label) .. " in the party"); return false end
    -- co-op, any combination: this is player 1's choice
    if cfg.coop_any and R.cp and R.cp.on then
        local c = R.cp
        if want == c.char[1] then return false end
        if want == c.char[2] then note(tostring(label) .. " is player 2's"); return false end
        if type(want) == "number" and R.held_by and R.held_by(want) and R.held_by(want) >= 3 then
            note(tostring(label) .. " is player " .. R.held_by(want) .. "'s"); return false
        end
        if not R.cp_quiet_ok() then return false end
        return R.cp_apply({ [1] = want, [2] = c.char[2] }, "player 1's key") ~= false
    end
    if coop.active then note("In co-op without 'Any combination', use the take-control key"); return false end
    if want == "arisen" then
        if state.active then release_possession("key: the Arisen") end
        return true
    end
    if state.active and state.pawn_idx == want then return false end
    cfg.selected_pawn_idx = want
    save_cfg()
    start_possession(want)
    return true
end
R.jump_tick = function()
    if R.cap then return end
    local now = os.clock()
    if now - (R.jump_names_t or 0) > 1.0 then -- names for the settings window (read here, on the game thread)
        R.jump_names_t = now
        local t = {}
        for i, e in ipairs(R.jump_party()) do t[i] = tostring(e.name) end
        R.jump_names = t
    end
    if R.key_hit("jump_arisen") then R.jump_to("arisen", "the Arisen") return end
    for k = 1, R.JUMP_MAX do
        if R.key_hit("jump_pawn" .. k) then
            local e = R.jump_party()[k]
            R.jump_to(e and e.idx or nil, e and tostring(e.name) or ("pawn " .. k))
            return
        end
    end
end
-- the controller combination for "take control / next pawn" (0 in the settings = L1 + left stick click)
R.take_mask = function()
    local m = tonumber(cfg.pad.take) or 0
    if m ~= 0 then return m end
    local pv = coop_pad_values()
    return (pv.LTrigTop or 0x100) | (pv.LStickPush or 0)
end
R.combo_name = function(mask)
    local t = R.btn_text(mask)
    if not t then return nil end
    local ok, x = pcall(R.pad_label, t)
    return (ok and type(x) == "string") and x or t
end
-- the pawn L1 + left stick click goes to while a pawn is played: the next one in party order, wrapping round
-- v0.9.150: (1) a character picked with the arrows a moment ago comes first: while the selection arrow is still up
-- (R.ping, 3 s) the combination goes to that pick, pawn or Arisen. (2) Otherwise the next pawn in party order, and
-- after the last pawn the Arisen ("arisen"), so one button walks the whole party round. With cycle_skip_arisen the
-- round is pawns only (0.9.148's behaviour). nil = nobody to go to.
R.next_pawn = function(party)
    if R.ping and os.clock() < (R.ping.t_end or 0) then
        if R.sel_kind == "arisen" then return "arisen", true end
        if R.sel_kind == "pawn" and R.sel_idx ~= nil and R.sel_idx ~= state.pawn_idx then
            for _, e in ipairs(party) do if e.idx == R.sel_idx then return e, true end end
        end
    end
    local nxt
    for _, e in ipairs(party) do if e.idx > state.pawn_idx and (not nxt or e.idx < nxt.idx) then nxt = e end end
    if nxt then return nxt end
    if not cfg.cycle_skip_arisen then return "arisen" end
    for _, e in ipairs(party) do if e.idx ~= state.pawn_idx and (not nxt or e.idx < nxt.idx) then nxt = e end end
    return nxt
end
-- v0.9.154 cheat, off by default: special arrows are free while a pawn is played (possession or co-op). Requested:
-- an Archer pawn needs Explosive / Blighting / Tarring / Drenching Arrows in its bag for the matching skills and
-- uses them up. Read live: the four items are ids 169 / 166 / 168 / 167, and ItemManager keeps running counts of
-- the PLAYER's (_ExplosiveArrowNum was 11 = the Arisen's 11 Explosive Arrows, the pawns held none).
-- (1) Not used up: every ItemManager call that removes items by id (deleteItem / deleteItemNoLock / deletePartyItem
--     and their overloads with an item id) is skipped for those four ids, and so is a negative addArrowNum.
-- (2) Not needed (cheat_free_arrows_nobag): the four arrow counters and getHaveNum for those ids answer at least 1.
-- What the game really asks before a special-arrow skill, and which call takes the arrow away, is not known from
-- names alone, so every hook counts what it saw (R.arrows.n, in the developer status file) for the first test.
R.arrows = { ids = { [166] = true, [167] = true, [168] = true, [169] = true }, n = {},
             KIND = { [17] = "Bomb", [18] = "Water", [19] = "Oil", [20] = "Poison" } } -- HumanCustomSkillID Job02_SpecialAllow*
R.arrow_on = function() return cfg.cheat_free_arrows and state.active end
-- v0.9.162: the "not needed in the bag" half is switched off for good in this build. With it on the game crashed twice
-- (2026-11-17 and 2026-11-18 about [time]): the forced with-arrow action works for a shot or two, then fires
-- plain arrows, then the game goes down. The code stays for a later look with the decompile; the setting is forced
-- off here whatever the config file says, and the menu line is gone.
cfg.cheat_free_arrows_nobag = false
R.arrow_hook = function()
    local A = R.arrows
    if A.hooked ~= nil or not cfg.cheat_free_arrows then return end
    A.hooked = false
    local ok, err = pcall(function()
        local im = sdk.find_type_definition("app.ItemManager")
        local function bump(k) A.n[k] = (A.n[k] or 0) + 1 end
        for _, sig in ipairs({ "deleteItem(System.Int32, System.Int32, app.CharacterID)", "deleteItem(System.Int32, System.Int32, app.Character)",
                               "deleteItemNoLock(System.Int32, System.Int32, app.CharacterID)", "deleteItemNoLock(System.Int32, System.Int32, app.CharacterID, System.Int32)",
                               "deletePartyItem(System.Int32, System.Int32)", "deletePartyItemNoLock(System.Int32, System.Int32, System.Boolean, System.Boolean)" }) do
            local m = im:get_method(sig)
            if m then
                local key = "kept " .. sig:match("^(%w+)") .. (sig:find("Character%)") and " (chara)" or "")
                local owner_kind = sig:find("app.CharacterID", 1, true) and "id" or (sig:find("app.Character%)") and "chara" or nil)
                sdk.hook(m, function(args)
                    if not cfg.cheat_free_arrows then return end
                    local id = sdk.to_int64(args[3]) & 0xFFFFFFFF
                    if not A.ids[id] then return end
                    -- v0.9.163: also while nobody is played, for arrows that are not the Arisen's (the point of the
                    -- cheat, in the requester's words: if the pawns use their arrows up on their own there is nothing
                    -- left to fire when you take one over). The Arisen's own arrows are spared only while a pawn is played.
                    local mine = state.active
                    if not mine and owner_kind == "id" and A.ar_id then mine = (sdk.to_int64(args[5]) & 0xFFFFFFFF) ~= A.ar_id end
                    if not mine and owner_kind == "chara" and A.ar_addr then mine = sdk.to_int64(args[5]) ~= A.ar_addr end
                    if mine then
                        bump(key)
                        if not A.logged then A.logged = true; log_msg("Free arrows: a special arrow (item " .. id .. ") was not used up") end
                        return sdk.PreHookResult.SKIP_ORIGINAL
                    end
                end, function(r) return r end)
            else A.n["missing " .. sig] = 1 end
        end
        for _, sig in ipairs({ "deleteItem(app.ItemDefine.StorageData, System.Int32)", "deleteItemNoLock(app.ItemDefine.StorageData, System.Int32, System.Boolean)" }) do
            local m = im:get_method(sig) -- by stored-item record: only counted, the id is not readable here
            if m then sdk.hook(m, function(args) if R.arrow_on() then bump("seen by-record " .. sig:match("^(%w+)")) end end, function(r) return r end) end
        end
        local an = im:get_method("addArrowNum(app.CharacterID, System.Int32, System.Int32)")
        if an then
            sdk.hook(an, function(args)
                if not cfg.cheat_free_arrows then return end
                if not state.active and not (A.ar_id and (sdk.to_int64(args[3]) & 0xFFFFFFFF) ~= A.ar_id) then return end
                local v = sdk.to_int64(args[5]) & 0xFFFFFFFF
                bump("addArrowNum " .. ((v >= 0x80000000) and "minus" or "plus"))
                if v >= 0x80000000 then return sdk.PreHookResult.SKIP_ORIGINAL end
            end, function(r) return r end)
        end
        for _, g in ipairs({ "get_PoisonArrowNum", "get_WaterArrowNum", "get_OilArrowNum", "get_ExplosiveArrowNum" }) do
            local m = im:get_method(g)
            if m then
                sdk.hook(m, function(args) end, function(r)
                    if not (R.arrow_on() and cfg.cheat_free_arrows_nobag) then return r end
                    bump(g)
                    if (sdk.to_int64(r) & 0xFFFFFFFF) < 1 then bump("raised " .. g); return sdk.to_ptr(1) end
                    return r
                end)
            end
        end
        for _, sig in ipairs({ "getHaveNum(System.Int32, app.CharacterID)", "getHaveNum(System.Int32, app.Character)" }) do
            local m = im:get_method(sig)
            if m then
                sdk.hook(m, function(args)
                    thread.get_hook_storage().dpc_arrow = (R.arrow_on() and cfg.cheat_free_arrows_nobag and A.ids[sdk.to_int64(args[3]) & 0xFFFFFFFF]) or false
                end, function(r)
                    if thread.get_hook_storage().dpc_arrow then
                        bump("asked getHaveNum")
                        if (sdk.to_int64(r) & 0xFFFFFFFF) < 1 then bump("raised getHaveNum"); return sdk.to_ptr(1) end
                    end
                    return r
                end)
            end
        end
        -- v0.9.155: 0.9.154's "not needed" did not work: with no arrows the Archer pawn played the missing-arrow action
        -- although getHaveNum had been raised to 1 ten times (the counter getters were never asked). The action is
        -- chosen by Job02ActionSelector.getSpecialArrowAction(Boolean, HumanCustomSkillID, String), which hands back
        -- "Job02_NoSpecialArrow" / "Job02_NoClimbingSpecialArrow" when there is no arrow. Assumption, to be shown by
        -- the first test: the String argument is the action it would have returned with an arrow. When the answer is
        -- one of the two "no arrow" actions, that argument is returned instead. Both strings are kept for the status
        -- file (arrows.last_action) so a wrong assumption shows at once.
        local sm = sdk.find_type_definition("app.Job02ActionSelector"):get_method("getSpecialArrowAction(System.Boolean, app.HumanCustomSkillID, System.String)")
        if sm then
            sdk.hook(sm, function(args)
                local hs = thread.get_hook_storage()
                hs.dpc_arrow_arg = (R.arrow_on() and cfg.cheat_free_arrows_nobag) and args[5] or nil
                hs.dpc_arrow_flag = sdk.to_int64(args[3]) & 1
            end, function(r)
                local hs = thread.get_hook_storage()
                local arg = hs.dpc_arrow_arg
                if not arg then return r end
                local out = r
                pcall(function()
                    local rs = sdk.to_managed_object(r)
                    local as = sdk.to_managed_object(arg)
                    local rt = rs and tostring(rs:call("ToString")) or "nil"
                    local at = as and tostring(as:call("ToString")) or "nil"
                    bump("asked getSpecialArrowAction")
                    A.n.last_action = string.format("flag %s, argument '%s', answer '%s'", tostring(hs.dpc_arrow_flag), at, rt)
                    if rt:find("NoSpecialArrow", 1, true) or rt:find("NoClimbingSpecialArrow", 1, true) then
                        if as and at ~= "" and at ~= "nil" and not at:find("NoSpecialArrow", 1, true) then
                            bump("swapped no-arrow action")
                            out = arg
                        else
                            bump("no-arrow action, nothing to swap in")
                        end
                    end
                end)
                return out
            end)
        else A.n["missing getSpecialArrowAction"] = 1 end
        -- v0.9.156 diagnostics: the action the Archer's selector hands back for a weapon skill
        local cm = sdk.find_type_definition("app.Job02ActionSelector"):get_method("getCustomSkillAction(app.HumanCustomSkillID, app.LocomotionSpeedTypeEnum)")
        if cm then
            sdk.hook(cm, function(args) thread.get_hook_storage().dpc_arrow_skill = R.arrow_on() and (sdk.to_int64(args[3]) & 0xFFFFFFFF) or nil end, function(r)
                local id = thread.get_hook_storage().dpc_arrow_skill
                local out = r
                if id then pcall(function()
                    local rs = sdk.to_managed_object(r)
                    local rt = rs and tostring(rs:call("ToString")) or "nil"
                    bump("asked getCustomSkillAction")
                    A.n.last_skill_action = string.format("skill %d -> '%s'", id, rt)
                    -- v0.9.157: this is where the no-arrow action comes from (read live on 0.9.156: skill 19, the oil
                    -- arrow, -> 'Job02_NoSpecialArrow' with every count raised). The answer is replaced by the action
                    -- of the same skill with an arrow, by name: aiming -> Job02_PrepareSpecialArrow<Kind>, not aiming
                    -- -> Job02_SpecialArrow<Kind>WithoutAim, climbing -> Job02_ClimbingSpecialArrow<Kind> (names from
                    -- the game's action enums; which one the game itself returns with an arrow has not been seen).
                    -- The bow carries the four arrow props whether or not the bag holds arrows (read live).
                    local kind = A.KIND[id]
                    if kind and cfg.cheat_free_arrows_nobag then
                        local want
                        if rt == "Job02_NoSpecialArrow" then want = "Job02_PrepareSpecialArrow" .. kind
                        elseif rt == "Job02_NoSpecialArrowWithoutAim" then want = "Job02_SpecialArrow" .. kind .. "WithoutAim"
                        elseif rt == "Job02_NoClimbingSpecialArrow" then want = "Job02_ClimbingSpecialArrow" .. kind end
                        if want then
                            A.str = A.str or {}
                            if not A.str[want] then local ms = sdk.create_managed_string(want); A.str[want] = ms and ms:add_ref() end
                            if A.str[want] then
                                out = sdk.to_ptr(A.str[want]:get_address())
                                bump("swapped to " .. want)
                            end
                        end
                    end
                end) end
                return out
            end)
        end
        A.hooked = true
        log_msg("Free arrows: hooks installed")
    end)
    if not ok then dev_error("free arrows hook", err) end
end
-- v0.9.156 third try at "not needed". On 0.9.155 neither getHaveNum nor getSpecialArrowAction was called when the
-- skill was pressed (all counters empty after a minute of trying), so the choice is made inside native code. What
-- is left to read there: ItemManager's four counters, read as fields. They hold the PLAYER's arrows (11 with the
-- Arisen's 11 Explosive Arrows) and a played pawn goes through the player's input, so the guess is that the game
-- looks at these for whoever the player is driving. While the cheat is on and a pawn is played, each counter that
-- is below 1 is held at 1; when the pawn is released or the cheat goes off, a counter this code raised and that
-- still reads 1 goes back to 0. A negative addArrowNum is skipped (0.9.154), so a shot does not take it below 1.
R.arrow_tick = function()
    if cfg.cheat_free_arrows and os.clock() >= (R.arrows.ar_next or 0) then -- v0.9.163: who the Arisen is, for the hooks
        R.arrows.ar_next = os.clock() + 3.0
        pcall(function()
            local ar = sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer")
            local cid = ar and ar:call("get_CharaID")
            if type(cid) == "userdata" then cid = cid:get_field("value__") end
            R.arrows.ar_id = type(cid) == "number" and (cid & 0xFFFFFFFF) or nil
            R.arrows.ar_addr = ar and ar:get_address() or nil
        end)
    end
    -- v0.9.160: the four counters are what the skill list prints in front of a special-arrow skill ("00 Incendiary
    -- Shot"). They count the Arisen's arrows, so a played Archer pawn carrying five of each read 00 (screenshots).
    -- While a pawn is played (not co-op, where the HUD is the Arisen's) they are set to the played pawn's own
    -- counts twice a second, and to the Arisen's again on release. With the experimental no-bag cheat on, a count
    -- of 0 is shown as 1. Display only: the game's own check for the skill does not read these (0.9.156).
    local A = R.arrows
    local on = cfg.pawn_arrow_counts and state.active and not coop.active and state.pawn_chara ~= nil
    if not on and not A.shown then return end
    local now = os.clock()
    if on and now < (A.next or 0) then return end
    A.next = now + 0.5
    pcall(function()
        local im = sdk.get_managed_singleton("app.ItemManager")
        if not im then return end
        local who = on and state.pawn_chara or sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer")
        if not who then return end
        for f, id in pairs({ _PoisonArrowNum = 166, _WaterArrowNum = 167, _OilArrowNum = 168, _ExplosiveArrowNum = 169 }) do
            local n = im:call("getHaveNum(System.Int32, app.Character)", id, who)
            if type(n) == "number" then
                if on and n < 1 and R.arrow_on() and cfg.cheat_free_arrows_nobag then n = 1 end
                if im:get_field(f) ~= n then
                    im:set_field(f, n)
                    A.n["set " .. f] = (A.n["set " .. f] or 0) + 1
                end
            end
        end
        A.shown = on or nil
    end)
end
-- 0.9.172-dev29 (the tester's idea after the "not needed in the bag" crashes): give a played Archer one real special arrow
-- of each kind it has none of, through the game's own ItemManager.getItem, so the skill finds it the normal way.
-- With free arrows on it is never used up; with it off, the next check gives another. The four arrow items weigh
-- nothing while this is on (ItemCommonParam._Weight 0, the game's value put back when it goes off), so a pawn's
-- weight class never flips back and forth. Every 2 s, for each played character (player 1's pawn, player 2's,
-- players 3+), Archers only.
R.arrow_give = { given = 0, w0 = nil, last = nil }
R.arrow_give_tick = function()
    local G = R.arrow_give
    local on = cfg.cheat_free_arrows and cfg.free_arrows_give ~= false
    local im = sdk.get_managed_singleton("app.ItemManager")
    if not im then return end
    local now = os.clock()
    -- dev32: no longer weightless for everyone (the tester: "that made all arrows no weight"); the item weights the dev29
    -- build changed are put back, and only the arrows DPC gave are taken off their carrier's weight (R.arrow_weight).
    if G.w0 then
        for id, w in pairs(G.w0) do
            pcall(function() local d = im:call("getItemData(System.Int32)", id); if d and w then d:set_field("_Weight", w) end end)
        end
        G.w0 = nil
    end
    if not on or now < (G.next or 0) then return end
    pcall(R.arrow_weight_update, im)
    G.next = now + 2.0
    local who = {}
    if state.active and state.pawn_chara and state.pawn_job == 2 then who[#who + 1] = state.pawn_chara end
    if R.s2 and R.s2.active and R.s2.chara and R.s2.job == 2 then who[#who + 1] = R.s2.chara end
    if R.np then for _, sl in pairs(R.np.slots) do if sl.active and sl.chara and sl.job == 2 then who[#who + 1] = sl.chara end end end
    for _, ch in ipairs(who) do
        for id in pairs(R.arrows.ids) do
            pcall(function()
                local n = im:call("getHaveNum(System.Int32, app.Character)", id, ch)
                if type(n) == "number" and n < 1 then
                    -- dev31: without the "obtained" popup (the tester saw one per arrow): GetItemOption.Default with IsNotice
                    -- (and the log / new-mark flags) off; the plain call if that overload refuses
                    local okq = pcall(function()
                        local td = sdk.find_type_definition("app.ItemDefine.GetItemOption")
                        local opt = td:get_field("Default"):get_data(nil)
                        opt:set_field("IsNotice", false)
                        opt:set_field("IsHistory", false)
                        opt:set_field("IsNewMark", false)
                        opt:set_field("IsRecord", false)
                        im:call("getItem(System.Int32, System.Int32, app.Character, app.ItemDefine.GetItemOption)", id, 1, ch, opt)
                    end)
                    if not okq then im:call("getItem(System.Int32, System.Int32, app.Character)", id, 1, ch); G.loud = (G.loud or 0) + 1 end
                    -- remember who got it (by character id) so its weight can be taken off that character only
                    local cid = ch:call("get_CharaID")
                    if type(cid) == "userdata" then cid = cid:get_field("value__") end
                    if type(cid) == "number" then
                        cid = cid & 0xFFFFFFFF
                        G.owed = G.owed or {}
                        G.owed[cid] = G.owed[cid] or { chara = ch, ids = {} }
                        G.owed[cid].ids[id] = (G.owed[cid].ids[id] or 0) + 1
                        G.owed[cid].chara = ch
                    end
                    G.given = G.given + 1
                    G.last = string.format("%d to %s", id, tostring(call(ch, "get_CharaIDString")))
                    R.arrows.n["given"] = (R.arrows.n["given"] or 0) + 1
                end
            end)
        end
    end
end

-- 0.9.172-dev30 downed-party alert (the tester lost two pawns to the Rift without noticing they were down while playing a
-- pawn in co-op with the camera pulled back). While a pawn is played or co-op runs, every party member that is down
-- (get_IsDead: down and waiting for a revive) is named at the top of the screen with how far and which way from the
-- character you play, and for how long it has been down. cfg.down_alert.
R.down = { t0 = {} }
R.down_list = function()
    local out = {}
    if not (cfg.down_alert ~= false and (state.active or coop.active)) then R.down.t0 = {}; return out end
    local me = state.pawn_chara or state.arisen_chara
    local mx, _, mz = brain_pos(me)
    local yaw = R.cam_yaw and R.cam_yaw() or nil
    local now = os.clock()
    local seen = {}
    local who = {}
    for _, e in ipairs(R.party_all() or {}) do who[#who + 1] = { chara = e.chara, name = e.name } end
    if state.active and state.arisen_chara then who[#who + 1] = { chara = state.arisen_chara, name = "the Arisen" } end
    for _, w in ipairs(who) do
        local ok, dead = pcall(function() return w.chara:call("get_IsDead") == true end)
        if ok and dead then
            local key = w.chara:get_address()
            seen[key] = true
            R.down.t0[key] = R.down.t0[key] or now
            local x, _, z = brain_pos(w.chara)
            local where = ""
            if x and mx then
                local d = math.sqrt((x - mx) ^ 2 + (z - mz) ^ 2)
                local dir = ""
                if yaw then
                    local a = math.deg(brain_angdiff(math.atan(x - mx, z - mz), yaw))
                    if math.abs(a) <= 35 then dir = "ahead" elseif math.abs(a) >= 145 then dir = "behind you"
                    elseif a > 0 then dir = "to the right" else dir = "to the left" end
                end
                where = string.format("%.0f m %s", d, dir)
            end
            out[#out + 1] = { name = w.name, where = where, secs = now - R.down.t0[key] }
        end
    end
    for k in pairs(R.down.t0) do if not seen[k] then R.down.t0[k] = nil end end
    return out
end
re.on_frame(function()
    local ok, err = pcall(function()
        if R.hud_hidden() then return end
        local list = R.down_list()
        if #list == 0 then return end
        local hx, hy, hw, hh = R.hud_rect()
        imgui.set_next_window_pos(Vector2f.new(hx + hw * 0.5 - 220, hy + hh * 0.09), 1)
        imgui.begin_window("DirectPawnControl_Down", nil, (1 << 0) | (1 << 1) | (1 << 3) | (1 << 6))
        local blink = (math.floor(os.clock() * 2) % 2 == 0) and 0xFF4040FF or 0xFF6060E0
        for _, d in ipairs(list) do
            imgui.text_colored(string.format("%s is DOWN - %s - revive them (%d s)", tostring(d.name), d.where, math.floor(d.secs)), blink)
        end
        imgui.end_window()
    end)
    if not ok then dev_error("down alert", err) end
end)

-- dev32: the arrows DPC gave weigh nothing for the character carrying them, and nothing else changes. Like a weight
-- bonus, but exact: ItemManager.getStorageWeight (both overloads, kg) and getStorageWeightInt (the same in the game's
-- integer unit, scale read from the two) answer less by the weight of the given arrows that character still holds
-- (at most what DPC gave, so arrows it bought or found still count). Recomputed every 2 s; G.kg[charaId] = kg.
R.arrow_weight_update = function(im)
    local G = R.arrow_give
    G.kg = {}
    for cid, o in pairs(G.owed or {}) do
        local kg = 0.0
        for id, n in pairs(o.ids) do
            local have = 0
            pcall(function() have = im:call("getHaveNum(System.Int32, app.Character)", id, o.chara) or 0 end)
            local d = im:call("getItemData(System.Int32)", id)
            local w = d and d:call("get_WeightF") or 0.0
            if have < n then o.ids[id] = have; n = have end
            kg = kg + math.max(0, n) * (tonumber(w) or 0.0)
        end
        if kg > 0 then G.kg[cid] = kg end
    end
    if G.hooked == nil then
        G.hooked = false
        local td = sdk.find_type_definition("app.ItemManager")
        -- by_obj: the argument is an app.Character; otherwise an app.CharacterID (an enum value, never a pointer)
        local function cid_of(a, by_obj)
            local ok, v = pcall(function()
                if by_obj then
                    local o = sdk.to_managed_object(a)
                    local x = o and o:call("get_CharaID")
                    if type(x) == "userdata" then x = x:get_field("value__") end
                    return x
                end
                return sdk.to_int64(a)
            end)
            return ok and type(v) == "number" and (v & 0xFFFFFFFF) or nil
        end
        local function hook(sig, is_int, by_obj)
            local m = td and td:get_method(sig)
            if not m then return end
            sdk.hook(m, function(args)
                local st = thread.get_hook_storage()
                st.aw_cid = (G.kg and next(G.kg)) and cid_of(args[3], by_obj) or nil
            end, function(r)
                local kg = G.kg and G.kg[thread.get_hook_storage().aw_cid or -1]
                if not kg then return r end
                if is_int then
                    local v = sdk.to_int64(r) & 0xFFFFFFFF
                    if v >= 0x80000000 then v = v - 0x100000000 end
                    local scale = G.int_scale or 100.0
                    return sdk.to_ptr(math.max(0, v - math.floor(kg * scale + 0.5)))
                end
                local f = sdk.to_float(r)
                return sdk.float_to_ptr(math.max(0.0, f - kg))
            end)
        end
        hook("getStorageWeight(app.Character)", false, true)
        hook("getStorageWeight(app.CharacterID)", false, false)
        hook("getStorageWeightInt(app.CharacterID)", true, false)
        G.hooked = true
    end
    -- the integer unit, from one character's two readings (before our change: compare raw values with no debt)
    pcall(function()
        local cm = sdk.get_managed_singleton("app.CharacterManager")
        if not cm then return end
        local ar = cm:call("get_ManualPlayer")
        if not ar then return end
        local cid = ar:call("get_CharaID")
        local cn = type(cid) == "userdata" and cid:get_field("value__") or cid
        if type(cn) == "number" and G.kg and (G.kg[cn & 0xFFFFFFFF] or 0) > 0 then return end  -- our own subtraction would skew it
        local f = im:call("getStorageWeight(app.Character)", ar)
        local i = im:call("getStorageWeightInt(app.CharacterID)", cid)
        if type(f) == "number" and f > 1.0 and type(i) == "number" and i > 0 then G.int_scale = i / f end
    end)
end

-- 0.9.172-dev35: Pawn Tactical Wheel (another mod, Lua) opens on L1 + R3 read from the game's merged controller, so in
-- co-op player 2's L1 + R3 (or player 1's R3 target key with L1 held) opened it. All REFramework scripts share one Lua
-- state, so while co-op runs we blank its pad trigger in its loaded input module (IN.BINDS.pad_open_trig = 0; its own
-- check treats 0 as unbound) and put it back after. Its saved config is a separate table and is never touched.
R.ptw = { saved = nil }
R.ptw_tick = function()
    local IN = package.loaded["PawnTacticalWheel.input"]
    if type(IN) ~= "table" or type(IN.BINDS) ~= "table" then return end
    local want = cfg.coop_block_ptw ~= false and (coop.active or (R.cp and R.cp.on)) and true or false
    if want and R.ptw.saved == nil and (IN.BINDS.pad_open_trig or 0) ~= 0 then
        R.ptw.saved = IN.BINDS.pad_open_trig
        IN.BINDS.pad_open_trig = 0
        if IN.W then IN.W.pad_mod_held = false end
    elseif not want and R.ptw.saved ~= nil then
        if (IN.BINDS.pad_open_trig or 0) == 0 then IN.BINDS.pad_open_trig = R.ptw.saved end -- unless the player rebound it meanwhile
        R.ptw.saved = nil
    end
end
re.on_frame(function() pcall(R.ptw_tick) end)
re.on_script_reset(function()
    local IN = package.loaded["PawnTacticalWheel.input"]
    if R.ptw.saved ~= nil and type(IN) == "table" and IN.BINDS and (IN.BINDS.pad_open_trig or 0) == 0 then IN.BINDS.pad_open_trig = R.ptw.saved end
end)

re.on_script_reset(function()
    local G = R.arrow_give
    if not (G and G.w0) then return end
    pcall(function()
        local im = sdk.get_managed_singleton("app.ItemManager")
        for id, w in pairs(G.w0) do local d = im:call("getItemData(System.Int32)", id); if d and w then d:set_field("_Weight", w) end end
    end)
end)

-- v0.9.153 co-op: the next pawn for player 2, pawns only (the Arisen is player 1's), wrapping round
R.next_pawn_only = function(party)
    -- 0.9.172: pawns played by players 3+ are not offered
    local free = {}
    for _, e in ipairs(party) do
        local held = false
        if R.np then for _, sl in pairs(R.np.slots) do if sl.active and sl.idx == e.idx then held = true end end end
        if not held then free[#free + 1] = e end
    end
    party = free
    local nxt
    for _, e in ipairs(party) do if e.idx > state.pawn_idx and (not nxt or e.idx < nxt.idx) then nxt = e end end
    if nxt then return nxt end
    for _, e in ipairs(party) do if e.idx ~= state.pawn_idx and (not nxt or e.idx < nxt.idx) then nxt = e end end
    return nxt
end
-- choosing a key or a button combination in the settings window. R.cap = { kind = "key" | "pad", id = <name in
-- cfg.keys / cfg.pad>, t0 }. Keys: the first key that goes down after everything was let go (Esc cancels).
-- Controller: at least two buttons held together for 0.8 s (one button alone would take a button from the game).
R.cap_tick = function()
    local c = R.cap
    if not c then return end
    local now = os.clock()
    if now - c.t0 > 8.0 or S.is_key_down_safe(0x1B) then R.cap, R.cap_quiet, R.cap_msg = nil, now + 0.5, "cancelled"; return end
    if c.kind == "key" then
        local down
        for vk = 0x08, 0xDE do
            if vk ~= 0x10 and vk ~= 0x11 and vk ~= 0x12 and vk ~= 0x1B and not (vk >= 0x5B and vk <= 0x5D) and not (vk >= 0xA0 and vk <= 0xB7) then
                if S.is_key_down_safe(vk) then down = vk; break end
            end
        end
        if not c.armed then
            if not down and now - c.t0 > 0.2 then c.armed = true end
        elseif down then
            cfg.keys[c.id] = down
            cfg.keys[c.id .. "_ctrl"] = S.is_key_down_safe(0x11)
            save_cfg()
            R.clash_logged = nil
            R.cap, R.cap_quiet, R.cap_msg = nil, now + 0.6, "set to " .. R.vk_name(down)
        end
    else
        local b = S.pad_buttons or 0
        local n, x = 0, b
        while x ~= 0 do n = n + (x & 1); x = x >> 1 end
        if n >= 2 and b == c.last then
            if now - (c.since or now) >= 0.8 then
                cfg.pad[c.id] = b
                save_cfg()
                R.cap, R.cap_quiet, R.cap_msg = nil, now + 1.0, "set to " .. tostring(R.combo_name(b) or b)
            end
        else
            c.last, c.since = b, now
        end
    end
end
-- the hint line: what the take-control button does right now, with the name of who it goes to. Built twice a
-- second here (game thread), drawn in on_frame. Controller wording while the controller was the last thing used,
-- keyboard wording otherwise.
R.hint_tick = function()
    local now = os.clock()
    if (S.pad_buttons or 0) ~= 0 or math.abs(S.pad_stick_x or 0) + math.abs(S.pad_stick_y or 0) > 0.5 then R.last_dev = "pad"
    elseif S.is_key_down_safe(0x57) or S.is_key_down_safe(0x41) or S.is_key_down_safe(0x53) or S.is_key_down_safe(0x44)
        or S.is_key_down_safe(cfg.keys.toggle_possess) or S.is_key_down_safe(cfg.keys.cycle_pawn) then R.last_dev = "kbm" end
    if now < (R.hint_next or 0) then return end
    R.hint_next = now + 0.2
    R.hint = nil
    if not cfg.hint_controls then return end
    local party = get_party()
    if #party == 0 then return end
    if coop.active then -- v0.9.153: player 2's one control
        local nxt = cfg.coop_p2_switch and cfg.pad_l1_l3_possess and state.active and R.next_pawn_only(party) or nil
        local take = nxt and R.combo_name(R.take_mask())
        if take then R.hint = "Player 2   " .. take .. ":  Control " .. tostring(nxt.name) end
        return
    end
    local pad = (R.last_dev or (S.pad_device_ok and "pad" or "kbm")) == "pad"
    local parts = {}
    local take = pad and (cfg.pad_l1_l3_possess and R.combo_name(R.take_mask()) or nil) or (cfg.keys.toggle_possess ~= 0 and R.key_label("toggle_possess") or nil)
    if state.active then
        if pad then
            local nxt = R.next_pawn(party)
            if take and nxt then parts[#parts + 1] = take .. ":  Control " .. (nxt == "arisen" and "Arisen" or tostring(nxt.name)) end
            local back = (tonumber(cfg.pad.back) or 0) ~= 0 and R.combo_name(cfg.pad.back) or (cfg.pad_hold_select and "Hold D-pad down" or nil)
            if back and nxt ~= "arisen" then parts[#parts + 1] = back .. ":  Control Arisen" end
        else
            local to = (R.sel_kind == "pawn" and R.sel_name) or "Arisen"
            if take then parts[#parts + 1] = take .. ":  Control " .. tostring(to) end
            if cfg.keys.cycle_pawn ~= 0 and #party > 1 then parts[#parts + 1] = R.key_label("cycle_pawn") .. ":  Select" end
        end
    else
        local sel = party[1]
        for _, e in ipairs(party) do if e.idx == cfg.selected_pawn_idx then sel = e end end
        if take then parts[#parts + 1] = take .. ":  Control " .. tostring(sel.name) end
        if #party > 1 then
            if pad then if cfg.pad_hold_select then parts[#parts + 1] = "Hold D-pad left / right:  Select" end
            elseif cfg.keys.cycle_pawn ~= 0 then parts[#parts + 1] = R.key_label("cycle_pawn") .. ":  Select" end
        end
    end
    if #parts > 0 then R.hint = table.concat(parts, "      ") end
end
-- v0.9.96 / 0.9.97 controller D-pad hold. R.dpad_dir: the one D-pad direction held with no shoulder button or trigger.
R.dpad_dir = function(b)
    local pv = coop_pad_values()
    local mods = (pv.LTrigTop or 0) | (pv.LTrigBottom or 0) | (pv.RTrigTop or 0) | (pv.RTrigBottom or 0)
    if (b & mods) ~= 0 then return nil end
    local dir, n = nil, 0
    if (b & (pv.LUp or 0x1)) ~= 0 then dir, n = "up", n + 1 end
    if (b & (pv.LDown or 0x2)) ~= 0 then dir, n = "down", n + 1 end
    if (b & (pv.LLeft or 0x4)) ~= 0 then dir, n = "left", n + 1 end
    if (b & (pv.LRight or 0x8)) ~= 0 then dir, n = "right", n + 1 end
    if n ~= 1 then return nil end
    -- v0.9.98: the mod owns left and right always, down only while a pawn is played (so the game's own hold on
    -- To Me = High Five still works as the Arisen), and never up (Go / hold = Explore stay the game's)
    if dir == "up" or (dir == "down" and not state.active) then return nil end
    return dir
end
-- v0.9.97 a hold must not give the pawn order, a tap must. The game turns the D-pad into an order in
-- app.PawnOrderController (tryGetOrderInput -> tryUpdatePawnOrder(order)). While a D-pad direction is held on the
-- controller, tryUpdatePawnOrder is skipped and the order kept; the tick above gives it on release if the hold
-- time was not reached, and drops it if the hold fired. The pad is read live in the hook (the mod's own poll can
-- be a frame behind on the press). Orders from the keyboard pass untouched.
-- v0.9.110 the Magick Archer's lock-on ring (GuiManager.MagicBowReticle, app.ui020804) is drawn for the Arisen's
-- skills even while a pawn is played (reported: the ring popped up when the Arisen fired a skill). After its update, switch its drawing off while a pawn is played
-- (not co-op: there player 1 is the Arisen and needs it).
-- dev29 player 1's HUD in co-op (card_p1_mode). 3: player 1 gets the same card as everyone, and the game's skill
-- palette (app.ui010201, after lateUpdate) and health / stamina gauge (app.ui020901, after update) are switched off
-- (GameObject DrawSelf, as the Magick Archer ring below); back on as soon as that is not wanted.
R.card_p1_mode = function()
    -- dev52 (the tester: "In split screen, the P1 pane could keep the whole native interface instead of our drawn skill
    -- palette and health and stamina bars ... It's the shared screen that necessitated moving those elements"):
    -- while the screen is split, player 1 gets the game's own HUD (setting card_p1_split_native, on by default).
    if cfg.card_p1_split_native ~= false and R.views_now and R.views_now() then return 1 end
    local m = tonumber(cfg.card_p1_mode) or 1
    if m == 1 and cfg.card_p1 then m = 2 end
    return m
end
R.card_p1_on = function() return R.card_p1_mode() >= 2 end
R.p1hud_want = function()
    return R.card_p1_mode() == 3 and cfg.coop_player_card ~= false and (coop.active or (R.cp and R.cp.on)) or false
end
R.p1hud_hidden = {}
R.p1hud_hook = function()
    if R.p1hud_hooked then return end
    R.p1hud_hooked = true
    -- dev30: and the pawn order / item shortcut cross (app.ui020401, PNL_Pawncommand: Go / Help / Wait / To me)
    for _, e in ipairs({ { "app.ui010201", "lateUpdate" }, { "app.ui020901", "update" }, { "app.ui020401", "update" } }) do
        local td = sdk.find_type_definition(e[1])
        local m = td and td:get_method(e[2])
        if m then
            local key = e[1]
            sdk.hook(m, function(args)
                thread.get_hook_storage().dpc_p1h = args[2]
            end, function(retval)
                local want = R.p1hud_want()
                if want or R.p1hud_hidden[key] then
                    pcall(function()
                        local u = sdk.to_managed_object(thread.get_hook_storage().dpc_p1h)
                        local go = u and u:call("get_GameObject")
                        if not go then return end
                        if want and go:call("get_DrawSelf") == true then
                            go:call("set_DrawSelf", false)
                            R.p1hud_hidden[key] = true
                            R.p1hud_n = (R.p1hud_n or 0) + 1
                        elseif not want and R.p1hud_hidden[key] then
                            go:call("set_DrawSelf", true)
                            R.p1hud_hidden[key] = nil
                        end
                    end)
                end
                return retval
            end)
        end
    end
end
pcall(R.p1hud_hook)
-- dev32 (reported with a screenshot: "Double bars in co-op because pawn name health bar shows up"): while the
-- co-op cards draw health / stamina by the characters (card_bars 2..5), a pawn someone plays loses the game's own
-- nameplate health bar (app.ui022601: CompChara +0x190, HpGauge.Parent panel); the name stays. The other pawns keep it.
R.cards_world_on = function()
    local b = tonumber(cfg.card_bars) or 5
    return cfg.coop_player_card ~= false and cfg.coop_skill_palette ~= false and b >= 2 and b <= 5
        and (coop.active or (R.cp and R.cp.on)) or false
end
R.npl_set, R.npl_hidden = {}, {}
R.npl_tick = function()
    local now = os.clock()
    if now < (R.npl_next or 0) then return end
    R.npl_next = now + 0.25
    local set = {}
    if R.cards_world_on() then
        for _, ch in pairs(R.pglow_now() or {}) do
            local a = ch and addr_of(ch)
            if a and a ~= 0 then set[a] = true end
        end
    end
    R.npl_set = set
    -- dev41: split screen: the game places its nameplates with player 1's camera but draws them over the whole
    -- screen, so one near the line stretched into the next view (reported with a screenshot). Hidden while split.
    R.npl_split = R.views_on and R.views_on() or false
    if (R.npl_fix_left or 0) > 0 then R.npl_fix_left = R.npl_fix_left - 1 end
    R.npl_fixed = R.npl_fixed or {}
    R.npl_any = next(set) ~= nil or next(R.npl_hidden) ~= nil or (R.npl_fix_left or 0) > 0
end
R.npl_hook = function()
    local td = sdk.find_type_definition("app.ui022601")
    local m = td and td:get_method("update")
    if not m then log_msg("nameplate bars: app.ui022601.update not found (game update?)"); return end
    sdk.hook(m, function(args)
        if R.npl_any then thread.get_hook_storage().dpc_npl = args[2] end
    end, function(retval)
        local hs = thread.get_hook_storage()
        local a = hs and hs.dpc_npl
        if not a then return retval end
        hs.dpc_npl = nil
        pcall(function()
            local ui = sdk.to_managed_object(a)
            local gkey = ui and ui:get_address()
            -- dev43: neither the GameObject's DrawSelf (dev41) nor the top panel's Visible (dev42) hid them (read live:
            -- View panel invisible, nameplate still drawn). They are hidden by calcAlpha below. Here, once per
            -- nameplate, undo what dev41 / dev42 may have left (a Reset Scripts loses their bookkeeping).
            if gkey and not R.npl_fixed[gkey] then
                R.npl_fixed[gkey] = true
                pcall(function()
                    local go = ui:call("get_GameObject")
                    if go and not go:call("get_DrawSelf") then go:call("set_DrawSelf", true) end
                    local root = ui:get_field("Parent")
                    for _ = 1, 12 do
                        local up = root and root:call("get_Parent")
                        if not up then break end
                        root = up
                    end
                    if root and not root:call("get_Visible") then root:call("set_Visible", true) end
                end)
            end
            local ch = ui and ui:get_field("CompChara")
            local ca = ch and ch:get_address() or 0
            local hg = ui:get_field("HpGauge")
            local panel = hg and hg:get_field("Parent")
            if not panel then return end
            local key = ui:get_address()
            if R.npl_set[ca] then
                panel:call("set_Visible", false)
                R.npl_hidden[key] = true
            elseif R.npl_hidden[key] then
                panel:call("set_Visible", true)
                R.npl_hidden[key] = nil
            end
        end)
        return retval
    end)
end
pcall(R.npl_hook)
-- dev43: DD2.exe 4.1 app.ui022601.updateDisp(bool) calls calcAlpha() and passes the result to GUIBase.setAlpha every
-- frame. While split, calcAlpha returns 0, so the game itself fades every nameplate out (it places them with one
-- camera over the whole screen). R.npl_alpha_n counts.
R.npl_alpha_n = 0
R.npl_fixed = R.npl_fixed or {}
R.npl_fix_left = 40 -- the update hook runs for a while after load to undo dev41 / dev42 leftovers
R.npl_alpha_hook = function()
    local td = sdk.find_type_definition("app.ui022601")
    local m = td and td:get_method("calcAlpha")
    if not m then log_msg("split screen: app.ui022601.calcAlpha not found (game update?)"); return end
    sdk.hook(m, nil, function(rv)
        if not R.npl_split then return rv end
        R.npl_alpha_n = R.npl_alpha_n + 1
        return sdk.float_to_ptr(0.0)
    end)
end
pcall(R.npl_alpha_hook)
-- dev45 (reported: a played mage couldn't put Flame Boon on the archer next to her). DD2.exe 4.1
-- app.Job03CastBoon.setEnchant (inlined getAimTarget): a normal boon goes to the caster's
-- Character.<AimCharacter>k__BackingField (+0x7d8) when it is set, otherwise to the caster herself; the IsLvEx boon
-- goes to the party in range. The Arisen's aim fills AimCharacter with the ally under the reticle; for a played pawn
-- only DPC's enemy lock-on fills it. So for a played character (not the Arisen, whose own aim works), just before
-- setEnchant the ally nearest where that player looks (their split-screen view, player 1's camera, or else the way
-- the caster faces; within 15 m and 40 degrees) becomes AimCharacter, and the old value is put back after.
-- R.boon_n counts hits, R.boon_last names the last ally.
R.boon_n, R.boon_last, R.boon_dbg = 0, nil, {}
R.boon_trace = true -- dev46: R.boon_dbg keeps the last pick (caster, direction source, each ally's distance / angle)
local function boon_nm(c) local ok, n = pcall(function() return c:call("get_GameObject"):call("get_Name") end); return ok and n or "?" end
R.boon_pick = function(chara, why)
    local L = R.boon_trace and { why } or nil
    local addr = chara:get_address()
    local pn = nil
    for i, c in pairs(R.players()) do if c and c:get_address() == addr then pn = i end end
    if L then L[#L + 1] = "caster=" .. boon_nm(chara) .. " pn=" .. tostring(pn); R.boon_dbg = L end
    if not pn then return nil end
    local cm = sdk.get_managed_singleton("app.CharacterManager")
    local mp = cm and cm:call("get_ManualPlayer")
    if mp and mp:get_address() == addr then if L then L[#L + 1] = "Arisen: native aim" end return nil end
    local p = chara:call("get_Transform"):call("get_Position")
    local fx, fz, src
    local v = R.view_of(R.views_now(), pn)
    if v then
        local x, _, z = R.qrot(v.rot, 0, 0, v.fwd or -1); fx, fz, src = x, z, "view"
    elseif pn == 1 then
        local cam = R.primary_cam()
        local r = cam and cam:call("get_GameObject"):call("get_Transform"):call("get_Rotation")
        if r then local x, _, z = R.qrot({ r.x, r.y, r.z, r.w }, 0, 0, -1); fx, fz, src = x, z, "camera" end
    end
    if not fx then local f = chara:call("get_Transform"):call("get_AxisZ"); fx, fz, src = f.x, f.z, "facing" end
    local fl = math.sqrt(fx * fx + fz * fz); if fl < 1e-4 then return nil end
    fx, fz = fx / fl, fz / fl
    if L then L[#L + 1] = string.format("%s %.2f,%.2f", src, fx, fz) end
    local cands, seen = {}, { [addr] = true }
    local function add(c) if c and sdk.is_managed_object(c) then local a = c:get_address(); if not seen[a] then seen[a] = true; cands[#cands + 1] = c end end end
    add(mp)
    for _, c in pairs(R.players()) do add(c) end
    local pm = sdk.get_managed_singleton("app.PawnManager")
    local pl = pm and pm:call("get_PartyPawnList")
    -- dev55: the party list holds app.Pawn, whose character is get_CachedCharacter (it has no get_Chara: that call
    -- returned nil, so AI pawns were never candidates and only player-controlled characters could get a boon)
    if pl then for i = 0, pl:call("get_Count") - 1 do
        local ph = pl:call("get_Item", i)
        local okc, pc = pcall(function() return ph and ph:call("get_CachedCharacter") end)
        add(okc and pc or nil)
    end end
    local best, best_s = nil, nil
    for _, c in ipairs(cands) do
        local q = c:call("get_Transform"):call("get_Position")
        local dx, dz = q.x - p.x, q.z - p.z
        local d = math.sqrt(dx * dx + dz * dz)
        local cosv = d < 0.5 and 1.0 or (dx * fx + dz * fz) / d
        if L then L[#L + 1] = string.format("%s %.1fm cos %.2f", boon_nm(c), d, cosv) end
        if d < 15.0 and cosv > 0.766 then -- 40 degrees
            local sc = (1.0 - cosv) * 10.0 + d * 0.1
            if not best_s or sc < best_s then best, best_s = c, sc end
        end
    end
    if L then L[#L + 1] = "pick " .. (best and boon_nm(best) or "none (self)") end
    return best
end
-- dev46 (second audit pass, tools/audit/player_written_fields.py): the other Mage support spells read the same
-- AimCharacter: Job03CastDivineShot.start, Job03CastFullRecover.updateFullRecoverEffect, Job03CastCureSpot.update.
R.boon_targets = {
    { "app.Job03CastBoon", "setEnchant", true },
    { "app.Job03CastDivineShot", "start" },
    { "app.Job03CastFullRecover", "updateFullRecoverEffect" },
    { "app.Job03CastCureSpot", "update" },
}
R.boon_hook_one = function(tname, mname, is_boon)
    local td = sdk.find_type_definition(tname)
    local m = td and td:get_method(mname)
    if not m then log_msg("ally spell targeting: " .. tname .. "." .. mname .. " not found (game update?)"); return end
    sdk.hook(m, function(args)
        local st = thread.get_hook_storage()
        st.boon_ch = nil
        if not state.active and not (R.np and next(R.np.slots)) then return end
        local ok, err = pcall(function()
            local this = sdk.to_managed_object(args[2])
            if not this then return end
            if is_boon and (this:get_field("MagicBook") or this:get_field("IsLvEx")) then return end
            local chara = this:get_field("Chara")
            if not chara then return end
            local ally = R.boon_pick(chara, tname)
            if not ally then return end
            st.boon_ch, st.boon_old = chara, chara:get_field("<AimCharacter>k__BackingField")
            chara:set_field("<AimCharacter>k__BackingField", ally)
            R.boon_n = R.boon_n + 1
            R.boon_last = boon_nm(ally)
        end)
        if not ok then R.boon_err = tostring(err) end
    end, function(rv)
        local st = thread.get_hook_storage()
        local ch = st.boon_ch
        if ch then
            st.boon_ch = nil
            pcall(function() ch:set_field("<AimCharacter>k__BackingField", st.boon_old) end)
        end
        return rv
    end)
end
for _, t in ipairs(R.boon_targets) do pcall(R.boon_hook_one, t[1], t[2], t[3]) end
re.on_pre_application_entry("UpdateBehavior", function() pcall(R.npl_tick) end)
