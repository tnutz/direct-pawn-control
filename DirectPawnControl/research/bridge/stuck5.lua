local out = {}
local D = _G.DPC_dbg
local S, R = D.state, D.R
out[#out+1] = "active=" .. tostring(S.active) .. " pawn=" .. tostring(S.pawn_name) .. " stops=" .. tostring(R.guide_stops) .. " forced=" .. tostring(R.guide_forced) .. " ai_ends=" .. tostring(R.ai_ends) .. " t0=" .. tostring(R.guide_t0)
local pm = sdk.get_managed_singleton("app.PawnManager")
local con = pm:call("get_PawnConcierge")
local cc = con and con:call("get_ConciergeCharacter")
out[#out+1] = "IsConcierge=" .. tostring(con and con:call("get_IsConcierge")) .. " chara=" .. tostring(cc and cc:call("get_GameObject"):call("get_Name")) .. " same=" .. tostring(cc and S.pawn_chara and cc:get_address() == S.pawn_chara:get_address())
if con then
  local cs = con:get_field("CurrentState"); local ns = con:get_field("NextState")
  out[#out+1] = "state=" .. tostring(cs and cs:get_type_definition():get_full_name()) .. " next=" .. tostring(ns and ns:get_type_definition():get_full_name())
  for _, f in ipairs({ "IsFinishConcierge", "IsRequestedSuspendPawnGuide", "IsRequestedConciergeGuide", "_IsMovingInFrontOfPl", "_CurrentConciergeQuestID", "ConciergeStartIntervalTimer", "IsCompleteGauidance" }) do
    out[#out+1] = "  " .. f .. "=" .. tostring(con:get_field(f))
  end
  out[#out+1] = "  dist=" .. tostring(con:call("get_DistanceToDestination")) .. " suspend=" .. tostring(con:call("isSuspendNavigation")) .. " disable=" .. tostring(con:call("isDisableNavigation"))
end
local ch = S.pawn_chara
if ch then
  local am = ch:call("get_ActionManager"); local fsm = am:get_field("Fsm")
  out[#out+1] = "nodes=" .. tostring(fsm:call("getCurrentNodeName(System.UInt32)", 0)) .. " | " .. tostring(fsm:call("getCurrentNodeName(System.UInt32)", 1))
  local dm = ch:call("get_AIDecisionMaker"):call("get_DecisionModule")
  local d = dm:call("get_DecisionExecutor"):call("get_ExecutingDecision")
  out[#out+1] = "skip=" .. tostring(dm:call("get_IsSkipThink")) .. " executing=" .. tostring(d and d:get_type_definition():get_full_name())
  local nav = ch:call("get_NavigationController")
  out[#out+1] = "nav disable=" .. tostring(nav:call("get_IsRequestDisableNavi")) .. " moveTime=" .. tostring(nav:get_field("_ConciergeMoveTime")) .. " timer=" .. tostring(nav:get_field("_Timer"))
  local nai = S.pawn_obj and S.pawn_obj:call("get_CachedNavigationAI")
  if nai then out[#out+1] = "nai IsNaviNow=" .. tostring(nai:call("get_IsNaviNow")) .. " stopCalled=" .. tostring(nai:call("get_IsStopCalled")) .. " moveType=" .. tostring(nai:call("get_CurrentMoveType")) .. " NaviAIState=" .. tostring(nai:get_field("NaviAIState")) end
  out[#out+1] = "order=" .. tostring(S.pawn_obj and S.pawn_obj:call("get_ActiveOrder")) .. " next=" .. tostring(S.pawn_obj and S.pawn_obj:get_field("_NextOrder")) .. " explore=" .. tostring(S.pawn_obj and S.pawn_obj:call("get_IsExploreOrdering"))
  local p = ch:call("get_GameObject"):call("get_Transform"):call("get_Position"); out[#out+1] = string.format("pos %.2f %.2f %.2f", p.x, p.y, p.z)
  pcall(function()
    local inp = ch:call("get_Input")
    local s = "input:"
    for _, f in ipairs(inp:get_type_definition():get_fields()) do
      local ok, v = pcall(function() return inp:get_field(f:get_name()) end)
      if ok and (type(v) == "number" or type(v) == "boolean") then s = s .. " " .. f:get_name() .. "=" .. tostring(v)
      elseif ok and type(v) == "userdata" then pcall(function() s = s .. string.format(" %s=(%.2f,%.2f,%.2f)", f:get_name(), v.x, v.y, v.z) end) end
    end
    out[#out+1] = s
  end)
end
local lg = {}
return table.concat(out, "\n")
