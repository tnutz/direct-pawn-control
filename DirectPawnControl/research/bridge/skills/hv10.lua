local out = {}
local t = sdk.find_type_definition("app.AIDecisionDefine.AITargetFlag")
for _, f in ipairs(t:get_fields()) do
  if f:is_static() then local ok, v = pcall(f.get_data, f, nil); out[#out+1] = f:get_name() .. "=" .. tostring(ok and v) end
end
return table.concat(out, " ")
