-- Experiment: have the main pawn itself interact with the nearest interactive object (what AI pawns do when they
-- gather): InteractManager.requestInteractFromAI(object, pointNo, character). Lists what is near first.
-- DO = true to send the request; otherwise it only lists.
local im = sdk.get_managed_singleton("app.InteractManager")
local pw = sdk.get_managed_singleton("app.PawnManager"):call("get_PawnCharacterList")[0]
local pp = pw:call("get_Transform"):call("get_Position")
local rows, best, bd = {}, nil, nil
for _, s in ipairs(im:get_field("InteractiveObjects"):get_field("_entries"):get_elements()) do
  local ok, o = pcall(s.get_field, s, "Value"); if not (ok and o) then ok, o = pcall(s.get_field, s, "value") end
  if ok and o then
    pcall(function()
      local go = o:get_field("<Owner>k__BackingField")
      local p = go:call("get_Transform"):call("get_Position")
      local d = math.sqrt((p.x - pp.x) ^ 2 + (p.y - pp.y) ^ 2 + (p.z - pp.z) ^ 2)
      local en = nil
      pcall(function() en = o:call("get_Valid") end)
      rows[#rows + 1] = { name = go:call("get_Name"), d = d, points = o:call("get_NumInteractPoints"), valid = en, forPlayer = o:get_field("<HasEnabledWorkTargetPlayer>k__BackingField") }
      if d < 6 and tostring(go:call("get_Name")):find("^gm") and (not bd or d < bd) then best, bd = o, d end -- gimmicks only: the pawns themselves are interactive objects too
    end)
  end
end
table.sort(rows, function(a, b) return a.d < b.d end)
local res = "not sent"
if DO and best then
  local ok, r = pcall(im.call, im, "requestInteractFromAI(app.InteractiveObject, System.UInt32, app.Character)", best, 0, pw)
  res = "sent ok=" .. tostring(ok) .. " r=" .. tostring(r)
end
local top = {}
for i = 1, math.min(8, #rows) do top[i] = rows[i] end
pcall(json.dump_file, "DPC_probe_interact_3.json", { n = #rows, nearest = top, result = res, interacting = im:call("isInteracting(app.Character)", pw) })
return string.format("%d objects; nearest %s %.1f m; %s", #rows, top[1] and top[1].name or "-", top[1] and top[1].d or -1, res)
