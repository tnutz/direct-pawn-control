local out = {}
local cm = sdk.get_managed_singleton("app.CharacterManager")
local ar = cm:call("get_ManualPlayer")
local hu = ar:call("get_Human")
local jp = hu:call("get_Param"):call("get_Job")
local j8 = nil
for _, f in ipairs(jp:get_type_definition():get_fields()) do
  local v = jp:get_field(f:get_name())
  local tn = ""; pcall(function() tn = v:get_type_definition():get_full_name() end)
  if tn == "app.Job08Parameter" then j8 = v end
end
if not j8 then
  for _, m in ipairs(jp:get_type_definition():get_methods()) do
    local ok, rt = pcall(function() return m:get_return_type():get_full_name() end)
    if ok and rt == "app.Job08Parameter" then j8 = jp:call(m:get_name()) end
  end
end
if not j8 then return "no job08 param" end
local function dump(o, label, depth)
  if not o or depth > 2 then return end
  for _, f in ipairs(o:get_type_definition():get_fields()) do
    local v = o:get_field(f:get_name())
    if type(v) == "userdata" then
      local tn = ""; pcall(function() tn = v:get_type_definition():get_full_name() end)
      if tn:find("^app%.Job08Parameter") and not tn:find("%[%]") then dump(v, label .. "." .. f:get_name(), depth + 1) else out[#out+1] = label .. "." .. f:get_name() .. " = <" .. tn .. ">" end
    else out[#out+1] = label .. "." .. f:get_name() .. " = " .. tostring(v) end
  end
end
dump(j8:get_field("LifeReturnParam"), "LR", 0)
out[#out+1] = "PlayChargedMotionFrame=" .. tostring(j8:get_field("PlayChargedMotionFrame")) .. " FirstLockOnFrame=" .. tostring(j8:get_field("FirstLockOnFrame"))
pcall(function() out[#out+1] = "now: prepared " .. tostring(hu:call("get_IsSkillPrepared")) .. " preparing " .. tostring(hu:call("get_IsSkillPreparing")) .. " rate " .. tostring(hu:call("get_RatePrepareSkill")) .. " timer " .. tostring(hu:call("get_TimerPrepareSkill")) end)
return table.concat(out, "\n")
