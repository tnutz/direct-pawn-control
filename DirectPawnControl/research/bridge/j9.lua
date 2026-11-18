local out = {}
local function tf(tn)
  local p = sdk.find_type_definition(tn)
  if not p then out[#out+1] = tn .. " none"; return end
  local pf = {}
  for _, f in ipairs(p:get_fields()) do pf[#pf+1] = f:get_name() .. ":" .. f:get_type():get_full_name() end
  out[#out+1] = tn .. ": " .. table.concat(pf, " | ")
end
tf("app.Job08Parameter.LifeReturnParameter.ChargeArrowParameter")
tf("app.Job08Parameter.ChargeArrowParameter")
tf("app.Job08Parameter.LifeReturnParameter.MultiParam")
tf("app.Job08Parameter.MultiParam")
tf("app.Job08Parameter.AimArrowParameter")
tf("app.Job08Parameter.JustReleaseParameter")
-- find an instance
local cm = sdk.get_managed_singleton("app.CharacterManager")
local ar = cm:call("get_ManualPlayer")
local hu = ar:call("get_Human")
local found = nil
local function scan(o, label)
  if not o then return end
  local t = o:get_type_definition()
  while t and t:get_full_name() ~= "System.Object" do
    for _, m in ipairs(t:get_methods()) do
      local ok, rt = pcall(function() return m:get_return_type():get_full_name() end)
      if ok and (rt == "app.Job08Parameter" or rt == "app.HumanParameter" or rt:find("JobParameter") or rt:find("Job08Parameter")) and #m:get_param_types() == 0 then
        out[#out+1] = label .. "." .. m:get_name() .. " -> " .. rt
        if rt == "app.Job08Parameter" and not found then local ok2, v = pcall(o.call, o, m:get_name()); if ok2 then found = v end end
      end
    end
    t = t:get_parent_type()
  end
end
scan(hu, "Human"); scan(ar, "Character"); scan(cm, "CharacterManager"); scan(hu:call("get_Job08ActionCtrl"), "J8Ctrl")
pcall(function() scan(hu:call("get_Param"), "HumanParam") end)
if found then
  local lr = found:get_field("LifeReturnParam")
  local function dump(o, label, depth)
    if not o or depth > 2 then return end
    for _, f in ipairs(o:get_type_definition():get_fields()) do
      local v = o:get_field(f:get_name())
      if type(v) == "userdata" then
        local tn = ""; pcall(function() tn = v:get_type_definition():get_full_name() end)
        if tn:find("^app%.") then dump(v, label .. "." .. f:get_name(), depth + 1) else out[#out+1] = label .. "." .. f:get_name() .. " = <" .. tn .. ">" end
      else out[#out+1] = label .. "." .. f:get_name() .. " = " .. tostring(v) end
    end
  end
  dump(lr, "LifeReturn", 0)
  out[#out+1] = "PlayChargedMotionFrame=" .. tostring(found:get_field("PlayChargedMotionFrame")) .. " FirstLockOnFrame=" .. tostring(found:get_field("FirstLockOnFrame"))
end
return table.concat(out, "\n")
