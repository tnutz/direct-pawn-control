-- read-only: for every party pawn, what the action executor and the navigation controller are doing
local out = {}
local D = _G.DPC_dbg
local pm = sdk.get_managed_singleton("app.PawnManager")
local list = pm:call("get_PawnCharacterList")
local n = list:call("get_Count")
out[#out+1] = "dpc " .. tostring(D and D.state and D.state.active) .. " pawn " .. tostring(D and D.state and D.state.pawn_name)
for i = 0, n - 1 do
  local ch = list:call("get_Item", i)
  local line = { tostring(i) }
  local ok, err = pcall(function()
    line[#line+1] = tostring(ch:call("get_GameObject"):call("get_Name"))
    local dm = ch:call("get_AIDecisionMaker"):call("get_DecisionModule")
    line[#line+1] = "skip=" .. tostring(dm:call("get_IsSkipThink"))
    local ai = dm:call("get_ActionInterface")
    local ex = ai and ai:call("get_Executor")
    if ex then
      line[#line+1] = "exState=" .. tostring(ex:get_field("_State"))
      local ce = ex:get_field("_CommandExecutor")
      if ce then
        line[#line+1] = "ceState=" .. tostring(ce:call("get__State")) .. " exec=" .. tostring(ce:call("get_IsExecute")) .. " started=" .. tostring(ce:call("get_HasStarted"))
        local p, s = ce:get_field("_PrimaryCommand"), ce:get_field("_SecondaryCommand")
        line[#line+1] = "prim=" .. (p and p:get_type_definition():get_full_name() or "nil")
        line[#line+1] = "sec=" .. (s and s:get_type_definition():get_full_name() or "nil")
      else line[#line+1] = "no cmd executor" end
    else line[#line+1] = "no executor" end
    local nav = ch:call("get_NavigationController")
    if nav then
      line[#line+1] = "nav=" .. nav:get_type_definition():get_name() .. " st=" .. tostring(nav:get_field("_CurrentState"))
        .. " idle=" .. tostring(nav:call("get_IsRequestIdle")) .. " dis=" .. tostring(nav:call("get_IsRequestDisableNavi"))
        .. " ovr=" .. tostring(nav:call("get_IsOverride")) .. " spd=" .. tostring(nav:call("get_MaxSpeedType"))
      local wp = nav:get_field("_WayPoints")
      line[#line+1] = "wps=" .. tostring(wp and wp:call("get_Count"))
    end
  end)
  if not ok then line[#line+1] = "ERR " .. tostring(err) end
  out[#out+1] = table.concat(line, " ")
end
return table.concat(out, "\n")
