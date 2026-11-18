local P = _G.DPC_probe
if not P then return "no probe" end
return "skills=" .. table.concat(P.skills, ",") .. " n=" .. #P.log .. " age=" .. string.format("%.1f", os.clock() - P.t0) .. "\n" .. table.concat(P.log, "\n")
