local out = {}
local uim = sdk.get_managed_singleton("app.UserInputManager")
local t = uim:get_type_definition()
local act = {}
pcall(function()
  for _, f in ipairs(sdk.find_type_definition("app.CharacterInput.Action"):get_fields()) do
    if f:is_static() then local ok, v = pcall(f.get_data, f, nil); if ok and type(v) == "number" then act[v] = f:get_name() end end
  end
end)
local function dumpassign(pa, tag)
  local ok, err = pcall(function()
    local l = pa:get_field("AssignList") or pa:call("get_AssignList")
    local n = l:call("get_Count")
    local rows = {}
    for i = 0, n - 1 do
      local it = l:call("get_Item", i)
      local a = it:get_field("Action"); local b = it:get_field("Button"); local p = it:get_field("PreInput")
      rows[#rows+1] = (act[a] or tostring(a)) .. "=" .. tostring(b) .. (p and p ~= 0 and ("/pre" .. tostring(p)) or "")
    end
    out[#out+1] = tag .. " (" .. n .. "): " .. table.concat(rows, " ")
  end)
  if not ok then out[#out+1] = tag .. " err " .. tostring(err) end
end
local fl = {}
for _, f in ipairs(t:get_fields()) do
  local v = nil; pcall(function() v = uim:get_field(f:get_name()) end)
  local tn = f:get_type():get_full_name()
  fl[#fl+1] = f:get_name() .. ":" .. tn
  if type(v) == "userdata" then
    if tn == "app.CharacterPadAssign" then dumpassign(v, "field " .. f:get_name())
    elseif tn:find("CharacterPadAssign") then
      pcall(function()
        local els = v:get_elements()
        for i, e in ipairs(els) do if e then dumpassign(e, "field " .. f:get_name() .. "[" .. i .. "]") end end
      end)
      pcall(function()
        local n = v:call("get_Count")
        for i = 0, n - 1 do dumpassign(v:call("get_Item", i), "field " .. f:get_name() .. "{" .. i .. "}") end
      end)
    end
  end
end
out[#out+1] = "UIM fields: " .. table.concat(fl, " | ")
local ms = {}
for _, m in ipairs(t:get_methods()) do local l = m:get_name():lower(); if l:find("assign") or l:find("custom") or l:find("default") or l:find("config") or l:find("preset") then ms[#ms+1] = m:get_name() end end
out[#out+1] = "UIM methods: " .. table.concat(ms, " ")
dumpassign(uim:call("getCurrentCharacterPadAssign"), "CURRENT")
return table.concat(out, "\n")
