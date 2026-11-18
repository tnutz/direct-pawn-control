-- Read-only: which methods / fields mention Aim on the camera and player-side types, and the live state now.
local out = {}
local function dump(name, pat)
  local td = sdk.find_type_definition(name)
  if not td then out[name] = "no type"; return end
  local l = {}
  local seen = {}
  local t = td
  local depth = 0
  while t and depth < 3 do
    for _, f in ipairs(t:get_fields()) do
      local n = f:get_name()
      if n:find(pat) and not seen["F" .. n] then seen["F" .. n] = true; l[#l + 1] = "F " .. n .. " : " .. f:get_type():get_full_name() end
    end
    for _, m in ipairs(t:get_methods()) do
      local n = m:get_name()
      if n:find(pat) then
        local ps = {}
        for _, pt in ipairs(m:get_param_types()) do ps[#ps + 1] = pt:get_full_name() end
        local s = "M " .. n .. "(" .. table.concat(ps, ", ") .. ")"
        if not seen[s] then seen[s] = true; l[#l + 1] = s end
      end
    end
    t = t:get_parent_type(); depth = depth + 1
  end
  out[name] = l
end
for _, n in ipairs({ "app.CameraManager", "app.MainCameraController", "app.AimCameraController", "app.Player", "app.Job02InputProcessor", "app.PlayerInputProcessor", "app.PlayerInputProcessorDetail", "app.Human", "app.HumanActionSelector", "app.GUIManager", "app.Job02ShotController", "app.PlayerCameraController" }) do
  dump(n, "[Aa]im")
end
dump("app.MainCameraController", "[Cc]ontroller")
local live = {}
pcall(function()
  local cm = sdk.get_managed_singleton("app.CameraManager")
  local mcc = cm:call("getMainCameraController", 0)
  live.mcc = mcc and mcc:get_type_definition():get_full_name()
  for _, f in ipairs(mcc:get_type_definition():get_fields()) do
    local ok, v = pcall(mcc.get_field, mcc, f:get_name())
    local s = tostring(v)
    if ok and type(v) == "userdata" then pcall(function() s = v:get_type_definition():get_full_name() end) end
    live["mcc." .. f:get_name()] = s
  end
end)
json.dump_file("DPC_probe_aim_1.json", { types = out, live = live })
local n = 0; for _ in pairs(out) do n = n + 1 end
return "types " .. n .. " mcc " .. tostring(live.mcc)
