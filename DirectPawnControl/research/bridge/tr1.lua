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
  local okf, fs = pcall(td.get_fields, td)
  if okf and fs then for _, f in ipairs(fs) do out[#out+1] = tn .. " field " .. f:get_name() .. ":" .. tostring(f:get_type():get_full_name()) end end
end
scan("app.Job09ActionController", { "decoy", "summon", "clone", "exist", "get_is", "smoke" })
local ar = sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer")
local c = ar:call("get_Human"):call("get_Job09ActionCtrl")
out[#out+1] = "ctrl = " .. tostring(c)
if c then
  for _, m in ipairs({ "get_IsSummonDecoy", "get_IsDecoyExist", "isExistDecoy", "get_Decoy", "get_DecoyCharacter", "get_IsSummoning" }) do
    local ok, v = pcall(c.call, c, m); out[#out+1] = m .. " = " .. tostring(ok and v)
  end
end
return table.concat(out, "\n")
