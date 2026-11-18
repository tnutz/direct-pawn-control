local out = {}
local function sig(m)
  local ps = {}
  pcall(function() for _, pt in ipairs(m:get_param_types()) do ps[#ps+1] = pt:get_full_name() end end)
  local rt = ""; pcall(function() rt = m:get_return_type():get_full_name() end)
  return m:get_name() .. "(" .. table.concat(ps, ",") .. ")->" .. rt
end
local function meths(tn, pat)
  local t = sdk.find_type_definition(tn); if not t then out[#out+1] = tn .. "=nil"; return end
  while t and t:get_full_name() ~= "System.Object" and t:get_full_name() ~= "via.Behavior" do
    for _, m in ipairs(t:get_methods()) do if not pat or m:get_name():lower():find(pat) then out[#out+1] = t:get_name() .. "." .. sig(m) end end
    for _, f in ipairs(t:get_fields()) do if not pat or f:get_name():lower():find(pat) then out[#out+1] = t:get_name() .. " F " .. f:get_name() .. ":" .. f:get_type():get_full_name() end end
    t = t:get_parent_type()
  end
end
meths("app.HumanLanternController")
meths("app.PawnManager.PawnLanternInfo")
meths("app.PawnManager", "lantern")
meths("app.Pawn", "lantern")
meths("app.HumanActionSelector", "lantern")
local function st(tag, ch)
  local ok, e = pcall(function()
    local lc = ch:call("get_Human"):call("get_LanternCtrl")
    local s = tag .. ": on=" .. tostring(lc:call("get_IsLanternOn")) .. " cond=" .. tostring(lc:call("isTurnOnCondition"))
    local t = lc:get_type_definition()
    while t and t:get_full_name() ~= "System.Object" do
      for _, f in ipairs(t:get_fields()) do
        local okv, v = pcall(function() return lc:get_field(f:get_name()) end)
        if okv and (type(v) == "boolean" or type(v) == "number") then s = s .. " " .. f:get_name() .. "=" .. tostring(v) end
      end
      t = t:get_parent_type()
    end
    out[#out+1] = s
  end)
  if not ok then out[#out+1] = tag .. " err " .. tostring(e) end
end
local cm = sdk.get_managed_singleton("app.CharacterManager")
local pl = cm and cm:call("get_ManualPlayer")
if pl then st("arisen", pl) end
local pm = sdk.get_managed_singleton("app.PawnManager")
if pm then
  local ok, e = pcall(function()
    local l = pm:call("get_PawnCharacterList")
    local n = l:call("get_Count")
    for i = 0, n - 1 do
      local ch = l:call("get_Item", i)
      st("pawn" .. i .. " " .. tostring(ch:call("get_GameObject"):call("get_Name")), ch)
      local pw = pm:call("getPartyPawn(app.Character, System.Boolean)", ch, false)
      if pw then
        local info = pw:get_field("PawnLanternInfo")
        if info then
          local s = "  info:"
          for _, f in ipairs(info:get_type_definition():get_fields()) do s = s .. " " .. f:get_name() .. "=" .. tostring(info:get_field(f:get_name())) end
          out[#out+1] = s
        end
      end
    end
  end)
  if not ok then out[#out+1] = "pm err " .. tostring(e) end
end
local D = _G.DPC_dbg
out[#out+1] = "active=" .. tostring(D and D.state.active)
return table.concat(out, "\n")
