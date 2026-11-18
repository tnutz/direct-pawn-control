-- Where do clicks land while possessed? Scan app.UserInputManager's inputs + Arisen/pawn CharacterInput, 45 s.
_G.WP = { t0 = os.clock(), dur = 45, hits = {}, paths = {}, err = nil, done = false, frames = 0 }
local function has_flags(o)
  local ok, v = pcall(o.get_field, o, "ButtonOnFlags")
  return ok and type(v) == "number"
end
local function collect()
  local list = {}
  local cm = sdk.get_managed_singleton("app.CharacterManager")
  local ar = cm:get_ManualPlayer()
  list[#list+1] = { "arisen.Input", ar:call("get_Input") }
  local cam = sdk.get_managed_singleton("app.CameraManager"):call("getMainCameraController", 0):call("get_TargetCharacter")
  if cam then list[#list+1] = { "camtarget.Input", cam:call("get_Input") } end
  local uim = sdk.get_managed_singleton("app.UserInputManager")
  if uim then
    for _, f in ipairs(uim:get_type_definition():get_fields()) do
      if not f:is_static() then
        local ok, v = pcall(f.get_data, f, uim)
        if ok and type(v) == "userdata" and v.get_type_definition then
          local okn, tn = pcall(function() return v:get_type_definition():get_full_name() end)
          if okn then
            if has_flags(v) then list[#list+1] = { "UIM." .. f:get_name(), v }
            else
              local okc, n = pcall(v.call, v, "get_Count")
              if not okc then okc, n = pcall(v.call, v, "get_Length") end
              if okc and type(n) == "number" and n < 16 then
                for i = 0, n - 1 do
                  local oki, it = pcall(function() return v[i] end)
                  if oki and it and has_flags(it) then list[#list+1] = { "UIM." .. f:get_name() .. "[" .. i .. "]", it } end
                end
              end
            end
          end
        end
      end
    end
  end
  return list
end
_G.WP.list = nil
if not _G.WP_CB then
  _G.WP_CB = true
  re.on_pre_application_entry("LateUpdateBehavior", function() if _G.WP_FN then _G.WP_FN() end end)
end
_G.WP_FN = function()
  local W = _G.WP
  if W.done then return end
  if os.clock() - W.t0 > W.dur then W.done = true; W.list = nil; json.dump_file("agent_bridge/wp.json", W); return end
  local ok, err = pcall(function()
    if not W.list then W.list = collect(); for _, e in ipairs(W.list) do W.paths[#W.paths+1] = e[1] end end
    W.frames = W.frames + 1
    for _, e in ipairs(W.list) do
      local on = e[2]:get_field("ButtonOnFlags")
      if on ~= 0 then
        local h = W.hits[e[1]] or { n = 0, bits = 0 }
        h.n = h.n + 1; h.bits = h.bits | on
        W.hits[e[1]] = h
      end
    end
  end)
  if not ok then W.err = tostring(err) end
end
return { "wide probe 45 s" }
