-- Bridge probe 2 (works paused): fields and methods of the AI types we may reuse.
-- Output: reframework/data/agent_bridge/ai_reflect.json
local TYPES = {
  "app.HumanEnemyController", "app.HumanEnemyManager", "app.HumanEnemySkillSetData", "app.HumanEnemyThinkTableDataList",
  "app.HumanEnemyCombatParameterData", "app.HumanEnemyParameterBase",
  "app.ActionInterface", "app.ActInterPackData", "app.actinter.Executor", "app.actinter.CommandExecutor",
  "app.AIDecisionMaker", "app.AIDecisionModule", "app.AIDecision", "app.ThinkTableController", "app.ThinkTableModule",
  "app.AIBlackBoardController", "app.BattleStateController", "app.CharacterAIStateController",
  "app.PawnBattleController", "app.PawnAIBlackBoardController", "app.PawnBattleAIData",
  "app.LockOnTargetWork", "app.CollisionSystem", "app.CollisionSystem.AsyncCastRay", "app.VisionMarker", "app.SensorController",
  "app.AITarget", "app.HateSystem", "app.AttackPermitController",
  "app.actinter.cmd.job02.Aim", "app.actinter.cmd.job02.AimedShot", "app.actinter.cmd.job.NormalAttack",
  "app.actinter.cmd.job.CustomSkillStandardBase", "app.actinter.cmd.move.ApproachTargetAroundPoint", "app.actinter.cmd.move.MoveBase",
}
local out = {}
for _, tn in ipairs(TYPES) do
  local td = sdk.find_type_definition(tn)
  if not td then out[tn] = "NOT FOUND" else
    local e = { parent = "", fields = {}, methods = {} }
    local p = td:get_parent_type(); local chain = {}
    while p do chain[#chain + 1] = p:get_full_name(); p = p:get_parent_type() end
    e.parent = table.concat(chain, " < ")
    for _, f in ipairs(td:get_fields()) do
      e.fields[#e.fields + 1] = (f:is_static() and "static " or "") .. f:get_name() .. ":" .. f:get_type():get_full_name()
    end
    for _, m in ipairs(td:get_methods()) do
      local ps = {}
      local ok, pt = pcall(m.get_param_types, m)
      if ok and pt then for _, q in ipairs(pt) do ps[#ps + 1] = q:get_full_name() end end
      local rt = m:get_return_type()
      e.methods[#e.methods + 1] = m:get_name() .. "(" .. table.concat(ps, ", ") .. "):" .. (rt and rt:get_full_name() or "?")
    end
    out[tn] = e
  end
end
json.dump_file("agent_bridge/ai_reflect.json", out)
local n = 0; for _ in pairs(out) do n = n + 1 end
return { types = n }
