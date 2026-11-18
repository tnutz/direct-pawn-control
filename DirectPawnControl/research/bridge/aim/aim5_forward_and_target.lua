-- Read-only: which way is the camera's forward axis, and what does the character's aim target look like?
local cm = sdk.get_managed_singleton("app.CameraManager"); local mcc = cm:call("getMainCameraController", 0)
local ch = mcc:call("get_TargetCharacter")
local r = {}
local tr = sdk.get_primary_camera():call("get_GameObject"):call("get_Transform")
local p, m = tr:call("get_Position"), tr:call("get_WorldMatrix")
local z = m[2]
local q = ch:call("get_Transform"):call("get_Position")
local dx, dy, dz = q.x - p.x, q.y - p.y, q.z - p.z
r[#r + 1] = string.format("char-cam dist %.2f ; dot with -row2 = %.2f (positive: forward is -Z)", math.sqrt(dx * dx + dy * dy + dz * dz), -(dx * z.x + dy * z.y + dz * z.z))
r[#r + 1] = string.format("row2 = %.2f,%.2f,%.2f", z.x, z.y, z.z)
local az = tr:call("get_AxisZ"); r[#r + 1] = string.format("AxisZ = %.2f,%.2f,%.2f", az.x, az.y, az.z)
local function desc(v)
  local s = type(v) .. " " .. tostring(v)
  pcall(function() s = s .. " type=" .. v:get_type_definition():get_full_name() end)
  pcall(function() s = s .. string.format(" xyz=%.2f,%.2f,%.2f", v.x, v.y, v.z) end)
  return s
end
for _, n in ipairs({ "get_AimTargetPosition", "get_AimTargetUniversalPosition", "get_AimTargetRootPosition", "get_AimTargetFrontAngleDeg", "get_AimTargetDown", "get_AimCharacter", "get_AimObject", "get_TargetFrontAngleDeg" }) do
  local ok, v = pcall(ch.call, ch, n)
  r[#r + 1] = n .. " -> " .. (ok and desc(v) or ("ERR " .. tostring(v)))
end
local td = ch:get_type_definition()
for _, mm in ipairs(td:get_methods()) do
  local n = mm:get_name()
  if n:find("AimTarget") and n:find("^set_") then
    local ps = {}
    for _, pt in ipairs(mm:get_param_types()) do ps[#ps + 1] = pt:get_full_name() end
    r[#r + 1] = n .. "(" .. table.concat(ps, ",") .. ")"
  end
end
r[#r + 1] = "char pos " .. string.format("%.1f,%.1f,%.1f", q.x, q.y, q.z) .. " who " .. tostring(ch:get_GameObject():call("get_Name"))
return table.concat(r, " | ")
