-- Read-only: (a) who could compute the aim point (methods with Ray / Target / Aim / calc on the input processor types
-- and app.CollisionSystem), (b) retry the centre-line ray over layers, only meaningful when the camera is on the pawn.
local out = { types = {}, ray = {} }
local function dump(name, pats)
  local td = sdk.find_type_definition(name)
  if not td then out.types[name] = "no type"; return end
  local l = {}
  for _, f in ipairs(td:get_fields()) do
    local n = f:get_name()
    for _, p in ipairs(pats) do if n:find(p) then l[#l + 1] = "F " .. n .. " : " .. f:get_type():get_full_name(); break end end
  end
  for _, m in ipairs(td:get_methods()) do
    local n = m:get_name()
    for _, p in ipairs(pats) do
      if n:find(p) then
        local ps = {}
        for _, pt in ipairs(m:get_param_types()) do ps[#ps + 1] = pt:get_full_name() end
        l[#l + 1] = "M " .. (m:is_static() and "static " or "") .. n .. "(" .. table.concat(ps, ", ") .. ") -> " .. m:get_return_type():get_full_name()
        break
      end
    end
  end
  out.types[name] = l
end
local P = { "[Rr]ay", "Target", "[Aa]im", "[Cc]alc", "[Ss]hoot", "[Cc]ast", "Layer", "Filter" }
for _, n in ipairs({ "app.Job02InputProcessor", "app.PlayerInputProcessorDetail", "app.PlayerInputProcessor", "app.CollisionSystem", "app.CollisionSystem.AsyncCastRay", "app.PlayerAimPathDrawer", "app.CollisionDefine", "app.CollisionDefine.Layer", "app.PawnRayController", "app.AimCameraController" }) do dump(n, P) end
local tr = sdk.get_primary_camera():call("get_GameObject"):call("get_Transform")
local p, z = tr:call("get_Position"), tr:call("get_WorldMatrix")[2]
local cm = sdk.get_managed_singleton("app.CameraManager"); local ch = cm:call("getMainCameraController", 0):call("get_TargetCharacter")
local q2 = ch:call("get_Transform"):call("get_Position")
out.char_dist = math.sqrt((q2.x - p.x) ^ 2 + (q2.y - p.y) ^ 2 + (q2.z - p.z) ^ 2)
local std = sdk.find_type_definition("via.physics.System"); local sys = sdk.get_native_singleton("via.physics.System")
local ok, err = pcall(function()
  local q = sdk.create_instance("via.physics.CastRayQuery"):add_ref()
  q:call("setRay(via.vec3, via.vec3)", Vector3f.new(p.x, p.y, p.z), Vector3f.new(p.x - z.x * 150.0, p.y - z.y * 150.0, p.z - z.z * 150.0))
  q:call("clearOptions"); q:call("enableAllHits"); q:call("enableNearSort")
  for layer = 0, 63 do
    local fi = q:call("get_FilterInfo")
    fi:call("set_Layer", layer); fi:call("set_MaskBits", 0xFFFFFFFF)
    q:call("set_FilterInfo", fi)
    local res = sdk.call_native_func(sys, std, "castRay(via.physics.CastRayQuery)", q)
    local n = res and res:call("get_NumContactPoints") or -1
    if n > 0 then
      local s = "hits " .. n
      for i = 0, math.min(n - 1, 2) do pcall(function()
        local pos = res:call("getContactPoint(System.UInt32)", i):get_field("Position")
        local nm = "?"; pcall(function() nm = tostring(res:call("getContactCollidable(System.UInt32)", i):call("get_GameObject"):call("get_Name")) end)
        s = s .. string.format(" [%.2fm %s]", math.sqrt((pos.x - p.x) ^ 2 + (pos.y - p.y) ^ 2 + (pos.z - p.z) ^ 2), nm)
      end) end
      out.ray["L" .. layer] = s
    end
  end
  local fi = q:call("get_FilterInfo"); out.ray.check = "layer now " .. tostring(fi:call("get_Layer")) .. " mask " .. tostring(fi:call("get_MaskBits"))
end)
out.err = not ok and tostring(err) or nil
json.dump_file("DPC_probe_ray_3.json", out)
local n = 0; for _ in pairs(out.ray) do n = n + 1 end
return string.format("char %.1f m from camera | ray entries %d | %s", out.char_dist, n, tostring(out.err))
