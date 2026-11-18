local D = _G.DPC_dbg
local st = D.state
local kg = sdk.get_managed_singleton("app.GuiManager"):get_field("KeyGuide")
local c = kg:get_field("PlChara")
local o = st.orig_keyguide
return string.format("active %s now %.2f next_hud %.2f frames %s PlChara %s orig %s pawn %s job %s kgJob %s", tostring(st.active), os.clock(), st.next_hud_check_t or -1, tostring(st.frames_since_start), tostring(c and c:call("get_CharaIDString")), tostring(o and o.PlChara and o.PlChara:call("get_CharaIDString")), tostring(st.pawn_chara and st.pawn_chara:call("get_CharaIDString")), tostring(st.pawn_job), tostring(kg:get_field("Job")))
