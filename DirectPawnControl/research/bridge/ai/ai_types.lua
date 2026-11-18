-- Bridge probe 1 (works with the game paused or unfocused): list app.* type names by keyword.
-- Output: reframework/data/agent_bridge/ai_types.json   { keyword = { names... } }
local tdb = sdk.get_tdb()
local n = tdb:get_num_types()
local KEYS = { "HumanEnemy", "ActInter", "actinter", "ThinkTable", "AIDecision", "DecisionPack", "AIBlackBoard", "BattleState",
               "Specter", "Spectre", "Obelisk", "Maister", "Nrd", "NRD", "Arisen", "AutoPlay", "PawnBattle", "PawnAI",
               "JobAI", "AITarget", "VisionMarker", "SensorController", "AsyncCast", "CastRay", "CollisionSystem",
               "LockOnTargetWork", "HateSystem", "AttackPermit", "CombatState", "AIGoal", "goalplanning" }
local out, count = {}, 0
for _, k in ipairs(KEYS) do out[k] = {} end
for i = 0, n - 1 do
  local ok, t = pcall(function() return tdb:get_type(i) end)
  if ok and t then
    local okn, name = pcall(t.get_full_name, t)
    if okn and name and name:sub(1, 4) == "app." and not name:find("[<`]") and #name < 110 then
      for _, k in ipairs(KEYS) do
        if name:find(k, 1, true) and #out[k] < 400 then out[k][#out[k] + 1] = name; count = count + 1 end
      end
    end
  end
end
for _, k in ipairs(KEYS) do table.sort(out[k]) end
json.dump_file("agent_bridge/ai_types.json", out)
return { types = n, hits = count }
