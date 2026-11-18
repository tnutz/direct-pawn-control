-- Sample arrow (shell) positions for 4 s to see which way they fly
_G.SH = { t0 = os.clock(), rows = {}, done = false }
if not _G.SH_CB then
  _G.SH_CB = true
  re.on_pre_application_entry("LateUpdateBehavior", function()
    local S = _G.SH
    if not S or S.done then return end
    local now = os.clock() - S.t0
    pcall(function()
      local list = sdk.get_managed_singleton("app.ShellManager"):get_field("ShellList")
      local n = list:call("get_Count")
      for i = 0, n - 1 do
        local sh = list:call("get_Item", i)
        local go = sh and sh:call("get_GameObject")
        local p = go and go:call("get_Transform"):call("get_Position")
        if p then S.rows[#S.rows + 1] = string.format("%.2f %x %.1f,%.1f,%.1f", now, sh:get_address() % 0x100000, p.x, p.y, p.z) end
      end
    end)
    if now > 4 then
      S.done = true
      local ar = sdk.get_managed_singleton("app.CharacterManager"):get_ManualPlayer()
      local ap = ar:get_Transform():get_Position()
      local f = ar:get_Transform():get_Rotation() * Vector3f.new(0, 0, 1)
      local cz = sdk.get_primary_camera():call("get_GameObject"):call("get_Transform"):call("get_AxisZ")
      local LS = _G.LS
      json.dump_file("agent_bridge/sh.json", { rows = S.rows, ar = string.format("%.1f,%.1f,%.1f", ap.x, ap.y, ap.z),
        face_yaw = math.deg(math.atan(f.x, f.z)), cam_yaw = math.deg(math.atan(-cz.x, -cz.z)),
        tgt = LS and LS.tpos and string.format("%.1f,%.1f,%.1f", LS.tpos.x, LS.tpos.y, LS.tpos.z) })
    end
  end)
end
return { "sampling shells" }
