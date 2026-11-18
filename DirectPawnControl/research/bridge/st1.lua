local out = {}
local ar = sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer")
local sm = ar:call("get_StaminaManager")
local td = sm:get_type_definition()
out[#out+1] = "type " .. td:get_full_name()
for _, m in ipairs(td:get_methods()) do
  local n = m:get_name()
  local ps = {}
  pcall(function() for _, pt in ipairs(m:get_param_types()) do ps[#ps+1] = pt:get_full_name() end end)
  local rt = ""; pcall(function() rt = m:get_return_type():get_full_name() end)
  local v = ""
  if #ps == 0 and (n:find("^get_") or n:find("^is")) then local ok, r = pcall(sm.call, sm, n); v = " = " .. tostring(ok and r) end
  out[#out+1] = n .. "(" .. table.concat(ps, ",") .. ") -> " .. rt .. v
end
for _, f in ipairs(td:get_fields()) do
  local v = ""; pcall(function() v = tostring(sm:get_field(f:get_name())) end)
  out[#out+1] = "f " .. f:get_name() .. ":" .. tostring(f:get_type():get_full_name()) .. " = " .. v
end
local D = _G.DPC_dbg
out[#out+1] = "DPC active=" .. tostring(D and D.state.active) .. " job=" .. tostring(ar:call("get_Human") and ar:call("get_Human"):call("get_JobContext") and ar:call("get_Human"):call("get_JobContext"):get_field("CurrentJob"))
local inp = ar:call("get_Input")
out[#out+1] = string.format("arisen input on=%X", inp:get_field("ButtonOnFlags") or 0)
return table.concat(out, "\n")
