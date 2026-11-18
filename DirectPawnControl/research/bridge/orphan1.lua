-- remove unkillable test enemies that outlived a script reset (the mod lost its list of them)
local out = {}
local em = sdk.get_managed_singleton("app.EnemyManager")
local arr = em and em:call("getAllEnemies")
if not arr then return "no enemy list" end
local n = arr:call("get_Count") or 0
local removed = 0
for i = 0, n - 1 do
  pcall(function()
    local ch = arr[i]:get_field("_Chara")
    if not ch then return end
    local id = tostring(ch:call("get_CharaIDString"))
    local hit = ch:call("get_Hit")
    local nodie = hit and hit:call("get_IsNoDie")
    out[#out+1] = id .. " hp " .. tostring(ch:call("get_Hp")) .. " nodie " .. tostring(nodie)
    if nodie == true then
      hit:call("set_IsNoDie", false)
      local go = ch:call("get_GameObject")
      if go and sdk.is_managed_object(go) then go:destroy(go); removed = removed + 1 end
    end
  end)
end
return "enemies " .. n .. ", removed " .. removed .. "\n" .. table.concat(out, "\n")
