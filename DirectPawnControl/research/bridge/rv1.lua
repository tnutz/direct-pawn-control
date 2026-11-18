local out = {}
local pm = sdk.get_managed_singleton("app.PawnManager")
out[#out+1] = "deadPartyPawnNum " .. tostring(pm:call("getDeadPartyPawnNum"))
local lst = pm:call("get_PawnCharacterList")
for i = 0, lst:call("get_Count") - 1 do
  local c = lst:call("get_Item", i)
  local s = { i .. " " .. tostring(c:call("get_CharaIDString")), "hp " .. tostring(c:call("get_Hp")), "dead " .. tostring(c:call("get_IsDead")), "down " .. tostring(c:call("get_IsDown")) }
  pcall(function() s[#s+1] = "cause " .. tostring(c:call("get_CauseOfDeath")) .. " posture " .. tostring(c:call("get_DeadPosture")) end)
  pcall(function()
    local hu = c:call("get_Human")
    local tm = hu:call("get_TimerRevivePawn")
    local fs = {}
    if tm then for _, f in ipairs(tm:get_type_definition():get_fields()) do fs[#fs+1] = f:get_name() .. "=" .. tostring(tm:get_field(f:get_name())) end end
    s[#s+1] = "reviveTimer {" .. table.concat(fs, ",") .. "}"
  end)
  pcall(function()
    local fsm = c:call("get_ActionManager"):get_field("Fsm")
    s[#s+1] = "nodes " .. tostring(fsm:call("getCurrentNodeName(System.UInt32)", 0)) .. " | " .. tostring(fsm:call("getCurrentNodeName(System.UInt32)", 1))
  end)
  pcall(function() local h = c:call("get_Hit"); s[#s+1] = "isDie " .. tostring(h:call("get_IsDie")) .. " startDead " .. tostring(h:call("get_IsStartDead")) end)
  out[#out+1] = table.concat(s, " ; ")
end
local ms = {}
for _, tn in ipairs({ "app.Job08ActionController", "app.HumanReviveInteractController", "app.PawnManager", "app.Pawn" }) do
  local t = sdk.find_type_definition(tn)
  if t then for _, m in ipairs(t:get_methods()) do local l = m:get_name():lower(); if l:find("lifereturn") or l:find("revive") or l:find("resurrect") then ms[#ms+1] = tn:sub(5) .. "." .. m:get_name() end end end
end
out[#out+1] = table.concat(ms, " ")
return table.concat(out, "\n")
