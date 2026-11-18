-- read-only: per vocation, the longest lock-on distance of its Default / attack entries and of each skill entry
local out = {}
local D = _G.DPC_dbg
local st = D.state
local names = {}
for _, f in ipairs(sdk.find_type_definition("app.HumanCustomSkillID"):get_fields()) do if f:is_static() then names[f:get_data(nil)] = f:get_name() end end
local lk = (D.native and D.native.lock) or st.arisen_lockon_ctrl
if not lk then pcall(function() lk = st.arisen_pip:get_field("Param"):get_field("LockOnCtrl") end) end
if not lk then
  pcall(function() lk = sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayerPlayer"):call("get_LockOnCtrl") end)
end
if not lk then return "no lock controller" end
local arr = lk:call("get_ParamList"):get_field("Parameters")
local function longest(tp)
  local m, rs = 0, tp:get_field("Ranges")
  if rs then for i = 0, rs:call("get_Length") - 1 do local rg = rs:call("Get", i); local d = rg:get_field("Distance"); if rg:get_field("IsDisable") ~= true and d > m then m = d end end end
  return m
end
for i = 0, arr:call("get_Length") - 1 do
  local jp = arr:call("Get", i)
  local base, sk = 0, {}
  local tps = jp:get_field("Parameters")
  for k = 0, tps:call("get_Length") - 1 do
    local tp = tps:call("Get", k)
    local at, d = tp:get_field("ActionType"), longest(tp)
    if at == 3 then local id = tp:get_field("CustomSkillID"); sk[#sk+1] = tostring(names[id] or id):gsub("^Job%d+_", "") .. "=" .. tostring(d)
    elseif at ~= 4 and d > base then base = d end
  end
  out[#out+1] = "job " .. tostring(jp:get_field("Job")) .. " base " .. tostring(base) .. " | " .. table.concat(sk, ", ")
end
return table.concat(out, "\n")
