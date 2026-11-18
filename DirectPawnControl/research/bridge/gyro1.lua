-- Read-only: where does the game read the controller's gyro for aiming?
local out = {}
local function dump(name, depth)
  local t, d, l = sdk.find_type_definition(name), 0, {}
  if not t then out[name] = "no type"; return end
  while t and d < (depth or 3) do
    for _, f in ipairs(t:get_fields()) do
      local n = f:get_name()
      if n:find("[Gg]yro") or n:find("[Mm]otion[Ss]ensor") or n:find("[Ss]ensor") then l[#l + 1] = "F " .. (f:is_static() and "static " or "") .. n .. " : " .. f:get_type():get_full_name() end
    end
    for _, m in ipairs(t:get_methods()) do
      local n = m:get_name()
      if n:find("[Gg]yro") or n:find("[Mm]otion[Ss]ensor") then
        local ps = {}
        for _, pt in ipairs(m:get_param_types()) do ps[#ps + 1] = pt:get_full_name() end
        l[#l + 1] = "M " .. (m:is_static() and "static " or "") .. n .. "(" .. table.concat(ps, ", ") .. ") -> " .. m:get_return_type():get_full_name()
      end
    end
    t = t:get_parent_type(); d = d + 1
  end
  out[name] = l
end
for _, n in ipairs({ "app.Player", "app.CameraManager", "app.MainCameraController", "app.AimCameraController", "app.RotateCameraControllerBase", "app.CameraControllerBase", "app.UserInputManager", "app.UserInput", "app.PlayerInputProcessor", "app.PlayerInputProcessorDetail", "app.CharacterInput", "app.OptionManager", "app.UserPadManager", "app.PadManager", "via.hid.GamePadDevice", "via.hid.GamePad", "app.AimCameraSetting", "app.AimCameraSetting.AimSetting", "app.CameraCommonSettings" }) do dump(n) end
local live = {}
pcall(function()
  local ar = sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer")
  local pl = ar:get_GameObject():call("getComponent(System.Type)", sdk.typeof("app.Player"))
  live.GyroSensorDisableTimer = pl:get_field("GyroSensorDisableTimer")
end)
out.live = live
json.dump_file("DPC_probe_gyro_1.json", out)
return "ok"
