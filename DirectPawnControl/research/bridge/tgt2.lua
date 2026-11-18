local D = _G.DPC_dbg
local S = D.state
local lk = S.arisen_lockon_ctrl
local function cid(c) return c and tostring(c:call("get_CharaIDString")) or "nil" end
local s = "active=" .. tostring(S.active) .. " pawn=" .. cid(S.pawn_chara) .. " lockChara=" .. cid(lk:get_field("Chara")) .. " target=" .. tostring(lk:call("get_Target") ~= nil)
s = s .. " sameLock=" .. tostring(D.native.lock and D.native.lock:get_address() == lk:get_address())
local cm = sdk.get_managed_singleton("app.CharacterManager")
local pl = cm:call("get_ManualPlayer")
s = s .. " manual=" .. cid(pl) .. " plLockSame=" .. tostring(pl:call("get_LockOnCtrl"):get_address() == lk:get_address())
return s
