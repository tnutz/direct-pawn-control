-- Test-enemy spawner (bridge state). Same pipeline as EncounterDirector's waveEngine:
-- GenerateManager.requestCreateInstance(PrefabController, GenerateInfoContainer, requestID, InstanceInfo, nil, nil)
-- Usage: set SPAWN_CID / SPAWN_COUNT / SPAWN_DIST below; spawned units are tracked in _G.SP.units.
local SPAWN_CID, SPAWN_COUNT, SPAWN_DIST = _G.SPAWN_CID or "ch220000_00", _G.SPAWN_COUNT or 1, _G.SPAWN_DIST or 14.0
local out = {}
_G.SP = _G.SP or { pending = {}, units = {} }
local SP = _G.SP

if not SP.charmap then
  SP.charmap = {}
  for _, f in ipairs(sdk.find_type_definition("app.CharacterID"):get_fields()) do
    if f:is_static() then
      local ok, v = pcall(f.get_data, f, nil)
      if ok and type(v) == "number" then SP.charmap[f:get_name()] = v end
    end
  end
end
if not SP.mreq then
  for _, m in ipairs(sdk.find_type_definition("app.GenerateManager"):get_methods()) do
    if m:get_name() == "requestCreateInstance" then
      local pt = m:get_param_types()
      if #pt == 6 and pt[1]:get_name() == "PrefabController" then SP.mreq = m end
    end
  end
end

local function prefab_for(charID)
  local gm = sdk.get_managed_singleton("app.GenerateManager")
  local cc = gm:get_field("_CatalogCtrl")
  local ec = cc:get_field("_EnemyCatalog")
  local merged = ec:get_field("<MergedCatalog>k__BackingField")
  local item = merged:get_Item(charID)
  return item and item:get_Item()
end

local cm = sdk.get_managed_singleton("app.CharacterManager")
local ar = cm:get_ManualPlayer()
local xf = ar:get_Transform()
local pos = xf:get_Position()
local rot = xf:get_Rotation()
-- forward vector of the Arisen
local fwd = rot * Vector3f.new(0, 0, 1)
local sa = math.rad(_G.SPAWN_ANGLE or 0)
fwd = Vector3f.new(fwd.x * math.cos(sa) + fwd.z * math.sin(sa), 0, -fwd.x * math.sin(sa) + fwd.z * math.cos(sa))
local wos = sdk.get_managed_singleton("app.WorldOffsetSystem")
local charID = SP.charmap[SPAWN_CID]
local pctrl = charID and prefab_for(charID)
out[#out+1] = "charID=" .. tostring(charID) .. " prefab=" .. tostring(pctrl ~= nil) .. " mreq=" .. tostring(SP.mreq ~= nil)
if not (charID and pctrl and SP.mreq and wos) then return out end
pcall(function() pctrl:get_Item():set_Standby(true) end)
local gm = sdk.get_managed_singleton("app.GenerateManager")
for i = 1, SPAWN_COUNT do
  local side = (i - (SPAWN_COUNT + 1) / 2) * 2.5
  local lp = Vector3f.new(pos.x + fwd.x * SPAWN_DIST + fwd.z * side, pos.y + 0.5, pos.z + fwd.z * SPAWN_DIST - fwd.x * side)
  local up = wos:call("toUniversalPosition", lp)
  local inst = sdk.create_instance("app.InstanceInfo"):add_ref()
  local cont = inst:get_Container()
  local idw = gm:getIdWrapper(charID)
  pcall(function() cont._CommonInfo:set_ObjectID(sdk.to_ptr(idw)) end)
  pcall(function() cont._CommonInfo._ObjectID._SelectedCharacterID = charID end)
  cont._CommonInfo:setContextPosition(up)
  cont._CommonInfo:setContextAngle(rot)
  cont._CharaInfo._IsThinkStop = (_G.SPAWN_THINKSTOP ~= false)
  SP.pending[#SP.pending+1] = { cid = SPAWN_CID, pctrl = pctrl, cont = cont, inst = inst, rid = math.random(20000, 89999), status = 1, t0 = os.clock() }
end
if not SP.cb then
  SP.cb = true
  re.on_pre_application_entry("UpdateBehavior", function()
    local S = _G.SP
    if #S.pending == 0 then return end
    local g = sdk.get_managed_singleton("app.GenerateManager")
    for i = #S.pending, 1, -1 do
      local p = S.pending[i]
      local ok, err = pcall(function()
        if p.status == 1 then
          if p.pctrl:get_Item():get_Ready() then
            S.mreq:call(g, p.pctrl, p.cont, p.rid, p.inst, nil, nil)
            p.status = 4
          end
        elseif p.status == 4 then
          local ch = p.inst:get_Chara()
          if ch then
            S.units[#S.units+1] = { chara = ch:add_ref(), cid = p.cid, inst = p.inst, addr = ch:get_address() }
            table.remove(S.pending, i)
          end
        end
      end)
      if not ok or os.clock() - p.t0 > 20 then
        log.info("[SP] spawn dropped: " .. tostring(err))
        table.remove(S.pending, i)
      end
    end
  end)
end
out[#out+1] = "queued " .. SPAWN_COUNT .. " x " .. SPAWN_CID .. " at " .. SPAWN_DIST .. " m at angle " .. tostring(_G.SPAWN_ANGLE or 0)
return out
