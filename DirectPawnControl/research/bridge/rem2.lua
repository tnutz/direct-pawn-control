local out = {}
local D = _G.DPC_dbg
local pm = sdk.get_managed_singleton("app.PawnManager")
local l = pm:call("get_PawnCharacterList")
local function sig(m)
  local ps = {}
  pcall(function() for _, pt in ipairs(m:get_param_types()) do ps[#ps+1] = pt:get_full_name() end end)
  local rt = ""; pcall(function() rt = m:get_return_type():get_full_name() end)
  return m:get_name() .. "(" .. table.concat(ps, ",") .. ")->" .. rt
end
for i = 0, l:call("get_Count") - 1 do
  local ch = l:call("get_Item", i)
  local s = tostring(ch:call("get_GameObject"):call("get_Name"))
  local ok, lt = pcall(ch.call, ch, "get_LockOnTarget")
  s = s .. " get_LockOnTarget ok=" .. tostring(ok) .. " v=" .. tostring(lt)
  if ok and lt then
    s = s .. " type=" .. lt:get_type_definition():get_full_name()
    local ok2, w = pcall(lt.call, lt, "get_work"); s = s .. " work ok=" .. tostring(ok2) .. " " .. tostring(w)
    if i == 1 then
      local ms = {}
      for _, m in ipairs(lt:get_type_definition():get_methods()) do ms[#ms+1] = sig(m) end
      out[#out+1] = "LockOnTarget M: " .. table.concat(ms, "  ")
      for _, f in ipairs(lt:get_type_definition():get_fields()) do
        local okv, v = pcall(function() return lt:get_field(f:get_name()) end)
        local d = tostring(okv and v); if okv and type(v) == "userdata" then pcall(function() d = v:get_type_definition():get_full_name() end) end
        out[#out+1] = "  F " .. f:get_name() .. " = " .. d
      end
    end
  end
  out[#out+1] = s
end
local t = sdk.find_type_definition("app.Character")
for _, m in ipairs(t:get_methods()) do if m:get_name():lower():find("lockon") then out[#out+1] = "Character." .. sig(m) end end
local t2 = sdk.find_type_definition("app.LockOnController")
local ms = {}
for _, m in ipairs(t2:get_methods()) do ms[#ms+1] = sig(m) end
out[#out+1] = "LockOnController M: " .. table.concat(ms, "  ")
local t3 = sdk.find_type_definition("app.Job08ActionController")
for _, m in ipairs(t3:get_methods()) do local n = m:get_name():lower(); if n:find("lifereturn") or n:find("lockon") or n:find("target") then out[#out+1] = "Job08." .. sig(m) end end
return table.concat(out, "\n")
