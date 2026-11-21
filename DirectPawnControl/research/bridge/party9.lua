local out = { pawns = {} }
local pm = sdk.get_managed_singleton("app.PawnManager")
local list = pm and pm:call("get_PawnCharacterList")
local n = list and list:call("get_Count") or 0
out.count = n
for i = 0, n - 1 do
  local c = list:call("get_Item", i)
  local e = { id = c and tostring(c:call("get_CharaIDString")) }
  pcall(function()
    local hp = c:call("get_Hit"); e.hp = hp and hp:call("get_Hp")
    local p = c:call("get_Transform"):call("get_Position"); e.pos = string.format("%.0f %.0f %.0f", p.x, p.y, p.z)
    e.name = c:call("get_Pawn") and tostring(c:call("get_Pawn"):call("get_Name")) or nil
  end)
  out.pawns[#out.pawns + 1] = e
end
pcall(function() out.party_count = pm:call("get_PartyPawnCount") end)
local D = rawget(_G, "DPC_dbg")
out.dpc_active = D and D.state.active
out.coop = D and D.coop.active
out.arrow_given = D and D.R.arrow_give and D.R.arrow_give.given
out.arrow_last = D and D.R.arrow_give and D.R.arrow_give.last
local ok, st = pcall(json.load_file, "dev_status/DirectPawnControl.json")
out.errors = ok and st and st.errors
out.last_err = ok and st and (st.last_error or st.err)
return out
