local out = {}
local A = rawget(_G, "CameraDistance_API")
out.cd_ver = A and A.version
out.style = A and A.get("coop_style")
out.framing = A and A.get("coop_framing")
out.enabled = A and A.get("enabled")
out.pitch = A and A.get("coop_classic_pitch")
out.native = A and A.get("native_offsets")
local ok, d = pcall(json.load_file, "DPC_coop.json")
out.coop_json = ok and d or tostring(d)
local D = rawget(_G, "DPC_dbg")
out.dpc_coop = D and D.coop.active
local cm = sdk.get_managed_singleton("app.CameraManager")
local mc = cm and cm:call("getMainCameraController", 0)
if mc then
  local ct = mc:call("get_CurrentControlType"); if type(ct) == "userdata" then ct = ct:get_field("value__") end
  out.ctype = ct
  out.player_cam = mc:call("get_CurrentPlayerCamera")
  out.battle = mc:call("get_IsBattleMode")
end
out.offset = cm and cm:call("get_DistanceOffset")
local gm = sdk.get_managed_singleton("app.GuiManager")
out.paused = gm and gm:call("isPausedGUI")
return out
