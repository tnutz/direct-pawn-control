local out = {}
local cm = sdk.get_managed_singleton("app.CharacterManager"); if not cm then return "no cm" end
local cat = cm:get_field("<DecisionPackCatalog>k__BackingField")
local dict = cat:get_field("<MergedCatalog>k__BackingField")
local function elems(x)
  if not x then return {} end
  local ok, e = pcall(function() return x:get_elements() end)
  if ok and e then return e end
  local r = {}
  pcall(function() local n = x:call("get_Count"); for i = 0, n - 1 do r[#r+1] = x:call("get_Item", i) end end)
  return r
end
local ok, err = pcall(function()
  local en = dict:call("GetEnumerator")
  local guard = 0
  while en:call("MoveNext") and guard < 500 do
    guard = guard + 1
    local kv = en:call("get_Current")
    local key = kv:get_field("key")
    local rc = kv:get_field("value")
    local pack = rc
    if rc and rc:get_type_definition():get_full_name():find("RefCounter") then
      local got = nil
      for _, f in ipairs(rc:get_type_definition():get_fields()) do
        local v = rc:get_field(f:get_name())
        if guard == 1 then out[#out+1] = "rc field " .. f:get_name() .. "=" .. tostring(v) end
        if type(v) == "userdata" then got = v end
      end
      pack = got
    end
    local decs = pack and elems(pack:get_field("_Decisions")) or {}
    local rows = {}
    for _, d in ipairs(decs) do
      local ids = elems(d:get_field("_HumanCustomSkillIDs"))
      if #ids > 0 then
        local ap = d:get_field("_ActInterPack")
        local p = ap and tostring(ap:call("get_Path")) or "?"
        p = p:gsub("^.*ActInterPackData[/\\]", "")
        local s = {}
        for _, v in ipairs(ids) do s[#s+1] = tostring((type(v) == "userdata") and v:get_field("value__") or v) end
        rows[#rows+1] = table.concat(s, ",") .. ">" .. p .. ">" .. tostring(d:get_field("_Target"))
      end
    end
    out[#out+1] = "pack " .. tostring(key) .. " decs=" .. #decs .. " " .. table.concat(rows, " ; ")
  end
end)
if not ok then out[#out+1] = "err " .. tostring(err) end
return table.concat(out, "\n")
