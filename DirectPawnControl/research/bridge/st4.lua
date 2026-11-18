local out = {}
local ar = sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer")
local l = ar:get_field("StaminaParams")
local n = l:call("get_Count")
out[#out+1] = "StaminaParams count=" .. tostring(n)
for i = 0, n - 1 do
  local e = l:call("get_Item", i)
  local r = { e:get_type_definition():get_full_name() }
  for _, f in ipairs(e:get_type_definition():get_fields()) do
    local v = ""; pcall(function() v = tostring(e:get_field(f:get_name())) end)
    if not v:find("sol%.") then r[#r+1] = f:get_name() .. "=" .. v end
  end
  out[#out+1] = table.concat(r, " ")
end
local hu = ar:call("get_Human")
for _, m in ipairs({ "get_Job04ActionCtrl", "get_Job04ActionController" }) do
  local ok, c = pcall(hu.call, hu, m)
  if ok and c then
    out[#out+1] = m .. " -> " .. c:get_type_definition():get_full_name()
    for _, f in ipairs(c:get_type_definition():get_fields()) do
      local v = ""; pcall(function() v = tostring(c:get_field(f:get_name())) end)
      if not v:find("sol%.") then out[#out+1] = " f " .. f:get_name() .. "=" .. v end
    end
  end
end
return table.concat(out, "\n")
