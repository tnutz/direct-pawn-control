local out = {}
local pm = sdk.get_managed_singleton("app.PawnManager")
local l = pm:call("get_PawnCharacterList")
local ar = l:call("get_Item", 0)
local ap = ar:call("get_GameObject"):call("get_Transform"):call("get_Position")
for i = 0, l:call("get_Count") - 1 do
  local ch = l:call("get_Item", i)
  local lt = ch:call("get_LockOnTarget")
  local s = tostring(ch:call("get_GameObject"):call("get_Name")) .. " count=" .. tostring(lt:call("getWorkCount"))
  local ok1, w1 = pcall(lt.call, lt, "getNearestWork(via.vec3)", Vector3f.new(ap.x, ap.y, ap.z)); s = s .. " nearest=" .. tostring(ok1 and w1)
  local ok2, w2 = pcall(lt.call, lt, "getNearestWorkOnlyShootWithoutAim()"); s = s .. " nearestNoAim=" .. tostring(ok2 and w2)
  local ok3, w3 = pcall(function() return lt:call("get_Works"):call("get_Item", 0) end); s = s .. " works0=" .. tostring(ok3 and w3)
  local ok4, w4 = pcall(lt.call, lt, "getWork(System.Int32, System.Boolean)", 0, false); s = s .. " getWork0=" .. tostring(ok4 and w4)
  s = s .. " usePoint=" .. tostring(lt:call("get_UsePointData")) .. " disable=" .. tostring(lt:get_field("DisableControl"))
  out[#out+1] = s
end
return table.concat(out, "\n")
