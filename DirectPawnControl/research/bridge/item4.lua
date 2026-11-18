-- logs how the game writes the quick-item cross's labels (KeyItem.setMessage) and when the pickers / counts run.
-- Hooks only record; they change nothing. They stay until Reset Scripts.
if _G.DPC_item4 then return "already installed" end
local P = { log = {}, n = 0 }
_G.DPC_item4 = P
local function add(s) P.n = P.n + 1; if #P.log < 60 then P.log[#P.log + 1] = string.format("%.2f %s", os.clock(), s) end end
local kt = sdk.find_type_definition("app.ui020401.KeyItem")
local function shift() local ok, v = pcall(function() return sdk.get_managed_singleton("app.GuiManager"):get_field("CrossGuide"):get_field("IsShift") end); return ok and tostring(v) or "?" end
sdk.hook(kt:get_method("setMessage(System.String, System.Boolean)"), function(args)
  pcall(function()
    local k = sdk.to_managed_object(args[2])
    local s = sdk.to_managed_object(args[3])
    add(string.format("setMessage(str) key action %s '%s' bool %s shift %s disp %s x%s", tostring(k:get_field("Action")), s and s:call("ToString") or "nil", tostring(sdk.to_int64(args[4]) & 1), shift(), tostring(k:get_field("DispItemId")), tostring(k:get_field("DispItemNum"))))
  end)
end, function(r) return r end)
sdk.hook(kt:get_method("setMessage(System.Guid, System.Boolean)"), function(args)
  pcall(function()
    local k = sdk.to_managed_object(args[2])
    add(string.format("setMessage(guid) key action %s bool %s shift %s", tostring(k:get_field("Action")), tostring(sdk.to_int64(args[4]) & 1), shift()))
  end)
end, function(r) return r end)
sdk.hook(kt:get_method("updateMessage"), function(args) pcall(function() local k = sdk.to_managed_object(args[2]); add("updateMessage key action " .. tostring(k:get_field("Action"))) end) end, function(r) return r end)
return "installed"
