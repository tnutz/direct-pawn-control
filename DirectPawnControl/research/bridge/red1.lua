local out = {}
local gm = sdk.get_managed_singleton("app.GuiManager")
local td = gm:get_type_definition()
local pats = { "damage", "dying", "pinch", "lowhp", "hpwarn", "vignette", "blood", "danger", "crisis", "filter", "screen", "hit" }
for _, f in ipairs(td:get_fields()) do
  local n = f:get_name(); local l = n:lower(); local tn = tostring(f:get_type():get_full_name())
  for _, p in ipairs(pats) do if l:find(p) or tn:lower():find(p) then
    local v = ""; pcall(function() v = tostring(gm:get_field(n)) end)
    out[#out+1] = "GuiManager." .. n .. " : " .. tn .. " = " .. v; break end end
end
for _, m in ipairs(td:get_methods()) do
  local l = m:get_name():lower()
  for _, p in ipairs({ "damage", "dying", "pinch", "vignette", "blood", "danger", "crisis" }) do if l:find(p) then out[#out+1] = "GuiManager:" .. m:get_name(); break end end
end
for _, sn in ipairs({ "app.PostEffectManager", "app.ScreenEffectManager", "app.FilterManager", "app.CameraEffectManager", "app.DamageEffectManager", "app.GraphicsManager", "app.PostEffectSettingManager" }) do
  out[#out+1] = sn .. " = " .. tostring(sdk.get_managed_singleton(sn))
end
return table.concat(out, "\n")
