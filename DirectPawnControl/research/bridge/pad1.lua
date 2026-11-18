local out = {}
local function scan(tn, pats)
  local td = sdk.find_type_definition(tn)
  if not td then out[#out+1] = tn .. " = nil"; return end
  for _, m in ipairs(td:get_methods()) do
    local l = m:get_name():lower()
    for _, p in ipairs(pats) do if l:find(p) then
      local ps = {}
      pcall(function() for _, pt in ipairs(m:get_param_types()) do ps[#ps+1] = pt:get_full_name() end end)
      local rt = ""; pcall(function() rt = m:get_return_type():get_full_name() end)
      out[#out+1] = tn .. "." .. m:get_name() .. "(" .. table.concat(ps, ",") .. ") -> " .. rt; break end end
  end
end
scan("via.hid.GamePadDevice", { "kind", "type", "name", "vendor", "product", "device", "style", "platform" })
scan("via.hid.GamePad", { "kind", "type", "name", "device", "connect", "count" })
scan("app.HitController", { "invinc", "nodie", "nodead", "immortal", "nodamage", "undead", "muteki", "guts", "damagerate", "isdie", "set_isno" })
scan("app.Character", { "invinc", "nodie", "immortal", "nodamage" })
scan("app.UserPadManager", { "kind", "type", "style", "device", "icon", "platform" })
local gp = sdk.get_native_singleton("via.hid.GamePad")
local gtd = sdk.find_type_definition("via.hid.GamePad")
local ok, pad = pcall(sdk.call_native_func, gp, gtd, "get_MergedDevice")
out[#out+1] = "merged ok=" .. tostring(ok) .. " " .. tostring(pad)
if ok and pad then
  for _, m in ipairs({ "get_Name", "get_DeviceKind", "get_Kind", "get_DeviceType", "get_Type", "get_VendorID", "get_ProductID", "get_DeviceKindDetails", "get_ConnectingDeviceKind" }) do
    local okm, v = pcall(pad.call, pad, m); if okm and v ~= nil then out[#out+1] = "merged:" .. m .. " = " .. tostring(v) end
  end
end
local upm = sdk.get_managed_singleton("app.UserPadManager")
if upm then for _, m in ipairs({ "get_PadType", "get_DeviceKind", "get_IconType", "getPadKind", "get_CurrentDeviceKind" }) do
  local okm, v = pcall(upm.call, upm, m); if okm and v ~= nil then out[#out+1] = "UserPadManager:" .. m .. " = " .. tostring(v) end end end
return table.concat(out, "\n")
