-- After item1: is the pawn still marked interacting, does the dropped item still exist, what does the gimmick say?
local cm = sdk.get_managed_singleton("app.CameraManager"); local mcc = cm:call("getMainCameraController", 0)
local ch = mcc:call("get_TargetCharacter")
local pp = ch:call("get_Transform"):call("get_Position")
local im = sdk.get_managed_singleton("app.InteractManager")
local r = { "who " .. tostring(ch:get_GameObject():call("get_Name")), "interacting " .. tostring(im:call("isInteracting(app.Character)", ch)), "active " .. tostring(im:get_field("ActiveInteracts"):call("get_Count")) }
local n = 0
for _, s in ipairs(im:get_field("InteractiveObjects"):get_field("_entries"):get_elements()) do
  local oks, o = pcall(s.get_field, s, "Value"); if not (oks and o) then oks, o = pcall(s.get_field, s, "value") end
  if oks and o then pcall(function()
    local go = o:get_field("<Owner>k__BackingField")
    local nm = tostring(go:call("get_Name"))
    if nm:find("^gm82_000") then
      local q = go:call("get_Transform"):call("get_Position")
      local d = math.sqrt((q.x - pp.x) ^ 2 + (q.y - pp.y) ^ 2 + (q.z - pp.z) ^ 2)
      if d < 6 then
        n = n + 1
        local g = go:call("getComponent(System.Type)", sdk.typeof("app.Gm82_000_01"))
        r[#r + 1] = string.format("%s %.2fm item %s x%s IsInteractAny %s plInteract %s deleted %s used %s", nm, d, tostring(g:call("getItemId")), tostring(g:call("getItemNum")), tostring(g:call("get_IsInteractAny")), tostring(g:get_field("_IsPLInteracting")), tostring(g:call("get_IsDeleted")), tostring(g:call("get_IsUsed")))
      end
    end
  end) end
end
r[#r + 1] = "items near " .. n
r[#r + 1] = "node0 " .. tostring(ch:call("get_ActionManager") and "" or "") 
return table.concat(r, " | ")
