local out = {}
local D = _G.DPC_dbg
local function dump(tag, ch)
  if not ch then out[#out+1] = tag .. " nil"; return end
  local hu = ch:call("get_Human")
  local lc = hu and hu:call("get_LanternCtrl")
  if not lc then out[#out+1] = tag .. " no ctrl"; return end
  local td = lc:get_type_definition()
  out[#out+1] = tag .. " type=" .. td:get_full_name()
  for _, m in ipairs({ "get_IsLanternOn", "isTurnOnCondition" }) do
    local ok, v = pcall(lc.call, lc, m); out[#out+1] = "  " .. m .. " = " .. tostring(v)
  end
  for _, f in ipairs(td:get_fields()) do
    local ok, v = pcall(function() return lc:get_field(f:get_name()) end)
    out[#out+1] = "  f " .. f:get_name() .. ":" .. f:get_type():get_full_name() .. " = " .. tostring(ok and v)
  end
  local p = td:get_parent_type()
  if p then for _, f in ipairs(p:get_fields()) do
    local ok, v = pcall(function() return lc:get_field(f:get_name()) end)
    out[#out+1] = "  pf " .. f:get_name() .. " = " .. tostring(ok and v)
  end end
  return td
end
local td = dump("pawn", D and D.state.pawn_chara)
dump("arisen", D and D.state.arisen_chara)
if td then
  local seen = {}
  local t = td
  while t and t:get_full_name() ~= "System.Object" do
    for _, m in ipairs(t:get_methods()) do
      local ps = {}
      pcall(function() for _, pt in ipairs(m:get_param_types()) do ps[#ps+1] = pt:get_full_name() end end)
      out[#out+1] = t:get_name() .. "." .. m:get_name() .. "(" .. table.concat(ps, ",") .. ")"
    end
    t = t:get_parent_type()
  end
end
for _, tn in ipairs({ "app.Pawn", "app.PawnManager", "app.Human", "app.HumanActionSelector", "app.PawnLanternController", "app.PawnUpdateController" }) do
  local t = sdk.find_type_definition(tn)
  if t then for _, m in ipairs(t:get_methods()) do if m:get_name():lower():find("lantern") then out[#out+1] = tn .. "." .. m:get_name() end end
    for _, f in ipairs(t:get_fields()) do if f:get_name():lower():find("lantern") then out[#out+1] = tn .. " field " .. f:get_name() .. ":" .. f:get_type():get_full_name() end end
  else out[#out+1] = tn .. " = nil" end
end
out[#out+1] = "active=" .. tostring(D and D.state.active)
return table.concat(out, "\n")
