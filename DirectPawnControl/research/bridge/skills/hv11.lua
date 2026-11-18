local out = {}
local t = sdk.find_type_definition("app.HumanCustomSkillID")
for _, f in ipairs(t:get_fields()) do
  if f:is_static() then local ok, v = pcall(f.get_data, f, nil); out[#out+1] = tostring(ok and v) .. "=" .. f:get_name() end
end
return table.concat(out, " ")
