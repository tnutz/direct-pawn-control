-- Read-only: where is a pawn's stamina, and what draws the pawn name / health plate?
local r = {}
local pw = sdk.get_managed_singleton("app.PawnManager"):call("get_PawnCharacterList")[0]
local function names(td, pat, lim)
  local l = {}
  for _, f in ipairs(td:get_fields()) do if f:get_name():find(pat) then l[#l + 1] = "F " .. f:get_name() .. ":" .. f:get_type():get_name() end end
  for _, m in ipairs(td:get_methods()) do if m:get_name():find(pat) and #l < (lim or 40) then l[#l + 1] = "M " .. m:get_name() end end
  return table.concat(l, " ")
end
r[#r + 1] = "Character: " .. names(pw:get_type_definition(), "[Ss]tamina")
local okm, sm = pcall(pw.call, pw, "get_StaminaManager")
if okm and sm then
  r[#r + 1] = "StaminaManager type " .. sm:get_type_definition():get_full_name()
  local l = {}
  for _, m in ipairs(sm:get_type_definition():get_methods()) do
    local n = m:get_name()
    if n:find("^get_") and m:get_num_params() == 0 then
      local ok, v = pcall(sm.call, sm, n)
      if ok and (type(v) == "number" or type(v) == "boolean") then l[#l + 1] = n .. "=" .. tostring(v) end
    end
  end
  r[#r + 1] = table.concat(l, " ")
end
local gm = sdk.get_managed_singleton("app.GuiManager")
r[#r + 1] = "GuiManager: " .. names(gm:get_type_definition(), "Pawn", 30)
r[#r + 1] = "GuiManager2: " .. names(gm:get_type_definition(), "[Nn]ame[PT]", 20) .. " " .. names(gm:get_type_definition(), "Gauge", 20)
return table.concat(r, " | ")
