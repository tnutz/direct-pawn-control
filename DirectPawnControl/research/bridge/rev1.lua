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
  if okf and fs then for _, f in ipairs(fs) do local l = f:get_name():lower(); for _, p in ipairs(pats) do if l:find(p) then out[#out+1] = tn .. " field " .. f:get_name() .. ":" .. tostring(f:get_type():get_full_name()); break end end end end
end
local pats = { "revive", "resurrect", "rescue", "dying", "helpup", "reraise", "isdown", "downed", "lostpawn", "dead", "isdie", "isdying" }
scan("app.Character", pats)
scan("app.Human", pats)
scan("app.Pawn", pats)
scan("app.HitController", pats)
scan("app.PawnManager", pats)
scan("app.InteractManager", { "rescue", "revive", "help" })
local pm = sdk.get_managed_singleton("app.PawnManager")
local list = pm:call("get_PawnCharacterList")
local n = list:call("get_Count")
for i = 0, n - 1 do
  local c = list:call("get_Item", i)
  local hit = c:call("get_Hit")
  local nm = c:call("get_GameObject"):call("get_Name")
  local fsm = c:call("get_ActionManager"):get_field("Fsm")
  local r = { tostring(nm), "hp=" .. tostring(hit:call("get_Hp")), "node=" .. tostring(fsm:call("getCurrentNodeName(System.UInt32)", 0)) }
  for _, m in ipairs({ "get_IsDead", "get_IsDying", "isDead", "get_IsDown", "get_IsRescueWait", "get_IsLost" }) do
    local ok, v = pcall(c.call, c, m); if ok and v ~= nil then r[#r+1] = m .. "=" .. tostring(v) end
    local ok2, v2 = pcall(hit.call, hit, m); if ok2 and v2 ~= nil then r[#r+1] = "Hit." .. m .. "=" .. tostring(v2) end
  end
  out[#out+1] = table.concat(r, " ")
end
return table.concat(out, "\n")
