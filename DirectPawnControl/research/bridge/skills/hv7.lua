local out = {}
local pm = sdk.get_managed_singleton("app.PawnManager"); if not pm then return "no pm" end
local roots = {}
pcall(function()
  local ch = pm:call("get_PawnCharacterList"):call("get_Item", 0)
  local go = ch:call("get_GameObject")
  local comps = go:call("get_Components")
  for _, c in ipairs(comps:get_elements()) do roots[#roots+1] = c:get_type_definition() end
end)
for _, sn in ipairs({ "app.CharacterManager", "app.PawnManager", "app.BattleManager", "app.AIManager", "app.HumanCommonParameterManager", "app.JobManager", "app.CharacterEditManager", "app.ItemManager" }) do
  local t = sdk.find_type_definition(sn); if t then roots[#roots+1] = t end
end
local seen, q, n = {}, {}, 0
for _, t in ipairs(roots) do q[#q+1] = { t, t:get_full_name(), 0 } end
local hits = {}
local qi = 1
while qi <= #q and n < 9000 do
  local t, path, depth = q[qi][1], q[qi][2], q[qi][3]; qi = qi + 1
  local name = t:get_full_name()
  if not seen[name] then
    seen[name] = true; n = n + 1
    local tt = t
    while tt do
      local tn = tt:get_full_name()
      if tn == "System.Object" or tn == "via.Component" or tn == "via.Behavior" then break end
      for _, f in ipairs(tt:get_fields()) do
        local ok, ft = pcall(f.get_type, f)
        if ok and ft then
          local fn = ft:get_full_name()
          if fn:find("DecisionPack") and not fn:find("DecisionPackHandler") then
            if #hits < 80 then hits[#hits+1] = path .. "." .. f:get_name() .. " : " .. fn end
          elseif depth < 5 and (fn:find("^app%.") or fn:find("app%.")) and not seen[fn] then
            -- element type for arrays/generics: strip to first app.X token
            local et = fn:match("(app%.[%w_%.]+)%[%]$") or fn
            local e = sdk.find_type_definition(et)
            if e then q[#q+1] = { e, path .. "." .. f:get_name(), depth + 1 } end
          end
        end
      end
      tt = tt:get_parent_type()
    end
  end
end
out[#out+1] = "types visited " .. n .. " queue " .. #q
for _, h in ipairs(hits) do out[#out+1] = h end
return table.concat(out, "\n")
