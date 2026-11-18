-- Read-only: layout of System.Nullable<via.vec3> and the current aim target values of the camera's target character.
local cm = sdk.get_managed_singleton("app.CameraManager"); local mcc = cm:call("getMainCameraController", 0)
local ch = mcc:call("get_TargetCharacter")
local r = {}
local td = sdk.find_type_definition("System.Nullable`1<via.vec3>")
r[#r + 1] = "td " .. tostring(td ~= nil) .. " size " .. tostring(td and td:get_valuetype_size())
for _, f in ipairs(td:get_fields()) do r[#r + 1] = "F " .. f:get_name() .. " : " .. f:get_type():get_full_name() .. " @" .. tostring(f:get_offset_from_fieldptr()) end
for _, m in ipairs(td:get_methods()) do r[#r + 1] = "M " .. m:get_name() end
local v = ch:call("get_AimTargetPosition")
for _, n in ipairs({ "_HasValue", "hasValue", "has_value", "_Value", "value" }) do
  local ok, x = pcall(v.get_field, v, n)
  if ok and x ~= nil then
    local s = tostring(x); pcall(function() s = string.format("%.2f,%.2f,%.2f", x.x, x.y, x.z) end)
    r[#r + 1] = n .. " = " .. s
  end
end
local okh, hv = pcall(v.call, v, "get_HasValue"); r[#r + 1] = "get_HasValue " .. tostring(okh) .. " " .. tostring(hv)
local b = {}
for i = 0, 15 do local okb, x = pcall(v.read_byte, v, i); b[#b + 1] = okb and string.format("%02x", x) or "??" end
r[#r + 1] = "bytes " .. table.concat(b, " ")
local a = ch:call("get_AimTargetFrontAngleDeg")
local okh2, hv2 = pcall(a.call, a, "get_HasValue"); r[#r + 1] = "frontAngle HasValue " .. tostring(hv2)
return table.concat(r, " | ")
