-- read-only: the red screen widget and its panel, in detail
local out = {}
local D = _G.DPC_dbg
local R, st = D.R, D.state
out[#out+1] = "possessing " .. tostring(st.active) .. " danger_hid " .. tostring(R.danger_hid) .. " hides " .. tostring(R.danger_hides)
local w = sdk.get_managed_singleton("app.GuiManager"):get_field("ScreenEffect")
local p = {}
for _, f in ipairs({ "FlowNow", "PlayerHpRate", "IsAnimEnd", "IsDangerSe", "IsCallDangerSe", "IsReqCritical" }) do p[#p+1] = f .. "=" .. tostring(w:get_field(f)) end
out[#out+1] = table.concat(p, " ")
local function ctl(tag, c)
  local q = { tag }
  for _, m in ipairs({ "get_Name", "get_Visible", "get_ActualVisible", "get_ForceInvisible", "get_Play", "get_PlayFrame", "get_PlayState", "get_StateFinishFrame", "get_NextState", "get_LoopState" }) do
    local ok, v = pcall(c.call, c, m)
    q[#q+1] = m:sub(5) .. "=" .. (ok and tostring(v) or "?")
  end
  out[#out+1] = table.concat(q, " ")
end
local pn = w:get_field("PnlCritical")
ctl("PnlCritical", pn)
pcall(function()
  local kids = pn:call("getChildren()")
  for i, k in ipairs(kids:get_elements()) do if i <= 8 then ctl("  child", k) end end
end)
pcall(function()
  local go = w:call("get_GameObject")
  local gui = go:call("getComponent(System.Type)", sdk.typeof("via.gui.GUI"))
  local view = gui:call("get_View")
  ctl("View", view)
  for i, k in ipairs(view:call("getChildren()"):get_elements()) do if i <= 8 then ctl(" top", k) end end
end)
return table.concat(out, "\n")
