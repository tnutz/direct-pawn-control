-- read-only: the game's lock-on range table for the played pawn's vocation and the Arisen's, and the shared controller's state
local out = {}
local D = _G.DPC_dbg
local st = D.state
local names = {}
for _, f in ipairs(sdk.find_type_definition("app.HumanCustomSkillID"):get_fields()) do if f:is_static() then names[f:get_data(nil)] = f:get_name() end end
local AT = { [0] = "Default", "NormalAttack", "SubNormalAttack", "CustomSkill", "Special" }
local lk = D.native and D.native.lock
out[#out+1] = "active " .. tostring(st.active) .. " pawn " .. tostring(st.pawn_name) .. " job " .. tostring(st.pawn_job)
local ajob
pcall(function() ajob = st.arisen_human:call("get_JobContext"):get_field("CurrentJob") end)
out[#out+1] = "arisen job (field) " .. tostring(ajob)
if not lk then
  pcall(function() lk = st.arisen_pip:get_field("Param"):get_field("LockOnCtrl") end)
end
if not lk then return table.concat(out, "\n") .. "\nno lock controller" end
pcall(function()
  local ch = lk:get_field("Chara")
  out[#out+1] = "lock Chara " .. tostring(ch and ch:call("get_GameObject"):call("get_Name")) .. " targets " .. tostring(lk:call("get_NumTarget")) .. " keep " .. tostring(lk:get_field("MaxDistanceKeepLockOn"))
  local tw = lk:call("get_Target")
  out[#out+1] = "target " .. tostring(tw and tw:get_type_definition():get_name())
end)
local pl = lk:call("get_ParamList")
local arr = pl:get_field("Parameters")
for i = 0, arr:call("get_Length") - 1 do
  local jp = arr:call("Get", i)
  local job = jp:get_field("Job")
  if job == st.pawn_job or job == ajob or job == 2 then
    local tps = jp:get_field("Parameters")
    for k = 0, tps:call("get_Length") - 1 do
      local tp = tps:call("Get", k)
      local sk = tp:get_field("CustomSkillID")
      local p = { "job" .. tostring(job), AT[tp:get_field("ActionType")] or "?", "act=" .. tostring(tp:get_field("ActionID")), tostring(tp:get_field("ActionIDComment")),
        "skill=" .. tostring(names[sk] or sk), "max=" .. tostring(tp:get_field("MaxDistance")), "cam=" .. tostring(tp:get_field("IsBasedOnCamera")), "dis=" .. tostring(tp:get_field("IsDisable")) }
      local rs = tp:get_field("Ranges")
      if rs then
        for r = 0, rs:call("get_Length") - 1 do
          local rg = rs:call("Get", r)
          p[#p+1] = string.format("[d=%s ang=%s nolever=%s dis=%s]", tostring(rg:get_field("Distance")), tostring(rg:get_field("AngleDegRange")), tostring(rg:get_field("IsForNoLeverInput")), tostring(rg:get_field("IsDisable")))
        end
      end
      out[#out+1] = table.concat(p, " ")
    end
  end
end
return table.concat(out, "\n")
