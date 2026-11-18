local out = {}
local D = _G.DPC_dbg
out[#out+1] = "possessing " .. tostring(D and D.state.active) .. " pawn " .. tostring(D and D.state.pawn_name)
local sm = sdk.get_native_singleton("via.SceneManager")
local scene = sdk.call_native_func(sm, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
local arr = scene:call("findComponents(System.Type)", sdk.typeof("app.ui010201"))
local kg = nil
pcall(function() local e = arr:get_elements(); kg = e and e[1] end)
if not kg then pcall(function() kg = arr[0] end) end
if not kg then pcall(function() kg = arr:call("get_Item", 0) end) end
if not kg then pcall(function() kg = arr:call("GetValue(System.Int32)", 0) end) end
out[#out+1] = "arrtype " .. tostring(arr:get_type_definition():get_full_name())
out[#out+1] = "found " .. tostring(arr and arr:call("get_Count"))
if not kg then return table.concat(out, " | ") .. " | no ui010201" end
local pc = kg:get_field("PlChara")
out[#out+1] = "PlChara " .. tostring(pc and pc:call("get_CharaIDString")) .. " Job " .. tostring(kg:get_field("Job")) .. " IsWeightOver " .. tostring(kg:get_field("IsWeightOver"))
for _, m in ipairs({ "isDisableDash", "isRestrictedDash", "isDisableJump", "isRestrictedJump", "isDisableGrab", "isRestrictedCatch", "isDisableAttack", "isDisableSheathe", "isRestrictedAggressive", "isRestrictedItem", "isEnableSkillShift" }) do
  local ok, v = pcall(kg.call, kg, m)
  out[#out+1] = m .. " = " .. tostring(ok and v)
end
for _, f in ipairs({ "BtnDash", "BtnDash2", "BtnInteract", "BtnJump", "BtnAtk", "BtnAtk2", "BtnGrab" }) do out[#out+1] = f .. "=" .. tostring(kg:get_field(f)) end
return table.concat(out, " | ")
