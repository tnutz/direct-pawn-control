-- Native-input Arisen brain (archer): decisions in pre-UpdateBehavior, synthetic stick + buttons written into the
-- Arisen's CharacterInput in the pre-hook of his own PlayerInputProcessor.update (REPLACES hardware input).
local A = _G.AB
local C = A.cfg
C.keep_min = 7; C.keep_max = 20; C.engage_r = 32; C.shot_cd = 0.9; C.hold = 0.12
C.face_tol = 5; C.turn_mag = C.turn_mag or 0.15
C.replace = true
A.native = false
A.native3 = false
A.N4 = A.N4 or {}
local N = A.N4
N.want, N.ax, N.ay, N.mag = 0, 0, 0, 0
N.hits, N.inj, N.err, N.ticks = 0, 0, nil, 0
local act = A.ACT
local function bit(n) local v = act[n]; return v and (1 << v) or 0 end
local cam_m = sdk.find_type_definition("app.PlayerInputProcessorDetail"):get_method("getCameraAngleRad")
local function cam_yaw()
  local ok, r = pcall(cam_m.call, cam_m, nil)
  if ok and type(r) == "number" then return r end
  return 0
end
-- world yaw (rad, atan(dx,dz)) -> stick (ax, ay) relative to the camera
local function stick_for(yaw)
  local s = yaw - cam_yaw()
  return -math.sin(s), math.cos(s)
end
N.stick_for = stick_for
local function pos(ch) local p = ch:get_Transform():get_Position(); return p.x, p.y, p.z end
local function facing(ch)
  local f = ch:get_Transform():get_Rotation() * Vector3f.new(0, 0, 1)
  return math.atan(f.x, f.z)
end
local function angdiff(a, b) local d = (a - b + math.pi) % (2 * math.pi) - math.pi; return d end

A.tick = function()
  local now = os.clock()
  local ar = sdk.get_managed_singleton("app.CharacterManager"):get_ManualPlayer()
  if not ar then return end
  N.ticks = N.ticks + 1
  A.ar_pip = ar:call("get_InputProcessor")
  A.ar_pip_addr = A.ar_pip and A.ar_pip:get_address() or 0
  if now >= A.next_scan then A.next_scan = now + 0.3; A.target = A.pick(ar) end
  local t = A.target
  local want, ax, ay, mag = 0, 0.0, 0.0, 0.0
  if not t then
    A.state = "idle"
  else
    local x, _, z = pos(ar)
    local tx, _, tz = pos(t)
    local dx, dz = tx - x, tz - z
    local d = math.sqrt(dx * dx + dz * dz)
    local yaw = math.atan(dx, dz)
    A.dist = d
    N.off = math.deg(angdiff(yaw, facing(ar)))
    if d > C.keep_max then
      A.state = "approach"; ax, ay = stick_for(yaw); mag = 1.0
    elseif d < C.keep_min then
      A.state = "backoff"; ax, ay = stick_for(yaw + math.pi); mag = 1.0
    else
      A.state = "engage"
      pcall(A.set_aim, ar, t)
      ar:call("set_TargetFrontAngleDeg(System.Single)", math.deg(yaw))
      if math.abs(N.off) > C.face_tol and not N.shooting then
        -- nudge the stick toward the target (walk-turn) until facing it
        A.state = "turn"; ax, ay = stick_for(yaw); mag = C.turn_mag
      elseif (now % C.shot_cd) < C.hold then
        want = want | bit("AttackS")
      end
    end
  end
  N.want, N.ax, N.ay, N.mag = want, (ax * mag) + 0.0, (ay * mag) + 0.0, mag + 0.0
end

if not A.n4_hooked then
  A.n4_hooked = true
  local m = sdk.find_type_definition("app.PlayerInputProcessor"):get_method("update")
  sdk.hook(m, function(args)
    local A = _G.AB
    if not (A.enabled and A.native4) then return end
    if sdk.to_int64(args[2]) ~= A.ar_pip_addr then return end
    local N = A.N4
    N.hits = N.hits + 1
    local ok, err = pcall(function()
      local ar = sdk.get_managed_singleton("app.CharacterManager"):get_ManualPlayer()
      local inp = ar:call("get_Input")
      local want = N.want
      local prev = N.prev or 0
      local trg, rel = want & ~prev, prev & ~want
      N.prev = want
      if A.cfg.replace then
        inp:set_field("ButtonOnFlags", want)
        inp:set_field("ButtonTriggerFlags", trg)
        inp:set_field("ButtonReleaseFlags", rel)
        inp:call("setAxisL(System.Single, System.Single)", N.ax, N.ay)
        inp:call("set_AxisMagnitudeL(System.Single)", N.mag)
      end
      if trg ~= 0 then A.native_presses = (A.native_presses or 0) + 1 end
      N.inj = N.inj + 1
    end)
    if not ok then N.err = tostring(err) end
  end, function(r) return r end)
end
A.native4 = true
return { "n4 on" }
