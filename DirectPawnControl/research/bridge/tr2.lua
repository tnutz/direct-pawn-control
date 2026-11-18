local out = {}
local ar = sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer")
local c = ar:call("get_Human"):call("get_Job09ActionCtrl")
local h = c:call("get_DecoyHandler")
out[#out+1] = "handler = " .. tostring(h)
local td = sdk.find_type_definition("app.DecoyHandler")
for _, m in ipairs(td:get_methods()) do
  local n = m:get_name()
  local np = 0; pcall(function() np = #m:get_param_types() end)
  local rt = ""; pcall(function() rt = m:get_return_type():get_full_name() end)
  local v = ""
  if h and np == 0 and (n:find("^get_") or n:find("^is")) then local ok, r = pcall(h.call, h, n); v = " = " .. tostring(ok and r) end
  out[#out+1] = n .. "/" .. np .. " -> " .. rt .. v
end
for _, f in ipairs(td:get_fields()) do
  local v = ""; if h then local ok, r = pcall(h.get_field, h, f:get_name()); v = " = " .. tostring(ok and r) end
  out[#out+1] = "field " .. f:get_name() .. ":" .. tostring(f:get_type():get_full_name()) .. v
end
return table.concat(out, "\n")
