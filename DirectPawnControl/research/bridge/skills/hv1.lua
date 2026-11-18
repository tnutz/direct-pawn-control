local out = {}
local pm = sdk.get_managed_singleton("app.PawnManager"); if not pm then return "no pm" end
local cm = sdk.get_managed_singleton("app.CharacterManager"); if not cm then return "no cm" end
local function scan(ch, label)
  local ok, err = pcall(function()
    local dm = ch:get_field("<AIDecisionMaker>k__BackingField")
    if not dm then out[#out+1] = label .. ": no dm"; return end
    local mod = dm:call("get_DecisionModule")
    local mt = mod:get_type_definition()
    local fl = {}
    for _, f in ipairs(mt:get_fields()) do
      local v = nil; pcall(function() v = mod:get_field(f:get_name()) end)
      local d = ""
      if type(v) == "userdata" then pcall(function() d = v:get_type_definition():get_full_name(); local c = v:call("get_Count"); if c then d = d .. "#" .. tostring(c) end end) else d = tostring(v) end
      fl[#fl+1] = f:get_name() .. "=" .. d
    end
    out[#out+1] = label .. " module " .. mt:get_full_name() .. ": " .. table.concat(fl, " | ")
    local list = mod:get_field("<MainDecisions>k__BackingField")
    local n = list:call("get_Count")
    local seen, cnt = {}, 0
    for i = 0, n - 1 do
      local d = list:call("get_Item", i)
      local ids = d and d:get_field("<HumanCustomSkillIDs>k__BackingField")
      if ids then
        for _, v in ipairs(ids:get_elements()) do
          local x = (type(v) == "userdata") and v:get_field("value__") or v
          local ap = d:get_field("<ActionPack>k__BackingField")
          local p = ap and tostring(ap:call("get_Path")) or "?"
          p = p:gsub("^.*actinterpackdata[/\\]", "")
          local key = x .. ":" .. p .. ":" .. tostring(d:get_field("<Target>k__BackingField"))
          if not seen[key] then seen[key] = true; cnt = cnt + 1; if cnt <= 60 then out[#out+1] = "  " .. key end end
        end
      end
    end
    out[#out+1] = label .. " decisions=" .. n .. " skillrows=" .. cnt
  end)
  if not ok then out[#out+1] = label .. " err " .. tostring(err) end
end
local pl = cm:call("get_ManualPlayer"); if pl then scan(pl, "player") end
local ok, e = pcall(function()
  local lst = pm:call("get_PawnCharacterList")
  local n = lst:call("get_Count")
  for i = 0, n - 1 do scan(lst:call("get_Item", i), "pawn" .. i) end
end)
if not ok then out[#out+1] = "list err " .. tostring(e) end
return table.concat(out, "\n")
