-- Read-only: find the pawn name / health plates in the scene and what positions them.
local r = {}
local function desc(v)
  local s = tostring(v)
  if type(v) == "userdata" then
    local ok = pcall(function() s = "<" .. v:get_type_definition():get_full_name() .. ">" end)
    if not ok then pcall(function() s = string.format("vec(%.1f,%.1f,%.1f)", v.x, v.y, v.z or 0) end) end
  end
  return s
end
local function fields(o, lim)
  local l = {}
  local t, d = o:get_type_definition(), 0
  while t and d < 2 do
    for _, f in ipairs(t:get_fields()) do
      if not f:is_static() and #l < (lim or 60) then
        local ok, v = pcall(o.get_field, o, f:get_name())
        l[#l + 1] = f:get_name() .. ":" .. f:get_type():get_name() .. "=" .. (ok and desc(v) or "?")
      end
    end
    t = t:get_parent_type(); d = d + 1
  end
  return table.concat(l, " ; ")
end
local scene = sdk.call_native_func(sdk.get_native_singleton("via.SceneManager"), sdk.find_type_definition("via.SceneManager"), "get_CurrentScene()")
for _, tn in ipairs({ "app.ui022502", "app.ui022501", "app.ui022503", "app.ui020601", "app.ui020602" }) do
  local okt, ty = pcall(sdk.typeof, tn)
  if okt and ty then
    local okc, comps = pcall(scene.call, scene, "findComponents(System.Type)", ty)
    local els = okc and comps and comps:get_elements() or {}
    local n = #els
    r[#r + 1] = tn .. " count " .. tostring(n)
    if n and n > 0 then
      local c = els[1]
      r[#r + 1] = "FIELDS " .. fields(c, 50)
      local ms = {}
      for _, m in ipairs(c:get_type_definition():get_methods()) do
        local ps = {}
        for _, pt in ipairs(m:get_param_types()) do ps[#ps + 1] = pt:get_name() end
        ms[#ms + 1] = m:get_name() .. "(" .. table.concat(ps, ",") .. ")"
      end
      r[#r + 1] = "METHODS " .. table.concat(ms, " ")
      for _, f in ipairs(c:get_type_definition():get_fields()) do
        local ok, v = pcall(c.get_field, c, f:get_name())
        if ok and type(v) == "userdata" then
          pcall(function()
            local ftn = v:get_type_definition():get_full_name()
            local e
            if ftn:find("List") then e = v:call("get_Item", 0) elseif ftn:find("%[%]") then e = v[0] end
            if e then r[#r + 1] = "ELEM of " .. f:get_name() .. " <" .. e:get_type_definition():get_full_name() .. "> " .. fields(e, 40) end
          end)
        end
      end
    end
  else r[#r + 1] = tn .. " no type" end
end
return table.concat(r, " | ")
