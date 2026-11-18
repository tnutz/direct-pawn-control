local out = {}
local pm = sdk.get_managed_singleton("app.PawnManager"); if not pm then return "no pm" end
local function desc(v)
  if type(v) ~= "userdata" then return tostring(v) end
  local d = "ud"
  pcall(function() d = v:get_type_definition():get_full_name() end)
  pcall(function() local c = v:call("get_Count"); if c then d = d .. "#" .. tostring(c) end end)
  pcall(function() local p = v:call("get_Path"); if p then d = d .. " path=" .. tostring(p) end end)
  return d
end
local function fields(o, label)
  local t = o:get_type_definition()
  while t do
    for _, f in ipairs(t:get_fields()) do
      if not f:is_static() then
        local v = nil; pcall(function() v = o:get_field(f:get_name()) end)
        out[#out+1] = label .. "." .. f:get_name() .. " = " .. desc(v)
      end
    end
    t = t:get_parent_type()
    if t and (t:get_full_name() == "System.Object") then break end
  end
end
local ok, e = pcall(function()
  local lst = pm:call("get_PawnCharacterList")
  local ch = lst:call("get_Item", 2)
  local dm = ch:get_field("<AIDecisionMaker>k__BackingField")
  local h = dm:call("get_DecisionModule"):get_field("<DecisionPackHandler>k__BackingField")
  local packs = h:get_field("<ActiveDecisionPacks>k__BackingField")
  local n = packs:call("get_Count")
  for i = 0, n - 1 do
    local p = packs:call("get_Item", i)
    if i == 0 then
      fields(p, "pack0")
      local ms = {}
      for _, m in ipairs(p:get_type_definition():get_methods()) do ms[#ms+1] = m:get_name() end
      out[#out+1] = "pack methods: " .. table.concat(ms, " ")
    else
      local s = {}
      local t = p:get_type_definition()
      for _, f in ipairs(t:get_fields()) do
        if not f:is_static() then local v = nil; pcall(function() v = p:get_field(f:get_name()) end); s[#s+1] = f:get_name() .. "=" .. desc(v) end
      end
      out[#out+1] = "pack" .. i .. ": " .. table.concat(s, " | ")
    end
  end
end)
if not ok then out[#out+1] = "err " .. tostring(e) end
-- type names
for _, tn in ipairs({ "app.DecisionPack", "app.DecisionPackData", "app.AIDecisionPackData", "app.DecisionPackCatalog", "app.DecisionPackManager", "app.AIDecisionData", "app.AIDecisionPack", "app.DecisionPackUserData", "app.JobDecisionPackData", "app.PawnDecisionPackData", "app.DecisionPackController", "app.DecisionPackSwitcher", "app.HumanDecisionPackController", "app.PawnBattleController", "app.BattleDecisionPackData" }) do
  local t = sdk.find_type_definition(tn)
  out[#out+1] = tn .. " -> " .. (t and "yes" or "no")
end
return table.concat(out, "\n")
