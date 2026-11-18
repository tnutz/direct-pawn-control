local out = {}
local gm = sdk.get_managed_singleton("app.GuiManager")
out[#out+1] = "_HistoryItemId=" .. tostring(gm:get_field("_HistoryItemId")) .. " _HistoryItemNum=" .. tostring(gm:get_field("_HistoryItemNum"))
for _, m in ipairs(gm:get_type_definition():get_methods()) do
  local l = m:get_name():lower()
  if l:find("history") then
    local ps = {}
    pcall(function() for _, pt in ipairs(m:get_param_types()) do ps[#ps+1] = pt:get_full_name() end end)
    out[#out+1] = "GuiManager:" .. m:get_name() .. "(" .. table.concat(ps, ",") .. ")"
  end
end
local cg = gm:get_field("CrossGuide")
local td = cg:get_type_definition()
for _, m in ipairs(td:get_methods()) do
  local ps = {}
  pcall(function() for _, pt in ipairs(m:get_param_types()) do ps[#ps+1] = pt:get_full_name() end end)
  out[#out+1] = "ui020401:" .. m:get_name() .. "(" .. table.concat(ps, ",") .. ")"
end
for _, f in ipairs(td:get_fields()) do
  local v = ""; pcall(function() v = tostring(cg:get_field(f:get_name())) end)
  if not v:find("sol%.") then out[#out+1] = "f " .. f:get_name() .. ":" .. tostring(f:get_type():get_full_name()) .. "=" .. v else out[#out+1] = "f " .. f:get_name() .. ":" .. tostring(f:get_type():get_full_name()) end
end
return table.concat(out, "\n")
