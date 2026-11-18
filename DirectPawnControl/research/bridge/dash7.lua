-- the key guide's dash slots before and after asking the game to redo its button assignment (its own method)
local out = {}
local gm = sdk.get_managed_singleton("app.GuiManager")
local g = gm:get_field("KeyGuide")
if not g then return "no guide" end
local function snap(tag)
  local p = { tag }
  for _, f in ipairs({ "BtnDash", "BtnDash2", "BtnInteract", "BtnAim", "BtnUniq", "BtnShift", "BtnStop", "BtnCameraReset", "IsBtnAssigned", "IsWeightOver", "IsHideRequest", "Job", "WeaponJob" }) do
    p[#p+1] = f .. "=" .. tostring(g:get_field(f))
  end
  out[#out+1] = table.concat(p, " ")
end
local D = _G.DPC_dbg
out[#out+1] = "dpc active " .. tostring(D and D.state.active)
snap("before")
local dash = sdk.find_type_definition("app.CharacterInput.Action")
local dv
for _, f in ipairs(dash:get_fields()) do if f:is_static() and f:get_name() == "Dash" then dv = f:get_data(nil) end end
out[#out+1] = "Dash action=" .. tostring(dv)
local ok, v = pcall(function() return g:call("convertBtn(app.CharacterInput.Action)", dv) end); out[#out+1] = "convertBtn(Dash)=" .. tostring(v)
local ok2, v2 = pcall(function() return g:call("convertBtn(app.CharacterInput.Action)", 6) end); out[#out+1] = "convertBtn(6)=" .. tostring(v2)
local ok3, e3 = pcall(function() g:call("updateButtonAssign()") end); out[#out+1] = "updateButtonAssign ok=" .. tostring(ok3) .. " " .. tostring(e3)
snap("after")
return table.concat(out, "\n")
