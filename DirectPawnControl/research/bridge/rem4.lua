local out = {}
local D = _G.DPC_dbg
local S = D.state
local ar = S.arisen_chara
local pm = sdk.get_managed_singleton("app.PawnManager")
local l = pm:call("get_PawnCharacterList")
local ap = ar:call("get_GameObject"):call("get_Transform"):call("get_Position")
out[#out+1] = string.format("arisen pos %.2f %.2f %.2f", ap.x, ap.y, ap.z)
local lk = S.arisen_lockon_ctrl
pcall(function()
  local c = lk:get_field("Chara"); local t = lk:call("get_Target")
  out[#out+1] = "lock Chara=" .. tostring(c and c:call("get_GameObject"):call("get_Name")) .. " target=" .. tostring(t) .. " num=" .. tostring(lk:call("get_NumTarget"))
  if t then
    for _, f in ipairs(t:get_type_definition():get_fields()) do
      local ok, v = pcall(function() return t:get_field(f:get_name()) end)
      local d = tostring(ok and v)
      if ok and type(v) == "userdata" then pcall(function() d = v:get_type_definition():get_full_name() end); pcall(function() d = d .. string.format(" (%.2f,%.2f,%.2f)", v.x, v.y, v.z) end); pcall(function() d = d .. " go=" .. tostring(v:call("get_GameObject"):call("get_Name")) end) end
      out[#out+1] = "   T." .. f:get_name() .. "=" .. d
    end
  end
end)
for i = 0, l:call("get_Count") - 1 do
  local ch = l:call("get_Item", i)
  if ch:call("get_IsDead") == true then
    local p = ch:call("get_GameObject"):call("get_Transform"):call("get_Position")
    out[#out+1] = string.format("DOWN %s pos %.2f %.2f %.2f d=%.1f", tostring(ch:call("get_GameObject"):call("get_Name")), p.x, p.y, p.z, math.sqrt((p.x-ap.x)^2+(p.z-ap.z)^2))
    local lt = ch:call("get_LockOnTarget")
    local w = lt:call("get_Works"):call("get_Item", 0)
    out[#out+1] = "  work=" .. tostring(w) .. " enable(lt.DisableControl)=" .. tostring(lt:get_field("DisableControl"))
    if w then
      local t = w:get_type_definition()
      local ms = {}
      for _, m in ipairs(t:get_methods()) do ms[#ms+1] = m:get_name() end
      out[#out+1] = "  W M: " .. table.concat(ms, " ")
      for _, f in ipairs(t:get_fields()) do
        local ok, v = pcall(function() return w:get_field(f:get_name()) end)
        local d = tostring(ok and v)
        if ok and type(v) == "userdata" then pcall(function() d = v:get_type_definition():get_full_name() end); pcall(function() d = d .. string.format(" (%.2f,%.2f,%.2f)", v.x, v.y, v.z) end) end
        out[#out+1] = "   W." .. f:get_name() .. "=" .. d
      end
      for _, g in ipairs({ "get_Position", "get_Pos", "getPosition", "get_LockOnPosition", "get_WorldPos" }) do
        local ok, v = pcall(w.call, w, g); if ok and v then pcall(function() out[#out+1] = string.format("   %s = %.2f %.2f %.2f", g, v.x, v.y, v.z) end) end
      end
      pcall(function() out[#out+1] = "  isTargetEnableLockOn=" .. tostring(lk:call("isTargetEnableLockOn(app.LockOnTargetWork)", w)) .. " tooFar=" .. tostring(lk:call("isTargetTooFar(app.LockOnTargetWork)", w)) .. " friend=" .. tostring(lk:call("isEnableFriendLockOn(app.Character)", ch)) end)
    end
  end
end
pcall(function()
  local fsm = ar:call("get_ActionManager"):get_field("Fsm")
  out[#out+1] = "arisen nodes " .. tostring(fsm:call("getCurrentNodeName(System.UInt32)", 0)) .. " | " .. tostring(fsm:call("getCurrentNodeName(System.UInt32)", 1))
  local c8 = ar:call("get_Human"):call("get_Job08ActionCtrl")
  local pt = c8:call("get_PrevTargetWithoutAim")
  out[#out+1] = "PrevTargetWithoutAim=" .. tostring(pt and pt:call("get_Name")) .. " prevSkill=" .. tostring(c8:call("get_PrevSkillIDWithoutAim"))
end)
return table.concat(out, "\n")
