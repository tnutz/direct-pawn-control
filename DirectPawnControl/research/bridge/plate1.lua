-- Read-only: which registered UI objects on GuiManager could be the pawn name / HP plate?
local gm = sdk.get_managed_singleton("app.GuiManager")
local r = {}
local function scan(o, label)
  local td = o:get_type_definition()
  local hits = {}
  for _, f in ipairs(td:get_fields()) do
    local n = f:get_name()
    if n:find("Hp") or n:find("HP") or n:find("Gauge") or n:find("Name") or n:find("Pawn") or n:find("Chara") or n:find("Job") or n:find("Pos") or n:find("Target") then hits[#hits + 1] = n .. ":" .. f:get_type():get_name() end
  end
  if #hits > 0 then r[#r + 1] = label .. " <" .. td:get_full_name() .. "> " .. table.concat(hits, ",") end
end
for _, f in ipairs(gm:get_type_definition():get_fields()) do
  local ok, v = pcall(gm.get_field, gm, f:get_name())
  if ok and type(v) == "userdata" then
    pcall(function()
      local tn = v:get_type_definition():get_full_name()
      if tn:find("^app%.ui") then scan(v, f:get_name())
      elseif tn:find("List") or tn:find("Dictionary") then
        local cnt = v:call("get_Count")
        if cnt and cnt > 0 and (tn:find("app%.ui") or f:get_name():find("Pawn") or f:get_name():find("Head") or f:get_name():find("Name")) then
          r[#r + 1] = f:get_name() .. " " .. tn .. " count " .. cnt
          if tn:find("List") then local e = v:call("get_Item", 0); if e then scan(e, f:get_name() .. "[0]") end end
        end
      end
    end)
  end
end
return table.concat(r, " | ")
