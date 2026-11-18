local out = {}
local td = sdk.find_type_definition("app.AimCameraController")
local t = td
while t and t:get_full_name() ~= "System.Object" and t:get_full_name() ~= "via.Behavior" do
  out[#out+1] = "## " .. t:get_full_name()
  for _, m in ipairs(t:get_methods()) do
    local ps = {}
    pcall(function() for _, pt in ipairs(m:get_param_types()) do ps[#ps+1] = pt:get_full_name() end end)
    local rt = ""; pcall(function() rt = m:get_return_type():get_full_name() end)
    out[#out+1] = " m " .. m:get_name() .. "(" .. table.concat(ps, ",") .. ") -> " .. rt
  end
  for _, f in ipairs(t:get_fields()) do out[#out+1] = " f " .. f:get_name() .. ":" .. tostring(f:get_type():get_full_name()) end
  t = t:get_parent_type()
end
return table.concat(out, "\n")
