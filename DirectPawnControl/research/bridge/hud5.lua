-- re-run the guide's own skill setup (what the mod does at take-over) and read the cached skill ids before/after each step
local out = {}
local gm = sdk.get_managed_singleton("app.GuiManager")
local g = gm:get_field("KeyGuide")
local names = {}
for _, f in ipairs(sdk.find_type_definition("app.HumanCustomSkillID"):get_fields()) do if f:is_static() then names[f:get_data(nil)] = f:get_name() end end
local function ids(tag)
  local a = g:get_field("CustomSkillId"); local p = {}
  for i = 0, a:call("get_Length") - 1 do local e = a:call("Get", i); local v = e; pcall(function() v = e:get_field("value__") end); p[#p+1] = tostring(names[v] or v) end
  out[#out+1] = tag .. ": " .. table.concat(p, ", ")
end
ids("before")
local ok, e = pcall(function() g:call("setupCustomSkillMsgId") end); ids("after setupCustomSkillMsgId ok=" .. tostring(ok))
ok, e = pcall(function() g:call("setupCustomSkillButton(System.Boolean)", true) end); ids("after setupCustomSkillButton ok=" .. tostring(ok) .. " " .. tostring(e))
return table.concat(out, "\n")
