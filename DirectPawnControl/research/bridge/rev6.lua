local out = {}
local pm = sdk.get_managed_singleton("app.PawnManager")
local list = pm:call("get_PawnCharacterList")
for i = 0, list:call("get_Count") - 1 do
  local c = list:call("get_Item", i)
  if c:call("get_IsDead") then
    local pw = pm:call("getPartyPawn(app.Character, System.Boolean)", c, false)
    if not pw then pw = pm:call("getPartyPawn(app.Character, System.Boolean)", c, true) end
    local hit = c:call("get_Hit")
    out[#out+1] = "pawn=" .. tostring(pw) .. " hp=" .. tostring(hit:call("get_Hp"))
    if pw then
      local okr, e = pcall(pw.call, pw, "setPawnRevive(System.Single, System.Boolean, System.Boolean)", 0.5, false, false)
      out[#out+1] = "setPawnRevive ok=" .. tostring(okr) .. " " .. tostring(e) .. " -> dead=" .. tostring(c:call("get_IsDead")) .. " hp=" .. tostring(hit:call("get_Hp"))
    end
  end
end
if #out == 0 then out[1] = "no dead pawn" end
return table.concat(out, "\n")
