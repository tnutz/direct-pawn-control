local out = {}
for _, tn in ipairs({ "app.Human", "app.Character", "app.HumanActionSelector", "app.ClingController", "app.HumanClingController", "app.CatchController", "app.Player" }) do
  local t = sdk.find_type_definition(tn)
  if not t then out[#out+1] = tn .. " none" else
    local ms = {}
    for _, m in ipairs(t:get_methods()) do
      local n = m:get_name(); local l = n:lower()
      if l:find("cling") or l:find("climb") or l:find("holdon") or l:find("grapple") then ms[#ms+1] = n end
    end
    local fs = {}
    for _, f in ipairs(t:get_fields()) do
      local l = f:get_name():lower()
      if l:find("cling") or l:find("climb") then fs[#fs+1] = f:get_name() .. ":" .. f:get_type():get_full_name() end
    end
    out[#out+1] = tn .. " M: " .. table.concat(ms, " ") .. " F: " .. table.concat(fs, " ")
  end
end
return table.concat(out, "\n")
