local out = {}
for _, tn in ipairs({ "app.Hit", "app.Character", "app.Pawn", "app.PawnManager", "app.Human" }) do
  local t = sdk.find_type_definition(tn)
  if t then
    local ms = {}
    for _, m in ipairs(t:get_methods()) do
      local n = m:get_name(); local l = n:lower()
      if l:find("dead") or l:find("die") or l:find("kill") or l:find("death") or l:find("sethp") or l:find("revive") or l:find("down") then
        local ps = {}
        pcall(function() for _, p in ipairs(m:get_param_types()) do ps[#ps+1] = p:get_name() end end)
        ms[#ms+1] = n .. "(" .. table.concat(ps, ",") .. ")"
      end
    end
    out[#out+1] = tn .. ": " .. table.concat(ms, " ")
  end
end
return table.concat(out, "\n")
