-- Read-only: enumerate GUI game objects in the scene; list names, and app components on those that look like name / HP plates.
local r = {}
local scene = sdk.call_native_func(sdk.get_native_singleton("via.SceneManager"), sdk.find_type_definition("via.SceneManager"), "get_CurrentScene()")
local comps = scene:call("findComponents(System.Type)", sdk.typeof("via.gui.GUI"))
r[#r + 1] = "ret " .. type(comps) .. " " .. tostring(comps)
local n
pcall(function() r[#r + 1] = "td " .. comps:get_type_definition():get_full_name() end)
for _, m in ipairs({ "get_Count", "get_Length", "GetLength" }) do
  local ok, v = pcall(comps.call, comps, m, 0); if not (ok and type(v) == "number") then ok, v = pcall(comps.call, comps, m) end
  if ok and type(v) == "number" then n = v; r[#r + 1] = m .. "=" .. v; break end
end
local function item(i)
  local ok, v = pcall(comps.call, comps, "get_Item", i); if ok and v then return v end
  ok, v = pcall(comps.call, comps, "GetValue(System.Int32)", i); if ok and v then return v end
  ok, v = pcall(function() return comps[i] end); if ok and v then return v end
end
local names, plates = {}, {}
for i = 0, (n or 0) - 1 do
  local c = item(i)
  if c then pcall(function()
    local go = c:call("get_GameObject"); local nm = tostring(go:call("get_Name"))
    names[nm] = (names[nm] or 0) + 1
    if names[nm] == 1 then
      local apps = {}
      for _, cc in ipairs(go:call("get_Components"):get_elements()) do pcall(function() local tn = cc:get_type_definition():get_full_name(); if tn:find("^app%.") then apps[#apps + 1] = tn end end) end
      plates[nm] = table.concat(apps, ",")
    end
  end) end
end
local l = {}
for k, v in pairs(names) do l[#l + 1] = k .. "x" .. v .. "{" .. tostring(plates[k]) .. "}" end
table.sort(l)
r[#r + 1] = table.concat(l, " ")
return table.concat(r, " | ")
