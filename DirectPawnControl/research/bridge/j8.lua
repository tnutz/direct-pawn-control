local out = {}
local cm = sdk.get_managed_singleton("app.CharacterManager")
local ar = cm:call("get_ManualPlayer")
local jc = ar:call("get_Human"):call("get_Job08ActionCtrl")
local t = jc:get_type_definition()
local fs = {}
for _, f in ipairs(t:get_fields()) do
  if not f:is_static() then
    local v = nil; pcall(function() v = jc:get_field(f:get_name()) end)
    local d = tostring(v)
    if type(v) == "userdata" then pcall(function() d = v:get_type_definition():get_full_name() end) end
    fs[#fs+1] = f:get_name() .. "=" .. d
  end
end
out[#out+1] = "F: " .. table.concat(fs, " | ")
local ms = {}
for _, m in ipairs(t:get_methods()) do ms[#ms+1] = m:get_name() end
out[#out+1] = "M: " .. table.concat(ms, " ")
for _, tn in ipairs({ "app.Job08Parameter", "app.Job08Parameter.LifeReturnParameter", "app.Job08LifeReturnParameter", "app.Job08Parameter.LifeReturnParam" }) do
  local p = sdk.find_type_definition(tn)
  if p then
    local pf = {}
    for _, f in ipairs(p:get_fields()) do pf[#pf+1] = f:get_name() .. ":" .. f:get_type():get_name() end
    out[#out+1] = tn .. ": " .. table.concat(pf, " | ")
  end
end
return table.concat(out, "\n")
