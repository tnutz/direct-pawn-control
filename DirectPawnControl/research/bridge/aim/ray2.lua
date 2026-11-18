-- Read-only: cast along the camera centre line with castRay(CastRayQuery) for each filter layer; report first hits.
local r = {}
local tr = sdk.get_primary_camera():call("get_GameObject"):call("get_Transform")
local p, z = tr:call("get_Position"), tr:call("get_WorldMatrix")[2]
local s = Vector3f.new(p.x, p.y, p.z)
local e = Vector3f.new(p.x - z.x * 150.0, p.y - z.y * 150.0, p.z - z.z * 150.0)
local std = sdk.find_type_definition("via.physics.System")
local sys = sdk.get_native_singleton("via.physics.System")
local ok, err = pcall(function()
  local q = sdk.create_instance("via.physics.CastRayQuery"):add_ref()
  q:call("setRay(via.vec3, via.vec3)", s, e)
  q:call("clearOptions"); q:call("enableAllHits"); q:call("enableNearSort")
  local fi = q:call("get_FilterInfo")
  for layer = 0, 40 do
    fi:call("set_Layer", layer); fi:call("set_MaskBits", 0xFFFFFFFF); q:call("set_FilterInfo", fi)
    local okc, res = pcall(sdk.call_native_func, sys, std, "castRay(via.physics.CastRayQuery)", q)
    if not okc then r[#r + 1] = "L" .. layer .. " ERR " .. tostring(res); break end
    local n = res and res:call("get_NumContactPoints") or -1
    if n and n > 0 then
      local out = "L" .. layer .. " hits " .. n
      for i = 0, math.min(n - 1, 2) do
        pcall(function()
          local cp = res:call("getContactPoint(System.UInt32)", i)
          local pos = cp:get_field("Position")
          local d = math.sqrt((pos.x - p.x) ^ 2 + (pos.y - p.y) ^ 2 + (pos.z - p.z) ^ 2)
          local nm = "?"
          pcall(function() nm = tostring(res:call("getContactCollidable(System.UInt32)", i):call("get_GameObject"):call("get_Name")) end)
          out = out .. string.format(" [%.2fm %s]", d, nm)
        end)
      end
      r[#r + 1] = out
    elseif layer == 0 then r[#r + 1] = "L0 hits " .. tostring(n) .. " res " .. tostring(res) end
  end
end)
if not ok then r[#r + 1] = "ERR " .. tostring(err) end
local cm = sdk.get_managed_singleton("app.CameraManager"); local ch = cm:call("getMainCameraController", 0):call("get_TargetCharacter")
local q2 = ch:call("get_Transform"):call("get_Position")
r[#r + 1] = string.format("char %s %.2f m from camera", tostring(ch:get_GameObject():call("get_Name")), math.sqrt((q2.x - p.x) ^ 2 + (q2.y - p.y) ^ 2 + (q2.z - p.z) ^ 2))
return table.concat(r, " | ")
