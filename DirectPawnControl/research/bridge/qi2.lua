local out = {}
local gm = sdk.get_managed_singleton("app.GuiManager")
for _, f in ipairs(gm:get_type_definition():get_fields()) do
  local tn = tostring(f:get_type():get_full_name())
  if tn:find("^app%.ui") or tn:lower():find("item") or f:get_name():lower():find("item") then out[#out+1] = f:get_name() .. ":" .. tn end
end
local im = sdk.get_managed_singleton("app.ItemManager")
for _, f in ipairs(im:get_type_definition():get_fields()) do
  local l = f:get_name():lower()
  if l:find("short") or l:find("quick") or l:find("slot") or l:find("fav") or l:find("regist") then out[#out+1] = "ItemManager." .. f:get_name() .. ":" .. tostring(f:get_type():get_full_name()) end
end
for _, m in ipairs(im:get_type_definition():get_methods()) do
  local l = m:get_name():lower()
  if l:find("short") or l:find("quick") or l:find("fav") or l:find("regist") then out[#out+1] = "ItemManager:" .. m:get_name() end
end
return table.concat(out, " | ")
