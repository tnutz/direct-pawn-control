local out = {}
local function scan(tn, pats)
  local td = sdk.find_type_definition(tn)
  if not td then out[#out+1] = tn .. " = nil"; return end
  out[#out+1] = "## " .. tn
  for _, m in ipairs(td:get_methods()) do
    local n = m:get_name(); local l = n:lower()
    for _, p in ipairs(pats) do if l:find(p) then
      local ps = {}
      pcall(function() for _, pt in ipairs(m:get_param_types()) do ps[#ps+1] = pt:get_full_name() end end)
      local rt = ""; pcall(function() rt = m:get_return_type():get_full_name() end)
      out[#out+1] = n .. "(" .. table.concat(ps, ",") .. ") -> " .. rt; break end end
  end
end
scan("app.ItemManager", { "use", "consume", "quick", "shortcut", "apply" })
local gm = sdk.get_managed_singleton("app.GuiManager")
for _, f in ipairs(gm:get_type_definition():get_fields()) do
  local n = f:get_name(); local l = n:lower(); local tn = tostring(f:get_type():get_full_name())
  for _, p in ipairs({ "shortcut", "quick", "itemuse", "useitem", "consume", "pouch", "itemslot" }) do if l:find(p) then
    out[#out+1] = "GuiManager." .. n .. " : " .. tn; break end end
end
for _, m in ipairs(gm:get_type_definition():get_methods()) do
  local l = m:get_name():lower()
  for _, p in ipairs({ "shortcut", "quick", "useitem", "consume" }) do if l:find(p) then out[#out+1] = "GuiManager:" .. m:get_name(); break end end
end
for _, sn in ipairs({ "app.ItemShortcutManager", "app.QuickItemManager", "app.ShortcutManager", "app.ItemUseManager" }) do
  out[#out+1] = sn .. " = " .. tostring(sdk.get_managed_singleton(sn)) .. " td=" .. tostring(sdk.find_type_definition(sn) ~= nil)
end
return table.concat(out, "\n")
