local out = {}
local cm = sdk.get_managed_singleton("app.CharacterManager"); if not cm then return "no cm" end
local cat = cm:get_field("<DecisionPackCatalog>k__BackingField")
if not cat then return "no catalog" end
local t = cat:get_type_definition()
out[#out+1] = t:get_full_name()
while t do
  local fs, ms = {}, {}
  for _, f in ipairs(t:get_fields()) do
    local v = nil; pcall(function() v = cat:get_field(f:get_name()) end)
    local d = tostring(v)
    if type(v) == "userdata" then pcall(function() d = v:get_type_definition():get_full_name() end); pcall(function() d = d .. "#" .. tostring(v:call("get_Count")) end) end
    fs[#fs+1] = f:get_name() .. "=" .. d
  end
  for _, m in ipairs(t:get_methods()) do ms[#ms+1] = m:get_name() end
  out[#out+1] = t:get_full_name() .. "\n F: " .. table.concat(fs, " | ") .. "\n M: " .. table.concat(ms, " ")
  t = t:get_parent_type()
  if t and t:get_full_name() == "System.Object" then break end
end
return table.concat(out, "\n")
