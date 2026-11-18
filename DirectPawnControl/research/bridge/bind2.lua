local out = {}
local uim = sdk.get_managed_singleton("app.UserInputManager")
local pa = uim:call("getCurrentCharacterPadAssign")
out[#out+1] = "current=" .. tostring(pa)
pa = pa or uim:get_field("CharacterPadAssign")
out[#out+1] = "field=" .. tostring(pa)
if not pa then pa = uim:call("getCharacterPadAssign(System.Int32)", 0); out[#out+1] = "idx0=" .. tostring(pa) end
if not pa then pa = uim:call("getDefaultCharacterPadAssign"); out[#out+1] = "default=" .. tostring(pa) end
if not pa then return table.concat(out, "\n") end
local function fields(o, tag)
  if not o then out[#out+1] = tag .. " nil"; return end
  local t = o:get_type_definition()
  out[#out+1] = tag .. " : " .. t:get_full_name()
  local ms = {}
  for _, m in ipairs(t:get_methods()) do ms[#ms+1] = m:get_name() end
  out[#out+1] = "  M: " .. table.concat(ms, " ")
  for _, f in ipairs(t:get_fields()) do
    local ok, v = pcall(function() return o:get_field(f:get_name()) end)
    local s = tostring(ok and v); if ok and type(v) == "userdata" then pcall(function() s = v:get_type_definition():get_full_name() end) end
    out[#out+1] = "  F " .. f:get_name() .. ":" .. f:get_type():get_full_name() .. " = " .. s
  end
end
fields(pa, "current")
local function dumplist(l, tag)
  if not l then return end
  local n = l:call("get_Count")
  out[#out+1] = tag .. " count=" .. tostring(n)
  for i = 0, n - 1 do
    local it = l:call("get_Item", i)
    if not it then pcall(function() it = l[i] end) end
    if i == 0 then fields(it, "Info[0]") end
    local s = ""
    if not it then out[#out+1] = "  " .. i .. ": nil" goto continue end
    for _, f in ipairs(it:get_type_definition():get_fields()) do
      local ok, v = pcall(function() return it:get_field(f:get_name()) end)
      if ok and type(v) ~= "userdata" then s = s .. " " .. f:get_name():gsub("k__BackingField", "") .. "=" .. tostring(v)
      elseif ok and v then
        local okc, c = pcall(function() return v:call("get_Count") end)
        if okc and c then local e = {}; for j = 0, c - 1 do e[#e+1] = tostring(v:call("get_Item", j)) end; s = s .. " " .. f:get_name() .. "=[" .. table.concat(e, ",") .. "]" end
      end
    end
    out[#out+1] = "  " .. i .. ":" .. s
    ::continue::
  end
end
for _, f in ipairs(pa:get_type_definition():get_fields()) do
  local ok, v = pcall(function() return pa:get_field(f:get_name()) end)
  if ok and v and type(v) == "userdata" then
    local okc = pcall(function() return v:call("get_Count") end)
    if okc then dumplist(v, f:get_name()) end
  end
end
return table.concat(out, "\n")
