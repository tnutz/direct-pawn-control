local out = {}
local function tdump(tn)
  local t = sdk.find_type_definition(tn)
  if not t then out[#out+1] = tn .. " none"; return end
  local fs, ms = {}, {}
  for _, f in ipairs(t:get_fields()) do fs[#fs+1] = (f:is_static() and "S:" or "") .. f:get_name() .. ":" .. f:get_type():get_full_name() end
  for _, m in ipairs(t:get_methods()) do
    local ps = {}
    pcall(function() for _, p in ipairs(m:get_param_types()) do ps[#ps+1] = p:get_full_name() end end)
    local rt = ""; pcall(function() rt = m:get_return_type():get_full_name() end)
    ms[#ms+1] = m:get_name() .. "(" .. table.concat(ps, ",") .. ")->" .. rt
  end
  local par = t:get_parent_type()
  out[#out+1] = tn .. " : " .. (par and par:get_full_name() or "?") .. "\n  F: " .. table.concat(fs, " | ") .. "\n  M: " .. table.concat(ms, " | ")
end
tdump("app.DecisionPackCatalog")
tdump("app.DecisionPack.Decision")
tdump("app.DecisionPack")
for _, sn in ipairs({ "app.PawnManager", "app.AIManager", "app.CharacterManager", "app.BattleManager", "app.AIDecisionManager", "app.GenerateManager", "app.HumanManager", "app.JobManager", "app.SkillManager", "app.HumanSkillManager", "app.AISystemManager", "app.ThinkManager" }) do
  local t = sdk.find_type_definition(sn)
  if t then
    local hits = {}
    for _, f in ipairs(t:get_fields()) do
      local ft = f:get_type():get_full_name()
      if ft:find("Decision") or ft:find("Catalog") then hits[#hits+1] = f:get_name() .. ":" .. ft end
    end
    out[#out+1] = sn .. (sdk.get_managed_singleton(sn) and " (live)" or " (no inst)") .. ": " .. table.concat(hits, " | ")
  end
end
return table.concat(out, "\n")
