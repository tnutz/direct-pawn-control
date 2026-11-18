local out = {}
local function dump(obj, label, pats, vals)
  local t = obj:get_type_definition()
  while t and t:get_full_name() ~= "System.Object" and t:get_full_name() ~= "via.Behavior" do
    for _, f in ipairs(t:get_fields()) do
      local n = f:get_name(); local tn = tostring(f:get_type():get_full_name()); local hit = (pats == nil)
      if pats then for _, p in ipairs(pats) do if n:lower():find(p) or tn:lower():find(p) then hit = true end end end
      if hit then
        local v = ""; if vals then pcall(function() v = " = " .. tostring(obj:get_field(n)) end) end
        out[#out+1] = label .. " f " .. n .. ":" .. tn .. v
      end
    end
    t = t:get_parent_type()
  end
end
local D = _G.DPC_dbg
local mcc = D and D.R.aim_mcc and D.R.aim_mcc()
out[#out+1] = "mcc = " .. tostring(mcc)
if mcc then
  dump(mcc, "MCC", { "aim", "setting", "controllers", "current" }, true)
  local td = mcc:get_type_definition()
  for _, m in ipairs(td:get_methods()) do
    local l = m:get_name():lower()
    if l:find("aim") or l:find("getcontroller") or l:find("get_current") then
      local ps = {}
      pcall(function() for _, pt in ipairs(m:get_param_types()) do ps[#ps+1] = pt:get_full_name() end end)
      local rt = ""; pcall(function() rt = m:get_return_type():get_full_name() end)
      out[#out+1] = "MCC m " .. m:get_name() .. "(" .. table.concat(ps, ",") .. ") -> " .. rt
    end
  end
end
local std = sdk.find_type_definition("app.AimCameraSetting")
if std then
  out[#out+1] = "## app.AimCameraSetting"
  for _, f in ipairs(std:get_fields()) do out[#out+1] = " f " .. f:get_name() .. ":" .. tostring(f:get_type():get_full_name()) end
  for _, m in ipairs(std:get_methods()) do
    local ps = {}
    pcall(function() for _, pt in ipairs(m:get_param_types()) do ps[#ps+1] = pt:get_full_name() end end)
    local rt = ""; pcall(function() rt = m:get_return_type():get_full_name() end)
    out[#out+1] = " m " .. m:get_name() .. "(" .. table.concat(ps, ",") .. ") -> " .. rt
  end
end
local atd = sdk.find_type_definition("app.AimCameraSetting.AimSetting")
if atd then
  out[#out+1] = "## AimSetting"
  for _, f in ipairs(atd:get_fields()) do out[#out+1] = " f " .. f:get_name() .. ":" .. tostring(f:get_type():get_full_name()) end
end
local actd = sdk.find_type_definition("app.AimCameraController")
out[#out+1] = "## AimCameraController own fields"
for _, f in ipairs(actd:get_fields()) do out[#out+1] = " f " .. f:get_name() .. ":" .. tostring(f:get_type():get_full_name()) end
return table.concat(out, "\n")
