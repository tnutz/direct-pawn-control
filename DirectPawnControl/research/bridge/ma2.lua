local cm = sdk.get_managed_singleton("app.CharacterManager")
local pl = cm:call("get_ManualPlayer")
local D = _G.DPC_dbg
local ar = (D and D.state.arisen_chara) or pl
local c = ar:call("get_Human"):call("get_Job08ActionCtrl")
return "ArrowType=" .. tostring(c and c:call("get_ArrowType")) .. " possessing=" .. tostring(D and D.state.active)
