local out = {}
local gm = sdk.get_managed_singleton("app.GuiManager")
local cg = gm:get_field("CrossGuide")
local function arr(name)
  local a = cg:get_field(name); local r = {}
  pcall(function() for i = 0, a:get_size() - 1 do local e = a:get_element(i); local v = e
    pcall(function() v = e:get_field("value__") end); r[#r+1] = tostring(v) end end)
  out[#out+1] = name .. " = [" .. table.concat(r, ",") .. "]"
end
arr("OrderActs"); arr("ShortcutActs"); arr("ShortcutInputs")
local sp = cg:get_field("ShortcutParam")
out[#out+1] = "ShortcutParam type " .. sp:get_type_definition():get_full_name()
for _, f in ipairs(sp:get_type_definition():get_fields()) do
  local v = ""; pcall(function() v = tostring(sp:get_field(f:get_name())) end)
  out[#out+1] = " f " .. f:get_name() .. ":" .. tostring(f:get_type():get_full_name()) .. "=" .. v
end
for _, m in ipairs(sp:get_type_definition():get_methods()) do
  local ps = {}
  pcall(function() for _, pt in ipairs(m:get_param_types()) do ps[#ps+1] = pt:get_full_name() end end)
  local rt = ""; pcall(function() rt = m:get_return_type():get_full_name() end)
  out[#out+1] = " m " .. m:get_name() .. "(" .. table.concat(ps, ",") .. ") -> " .. rt
end
local pc = cg:get_field("PlChara")
local ar = sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer")
out[#out+1] = "PlChara is Arisen: " .. tostring(pc and ar and pc:get_address() == ar:get_address()) .. " name=" .. tostring(pc and pc:call("get_GameObject"):call("get_Name"))
out[#out+1] = "isItemDisable=" .. tostring(cg:call("isItemDisable")) .. " isOrderDisable=" .. tostring(cg:call("isOrderDisable")) .. " checkEnable=" .. tostring(select(2, pcall(cg.call, cg, "checkEnable")))
return table.concat(out, "\n")
