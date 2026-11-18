local out = {}
local D = _G.DPC_dbg
local S = D.state
local ar = S.arisen_chara
local function pos(c) local p = c:call("get_GameObject"):call("get_Transform"):call("get_Position"); return p end
local ap = ar and pos(ar)
out[#out+1] = "active=" .. tostring(S.active)
local pm = sdk.get_managed_singleton("app.PawnManager")
local l = pm:call("get_PawnCharacterList")
local n = l:call("get_Count")
for i = 0, n - 1 do
  local ch = l:call("get_Item", i)
  local s = tostring(ch:call("get_GameObject"):call("get_Name"))
  for _, m in ipairs({ "get_IsDead", "get_IsDown", "get_Hp", "get_IsDying", "get_IsPawnDown", "get_IsWaitRevive" }) do
    local ok, v = pcall(ch.call, ch, m); if ok and v ~= nil then s = s .. " " .. m .. "=" .. tostring(v) end
  end
  pcall(function() local hit = ch:call("get_Hit"); s = s .. " hit.hp=" .. tostring(hit:call("get_Hp")) .. " hit.dead=" .. tostring(hit:call("get_IsDie")) end)
  pcall(function() local p = pos(ch); s = s .. string.format(" d=%.1f", math.sqrt((p.x-ap.x)^2+(p.z-ap.z)^2)) end)
  pcall(function() local fsm = ch:call("get_ActionManager"):get_field("Fsm"); s = s .. " node=" .. tostring(fsm:call("getCurrentNodeName(System.UInt32)", 0)) end)
  pcall(function() local pw = pm:call("getPartyPawn(app.Character, System.Boolean)", ch, false); s = s .. " pawnState=" .. tostring(pw and pw:call("get_State")) end)
  out[#out+1] = s
end
pcall(function()
  local hu = ar:call("get_Human")
  local sc = hu:call("get_SkillContext")
  out[#out+1] = "arisen node=" .. tostring(ar:call("get_ActionManager"):get_field("Fsm"):call("getCurrentNodeName(System.UInt32)", 0)) .. " | " .. tostring(ar:call("get_ActionManager"):get_field("Fsm"):call("getCurrentNodeName(System.UInt32)", 1))
end)
return table.concat(out, "\n")
