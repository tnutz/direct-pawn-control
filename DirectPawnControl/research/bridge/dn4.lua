local out = {}
local h = sdk.find_type_definition("app.HitController")
for _, n in ipairs({ "updateDamageHp", "damageProc", "updateDamage", "setDamageInfo", "setHp", "checkNoDieAttack" }) do
  for _, m in ipairs(h:get_methods()) do
    if m:get_name() == n then
      local ps = {}
      for i, p in ipairs(m:get_param_types()) do ps[#ps+1] = p:get_full_name() end
      local pn = {}
      pcall(function() for _, x in ipairs(m:get_param_names()) do pn[#pn+1] = x end end)
      out[#out+1] = n .. "(" .. table.concat(ps, ", ") .. ") names: " .. table.concat(pn, ",") .. " -> " .. m:get_return_type():get_full_name()
    end
  end
end
local dt = nil
for _, m in ipairs(h:get_methods()) do if m:get_name() == "updateDamageHp" then dt = m:get_param_types()[1] end end
if dt then
  local fs = {}
  local tt = dt
  while tt and tt:get_full_name() ~= "System.Object" do
    for _, f in ipairs(tt:get_fields()) do if not f:is_static() then fs[#fs+1] = f:get_name() .. ":" .. f:get_type():get_name() end end
    tt = tt:get_parent_type()
  end
  out[#out+1] = dt:get_full_name() .. " F: " .. table.concat(fs, " | ")
end
local hf = {}
for _, f in ipairs(h:get_fields()) do
  local ft = f:get_type():get_full_name()
  if ft:find("Handler") or ft:find("Action") or ft:find("Func") or ft:find("Delegate") then hf[#hf+1] = f:get_name() .. ":" .. ft end
end
out[#out+1] = "handlers: " .. table.concat(hf, " | ")
return table.concat(out, "\n")
