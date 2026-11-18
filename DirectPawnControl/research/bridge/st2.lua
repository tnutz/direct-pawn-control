local out = {}
local ar = sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer")
local hu = ar:call("get_Human")
local function scan(obj, label, pats)
  local td = obj:get_type_definition()
  while td and td:get_full_name() ~= "System.Object" and td:get_full_name() ~= "via.Behavior" do
    for _, m in ipairs(td:get_methods()) do
      local n = m:get_name(); local l = n:lower()
      for _, p in ipairs(pats) do if l:find(p) then
        local np = 0; pcall(function() np = #m:get_param_types() end)
        local v = ""
        if np == 0 and (n:find("^get_") or n:find("^is")) then local ok, r = pcall(obj.call, obj, n); v = " = " .. tostring(ok and r) end
        out[#out+1] = label .. ":" .. n .. "/" .. np .. v; break end end
    end
    for _, f in ipairs(td:get_fields()) do
      local l = f:get_name():lower()
      for _, p in ipairs(pats) do if l:find(p) then
        local v = ""; pcall(function() v = tostring(obj:get_field(f:get_name())) end)
        out[#out+1] = label .. " f " .. f:get_name() .. ":" .. tostring(f:get_type():get_full_name()) .. " = " .. v; break end end
    end
    td = td:get_parent_type()
  end
end
scan(hu, "Human", { "dash", "sprint", "stamina", "exhaust" })
scan(ar, "Character", { "dash", "sprint", "staminarec", "stamina" })
return table.concat(out, "\n")
