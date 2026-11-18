-- read-only: the game's display size, to tell which computer a browser belongs to
local out = {}
pcall(function() local s = imgui.get_display_size(); out[#out+1] = "imgui display " .. tostring(s.x) .. "x" .. tostring(s.y) end)
pcall(function()
  local sm = sdk.get_native_singleton("via.SceneManager")
  local v = sdk.call_native_func(sm, sdk.find_type_definition("via.SceneManager"), "get_MainView")
  local sz = v:call("get_WindowSize")
  out[#out+1] = "main view window " .. tostring(sz.w) .. "x" .. tostring(sz.h)
end)
return table.concat(out, "\n")
