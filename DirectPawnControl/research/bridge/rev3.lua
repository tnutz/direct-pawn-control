local out = {}
local pm = sdk.get_managed_singleton("app.PawnManager")
local list = pm:call("get_PawnCharacterList")
for i = 0, list:call("get_Count") - 1 do
  local c = list:call("get_Item", i)
  local hit = c:call("get_Hit")
  local fsm = c:call("get_ActionManager"):get_field("Fsm")
  out[#out+1] = tostring(c:call("get_GameObject"):call("get_Name")) .. " dead=" .. tostring(c:call("get_IsDead")) .. " hp=" .. tostring(hit:call("get_Hp")) .. "/" .. tostring(hit:call("get_ReducedMaxHp")) .. " node=" .. tostring(fsm:call("getCurrentNodeName(System.UInt32)", 0))
end
return table.concat(out, "\n")
