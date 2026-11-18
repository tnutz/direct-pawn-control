local out = {}
local cm = sdk.get_managed_singleton("app.CharacterManager"); if not cm then return "no cm" end
local ar = cm:call("get_ManualPlayer"); if not ar then return "no player" end
local hu = ar:call("get_Human")
pcall(function()
  local sm = ar:call("get_StaminaManager")
  out[#out+1] = string.format("stamina %.0f / %.0f", sm:call("get_RemainingAmount"), sm:call("get_MaxValue"))
  local hit = ar:call("get_Hit"); out[#out+1] = string.format("hp %.0f / %.0f", hit:call("get_Hp"), hit:call("get_ReducedMaxHp"))
  local fsm = ar:call("get_ActionManager"):get_field("Fsm")
  out[#out+1] = "nodes " .. tostring(fsm:call("getCurrentNodeName(System.UInt32)", 0)) .. " | " .. tostring(fsm:call("getCurrentNodeName(System.UInt32)", 1))
  out[#out+1] = "drawn " .. tostring(ar:call("get_IsDrawedWeapon")) .. " skillstate " .. tostring(hu:call("get_CustomSkillState"))
  out[#out+1] = "arrowtype " .. tostring(hu:call("get_Job08ActionCtrl"):call("get_ArrowType"))
end)
for _, tn in ipairs({ "app.Human", "app.HumanSkillContext", "app.Job08ActionController", "app.HumanSkillAvailability", "app.ui010201" }) do
  local t = sdk.find_type_definition(tn)
  if t then
    local ms = {}
    for _, m in ipairs(t:get_methods()) do
      local n = m:get_name(); local l = n:lower()
      if (l:find("skill") and (l:find("enable") or l:find("disable") or l:find("can") or l:find("avail") or l:find("check"))) or l:find("lifereturn") then
        local ps = {}
        pcall(function() for _, p in ipairs(m:get_param_types()) do ps[#ps+1] = p:get_name() end end)
        ms[#ms+1] = n .. "(" .. table.concat(ps, ",") .. ")"
      end
    end
    out[#out+1] = tn .. ": " .. table.concat(ms, " ")
  end
end
return table.concat(out, "\n")
