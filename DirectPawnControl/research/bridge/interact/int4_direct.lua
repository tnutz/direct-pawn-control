local im = sdk.get_managed_singleton("app.InteractManager")
local pw = sdk.get_managed_singleton("app.PawnManager"):call("get_PawnCharacterList")[0]
local pp = pw:call("get_Transform"):call("get_Position")
local best, bd, bn
for _, s in ipairs(im:get_field("InteractiveObjects"):get_field("_entries"):get_elements()) do
  local ok, o = pcall(s.get_field, s, "Value"); if not (ok and o) then ok, o = pcall(s.get_field, s, "value") end
  if ok and o then pcall(function()
    local go = o:get_field("<Owner>k__BackingField")
    local nm = tostring(go:call("get_Name"))
    local p = go:call("get_Transform"):call("get_Position")
    local d = math.sqrt((p.x - pp.x) ^ 2 + (p.y - pp.y) ^ 2 + (p.z - pp.z) ^ 2)
    if d < 4 and not nm:find("^ch1") and (not bd or d < bd) then best, bd, bn = o, d, nm end
  end) end
end
if not best then return "nothing within 4 m" end
local out = { string.format("target %s %.1f m", bn, bd) }
-- enum names of the AI request result, for reading earlier results
pcall(function()
  local td = sdk.find_type_definition("app.InteractManager.InteractRequestResult")
  local l = {}
  for _, f in ipairs(td:get_fields()) do if f:is_static() then l[#l + 1] = f:get_name() .. "=" .. tostring(f:get_data(nil)) end end
  out[#out + 1] = "results: " .. table.concat(l, ",")
end)
local ok1, e1 = pcall(function()
  local pt = sdk.create_instance("app.InteractManager.InteractPoint"):add_ref()
  pt:set_field("Object", best); pt:set_field("PointNo", 0)
  im:call("addActiveInteract(app.Character, app.InteractManager.InteractPoint)", pw, pt)
end)
out[#out + 1] = "addActive ok=" .. tostring(ok1) .. " " .. tostring(e1 or "")
local ok2, e2 = pcall(im.call, im, "executeInteract(app.Character)", pw)
out[#out + 1] = "execute ok=" .. tostring(ok2) .. " " .. tostring(e2 or "")
out[#out + 1] = "interacting=" .. tostring(im:call("isInteracting(app.Character)", pw))
_G.INT4 = { t = os.clock() }
return table.concat(out, " | ")
