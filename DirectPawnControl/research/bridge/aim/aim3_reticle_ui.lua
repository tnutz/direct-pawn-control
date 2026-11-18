-- Read-only. (a) methods / fields of the bow reticle UI (app.ui020801) and Player reticle code.
-- (b) interactive objects within 4 m of the camera's target character (the possessed pawn), with their concrete types.
local out = { ui = {}, player = {}, near = {} }
local function dump(name, into, pat, depthmax)
  local t, d = sdk.find_type_definition(name), 0
  while t and d < (depthmax or 1) do
    for _, f in ipairs(t:get_fields()) do if not pat or f:get_name():find(pat) then into[#into + 1] = "F " .. f:get_name() .. " : " .. f:get_type():get_full_name() end end
    for _, m in ipairs(t:get_methods()) do
      if not pat or m:get_name():find(pat) then
        local ps = {}
        for _, pt in ipairs(m:get_param_types()) do ps[#ps + 1] = pt:get_full_name() end
        into[#into + 1] = "M " .. m:get_name() .. "(" .. table.concat(ps, ", ") .. ")"
      end
    end
    t = t:get_parent_type(); d = d + 1
  end
end
dump("app.ui020801", out.ui, nil, 1)
dump("app.Player", out.player, "[Rr]eticle", 1)
dump("app.Player", out.player, "Aim", 1)
out.item = {}
dump("app.InteractManager", out.item, nil, 1)
local ok, err = pcall(function()
  local cm = sdk.get_managed_singleton("app.CameraManager"); local mcc = cm:call("getMainCameraController", 0)
  local ch = mcc:call("get_TargetCharacter")
  local pp = ch:call("get_Transform"):call("get_Position")
  out.who = tostring(ch:get_GameObject():call("get_Name"))
  local im = sdk.get_managed_singleton("app.InteractManager")
  for _, s in ipairs(im:get_field("InteractiveObjects"):get_field("_entries"):get_elements()) do
    local oks, o = pcall(s.get_field, s, "Value"); if not (oks and o) then oks, o = pcall(s.get_field, s, "value") end
    if oks and o then pcall(function()
      local go = o:get_field("<Owner>k__BackingField")
      local q = go:call("get_Transform"):call("get_Position")
      local dd = math.sqrt((q.x - pp.x) ^ 2 + (q.y - pp.y) ^ 2 + (q.z - pp.z) ^ 2)
      if dd <= 4.0 then
        local e = { name = tostring(go:call("get_Name")), dist = dd, type = o:get_type_definition():get_full_name(), points = o:call("get_NumInteractPoints"), comps = {}, fields = {} }
        for _, c in ipairs(go:call("get_Components"):get_elements()) do pcall(function() e.comps[#e.comps + 1] = c:get_type_definition():get_full_name() end) end
        local t, d = o:get_type_definition(), 0
        while t and d < 3 do
          for _, f in ipairs(t:get_fields()) do
            local okv, v = pcall(o.get_field, o, f:get_name())
            if okv then
              local sv = tostring(v)
              if type(v) == "userdata" then pcall(function() sv = "<" .. v:get_type_definition():get_full_name() .. ">" end) end
              e.fields[f:get_name()] = sv
            end
          end
          t = t:get_parent_type(); d = d + 1
        end
        out.near[#out.near + 1] = e
      end
    end) end
  end
end)
out.err = not ok and tostring(err) or nil
json.dump_file("DPC_probe_aim_3.json", out)
return "ui " .. #out.ui .. " near " .. #out.near .. " who " .. tostring(out.who) .. " " .. tostring(out.err)
