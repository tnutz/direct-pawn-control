-- Step 3: the game-wide catalog (CharacterManager.DecisionPackCatalog). Dump every DecisionPack's path and, for each
-- decision in it, the fields that name skills / action packs / targets. Read-only.
local out = { packs = {}, notes = {} }
local function tname(o) local ok, n = pcall(function() return o:get_type_definition():get_full_name() end); return ok and n or nil end
local function fields_of(td)
  local l = {}
  while td do
    for _, f in ipairs(td:get_fields()) do if not f:is_static() then l[#l+1] = { n = f:get_name(), t = f:get_type():get_full_name() } end end
    td = td:get_parent_type()
    if td and (td:get_full_name() == "System.Object" or td:get_full_name():find("^via%.")) then break end
  end
  return l
end
local function val(v)
  if type(v) ~= "userdata" then return v end
  local tn = tname(v) or "?"
  if tn:find("%[%]$") then
    local r = {}
    local ok, e = pcall(v.get_elements, v)
    if ok and e then for i, x in ipairs(e) do if i > 12 then break end; r[#r+1] = val(x) end end
    return r
  end
  local okp, p = pcall(v.call, v, "get_Path"); if okp and p then return tostring(p) end
  local okv, n = pcall(v.get_field, v, "value__"); if okv and n ~= nil then return n end
  return tn
end
local cm = sdk.get_managed_singleton("app.CharacterManager")
local cat = cm:call("get_DecisionPackCatalog")
out.cat_type = tname(cat)
local fl = {}
for _, f in ipairs(fields_of(cat:get_type_definition())) do fl[#fl+1] = f.n .. ":" .. f.t end
out.cat_fields = fl
-- find DecisionPack objects under the catalog (bounded walk)
local packs, seen, visited = {}, {}, 0
local function walk(o, depth)
  if type(o) ~= "userdata" or depth > 6 or visited > 20000 then return end
  local ok, addr = pcall(o.get_address, o); if not ok or seen[addr] then return end
  seen[addr] = true; visited = visited + 1
  local tn = tname(o); if not tn then return end
  if tn == "app.DecisionPack" then packs[#packs+1] = o; return end
  if tn:find("%[%]$") then
    local ok2, e = pcall(o.get_elements, o); if ok2 and e then for _, v in ipairs(e) do walk(v, depth + 1) end end
    return
  end
  if tn:find("List") then
    local okc, n = pcall(o.call, o, "get_Count")
    if okc and n then for i = 0, n - 1 do local ok3, v = pcall(o.call, o, "get_Item", i); if ok3 then walk(v, depth + 1) end end end
  end
  for _, f in ipairs(fields_of(o:get_type_definition())) do
    if f.t:find("^app%.") or f.t:find("%[%]$") or f.t:find("^System%.Collections") or f.t:find("^via%.UserData") or f.t == "System.Object" or f.t:find("TValue") or f.t:find("^!") then
      local okv, v = pcall(o.get_field, o, f.n); if okv and v then walk(v, depth + 1) end
    end
  end
end
walk(cat, 0)
out.visited, out.pack_count = visited, #packs
local dec_fields = nil
for _, p in ipairs(packs) do
  local row = { path = tostring(p:call("get_Path")), stage = p:get_field("_Stage"), decisions = {} }
  local okd, ds = pcall(function() return p:get_field("_Decisions"):get_elements() end)
  if okd and ds then
    row.n = #ds
    for _, d in ipairs(ds) do
      if not dec_fields then
        dec_fields = fields_of(d:get_type_definition())
        local l = {}; for _, f in ipairs(dec_fields) do l[#l+1] = f.n .. ":" .. f.t end; out.decision_fields = l; out.decision_type = tname(d)
      end
      local r, has = {}, false
      for _, f in ipairs(dec_fields) do
        local n = f.n
        if n:find("Skill") or n:find("ActionPack") or n:find("ActInter") or n:find("Target") or n:find("Situation") or n:find("Priority") then
          local okv, v = pcall(d.get_field, d, n)
          if okv and v ~= nil then
            local x = val(v)
            r[n] = x
            if n:find("CustomSkill") and type(x) == "table" and #x > 0 then has = true end
          end
        end
      end
      if has then row.decisions[#row.decisions + 1] = r end
    end
  end
  out.packs[#out.packs + 1] = row
end
pcall(json.dump_file, "DPC_probe_decisions_3.json", out)
return string.format("catalog %s visited %d packs %d", tostring(out.cat_type), visited, #packs)
