local out = {}
local cm = sdk.get_managed_singleton("app.CharacterManager")
local pl = cm:call("get_ManualPlayer")
local hu = pl:call("get_Human")
local function sig(m)
  local ps = {}
  pcall(function() for _, pt in ipairs(m:get_param_types()) do ps[#ps+1] = pt:get_full_name() end end)
  local rt = ""; pcall(function() rt = m:get_return_type():get_full_name() end)
  return m:get_name() .. "(" .. table.concat(ps, ",") .. ")->" .. rt
end
out[#out+1] = "job=" .. tostring(pl:call("get_Job") or hu:call("get_Job"))
for _, m in ipairs(hu:get_type_definition():get_methods()) do
  local l = m:get_name():lower()
  if l:find("job08") or l:find("magic") or l:find("jobcontext") or l:find("actioncontroller") then out[#out+1] = "Human." .. sig(m) end
end
local function dump(tag, o)
  if not o then out[#out+1] = tag .. " nil"; return end
  local t = o:get_type_definition()
  out[#out+1] = "== " .. tag .. " : " .. t:get_full_name()
  while t and t:get_full_name() ~= "System.Object" and not t:get_full_name():find("^via%.") do
    local ms = {}
    for _, m in ipairs(t:get_methods()) do ms[#ms+1] = sig(m) end
    out[#out+1] = " M(" .. t:get_name() .. "): " .. table.concat(ms, "  ")
    for _, f in ipairs(t:get_fields()) do if not f:is_static() then
      local ok, v = pcall(function() return o:get_field(f:get_name()) end)
      local s = tostring(ok and v); if ok and type(v) == "userdata" then pcall(function() s = v:get_type_definition():get_full_name() end) end
      out[#out+1] = "  F " .. f:get_name() .. " = " .. s
    end end
    t = t:get_parent_type()
  end
end
for _, g in ipairs({ "get_Job08ActionController", "get_Job08ActionCtrl", "get_Job08Context", "get_JobContext" }) do
  local ok, v = pcall(hu.call, hu, g)
  if ok and v then dump(g, v) end
end
return table.concat(out, "\n")
