-- The Arisen is stuck in Job01_ShieldCounterStart. Try the game's own ways out, one per run. MODE: "look" | "end" | "idle" | "reset"
local MODE = "end"
local ar = sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer")
local fsm = ar:call("get_ActionManager"):get_field("Fsm")
local function node() return tostring(fsm:call("getCurrentNodeName(System.UInt32)", 0)) end
local sel = ar:call("get_HumanActionSelector")
local r = { MODE, "before " .. node(), "idleOK " .. tostring(sel and sel:call("isEnableRequestIdle")) }
if MODE == "end" then
  local ok, e = pcall(sel.call, sel, "requestEndAction"); r[#r + 1] = "requestEndAction ok=" .. tostring(ok) .. " " .. tostring(e)
elseif MODE == "idle" then
  local ok, e = pcall(sel.call, sel, "requestIdleImpl(System.Boolean)", false); r[#r + 1] = "requestIdleImpl ok=" .. tostring(ok) .. " " .. tostring(e)
elseif MODE == "reset" then
  local ok, e = pcall(sel.call, sel, "requestResetAction"); r[#r + 1] = "requestResetAction ok=" .. tostring(ok) .. " " .. tostring(e)
end
r[#r + 1] = "after " .. node()
return table.concat(r, " | ")
