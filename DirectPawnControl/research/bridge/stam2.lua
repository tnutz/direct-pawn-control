-- Read-only: the pawn over-head plate UI (app.ui022502): fields, per-pawn entries, anything with a screen position.
local r = {}
local gm = sdk.get_managed_singleton("app.GuiManager")
local ui = gm:get_field("PawnOverHead")
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
r[#r + 1] = "ui " .. ui:get_type_definition():get_full_name()
r[#r + 1] = fields(ui, 45)
local ms = {}
for _, m in ipairs(ui:get_type_definition():get_methods()) do
  local ps = {}
  for _, pt in ipairs(m:get_param_types()) do ps[#ps + 1] = pt:get_name() end
  ms[#ms + 1] = m:get_name() .. "(" .. table.concat(ps, ",") .. ")"
end
r[#r + 1] = "methods " .. table.concat(ms, " ")
-- first element of any list / array field
for _, f in ipairs(ui:get_type_definition():get_fields()) do
  local ok, v = pcall(ui.get_field, ui, f:get_name())
  if ok and type(v) == "userdata" then
    pcall(function()
      local tn = v:get_type_definition():get_full_name()
      local e
      if tn:find("List") then e = v:call("get_Item", 0) elseif tn:find("%[%]") then e = v[0] end
      if e then r[#r + 1] = "ELEM of " .. f:get_name() .. " <" .. e:get_type_definition():get_full_name() .. "> " .. fields(e, 40) end
    end)
  end
end
return table.concat(r, " | ")
