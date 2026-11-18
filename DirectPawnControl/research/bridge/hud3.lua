local D = _G.DPC_dbg
local st = D.state
local kg = sdk.get_managed_singleton("app.GuiManager"):get_field("KeyGuide")
if not (st.active and st.arisen_chara) then return "not possessing / no arisen ref: arisen_chara " .. tostring(st.arisen_chara) .. " arisen_human " .. tostring(st.arisen_human) end
kg:set_field("PlChara", st.arisen_chara)
_G.DPC_probe_kg_t = os.clock()
return "set PlChara to the Arisen at " .. tostring(os.clock()) .. " arisen_human " .. tostring(st.arisen_human ~= nil) .. " pawn_human " .. tostring(st.pawn_human ~= nil)
