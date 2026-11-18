-- Recorder (bridge state): samples DPC's brain telemetry + live game facts for _G.RR_T seconds -> agent_bridge/rr.json
local T = _G.RR_T or 10
_G.RR = { t0 = os.clock(), rows = {}, done = false, last = 0 }
if not _G.RR_CB then
  _G.RR_CB = true
  re.on_pre_application_entry("LateUpdateBehavior", function()
    local R = _G.RR
    if not R or R.done then return end
    local now = os.clock()
    if now - R.last < 0.25 then return end
    R.last = now
    local row = { t = math.floor((now - R.t0) * 100) / 100 }
    pcall(function()
      local b = json.load_file("DPC_arisen_brain.json")
      if b then
        row.mode = b.mode; row.tgt = b.target; row.hp = b.target_hp; row.d = b.dist and math.floor(b.dist * 10) / 10
        row.off = b.off_deg and math.floor(b.off_deg); row.shots = b.presses; row.sk = b.skill_uses
        row.nodes = b.arisen_nodes; row.err = b.errors; row.on = b.on; row.poss = b.possessing; row.want = b.want
      end
    end)
    pcall(function()
      local sm = sdk.get_managed_singleton("app.ShellManager")
      row.shells = sm:get_field("ShellList"):call("get_Count")
    end)
    pcall(function()
      local cm = sdk.get_managed_singleton("app.CharacterManager")
      local ar = cm:get_ManualPlayer()
      local p = ar:get_Transform():get_Position()
      row.apos = string.format("%.1f,%.1f,%.1f", p.x, p.y, p.z)
      row.ahp = math.floor(ar:get_Hp())
      local cam = sdk.get_managed_singleton("app.CameraManager"):call("getMainCameraController", 0):call("get_TargetCharacter")
      row.cam = cam and cam:call("get_CharaIDString")
    end)
    R.rows[#R.rows + 1] = row
    if now - R.t0 > (_G.RR_T or 10) then
      R.done = true
      json.dump_file("agent_bridge/rr.json", R.rows)
    end
  end)
end
return { "recording " .. T .. " s" }
