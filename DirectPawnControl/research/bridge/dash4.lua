local D = _G.DPC_dbg
local gm = sdk.get_managed_singleton("app.GuiManager")
local kg = gm:get_field("KeyGuide")
local st = D.state
local function id(c) return c and tostring(c:call("get_CharaIDString")) or "nil" end
local before = id(kg:get_field("PlChara"))
if not (st.active and st.pawn_chara and st.pawn_human) then return "not possessing; before " .. before end
kg:set_field("PlChara", st.pawn_chara)
kg:set_field("PlHuman", st.pawn_human)
local pin = st.pawn_chara:call("get_Input")
if pin then kg:set_field("PlInput", pin) end
_G.DPC_probe_kg_t = os.clock()
return "before " .. before .. " -> set to " .. id(kg:get_field("PlChara")) .. " at " .. tostring(os.clock())
