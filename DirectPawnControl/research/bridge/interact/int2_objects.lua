-- Shapes of the interact types, and the interactive objects near the Arisen and near the main pawn. Read-only.
local out = { types = {}, near = {} }
local function shape(tn)
  local td = sdk.find_type_definition(tn); if not td then out.types[tn] = "none"; return end
  local l = { "parent " .. tostring(td:get_parent_type() and td:get_parent_type():get_full_name()) }
  for _, f in ipairs(td:get_fields()) do l[#l + 1] = "F " .. f:get_name() .. " : " .. f:get_type():get_full_name() end
  for _, m in ipairs(td:get_methods()) do
    local ps = {}
    for _, pt in ipairs(m:get_param_types()) do ps[#ps + 1] = pt:get_name() end
    l[#l + 1] = "M " .. m:get_name() .. "(" .. table.concat(ps, ",") .. ") -> " .. m:get_return_type():get_name()
  end
  out.types[tn] = l
end
for _, t in ipairs({ "app.InteractiveObject", "app.InteractManager.InteractPoint", "app.InteractManager.InteractRequest", "app.InteractManager.ActiveInteract", "app.InteractPointData", "app.InteractiveObjectUpdater" }) do shape(t) end
local im = sdk.get_managed_singleton("app.InteractManager")
local ar = sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer")
local pw = sdk.get_managed_singleton("app.PawnManager"):call("get_PawnCharacterList")[0]
local ap = ar:call("get_Transform"):call("get_Position")
local pp = pw:call("get_Transform"):call("get_Position")
out.hasHighest = im:call("hasHighestPriorityObjectForPlayer")
local set = im:get_field("InteractiveObjects")
local n, rows = 0, {}
pcall(function()
  local it = set:call("GetEnumerator")
  -- HashSet enumerator is a struct; fall back to the slots array
end)
local ok, slots = pcall(function() return set:get_field("_entries") or set:get_field("_slots") end)
out.set_fields = {}
for _, f in ipairs(set:get_type_definition():get_fields()) do out.set_fields[#out.set_fields + 1] = f:get_name() .. ":" .. f:get_type():get_full_name() end
if ok and slots then
  for _, s in ipairs(slots:get_elements()) do
    local okv, o = pcall(function() return s:get_field("value") or s:get_field("Value") end)
    if okv and o then
      n = n + 1
      local okp, p = pcall(function() return o:call("get_GameObject"):call("get_Transform"):call("get_Position") end)
      if okp and p then
        local da = math.sqrt((p.x - ap.x) ^ 2 + (p.z - ap.z) ^ 2)
        local dp = math.sqrt((p.x - pp.x) ^ 2 + (p.z - pp.z) ^ 2)
        if da < 15 or dp < 15 then
          local okn, nm = pcall(function() return o:call("get_GameObject"):call("get_Name") end)
          rows[#rows + 1] = { name = okn and nm or "?", type = o:get_type_definition():get_full_name(), dA = da, dP = dp }
        end
      end
    end
  end
end
out.count, out.near = n, rows
pcall(json.dump_file, "DPC_probe_interact_2.json", out)
return "objects " .. n .. " near " .. #rows .. " highest " .. tostring(out.hasHighest)
