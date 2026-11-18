local out = {}
local function scan(tn, pats, byret)
  local td = sdk.find_type_definition(tn)
  if not td then out[#out+1] = tn .. " = nil"; return end
  out[#out+1] = "## " .. tn .. " parent=" .. tostring(td:get_parent_type() and td:get_parent_type():get_full_name())
  for _, m in ipairs(td:get_methods()) do
    local n = m:get_name(); local l = n:lower()
    local rt = ""; pcall(function() rt = m:get_return_type():get_full_name() end)
    local hit = false
    for _, p in ipairs(pats) do if l:find(p) then hit = true end end
    if byret and rt == byret then hit = true end
    if hit then
      local ps = {}
      pcall(function() for _, pt in ipairs(m:get_param_types()) do ps[#ps+1] = pt:get_full_name() end end)
      out[#out+1] = n .. "(" .. table.concat(ps, ",") .. ") -> " .. rt
    end
  end
end
scan("app.Pawn", { "revive", "ctor" })
scan("app.SpecialPawn", { "revive", "dead", "lost" })
scan("app.PawnManager", { "revive", "getpawn", "get_pawn", "findpawn" }, "app.Pawn")
scan("app.HitController", { "reviv", "recover", "resurrect", "sethp", "set_hp", "heal" })
scan("app.HumanReviveInteractController", { "." })
scan("app.Character", { "get_pawn", "pawn" }, "app.Pawn")
return table.concat(out, "\n")
