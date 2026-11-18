local out = {}
local D = _G.DPC_dbg
local mcc = D.R.aim_mcc()
local ac = mcc:get_field("<CameraControllers>k__BackingField"):call("get_Item", 7)
local set = ac:get_field("_AimCameraSetting")
out[#out+1] = string.format("asset FOV=%s BasisHeight=%s Narrowing=%s", tostring(set:get_field("_FOV")), tostring(set:get_field("_BasisHeight")), tostring(set:get_field("_NarrowingRate")))
for _, k in ipairs({ "_AimSetting", "_CurrentAimSetting", "_NextAimSetting" }) do
  local v = ac:get_field(k); out[#out+1] = k .. " = " .. (v and string.format("%X", v:get_address()) or "nil")
end
out[#out+1] = "_IsSwitch=" .. tostring(ac:get_field("_IsSwitch")) .. " _Fov=" .. tostring(ac:get_field("_Fov"))
local arr = set:get_field("_AimSettings")
for i = 0, arr:get_size() - 1 do
  local e = arr:get_element(i)
  local fov = "-"
  pcall(function() local f = e:get_field("_Fov"); if f:get_field("_HasValue") then fov = string.format("%.1f", f:get_field("_Value")) end end)
  local cond = e:get_field("_Condition")
  local cs = "nil"
  if cond then
    cs = cond:get_type_definition():get_full_name()
    pcall(function()
      for _, f in ipairs(cond:get_type_definition():get_fields()) do
        local v = cond:get_field(f:get_name())
        local tv = tostring(v)
        if tv:find("sol%.") and v and v.get_type_definition then
          local okn, tn = pcall(function() return v:get_type_definition():get_full_name() end)
          tv = okn and tn or tv
          pcall(function()
            if v.get_size then
              local parts = {}
              for j = 0, v:get_size() - 1 do
                local c = v:get_element(j)
                local p = { c:get_type_definition():get_full_name() }
                for _, cf in ipairs(c:get_type_definition():get_fields()) do
                  local cv = tostring(c:get_field(cf:get_name()))
                  if not cv:find("sol%.") then p[#p+1] = cf:get_name() .. "=" .. cv end
                end
                parts[#parts+1] = table.concat(p, " ")
              end
              tv = "[" .. table.concat(parts, " ; ") .. "]"
            end
          end)
        end
        cs = cs .. " " .. f:get_name() .. "=" .. tv
      end
    end)
  end
  out[#out+1] = string.format("%d en=%s throw=%s fov=%s dist=%.2f yaw=%.1f pitch=%.1f gyro=%s addr=%X | %s", i, tostring(e:get_field("_Enabled")), tostring(e:get_field("_ThrowingAim")), fov,
    e:get_field("_Distance") or 0, e:get_field("_YawRotSpeed") or 0, e:get_field("_PitchRotSpeed") or 0, tostring(e:get_field("_GyroOperation")), e:get_address(), cs:sub(1, 260))
end
return table.concat(out, "\n")
