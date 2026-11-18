-- read-only: item ids whose name contains "Arrow", how many the Arisen and each pawn hold, and the item manager's arrow counters
local out = {}
local nm = sdk.find_type_definition("app.GUIBase"):get_method("getItemName(System.Int32)")
local im = sdk.get_managed_singleton("app.ItemManager")
local ar = sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer")
local pm = sdk.get_managed_singleton("app.PawnManager")
local list = pm:call("get_PawnCharacterList")
local function have(id, ch) local ok, n = pcall(function() return im:call("getHaveNum(System.Int32, app.Character)", id, ch) end); return ok and tostring(n) or "?" end
for id = 1, 600 do
  local ok, s = pcall(function() return nm:call(nil, id) end)
  s = ok and tostring(s) or ""
  if s:find("Arrow", 1, true) or s:find("arrow", 1, true) then
    local p = {}
    for i = 0, list:call("get_Count") - 1 do p[#p+1] = have(id, list:call("get_Item", i)) end
    out[#out+1] = string.format("%d %s | arisen %s | pawns %s", id, s, have(id, ar), table.concat(p, ","))
  end
end
for _, f in ipairs({ "_PoisonArrowNum", "_WaterArrowNum", "_OilArrowNum", "_ExplosiveArrowNum" }) do out[#out+1] = f .. " = " .. tostring(im:get_field(f)) end
return table.concat(out, "\n")
