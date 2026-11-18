-- read-only: the key guide's dash slots and what each button slot currently holds
local out = {}
local gm = sdk.get_managed_singleton("app.GuiManager")
local g = gm:get_field("KeyGuide")
if not g then return "no guide" end
local D = _G.DPC_dbg
out[#out+1] = "dpc active " .. tostring(D and D.state.active) .. " pawn " .. tostring(D and D.state.pawn_name)
for _, f in ipairs({ "BtnDash", "BtnDash2", "BtnInteract", "BtnJump", "BtnSheathe", "BtnGrab", "BtnAtk", "BtnAtk2", "BtnListNum", "IsBtnAssigned" }) do
  out[#out+1] = f .. "=" .. tostring(g:get_field(f))
end
for _, m in ipairs({ "isDisableDash", "isRestrictedDash", "isDisableJump", "isDisableSheathe" }) do
  local ok, v = pcall(function() return g:call(m) end); out[#out+1] = m .. "=" .. tostring(v)
end
local pc = g:get_field("PlChara"); out[#out+1] = "PlChara=" .. tostring(pc and pc:call("get_GameObject"):call("get_Name"))
local bl = g:get_field("BtnList")
if bl then
  local n = bl:call("get_Count")
  for i = 0, n - 1 do
    local b = bl:call("get_Item", i)
    local parts = { "btn" .. i }
    local t = b:get_type_definition()
    for _, f in ipairs(t:get_fields()) do
      if not f:is_static() then
        local v; pcall(function() v = b:get_field(f:get_name()) end)
        local s = tostring(v)
        if type(v) == "userdata" then pcall(function() s = v:get_type_definition():get_name(); local m = v:call("get_Message"); if m then s = s .. ":" .. tostring(m) end end) end
        parts[#parts+1] = f:get_name() .. "=" .. s:sub(1, 40)
      end
    end
    out[#out+1] = table.concat(parts, " ")
  end
end
local um = sdk.get_managed_singleton("app.UserInputManager")
pcall(function()
  local al = um:call("getCurrentCharacterPadAssign"):get_field("AssignList")
  local n = al:call("get_Count")
  for i = 0, n - 1 do
    local a = al:call("get_Item", i)
    local act = a:get_field("Action")
    if act == 5 or act == 6 or act == 7 or true then
      local btn = a:get_field("Button")
      if btn == 128 or btn == 4096 or btn == 16 then out[#out+1] = "assign action " .. tostring(act) .. " button " .. tostring(btn) .. " pre " .. tostring(a:get_field("PreInput")) end
    end
  end
end)
return table.concat(out, "\n")
