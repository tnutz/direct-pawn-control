local P = _G.DPC_item2
if not P then return "not installed" end
local out = { "widget updates " .. tostring(P.upd) .. ", have-calls outside the widget " .. tostring(P.out) }
for k, v in pairs(P.n) do out[#out+1] = "n " .. k .. " = " .. tostring(v) end
for k, v in pairs(P.who) do out[#out+1] = "who " .. k .. " = " .. tostring(v) end
local ids = {}
for k, v in pairs(P.ids) do ids[#ids+1] = k .. "x" .. v end
out[#out+1] = "ids " .. table.concat(ids, " ")
local D = _G.DPC_dbg
pcall(function()
  local st = D.state
  out[#out+1] = "active " .. tostring(st.active) .. " pawn " .. tostring(st.pawn_name)
  local cg = sdk.get_managed_singleton("app.GuiManager"):get_field("CrossGuide")
  local pc = cg:get_field("PlChara")
  out[#out+1] = "widget PlChara is arisen " .. tostring(pc and st.arisen_chara and pc:get_address() == st.arisen_chara:get_address()) .. ", is pawn " .. tostring(pc and st.pawn_chara and pc:get_address() == st.pawn_chara:get_address())
  local kl = cg:get_field("KeyList")
  for i = 0, kl:call("get_Count") - 1 do
    local k = kl:call("get_Item", i)
    out[#out+1] = string.format("key %d: action %s item %s x%s msg %s", i, tostring(k:get_field("Action")), tostring(k:get_field("DispItemId")), tostring(k:get_field("DispItemNum")), tostring(k:get_field("NowMsg")))
  end
  local function cid(c) local ok, v = pcall(function() return c:call("get_CharaID") end); return ok and tostring(v) or "?" end
  out[#out+1] = "CharaID arisen " .. cid(st.arisen_chara or sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer")) .. " pawn " .. (st.pawn_chara and cid(st.pawn_chara) or "-")
end)
return table.concat(out, "\n")
