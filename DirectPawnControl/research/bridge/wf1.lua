local out = {}
local function scan(tn, pats)
  local td = sdk.find_type_definition(tn)
  if not td then out[#out+1] = tn .. " = nil"; return end
  local ok, ms = pcall(td.get_methods, td)
  if ok and ms then for _, m in ipairs(ms) do
    local n = m:get_name(); local l = n:lower()
    for _, p in ipairs(pats) do if l:find(p) then
      local ps = {}
      pcall(function() for _, pt in ipairs(m:get_param_types()) do ps[#ps+1] = pt:get_full_name() end end)
      local rt = ""; pcall(function() rt = m:get_return_type():get_full_name() end)
      out[#out+1] = tn .. "." .. n .. "(" .. table.concat(ps, ",") .. ") -> " .. rt; break end end
  end end
end
scan("app.Human", { "weaponjob", "currentjob", "weapontype", "weaponkind", "get_job", "rearm", "changeweapon", "actualjob", "mainweapon" })
scan("app.Character", { "weaponjob", "weapontype", "weaponkind", "get_job", "actualjob" })
scan("app.JobContext", { "job", "weapon" })
scan("app.Job10Parameter", { "get_" })
scan("app.Job10InputProcessor", { "job", "weapon", "current" })
local ar = sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer")
local hu = ar:call("get_Human")
for _, m in ipairs({ "get_WeaponJob", "get_CurrentJob", "get_Job", "get_ActualJob" }) do
  local ok, v = pcall(hu.call, hu, m); out[#out+1] = "Human:" .. m .. " = " .. tostring(ok and v)
end
return table.concat(out, "\n")
