-- read-only: the raw return value of the two quick-item pickers (to learn how a Nullable<ItemIDEnum> comes back)
if not _G.DPC_item6 then
  local P = { hp = {}, st = {}, n = 0 }
  _G.DPC_item6 = P
  local t = sdk.find_type_definition("app.ItemShortcutParameter")
  sdk.hook(t:get_method("getRecoverHPItemID(System.Boolean, app.ItemShortcutSettingType)"), function(args) end, function(r) P.n = P.n + 1; pcall(function() P.hp[string.format("0x%X", sdk.to_int64(r))] = true end); return r end)
  sdk.hook(t:get_method("getRecoverStaminaItemID(app.ItemShortcutSettingType)"), function(args) end, function(r) pcall(function() P.st[string.format("0x%X", sdk.to_int64(r))] = true end); return r end)
  return "installed"
end
local P = _G.DPC_item6
local out = { "calls " .. P.n }
for k in pairs(P.hp) do out[#out+1] = "hp raw " .. k end
for k in pairs(P.st) do out[#out+1] = "stamina raw " .. k end
local D = _G.DPC_dbg
pcall(function()
  local st = D.state
  local ar = sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer")
  out[#out+1] = string.format("arisen_chara %X manual player %X pawn %X", st.arisen_chara and st.arisen_chara:get_address() or 0, ar and ar:get_address() or 0, st.pawn_chara and st.pawn_chara:get_address() or 0)
  local cg = sdk.get_managed_singleton("app.GuiManager"):get_field("CrossGuide")
  local kl = cg:get_field("KeyList")
  for i = 0, kl:call("get_Count") - 1 do local k = kl:call("get_Item", i); out[#out+1] = string.format("key %d action %s item %s x%s", i, tostring(k:get_field("Action")), tostring(k:get_field("DispItemId")), tostring(k:get_field("DispItemNum"))) end
end)
return table.concat(out, "\n")
