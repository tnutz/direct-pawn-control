-- Step 4: the DecisionPack catalog only covers 12 skills, and a Fighter pawn with Blink Strike equipped has no
-- AIDecision naming a custom skill. So where does the pawn AI keep its skill action packs? Walk every component
-- on the pawn's GameObject (bounded) and record each app.ActInterPackData found: field path + file path. Read-only.
local IDX = IDX or 0
local found, seen, visited, comps = {}, {}, 0, {}
local function tname(o) local ok, n = pcall(function() return o:get_type_definition():get_full_name() end); return ok and n or nil end
local function walk(o, path, depth)
  if type(o) ~= "userdata" or depth > 6 or visited > 40000 then return end
  local ok, addr = pcall(o.get_address, o); if not ok or seen[addr] then return end
  seen[addr] = true; visited = visited + 1
  local tn = tname(o); if not tn then return end
  if tn == "app.ActInterPackData" then
    local okp, p = pcall(o.call, o, "get_Path")
    found[#found + 1] = { at = path:gsub("%[%d+%]", "[]"), file = okp and tostring(p) or "?" }
    return
  end
  if tn:find("%[%]$") then
    local ok2, e = pcall(o.get_elements, o)
    if ok2 and e then for i, v in ipairs(e) do if i > 600 then break end; walk(v, path .. "[" .. i .. "]", depth + 1) end end
    return
  end
  if tn:find("^System%.Collections%.Generic%.List") then
    local okc, n = pcall(o.call, o, "get_Count")
    if okc and n then for i = 0, math.min(n, 600) - 1 do local ok3, v = pcall(o.call, o, "get_Item", i); if ok3 then walk(v, path .. "[" .. i .. "]", depth + 1) end end end
    return
  end
  if tn:find("^System%.Collections%.Generic%.Dictionary") then
    local oke, ent = pcall(o.get_field, o, "_entries")
    if oke and ent then local ok2, e = pcall(ent.get_elements, ent); if ok2 and e then for i, v in ipairs(e) do local ok3, val = pcall(v.get_field, v, "value"); if ok3 and val then walk(val, path .. "{}", depth + 1) end end end end
    return
  end
  if not tn:find("^app%.") then return end
  if tn == "app.Character" and depth > 0 then return end
  local td = o:get_type_definition()
  while td do
    for _, f in ipairs(td:get_fields()) do
      if not f:is_static() then
        local ft = f:get_type():get_full_name()
        if ft:find("^app%.") or ft:find("%[%]$") or ft:find("^System%.Collections%.Generic%.") or ft == "via.UserData" then
          local okv, v = pcall(o.get_field, o, f:get_name()); if okv and v then walk(v, path .. "." .. f:get_name(), depth + 1) end
        end
      end
    end
    td = td:get_parent_type()
    if td and (td:get_full_name() == "System.Object" or td:get_full_name():find("^via%.")) then break end
  end
end
local pw = sdk.get_managed_singleton("app.PawnManager"):call("get_PawnCharacterList")[IDX]
local go = pw:get_GameObject()
local cs = go:call("get_Components"):get_elements()
for _, c in ipairs(cs) do
  local tn = tname(c) or "?"
  local before = #found
  if tn:find("^app%.") and (not ONLY or tn:find(ONLY, 1, true)) then visited = 0; walk(c, tn, 0) end
  comps[#comps + 1] = tn .. "=" .. (#found - before)
end
local by = {}
for _, f in ipairs(found) do by[f.at] = by[f.at] or {}; local l = by[f.at]; if #l < 400 then l[#l + 1] = f.file end end
pcall(json.dump_file, "DPC_probe_decisions_4_" .. IDX .. (TAG or "") .. ".json", { visited = visited, total = #found, comps = comps, by = by })
return string.format("pawn %d visited %d packs %d", IDX, visited, #found)
