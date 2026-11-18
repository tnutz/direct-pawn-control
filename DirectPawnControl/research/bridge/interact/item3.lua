-- Dropped item: run the object's Start handler for the pawn (the step our direct path skips). MODE "start" or "exec" or "end".
local MODE = "start"
local cm = sdk.get_managed_singleton("app.CameraManager"); local mcc = cm:call("getMainCameraController", 0)
local ch = mcc:call("get_TargetCharacter")
local pp = ch:call("get_Transform"):call("get_Position")
local im = sdk.get_managed_singleton("app.InteractManager")
local best, bd, bgo
for _, s in ipairs(im:get_field("InteractiveObjects"):get_field("_entries"):get_elements()) do
  local oks, o = pcall(s.get_field, s, "Value"); if not (oks and o) then oks, o = pcall(s.get_field, s, "value") end
  if oks and o then pcall(function()
    local go = o:get_field("<Owner>k__BackingField")
    if tostring(go:call("get_Name")):find("^gm82_000") then
      local q = go:call("get_Transform"):call("get_Position")
      local d = math.sqrt((q.x - pp.x) ^ 2 + (q.y - pp.y) ^ 2 + (q.z - pp.z) ^ 2)
      if d < 6 and (not bd or d < bd) then best, bd, bgo = o, d, go end
    end
  end) end
end
local r = { MODE }
if MODE == "start" and best then
  local ok, e = pcall(function() best:get_field("StartInteractHandler"):call("Invoke", 0, ch) end)
  r[#r + 1] = "start ok=" .. tostring(ok) .. " " .. tostring(e)
elseif MODE == "exec" then
  local ok, e = pcall(im.call, im, "executeInteract(app.Character)", ch)
  r[#r + 1] = "exec ok=" .. tostring(ok) .. " " .. tostring(e)
elseif MODE == "end" then
  local ok, e = pcall(im.call, im, "endInteract(app.Character)", ch)
  r[#r + 1] = "end ok=" .. tostring(ok) .. " " .. tostring(e)
end
if best then
  local g = bgo:call("getComponent(System.Type)", sdk.typeof("app.Gm82_000_01"))
  r[#r + 1] = string.format("item %.2fm IsInteractAny %s chara %s", bd, tostring(g:call("get_IsInteractAny")), tostring(g:call("getInteractChara()") ~= nil))
else r[#r + 1] = "no item near" end
r[#r + 1] = "interacting " .. tostring(im:call("isInteracting(app.Character)", ch)) .. " active " .. tostring(im:get_field("ActiveInteracts"):call("get_Count"))
local okn, n0 = pcall(function() return ch:call("get_ActionManager"):get_field("Fsm"):call("getCurrentNodeName", 0) end)
r[#r + 1] = "node " .. tostring(n0)
return table.concat(r, " | ")
