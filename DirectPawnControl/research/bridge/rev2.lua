local out = {}
local pm = sdk.get_managed_singleton("app.PawnManager")
local list = pm:call("get_PawnCharacterList")
for i = 0, list:call("get_Count") - 1 do
  local c = list:call("get_Item", i)
  if c:call("get_IsDead") then
    local go = c:call("get_GameObject")
    local pw = go:call("getComponent(System.Type)", sdk.typeof("app.Pawn"))
    local hit = c:call("get_Hit")
    out[#out+1] = tostring(go:call("get_Name")) .. " pawn=" .. tostring(pw) .. " hp=" .. tostring(hit:call("get_Hp")) .. " max=" .. tostring(hit:call("get_ReducedMaxHp"))
    if pw then
      local ok, e = pcall(pw.call, pw, "setPawnRevive(System.Single, System.Boolean, System.Boolean)", 0.5, false, false)
      out[#out+1] = "setPawnRevive ok=" .. tostring(ok) .. " " .. tostring(e)
      out[#out+1] = "after: dead=" .. tostring(c:call("get_IsDead")) .. " hp=" .. tostring(hit:call("get_Hp")) .. " DeadStatus=" .. tostring(pw:get_field("DeadStatus"))
    end
  end
end
if #out == 0 then out[1] = "no dead pawn" end
return table.concat(out, "\n")
