local out = {}
local uim = sdk.get_managed_singleton("app.UserInputManager")
local act = {}
for _, f in ipairs(sdk.find_type_definition("app.CharacterInput.Action"):get_fields()) do
  if f:is_static() then local ok, v = pcall(f.get_data, f, nil); if ok and type(v) == "number" then act[#act+1] = v .. "=" .. f:get_name() end end
end
out[#out+1] = "Action enum: " .. table.concat(act, " ")
local pa = uim:call("getCurrentCharacterPadAssign")
local l = pa:get_field("AssignList")
local rows = {}
for i = 0, l:call("get_Count") - 1 do
  local it = l:call("get_Item", i)
  rows[#rows+1] = tostring(it:get_field("Action")) .. ":" .. tostring(it:get_field("Button")) .. ":" .. tostring(it:get_field("PreInput"))
end
out[#out+1] = "raw: " .. table.concat(rows, " ")
local it0 = l:call("get_Item", 0)
local fs = {}
for _, f in ipairs(it0:get_type_definition():get_fields()) do fs[#fs+1] = f:get_name() .. ":" .. f:get_type():get_full_name() end
out[#out+1] = "Info fields: " .. table.concat(fs, " | ")
local kb = uim:get_field("<KeyBindController>k__BackingField")
if kb then
  local t = kb:get_type_definition()
  local kf, km = {}, {}
  for _, f in ipairs(t:get_fields()) do
    local v = nil; pcall(function() v = kb:get_field(f:get_name()) end)
    local d = tostring(v)
    if type(v) == "userdata" then pcall(function() d = v:get_type_definition():get_full_name() end); pcall(function() d = d .. "#" .. tostring(v:call("get_Count")) end) end
    kf[#kf+1] = f:get_name() .. ":" .. f:get_type():get_full_name() .. "=" .. d
  end
  for _, m in ipairs(t:get_methods()) do
    local ps = {}
    pcall(function() for _, p in ipairs(m:get_param_types()) do ps[#ps+1] = p:get_name() end end)
    local rt = ""; pcall(function() rt = m:get_return_type():get_name() end)
    km[#km+1] = m:get_name() .. "(" .. table.concat(ps, ",") .. ")->" .. rt
  end
  out[#out+1] = "KeyBind F: " .. table.concat(kf, " | ")
  out[#out+1] = "KeyBind M: " .. table.concat(km, " ")
end
local ad = uim:get_field("AdditionalAssignInfos")
out[#out+1] = "additional: " .. tostring(ad and #ad:get_elements())
return table.concat(out, "\n")
