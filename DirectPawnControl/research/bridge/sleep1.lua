local out = {}
local function scan(tn, pats)
  local td = sdk.find_type_definition(tn)
  if not td then out[#out+1] = tn .. " = nil"; return end
  local ok, ms = pcall(td.get_methods, td)
  if ok and ms then for _, m in ipairs(ms) do
    local n = m:get_name()
    for _, p in ipairs(pats) do if n:lower():find(p) then
      local ps = {}
      pcall(function() for _, pt in ipairs(m:get_param_types()) do ps[#ps+1] = pt:get_full_name() end end)
      out[#out+1] = tn .. "." .. n .. "(" .. table.concat(ps, ",") .. ")"; break end end
  end end
  local okf, fs = pcall(td.get_fields, td)
  if okf and fs then for _, f in ipairs(fs) do local n = f:get_name(); for _, p in ipairs(pats) do if n:lower():find(p) then out[#out+1] = tn .. " field " .. n .. ":" .. tostring(f:get_type():get_full_name()); break end end end end
end
local pats = { "sleep", "wake", "rouse", "statuscondition" }
scan("app.Character", pats)
scan("app.StatusConditionCtrl", { "sleep", "wake", "isactive", "reqstatus", "cure", "request", "get_" })
scan("app.InteractManager", { "sleep", "wake", "help", "request", "talk" })
scan("app.Human", pats)
scan("app.Pawn", { "sleep", "wake", "rouse", "help" })
return table.concat(out, "\n")
