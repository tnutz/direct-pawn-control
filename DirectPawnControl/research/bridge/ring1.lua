local out = {}
local gm = sdk.get_managed_singleton("app.GuiManager")
for _, f in ipairs(gm:get_type_definition():get_fields()) do
  local tn = f:get_type():get_full_name()
  if tn:find("^app%.ui") or f:get_name():lower():find("lock") or f:get_name():lower():find("aim") or f:get_name():lower():find("reticle") or f:get_name():lower():find("bow") or f:get_name():lower():find("magic") then
    local ok, v = pcall(function() return gm:get_field(f:get_name()) end)
    out[#out+1] = f:get_name() .. ":" .. tn .. " = " .. tostring(ok and v ~= nil)
  end
end
return table.concat(out, "\n")
