local out = {}
local pm = sdk.get_managed_singleton("app.PawnManager"); if not pm then return "no pm" end
local function elems(x)
  if not x then return {} end
  local ok, e = pcall(function() return x:get_elements() end)
  if ok and e then return e end
  return {}
end
local ok, e = pcall(function()
  local ch = pm:call("get_PawnCharacterList"):call("get_Item", 0)
  local gp = ch:call("get_GameObject"):call("getComponent(System.Type)", sdk.typeof("app.goalplanning.AIGoalPlanning"))
  local cs = gp:get_field("_AIGoalData"):get_field("_CSDecisions")
  for _, set in ipairs(elems(cs:get_field("_CustomSkillDecisions"))) do
    local sid = set:get_field("_SKillID")
    local rows, seen, np, nd = {}, {}, 0, 0
    for _, pack in ipairs(elems(set:get_field("_DecisionPackList"))) do
      np = np + 1
      for _, d in ipairs(elems(pack:get_field("_Decisions"))) do
        nd = nd + 1
        local named = false
        local ids = elems(d:get_field("_HumanCustomSkillIDs"))
        for _, v in ipairs(ids) do local x = (type(v) == "userdata") and v:get_field("value__") or v; if x == sid then named = true end end
        local ap = d:get_field("_ActInterPack")
        local p = ap and tostring(ap:call("get_Path")) or "?"
        p = p:gsub("^.*ActInterPackData[/\\]", ""):gsub("%.user$", "")
        local key = (named and "" or "~") .. p .. ">" .. tostring(d:get_field("_Target"))
        if not seen[key] then seen[key] = true; rows[#rows+1] = key end
      end
    end
    out[#out+1] = tostring(sid) .. " p" .. np .. " d" .. nd .. " " .. table.concat(rows, " ; ")
  end
  local ns = elems(cs:get_field("_NormalSkillDecisions"))
  if ns[1] then
    local fs = {}
    for _, f in ipairs(ns[1]:get_type_definition():get_fields()) do fs[#fs+1] = f:get_name() .. "=" .. tostring(ns[1]:get_field(f:get_name())) end
    out[#out+1] = "normal: " .. table.concat(fs, " | ")
  end
end)
if not ok then out[#out+1] = "err " .. tostring(e) end
return table.concat(out, "\n")
