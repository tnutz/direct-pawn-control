-- Bridge prototype of DPC v0.8.2's lock swap: during the Arisen's PlayerInputProcessor.update, lock his
-- LockOnController onto the nearest enemy (<30 m); if a pawn is possessed (controller shared, Chara = pawn),
-- swap Chara to the Arisen and restore Chara + the previous target in the post-hook.
_G.LS = _G.LS or {}
local LS = _G.LS
LS.on = true; LS.sets = 0; LS.restores = 0; LS.errs = 0; LS.err = nil; LS.next = 0
LS.SET = "setTarget(app.LockOnTargetWork, System.Boolean, System.Boolean)"
LS.REM = "removeTarget(app.LockOnTargetWork)"
LS.scan = function()
  local cm = sdk.get_managed_singleton("app.CharacterManager")
  local ar = cm:get_ManualPlayer()
  LS.ar = ar
  LS.pip = ar:call("get_InputProcessor"):get_address()
  LS.lk = ar:get_GameObject():call("getComponent(System.Type)", sdk.typeof("app.Player")):call("get_LockOnCtrl")
  local ap = ar:get_Transform():get_Position()
  local arr = sdk.get_managed_singleton("app.EnemyManager"):call("getAllEnemies")
  local best, bd
  for i = 0, arr:call("get_Count") - 1 do
    local it = arr[i]; local e = it and it:get_field("_Chara")
    if e and not e:call("get_IsDead") then
      local p = e:get_Transform():get_Position()
      local d = math.sqrt((p.x-ap.x)^2+(p.z-ap.z)^2)
      if d < 30 and (not bd or d < bd) then best, bd = e, d end
    end
  end
  LS.work = best and best:call("get_LockOnTarget"):call("get_work") or nil
  LS.tgt = best and best:call("get_CharaIDString") or "-"
end
if not LS.cb then
  LS.cb = true
  re.on_pre_application_entry("UpdateBehavior", function()
    local LS = _G.LS
    if not LS.on or os.clock() < LS.next then return end
    LS.next = os.clock() + 0.3
    local ok, err = pcall(LS.scan)
    if not ok then LS.errs = LS.errs + 1; LS.err = "scan " .. tostring(err) end
  end)
  local m = sdk.find_type_definition("app.PlayerInputProcessor"):get_method("update")
  sdk.hook(m, function(args)
    local LS = _G.LS
    if not (LS.on and LS.work and LS.lk and LS.pip) then return end
    if sdk.to_int64(args[2]) ~= LS.pip then return end
    local ok, err = pcall(function()
      local ch = LS.lk:get_field("Chara")
      LS.shared = ch ~= nil and ch:get_address() ~= LS.ar:get_address()
      if LS.shared then
        LS.saved_chara = ch
        LS.saved_tgt = LS.lk:call("get_Target")
        LS.lk:set_field("Chara", LS.ar)
      end
      LS.lk:call(LS.SET, LS.work, false, false)
      LS.swapped = true
      LS.sets = LS.sets + 1
    end)
    if not ok then LS.errs = LS.errs + 1; LS.err = tostring(err) end
  end, function(r)
    local LS = _G.LS
    if LS.swapped then
      LS.swapped = false
      if LS.shared then
        pcall(function()
          LS.lk:call(LS.REM, LS.work)
          if LS.saved_tgt then LS.lk:call(LS.SET, LS.saved_tgt, false, false) end
        end)
        pcall(function() LS.lk:set_field("Chara", LS.saved_chara) end)
        LS.restores = LS.restores + 1
      end
    end
    return r
  end)
end
return { "lock swap prototype on" }
