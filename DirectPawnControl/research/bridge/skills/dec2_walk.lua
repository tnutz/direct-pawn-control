-- Step 2: find the AIDecision objects under each party pawn's AIDecisionMaker and dump, for every decision that
-- names custom skills: skill ids, action pack (path / name), target flags, stage. Read-only, bounded walk.
local IDX = IDX or 0
local out, decs, seen, visited = {}, {}, {}, 0
local function tname(o) local ok, n = pcall(function() return o:get_type_definition():get_full_name() end); return ok and n or nil end
local function elems(o, tn)
  local r = {}
  if tn:find("%[%]$") then
    local ok, e = pcall(o.get_elements, o); if ok and e then for _, v in ipairs(e) do r[#r+1] = v end end
  elseif tn:find("^System%.Collections%.Generic%.List") or tn:find("ReadOnlyCollection") then
    local ok, n = pcall(o.call, o, "get_Count")
    if ok and n then for i = 0, math.min(n, 4000) - 1 do local ok2, v = pcall(o.call, o, "get_Item", i); if ok2 and v then r[#r+1] = v end end end
  elseif tn:find("^System%.Collections%.Generic%.Dictionary") then
    local ok, ent = pcall(o.get_field, o, "_entries")
    if ok and ent then local ok2, e = pcall(ent.get_elements, ent); if ok2 and e then for _, v in ipairs(e) do local ok3, val = pcall(v.get_field, v, "value"); if ok3 and val then r[#r+1] = val end end end end
  end
  return r
end
local function walk(o, path, depth)
  if type(o) ~= "userdata" or depth > 7 or visited > 6000 then return end
  local ok, addr = pcall(o.get_address, o); if not ok or not addr or seen[addr] then return end
  seen[addr] = true; visited = visited + 1
  local tn = tname(o); if not tn then return end
  if tn == "app.AIDecision" then decs[#decs+1] = { o = o, path = path }; return end
  if tn:find("%[%]$") or tn:find("^System%.Collections%.Generic%.") then
    for i, v in ipairs(elems(o, tn)) do walk(v, path .. "[" .. (i - 1) .. "]", depth + 1) end
    return
  end
  if not tn:find("^app%.") then return end
  if tn:find("Character$") or tn:find("BlackBoard") or tn:find("ContextHolder") or tn == "app.Human" then return end
  local td = o:get_type_definition()
  while td do
    for _, f in ipairs(td:get_fields()) do
      if not f:is_static() then
        local ft = f:get_type():get_full_name()
        if ft:find("^app%.") or ft:find("%[%]$") or ft:find("^System%.Collections%.Generic%.") then
          local okv, v = pcall(o.get_field, o, f:get_name())
          if okv and v then walk(v, path .. "." .. f:get_name(), depth + 1) end
        end
      end
    end
    td = td:get_parent_type()
    if td and (td:get_full_name() == "System.Object" or td:get_full_name():find("^via%.")) then break end
  end
end
local pw = sdk.get_managed_singleton("app.PawnManager"):call("get_PawnCharacterList")[IDX]
local job = pw:call("get_Human"):call("get_JobContext"):get_field("CurrentJob")
local dm = pw:get_field("<AIDecisionMaker>k__BackingField")
local mod = dm:call("get_DecisionModule")
out.pawn, out.job, out.module = pw:call("get_CharaIDString"), job, tname(mod)
walk(dm, "dm", 0)
out.visited, out.found = visited, #decs
local function arr(o) local r = {}; if o then local ok, e = pcall(o.get_elements, o); if ok and e then for _, v in ipairs(e) do r[#r+1] = (type(v) == "userdata") and (v:get_field("value__") or tostring(v)) or v end end end; return r end
local rows, paths = {}, {}
for _, d in ipairs(decs) do
  local o = d.o
  local root = d.path:gsub("%[%d+%]", "[]"); paths[root] = (paths[root] or 0) + 1
  local ids = arr(o:get_field("<HumanCustomSkillIDs>k__BackingField"))
  if #ids > 0 then
    local ap = o:get_field("<ActionPack>k__BackingField")
    local row = { ids = ids, target = o:get_field("<Target>k__BackingField"), utarget = o:get_field("<UniqueTarget>k__BackingField"),
                  ptarget = o:get_field("<PositionTarget>k__BackingField"), stage = o:get_field("<Stage>k__BackingField"),
                  situation = o:get_field("<Situation>k__BackingField"), prio = o:get_field("<Priority>k__BackingField") }
    if ap then
      for _, m in ipairs({ "get_Path", "get_Name", "ToString", "get_ResourcePath", "get_FilePath" }) do
        local ok, v = pcall(ap.call, ap, m); if ok and v ~= nil then row[m] = tostring(v) end
      end
      row.ap_type = tname(ap)
      local okp, pk = pcall(ap.call, ap, "get_Pack"); if okp and pk then row.pack_type = tname(pk) end
    end
    rows[#rows+1] = row
  end
end
out.paths, out.rows = paths, rows
-- shape of via.UserData / ActInterPack for the name question
local ms = {}
for _, tn in ipairs({ "via.UserData", "app.ActInterPack" }) do
  local td = sdk.find_type_definition(tn)
  if td then local l = {}; for _, m in ipairs(td:get_methods()) do l[#l+1] = m:get_name() end; for _, f in ipairs(td:get_fields()) do l[#l+1] = "F:" .. f:get_name() .. ":" .. f:get_type():get_full_name() end; ms[tn] = table.concat(l, " ") end
end
out.types = ms
pcall(json.dump_file, "DPC_probe_decisions_2_" .. IDX .. ".json", out)
return string.format("pawn %d job %s module %s visited %d decisions %d with-skill %d", IDX, tostring(job), tostring(out.module), visited, #decs, #rows)
