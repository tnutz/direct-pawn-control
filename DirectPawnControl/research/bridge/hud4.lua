-- read-only: whose skills the key guide holds, against the played pawn's and the Arisen's own
local out = {}
local D = _G.DPC_dbg
local st = D.state
local gm = sdk.get_managed_singleton("app.GuiManager")
local g = gm:get_field("KeyGuide")
local function a(o) return o and string.format("%x", o:get_address()) or "nil" end
local names = {}
for _, f in ipairs(sdk.find_type_definition("app.HumanCustomSkillID"):get_fields()) do if f:is_static() then names[f:get_data(nil)] = f:get_name() end end
local function skills(human, job)
  local sc = human:call("get_SkillContext") or human:call("get_HumanCustomSkillContext")
  local p = {}
  for slot = 0, 5 do local id = sc:call("getSkillID", job, slot); p[#p+1] = tostring(names[id] or id) end
  return a(sc) .. " job " .. tostring(job) .. ": " .. table.concat(p, ", ")
end
out[#out+1] = "active " .. tostring(st.active) .. " pawn " .. tostring(st.pawn_name) .. " pawn_job " .. tostring(st.pawn_job)
out[#out+1] = "guide PlChara " .. a(g:get_field("PlChara")) .. " PlHuman " .. a(g:get_field("PlHuman")) .. " ctx " .. a(g:get_field("SkillContext")) .. " Job " .. tostring(g:get_field("Job")) .. " WeaponJob " .. tostring(g:get_field("WeaponJob"))
out[#out+1] = "pawn chara " .. a(st.pawn_chara) .. " human " .. a(st.pawn_human) .. " arisen chara " .. a(st.arisen_chara) .. " human " .. a(st.arisen_human)
pcall(function() out[#out+1] = "pawn   skills " .. skills(st.pawn_human, st.pawn_job or 1) end)
pcall(function() local aj = st.arisen_human:call("get_JobContext"):call("get_Job") or st.arisen_human:call("get_JobContext"):get_field("CurrentJob"); out[#out+1] = "arisen skills " .. skills(st.arisen_human, aj) end)
local ids = g:get_field("CustomSkillId")
if ids then
  local p = {}
  local n = ids:call("get_Length") or ids:call("get_Count")
  for i = 0, n - 1 do local e = ids:call("Get", i); local v = e; pcall(function() v = e:get_field("value__") end); p[#p+1] = tostring(names[v] or v) end
  out[#out+1] = "guide CustomSkillId: " .. table.concat(p, ", ")
end
local sb = g:get_field("SkillBtnNo")
if sb then local p = {}; local n = sb:call("get_Length"); for i = 0, n - 1 do local e = sb:call("Get", i); local v = e; pcall(function() v = e:get_field("mValue") end); p[#p+1] = tostring(v) end; out[#out+1] = "SkillBtnNo: " .. table.concat(p, ",") end
out[#out+1] = "hud_repoints " .. tostring(D.R and D.R.hud_repoints)
return table.concat(out, "\n")
