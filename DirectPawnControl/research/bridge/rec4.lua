-- 8 s recorder: target HP, Arisen action nodes, presses, nearest pawn distance to the target
local rows, t0, done = {}, os.clock(), false
_G.__rec_rows = rows
re.on_pre_application_entry("LateUpdateBehavior", function()
  if done then return end
  local now = os.clock() - t0
  if now > (_G.REC_T or 8) then done = true; json.dump_file("agent_bridge/rec.json", rows); return end
  if #rows > 0 and now - rows[#rows].t < 0.1 then return end
  pcall(function()
    local A = _G.AB
    local ar = sdk.get_managed_singleton("app.CharacterManager"):get_ManualPlayer()
    local fsm = ar:call("get_ActionManager"):get_field("Fsm")
    local t = A.target
    local pd = 999
    if t then
      local tp = t:get_Transform():get_Position()
      local pl = sdk.get_managed_singleton("app.PawnManager"):call("get_PawnCharacterList")
      for i = 0, pl:get_Count() - 1 do
        local p = pl[i]:get_Transform():get_Position()
        pd = math.min(pd, math.sqrt((p.x-tp.x)^2 + (p.z-tp.z)^2))
      end
    end
    local sm = sdk.get_managed_singleton("app.ShellManager")
    rows[#rows+1] = { t = math.floor(now * 100) / 100, hp = t and t:call("get_Hp"), st = A.state, presses = A.native_presses,
      L0 = fsm:call("getCurrentNodeName(System.UInt32)", 0), L1 = fsm:call("getCurrentNodeName(System.UInt32)", 1), hits = A.N4 and A.N4.hits, err = A.N4 and A.N4.err, d = A.dist and math.floor(A.dist*10)/10, off = A.N4 and A.N4.off and math.floor(A.N4.off), post_ax = A.N4 and A.N4.post_ax, ax = A.N4 and A.N4.ax, n4 = A.native4, ay = A.N4 and A.N4.ay, pawn_d = math.floor(pd * 10) / 10, shells = sm:get_field("ShellList"):call("get_Count") }
  end)
end)
return { "recording 8 s" }
