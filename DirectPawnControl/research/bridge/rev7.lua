local out = {}
local pm = sdk.get_managed_singleton("app.PawnManager")
local list = pm:call("get_PawnCharacterList")
for i = 0, list:call("get_Count") - 1 do
  local c = list:call("get_Item", i)
  local hit = c:call("get_Hit")
  local fsm = c:call("get_ActionManager"):get_field("Fsm")
  local hp, mx = hit:call("get_Hp"), hit:call("get_ReducedMaxHp")
  local line = tostring(c:call("get_GameObject"):call("get_Name")) .. " dead=" .. tostring(c:call("get_IsDead")) .. " hp=" .. tostring(hp) .. "/" .. tostring(mx) .. " node=" .. tostring(fsm:call("getCurrentNodeName(System.UInt32)", 0))
  if not c:call("get_IsDead") and hp < 5 then
    local ok, e = pcall(hit.call, hit, "setHpValue(System.Single, System.Boolean)", mx * 0.5, false)
    line = line .. " | setHpValue ok=" .. tostring(ok) .. " " .. tostring(e) .. " -> hp=" .. tostring(hit:call("get_Hp"))
  end
  out[#out+1] = line
end
return table.concat(out, "\n")
