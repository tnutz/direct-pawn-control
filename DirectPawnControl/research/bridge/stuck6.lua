local out = {}
local D = _G.DPC_dbg
local S, R = D.state, D.R
local ch = S.pawn_chara
if not ch then return "no pawn; active=" .. tostring(S.active) end
local aidm = ch:call("get_AIDecisionMaker")
local dm = aidm:call("get_DecisionModule")
out[#out+1] = "active=" .. tostring(S.active) .. " module=" .. dm:get_type_definition():get_full_name() .. " cur=" .. tostring(aidm:call("get_CurrentModuleType")) .. " chg=" .. tostring(aidm:call("get_ChangeModuleType")) .. " init=" .. tostring(aidm:call("get_InitalSetType"))
out[#out+1] = "skip before=" .. tostring(dm:call("get_IsSkipThink"))
local ok, e = pcall(function() dm:call("set_IsSkipThink(System.Boolean)", true) end)
out[#out+1] = "set ok=" .. tostring(ok) .. " " .. tostring(e) .. " after=" .. tostring(dm:call("get_IsSkipThink"))
local t = dm:get_type_definition()
while t and t:get_full_name() ~= "System.Object" do
  local ms = {}
  for _, m in ipairs(t:get_methods()) do ms[#ms+1] = m:get_name() end
  out[#out+1] = t:get_full_name() .. " M: " .. table.concat(ms, " ")
  for _, f in ipairs(t:get_fields()) do local okv, v = pcall(function() return dm:get_field(f:get_name()) end)
    if okv and (type(v) == "boolean" or type(v) == "number") then out[#out+1] = "  " .. f:get_name() .. "=" .. tostring(v) end end
  t = t:get_parent_type()
end
local ex = dm:call("get_DecisionExecutor")
local d = ex and ex:call("get_ExecutingDecision")
out[#out+1] = "executing=" .. tostring(d and d:get_type_definition():get_full_name()) .. " ai_ends=" .. tostring(R.ai_ends) .. " stops=" .. tostring(R.guide_stops)
if d then
  for _, f in ipairs(d:get_type_definition():get_fields()) do local okv, v = pcall(function() return d:get_field(f:get_name()) end)
    local s = tostring(okv and v); if okv and type(v) == "userdata" then pcall(function() s = v:get_type_definition():get_full_name() end); pcall(function() s = s .. " " .. tostring(v:call("get_Path")) end); pcall(function() s = s .. " " .. tostring(v:call("get_Name")) end) end
    out[#out+1] = "  d." .. f:get_name() .. "=" .. s end
end
local bb = ch:call("get_AIBlackBoardController")
local function p(tag, o) local s = "nil"; if o then s = o:get_type_definition():get_full_name(); pcall(function() s = s .. " " .. tostring(o:call("get_Path")) end) end; out[#out+1] = tag .. " = " .. s end
p("ReqMain", bb:call("get_ReqMainActInterPackData")); p("ReqSub", bb:call("get_ReqSubActInterPackData"))
local am = ch:call("get_ActionManager"); local fsm = am:get_field("Fsm")
out[#out+1] = "nodes=" .. tostring(fsm:call("getCurrentNodeName(System.UInt32)", 0)) .. " | " .. tostring(fsm:call("getCurrentNodeName(System.UInt32)", 1))
local pm = sdk.get_managed_singleton("app.PawnManager"); local con = pm:call("get_PawnConcierge")
local cs = con:get_field("CurrentState")
out[#out+1] = "IsConcierge=" .. tostring(con:call("get_IsConcierge")) .. " state=" .. tostring(cs and cs:get_type_definition():get_full_name())
out[#out+1] = "order=" .. tostring(S.pawn_obj:call("get_ActiveOrder")) .. " state=" .. tostring(S.pawn_obj:call("get_State"))
local p3 = ch:call("get_GameObject"):call("get_Transform"):call("get_Position"); out[#out+1] = string.format("pos %.2f %.2f %.2f", p3.x, p3.y, p3.z)
return table.concat(out, "\n")
