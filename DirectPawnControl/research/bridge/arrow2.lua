-- read-only: which special-arrow props the played pawn (or the first Archer pawn) and the Arisen carry on the bow
local out = {}
local D = _G.DPC_dbg
local function dump(tag, ch)
  if not ch then out[#out+1] = tag .. ": none"; return end
  local ok, err = pcall(function()
    local hu = ch:call("get_Human")
    local l = hu:get_field("SpecialArrows")
    local n = l and l:call("get_Count") or -1
    local p = {}
    for i = 0, n - 1 do
      local t = l:call("get_Item", i)
      local a, w = t:call("get_Item1"), t:call("get_Item2")
      p[#p+1] = tostring(a) .. (w and "" or " (no weapon)")
    end
    out[#out+1] = string.format("%s: job %s, SpecialArrows %d [%s]", tag, tostring(ch:call("get_Job") or "?"), n, table.concat(p, ", "))
  end)
  if not ok then out[#out+1] = tag .. ": " .. tostring(err) end
end
dump("played pawn", D and D.state.pawn_chara)
dump("arisen", sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer"))
return table.concat(out, "\n")
