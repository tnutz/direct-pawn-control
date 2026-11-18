local out = {}
local gm = sdk.get_managed_singleton("app.GuiManager")
local se = gm:get_field("ScreenEffect")
local td = se:get_type_definition()
out[#out+1] = "type " .. td:get_full_name() .. " parent " .. tostring(td:get_parent_type() and td:get_parent_type():get_full_name())
for _, m in ipairs(td:get_methods()) do
  local ps = {}
  pcall(function() for _, pt in ipairs(m:get_param_types()) do ps[#ps+1] = pt:get_full_name() end end)
  local rt = ""; pcall(function() rt = m:get_return_type():get_full_name() end)
  out[#out+1] = m:get_name() .. "(" .. table.concat(ps, ",") .. ") -> " .. rt
end
for _, f in ipairs(td:get_fields()) do
  local v = ""; pcall(function() v = tostring(se:get_field(f:get_name())) end)
  out[#out+1] = "field " .. f:get_name() .. " : " .. tostring(f:get_type():get_full_name()) .. " = " .. v
end
out[#out+1] = "DangerHpRate=" .. tostring(gm:call("getDangerHpRate")) .. " DangerHp=" .. tostring(select(2, pcall(gm.call, gm, "getDangerHp")))
return table.concat(out, "\n")
