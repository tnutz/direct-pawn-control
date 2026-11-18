local out = {}
local function dump(tag, o, depth)
  if o == nil then out[#out+1] = tag .. " = nil"; return end
  local td = o:get_type_definition()
  out[#out+1] = tag .. " : " .. td:get_full_name()
  local t = td
  while t and t:get_full_name() ~= "System.Object" and not t:get_full_name():find("^via%.") do
    for _, f in ipairs(t:get_fields()) do if not f:is_static() then
      local ok, v = pcall(function() return o:get_field(f:get_name()) end)
      local s = tostring(ok and v)
      if ok and type(v) == "userdata" then
        pcall(function() s = v:get_type_definition():get_full_name() end)
        pcall(function() s = s .. " " .. tostring(v:call("get_CharaIDString")) end)
        pcall(function() s = s .. string.format(" (%.1f,%.1f,%.1f)", v.x, v.y, v.z) end)
      end
      out[#out+1] = "  " .. f:get_name() .. " = " .. s
    end end
    t = t:get_parent_type()
  end
  local ms = {}
  for _, m in ipairs(td:get_methods()) do ms[#ms+1] = m:get_name() end
  out[#out+1] = "  M: " .. table.concat(ms, " ")
end
local D = _G.DPC_dbg
local pm = sdk.get_managed_singleton("app.PawnManager")
local con = pm and pm:call("get_PawnConcierge")
dump("PawnConcierge", con)
local ch = D and D.state.pawn_chara
local nav = ch and ch:call("get_NavigationController")
if nav then dump("nav._Data", nav:get_field("_Data")) 
  out[#out+1] = "conciergeMoveTime=" .. tostring(nav:get_field("_ConciergeMoveTime")) .. " timer=" .. tostring(nav:get_field("_Timer")) .. " startStrafe=" .. tostring(nav:get_field("_IsStartStrafe"))
  out[#out+1] = "isDisableNavigationAI=" .. tostring(nav:call("isDisableNavigationAI"))
end
local nai = D and D.state.pawn_obj and D.state.pawn_obj:call("get_CachedNavigationAI")
if nai then
  local td = nai:get_type_definition(); local ms = {}
  for _, m in ipairs(td:get_methods()) do ms[#ms+1] = m:get_name() end
  out[#out+1] = "NavigationAI M: " .. table.concat(ms, " ")
  for _, f in ipairs(td:get_fields()) do local ok, v = pcall(function() return nai:get_field(f:get_name()) end)
    if ok and (type(v) == "boolean" or type(v) == "number") then out[#out+1] = "  nai." .. f:get_name() .. "=" .. tostring(v) end end
end
out[#out+1] = "active=" .. tostring(D and D.state.active) .. " ai_ends=" .. tostring(D and D.R.ai_ends)
return table.concat(out, "\n")
