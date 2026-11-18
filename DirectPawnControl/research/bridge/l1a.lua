-- read-only recorder: 30 s of player 2's flags (as DPC built them), what sits in the pawn's input, and the pawn's action nodes
local D = _G.DPC_dbg
if not D then return "no DPC_dbg" end
local st = D.state
_G.DPC_probe = { log = {}, t0 = os.clock(), last = "" }
local P = _G.DPC_probe
P.skills = {}
for i = 1, 6 do P.skills[i] = st.pawn_skills and st.pawn_skills[i] or 0 end
if not _G.DPC_probe_hooked then
  _G.DPC_probe_hooked = true
  re.on_frame(function()
    local P = _G.DPC_probe
    if not P or os.clock() - P.t0 > 30 then return end
    pcall(function()
      local s = _G.DPC_dbg.state
      local pin = s.pawn_input
      local on = s.last_on_flags or 0
      local pon = pin and pin:get_field("ButtonOnFlags") or 0
      local fsm = s.pawn_chara:call("get_ActionManager"):get_field("Fsm")
      local n0 = tostring(fsm:call("getCurrentNodeName(System.UInt32)", 0))
      local n1 = tostring(fsm:call("getCurrentNodeName(System.UInt32)", 1))
      local key = string.format("%X|%X|%s|%s", on, pon, n0, n1)
      if key ~= P.last then
        P.last = key
        P.log[#P.log + 1] = string.format("%.2f on=%X pawn_in=%X %s | %s", os.clock() - P.t0, on, pon, n0, n1)
        if #P.log > 250 then table.remove(P.log, 1) end
      end
    end)
  end)
end
return "recording 30 s; skills=" .. table.concat(P.skills, ",")
