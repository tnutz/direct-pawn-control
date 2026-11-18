local out = {}
local pm = sdk.get_managed_singleton("app.PawnManager")
local list = pm:call("get_PawnCharacterList")
local function find_pawn(c)
  local go = c:call("get_GameObject")
  local comps = go:call("get_Components")
  local n = comps and comps:call("get_Count") or (comps and #comps) or 0
  local names = {}
  local found
  local ok = pcall(function()
    for i = 0, comps:get_size() - 1 do
      local k = comps:get_element(i)
      local tn = k:get_type_definition():get_full_name()
      names[#names + 1] = tn
      local td = k:get_type_definition()
      while td do if td:get_full_name() == "app.Pawn" then found = k; break end; td = td:get_parent_type() end
    end
  end)
  return found, names, ok
end
for i = 0, list:call("get_Count") - 1 do
  local c = list:call("get_Item", i)
  if c:call("get_IsDead") then
    local pw, names, ok = find_pawn(c)
    out[#out+1] = "comps ok=" .. tostring(ok) .. " n=" .. #names .. " pawn=" .. tostring(pw and pw:get_type_definition():get_full_name())
    local pawnish = {}
    for _, n in ipairs(names) do if n:lower():find("pawn") then pawnish[#pawnish+1] = n end end
    out[#out+1] = "pawnish: " .. table.concat(pawnish, ", ")
    for _, m in ipairs({ "get_Pawn", "get_PawnController", "get_Human" }) do
      local okm, v = pcall(c.call, c, m); out[#out+1] = m .. " = " .. tostring(okm and v and v:get_type_definition():get_full_name())
    end
    if pw then
      local hit = c:call("get_Hit")
      local okr, e = pcall(pw.call, pw, "setPawnRevive(System.Single, System.Boolean, System.Boolean)", 0.5, false, false)
      out[#out+1] = "setPawnRevive ok=" .. tostring(okr) .. " " .. tostring(e) .. " -> dead=" .. tostring(c:call("get_IsDead")) .. " hp=" .. tostring(hit:call("get_Hp"))
    end
  end
end
if #out == 0 then out[1] = "no dead pawn" end
return table.concat(out, "\n")
