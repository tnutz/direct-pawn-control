-- Arisen combat brain prototype (bridge state). Hot-swappable: re-sending this file replaces AB.tick.
_G.AB = _G.AB or { enabled = false, next_scan = 0, log = {}, shots = 0, skills = 0, errs = 0 }
local AB = _G.AB
AB.cfg = AB.cfg or {}
local C = AB.cfg
C.engage_r = 32; C.keep_min = 7; C.keep_max = 20; C.attack = C.attack or false; C.skills = C.skills or false
C.shot_cd = 0.9; C.skill_cd = 6.0; C.block_pip = true; C.aim = true; C.aim_h = 1.0

local function pos(ch) local p = ch:get_Transform():get_Position(); return p.x, p.y, p.z end
local function alive(ch)
  local ok, d = pcall(function() return ch:call("get_IsDead") end)
  return ok and d == false
end
local function enemies()
  local list = {}
  local em = sdk.get_managed_singleton("app.EnemyManager")
  local arr = em and em:call("getAllEnemies")
  if not arr then return list end
  for i = 0, arr:call("get_Count") - 1 do
    local e = arr[i] and arr[i]:get_field("_Chara")
    if e and alive(e) then list[#list+1] = e end
  end
  return list
end
local function note(s)
  AB.log[#AB.log+1] = string.format("%.2f %s", os.clock(), s)
  if #AB.log > 60 then table.remove(AB.log, 1) end
end

AB.pick = function(ar)
  local ax, ay, az = pos(ar)
  -- sticky: keep the current target while it is alive and in range
  if AB.target and alive(AB.target) then
    local tx, ty, tz = pos(AB.target)
    if math.sqrt((tx-ax)^2 + (tz-az)^2) <= C.engage_r * 1.2 then return AB.target end
  end
  local best, bd = nil, nil
  for _, e in ipairs(enemies()) do
    local ex, ey, ez = pos(e)
    local d = math.sqrt((ex-ax)^2 + (ez-az)^2)
    if d <= C.engage_r and (not bd or d < bd) then best, bd = e, d end
  end
  if best and (not AB.target or best:get_address() ~= AB.target:get_address()) then note("target " .. best:get_CharaIDString() .. string.format(" %.1fm", bd)) end
  return best
end

local NV3 = sdk.find_type_definition("System.Nullable`1<via.vec3>")
AB.set_aim = function(ar, t)
  local tx, ty, tz = pos(t)
  local nv = ValueType.new(NV3)
  nv:set_field("_HasValue", true)
  nv:set_field("_Value", Vector3f.new(tx, ty + (C.aim_h or 1.0), tz))
  ar:call("set_AimTargetPosition(System.Nullable`1<via.vec3>)", nv)
  AB.aim_set = (AB.aim_set or 0) + 1
end

AB.tick = function()
  local now = os.clock()
  local ar = sdk.get_managed_singleton("app.CharacterManager"):get_ManualPlayer()
  if not ar then return end
  local sel = ar:call("get_HumanActionSelector")
  AB.ar_pip = ar:call("get_InputProcessor")
  AB.ar_pip_addr = AB.ar_pip and AB.ar_pip:get_address() or 0
  if now >= AB.next_scan then
    AB.next_scan = now + 0.3
    AB.target = AB.pick(ar)
  end
  local t = AB.target
  if not t then
    if AB.state ~= "idle" then
      AB.state = "idle"
      if sel:call("isEnableRequestIdle") then sel:call("requestIdleImpl(System.Boolean)", false) end
    end
    return
  end
  local ax, ay, az = pos(ar)
  local tx, ty, tz = pos(t)
  local dx, dz = tx - ax, tz - az
  local d = math.sqrt(dx*dx + dz*dz)
  local ang = math.deg(math.atan(dx, dz))
  AB.dist = d
  ar:call("set_TargetFrontAngleDeg(System.Single)", ang)
  if d > C.keep_max then
    AB.state = "approach"
    ar:call("set_TargetMoveAngleDeg(System.Single)", ang)
    sel:call("requestLocomotionImpl(app.LocomotionSpeedTypeEnum, System.Boolean)", 2, false)
  elseif d < C.keep_min then
    AB.state = "backoff"
    ar:call("set_TargetMoveAngleDeg(System.Single)", ang + 180)
    sel:call("requestLocomotionImpl(app.LocomotionSpeedTypeEnum, System.Boolean)", 2, false)
  else
    if AB.state == "approach" or AB.state == "backoff" then
      if sel:call("isEnableRequestIdle") then sel:call("requestIdleImpl(System.Boolean)", false) end
    end
    AB.state = "engage"
    if C.attack then
      if not ar:call("get_IsDrawedWeapon") then
        if now >= (AB.next_draw or 0) then AB.next_draw = now + 1.0; sel:call("requestDrawWeapon()"); note("draw") end
      elseif now >= (AB.next_shot or 0) then
        AB.next_shot = now + C.shot_cd
        if C.aim then pcall(AB.set_aim, ar, t) end
        sel:call("requestNormalAttack(app.LocomotionSpeedTypeEnum)", 0)
        AB.shots = AB.shots + 1
        AB.release_at = now + (C.release_delay or 0.15)
      end
      if AB.release_at and now >= AB.release_at then
        AB.release_at = nil
        if C.aim then pcall(AB.set_aim, ar, t) end
        local okS, r = pcall(sel.call, sel, "requestShoot()")
        AB.last_shoot_ret = tostring(okS and r)
      end
    end
  end
end

if not AB.cb then
  AB.cb = true
  -- block the Arisen's own player-input processing while the brain runs (as DPC does while possessing)
  sdk.hook(sdk.find_type_definition("app.PlayerInputProcessor"):get_method("update"), function(args)
    local A = _G.AB
    if A.enabled and A.cfg.block_pip and A.ar_pip_addr and A.ar_pip_addr ~= 0 and sdk.to_int64(args[2]) == A.ar_pip_addr then
      return sdk.PreHookResult.SKIP_ORIGINAL
    end
  end, function(r) return r end)
  re.on_pre_application_entry("UpdateBehavior", function()
    local A = _G.AB
    if not (A.enabled and A.tick) then return end
    local ok, err = pcall(A.tick)
    if not ok then
      A.errs = A.errs + 1
      A.last_err = tostring(err)
      if A.errs > 30 then A.enabled = false; note("disabled: " .. A.last_err) end
    end
    local now = os.clock()
    if now >= (A.next_dump or 0) then
      A.next_dump = now + 0.25
      pcall(function()
        local ar = sdk.get_managed_singleton("app.CharacterManager"):get_ManualPlayer()
        local fsm = ar:call("get_ActionManager"):get_field("Fsm")
        local thp = A.target and A.target:call("get_Hp")
        json.dump_file("agent_bridge/brain.json", {
          t = now, state = A.state, dist = A.dist, target = A.target and A.target:get_CharaIDString(), target_hp = thp,
          shots = A.shots, skills = A.skills, aim_set = A.aim_set, aim_now = (function() local ok, v = pcall(function() local n = ar:call("get_AimTargetPosition"); return n and n:get_field("_HasValue") and tostring(n:get_field("_Value")) end) return ok and v or nil end)(), errs = A.errs, last_err = A.last_err,
          L0 = fsm:call("getCurrentNodeName(System.UInt32)", 0), L1 = fsm:call("getCurrentNodeName(System.UInt32)", 1),
          drawn = ar:call("get_IsDrawedWeapon"), log = A.log,
        })
      end)
    end
  end)
end
AB.enabled = true
return { "brain tick installed; attack=" .. tostring(C.attack) .. " skills=" .. tostring(C.skills) }
