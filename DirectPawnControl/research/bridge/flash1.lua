-- read-only: the red-flash hooks' counters and the screen-effect widget's state
local D = _G.DPC_dbg
local R, st = D.R, D.state
local out = {}
out[#out+1] = "active " .. tostring(st.active) .. " hooked " .. tostring(R.danger_hooked) .. " skips " .. tostring(R.danger_skips) .. " swaps " .. tostring(R.danger_swaps) .. " rate " .. tostring(R.danger_rate)
local gm = sdk.get_managed_singleton("app.GuiManager")
local w = gm:get_field("ScreenEffect")
if w then
  local p = {}
  for _, f in ipairs({ "FlowNow", "PlayerHpRate", "IsAnimEnd", "IsDangerSe", "IsCallDangerSe", "IsInit", "IsReqCritical" }) do p[#p+1] = f .. "=" .. tostring(w:get_field(f)) end
  out[#out+1] = table.concat(p, " ")
  pcall(function() local pn = w:get_field("PnlCritical"); out[#out+1] = "PnlCritical visible " .. tostring(pn:call("get_Visible")) .. " play state " .. tostring(pn:call("get_PlayState")) end)
else out[#out+1] = "no ScreenEffect widget" end
local ms = {}
for _, m in ipairs(sdk.find_type_definition("app.GuiManager"):get_methods()) do
  local n = m:get_name()
  if n:find("Critical") or n:find("Danger") or n:find("Damage") or n:find("Flash") or n:find("ScreenEffect") then ms[#ms+1] = n end
end
out[#out+1] = "GuiManager: " .. table.concat(ms, " ")
return table.concat(out, "\n")
