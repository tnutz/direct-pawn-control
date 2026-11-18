-- Read-only: result-pool counters around both castRay forms, and the pick rule for the aim point.
local r = {}
local std = sdk.find_type_definition("via.physics.System"); local sys = sdk.get_native_singleton("via.physics.System")
local function cnt() return tostring(sdk.call_native_func(sys, std, "get_NumUsedCastRayResults")) .. "/" .. tostring(sdk.call_native_func(sys, std, "get_NumCacheCastRayResults")) .. "/" .. tostring(sdk.call_native_func(sys, std, "get_MaxCacheCastRayResult")) end
r[#r + 1] = "pool used/cache/max before " .. cnt()
local tr = sdk.get_primary_camera():call("get_GameObject"):call("get_Transform")
local p, z = tr:call("get_Position"), tr:call("get_WorldMatrix")[2]
local q = sdk.create_instance("via.physics.CastRayQuery"):add_ref()
q:call("setRay(via.vec3, via.vec3)", Vector3f.new(p.x, p.y, p.z), Vector3f.new(p.x - z.x * 150.0, p.y - z.y * 150.0, p.z - z.z * 150.0))
q:call("clearOptions"); q:call("enableAllHits"); q:call("enableNearSort")
for i = 1, 5 do sdk.call_native_func(sys, std, "castRay(via.physics.CastRayQuery)", q) end
r[#r + 1] = "after 5 x castRay(q) " .. cnt()
local ok, err = pcall(function()
  local scene = sdk.call_native_func(sdk.get_native_singleton("via.SceneManager"), sdk.find_type_definition("via.SceneManager"), "get_CurrentScene()")
  local res = sdk.create_instance("via.physics.CastRayResult"):add_ref()
  for i = 1, 5 do sdk.call_native_func(sys, std, "castRay(via.Scene, via.physics.CastRayQuery, via.physics.CastRayResult)", scene, q, res) end
  r[#r + 1] = "after 5 x castRay(scene,q,res) " .. cnt() .. " hits " .. tostring(res:call("get_NumContactPoints"))
  local n = res:call("get_NumContactPoints")
  local pick
  for i = 0, n - 1 do
    local c = res:call("getContactCollidable(System.UInt32)", i)
    local go = c:call("get_GameObject")
    local layer = c:call("get_FilterInfo"):call("get_Layer")
    local tag = tostring(go:call("get_Tag") or "")
    local folder = go:call("get_Folder"); folder = folder and tostring(folder:call("get_Name")) or ""
    local pos = res:call("getContactPoint(System.UInt32)", i):get_field("Position")
    local d = math.sqrt((pos.x - p.x) ^ 2 + (pos.y - p.y) ^ 2 + (pos.z - p.z) ^ 2)
    local solid = (layer == 1 or layer == 22) or (tag:find("Character", 1, true) and folder ~= "Player" and folder ~= "Pawn")
    if solid and d > 1.0 then pick = string.format("%.2f m %s L%d folder=%s tag=%s (hit #%d)", d, tostring(go:call("get_Name")), layer, folder, tag, i); break end
  end
  r[#r + 1] = "pick: " .. tostring(pick)
  res:call("clear")
  r[#r + 1] = "after clear " .. cnt()
end)
if not ok then r[#r + 1] = "ERR " .. tostring(err) end
return table.concat(r, " | ")
