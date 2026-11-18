-- Read-only: how the camera switches control type, and what the GUI has for the aim reticle.
local out = {}
local function dump(name, pats, depthmax)
  local td = sdk.find_type_definition(name)
  if not td then out[name] = "no type"; return end
  local l, seen, t, depth = {}, {}, td, 0
  local function hit(n) for _, p in ipairs(pats) do if n:find(p) then return true end end return false end
  while t and depth < (depthmax or 3) do
    for _, f in ipairs(t:get_fields()) do
      local n = f:get_name()
      if hit(n) and not seen["F" .. n] then seen["F" .. n] = true; l[#l + 1] = "F " .. n .. " : " .. f:get_type():get_full_name() end
    end
    for _, m in ipairs(t:get_methods()) do
      local n = m:get_name()
      if hit(n) then
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
dump("app.MainCameraController", { "[Ss]witch", "[Rr]equest", "[Cc]hange", "ControlType", "Target", "UserInput", "Next" }, 1)
dump("app.CameraManager", { "[Ss]witch", "[Rr]equest", "[Cc]hange", "ControlType", "Target", "Player" }, 1)
dump("app.Player", { "Camera", "Reticle", "Gui", "GUI" }, 1)
dump("app.PlayerInputProcessor", { "Camera", "Reticle" }, 1)
dump("app.Job02InputProcessor", { "Camera", "Reticle" }, 2)
dump("app.Human", { "Camera", "Reticle" }, 1)
dump("app.HumanActionSelector", { "Camera" }, 1)
dump("app.GuiManager", { "Reticle", "Aim", "Sight", "Cursor", "PlChara", "PlHuman", "Player" }, 1)
dump("app.AimCameraController", { "." }, 1)
local live = {}
pcall(function()
  local cm = sdk.get_managed_singleton("app.CameraManager")
  local mcc = cm:call("getMainCameraController", 0)
  local d = mcc:get_field("<CameraControllers>k__BackingField")
  local l = {}
  for _, e in ipairs(d:get_field("_entries"):get_elements()) do
    local k, v = e:get_field("key"), e:get_field("value")
    if v then l[#l + 1] = tostring(k) .. " = " .. v:get_type_definition():get_full_name() end
  end
  live.controllers = l
  local th = mcc:get_field("<TargetHuman>k__BackingField")
  local ui = mcc:get_field("<UserInput>k__BackingField")
  local ar = sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer")
  local pw = sdk.get_managed_singleton("app.PawnManager"):call("get_PawnCharacterList")
  live.target_is_arisen_human = th and ar and th:get_address() == ar:call("get_Human"):get_address()
  live.input_is_arisen = ui and ar and ui:get_address() == ar:call("get_Input"):get_address()
  local n = pw:call("get_Count")
  for i = 0, n - 1 do
    local p = pw[i]
    if p then
      live["target_is_pawn" .. i] = th and th:get_address() == p:call("get_Human"):get_address()
      live["input_is_pawn" .. i] = ui and ui:get_address() == p:call("get_Input"):get_address()
      live["pawn" .. i] = tostring(p:get_GameObject():call("get_Name"))
    end
  end
  local tg = mcc:call("get_TargetObject")
  live.target_obj = tg and tostring(tg:call("get_Name"))
end)
json.dump_file("DPC_probe_aim_2.json", { types = out, live = live })
return "ok " .. tostring(live.target_obj)
