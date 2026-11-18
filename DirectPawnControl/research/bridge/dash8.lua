-- read-only: the whole pad assignment list in order (index, action, button, pre-input, flags)
local out = {}
local um = sdk.get_managed_singleton("app.UserInputManager")
local pa = um:call("getCurrentCharacterPadAssign")
out[#out+1] = "assign type " .. pa:get_type_definition():get_full_name()
local al = pa:get_field("AssignList")
local n = al:call("get_Count")
local names = {}
for _, f in ipairs(sdk.find_type_definition("app.CharacterInput.Action"):get_fields()) do if f:is_static() then names[f:get_data(nil)] = f:get_name() end end
for i = 0, n - 1 do
  local a = al:call("get_Item", i)
  out[#out+1] = string.format("%d %s(%s) btn=%s pre=%s ign=%s", i, tostring(names[a:get_field("Action")]), tostring(a:get_field("Action")), tostring(a:get_field("Button")), tostring(a:get_field("PreInput")), tostring(a:get_field("IsIgnorePreInput")))
end
return table.concat(out, "\n")
