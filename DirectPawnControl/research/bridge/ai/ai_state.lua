-- Bridge probe 3 (needs a loaded save; fine while paused): which AI parts the Arisen and each pawn actually have.
-- Output: reframework/data/agent_bridge/ai_state.json
local function tname(o) if o == nil then return "nil" end local ok, n = pcall(function() return o:get_type_definition():get_full_name() end); return ok and n or type(o) end
local function describe(o, depth)
  if o == nil then return "nil" end
  if type(o) ~= "userdata" then return tostring(o) end
  local okv, s = pcall(function() return string.format("(%.2f,%.2f,%.2f)", o.x, o.y, o.z) end)
  if okv then return s end
  local td; if not pcall(function() td = o:get_type_definition() end) or not td then return tostring(o) end
  if (depth or 0) <= 0 then return td:get_full_name() end
  local t = { _type = td:get_full_name() }
  local cur, guard = td, 0
  while cur and guard < 4 and cur:get_full_name() ~= "System.Object" and not cur:get_full_name():find("^via%.") do
    for _, f in ipairs(cur:get_fields()) do
      if not f:is_static() then
        local ok, v = pcall(o.get_field, o, f:get_name())
        t[f:get_name()] = ok and describe(v, depth - 1) or "ERR"
      end
    end
    cur = cur:get_parent_type(); guard = guard + 1
  end
  return t
end
local function chara_ai(ch)
  if not ch then return "nil" end
  local r = { id = tostring(ch:call("get_CharaIDString")) }
  for _, f in ipairs({ "AIDecisionMaker", "AIBlackBoardController", "AISituationAgent", "CharaAIStateCtrl", "BattleStateCtrl",
                       "HateSystem", "SensorController", "VisionMarker", "AttackPermitCtrl", "NavigationAI", "InputProcessor" }) do
    local ok, v = pcall(ch.get_field, ch, f)
    r[f] = ok and describe(v, (f == "BattleStateCtrl" or f == "CharaAIStateCtrl") and 1 or 0) or "ERR"
  end
  pcall(function()
    local bb = ch:get_field("AIBlackBoardController")
    r.ReqMain = describe(bb and bb:call("get_ReqMainActInterPackData"), 1)
    r.ReqSub = describe(bb and bb:call("get_ReqSubActInterPackData"), 1)
  end)
  pcall(function()
    local dm = ch:get_field("AIDecisionMaker")
    r.DecisionMaker = describe(dm, 1)
  end)
  pcall(function()
    local h = ch:call("get_Human")
    r.HumanEnemyController = describe(h and h:get_field("HumanEnemyController"), 1)
  end)
  return r
end
local out = {}
local cm = sdk.get_managed_singleton("app.CharacterManager")
out.arisen = chara_ai(cm and cm:call("get_ManualPlayer"))
local pm = sdk.get_managed_singleton("app.PawnManager")
local list = pm and pm:call("get_PawnCharacterList")
out.pawns = {}
if list then for i = 0, list:call("get_Count") - 1 do out.pawns[#out.pawns + 1] = chara_ai(list[i]) end end
-- nearest human enemy (bandit / specter), if any
pcall(function()
  local em = sdk.get_managed_singleton("app.EnemyManager")
  local arr = em:call("getAllEnemies")
  out.enemies = {}
  for i = 0, math.min(arr:call("get_Count"), 12) - 1 do
    local e = arr[i]:get_field("_Chara")
    if e then
      local rec = { id = tostring(e:call("get_CharaIDString")), human = e:call("get_Human") ~= nil }
      if rec.human and not out.human_enemy then out.human_enemy = chara_ai(e) end
      out.enemies[#out.enemies + 1] = rec
    end
  end
end)
pcall(function()
  out.skillsets = describe(cm:call("get_HumanEnemySkillSetData"), 2)
  out.thinktables = describe(cm:call("get_HumanEnemyThinkTableDataList"), 2)
end)
json.dump_file("agent_bridge/ai_state.json", out)
return { ok = true }
