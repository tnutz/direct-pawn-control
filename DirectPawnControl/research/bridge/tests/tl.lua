-- Frame timeline: at which points in the frame does the Arisen's CharacterInput carry a button?  45 s.
_G.TL = { t0 = os.clock(), dur = 45, pat = {}, frames = 0, done = false, cur = "" }
local pts = { "preUB", "PlayerPre", "PlayerPost", "postUB", "preLUB", "postLUB", "preBR", "preEndR" }
local function inp() return sdk.get_managed_singleton("app.CharacterManager"):get_ManualPlayer():call("get_Input") end
local function mark(tag)
  local T = _G.TL
  if T.done then return end
  local ok, on = pcall(function() return inp():get_field("ButtonOnFlags") end)
  T.cur = T.cur .. ((ok and on ~= 0) and "1" or "0")
end
_G.TL_F = function(tag)
  local T = _G.TL
  if not T or T.done then return end
  if tag == "preUB" then
    if #T.cur > 0 then T.pat[T.cur] = (T.pat[T.cur] or 0) + 1 end
    T.cur = ""; T.frames = T.frames + 1
    if os.clock() - T.t0 > T.dur then T.done = true; T.order = table.concat(pts, ","); json.dump_file("agent_bridge/tl.json", T); return end
  end
  mark(tag)
end
if not _G.TL_CB then
  _G.TL_CB = true
  re.on_pre_application_entry("UpdateBehavior", function() if _G.TL_F then _G.TL_F("preUB") end end)
  re.on_application_entry("UpdateBehavior", function() if _G.TL_F then _G.TL_F("postUB") end end)
  re.on_pre_application_entry("LateUpdateBehavior", function() if _G.TL_F then _G.TL_F("preLUB") end end)
  re.on_application_entry("LateUpdateBehavior", function() if _G.TL_F then _G.TL_F("postLUB") end end)
  re.on_pre_application_entry("BeginRendering", function() if _G.TL_F then _G.TL_F("preBR") end end)
  re.on_pre_application_entry("EndRendering", function() if _G.TL_F then _G.TL_F("preEndR") end end)
  sdk.hook(sdk.find_type_definition("app.Player"):get_method("update"),
    function(args) if _G.TL_F then _G.TL_F("PlayerPre") end end,
    function(r) if _G.TL_F then _G.TL_F("PlayerPost") end return r end)
end
return { "timeline probe 45 s" }
