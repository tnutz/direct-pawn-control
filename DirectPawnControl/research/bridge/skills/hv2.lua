local out = {}
local pm = sdk.get_managed_singleton("app.PawnManager"); if not pm then return "no pm" end
local function desc(v)
  if type(v) ~= "userdata" then return tostring(v) end
  local d = "ud"
  pcall(function() d = v:get_type_definition():get_full_name() end)
  pcall(function() local c = v:call("get_Count"); if c then d = d .. "#" .. tostring(c) end end)
  pcall(function() local p = v:call("get_Path"); if p then d = d .. " path=" .. tostring(p) end end)
  return d
end
local function fields(o, label, depth)
  local t = o:get_type_definition()
  while t do
    for _, f in ipairs(t:get_fields()) do
      if not f:is_static() then
        local v = nil; pcall(function() v = o:get_field(f:get_name()) end)
        out[#out+1] = label .. "." .. f:get_name() .. " = " .. desc(v)
      end
    end
    t = t:get_parent_type()
    if t and (t:get_full_name() == "System.Object" or t:get_full_name() == "via.Behavior") then break end
  end
end
local ok, e = pcall(function()
  local lst = pm:call("get_PawnCharacterList")
  local ch = lst:call("get_Item", 2)
  local dm = ch:get_field("<AIDecisionMaker>k__BackingField")
  fields(dm, "dm")
  local mod = dm:call("get_DecisionModule")
  local h = mod:get_field("<DecisionPackHandler>k__BackingField")
  fields(h, "handler")
  local ms = {}
  for _, m in ipairs(h:get_type_definition():get_methods()) do ms[#ms+1] = m:get_name() end
  out[#out+1] = "handler methods: " .. table.concat(ms, " ")
  local d = mod:get_field("<MainDecisions>k__BackingField"):call("get_Item", 0)
  fields(d, "decision0")
end)
if not ok then out[#out+1] = "err " .. tostring(e) end
return table.concat(out, "\n")
