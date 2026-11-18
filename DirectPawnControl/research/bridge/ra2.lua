local out = {}
local cm = sdk.get_managed_singleton("app.CharacterManager")
local ar = cm:call("get_ManualPlayer"); if not ar then return "no player" end
local hu = ar:call("get_Human")
local av = hu:call("get_SkillAvailability")
local sc = hu:call("get_SkillContext")
for _, id in ipairs({ 84, 83, 82, 80, 87, 86 }) do
  local a, b, c = "?", "?", "?"
  pcall(function() a = tostring(av:call("isCustomSkillAvailable(app.HumanCustomSkillID)", id)) end)
  pcall(function() b = tostring(av:call("isCustomSkillAvailableWithoutItemCondition(app.HumanCustomSkillID)", id)) end)
  pcall(function() c = tostring(sc:call("isCustomSkillEnable(app.HumanCustomSkillID)", id)) end)
  out[#out+1] = id .. " avail=" .. a .. " noitem=" .. b .. " enable=" .. c
end
local t = sdk.find_type_definition("app.HumanSkillAvailability")
local fs = {}
for _, f in ipairs(t:get_fields()) do local v = nil; pcall(function() v = av:get_field(f:get_name()) end); fs[#fs+1] = f:get_name() .. "=" .. tostring(v) end
out[#out+1] = table.concat(fs, " | ")
local ms = {}
for _, m in ipairs(t:get_methods()) do ms[#ms+1] = m:get_name() end
out[#out+1] = table.concat(ms, " ")
return table.concat(out, "\n")
