-- Read-only: the main pawn's joints (names, height above the root) to find what the name plate could hang on.
local pw = sdk.get_managed_singleton("app.PawnManager"):call("get_PawnCharacterList")[0]
local tr = pw:call("get_Transform")
local root = tr:call("get_Position")
local r = {}
local okh, h = pcall(tr.call, tr, "getJointByName", "Head")
r[#r + 1] = "getJointByName(Head) -> " .. tostring(okh) .. " " .. tostring(h)
local joints = tr:call("get_Joints")
local els = joints and joints:get_elements() or {}
r[#r + 1] = "joints " .. #els
local out = {}
for i, j in ipairs(els) do
  local ok, n = pcall(j.call, j, "get_Name")
  if ok and n then
    local ln = tostring(n):lower()
    if i <= 12 or ln:find("head") or ln:find("neck") or ln:find("spine") or ln:find("hip") or ln:find("root") or ln:find("cog") or ln:find("face") then
      local p = j:call("get_Position")
      out[#out + 1] = string.format("%s[%.2f]", tostring(n), p.y - root.y)
    end
  end
end
r[#r + 1] = table.concat(out, " ")
local fsm = pw:call("get_ActionManager"):get_field("Fsm")
r[#r + 1] = "node " .. tostring(fsm:call("getCurrentNodeName(System.UInt32)", 0))
return table.concat(r, " | ")
