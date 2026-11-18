local out = {}
local pm = sdk.get_managed_singleton("app.PawnManager"); if not pm then return "no pm" end
local function elems(x)
  if not x then return {} end
  local ok, e = pcall(function() return x:get_elements() end)
  if ok and e then return e end
  local r = {}
  pcall(function() local n = x:call("get_Count"); for i = 0, n - 1 do r[#r+1] = x:call("get_Item", i) end end)
  return r
end
local function desc(v)
  if type(v) ~= "userdata" then return tostring(v) end
  local d = "ud"
  pcall(function() d = v:get_type_definition():get_full_name() end)
  pcall(function() local c = v:call("get_Count"); if c then d = d .. "#" .. tostring(c) end end)
  pcall(function() d = d .. "#" .. tostring(#v:get_elements()) end)
  pcall(function() local p = v:call("get_Path"); if p then d = d .. " path=" .. tostring(p) end end)
  return d
end
local function fields(o, label)
  local t = o:get_type_definition()
  while t do
    if t:get_full_name() == "System.Object" or t:get_full_name() == "via.Behavior" or t:get_full_name() == "via.UserData" then break end
    for _, f in ipairs(t:get_fields()) do
      if not f:is_static() then
        local v = nil; pcall(function() v = o:get_field(f:get_name()) end)
        out[#out+1] = label .. "." .. f:get_name() .. " = " .. desc(v)
      end
    end
    t = t:get_parent_type()
  end
end
local ok, e = pcall(function()
  local lst = pm:call("get_PawnCharacterList")
  local n = lst:call("get_Count")
  for i = 0, n - 1 do
    local ch = lst:call("get_Item", i)
    local go = ch:call("get_GameObject")
    local gp = go:call("getComponent(System.Type)", sdk.typeof("app.goalplanning.AIGoalPlanning"))
    if not gp then out[#out+1] = "pawn" .. i .. " no goalplanning" else
      local gd = gp:get_field("_AIGoalData")
      out[#out+1] = "pawn" .. i .. " goaldata " .. desc(gd)
      if gd and i == 0 then
        fields(gd, "gd")
        local cs = gd:get_field("_CSDecisions")
        if cs then
          out[#out+1] = "cs " .. desc(cs); fields(cs, "cs")
          local cu = cs:get_field("_CustomSkillDecisions")
          local arr = elems(cu)
          out[#out+1] = "custom n=" .. #arr
          if arr[1] then fields(arr[1], "cu1") end
          if #arr == 0 and cu then fields(cu, "cu") end
        end
      end
    end
  end
end)
if not ok then out[#out+1] = "err " .. tostring(e) end
return table.concat(out, "\n")
