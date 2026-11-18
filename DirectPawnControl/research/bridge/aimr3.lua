local out = {}
local D = _G.DPC_dbg
local mcc = D.R.aim_mcc()
local dict = mcc:get_field("<CameraControllers>k__BackingField")
local ac
pcall(function() ac = dict:call("get_Item", 7) end)
out[#out+1] = "aim controller = " .. tostring(ac and ac:get_type_definition():get_full_name())
if not ac then return table.concat(out, "\n") end
local set = ac:get_field("_AimCameraSetting")
local function show(label, s)
  if not s then out[#out+1] = label .. " -> nil"; return end
  local r = { label .. " ->" }
  for _, k in ipairs({ "_Enabled", "_ThrowingAim", "_Distance", "_YawRotSpeed", "_PitchRotSpeed", "_GyroOperation", "_UseOptionalSpeedRate", "_OptionalRotSpeed" }) do
    r[#r+1] = k .. "=" .. tostring(s:get_field(k))
  end
  local fov = s:get_field("_Fov"); local fv = "?"
  pcall(function() fv = tostring(fov:get_field("_HasValue")) .. "/" .. tostring(fov:get_field("_Value")) end)
  r[#r+1] = "_Fov=" .. fv .. " addr=" .. string.format("%X", s:get_address())
  out[#out+1] = table.concat(r, " ")
end
local ar = sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer")
show("evaluate(Arisen)", set:call("evaluate(via.GameObject)", ar:call("get_GameObject")))
local pm = sdk.get_managed_singleton("app.PawnManager")
local list = pm:call("get_PawnCharacterList")
for i = 0, list:call("get_Count") - 1 do
  local c = list:call("get_Item", i)
  local go = c:call("get_GameObject")
  show("evaluate(" .. tostring(go:call("get_Name")) .. ")", set:call("evaluate(via.GameObject)", go))
end
show("controller _AimSetting", ac:get_field("_AimSetting"))
show("controller _CurrentAimSetting", ac:get_field("_CurrentAimSetting"))
local arr = set:get_field("_AimSettings")
out[#out+1] = "settings in asset: " .. tostring(arr and arr:get_size())
out[#out+1] = "possessing=" .. tostring(D.state.active) .. " pawn=" .. tostring(D.state.pawn_name) .. " aim_hold=" .. tostring(D.R.aim_hold)
return table.concat(out, "\n")
