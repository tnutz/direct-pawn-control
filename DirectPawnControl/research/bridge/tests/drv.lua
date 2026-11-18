-- Stand-in: drive the Arisen's processor ourselves during possession (app.Player.update doesn't call it then)
local LS = _G.LS
LS.drv_cnt, LS.drv_err = 0, nil
if not LS.drv_hooked then
  LS.drv_hooked = true
  sdk.hook(sdk.find_type_definition("app.Player"):get_method("update"), function(args)
    local LS = _G.LS
    if not LS.drv_on then return end
    local ok, err = pcall(function()
      local ar = sdk.get_managed_singleton("app.CharacterManager"):get_ManualPlayer()
      ar:call("get_InputProcessor"):call("update")
    end)
    LS.drv_cnt = LS.drv_cnt + 1
    if not ok then LS.drv_err = tostring(err) end
  end, function(r) return r end)
end
LS.drv_on = true
return { "driving Arisen processor" }
