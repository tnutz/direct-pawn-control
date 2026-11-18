local out = {}
local pm = sdk.get_managed_singleton("app.PawnManager")
local lst = pm:call("get_PawnCharacterList")
local ch = nil
for i = 0, lst:call("get_Count") - 1 do
  local c = lst:call("get_Item", i)
  local okn, nm = pcall(function() return c:call("get_CharaIDString") end)
  out[#out+1] = i .. " " .. tostring(nm) .. " hp " .. tostring(c:call("get_Hp")) .. " dead " .. tostring(c:call("get_IsDead"))
  ch = ch or c
end
local hit = ch:call("get_Hit")
local t = hit:get_type_definition()
local gs = {}
for _, m in ipairs(t:get_methods()) do
  local n = m:get_name(); local l = n:lower()
  if (n:find("^get_") or n:find("^is")) and (l:find("nodie") or l:find("invinc") or l:find("immort") or l:find("nodamage") or l:find("dead") or l:find("die") or l:find("minhp") or l:find("guts") or l:find("lowerlimit")) then
    local np = 0; pcall(function() np = #m:get_param_types() end)
    local v = ""
    if np == 0 then local ok, x = pcall(hit.call, hit, n); if ok then v = "=" .. tostring(x) end end
    gs[#gs+1] = n .. "/" .. np .. v
  end
end
out[#out+1] = "hit getters: " .. table.concat(gs, " ")
local fs = {}
for _, f in ipairs(t:get_fields()) do
  local l = f:get_name():lower()
  if l:find("die") or l:find("dead") or l:find("invinc") or l:find("nodamage") or l:find("hp") then
    local v = nil; pcall(function() v = hit:get_field(f:get_name()) end)
    fs[#fs+1] = f:get_name() .. "=" .. tostring(v)
  end
end
out[#out+1] = "hit fields: " .. table.concat(fs, " | ")
local ms = {}
for _, m in ipairs(sdk.find_type_definition("app.Character"):get_methods()) do
  local n = m:get_name(); local l = n:lower()
  if l:find("dieaction") or l:find("requestdie") or l:find("todead") or l:find("setdead") or l:find("startdie") or l:find("ondie") or l:find("dying") or l:find("ondead") then ms[#ms+1] = n end
end
out[#out+1] = "chara: " .. table.concat(ms, " ")
ms = {}
for _, tn in ipairs({ "app.HumanActionSelector", "app.Pawn" }) do
  for _, m in ipairs(sdk.find_type_definition(tn):get_methods()) do
    local n = m:get_name(); local l = n:lower()
    if l:find("die") or l:find("dead") or l:find("dying") or l:find("faint") or l:find("rescue") or l:find("wait") and l:find("help") then ms[#ms+1] = tn:sub(5) .. "." .. n end
  end
end
out[#out+1] = table.concat(ms, " ")
return table.concat(out, "\n")
