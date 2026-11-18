-- Damage attribution log: hook app.Character.onDamageHit and record attacker + damage for hits on enemies.
local td = sdk.find_type_definition("app.HitController.DamageInfo")
local names = {}
for _, f in ipairs(td:get_fields()) do names[#names+1] = f:get_name() .. ":" .. f:get_type():get_name() end
local A = _G.AB
A.dmg = A.dmg or {}
if not A.dmg_hooked then
  A.dmg_hooked = true
  local m = sdk.find_type_definition("app.Character"):get_method("onDamageHit")
  sdk.hook(m, function(args)
    pcall(function()
      local recv = sdk.to_managed_object(args[2])
      local info = sdk.to_managed_object(args[3])
      local L = _G.AB.dmg
      if #L > 60 then return end
      local row = { t = os.clock(), recv = recv:call("get_CharaIDString") }
      for _, k in ipairs({ "Damage", "AttackOwner", "<AttackOwner>k__BackingField", "AttackHitController", "Owner" }) do
        local ok, v = pcall(info.get_field, info, k)
        if ok and v ~= nil then
          if type(v) == "userdata" then
            local ok2, s = pcall(function() return v:call("get_CharaIDString") or v:get_type_definition():get_full_name() end)
            row[k] = ok2 and s or tostring(v)
          else row[k] = v end
        end
      end
      for _, g in ipairs({ "get_AttackOwnerCharacter", "get_Attacker", "get_AttackOwner", "get_Damage" }) do
        local ok, v = pcall(info.call, info, g)
        if ok and v ~= nil then
          if type(v) == "userdata" then
            local ok2, s = pcall(function() return v:call("get_CharaIDString") end)
            row[g] = ok2 and s or v:get_type_definition():get_full_name()
          else row[g] = v end
        end
      end
      L[#L+1] = row
    end)
  end, function(r) return r end)
end
local mn = {}
for _, mm in ipairs(td:get_methods()) do local n = mm:get_name(); if n:find("^get_") then mn[#mn+1] = n end end
json.dump_file("agent_bridge/dmginfo_fields.json", { fields = names, getters = mn })
return { "fields " .. #names .. " getters " .. #mn }
