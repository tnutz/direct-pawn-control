-- Onsen (hot spring) report, Nexus 2026-11-26 (grovermclurg): "Freezes game if used while sitting in onsen".
-- Run it while the Arisen and the party are IN the onsen, before taking anything over. Read-only.
-- Question: is bathing an InteractManager object interaction (what R.busy_interact sees, like the tavern lean), or
-- only the onsen's own system (app.SpaManager and its SpaState* states, which the decompile shows controlling the
-- player's and party's positions: SpaRequestContainer.setupCharacterControlListPlayer, SpaStateCharacterPosControl)?
-- If getActiveInteract is nil for everyone while bathing, DPC's lean guards don't see the onsen and a take-over
-- needs its own check (e.g. refuse or wait while SpaManager is active).
local out = {}
local function add(s) out[#out + 1] = tostring(s) end
local function tn(o) local ok, n = pcall(function() return o:get_type_definition():get_full_name() end); return ok and n or "?" end
local function fields(o, max)
  local l = {}
  local ok = pcall(function()
    local td = o:get_type_definition()
    while td and #l < (max or 60) do
      for _, f in ipairs(td:get_fields()) do
        if not f:is_static() then
          local okv, v = pcall(f.get_data, f, o)
          local s = okv and (type(v) == "userdata" and ("<" .. tn(v) .. ">") or tostring(v)) or "?"
          l[#l + 1] = f:get_name() .. "=" .. s
        end
      end
      td = td:get_parent_type()
      if td and td:get_full_name():find("^System%.") then break end
    end
  end)
  if not ok then l[#l + 1] = "(fields failed)" end
  return table.concat(l, ", ")
end
local spa = sdk.get_managed_singleton("app.SpaManager")
add("SpaManager: " .. (spa and tn(spa) or "nil"))
if spa then add("  " .. fields(spa, 80)) end
local im = sdk.get_managed_singleton("app.InteractManager")
local function who(ch, label)
  if not ch then add(label .. ": nil"); return end
  local ai = im and select(2, pcall(im.call, im, "getActiveInteract(app.Character)", ch))
  local fsm = ch:call("get_ActionManager"):get_field("Fsm")
  local n0 = fsm and tostring(fsm:call("getCurrentNodeName(System.UInt32)", 0)) or "?"
  local n1 = fsm and tostring(fsm:call("getCurrentNodeName(System.UInt32)", 1)) or "?"
  local cmd = "?"
  pcall(function()
    local ex = ch:call("get_AIDecisionMaker"):call("get_DecisionModule"):call("get_ActionInterface"):call("get_Executor")
    local p = ex:get_field("_CommandExecutor"):get_field("_PrimaryCommand")
    cmd = p and tn(p) or "none"
  end)
  local dec = "?"
  pcall(function()
    local d = ch:call("get_AIDecisionMaker"):call("get_DecisionModule"):call("get_DecisionExecutor"):call("get_ExecutingDecision")
    dec = d and tostring(d:call("get_PackPath") or tn(d)) or "none"
  end)
  add(string.format("%s: activeInteract=%s nodes=%s | %s cmd=%s decision=%s", label, ai and tn(ai) or "nil", n0, n1, cmd, dec))
  if ai and type(ai) == "userdata" then add("  interact: " .. fields(ai, 30)) end
end
who(sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer"), "Arisen")
local list = sdk.get_managed_singleton("app.PawnManager"):call("get_PawnCharacterList")
for i = 0, (list and list:call("get_Count") or 0) - 1 do who(list:call("get_Item", i), "pawn " .. i) end
return table.concat(out, "\n")
