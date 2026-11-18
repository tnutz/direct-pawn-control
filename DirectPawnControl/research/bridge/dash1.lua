local out = {}
for _, tn in ipairs({ "app.ui010201", "app.GUIBase", "app.ui010201.SkillInfo", "app.ui010201.KeyInfo" }) do
  local t = sdk.find_type_definition(tn)
  if t then
    local ms, fs = {}, {}
    for _, m in ipairs(t:get_methods()) do
      local n = m:get_name(); local l = n:lower()
      if tn ~= "app.GUIBase" or l:find("dash") or l:find("guide") then
        local ps = {}
        pcall(function() for _, p in ipairs(m:get_param_types()) do ps[#ps+1] = p:get_name() end end)
        ms[#ms+1] = n .. "(" .. table.concat(ps, ",") .. ")"
      end
    end
    if tn ~= "app.GUIBase" then for _, f in ipairs(t:get_fields()) do fs[#fs+1] = f:get_name() .. ":" .. f:get_type():get_name() end end
    out[#out+1] = tn .. "\n M: " .. table.concat(ms, " ") .. "\n F: " .. table.concat(fs, " | ")
  else out[#out+1] = tn .. " none" end
end
return table.concat(out, "\n")
