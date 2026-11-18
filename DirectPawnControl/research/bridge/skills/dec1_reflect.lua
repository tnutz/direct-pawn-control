-- Step 1 of rebuilding the quick-skill table from the game's own data (2026-11-15).
-- app.AIDecision has ActionPack (app.ActInterPackData), Target (AITargetFlag) and Preconditions: the pawn AI's own
-- "use this action pack on this kind of target when ..." table. This dumps the shape of the types involved and
-- where pawn 0's AIDecisionMaker keeps its decisions. Read-only.
local out = {}
local function dump(tn)
  local td = sdk.find_type_definition(tn); if not td then out[#out+1] = "== " .. tn .. ": none"; return end
  local par = td:get_parent_type()
  out[#out+1] = "== " .. tn .. " : " .. tostring(par and par:get_full_name())
  for _, f in ipairs(td:get_fields()) do out[#out+1] = "  F " .. f:get_name() .. " : " .. f:get_type():get_full_name() .. (f:is_static() and " static" or "") end
  for _, m in ipairs(td:get_methods()) do
    local n = m:get_name()
    if not n:find("^%.") then
      local ps = {}
      for _, pt in ipairs(m:get_param_types()) do ps[#ps+1] = pt:get_name() end
      out[#out+1] = "  M " .. n .. "(" .. table.concat(ps, ",") .. ") -> " .. m:get_return_type():get_full_name()
    end
  end
end
for _, t in ipairs({ "app.AIDecisionMaker", "app.DecisionPack", "app.DecisionPackHandle", "app.DecisionExecutor", "app.DecisionEvaluator",
                     "app.AIDecision", "app.ActInterPackData", "app.decision.condition.ConditionBase",
                     "app.decision.condition.CheckCustomSkill", "app.decision.condition.HasCustomSkill" }) do dump(t) end
-- every type whose name mentions CustomSkill under app.decision
local tdb = sdk.get_tdb and sdk.get_tdb()
local ok, n = pcall(function() return tdb:get_num_types() end)
if ok and n then
  local hits = {}
  for i = 0, n - 1 do
    local okt, td = pcall(tdb.get_type, tdb, i)
    if okt and td then
      local fn = td:get_full_name()
      if fn and fn:find("^app%.decision%.") and (fn:find("Skill") or fn:find("Job")) then hits[#hits+1] = fn end
    end
  end
  out[#out+1] = "== app.decision.* types with Skill/Job: " .. table.concat(hits, ", ")
else
  out[#out+1] = "== tdb enumeration unavailable: " .. tostring(n)
end
pcall(json.dump_file, "DPC_probe_decisions_1.json", { lines = out })
return #out .. " lines -> data/DPC_probe_decisions_1.json"
