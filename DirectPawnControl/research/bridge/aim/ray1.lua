-- Read-only: can Lua cast a ray along the camera's centre line, and what does it hit?
local r = {}
local tr = sdk.get_primary_camera():call("get_GameObject"):call("get_Transform")
local p, z = tr:call("get_Position"), tr:call("get_WorldMatrix")[2]
local s = Vector3f.new(p.x, p.y, p.z)
local e = Vector3f.new(p.x - z.x * 150.0, p.y - z.y * 150.0, p.z - z.z * 150.0)
local qtd, rtd = sdk.find_type_definition("via.physics.CastRayQuery"), sdk.find_type_definition("via.physics.CastRayResult")
r[#r + 1] = "types " .. tostring(qtd ~= nil) .. " " .. tostring(rtd ~= nil)
local function names(td, pat)
  local l = {}
  for _, m in ipairs(td:get_methods()) do
    if not pat or m:get_name():find(pat) then
      local ps = {}
      for _, pt in ipairs(m:get_param_types()) do ps[#ps + 1] = pt:get_name() end
      l[#l + 1] = m:get_name() .. "(" .. table.concat(ps, ",") .. ")"
    end
  end
  return table.concat(l, " ")
end
r[#r + 1] = "Q: " .. names(qtd)
r[#r + 1] = "R: " .. names(rtd)
local ftd = sdk.find_type_definition("via.physics.FilterInfo")
if ftd then r[#r + 1] = "F: " .. names(ftd) end
local std = sdk.find_type_definition("via.physics.System")
r[#r + 1] = "S: " .. names(std, "[Cc]ast")
local ok, err = pcall(function()
  local q = sdk.create_instance("via.physics.CastRayQuery"):add_ref()
  local res = sdk.create_instance("via.physics.CastRayResult"):add_ref()
  q:call("setRay(via.vec3, via.vec3)", s, e)
  pcall(q.call, q, "clearOptions"); pcall(q.call, q, "enableAllHits"); pcall(q.call, q, "enableNearSort")
  local fi = q:call("get_FilterInfo")
  r[#r + 1] = "filter default: layer " .. tostring(fi:call("get_Layer")) .. " mask " .. tostring(fi:call("get_MaskBits")) .. " group " .. tostring(fi:call("get_Group"))
  local function cast(label)
    sdk.call_native_func(sdk.get_native_singleton("via.physics.System"), std, "castRay(via.physics.CastRayQuery, via.physics.CastRayResult)", q, res)
    local n = res:call("get_NumContactPoints")
    local out = label .. " hits " .. tostring(n)
    for i = 0, math.min((n or 0) - 1, 4) do
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
  end
  cast("default")
  pcall(function() fi:call("set_MaskBits", 0xFFFFFFFF); q:call("set_FilterInfo", fi) end)
  cast("mask all")
end)
if not ok then r[#r + 1] = "ERR " .. tostring(err) end
local cm = sdk.get_managed_singleton("app.CameraManager"); local ch = cm:call("getMainCameraController", 0):call("get_TargetCharacter")
local q2 = ch:call("get_Transform"):call("get_Position")
r[#r + 1] = string.format("target char %s at %.2f m from camera", tostring(ch:get_GameObject():call("get_Name")), math.sqrt((q2.x - p.x) ^ 2 + (q2.y - p.y) ^ 2 + (q2.z - p.z) ^ 2))
return table.concat(r, " | ")
