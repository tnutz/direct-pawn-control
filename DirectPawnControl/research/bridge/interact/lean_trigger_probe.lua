-- lean_trigger_probe.lua  (READ-ONLY bridge probe, DD2 4.1.0.0; changes nothing in the game)
-- Question: which AI data makes a pawn pick the wall lean (Gm80_079 / GmAIInteract_02, action pack
-- Common/InteractingWithObject) or a seat (GmAIInteractSit / _00 / _03 / _05, Gm80_042_seat), and what holds it back.
-- Chain read from DD2.exe 4.1 + il2cpp dump (2026-11-26):
--   app.goalplanning.AIGoalPlanning (per pawn) -> _AIGoalData._GoalTypeList[].ParamList[]._GoalParam
--     (_SituationConditionList, _CoolTime, _Priority, _DecisionCategory._Process._Decisions._DecisionPacks[])
--   -> decisions go into AIDecisionMaker.DecisionModule (app.DecisionEvaluationModule Main/Pre/PostDecisions,
--      app.AIDecision: Target flag, TargetConditions, CooldownID/CooldownTime/CooldownTimer, ActionPack)
--   -> target = AITarget with <InteractActionMarker> (gimmick side: GimmickBase.InteractiveObject(+0x288).Marker
--      (app.InteractActionMarker, own InteractDecisionPack, Vision marker, reservations))
--   -> pack runs actinter.cmd.InteractReserve (marker.tryReserve) then InteractBegin (marker.requestInteract ->
--      InteractManager.requestInteractFromAI).
-- Run: send.py lean_trigger_probe.lua   Output: reframework/data/agent_bridge/lean_trigger_probe.json (+ short string)
-- Stand in the tavern with the main pawn near a lean wall / bench. Run it twice ~20 s apart to see timers move.

local PAT = { "interact", "sit", "lean", "chair", "bench", "gm80_079", "gm80_042", "wall" }
local RANGE = 15.0

local function tn(o) local ok, n = pcall(function() return o:get_type_definition():get_full_name() end); return ok and n or type(o) end
local function f(o, n) if not o then return nil end local ok, v = pcall(o.get_field, o, n); if ok then return v end end
local function c(o, m, ...) if not o then return nil end local ok, v = pcall(o.call, o, m, ...); if ok then return v end end
local function s(v) if v == nil then return nil end if type(v) == "userdata" then local x = c(v, "ToString"); return x and tostring(x) or tn(v) end return v end
local function elems(x)
  if not x then return {} end
  local ok, e = pcall(x.get_elements, x); if ok and e then return e end
  local out, items, n = {}, f(x, "_items"), f(x, "_size")           -- List`1
  if items and n then local ie = items:get_elements(); for i = 1, n do out[#out + 1] = ie[i] end end
  return out
end
local function dict(d)                                               -- Dictionary`2 -> { {k, v} }
  local out = {}
  for _, e in ipairs(elems(f(d, "_entries"))) do
    local k = f(e, "key") or f(e, "Key"); local v = f(e, "value") or f(e, "Value")
    if k ~= nil then out[#out + 1] = { k, v } end
  end
  return out
end
local function path(ap) return ap and tostring(c(ap, "get_Path") or "") or nil end
local function hit(p)
  if not p then return false end
  p = p:lower(); for _, w in ipairs(PAT) do if p:find(w, 1, true) then return true end end; return false
end
local function names(list) local t = {} for _, x in ipairs(elems(list)) do t[#t + 1] = tn(x) end return t end
local function cond_set(cs)                                          -- AIGoalConditionSet: list its members' types
  if not cs then return nil end
  local r = { _type = tn(cs) }
  local td = cs:get_type_definition()
  for _, fd in ipairs(td:get_fields()) do
    if not fd:is_static() then local v = f(cs, fd:get_name()); r[fd:get_name()] = (type(v) == "userdata") and names(v) or s(v) end
  end
  return r
end

local out = { t = os.clock() }
local pm = sdk.get_managed_singleton("app.PawnManager"); if not pm then return "no PawnManager" end
local pw = c(pm, "get_PawnCharacterList"); pw = pw and elems(pw)[1]; if not pw then return "no pawn" end
local go = c(pw, "get_GameObject")
local pp = c(c(pw, "get_Transform"), "get_Position")
local im = sdk.get_managed_singleton("app.InteractManager")
out.pawn = s(c(pw, "get_CharaIDString"))
out.interacting = s(c(im, "isInteracting(app.Character)", pw))
out.active_interact = tn(c(im, "getActiveInteract(app.Character)", pw))

-- 1. goal planning: which goal carries interact / sit decisions, its conditions and cooldown
local gp = c(go, "getComponent(System.Type)", sdk.typeof("app.goalplanning.AIGoalPlanning"))
out.goal = { found = gp ~= nil, state = s(f(gp, "_CurrentState")), now_cat = s(f(gp, "NowSituationCategory")),
  personal_cat = s(f(gp, "PersonalSituationCategory")), need_stop = s(f(gp, "needStopUpdate")), enable_target = s(f(gp, "_EnableTarget")),
  gimmick_eval_state = s(f(gp, "_GimmickEvaluateState")), goals = {}, current = {}, cooltimes = {}, gimmick_targets = {} }
local cool = {}
for _, kv in ipairs(dict(f(gp, "_CoolTimeDict"))) do cool[kv[1]:get_address()] = kv[2] end
for _, kv in ipairs(dict(f(gp, "_AddCoolTimeDict"))) do out.goal.cooltimes[#out.goal.cooltimes + 1] = { add = true, v = kv[2] } end
for _, pd in ipairs(elems(f(gp, "_CurrentGoalList"))) do out.goal.current[#out.goal.current + 1] = s(c(pd, "ToString")) end
local gd = f(gp, "_AIGoalData")
for ti, gt in ipairs(elems(f(gd, "_GoalTypeList"))) do
  for pi, pdata in ipairs(elems(f(gt, "_ParamList"))) do
    local prm = f(pdata, "_GoalParam")
    local proc = f(f(prm, "_DecisionCategory"), "_Process")
    local packs = elems(f(f(proc, "_Decisions"), "_DecisionPacks"))
    local rows, any = {}, false
    for _, pk in ipairs(packs) do
      for _, d in ipairs(elems(f(pk, "_Decisions"))) do
        local p = path(f(d, "_ActInterPack"))
        if hit(p) then any = true
          rows[#rows + 1] = { pack = s(c(pk, "ToString")), act = p, target = s(f(d, "_Target")), cd = s(f(d, "_Cooldown")),
            cd_id = s(f(d, "_CooldownID")), enabled = s(f(d, "_Enabled")), prio = s(f(d, "_Priority")), situation = s(f(d, "_Situation")) }
        end
      end
    end
    if any then
      local sits = {}
      for _, sd in ipairs(elems(f(prm, "_SituationConditionList"))) do
        sits[#sits + 1] = { cat = s(f(sd, "_Category")), prio = s(f(sd, "_Priolity")), hash = s(f(sd, "_Hash")), target = s(f(sd, "_EnableTarget")),
          cond = cond_set(f(sd, "_Condition")), excl = cond_set(f(sd, "_ExclusionCondition")), special = tn(f(sd, "_SpecialCondition")),
          now = s(c(sd, "evaluate(app.Character)", pw)) }   -- evaluate() is a read (returns bool); drop if wary
      end
      out.goal.goals[#out.goal.goals + 1] = { type_i = ti, param_i = pi, file = s(c(pdata, "ToString")), guid = s(f(gt, "Guid")),
        battle_flags = s(f(gt, "_BattleStateFlags")), capacity = s(f(gt, "_GoalCapacity")), cooltime = s(f(prm, "_CoolTime")),
        cool_left = cool[pdata:get_address()], is_cool = s(c(gp, "isCoolTime(app.goalplanning.AIGoalParamData)", pdata)),
        has_goal = s(c(gp, "hasGoal(app.goalplanning.AIGoalParamData)", pdata)), prio = s(f(prm, "_Priority")),
        exec_num = s(f(prm, "_ExecutableNum")), unique = s(f(prm, "_IsUniqueGoal")), category = tn(proc), situations = sits, decisions = rows }
    end
  end
end
for _, at in ipairs(elems(f(gp, "SortedGimmickTargetList") or f(gp, "GimmickTargetList"))) do
  local mk = f(at, "<InteractActionMarker>k__BackingField")
  local o = mk and f(mk, "Object"); local ow = o and c(o, "get_Owner")
  out.goal.gimmick_targets[#out.goal.gimmick_targets + 1] = { type = tn(at), owner = ow and tostring(c(ow, "get_Name")) or nil, marker = mk ~= nil }
end

-- 2. live decisions in the pawn's decision module (cooldowns are per AIDecision)
local dm = c(c(pw, "get_AIDecisionMaker"), "get_DecisionModule")
out.module = { type = tn(dm), executing = nil, decisions = {} }
local ex = c(dm, "get_ExecutingDecision"); out.module.executing = ex and path(c(ex, "get_ActionPack")) or nil
for _, lst in ipairs({ "<MainDecisions>k__BackingField", "<PreDecisions>k__BackingField", "<PostDecisions>k__BackingField" }) do
  for _, d in ipairs(elems(f(dm, lst))) do
    local p = path(c(d, "get_ActionPack"))
    if hit(p) then
      out.module.decisions[#out.module.decisions + 1] = { list = lst:match("<(%a+)>"), act = p, enabled = s(c(d, "get_Enabled")),
        disable = s(c(d, "get_DisableFlag")), target = s(c(d, "get_Target")), cd_id = s(c(d, "get_CooldownID")),
        cd_time = s(c(d, "get_CooldownTime")), cd_timer = s(c(d, "get_CooldownTimer")), cooling = s(c(d, "get_Cooldown")),
        prio = s(f(d, "<Priority>k__BackingField")), situation = s(c(d, "get_Situation")), tags = s(c(d, "get_ControlTags")),
        pre = names(c(d, "get_Preconditions")), tpre = names(c(d, "get_TargetPreconditions")), tcond = names(c(d, "get_TargetConditions")),
        eval = names(c(d, "get_EvaluationCriteria")) }
    end
  end
end
out.module.situation = s(c(dm, "get_Situation")); out.module.invalid_tags = s(c(dm, "get_InvalidControlTags"))

-- 3. the gimmicks near the pawn: their marker and the marker's own decision pack
out.gimmicks = {}
for _, e in ipairs(elems(f(f(im, "InteractiveObjects"), "_entries"))) do
  local o = f(e, "value") or f(e, "Value")
  local ow = o and c(o, "get_Owner"); local nm = ow and tostring(c(ow, "get_Name")) or ""
  local p = ow and c(c(ow, "get_Transform"), "get_Position")
  if p and pp then
    local dd = math.sqrt((p.x - pp.x) ^ 2 + (p.y - pp.y) ^ 2 + (p.z - pp.z) ^ 2)
    local comps = {}
    for _, tname in ipairs({ "app.GmAIInteract_02", "app.GmAIInteractSit", "app.GmAIInteract_00", "app.GmAIInteract_01",
                             "app.GmAIInteract_03", "app.GmAIInteract_04", "app.GmAIInteract_05", "app.Gm80_079_interact", "app.Gm80_042_seat" }) do
      local okt, ty = pcall(sdk.typeof, tname)
      local cp = okt and ty and c(ow, "getComponent(System.Type)", ty)
      if cp then comps[#comps + 1] = { t = tname, state = s(c(cp, "get_State")), enable0 = s(c(cp, "isInteractEnable(System.UInt32)", 0)) } end
    end
    if dd < RANGE and (#comps > 0 or hit(nm)) then
      local mk = f(o, "Marker"); local mp = f(mk, "InteractDecisionPack"); local mdec = {}
      for _, d in ipairs(elems(f(mp, "_Decisions"))) do
        mdec[#mdec + 1] = { act = path(f(d, "_ActInterPack")), target = s(f(d, "_Target")), cd = s(f(d, "_Cooldown")), cd_id = s(f(d, "_CooldownID")) }
      end
      out.gimmicks[#out.gimmicks + 1] = { name = nm, dist = dd, comps = comps, marker = mk ~= nil,
        active = s(c(mk, "get_ActiveFlag")), itype = s(f(mk, "InteractTypeValue")), reserved = s(f(mk, "HasReservedCharacter")),
        enable_pawn = s(c(mk, "isEnableReservation(app.Character)", pw)), can_pawn = s(c(mk, "canCharacterInteract(app.Character)", pw)),
        points = s(c(mk, "getNumInteractPoint")), marker_pack = mp and s(c(mp, "ToString")) or nil, marker_decisions = mdec }
    end
  end
end

json.dump_file("agent_bridge/lean_trigger_probe.json", out)
return string.format("goals=%d live=%d gimmicks=%d executing=%s interacting=%s (json: agent_bridge/lean_trigger_probe.json)",
  #out.goal.goals, #out.module.decisions, #out.gimmicks, tostring(out.module.executing), tostring(out.interacting))
