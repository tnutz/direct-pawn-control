-- read-only: every distinct label the game writes on the quick-item cross, with the widget's state at that moment
if not _G.DPC_item7 then
  local P = { u = {}, order = {} }
  _G.DPC_item7 = P
  local kt = sdk.find_type_definition("app.ui020401.KeyItem")
  sdk.hook(kt:get_method("setMessage(System.String, System.Boolean)"), function(args)
    pcall(function()
      local k = sdk.to_managed_object(args[2])
      local s = sdk.to_managed_object(args[3])
      local cg = sdk.get_managed_singleton("app.GuiManager"):get_field("CrossGuide")
      local key = string.format("action %s '%s' bool %s | widget shift %s flow %s | key enable %s disp %s x%s shiftprev %s", tostring(k:get_field("Action")), s and s:call("ToString") or "nil",
        tostring(sdk.to_int64(args[4]) & 1), tostring(cg:get_field("IsShift")), tostring(cg:get_field("<FlowNow>k__BackingField")), tostring(k:get_field("IsEnable")), tostring(k:get_field("DispItemId")), tostring(k:get_field("DispItemNum")), tostring(k:get_field("IsShiftPrev")))
      if not P.u[key] then P.u[key] = 0; P.order[#P.order + 1] = key end
      P.u[key] = P.u[key] + 1
    end)
  end, function(r) return r end)
  return "installed"
end
local P = _G.DPC_item7
local out = {}
for _, k in ipairs(P.order) do out[#out+1] = P.u[k] .. "x  " .. k end
return table.concat(out, "\n")
