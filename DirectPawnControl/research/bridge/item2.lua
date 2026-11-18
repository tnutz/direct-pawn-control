-- counts which ItemManager "how many do you have" calls the quick-item cross (ui020401) makes during its update,
-- and for whom. Hooks only count; they change nothing. They stay until Reset Scripts.
if _G.DPC_item2 then return "already installed" end
local P = { inw = false, n = {}, who = {}, ids = {} }
_G.DPC_item2 = P
local D = _G.DPC_dbg
local function hook(tn, sig, key, fn)
  local m = sdk.find_type_definition(tn):get_method(sig)
  if not m then P.n[key] = "no method"; return end
  P.n[key] = 0
  sdk.hook(m, function(args) local ok = pcall(fn, args) end, function(r) return r end)
end
local wm = sdk.find_type_definition("app.ui020401"):get_method("update")
sdk.hook(wm, function(args) P.inw = true; P.upd = (P.upd or 0) + 1 end, function(r) P.inw = false; return r end)
for _, v in ipairs({ { "getHaveNum(System.Int32, app.CharacterID)", "have_id" }, { "getHaveNum(System.Int32, app.Character)", "have_ch" },
                     { "getHaveNumNoLock(System.Int32, app.CharacterID)", "nolock_id" }, { "getHaveNumNoLock(System.Int32, app.Character)", "nolock_ch" } }) do
  local key, is_ch = v[2], v[2]:find("_ch") ~= nil
  hook("app.ItemManager", v[1], key, function(args)
    if not P.inw then P.out = (P.out or 0) + 1; return end
    P.n[key] = P.n[key] + 1
    local id = sdk.to_int64(args[3]) & 0xFFFFFFFF
    local w
    if is_ch then
      local a = sdk.to_int64(args[4])
      local st = D.state
      w = (st.arisen_chara and a == st.arisen_chara:get_address()) and "arisen" or (st.pawn_chara and a == st.pawn_chara:get_address()) and "pawn" or "other"
    else w = "cid " .. tostring(sdk.to_int64(args[4]) & 0xFFFFFFFF) end
    P.who[key .. " " .. w] = (P.who[key .. " " .. w] or 0) + 1
    P.ids[id] = (P.ids[id] or 0) + 1
  end)
end
for _, v in ipairs({ "getRecoverHPItemID(System.Boolean, app.ItemShortcutSettingType)", "getRecoverStaminaItemID(app.ItemShortcutSettingType)", "getItemID(app.ItemIDEnum[], System.Boolean)" }) do
  local key = v:match("^(%w+)")
  hook("app.ItemShortcutParameter", v, key, function(args) if P.inw then P.n[key] = P.n[key] + 1 else P.n[key .. "_out"] = (P.n[key .. "_out"] or 0) + 1 end end)
end
return "installed"
