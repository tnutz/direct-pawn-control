local out = {}
local t = sdk.find_type_definition("app.Concierge")
for _, m in ipairs(t:get_methods()) do
  local n = m:get_name()
  if not n:find("^get_") and not n:find("^set_") and not n:find("^add_") and not n:find("^remove_") then
    local ps = {}
    pcall(function() for _, pt in ipairs(m:get_param_types()) do ps[#ps+1] = pt:get_full_name() end end)
    local rt = ""; pcall(function() rt = m:get_return_type():get_full_name() end)
    out[#out+1] = n .. "(" .. table.concat(ps, ",") .. ")->" .. rt
  end
end
local D = _G.DPC_dbg
local S = D.state
out[#out+1] = "possessed=" .. tostring(S.pawn_chara and S.pawn_chara:call("get_CharaIDString")) .. " go=" .. tostring(S.pawn_chara and S.pawn_chara:call("get_GameObject"):call("get_Name")) .. " name=" .. tostring(S.pawn_name)
local pm = sdk.get_managed_singleton("app.PawnManager")
local con = pm:call("get_PawnConcierge")
local cc = con:call("get_ConciergeCharacter")
out[#out+1] = "concierge chara=" .. tostring(cc and cc:call("get_GameObject"):call("get_Name")) .. " same=" .. tostring(cc and S.pawn_chara and cc:get_address() == S.pawn_chara:get_address())
out[#out+1] = "IsConcierge=" .. tostring(con:call("get_IsConcierge")) .. " type=" .. tostring(con:call("get_CurrentConciergeType")) .. " quest=" .. tostring(con:call("get_CurrentConciergeQuestID")) .. " infront=" .. tostring(con:call("get_IsMovingInFrontOfPl")) .. " wait=" .. tostring(con:call("get_IsWaitPlayer"))
local cs = con:get_field("CurrentState")
out[#out+1] = "state=" .. tostring(cs and cs:get_type_definition():get_full_name())
for _, tn in ipairs({ "app.Concierge.ConciergeStateContinue" }) do
  local tt = sdk.find_type_definition(tn)
  if tt then local p = tt:get_parent_type(); out[#out+1] = tn .. " parent=" .. tostring(p and p:get_full_name()) end
end
return table.concat(out, "\n")
