-- Read-only: every hit of a layer-0 ray along the camera centre line, with each collidable's own layer / group and object.
local r = {}
local tr = sdk.get_primary_camera():call("get_GameObject"):call("get_Transform")
local p, z = tr:call("get_Position"), tr:call("get_WorldMatrix")[2]
local std = sdk.find_type_definition("via.physics.System"); local sys = sdk.get_native_singleton("via.physics.System")
local q = sdk.create_instance("via.physics.CastRayQuery"):add_ref()
q:call("setRay(via.vec3, via.vec3)", Vector3f.new(p.x, p.y, p.z), Vector3f.new(p.x - z.x * 150.0, p.y - z.y * 150.0, p.z - z.z * 150.0))
q:call("clearOptions"); q:call("enableAllHits"); q:call("enableNearSort")
local res = sdk.call_native_func(sys, std, "castRay(via.physics.CastRayQuery)", q)
local n = res:call("get_NumContactPoints")
r[#r + 1] = "hits " .. tostring(n)
for i = 0, math.min(n - 1, 29) do
  local s = "#" .. i
  pcall(function()
    local pos = res:call("getContactPoint(System.UInt32)", i):get_field("Position")
    s = s .. string.format(" %.2fm", math.sqrt((pos.x - p.x) ^ 2 + (pos.y - p.y) ^ 2 + (pos.z - p.z) ^ 2))
  end)
  pcall(function()
    local c = res:call("getContactCollidable(System.UInt32)", i)
    local go = c:call("get_GameObject")
    s = s .. " " .. tostring(go:call("get_Name"))
    pcall(function() local fi = c:call("get_FilterInfo"); s = s .. " L" .. tostring(fi:call("get_Layer")) .. " g" .. tostring(fi:call("get_Group")) .. " m" .. string.format("%x", fi:call("get_MaskBits")) end)
    pcall(function() s = s .. " tag=" .. tostring(go:call("get_Tag")) end)
    pcall(function() local f = go:call("get_Folder"); s = s .. " folder=" .. tostring(f and f:call("get_Name")) end)
  end)
  r[#r + 1] = s
end
local cm = sdk.get_managed_singleton("app.CameraManager"); local ch = cm:call("getMainCameraController", 0):call("get_TargetCharacter")
local q2 = ch:call("get_Transform"):call("get_Position")
r[#r + 1] = string.format("char %.1f m from camera; pitch %.0f", math.sqrt((q2.x - p.x) ^ 2 + (q2.y - p.y) ^ 2 + (q2.z - p.z) ^ 2), math.deg(math.asin(-z.y)))
return table.concat(r, " | ")
