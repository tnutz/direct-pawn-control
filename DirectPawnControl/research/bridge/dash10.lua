-- read-only: the key guide's dash slots, who the guide is on, and the Circle slot's entry
local out = {}
local gm = sdk.get_managed_singleton("app.GuiManager")
local g = gm:get_field("KeyGuide")
local D = _G.DPC_dbg
local st = D.state
local function a(o) return o and string.format("%x", o:get_address()) or "nil" end
out[#out+1] = "version active " .. tostring(st.active) .. " pawn " .. tostring(st.pawn_name)
out[#out+1] = "guide PlChara " .. a(g:get_field("PlChara")) .. " PlInput " .. a(g:get_field("PlInput")) .. " | arisen " .. a(st.arisen_chara) .. " pawn " .. a(st.pawn_chara)
local p = {}
for _, f in ipairs({ "BtnDash", "BtnDash2", "BtnInteract", "IsBtnAssigned", "IsWeightOver" }) do p[#p+1] = f .. "=" .. tostring(g:get_field(f)) end
out[#out+1] = table.concat(p, " ")
for _, m in ipairs({ "isDisableDash", "isRestrictedDash" }) do local ok, v = pcall(function() return g:call(m) end); out[#out+1] = m .. "=" .. tostring(v) end
local ok, v = pcall(function() return g:call("convertBtn(app.CharacterInput.Action)", 4) end); out[#out+1] = "convertBtn(Dash)=" .. tostring(v)
local bl = g:get_field("BtnList")
local b = bl and bl:call("get_Item", 5)
if b then
  local q = {}
  for _, f in ipairs(b:get_type_definition():get_fields()) do
    if not f:is_static() then local val; pcall(function() val = b:get_field(f:get_name()) end)
      if type(val) ~= "userdata" then q[#q+1] = f:get_name() .. "=" .. tostring(val) end end
  end
  out[#out+1] = "slot5(" .. b:get_type_definition():get_full_name() .. "): " .. table.concat(q, " ")
end
local R = D.R
out[#out+1] = "slots " .. tostring(R.dash_slots and (tostring(R.dash_slots[1]) .. "," .. tostring(R.dash_slots[2]))) .. " puts " .. tostring(R.dash_puts)
for i = 0, 9 do
  local bi = bl:call("get_Item", i)
  local q = { "slot" .. i }
  for _, fn in ipairs({ "Key", "ExclusiveKey", "CheckAssignKey", "KeyInputType", "IsAutoVisibleOff", "IsReservedClear", "IsDisable", "IsSpellStock", "KeyHash", "CheckAssignKeyHash" }) do
    local okf, val = pcall(function() return bi:get_field(fn) end)
    if okf and val ~= nil and type(val) ~= "userdata" then q[#q+1] = fn .. "=" .. tostring(val) end
  end
  pcall(function() local m = bi:call("get_MsgId"); q[#q+1] = "msg=" .. tostring(m and m:call("ToString")):sub(1, 8) end)
  pcall(function() local pn = bi:get_field("Pnl"); q[#q+1] = "vis=" .. tostring(pn and pn:call("get_Visible")) end)
  pcall(function() local tx = bi:get_field("Txt"); q[#q+1] = "txt=" .. tostring(tx and tx:call("get_Message")) end)
  out[#out+1] = table.concat(q, " ")
end
local pc = g:get_field("PlChara")
if pc then
  local q = {}
  for _, m in ipairs({ "get_IsDrawedWeapon", "get_IsPlayer", "get_IsManualPlayer", "get_IsPawn" }) do local ok2, r = pcall(function() return pc:call(m) end); q[#q+1] = m .. "=" .. tostring(r) end
  out[#out+1] = "PlChara: " .. table.concat(q, " ")
end
return table.concat(out, "\n")
