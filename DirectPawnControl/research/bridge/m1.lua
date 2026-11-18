-- Movement-injection experiment: force a stick direction through different write paths and record displacement.
local A = _G.AB
local N = A.N4
local MV = {}
_G.MV = MV
MV.res = {}
local modes = {
  { name = "setAxisL@pip", f = function(inp, ax, ay) inp:call("setAxisL(System.Single, System.Single)", ax, ay); inp:call("set_AxisMagnitudeL(System.Single)", 1.0) end },
  { name = "_AxisL@pip", f = function(inp, ax, ay) inp:set_field("_AxisL", Vector2f.new(ax, ay)); inp:set_field("<AxisMagnitudeL>k__BackingField", 1.0); inp:set_field("<AnalogL>k__BackingField", 1.0) end },
  { name = "autopad+_AxisL@pip", auto = true, f = function(inp, ax, ay) inp:set_field("_AxisL", Vector2f.new(ax, ay)); inp:set_field("<AxisMagnitudeL>k__BackingField", 1.0); inp:set_field("<AnalogL>k__BackingField", 1.0) end },
  { name = "kbAxisL@pip", f = function(inp, ax, ay) inp:set_field("KeyboardMouseAxisL", Vector2f.new(ax, ay)); inp:set_field("KeyboardMouseAnalogL", 1.0) end },
}
MV.i = 0; MV.t0 = os.clock(); MV.on = true
local function arpos()
  local p = sdk.get_managed_singleton("app.CharacterManager"):get_ManualPlayer():get_Transform():get_Position()
  return p.x, p.z
end
MV.start = { arpos() }
local saved_enabled = A.native4
A.native4 = false -- brain writer off during the experiment
if not MV.hooked then
  local m = sdk.find_type_definition("app.PlayerInputProcessor"):get_method("update")
  sdk.hook(m, function(args)
    local MV = _G.MV
    if not (MV and MV.on) then return end
    if sdk.to_int64(args[2]) ~= _G.AB.ar_pip_addr then return end
    local mode = MV.cur
    if not mode then return end
    pcall(function()
      local inp = sdk.get_managed_singleton("app.CharacterManager"):get_ManualPlayer():call("get_Input")
      local ax, ay = _G.AB.N4.stick_for(MV.yaw)
      mode.f(inp, ax, ay)
      MV.writes = (MV.writes or 0) + 1
    end)
  end, function(r) return r end)
  MV.hooked = true
end
re.on_pre_application_entry("UpdateBehavior", function()
  local MV = _G.MV
  if not MV.on then return end
  local now = os.clock() - MV.t0
  local slot = math.floor(now / 2.0) + 1 -- 2 s per mode
  local x, z = arpos()
  if slot ~= MV.i then
    if MV.i >= 1 and MV.i <= #modes then
      local s = MV.slotstart
      MV.res[#MV.res+1] = { mode = modes[MV.i].name, moved = math.floor(math.sqrt((x-s[1])^2 + (z-s[2])^2) * 100) / 100, writes = MV.writes }
    end
    MV.i = slot; MV.slotstart = { x, z }; MV.writes = 0
    if slot > #modes then
      MV.on = false; MV.cur = nil
      pcall(function() sdk.get_managed_singleton("app.CharacterManager"):get_ManualPlayer():call("get_Input"):set_field("<IsAutoPad>k__BackingField", false) end)
      json.dump_file("agent_bridge/mv.json", MV.res)
      return
    end
    MV.cur = modes[slot]
    MV.yaw = (slot % 2 == 0) and 0 or math.pi -- alternate direction so we don't wander off
  end
  pcall(function()
    sdk.get_managed_singleton("app.CharacterManager"):get_ManualPlayer():call("get_Input"):set_field("<IsAutoPad>k__BackingField", MV.cur.auto and true or false)
  end)
end)
return { "movement experiment " .. #modes .. " modes x 2 s" }
