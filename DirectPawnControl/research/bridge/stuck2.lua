local out = {}
local function sig(m)
  local ps = {}
  pcall(function() for _, pt in ipairs(m:get_param_types()) do ps[#ps+1] = pt:get_full_name() end end)
  return m:get_name() .. "(" .. table.concat(ps, ",") .. ")"
end
local function scan(tn, pats, inst)
  local t = sdk.find_type_definition(tn); if not t then out[#out+1] = tn .. "=nil"; return end
  local ms = {}
  for _, m in ipairs(t:get_methods()) do local l = m:get_name():lower()
    for _, p in ipairs(pats) do if l:find(p) then ms[#ms+1] = sig(m); break end end end
  out[#out+1] = tn .. " M: " .. table.concat(ms, "  ")
  for _, f in ipairs(t:get_fields()) do local l = f:get_name():lower()
    for _, p in ipairs(pats) do if l:find(p) then
      local v = ""
      if inst then local ok, x = pcall(function() return inst:get_field(f:get_name()) end); if ok then v = " = " .. tostring(x) end end
      out[#out+1] = "  F " .. f:get_name() .. ":" .. f:get_type():get_full_name() .. v; break end end end
end
local D = _G.DPC_dbg
local ch = D and D.state.pawn_chara
local nav = ch and ch:call("get_NavigationController")
scan("app.PawnNavigationController", { "." }, nav)
scan("app.NavigationController", { "." }, nav)
scan("app.Pawn", { "guide", "concierge", "order", "lead", "navi", "talk", "request", "state" }, D and D.state.pawn_obj)
scan("app.AIBlackBoardController", { "req", "actinter", "pack", "clear", "reset" })
scan("app.HumanActionSelector", { "request", "cancel", "isenable", "end" })
scan("app.PawnManager", { "guide", "concierge", "lead", "navi" })
if ch then
  pcall(function()
    local bb = ch:call("get_AIBlackBoardController")
    local function p(tag, o) local s = "nil"; if o then s = o:get_type_definition():get_full_name(); pcall(function() s = s .. " " .. tostring(o:call("get_Path")) end) end; out[#out+1] = tag .. " = " .. s end
    p("ReqMain", bb:call("get_ReqMainActInterPackData")); p("ReqSub", bb:call("get_ReqSubActInterPackData"))
  end)
end
return table.concat(out, "\n")
