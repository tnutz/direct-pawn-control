local P = _G.DPC_item4
if not P then return "not installed" end
local out = { "calls " .. P.n }
for _, s in ipairs(P.log) do out[#out+1] = s end
local Q = _G.DPC_item2
if Q then for k, v in pairs(Q.n) do out[#out+1] = "n " .. k .. " = " .. tostring(v) end; for k, v in pairs(Q.who) do out[#out+1] = "who " .. k .. " = " .. tostring(v) end; out[#out+1] = "have-calls outside widget " .. tostring(Q.out) end
return table.concat(out, "\n")
