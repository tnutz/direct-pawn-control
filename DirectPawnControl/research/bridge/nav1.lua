local out = {}
local D = _G.DPC_dbg
local pm = sdk.get_managed_singleton("app.PawnManager")
local ch = pm:call("get_PawnCharacterList"):call("get_Item", 0)
local pawn = D.state.pawn_obj
if not pawn then
  local go = ch:call("get_GameObject")
  pawn = go:call("getComponent(System.Type)", sdk.typeof("app.Pawn"))
end
local nai = pawn and pawn:call("get_CachedNavigationAI")
if not nai then return "no navigation ai" end
local t = nai:get_type_definition()
while t and t:get_full_name() ~= "System.Object" and t:get_full_name() ~= "via.Behavior" do
  local ms, fs = {}, {}
  for _, m in ipairs(t:get_methods()) do
    local ps = {}
    pcall(function() for _, p in ipairs(m:get_param_types()) do ps[#ps+1] = p:get_name() end end)
    ms[#ms+1] = m:get_name() .. "(" .. table.concat(ps, ",") .. ")"
  end
  for _, f in ipairs(t:get_fields()) do
    if not f:is_static() then local v = nil; pcall(function() v = nai:get_field(f:get_name()) end); fs[#fs+1] = f:get_name() .. ":" .. f:get_type():get_name() .. "=" .. tostring(v):sub(1, 30) end
  end
  out[#out+1] = t:get_full_name() .. "\n M: " .. table.concat(ms, " ") .. "\n F: " .. table.concat(fs, " | ")
  t = t:get_parent_type()
end
local e = sdk.find_type_definition("app.NavigationAI.NaviAIStateEnum") or sdk.find_type_definition("app.NavigationAI.NaviAIState")
if e then local s = {} for _, f in ipairs(e:get_fields()) do if f:is_static() then s[#s+1] = f:get_name() .. "=" .. tostring(f:get_data(nil)) end end out[#out+1] = "state enum: " .. table.concat(s, " ") end
return table.concat(out, "\n")
