-- Read-only: what can stop a pawn's running AI action? Methods with End / Cancel / Stop / Abort / Clear / Reset / Idle / Interrupt.
local out = {}
local function dump(name, pats, depth)
  local t, d, l = sdk.find_type_definition(name), 0, {}
  if not t then out[name] = "no type"; return end
  while t and d < (depth or 1) do
    for _, m in ipairs(t:get_methods()) do
      local n = m:get_name()
      for _, p in ipairs(pats) do
        if n:find(p) then
          local ps = {}
          for _, pt in ipairs(m:get_param_types()) do ps[#ps + 1] = pt:get_full_name() end
          l[#l + 1] = n .. "(" .. table.concat(ps, ", ") .. ")"
          break
        end
      end
    end
    t = t:get_parent_type(); d = d + 1
  end
  out[name] = l
end
local P = { "[Ee]nd", "[Cc]ancel", "[Ss]top", "[Aa]bort", "[Cc]lear", "[Rr]eset", "[Ii]dle", "[Ii]nterrupt", "[Ff]orce", "isPlay", "[Cc]urrent", "[Ee]xec" }
for _, n in ipairs({ "app.ActionInterface", "app.AIBlackBoardController", "app.PawnAIBlackBoardController", "app.HumanActionSelector", "app.AIDecisionMaker", "app.DecisionEvaluationModule", "app.DecisionExecutor", "app.goalplanning.AIGoalPlanning", "app.PawnNavigationController", "app.Pawn" }) do dump(n, P, 2) end
-- live: main pawn's current state
local pw = sdk.get_managed_singleton("app.PawnManager"):call("get_PawnCharacterList")[0]
local live = {}
pcall(function()
  local fsm = pw:call("get_ActionManager"):get_field("Fsm")
  live.node0 = fsm:call("getCurrentNodeName(System.UInt32)", 0); live.node1 = fsm:call("getCurrentNodeName(System.UInt32)", 1)
  local ai = pw:get_GameObject():call("getComponent(System.Type)", sdk.typeof("app.ActionInterface"))
  live.ai = ai ~= nil
  if ai then
    for _, f in ipairs(ai:get_type_definition():get_fields()) do
      local ok, v = pcall(ai.get_field, ai, f:get_name()); local sv = tostring(v)
      if ok and type(v) == "userdata" then pcall(function() sv = "<" .. v:get_type_definition():get_full_name() .. ">" end) end
      live["ai." .. f:get_name()] = f:get_type():get_full_name() .. " = " .. sv
    end
  end
end)
out.live = live
json.dump_file("DPC_probe_act_1.json", out)
return "ok"
