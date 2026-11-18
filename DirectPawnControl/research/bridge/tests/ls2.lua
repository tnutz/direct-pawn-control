-- Variant: do the lock swap around app.Player.update (where the game's own lock-on update runs), not the
-- processor update. Restores in the post-hook.
local LS = _G.LS
LS.on_pip = false        -- disable the processor-window variant
LS.on = true             -- keep scanning
LS.p_sets, LS.p_restores, LS.p_errs = 0, 0, 0
if not LS.p_hooked then
  LS.p_hooked = true
  local m = sdk.find_type_definition("app.Player"):get_method("update")
  sdk.hook(m, function(args)
    local LS = _G.LS
    if not (LS.on_player and LS.work and LS.lk) then return end
    local ok, err = pcall(function()
      local ch = LS.lk:get_field("Chara")
      LS.p_shared = ch ~= nil and ch:get_address() ~= LS.ar:get_address()
      if LS.p_shared then
        LS.p_saved_chara = ch
        LS.p_saved_tgt = LS.lk:call("get_Target")
        LS.lk:set_field("Chara", LS.ar)
      end
      LS.lk:call(LS.SET, LS.work, false, false)
      LS.p_swapped = true
      LS.p_sets = LS.p_sets + 1
    end)
    if not ok then LS.p_errs = LS.p_errs + 1; LS.err = tostring(err) end
  end, function(r)
    local LS = _G.LS
    if LS.p_swapped then
      LS.p_swapped = false
      if LS.p_shared then
        pcall(function()
          LS.lk:call(LS.REM, LS.work)
          if LS.p_saved_tgt then LS.lk:call(LS.SET, LS.p_saved_tgt, false, false) end
        end)
        pcall(function() LS.lk:set_field("Chara", LS.p_saved_chara) end)
        LS.p_restores = LS.p_restores + 1
      end
    end
    return r
  end)
end
LS.on_player = true
return { "player-update lock swap on" }
