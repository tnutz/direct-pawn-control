local out = {}
local D = _G.DPC_dbg
local S, R = D.state, D.R
local function cid(c) local s = "?"; pcall(function() s = tostring(c:call("get_CharaIDString")) .. "/" .. tostring(c:call("get_GameObject"):call("get_Name")) end); return s end
local function pos(c) local p = c:call("get_GameObject"):call("get_Transform"):call("get_Position"); return p end
out[#out+1] = "active=" .. tostring(S.active) .. " pawn=" .. tostring(S.pawn_name) .. " coop=" .. tostring(D.native and D.native.lock ~= nil)
local pw = S.pawn_chara
local pp = pw and pos(pw)
local function lockinfo(tag, lk)
  if not lk then out[#out+1] = tag .. " nil"; return end
  local s = tag .. ":"
  pcall(function() s = s .. " Chara=" .. cid(lk:get_field("Chara")) end)
  pcall(function()
    local t = lk:call("get_Target")
    if not t then s = s .. " target=nil"; return end
    s = s .. " target=" .. t:get_type_definition():get_full_name()
    for _, f in ipairs(t:get_type_definition():get_fields()) do
      local ok, v = pcall(function() return t:get_field(f:get_name()) end)
      if ok and type(v) == "userdata" then
        local d = ""; pcall(function() d = v:get_type_definition():get_full_name() end)
        pcall(function() d = d .. " " .. cid(v) end)
        pcall(function() d = d .. " go=" .. tostring(v:call("get_GameObject"):call("get_Name")) end)
        s = s .. "\n    " .. f:get_name() .. "=" .. d
      elseif ok then s = s .. "\n    " .. f:get_name() .. "=" .. tostring(v) end
    end
  end)
  out[#out+1] = s
  local t = lk:get_type_definition(); local fs = {}
  for _, f in ipairs(t:get_fields()) do local ok, v = pcall(function() return lk:get_field(f:get_name()) end)
    if ok and (type(v) == "boolean" or type(v) == "number") then fs[#fs+1] = f:get_name() .. "=" .. tostring(v) end end
  out[#out+1] = "  " .. table.concat(fs, " ")
end
lockinfo("arisen_lock", S.arisen_lockon_ctrl)
if D.native and D.native.lock then lockinfo("native.lock", D.native.lock) end
local em = sdk.get_managed_singleton("app.EnemyManager")
local arr = em and em:call("getAllEnemies")
local n = arr and arr:call("get_Count") or 0
out[#out+1] = "enemies=" .. n
for i = 0, math.min(n, 30) - 1 do pcall(function()
  local e = arr[i]:get_field("_Chara")
  local p = pos(e); local d = pp and math.sqrt((p.x-pp.x)^2 + (p.z-pp.z)^2) or -1
  local hp = "?"; pcall(function() hp = tostring(e:call("get_Hit"):call("get_Hp")) end)
  if d < 40 then out[#out+1] = string.format("  e %s d=%.1f hp=%s", cid(e), d, hp) end
end) end
-- nearby non-enemy characters
pcall(function()
  local cm = sdk.get_managed_singleton("app.CharacterManager")
  for _, m in ipairs({ "get_NpcCharacterList", "get_NPCList", "get_HumanList" }) do
    local ok, l = pcall(cm.call, cm, m)
    if ok and l then
      local c = l:call("get_Count"); out[#out+1] = m .. " count=" .. tostring(c)
      for i = 0, c - 1 do pcall(function()
        local ch = l:call("get_Item", i); local p = pos(ch); local d = math.sqrt((p.x-pp.x)^2 + (p.z-pp.z)^2)
        if d < 15 then out[#out+1] = string.format("  npc %s d=%.1f", cid(ch), d) end
      end) end
    end
  end
end)
return table.concat(out, "\n")
