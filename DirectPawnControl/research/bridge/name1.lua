local out = {}
local pm = sdk.get_managed_singleton("app.PawnManager")
local l = pm:call("get_PawnCharacterList")
for i = 0, l:call("get_Count") - 1 do
  local ch = l:call("get_Item", i)
  local pdc = ch:call("get_Human"):call("get_PawnDataContext")
  if pdc then
    local s = tostring(ch:call("get_GameObject"):call("get_Name")) .. ":"
    local t = pdc:get_type_definition()
    while t and t:get_full_name() ~= "System.Object" do
      for _, m in ipairs(t:get_methods()) do
        local n = m:get_name()
        if n:lower():find("name") or n:lower():find("nick") or n:lower():find("moniker") then
          local np = 0; pcall(function() np = #m:get_param_types() end)
          local v = ""
          if np == 0 and n:find("^get") then local ok, x = pcall(pdc.call, pdc, n); v = "=" .. tostring(ok and x) end
          s = s .. " " .. n .. "/" .. np .. v
        end
      end
      for _, f in ipairs(t:get_fields()) do local n = f:get_name()
        if n:lower():find("name") or n:lower():find("nick") or n:lower():find("moniker") then
          local ok, x = pcall(function() return pdc:get_field(n) end); s = s .. " F:" .. n .. "=" .. tostring(ok and x)
        end
      end
      t = t:get_parent_type()
    end
    out[#out+1] = s
  end
end
local gm = sdk.get_managed_singleton("app.GuiManager")
local t = sdk.find_type_definition("app.GuiManager")
for _, m in ipairs(t:get_methods()) do local n = m:get_name():lower(); if n:find("pawnname") or n:find("charaname") or n:find("getname") or n:find("moniker") then out[#out+1] = "GuiManager." .. m:get_name() end end
local u = gm:get_field("MagicBowReticle")
if u then
  local ms = {}
  local tt = u:get_type_definition()
  for _, m in ipairs(tt:get_methods()) do ms[#ms+1] = m:get_name() end
  out[#out+1] = "ui020804 M: " .. table.concat(ms, " ")
  pcall(function() out[#out+1] = "ui020804 go drawself=" .. tostring(u:call("get_GameObject"):call("get_DrawSelf")) end)
end
return table.concat(out, "\n")
