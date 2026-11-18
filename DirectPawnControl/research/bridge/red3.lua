local out = {}
local D = _G.DPC_dbg
out[#out+1] = "hooked=" .. tostring(D.R.danger_hooked) .. " skips=" .. tostring(D.R.danger_skips) .. " swaps=" .. tostring(D.R.danger_swaps) .. " rate=" .. tostring(D.R.danger_rate) .. " active=" .. tostring(D.state.active)
local gm = sdk.get_managed_singleton("app.GuiManager")
local se = gm:get_field("ScreenEffect")
local td = se:get_type_definition()
for _, m in ipairs(td:get_methods()) do
  local ps = {}
  pcall(function() for _, pt in ipairs(m:get_param_types()) do ps[#ps+1] = pt:get_full_name() end end)
  out[#out+1] = "ui022401:" .. m:get_name() .. "(" .. table.concat(ps, ",") .. ")"
end
for _, f in ipairs(td:get_fields()) do
  local v = ""; pcall(function() v = tostring(se:get_field(f:get_name())) end)
  if not v:find("sol%.") then out[#out+1] = " f " .. f:get_name() .. " = " .. v else out[#out+1] = " f " .. f:get_name() .. " : " .. tostring(f:get_type():get_full_name()) end
end
for _, m in ipairs(gm:get_type_definition():get_methods()) do
  local l = m:get_name():lower()
  if l:find("critical") or l:find("screeneffect") or l:find("damageeffect") or l:find("reqdamage") or l:find("flash") then
    local ps = {}
    pcall(function() for _, pt in ipairs(m:get_param_types()) do ps[#ps+1] = pt:get_full_name() end end)
    out[#out+1] = "GuiManager:" .. m:get_name() .. "(" .. table.concat(ps, ",") .. ")"
  end
end
return table.concat(out, "\n")
