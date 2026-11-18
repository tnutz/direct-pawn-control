local out = {}
local D = _G.DPC_dbg
if not D then return "no dbg" end
local S, R = D.state, D.R
out[#out+1] = "active=" .. tostring(S.active) .. " pawn=" .. tostring(S.pawn_name) .. " ai_ends=" .. tostring(R.ai_ends)
local function try(tag, fn) local ok, v = pcall(fn); out[#out+1] = tag .. " = " .. tostring(v) end
local function info(tag, ch)
  if not ch then out[#out+1] = tag .. " nil"; return end
  out[#out+1] = "--- " .. tag
  try("nodes", function()
    local am = ch:call("get_ActionManager"); local fsm = am:get_field("Fsm")
    return tostring(fsm:call("getCurrentNodeName(System.UInt32)", 0)) .. " | " .. tostring(fsm:call("getCurrentNodeName(System.UInt32)", 1))
  end)
  local aidm = ch:call("get_AIDecisionMaker")
  local dm = aidm and aidm:call("get_DecisionModule")
  if dm then
    try("IsSkipThink", function() return dm:call("get_IsSkipThink") end)
    try("executing", function()
      local ex = dm:call("get_DecisionExecutor"); local d = ex:call("get_ExecutingDecision")
      if not d then return "none" end
      local s = d:get_type_definition():get_full_name()
      pcall(function() s = s .. " pack=" .. tostring(d:call("get_ActionPackData"):call("get_Path")) end)
      pcall(function() s = s .. " " .. tostring(d:call("ToString")) end)
      return s
    end)
    local td = dm:get_type_definition()
    for _, fl in ipairs(td:get_fields()) do
      local ok, v = pcall(function() return dm:get_field(fl:get_name()) end)
      if ok and (type(v) == "boolean" or type(v) == "number") then out[#out+1] = "  dm." .. fl:get_name() .. "=" .. tostring(v) end
    end
  end
  local nav = ch:call("get_NavigationController")
  if nav then
    try("nav type", function() return nav:get_type_definition():get_full_name() end)
    for _, m in ipairs({ "get_IsRequestDisableNavi", "get_IsMoving", "get_IsNavigating", "get_IsArrived", "get_HasPath" }) do
      local ok, v = pcall(nav.call, nav, m); if ok and v ~= nil then out[#out+1] = "  nav." .. m .. "=" .. tostring(v) end
    end
  end
  try("actinter", function()
    local ai = ch:call("get_ActionInterface") or ch:call("get_ActInter")
    return ai and ai:get_type_definition():get_full_name()
  end)
  try("input flags", function()
    local inp = ch:call("get_Input"); return tostring(inp:get_type_definition():get_full_name())
  end)
  try("pos", function() local p = ch:call("get_GameObject"):call("get_Transform"):call("get_Position"); return string.format("%.1f %.1f %.1f", p.x, p.y, p.z) end)
end
info("pawn", S.pawn_chara)
info("arisen", S.arisen_chara)
if S.pawn_obj then
  for _, n in ipairs({ "_NextOrder", "_CurrentOrder", "_Order" }) do
    local ok, v = pcall(function() return S.pawn_obj:get_field(n) end); out[#out+1] = "pawn_obj." .. n .. "=" .. tostring(ok and v)
  end
end
-- method inventory for later
for _, tn in ipairs({ "app.DecisionExecutor", "app.DecisionModule", "app.PawnNavigationController", "app.AIDecisionMaker" }) do
  local t = sdk.find_type_definition(tn)
  if t then local ns = {}
    for _, m in ipairs(t:get_methods()) do ns[#ns+1] = m:get_name() end
    out[#out+1] = tn .. ": " .. table.concat(ns, " ")
  else out[#out+1] = tn .. "=nil" end
end
return table.concat(out, "\n")
