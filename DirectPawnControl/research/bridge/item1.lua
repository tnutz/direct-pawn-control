-- read-only: the game's quick-item lists, what the Arisen and the played pawn hold of each, and what the picker returns now
local out = {}
local D = _G.DPC_dbg
local st = D.state
local gm = sdk.get_managed_singleton("app.GuiManager")
local im = sdk.get_managed_singleton("app.ItemManager")
local cg = gm:get_field("CrossGuide")
local sp = cg and cg:get_field("ShortcutParam")
if not sp then return "no shortcut parameter" end
local nm = sdk.find_type_definition("app.GUIBase"):get_method("getItemName(System.Int32)")
local ar = sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer")
local function name(id) local ok, s = pcall(function() return nm:call(nil, id) end); return ok and tostring(s) or "?" end
local function have(id, ch) if not ch then return "-" end local ok, n = pcall(function() return im:call("getHaveNum(System.Int32, app.Character)", id, ch) end); return ok and tostring(n) or "?" end
out[#out+1] = "active " .. tostring(st.active) .. " pawn " .. tostring(st.pawn_name) .. " setting type " .. tostring(sp:get_field("CurrApplyShortcutSettingType")) .. " interval " .. tostring(sp:get_field("SecInterval"))
pcall(function() local pc = cg:get_field("PlChara"); out[#out+1] = "cross guide PlChara " .. tostring(pc and pc:call("get_GameObject"):call("get_Name")) .. " | arisen " .. tostring(ar:call("get_GameObject"):call("get_Name")) .. " | isItemDisable " .. tostring(cg:call("isItemDisable")) end)
for _, f in ipairs({ "RecoverHPItems", "RecoverStaminaItems", "RecoverMaxStaminaItems" }) do
  local a = sp:get_field(f)
  local p = {}
  if a then
    for i = 0, a:call("get_Length") - 1 do
      local e = a:call("Get", i); local id = e; pcall(function() id = e:get_field("value__") end)
      p[#p+1] = string.format("%s %s (arisen %s, pawn %s)", tostring(id), name(id), have(id, ar), have(id, st.pawn_chara))
    end
  end
  out[#out+1] = f .. ": " .. table.concat(p, "; ")
end
local function pick(tag, f)
  local ok, r = pcall(f)
  local s = tostring(r)
  if ok and type(r) == "userdata" then
    pcall(function() s = "has=" .. tostring(r:get_field("_HasValue")) .. " value=" .. tostring(r:get_field("_Value")) end)
  end
  out[#out+1] = tag .. ": " .. (ok and s or ("ERR " .. s))
end
local t = sp:get_field("CurrApplyShortcutSettingType") or 0
pick("picker HP", function() return sp:call("getRecoverHPItemID(System.Boolean, app.ItemShortcutSettingType)", false, t) end)
pick("picker HP (flag true)", function() return sp:call("getRecoverHPItemID(System.Boolean, app.ItemShortcutSettingType)", true, t) end)
pick("picker stamina", function() return sp:call("getRecoverStaminaItemID(app.ItemShortcutSettingType)", t) end)
pick("picker max stamina", function() return sp:call("getRecoverMaxStaminaItemID(app.ItemShortcutSettingType)", t) end)
return table.concat(out, "\n")
