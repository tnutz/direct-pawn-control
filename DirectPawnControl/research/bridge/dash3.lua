local out = {}
local D = _G.DPC_dbg
local gm = sdk.get_managed_singleton("app.GuiManager")
local kg = gm:get_field("KeyGuide")
local st = D.state
local function id(c) return c and tostring(c:call("get_CharaIDString")) or "nil" end
out[#out+1] = "active " .. tostring(st.active) .. " pawn " .. id(st.pawn_chara) .. " arisen " .. id(st.arisen_chara)
out[#out+1] = "kg.PlChara " .. id(kg:get_field("PlChara")) .. " Job " .. tostring(kg:get_field("Job"))
local pi = kg:get_field("PlInput")
local pawn_in = st.pawn_chara and st.pawn_chara:call("get_Input")
local ar_in = st.arisen_chara and st.arisen_chara:call("get_Input")
out[#out+1] = "kg.PlInput is " .. ((pi and pawn_in and pi:get_address() == pawn_in:get_address()) and "pawn's" or (pi and ar_in and pi:get_address() == ar_in:get_address()) and "Arisen's" or "other")
for label, inp in pairs({ pawn = pawn_in, arisen = ar_in }) do
  if inp then
    local s = {}
    pcall(function() s[#s+1] = "magL " .. string.format("%.2f", inp:call("get_AxisMagnitudeL")) end)
    pcall(function() s[#s+1] = "on " .. string.format("%x", inp:get_field("ButtonOnFlags")) end)
    out[#out+1] = label .. ": " .. table.concat(s, " ")
  end
end
for _, m in ipairs({ "isDisableDash", "isRestrictedDash" }) do out[#out+1] = m .. "=" .. tostring(kg:call(m)) end
local hu = st.pawn_human
if hu then
  local ms = {}
  for _, m in ipairs(hu:get_type_definition():get_methods()) do
    local n = m:get_name(); local l = n:lower()
    if l:find("dash") and (n:find("^get_") or n:find("^is")) and #m:get_param_types() == 0 then
      local ok, v = pcall(hu.call, hu, n)
      local ok2, v2 = pcall(st.arisen_human.call, st.arisen_human, n)
      ms[#ms+1] = n .. "=" .. tostring(ok and v) .. "/" .. tostring(ok2 and v2)
    end
  end
  out[#out+1] = "Human dash getters pawn/arisen: " .. table.concat(ms, " ")
end
return table.concat(out, " | ")
