local D = _G.DPC_dbg
local kg = sdk.get_managed_singleton("app.GuiManager"):get_field("KeyGuide")
local st = D.state
local c = kg:get_field("PlChara")
local pi = kg:get_field("PlInput")
local pawn_in = st.pawn_chara and st.pawn_chara:call("get_Input")
return "active " .. tostring(st.active) .. " PlChara " .. tostring(c and c:call("get_CharaIDString")) .. " PlInput pawn's " .. tostring(pi and pawn_in and pi:get_address() == pawn_in:get_address()) .. " dt " .. tostring(os.clock() - (_G.DPC_probe_kg_t or 0)) .. " cfg hook " .. tostring(D.R and true)
