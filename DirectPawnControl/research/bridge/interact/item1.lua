-- Dropped item (gm82_000_01) next to the possessed pawn: dump the item component, try the pawn-side interact again and
-- report each step. Also dumps the captured camera interp params from the archer-aim test (same Lua state).
local out = { comp = {}, interp = {} }
local cm = sdk.get_managed_singleton("app.CameraManager"); local mcc = cm:call("getMainCameraController", 0)
local ch = mcc:call("get_TargetCharacter")
local pp = ch:call("get_Transform"):call("get_Position")
local im = sdk.get_managed_singleton("app.InteractManager")
local best, bd, bgo
for _, s in ipairs(im:get_field("InteractiveObjects"):get_field("_entries"):get_elements()) do
  local oks, o = pcall(s.get_field, s, "Value"); if not (oks and o) then oks, o = pcall(s.get_field, s, "value") end
  if oks and o then pcall(function()
    local go = o:get_field("<Owner>k__BackingField")
    local n = tostring(go:call("get_Name"))
    if n:find("^gm82_000") then
      local q = go:call("get_Transform"):call("get_Position")
      local d = math.sqrt((q.x - pp.x) ^ 2 + (q.y - pp.y) ^ 2 + (q.z - pp.z) ^ 2)
      if d < 5 and (not bd or d < bd) then best, bd, bgo = o, d, go end
    end
  end) end
end
if best then
  out.target = tostring(bgo:call("get_Name")) .. string.format(" %.2f m", bd)
  for _, c in ipairs(bgo:call("get_Components"):get_elements()) do
    local okn, tn = pcall(function() return c:get_type_definition():get_full_name() end)
    if okn and (tn:find("Gm82") or tn:find("ItemFall")) then
      local l = {}
      local t, d = c:get_type_definition(), 0
      while t and d < 3 do
        for _, f in ipairs(t:get_fields()) do
          local okv, v = pcall(c.get_field, c, f:get_name()); local sv = tostring(v)
          if okv and type(v) == "userdata" then pcall(function() sv = "<" .. v:get_type_definition():get_full_name() .. ">" end) end
          l[#l + 1] = "F " .. f:get_name() .. " : " .. f:get_type():get_full_name() .. " = " .. sv
        end
        for _, m in ipairs(t:get_methods()) do
          local ps = {}
          for _, pt in ipairs(m:get_param_types()) do ps[#ps + 1] = pt:get_full_name() end
          l[#l + 1] = "M " .. m:get_name() .. "(" .. table.concat(ps, ", ") .. ")"
        end
        t = t:get_parent_type(); d = d + 1
      end
      out.comp[tn] = l
    end
  end
  local okh, en = pcall(function() return best:get_field("InteractEnabledHandler"):call("Invoke", 0) end)
  out.enabled = tostring(okh) .. " " .. tostring(en)
  local pt = sdk.create_instance("app.InteractManager.InteractPoint"):add_ref()
  pt:set_field("Object", best); pt:set_field("PointNo", 0)
  local ok1, e1 = pcall(im.call, im, "addActiveInteract(app.Character, app.InteractManager.InteractPoint)", ch, pt)
  local ok2, e2 = pcall(im.call, im, "executeInteract(app.Character)", ch)
  out.try_pawn = string.format("add ok=%s exec ok=%s interacting=%s", tostring(ok1), tostring(ok2), tostring(im:call("isInteracting(app.Character)", ch)))
else out.target = "no gm82_000 within 5 m" end
local function fields(o)
  local l = {}
  if not o then return "nil" end
  local t = o:get_type_definition(); l.type = t:get_full_name()
  for _, f in ipairs(t:get_fields()) do
    local okv, v = pcall(o.get_field, o, f:get_name()); local sv = tostring(v)
    if okv and type(v) == "userdata" then pcall(function() sv = "<" .. v:get_type_definition():get_full_name() .. ">" end) end
    l[f:get_name()] = f:get_type():get_full_name() .. " = " .. sv
  end
  return l
end
local A = _G.AIMY
if A then
  out.interp.enter = A.enter0 and { ct = A.enter0.ct, opt = A.enter0.opt, interp = fields(A.enter0.interp), pfx = tostring(A.enter0.pfx) }
  out.interp.exit = A.exit0 and { ct = A.exit0.ct, opt = A.exit0.opt, interp = fields(A.exit0.interp), pfx = tostring(A.exit0.pfx) }
  out.interp.same = A.enter0 and A.exit0 and A.enter0.interp and A.exit0.interp and A.enter0.interp:get_address() == A.exit0.interp:get_address()
end
json.dump_file("DPC_probe_item_1.json", out)
return tostring(out.target) .. " | enabled " .. tostring(out.enabled) .. " | " .. tostring(out.try_pawn)
