local out = {}
local function scan(tn, pats)
  local td = sdk.find_type_definition(tn)
  if not td then out[#out+1] = tn .. " = nil"; return end
  for _, m in ipairs(td:get_methods()) do
    local l = m:get_name():lower()
    for _, p in ipairs(pats) do if l:find(p) then
      local ps = {}
      pcall(function() for _, pt in ipairs(m:get_param_types()) do ps[#ps+1] = pt:get_full_name() end end)
      local rt = ""; pcall(function() rt = m:get_return_type():get_full_name() end)
      out[#out+1] = tn .. "." .. m:get_name() .. "(" .. table.concat(ps, ",") .. ") -> " .. rt; break end end
  end
  for _, f in ipairs(td:get_fields()) do
    local l = f:get_name():lower()
    for _, p in ipairs(pats) do if l:find(p) then out[#out+1] = tn .. " field " .. f:get_name() .. ":" .. tostring(f:get_type():get_full_name()); break end end
  end
end
scan("app.Human", { "lantern" })
scan("app.Character", { "lantern" })
scan("app.ItemManager", { "lantern" })
scan("app.LanternController", { "." })
scan("app.ui020401", { "lantern" })
local D = _G.DPC_dbg
if D and D.state.pawn_chara then
  local hu = D.state.pawn_chara:call("get_Human")
  for _, m in ipairs({ "get_LanternCtrl", "get_LanternController", "get_IsLanternOn", "get_Lantern" }) do
    local ok, v = pcall(hu.call, hu, m); out[#out+1] = "pawn Human:" .. m .. " = " .. tostring(ok and v)
  end
end
return table.concat(out, "\n")
