local out = {}
local ar = sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer")
local hu = ar:call("get_Human")
local sm = ar:call("get_StaminaManager")
out[#out+1] = string.format("stamina %.1f / %.1f (reduced max %.1f) enableConsume=%s runningOut=%s", sm:call("get_RemainingAmount"), sm:call("get_MaxValue"), sm:call("get_ReducedMaxValue"), tostring(sm:call("get_IsEnableConsume")), tostring(sm:call("get_IsRunningOutOf")))
out[#out+1] = "IsDash=" .. tostring(hu:call("get_IsDash")) .. " IsPrevDash=" .. tostring(hu:call("get_IsPrevDash")) .. " IsEnableDashAction=" .. tostring(hu:call("get_IsEnableDashAction"))
local function dumpobj(o, label)
  if not o then out[#out+1] = label .. " = nil"; return end
  local t = o:get_type_definition()
  out[#out+1] = "## " .. label .. " : " .. t:get_full_name()
  while t and t:get_full_name() ~= "System.Object" do
    for _, f in ipairs(t:get_fields()) do
      local v = ""; pcall(function() v = tostring(o:get_field(f:get_name())) end)
      if not v:find("sol%.") then out[#out+1] = " f " .. f:get_name() .. " = " .. v else out[#out+1] = " f " .. f:get_name() .. " : " .. tostring(f:get_type():get_full_name()) end
    end
    for _, m in ipairs(t:get_methods()) do
      local n = m:get_name(); local np = 0; pcall(function() np = #m:get_param_types() end)
      if np == 0 and (n:find("^get_") or n:find("^is")) then local ok, r = pcall(o.call, o, n); if ok and type(r) ~= "userdata" then out[#out+1] = " m " .. n .. " = " .. tostring(r) end
      elseif n:lower():find("recover") or n:lower():find("disable") then out[#out+1] = " m " .. n .. "/" .. np end
    end
    t = t:get_parent_type()
  end
end
dumpobj(hu:call("get_HumanStaminaCtrl"), "HumanStaminaCtrl")
dumpobj(hu:call("get_StaminaContext"), "StaminaContext")
dumpobj(ar:get_field("StaminaTrack"), "StaminaTrack")
dumpobj(ar:get_field("UpperStaminaTrack"), "UpperStaminaTrack")
local fsm = ar:call("get_ActionManager"):get_field("Fsm")
out[#out+1] = "nodes " .. tostring(fsm:call("getCurrentNodeName(System.UInt32)", 0)) .. " | " .. tostring(fsm:call("getCurrentNodeName(System.UInt32)", 1))
local inp = ar:call("get_Input")
out[#out+1] = string.format("input on=%X", inp:get_field("ButtonOnFlags") or 0)
local sc = ar:call("get_StatusConditionCtrl")
out[#out+1] = string.format("status flags=%X", sc:call("get_ActiveStatusConditionFlagProp") or 0)
out[#out+1] = "NoDie=" .. tostring(ar:call("get_Hit"):call("get_IsNoDie")) .. " hp=" .. tostring(ar:call("get_Hit"):call("get_Hp"))
local D = _G.DPC_dbg
out[#out+1] = "DPC active=" .. tostring(D.state.active) .. " aim_set=" .. tostring(D.R.aim_set) .. " setups=" .. tostring(D.R.aim_setups) .. " reqs=" .. tostring(D.R.aim_reqs)
return table.concat(out, "\n")
