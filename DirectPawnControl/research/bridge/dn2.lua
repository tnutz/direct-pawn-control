local out = {}
local pm = sdk.get_managed_singleton("app.PawnManager")
local ch = pm:call("get_PawnCharacterList"):call("get_Item", 0)
local hit = ch:call("get_Hit")
local t = hit:get_type_definition()
out[#out+1] = t:get_full_name()
local ms = {}
for _, m in ipairs(t:get_methods()) do
  local n = m:get_name(); local l = n:lower()
  if l:find("dead") or l:find("die") or l:find("kill") or l:find("hp") or l:find("revive") or l:find("damage") then
    local ps = {}
    pcall(function() for _, p in ipairs(m:get_param_types()) do ps[#ps+1] = p:get_name() end end)
    ms[#ms+1] = n .. "(" .. table.concat(ps, ",") .. ")"
  end
end
out[#out+1] = table.concat(ms, " ")
local t2 = sdk.find_type_definition("app.Character.KillAndSetDieLoopOption")
if t2 then local fs = {} for _, f in ipairs(t2:get_fields()) do fs[#fs+1] = f:get_name() .. ":" .. f:get_type():get_full_name() .. (f:is_static() and "(s)" or "") end out[#out+1] = "opt: " .. table.concat(fs, " ") end
return table.concat(out, "\n")
