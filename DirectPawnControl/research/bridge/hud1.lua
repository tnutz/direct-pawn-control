local out = {}
local D = _G.DPC_dbg
out[#out+1] = "active " .. tostring(D.state.active) .. " pawn " .. tostring(D.state.pawn_name)
local sm = sdk.get_native_singleton("via.SceneManager")
local scene = sdk.call_native_func(sm, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
for _, tn in ipairs({ "app.ui020901", "app.ui020401", "app.ui020301", "app.ui010201" }) do
  local arr = scene:call("findComponents(System.Type)", sdk.typeof(tn))
  local n = arr and arr:call("get_Count")
  local a0 = nil; local how = {}
  local ok0, v0 = pcall(function() return arr[0] end); how[#how+1] = "arr[0]=" .. tostring(ok0 and v0 ~= nil)
  local ok1, v1 = pcall(function() return arr:get_element(0) end); how[#how+1] = "get_element=" .. tostring(ok1 and v1 ~= nil)
  local ok2, v2 = pcall(function() return arr:call("get_Item", 0) end); how[#how+1] = "get_Item=" .. tostring(ok2 and v2 ~= nil)
  local ok3, v3 = pcall(function() return arr:get_elements()[1] end); how[#how+1] = "elements[1]=" .. tostring(ok3 and v3 ~= nil)
  local w = (ok0 and v0) or (ok1 and v1) or (ok2 and v2) or (ok3 and v3)
  local c = w and w:get_field("PlChara")
  out[#out+1] = tn .. " n=" .. tostring(n) .. " " .. table.concat(how, ",") .. " PlChara=" .. tostring(c and c:call("get_CharaIDString"))
end
return table.concat(out, " | ")
