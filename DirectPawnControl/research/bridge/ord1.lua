local out = {}
local function sig(m)
  local ps = {}
  pcall(function() for _, pt in ipairs(m:get_param_types()) do ps[#ps+1] = pt:get_full_name() end end)
  local rt = ""; pcall(function() rt = m:get_return_type():get_full_name() end)
  return m:get_name() .. "(" .. table.concat(ps, ",") .. ")->" .. rt .. (m:is_static() and " static" or "")
end
local function scan(tn, pats)
  local t = sdk.find_type_definition(tn); if not t then out[#out+1] = tn .. "=nil"; return end
  out[#out+1] = "== " .. tn
  for _, m in ipairs(t:get_methods()) do local l = m:get_name():lower()
    for _, p in ipairs(pats) do if l:find(p) then out[#out+1] = "  " .. sig(m); break end end end
  for _, f in ipairs(t:get_fields()) do local l = f:get_name():lower()
    for _, p in ipairs(pats) do if l:find(p) then out[#out+1] = "  F " .. f:get_name() .. ":" .. f:get_type():get_full_name(); break end end end
end
scan("app.ui020401", { "." })
scan("app.PawnOrderController", { "." })
scan("app.PawnManager", { "order" })
scan("app.GuiManager", { "order", "cross" })
return table.concat(out, "\n")
