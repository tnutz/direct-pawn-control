-- read-only: the last lock-on request of the played pawn's input processor and of the Arisen's
local out = {}
local D = _G.DPC_dbg
local st, nat = D.state, D.native
local function req(tag, param)
  if not param then out[#out+1] = tag .. ": no param"; return end
  local r = param:get_field("PrevLockOnRequestParam")
  if not r then out[#out+1] = tag .. ": no request"; return end
  out[#out+1] = string.format("%s: Job=%s ActionType=%s ActionID=%s Skill=%s air=%s", tag, tostring(r:call("get_Job")), tostring(r:call("get_ActionType")),
    tostring(r:call("get_ActionID")), tostring(r:call("get_CustomSkillID")), tostring(r:call("get_IsUseOnAir")))
  local lk = param:get_field("LockOnCtrl")
  if lk then
    local ch = lk:get_field("Chara")
    out[#out+1] = string.format("%s lock %x Chara %s targets %s", tag, lk:get_address(), tostring(ch and ch:call("get_GameObject"):call("get_Name")), tostring(lk:call("get_NumTarget")))
  end
end
out[#out+1] = "active " .. tostring(st.active) .. " pawn " .. tostring(st.pawn_name) .. " job " .. tostring(st.pawn_job) .. " drive " .. tostring(nat and nat.drive)
pcall(function() req("pawn pip", nat.param or (nat.pip and nat.pip:get_field("Param"))) end)
pcall(function() req("arisen pip", st.arisen_pip:get_field("Param")) end)
pcall(function()
  local jc = st.arisen_human:call("get_JobContext")
  out[#out+1] = "arisen JobContext get_Job=" .. tostring(jc:call("get_Job")) .. " field=" .. tostring(jc:get_field("CurrentJob"))
  local pj = st.pawn_human:call("get_JobContext")
  out[#out+1] = "pawn JobContext get_Job=" .. tostring(pj:call("get_Job")) .. " field=" .. tostring(pj:get_field("CurrentJob"))
end)
return table.concat(out, "\n")
