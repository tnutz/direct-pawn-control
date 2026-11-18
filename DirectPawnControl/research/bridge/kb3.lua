local out = {}
local uim = sdk.get_managed_singleton("app.UserInputManager")
local kb = uim:get_field("<KeyBindController>k__BackingField")
local function fdump(o)
  local s = {}
  local t = o:get_type_definition()
  for _, f in ipairs(t:get_fields()) do
    if not f:is_static() then
      local v = nil; pcall(function() v = o:get_field(f:get_name()) end)
      local d = tostring(v)
      if type(v) == "userdata" then
        local ok, str = pcall(function() return v:call("ToString") end)
        d = (ok and str and tostring(str)) or "ud"
        pcall(function() d = v:get_type_definition():get_full_name() .. ":" .. d end)
      end
      s[#s+1] = f:get_name():gsub("k__BackingField", "") .. "=" .. d
    end
  end
  return table.concat(s, ", ")
end
local ok, err = pcall(function()
  local tbl = kb:call("getCurrentKeyBindSettingTable")
  out[#out+1] = "table " .. tbl:get_type_definition():get_full_name() .. " count " .. tostring(tbl:call("get_Count"))
  local en = tbl:call("GetEnumerator")
  local i = 0
  while en:call("MoveNext") and i < 110 do
    i = i + 1
    local kv = en:call("get_Current")
    local k, v = kv:get_field("key"), kv:get_field("value")
    if i == 1 then
      local t = v:get_type_definition()
      local fs = {}
      for _, f in ipairs(t:get_fields()) do fs[#fs+1] = f:get_name() .. ":" .. f:get_type():get_full_name() end
      out[#out+1] = "item type " .. t:get_full_name() .. " F: " .. table.concat(fs, " | ")
      local ms = {}
      for _, m in ipairs(t:get_methods()) do ms[#ms+1] = m:get_name() end
      out[#out+1] = "item M: " .. table.concat(ms, " ")
    end
    out[#out+1] = tostring(k) .. " -> " .. fdump(v)
  end
end)
if not ok then out[#out+1] = "err " .. tostring(err) end
return table.concat(out, "\n")
