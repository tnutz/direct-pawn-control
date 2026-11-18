-- Which components does the Arisen's GameObject have that the main pawn's does not (and the reverse)? The
-- interact / gather prompt is driven by something on the player side. Also dumps methods of anything whose name
-- mentions Interact / Gather / Gimmick / Prompt on either. Read-only.
local function comps(ch)
  local t, list = {}, {}
  for _, c in ipairs(ch:get_GameObject():call("get_Components"):get_elements()) do
    local ok, n = pcall(function() return c:get_type_definition():get_full_name() end)
    if ok and n then t[n] = c; list[#list + 1] = n end
  end
  return t, list
end
local ar = sdk.get_managed_singleton("app.CharacterManager"):call("get_ManualPlayer")
local pw = sdk.get_managed_singleton("app.PawnManager"):call("get_PawnCharacterList")[0]
local A, al = comps(ar)
local P, pl = comps(pw)
local onlyA, onlyP, both = {}, {}, {}
for _, n in ipairs(al) do if not P[n] then onlyA[#onlyA + 1] = n else both[#both + 1] = n end end
for _, n in ipairs(pl) do if not A[n] then onlyP[#onlyP + 1] = n end end
local detail = {}
local function dump(n, c)
  local td = c:get_type_definition()
  local l = {}
  for _, f in ipairs(td:get_fields()) do l[#l + 1] = "F " .. f:get_name() .. " : " .. f:get_type():get_full_name() end
  for _, m in ipairs(td:get_methods()) do
    local ps = {}
    for _, pt in ipairs(m:get_param_types()) do ps[#ps + 1] = pt:get_name() end
    l[#l + 1] = "M " .. m:get_name() .. "(" .. table.concat(ps, ",") .. ")"
  end
  detail[n] = l
end
for _, n in ipairs(onlyA) do if n:find("^app%.") then dump(n, A[n]) end end
for n, c in pairs(A) do if (n:find("Interact") or n:find("Gather") or n:find("Prompt")) and not detail[n] then dump(n, c) end end
-- singletons that might own the prompt
local singles = {}
for _, n in ipairs({ "app.InteractManager", "app.GimmickManager", "app.GatherManager", "app.ItemManager", "app.GuiManager", "app.InteractPointManager", "app.PlayerInteractManager", "app.InteractionManager" }) do
  local s = sdk.get_managed_singleton(n)
  singles[n] = s and true or false
  if s and (n:find("Interact") or n:find("Gather")) then dump(n, s) end
end
pcall(json.dump_file, "DPC_probe_interact_1.json", { onlyArisen = onlyA, onlyPawn = onlyP, detail = detail, singletons = singles })
return string.format("arisen %d comps, pawn %d; only arisen %d, only pawn %d", #al, #pl, #onlyA, #onlyP)
