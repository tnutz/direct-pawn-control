-- 60 s input-path probe while possessed: where does a mouse-click (AttackS bit) show up?
_G.IP = { t0 = os.clock(), dur = 60, A = 0, B = 0, Bt = 0, C = 0, Ct = 0, D = 0, frames = 0, samples = {}, done = false }
local AT = 2 -- 1 << AttackS(1)
local function ar_inp()
  local ar = sdk.get_managed_singleton("app.CharacterManager"):get_ManualPlayer()
  return ar and ar:call("get_Input")
end
local function pawn_inp()
  local cam = sdk.get_managed_singleton("app.CameraManager"):call("getMainCameraController", 0):call("get_TargetCharacter")
  return cam and cam:call("get_Input")
end
if not _G.IP_CB then
  _G.IP_CB = true
  re.on_pre_application_entry("UpdateBehavior", function() if _G.IP_A then _G.IP_A() end end)
  re.on_pre_application_entry("LateUpdateBehavior", function() if _G.IP_C then _G.IP_C() end end)
  sdk.hook(sdk.find_type_definition("app.Player"):get_method("update"),
    function(args) if _G.IP_B then _G.IP_B() end end,
    function(r) if _G.IP_D then _G.IP_D() end return r end)
end
local function live() local I = _G.IP; return I and not I.done and os.clock() - I.t0 < I.dur end
_G.IP_A = function()
  if not live() then
    local I = _G.IP
    if I and not I.done then I.done = true; json.dump_file("agent_bridge/ip.json", I) end
    return
  end
  pcall(function()
    local I = _G.IP; I.frames = I.frames + 1
    local on = ar_inp():get_field("ButtonOnFlags")
    if on & AT ~= 0 then I.A = I.A + 1 end
    if on ~= 0 and #I.samples < 40 then I.samples[#I.samples+1] = string.format("A %.2f on=%X", os.clock() - I.t0, on) end
  end)
end
_G.IP_B = function()
  if not live() then return end
  pcall(function()
    local I = _G.IP
    local inp = ar_inp()
    if inp:get_field("ButtonOnFlags") & AT ~= 0 then I.B = I.B + 1 end
    if inp:get_field("ButtonTriggerFlags") & AT ~= 0 then I.Bt = I.Bt + 1 end
  end)
end
_G.IP_D = function()
  if not live() then return end
  pcall(function()
    local I = _G.IP
    if ar_inp():get_field("ButtonOnFlags") & AT ~= 0 then I.D = I.D + 1 end
  end)
end
_G.IP_C = function()
  if not live() then return end
  pcall(function()
    local I = _G.IP
    local pin = pawn_inp()
    if pin:get_field("ButtonOnFlags") & AT ~= 0 then I.C = I.C + 1 end
    if pin:get_field("ButtonTriggerFlags") & AT ~= 0 then I.Ct = I.Ct + 1 end
  end)
end
return { "input probe running 60 s" }
