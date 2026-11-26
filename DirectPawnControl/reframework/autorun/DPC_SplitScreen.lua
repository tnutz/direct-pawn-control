-- DPC Split Screen: one view per player for Direct Pawn Control's couch co-op (two to four players).
--
-- Built on guitarguy1104's DD2CouchCoop (pre-alpha 1.0 build 12, sent 2026-11-19: "the logic for these mods is all
-- yours to use as you see fit"). From his findings:
--   * Player 2's view is drawn by the scene's spare "UserEditCamera" GameObject, given a via.render.RenderOutput.
--     Each view's RenderOutput gets a Region (via.Rect, 0..1 of the screen); each camera an AspectRatio to match.
--   * The camera pose is written into the camera Transform's world matrix (+0x80) and local position / rotation
--     (+0x30 / +0x40) at BeginRendering, after the game's own camera update. The layout is checked once first.
--   * The game moves characters relative to the main camera, so player 2's left stick is turned by the yaw between
--     the two views (here through DPC's API 1.3 set_view_turn).
--   * Post effects are copied from the main camera to player 2's (every via.render.* component except the output,
--     capture, depth of field and custom filters); directional lights cast shadows per RenderOutput; player 2 gets
--     a second sound listener and see-through controller; enemies player 1's camera culls stay drawn if player 2 sees
--     them.
-- Not taken: his native DLL (Wwise listener routing, TAA settings, primary camera), the cloned camera rig (planned
-- for a later build), the HUD copies and menu handling.
--
-- Found in game (2026-11-25): DLSS frame generation draws the extra views black and loses the graphics device when one
-- is switched off and on; upscaling and dynamic resolution are fine. The split stays off while frame generation is
-- on. 0.2: players 3 and 4 (three across, a 2 x 2 grid with a spare quarter, four across), DPC's bars and cards in
-- each player's own view (DPC 0.9.177-dev39, API set_view_list), the split kept through menus.
--
-- Needs Direct Pawn Control 0.9.177-dev39 or later. Settings: Script Generated UI > DPC Split Screen.

local VERSION = "0.2.0"
local CFG_FILE = "DPC_SplitScreen.json"

local cfg = {
    enabled = false, -- dev24: off by default (early release; the co-op camera row in DPC's settings turns it on)
    layout = 1, -- two players: 1 auto (side by side on wide screens), 2 side by side, 3 top and bottom
    layout3 = 1, -- three players: 1 auto (three across on wide screens), 2 three across, 3 a 2 x 2 grid
    layout4 = 1, -- four players: 1 a 2 x 2 grid, 2 four across
    spare = 2, -- three players in a grid, the fourth quarter: 1 blank, 2 an overview of the party from above
    menus_keep = true, -- keep the split while a menu is open (no switch to one view and back)
    fit_hud_16 = false,
    fit_hud_18 = false,
    fit_hud_21 = false,
    pfx_light_23 = false,
    hud_scale = 1.0, -- dev21: extra size for the fitted HUD (1 = the size the height fit gives; tried live)
    fit_hud = true, -- dev21: on (height-only fit, the version that looked right). dev20: off (dev18's model failed in game too). dev18: on (model fitted to four in-game results, see gui_fit). dev17: off again (dev16 drew the HUD too big, into player 2's view). dev14: the game's HUD in player 1's view is laid out for that view's shape. dev15: off, experiment (see MODLOG: ScreenSize scales about the top-left corner, it cannot also move the HUD into the view)
    pcam = {}, -- dev13: players 2-4's Camera Distance preset by player ("p2" = index into CameraDistance_API.presets(); 0 / nil = this mod's Distance / Height)
    cam_distance = 3.6,
    cam_height = 1.5,
    cam_speed = 2.6,
    invert_x = false,
    invert_y = false,
    fov_scale = 1.0,
    turn_flip = false, -- if player 2 walks the wrong way in his view, this flips the stick turn
    divider = true,
    post_effects = true,
    shadows = true,
    listener = true,
    sound_from = 2, -- dev12: sound heard from 1 player 1's view (the game's), 2 the middle of the players (DPC 0.9.177-dev50+ moves the listener)
    see_through = true,
    no_near_fade = true, -- dev11: players' characters don't fade out when player 1's camera is close (it faded them in every view)
    keep_seen = true, -- enemies player 2 sees are not culled by player 1's camera
    own_pfx = false,
    own_pfx_light = false, -- dev23: off again until tested (a GPU hang followed dev19; photo mode or these components) -- dev19: players 3-4's cameras get only the brightness / colour components (ToneMapping, ColorCorrect); all 19 crashed (dev7)
    mirror = true, -- dev10: keep hidden extra cameras on the main camera's pose while one view (stutter tests) -- dev7: build post-effect components on cameras this script makes (every crash came after that)
    view_scale = 1.0, -- dev6: render scale of players 2-4's views (RenderOutput ImageQuality x this), for the 4-view crash tests
    p2_output_id = 0, -- 0 = Tertiary (4) on a RenderOutput this script adds; 1 / 2 / 4 / 8 / 16 to try others
}
do
    local ok, saved = pcall(json.load_file, CFG_FILE)
    if ok and type(saved) == "table" then
        for k, v in pairs(saved) do if cfg[k] ~= nil and type(cfg[k]) == type(v) then cfg[k] = v end end
    end
    if not cfg.pfx_light_23 then cfg.own_pfx_light, cfg.pfx_light_23 = false, true end -- dev23: off once
    if not cfg.fit_hud_21 then cfg.fit_hud, cfg.fit_hud_21 = true, true end -- dev21: on once

end
local function save_cfg() pcall(json.dump_file, CFG_FILE, cfg) end

local S = { version = VERSION, active = false, cfg = cfg, halted = nil, save = save_cfg, -- save: TestGuide 2.7.4
    st = { frames = 0, starts = 0, stops = 0, errors = 0, turns = 0, angle_fix = 0, kept = 0, suspended_by = nil,
        last_error = nil, why_off = nil } }
_G.DPC_SplitScreen = S
local st = S.st

local rlog = log
local function log(m) rlog.info("[DPC Split Screen] " .. tostring(m)) end
local function fail(where, err)
    st.errors = st.errors + 1
    st.last_error = where .. ": " .. tostring(err)
    log("ERROR " .. st.last_error)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Math (quaternions as { x, y, z, w })
-- ---------------------------------------------------------------------------------------------------------------
local function qmul(a, b)
    return {
        a[4] * b[1] + a[1] * b[4] + a[2] * b[3] - a[3] * b[2],
        a[4] * b[2] - a[1] * b[3] + a[2] * b[4] + a[3] * b[1],
        a[4] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[4],
        a[4] * b[4] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3],
    }
end
local function qrotate(q, v)
    local p = qmul(qmul(q, { v[1], v[2], v[3], 0 }), { -q[1], -q[2], -q[3], q[4] })
    return { p[1], p[2], p[3] }
end
-- which way a camera looks along its Z (-1 or +1): measured when the split starts, from where player 1 stands
local FWD = { -1 }
local function cam_forward(q) return qrotate(q, { 0, 0, FWD[1] }) end
local function yaw_of(f) return math.atan(f[1] * FWD[1], f[3] * FWD[1]) end

-- ---------------------------------------------------------------------------------------------------------------
-- Game objects
-- ---------------------------------------------------------------------------------------------------------------
local WORLD_MATRIX_OFFSET, LOCAL_POSITION_OFFSET, LOCAL_ROTATION_OFFSET = 0x80, 0x30, 0x40
local P2_HOST = "UserEditCamera"
local SM_T = sdk.find_type_definition("via.SceneManager")
local RECT_T = sdk.find_type_definition("via.Rect")
local GO_CREATE = sdk.find_type_definition("via.GameObject"):get_method("create(System.String, via.Folder)")

local function scene()
    local sm = sdk.get_native_singleton("via.SceneManager")
    return sm and sdk.call_native_func(sm, SM_T, "get_CurrentScene")
end
-- managed arrays: get_elements where it exists, else get_size / get_element (dev2: findComponents returned an
-- array without get_elements in the first test)
local function elems(arr)
    if arr == nil then return {} end
    local out = {}
    -- dev3: get_elements gives a userdata list (not a Lua table) for via.Component[]; dev2 rejected it, so no post
    -- effects were copied and player 2's half drew black. Copy whatever it gives into a plain table.
    local ok, t = pcall(function() return arr:get_elements() end)
    if ok and t ~= nil then
        pcall(function() for i = 1, #t do out[#out + 1] = t[i] end end)
        if #out > 0 then return out end
    end
    pcall(function() for i = 0, arr:get_size() - 1 do out[#out + 1] = arr:get_element(i) end end)
    return out
end
local function rect(v)
    local r = ValueType.new(RECT_T)
    r.l, r.t, r.r, r.b = v[1], v[2], v[3], v[4]
    return r
end

local V = { main = nil, p2 = nil, matrix_ok = nil, layout_key = nil, disp_w = nil, disp_h = nil }
S.views = V

local function find_main()
    if V.main and pcall(function() assert(V.main.go:call("get_Valid")) end) then return V.main end
    V.main = nil
    local sc = scene()
    local go = sc and sc:call("findGameObject(System.String)", "MainCamera")
    if not go then return nil end
    local m = { go = go:add_ref() }
    m.cam = go:call("getComponent(System.Type)", sdk.typeof("via.Camera")):add_ref()
    m.ro = go:call("getComponent(System.Type)", sdk.typeof("via.render.RenderOutput")):add_ref()
    m.t = go:call("get_Transform"):add_ref()
    m.saved_aspect = m.cam:call("get_AspectRatio")
    local ctrls = sc:call("findComponents(System.Type)", sdk.typeof("app.MainCameraController"))
    local list = elems(ctrls)
    m.mcc = list[1] and list[1]:add_ref() or nil
    V.main = m
    return m
end

local function check_matrix(t)
    local w = t:call("get_WorldMatrix")
    for row = 0, 3 do
        local v = w[row]
        local want = { v.x, v.y, v.z, v.w }
        for c = 0, 3 do
            if math.abs(t:read_float(WORLD_MATRIX_OFFSET + row * 16 + c * 4) - want[c + 1]) > 1e-3 then return false end
        end
    end
    return true
end

local function write_pose(t, pos, q)
    local rows = { qrotate(q, { 1, 0, 0 }), qrotate(q, { 0, 1, 0 }), qrotate(q, { 0, 0, 1 }) }
    for r = 1, 3 do
        local base = WORLD_MATRIX_OFFSET + (r - 1) * 16
        t:write_float(base, rows[r][1]); t:write_float(base + 4, rows[r][2])
        t:write_float(base + 8, rows[r][3]); t:write_float(base + 12, 0.0)
    end
    local base = WORLD_MATRIX_OFFSET + 48
    t:write_float(base, pos[1]); t:write_float(base + 4, pos[2]); t:write_float(base + 8, pos[3])
    t:write_float(base + 12, 1.0)
    t:write_float(LOCAL_POSITION_OFFSET, pos[1]); t:write_float(LOCAL_POSITION_OFFSET + 4, pos[2])
    t:write_float(LOCAL_POSITION_OFFSET + 8, pos[3])
    for i = 1, 4 do t:write_float(LOCAL_ROTATION_OFFSET + (i - 1) * 4, q[i]) end
end

-- post effects (guitarguy1104's build_pfx / copy_pfx)
local PFX_EXCLUDE = { ["via.render.RenderOutput"] = true, ["via.render.CaptureToTexture"] = true,
    ["via.render.DepthOfField"] = true, ["via.render.CustomFilter"] = true }
local function copyable(rt)
    local n = rt:get_full_name()
    return not (n:find("GameObject") or n:find("Ref$") or n:find("Component") or n:find("Transform")
        or n:find("Folder") or n:find("Camera") or n:find("Light"))
end
-- dev19 (the tester: "why the large difference in brightness with the 3rd pane much brighter?"): cameras this script makes
-- had no post effects since dev7 (the full set of 19 crashed the GPU), so no tone mapping / exposure / colour grading.
-- With own_pfx_light they get only these. Made once per camera and kept, like the rest.
local PFX_LIGHT = { ["via.render.ToneMapping"] = true, ["via.render.ColorCorrect"] = true }
local function build_pfx(p2, main, only)
    p2.pfx = {}
    for _, src in ipairs(elems(main.go:call("get_Components"))) do
        local td = src:get_type_definition()
        local tn = td:get_full_name()
        if tn:find("^via%.render%.") and not PFX_EXCLUDE[tn] and (not only or only[tn]) then
            local dst = p2.go:call("getComponent(System.Type)", sdk.typeof(tn))
            if dst == nil then
                dst = p2.go:call("createComponent(System.Type)", sdk.typeof(tn))
                if dst then p2.created[#p2.created + 1] = dst:add_ref() end
            end
            -- dev8: keep the getter / setter method objects (dev7 looked each one up by name on every copy)
            local setters, props = {}, {}
            for _, m in ipairs(td:get_methods()) do
                local n = m:get_name()
                if n:sub(1, 4) == "set_" and m:get_num_params() == 1 then setters[n:sub(5)] = m end
            end
            for _, m in ipairs(td:get_methods()) do
                local n, rt = m:get_name(), m:get_return_type()
                if n:sub(1, 4) == "get_" and m:get_num_params() == 0 and setters[n:sub(5)] and rt and copyable(rt)
                    and n ~= "get_CameraObject" then
                    props[#props + 1] = { g = m, s = setters[n:sub(5)] }
                end
            end
            if dst then p2.pfx[#p2.pfx + 1] = { src = src:add_ref(), dst = dst:add_ref(), props = props, tonemap = tn == "via.render.ToneMapping" } end
        end
    end
end
-- dev8: one component per call (the caller spreads them over frames); a property that throws once is dropped
local function copy_pfx_one(e)
    local keep = {}
    for _, pr in ipairs(e.props) do
        if pcall(pr.s.call, pr.s, e.dst, pr.g:call(e.src)) then keep[#keep + 1] = pr end
    end
    e.props = keep
    if e.tonemap then pcall(function() e.dst:call("setAutoExposure", e.src:call("getAutoExposure")) end) end
end
local function copy_pfx(p2)
    for _, e in ipairs(p2.pfx or {}) do copy_pfx_one(e) end
end

-- second sound listener (guitarguy1104's add_p2_listener, without the native Wwise routing)
local LISTENER = "soundlib.SoundListener"
local function sound_call(m, arg) return sdk.find_type_definition("soundlib.SoundManager"):get_method(m):call(nil, arg) end
local function add_listener(p2, main)
    local p1l = main.go:call("getComponent(System.Type)", sdk.typeof(LISTENER))
    local l = p2.go:call("getComponent(System.Type)", sdk.typeof(LISTENER))
    p2.listener_created = l == nil
    if l == nil then l = p2.go:call("createComponent(System.Type)", sdk.typeof(LISTENER)) end
    if l == nil then return end
    l = l:add_ref()
    l:set_field("_ListenerIdx", 1)
    if p1l then
        for _, f in ipairs({ "_SyncFOV", "_SyncNearClipPlane", "_EnableAxisY", "_InvertAxisZ", "_Offset" }) do
            pcall(function() l:set_field(f, p1l:get_field(f)) end)
        end
    end
    p2.listener_go = p2.listener_go or GO_CREATE:call(nil, "DPCSplit_P2Listener", main.go:call("get_Folder"):call("get_Parent")):add_ref()
    pcall(function() l:call("set_OffsetGameObj", p2.listener_go) end)
    pcall(function() l:call("set_IsCalcDistanceDecayAtPlayerPos", false) end)
    pcall(function() l:set_field("_Camera", p2.cam) end)
    pcall(function() l:call("activateListener") end)
    pcall(sound_call, "addListener", l)
    p2.listener = l
    log("player 2's sound listener added")
end
local function remove_listener(p2, main)
    local l = p2.listener
    if not l then return end
    p2.listener = nil
    pcall(function() l:call("deactivateListener") end)
    pcall(sound_call, "removeListener", l)
    local p1l = main and main.go:call("getComponent(System.Type)", sdk.typeof(LISTENER))
    if p1l then pcall(sound_call, "addListener", p1l) end
end

local SEE_THROUGH = "app.SeeThroughController"
local function add_see_through(p2, main)
    local p1c = main.go:call("getComponent(System.Type)", sdk.typeof(SEE_THROUGH))
    local c = p2.go:call("getComponent(System.Type)", sdk.typeof(SEE_THROUGH))
    local created = c == nil
    if c == nil then c = p2.go:call("createComponent(System.Type)", sdk.typeof(SEE_THROUGH)) end
    if c == nil then return end
    c = c:add_ref()
    if p1c then for _, f in ipairs({ "_RayCheckIntervalFrame", "_RayRadius" }) do pcall(function() c:set_field(f, p1c:get_field(f)) end) end end
    c:set_field("_Camera", p2.cam)
    p2.see_through, p2.see_through_created, p2.see_through_c = c, created, c
end
local function remove_see_through(p2)
    local c = p2.see_through
    if not c then return end
    p2.see_through = nil
    pcall(function() c:call("set_Enabled", false) end)
end

local shadows = { saved = {} }
local SUN_T = sdk.typeof("via.render.DirectionalLight")
local shadow_t = 0
local function each_sun(fn)
    if not SUN_T then return end
    local sc = scene()
    local arr = sc and sc:call("findComponents(System.Type)", SUN_T)
    for _, l in ipairs(elems(arr)) do fn(l, l:get_address()) end
end
-- dev19 (the tester: "shadows are popping in and out"): the flag was set again only every 5 s and the game turns it back
-- off in between (new light objects as you move, time of day), so a view lost its shadows for up to 5 s. Now the
-- lights are found every 5 s (the scene search is the slow part) and their flag checked 5 times a second.
shadows.lights = {}
shadows.resets = 0
local function find_suns()
    local list = {}
    each_sun(function(l, a) list[#list + 1] = l:add_ref() end)
    shadows.lights = list
end
local function apply_shadows()
    for _, l in ipairs(shadows.lights) do
        pcall(function()
            local a = l:get_address()
            local now = l:call("get_PerRenderOutputShadowCast")
            if shadows.saved[a] == nil then shadows.saved[a] = now end
            if not now then l:call("set_PerRenderOutputShadowCast", true); shadows.resets = shadows.resets + 1 end
        end)
    end
end
local function restore_shadows()
    if next(shadows.saved) == nil then return end
    each_sun(function(l, a) local v = shadows.saved[a]; if v ~= nil then pcall(l.call, l, "set_PerRenderOutputShadowCast", v) end end)
    shadows.saved = {}
end


-- ---------------------------------------------------------------------------------------------------------------
-- Extra views: player 2 on the scene's UserEditCamera, players 3 / 4 and the overview on cameras this script makes.
-- Nothing here is ever destroyed while the game runs (switched off and reused): the first test lost the graphics
-- device after a few destroy / create cycles.
-- ---------------------------------------------------------------------------------------------------------------
local api = nil
local OUTPUT_ID = { [2] = 4, [3] = 2, [4] = 16, ov = 16 } -- RenderOutputID mask bits (main = 1)
V.ex = {} -- key (2, 3, 4, "ov") -> view
V.kept = {}

local function ro_setup(v, main, key)
    S.ro_before = S.ro_before or {}
    for _, n in ipairs({ "ImageQuality", "HorizontalScreenScale", "ManualAspectUse", "Interleave", "DistortionType",
        "BackgroundColor", "ForceUseClearBackgroundColor", "UseCustomSceneLayer", "Cutscene" }) do
        local okm, mv = pcall(function() return main.ro:call("get_" .. n) end)
        if v.created_ro and okm then pcall(function() v.ro:call("set_" .. n, mv) end) end
    end
    local id = OUTPUT_ID[key] or 2
    if key == 2 and cfg.p2_output_id > 0 then id = cfg.p2_output_id end
    if v.created_ro or (key == 2 and cfg.p2_output_id > 0) then pcall(function() v.ro:call("set_RenderOutputID", id) end) end
    pcall(function() v.out_id = v.ro:call("get_RenderOutputID") end)
    -- dev6: ImageQuality is a float (a render scale). Remember main's, apply view_scale, log both.
    pcall(function()
        v.iq_base = main.ro:call("get_ImageQuality")
        if cfg.view_scale < 0.999 then v.ro:call("set_ImageQuality", v.iq_base * cfg.view_scale) end
        S.iq = string.format("main %.2f, view %s %.2f", v.iq_base, tostring(key), v.ro:call("get_ImageQuality"))
        log("image quality: " .. S.iq)
    end)
    if key == 2 then S.ro_after = tostring(v.out_id) end
end

local function make_view(main, key)
    local k = V.kept[key]
    if k and pcall(function() assert(k.go:call("get_Valid")) end) then
        V.kept[key] = nil
        k.cam:call("set_VerticalEnable", main.cam:call("get_VerticalEnable"))
        if cfg.post_effects and (not k.own or cfg.own_pfx or cfg.own_pfx_light) then if #(k.pfx or {}) == 0 then build_pfx(k, main, (k.own and not cfg.own_pfx) and PFX_LIGHT or nil) end; copy_pfx(k) end
        if key == 2 and cfg.listener then pcall(add_listener, k, main) end
        if key == 2 and cfg.see_through then
            if k.see_through_c then pcall(function() k.see_through_c:call("set_Enabled", true) end); k.see_through = k.see_through_c
            else pcall(add_see_through, k, main) end
        end
        return k
    end
    V.kept[key] = nil
    local v = { key = key, created = {} }
    local go
    if key == 2 then
        local sc = scene()
        go = sc and sc:call("findGameObject(System.String)", P2_HOST)
        if go == nil then error("no " .. P2_HOST .. " object in this scene") end
    else
        local name = "DPCSplit_View_" .. tostring(key)
        local sc = scene()
        go = sc and sc:call("findGameObject(System.String)", name) -- left from before a Reset Scripts
        if go == nil then go = GO_CREATE:call(nil, name, main.go:call("get_Folder")) end
        if go == nil then error("could not make a camera for view " .. tostring(key)) end
    end
    v.go = go:add_ref()
    V.leftover[key == 2 and P2_HOST or ("DPCSplit_View_" .. tostring(key))] = nil
    local cam = go:call("getComponent(System.Type)", sdk.typeof("via.Camera"))
    if cam == nil then cam = go:call("createComponent(System.Type)", sdk.typeof("via.Camera")) end
    if cam == nil then error("no camera for view " .. tostring(key)) end
    v.cam = cam:add_ref()
    local ro = go:call("getComponent(System.Type)", sdk.typeof("via.render.RenderOutput"))
    v.created_ro = ro == nil
    v.ro = (ro or go:call("createComponent(System.Type)", sdk.typeof("via.render.RenderOutput"))):add_ref()
    v.t = go:call("get_Transform"):add_ref()
    ro_setup(v, main, key)
    v.cam:call("set_VerticalEnable", main.cam:call("get_VerticalEnable"))
    -- dev7: every four-view crash (GPU hang, DXGI DEVICE_HUNG) came after this script made a camera and built 19
    -- post-effect components on it; player 2's view (the game's own UserEditCamera) never crashed. Cameras this
    -- script makes get no post effects unless own_pfx is on.
    v.own = key ~= 2
    if cfg.post_effects and (not v.own or cfg.own_pfx or cfg.own_pfx_light) then build_pfx(v, main, (v.own and not cfg.own_pfx) and PFX_LIGHT or nil); copy_pfx(v) end
    if key == 2 and cfg.listener then local ok, e = pcall(add_listener, v, main); if not ok then fail("listener", e) end end
    if key == 2 and cfg.see_through then local ok, e = pcall(add_see_through, v, main); if not ok then fail("see-through", e) end end
    v.shown = nil -- show_view sets it
    log(string.format("view %s: %s, output id %s, %d post effects", tostring(key), key == 2 and P2_HOST or "own camera",
        tostring(v.out_id), #(v.pfx or {})))
    if key == 2 then S.pfx_n = #(v.pfx or {}) end
    return v
end

-- dev2: via.render.RenderOutput has no set_Enabled (read live: get_Enabled gives nil), so dev1's "hide" did nothing and
-- player 2's view stayed on the right half after co-op ended. Use a real setter if the type has one, else hide the
-- camera's GameObject (guitarguy1104's fallback). Both are checked once per view.
local function show_view(v, on)
    if not v or v.shown == on then return end
    v.shown = on
    if v.hide_m == nil then
        local td = v.ro:get_type_definition()
        v.hide_m = (td:get_method("set_Enabled") and "set_Enabled") or (td:get_method("set_EnableSelf") and "set_EnableSelf") or false
        S.hide_method = v.hide_m or "GameObject.DrawSelf"
    end
    if v.hide_m then pcall(function() v.ro:call(v.hide_m, on) end) end
    pcall(function() v.go:call("set_DrawSelf", on) end)
end

local function put_away(key, main)
    local v = V.ex[key]
    if not v then return end
    V.ex[key] = nil
    show_view(v, false)
    if key == 2 then pcall(remove_listener, v, main); pcall(remove_see_through, v) end
    V.kept[key] = v
end

-- ---------------------------------------------------------------------------------------------------------------
-- Cameras: an orbit camera per extra player, turned by their right stick; the overview looks down on the party
-- ---------------------------------------------------------------------------------------------------------------
local cams = {} -- key -> { yaw, elev, pos, rot, need_init }
S.cams = cams
local clock = { last = os.clock(), p1_yaw = 0.0 }
S.cam = clock -- p1_yaw (tests)

local function chara_pos(ch)
    local p = ch and ch:call("get_GameObject"):call("get_Transform"):call("get_Position")
    return p and { p.x, p.y, p.z }
end

local function cam_rot(c)
    local qy = { 0, math.sin(c.yaw / 2), 0, math.cos(c.yaw / 2) }
    local pitch = c.elev * FWD[1]
    local qp = { math.sin(pitch / 2), 0, 0, math.cos(pitch / 2) }
    return qmul(qy, qp)
end

local function follow(c, target, dist, dt)
    local f = cam_forward(c.rot)
    local want = { target[1] - f[1] * dist, target[2] - f[2] * dist, target[3] - f[3] * dist }
    if c.pos == nil then c.pos = want
    else
        local k = math.min(1.0, dt * 12.0)
        for i = 1, 3 do c.pos[i] = c.pos[i] + (want[i] - c.pos[i]) * k end
    end
end

local function init_cam(c, main)
    local r = main.t:call("get_Rotation")
    local f = cam_forward({ r.x, r.y, r.z, r.w })
    c.yaw = yaw_of(f)
    c.elev = math.max(-0.5, math.min(1.2, math.asin(math.max(-1, math.min(1, -f[2])))))
    c.pos, c.need_init = nil, false
end

-- dev13 (the tester: Camera Distance's presets "work perfectly with split screen but only apply to P1's frame ... each
-- player could set their own camera"): a player's preset adds its distance (combat distance while in a fight: the
-- player's weapon drawn, or Camera Distance's own combat state), height, shoulder offset, downward tilt and forward
-- lead to this mod's base Distance / Height. Field of view stays the split's.
local function preset_of(p)
    local CD = rawget(_G, "CameraDistance_API")
    local i = cfg.pcam and tonumber(cfg.pcam["p" .. p])
    if not (CD and CD.presets and i and i > 0) then return nil end
    local ok, list = pcall(CD.presets)
    return ok and list and list[i] or nil
end
S.preset_of = preset_of
local function cam_shape(p, ch)
    local P = preset_of(p)
    local dist, h, side, tilt, lead = cfg.cam_distance, cfg.cam_height, 0.0, 0.0, 0.0
    if P then
        if P.rts_mode then
            dist = dist + (P.extra_distance or 8.0)
        else
            local fight = false
            if P.use_combat_distance then
                pcall(function() fight = ch:call("get_IsDrawedWeapon") == true end)
                if not fight then local CD = rawget(_G, "CameraDistance_API"); fight = CD and CD.in_combat and CD.in_combat() or false end
            end
            dist = dist + ((fight and P.combat_distance) or P.distance or 0.0) + (P.extra_distance or 0.0)
        end
        h = h + (P.height_y or 0.0)
        side = P.shoulder_x or 0.0
        tilt = math.rad(P.pitch_deg or 0.0)
        lead = P.forward_lead or 0.0
    end
    return math.max(0.8, dist), h, side, tilt, lead
end

local function update_player_cam(p, ch, dt, main)
    local c = cams[p]
    if not c then c = { yaw = 0.0, elev = 0.25, need_init = true }; cams[p] = c end
    if c.need_init then init_cam(c, main) end
    local v = api.view_axes and api.view_axes(p)
    if v then
        local rx, ry = v.rx or 0.0, v.ry or 0.0
        if math.abs(rx) < 0.12 then rx = 0 end
        if math.abs(ry) < 0.12 then ry = 0 end
        c.yaw = c.yaw - rx * cfg.cam_speed * dt * (cfg.invert_x and -1 or 1)
        c.elev = math.max(-0.5, math.min(1.2, c.elev - ry * cfg.cam_speed * 0.7 * dt * (cfg.invert_y and -1 or 1)))
    end
    local dist, h, side, tilt, lead = cam_shape(p, ch)
    local e0 = c.elev
    c.elev = math.max(-0.5, math.min(1.45, e0 + tilt))
    c.rot = cam_rot(c)
    c.elev = e0
    local t = chara_pos(ch)
    if not t then return false end
    t[2] = t[2] + h
    if side ~= 0.0 or lead ~= 0.0 then
        local fx, fz = -math.sin(c.yaw), -math.cos(c.yaw) -- yaw's ground forward
        local f = cam_forward(c.rot); local fl = math.sqrt(f[1] * f[1] + f[3] * f[3])
        if fl > 1e-3 then fx, fz = f[1] / fl, f[3] / fl end
        t[1], t[3] = t[1] + fx * lead - fz * side, t[3] + fz * lead + fx * side
    end
    c.dist = c.dist and (c.dist + (dist - c.dist) * math.min(1.0, dt * 4.0)) or dist
    follow(c, t, c.dist, dt)
    return true
end

local function update_overview(charas, dt, main)
    local c = cams.ov
    if not c then c = { yaw = 0.0, elev = 1.05, need_init = true }; cams.ov = c end
    if c.need_init then init_cam(c, main); c.elev = 1.05 end
    -- slowly follow player 1's view direction
    local d = clock.p1_yaw - c.yaw
    d = (d + math.pi) % (2 * math.pi) - math.pi
    c.yaw = c.yaw + d * math.min(1.0, dt * 0.8)
    c.rot = cam_rot(c)
    local n, mid, far = 0, { 0, 0, 0 }, 0
    local ps = {}
    for _, ch in ipairs(charas) do
        local p = chara_pos(ch)
        if p then n = n + 1; ps[#ps + 1] = p; for i = 1, 3 do mid[i] = mid[i] + p[i] end end
    end
    if n == 0 then return false end
    for i = 1, 3 do mid[i] = mid[i] / n end
    for _, p in ipairs(ps) do far = math.max(far, math.sqrt((p[1] - mid[1]) ^ 2 + (p[3] - mid[3]) ^ 2)) end
    follow(c, mid, math.max(12.0, far * 2.2 + 8.0), dt)
    return true
end

-- ---------------------------------------------------------------------------------------------------------------
-- Layouts: cells in screen fractions { l, t, r, b }
-- ---------------------------------------------------------------------------------------------------------------
local function cells_for(n)
    local w, h = V.disp_w or 1920, V.disp_h or 1080
    local wide = w / h >= 2.4
    if n <= 2 then
        local mode = cfg.layout
        if mode == 1 then mode = wide and 2 or 3 end
        if mode == 2 then return { [1] = { 0, 0, .5, 1 }, [2] = { .5, 0, 1, 1 } }, "side" end
        return { [1] = { 0, 0, 1, .5 }, [2] = { 0, .5, 1, 1 } }, "stack"
    end
    local grid = { { 0, 0, .5, .5 }, { .5, 0, 1, .5 }, { 0, .5, .5, 1 }, { .5, .5, 1, 1 } }
    if n == 3 then
        local mode = cfg.layout3
        if mode == 1 then mode = wide and 2 or 3 end
        if mode == 2 then return { [1] = { 0, 0, 1 / 3, 1 }, [2] = { 1 / 3, 0, 2 / 3, 1 }, [3] = { 2 / 3, 0, 1, 1 } }, "row3" end
        local c = { [1] = grid[1], [2] = grid[2], [3] = grid[3] }
        if cfg.spare == 2 then c.ov = grid[4] end
        return c, "grid3"
    end
    if cfg.layout4 == 2 then return { [1] = { 0, 0, .25, 1 }, [2] = { .25, 0, .5, 1 }, [3] = { .5, 0, .75, 1 }, [4] = { .75, 0, 1, 1 } }, "row4" end
    return { [1] = grid[1], [2] = grid[2], [3] = grid[3], [4] = grid[4] }, "grid4"
end

-- the game's FOV is for the whole screen. A cell as tall as the screen keeps the vertical angle; a cell as wide as
-- the screen keeps the horizontal one; a grid cell has the screen's shape and keeps both.
local function view_fov(base, vertical, full, cell, keep_h)
    local r = math.rad(base) / 2
    local tv = vertical and math.tan(r) or math.tan(r) / full
    if keep_h then tv = tv * full / cell end
    local out = vertical and math.atan(tv) or math.atan(tv * cell)
    return math.min(150.0, math.deg(out * 2) * cfg.fov_scale)
end

-- ---------------------------------------------------------------------------------------------------------------
-- When to show one view: talks, cutscenes, special cameras, loading (menus too if menus_keep is off), frame generation
-- ---------------------------------------------------------------------------------------------------------------
local SPLIT_CONTROLLERS = {
    ["app.UsuallyCameraController"] = true, ["app.CombatCameraController"] = true,
    ["app.AimCameraController"] = true, ["app.NarrowCameraController"] = true,
    ["app.ClimbingCameraController"] = true, ["app.FollowCameraController"] = true,
    ["app.BallistaCameraController"] = true, ["app.CinematicActionCameraController"] = true,
    ["app.InsertViewCameraController"] = true,
}
local SUSPEND = {
    { "app.GuiManager", { "get_IsPausedGUINoLock", "get_IsPause", "get_IsPaused", "get_IsOpenMainFlowUI", "get_IsOptionMenuOpen" }, menu = true },
    { "app.PauseManager", { "get_IsPaused", "get_IsPause", "get_GameIsPaused" }, menu = true },
    { "app.EventManager", { "get_IsPlayingEvent", "get_IsEvent", "get_IsCutScene", "get_IsPlayingCutScene" } },
    { "app.CutSceneManager", { "get_IsPlaying", "get_IsPlayingCutScene", "get_IsCutSceneOrMovie" } },
    { "app.TalkEventManager", { "get_IsTalking", "get_IsTalkEvent" } },
}
local checks = nil
S.menu_open = false
local function suspend_reason(main)
    if checks == nil then
        checks = {}
        for _, c in ipairs(SUSPEND) do
            local td = sdk.find_type_definition(c[1])
            for _, mn in ipairs(c[2]) do
                local m = td and td:get_method(mn)
                if m and m:get_num_params() == 0 then checks[#checks + 1] = { cls = c[1], name = c[1] .. "." .. mn, m = m, menu = c.menu } end
            end
        end
        S.checks = checks
    end
    local menu = false
    for _, c in ipairs(checks) do
        local obj = sdk.get_managed_singleton(c.cls)
        if obj then
            local ok, v = pcall(c.m.call, c.m, obj)
            if ok and v == true then
                if c.menu and cfg.menus_keep then menu = true else return c.name end
            end
        end
    end
    S.menu_open = menu
    if S.world_loading then return "loading" end
    if main.mcc then
        local cur = main.mcc:get_field("_CurrentCameraController")
        local n = cur and cur:get_type_definition():get_full_name()
        -- dev23 (crash, DEVICE_HUNG, in photo mode while split): photo mode counts as a pause, so the camera check
        -- was skipped and the split stayed on under the photo camera. A photo camera now ends the split even in a menu.
        if n and not SPLIT_CONTROLLERS[n] and (not menu or n:find("Photo")) then return n end
    end
    return nil
end

-- frame generation: via.render.UpscalingInterface.get_UsingFrameGeneration() (static), read once a second
local FG_M = nil
pcall(function() FG_M = sdk.find_type_definition("via.render.UpscalingInterface"):get_method("get_UsingFrameGeneration") end)
local fg = { on = false, t = 0 }
S.fg = fg
local function frame_gen_on(now)
    if now - fg.t < 1.0 then return fg.on end
    fg.t = now
    local ok, v = false, nil
    if FG_M then ok, v = pcall(FG_M.call, FG_M, nil) end
    local was = fg.on
    fg.on = ok and v == true
    if fg.on and not was then fg.note_t = now + 10.0; log("frame generation is on: split screen waits until it is off") end
    return fg.on
end

-- ---------------------------------------------------------------------------------------------------------------
-- Start / stop
-- ---------------------------------------------------------------------------------------------------------------
local fov_mem = {}
-- dev9: one view's aspect is the screen's (reported: after a Reset Scripts everything was stretched wide: the aspect
-- saved at load was the split's, 1.78 on a 3.56 screen). The aspect saved at load is only a fallback.
local function full_aspect(m)
    local w, h = V.disp_w, V.disp_h
    if w and h and h > 0 then return w / h end
    return m and m.saved_aspect
end
local function single_view()
    local m = V.main
    if m then
        pcall(function() m.ro:call("set_Region(via.Rect)", rect({ 0, 0, 1, 1 })) end)
        local a = full_aspect(m)
        if a then pcall(function() m.cam:call("set_AspectRatio", a) end) end
        if fov_mem.w1 and fov_mem.b1 then
            pcall(function() if math.abs(m.cam:call("get_FOV") - fov_mem.w1) < 1e-3 then m.cam:call("set_FOV", fov_mem.b1) end end)
        end
    end
    fov_mem = {}
    V.layout_key = nil
    S.view_list_cache = nil
end

-- dev11: app.CharacterFade fades a character (face first, then hair) when the camera is within ~0.4-1.0 m, measured
-- from MainCamera only (read live: get_Camera = MainCamera for every party member). In split screen that is player 1's
-- camera, so when it passed close to a character, that character lost her face in every view. While the split is on,
-- the players' characters get FadeType Disable (1); put back to Default (0) when it ends or they leave.
local FADE_T = sdk.find_type_definition("app.CharacterFade")
local FADE_TYPE = FADE_T and (function() local ok, t = pcall(FADE_T.get_runtime_type, FADE_T); return ok and t or nil end)()
local M_GET_FADE = FADE_T and FADE_T:get_method("get_Fade")
local M_SET_FADE = FADE_T and FADE_T:get_method("set_Fade")
local faded = {} -- address of the character -> its CharacterFade
local fade_next = 0
local function fade_restore(keep)
    for a, f in pairs(faded) do
        if not (keep and keep[a]) then
            pcall(function() if sdk.is_managed_object(f) and M_GET_FADE:call(f) == 1 then M_SET_FADE:call(f, 0) end end)
            faded[a] = nil
        end
    end
end
local function fade_update(players, n, now)
    if not (cfg.no_near_fade and FADE_TYPE and M_SET_FADE) then if next(faded) then fade_restore() end return end
    if now < fade_next then return end
    fade_next = now + 0.5
    local keep = {}
    for p = 1, n do
        local ch = players[p]
        local ok, a = pcall(ch.get_address, ch)
        if ok and a then
            keep[a] = true
            local f = faded[a]
            if not f then
                pcall(function()
                    local go = ch:call("get_GameObject")
                    f = go and go:call("getComponent(System.Type)", FADE_TYPE)
                end)
                if f then faded[a] = f end
            end
            if f then pcall(function() if M_GET_FADE:call(f) ~= 1 then M_SET_FADE:call(f, 1) end end) end
        end
    end
    fade_restore(keep)
end
S.fade_restore = fade_restore

-- dev14 (the tester: "The minimap and some native text elements that are left on P1's screen get squished"): the game lays
-- its HUD out for the whole screen and draws it into player 1's view (via.gui.GUI RenderOutputID bit 1; 69 GUIs, 41 on
-- 1 only, 27 on 1 + 4). Measured live 2026-11-25: scaling a GUI view's ScreenSize width by r makes it r times as wide
-- per unit (width x0.25 on the full screen stretched it 4x). So each GUI on output 1 gets width = its own x (view
-- aspect / screen aspect); 1 (quad on any screen, three across on 48:9) leaves them alone. GUIs come and go with
-- menus: rescanned once a second (the scan is timed; slower than 2 ms moves it to every 5 s). Put back on stop.
local GUIFIT = { orig = {}, next = 0, every = 1.0, r = 1.0, scan_ms = 0 }
local SIZE_T = sdk.find_type_definition("via.Size")
local function gui_size(v, w, h)
    local sz = ValueType.new(SIZE_T); sz.w = w; sz.h = h
    v:call("set_ScreenSize", sz)
end
local function gui_move(v, x, y, z)
    local p = v:call("get_Position"); p.x = x; p.y = y; p.z = z
    v:call("set_Position", p)
end
local function gui_restore()
    for a, o in pairs(GUIFIT.orig) do
        pcall(function() if sdk.is_managed_object(o.v) then gui_size(o.v, o.w, o.h); gui_move(o.v, o.px, o.py, o.pz) end end)
        GUIFIT.orig[a] = nil
    end
    GUIFIT.r = 1.0
end
-- dev16 (the tester, after the height x3 try: "not squished just positioned wrong ... too small"): ScreenSize (w k, h k / r)
-- keeps the shape (k / (k / r) = r undoes the squeeze); the view's Position (a via.gui.TransformObject) moves it:
-- down by the extra height (the HUD's bottom edge on the view's bottom edge) and left so the game's HUD band (its
-- middle 16:9 part on a wider screen) is centred. k = the smallest that still fits the band in 96 % of the view:
-- k = band / 0.96, at least r (full size), at most 1. Three across on 32:9: k 0.52, the HUD at ~0.64 of full size.
-- Views wider than the screen (r > 1) are left alone.
-- dev18: the mapping, fitted to four results in game (view 2560x2160 on 7680x2160, r 1/3) and checked against each:
-- the HUD's design units (1920 x 1080) are drawn at view height / ScreenSize.h pixels per unit, both ways (so the
-- height sets the size); the layout is ScreenSize.w x (screen aspect / 16:9) units wide, stretched over the view's
-- width, with the 16:9 design band centred in it by the game; Position moves it in design units. So width w k and
-- height h k / r give one scale both ways (round), at r / k of full size, the band centred; Position y + (h k / r - h)
-- puts its bottom edge on the view's bottom. dev16 also moved it left by (w k - w) / 2, which pushed the minimap
-- off the left edge, and reshaped the GUIs on outputs 1 + 4, which drew lines across player 2's view.
local function gui_fit(r, now, screen_aspect)
    -- dev22 (the tester: it "has also affected pause menu"): menus draw full screen, so nothing is fitted while one is open
    if not cfg.fit_hud or S.menu_open or math.abs(r - 1.0) < 0.02 or r > 1.0 then if next(GUIFIT.orig) then gui_restore() end return end
    local changed = math.abs(r - GUIFIT.r) > 1e-3
    if not changed and now < GUIFIT.next then return end
    GUIFIT.r = r
    local t0 = os.clock()
    local scene = sdk.call_native_func(sdk.get_native_singleton("via.SceneManager"), sdk.find_type_definition("via.SceneManager"), "get_CurrentScene()")
    local arr = scene and scene:call("findComponents(System.Type)", sdk.typeof("via.gui.GUI"))
    if arr then
        for i = 0, arr:get_size() - 1 do
            local g = arr:get_element(i)
            if g and ((g:call("get_RenderOutputID") or 0) & 1) == 1 then -- dev21: as in the try that looked right (1 and 1 + 4)
                local v = g:call("get_View")
                if v then
                    local a = v:get_address()
                    local o = GUIFIT.orig[a]
                    if not o then
                        local z = v:call("get_ScreenSize")
                        local q = v:call("get_Position")
                        o = { v = v:add_ref(), w = z.w, h = z.h, px = q.x, py = q.y, pz = q.z, set = nil }
                        GUIFIT.orig[a] = o
                    end
                    -- dev21 (the [time] try the tester called close: "not squished just positioned wrong", then right place,
                    -- only small): width as is, height / r, moved down by the extra height. Changing the width too
                    -- (dev14 / 16 / 18) scattered the parts, so it stays.
                    local key = string.format("%.4f", r)
                    if o.set ~= key then
                        local hh = o.h / r
                        gui_size(v, o.w, hh)
                        gui_move(v, o.px, o.py + (hh - o.h), o.pz)
                        o.set = key
                    end
                end
            end
        end
    end
    GUIFIT.scan_ms = (os.clock() - t0) * 1000.0
    if GUIFIT.scan_ms > 2.0 then GUIFIT.every = 5.0 end
    GUIFIT.next = now + GUIFIT.every
end
S.gui_fit_state = GUIFIT

local function stop(why)
    pcall(gui_restore)
    pcall(fade_restore)
    local was = S.active or next(V.ex) ~= nil
    S.active = false
    st.why_off = why
    for key in pairs(V.ex) do put_away(key, V.main) end
    pcall(restore_shadows)
    single_view()
    for _, c in pairs(cams) do c.need_init = true end
    if was then st.stops = st.stops + 1; log("one view again (" .. tostring(why) .. ")") end
end
S.stop = stop

local function suspend(why)
    pcall(fade_restore)
    pcall(gui_restore)
    if S.active then
        S.active = false
        for _, v in pairs(V.ex) do show_view(v, false) end
        single_view()
        for _, c in pairs(cams) do c.need_init = true end
    end
    st.suspended_by = why
end

-- ---------------------------------------------------------------------------------------------------------------
-- DPC
-- ---------------------------------------------------------------------------------------------------------------
local function chara_addr(ch) local ok, a = pcall(ch.get_address, ch); return ok and a or nil end

local function turn_for(ch)
    if not (S.active and api) then return nil end
    local p = api.player_of and api.player_of(ch)
    if not p or p < 2 then return nil end
    local c = cams[p]
    if not (c and V.ex[p]) then return nil end
    st.turns = st.turns + 1
    return (c.yaw - clock.p1_yaw) * (cfg.turn_flip and -1 or 1)
end

-- every player's view, for DPC's bars and cards: pixels, pose, field of view
local function view_list()
    return S.active and S.view_list_cache or nil
end

local function setup(a)
    if not (a.has and a.has("views")) then
        st.why_off = "needs Direct Pawn Control 0.9.177-dev37 or later (API 1.3)"
        log(st.why_off)
        return
    end
    api = a
    S.api = a
    a.set_view_turn(turn_for, { mod = "DPC Split Screen", active = function() return S.active end })
    if a.set_view_list then a.set_view_list(view_list, { mod = "DPC Split Screen" }) end
    a.on("world_loading", function() S.world_loading = true end, { mod = "DPC Split Screen" })
    a.on("world_back", function() S.world_loading = false end, { mod = "DPC Split Screen" })
    a.on("coop_stop", function() for _, c in pairs(cams) do c.need_init = true end end, { mod = "DPC Split Screen" })
    log("connected to Direct Pawn Control " .. tostring(a.dpc_version))
end

-- player 1's movement keeps reading the main camera's angle (guitarguy1104: a second camera can take it over)
do
    local td = sdk.find_type_definition("app.PlayerInputProcessorDetail")
    local m = td and td:get_method("getCameraAngleRad")
    if m then
        sdk.hook(m, nil, function(rv)
            if S.active and S.main_angle then st.angle_fix = st.angle_fix + 1; return sdk.float_to_ptr(S.main_angle) end
            return rv
        end)
    end
end

-- characters player 1's camera would cull stay drawn while another view looks at them (guitarguy1104's DD2CoopCulling)
local cull = { n = 0, v = {} }
S.cull_view = cull
do
    local td = sdk.find_type_definition("app.InCameraChecker")
    local m = td and td:get_method("isInCamera")
    if m then
        sdk.hook(m, function(args)
            if cull.n > 0 then thread.get_hook_storage().chk = args[2] end
        end, function(rv)
            if cull.n == 0 or (sdk.to_int64(rv) & 1) == 1 then return rv end
            local stg = thread.get_hook_storage()
            local c = stg.chk
            stg.chk = nil
            if not c then return rv end
            local ok, seen = pcall(function()
                local box = sdk.to_managed_object(c):call("calcBox")
                local a, b = box.minpos, box.maxpos
                local cx, cy, cz = (a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2
                local rad = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2 + (b.z - a.z) ^ 2) / 2
                for i = 1, cull.n do
                    local view = cull.v[i]
                    local dx, dy, dz = cx - view.x, cy - view.y, cz - view.z
                    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
                    if d < 12.0 then return true end
                    local f = (view.fx * dx + view.fy * dy + view.fz * dz) / d
                    if math.acos(math.max(-1, math.min(1, f))) < view.half + math.asin(math.min(1, rad / d)) + math.rad(8) then return true end
                end
                return false
            end)
            if ok and seen then st.kept = st.kept + 1; return sdk.to_ptr(1) end
            return rv
        end)
    end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Every frame, before the frame is drawn
-- ---------------------------------------------------------------------------------------------------------------
-- dev5: while the split is off, the game's primary camera can still be one of the hidden extra cameras (read live:
-- UserEditCamera, BgCamera; there is no setter for it). The game's nameplates and anything using
-- draw.world_to_screen then follow a camera somewhere else (reported: "nameplates can be very far off"). So every
-- hidden extra camera is kept on the main camera's pose and lens while one view is shown.
V.leftover = {}
local function mirror_main()
    local main = find_main()
    if not main then return end
    if V.matrix_ok == nil then V.matrix_ok = check_matrix(main.t) end
    if not V.matrix_ok then return end
    local p, r = main.t:call("get_Position"), main.t:call("get_Rotation")
    local pos, q = { p.x, p.y, p.z }, { r.x, r.y, r.z, r.w }
    local fov, asp, vert = main.cam:call("get_FOV"), main.cam:call("get_AspectRatio"), main.cam:call("get_VerticalEnable")
    -- dev10 (reported: a stutter every half second turning the camera solo): lens settings only when they changed
    local function one(v)
        if not (v and v.t and v.cam) then return end
        pcall(function()
            if v.m_vert ~= vert then v.cam:call("set_VerticalEnable", vert); v.m_vert = vert end
            if v.m_fov ~= fov then v.cam:call("set_FOV", fov); v.m_fov = fov end
            if v.m_asp ~= asp then v.cam:call("set_AspectRatio", asp); v.m_asp = asp end
            write_pose(v.t, pos, q)
        end)
    end
    for _, v in pairs(V.kept) do one(v) end
    for _, v in pairs(V.leftover) do one(v) end
    for _, v in pairs(V.ex) do if not v.shown then one(v) end end
    st.mirrored = (st.mirrored or 0) + 1
end

-- dev2: views left drawing by an earlier load (a Reset Scripts keeps the game objects): hide them once, and put the
-- main view back on the whole screen
local function cleanup_once()
    if S.cleaned then return end
    if not V.disp_w then return end -- dev9: wait for the screen size (the aspect comes from it)
    local sc = scene()
    if not sc then return end
    S.cleaned = true
    local n = 0
    for _, name in ipairs({ P2_HOST, "DPCSplit_View_3", "DPCSplit_View_4", "DPCSplit_View_ov" }) do
        local go = sc:call("findGameObject(System.String)", name)
        local ro = go and go:call("getComponent(System.Type)", sdk.typeof("via.render.RenderOutput"))
        if ro then
            pcall(function() go:call("set_DrawSelf", false) end)
            n = n + 1
        end
        if go then
            local cam = go:call("getComponent(System.Type)", sdk.typeof("via.Camera"))
            if cam then V.leftover[name] = { go = go:add_ref(), cam = cam:add_ref(), t = go:call("get_Transform"):add_ref() } end
        end
    end
    local m = find_main()
    if m then
        pcall(function() m.ro:call("set_Region(via.Rect)", rect({ 0, 0, 1, 1 })) end)
        local a = full_aspect(m)
        if a then pcall(function() m.cam:call("set_AspectRatio", a) end) end
    end
    if n > 0 then log("hid " .. n .. " view(s) left from an earlier load") end
end

local resume_t, pfx_t, pfx_rr = 0, 0, 0
local function tick()
    if not S.cleaned then pcall(cleanup_once) end
    local now = os.clock()
    local dt = math.min(now - clock.last, 0.1)
    clock.last = now
    cull.n = 0

    -- dev2: co-op is "two or more players with a character" (DPC's coop.active is false while both players are on
    -- pawns: the first build split, then ended the split when player 1 took a pawn)
    local players = {}
    if api then
        pcall(function()
            for _, e in ipairs(api.players()) do if e.chara and e.player and e.player <= 4 then players[e.player] = e.chara end end
        end)
    end
    local n = 0
    for p = 1, 4 do if players[p] then n = p else break end end
    if not (cfg.enabled and api and n >= 2) then
        if S.active or next(V.ex) then stop(not cfg.enabled and "switched off" or "co-op ended") end
        st.suspended_by = nil
        return
    end
    if frame_gen_on(now) then
        if S.active or next(V.ex) then stop("frame generation is on") end
        st.suspended_by = "frame generation is on (turn it off in the graphics options)"
        return
    end
    local main = find_main()
    if not main then return end
    if V.matrix_ok == nil then
        V.matrix_ok = check_matrix(main.t)
        if not V.matrix_ok then fail("start", "camera transform layout is not what this build expects; split screen stays off") end
    end
    if not V.matrix_ok then return end

    local why = suspend_reason(main)
    if why then resume_t = 0.2; suspend(why); return end
    if resume_t > 0 then resume_t = resume_t - dt; return end
    st.suspended_by = nil

    local r = main.t:call("get_Rotation")
    local mq = { r.x, r.y, r.z, r.w }
    if not FWD.set then -- which way cameras face along Z, from where player 1 stands
        local cp = main.t:call("get_Position")
        local pp = chara_pos(players[1])
        if pp then
            local z = qrotate(mq, { 0, 0, -1 })
            FWD[1] = (z[1] * (pp[1] - cp.x) + z[2] * (pp[2] - cp.y) + z[3] * (pp[3] - cp.z)) >= 0 and -1 or 1
            FWD.set, S.fwd = true, FWD[1]
        end
    end
    clock.p1_yaw = yaw_of(cam_forward(mq))
    do -- the angle app.PlayerInputProcessorDetail.getCameraAngleRad gives for the main camera
        local f = qrotate(mq, { 0, 0, 1 })
        local a = math.atan(f[1], f[3]) - math.pi
        if a < -math.pi then a = a + 2 * math.pi end
        S.main_angle = a
    end

    local cells, kind = cells_for(n)
    -- cameras for this frame; a view whose character is missing waits
    local ready = {}
    for p = 2, n do if cells[p] and update_player_cam(p, players[p], dt, main) then ready[p] = true end end
    if cells.ov then
        local list = {}
        for p = 1, n do list[#list + 1] = players[p] end
        if update_overview(list, dt, main) then ready.ov = true end
    end
    -- views in, views out
    for key in pairs(V.ex) do if not (cells[key] and ready[key]) then put_away(key, main) end end
    for key in pairs(ready) do
        if not V.ex[key] then
            local ok, v = pcall(make_view, main, key)
            if ok then V.ex[key] = v; st.starts = st.starts + 1 else fail("view " .. tostring(key), v); ready[key] = nil end
        end
    end

    local W, H = V.disp_w or 1920, V.disp_h or 1080
    local full = W / H
    local key = kind .. ":" .. W .. "x" .. H
    for k in pairs(V.ex) do key = key .. ":" .. tostring(k) end
    if V.layout_key ~= key then
        main.ro:call("set_Region(via.Rect)", rect(cells[1]))
        for k, v in pairs(V.ex) do v.ro:call("set_Region(via.Rect)", rect(cells[k])) end
        V.layout_key = key
    end
    for _, v in pairs(V.ex) do show_view(v, true) end
    S.active = true
    S.kind, S.cells = kind, cells
    pcall(fade_update, players, n, now)

    local vert = main.cam:call("get_VerticalEnable")
    local f1 = main.cam:call("get_FOV")
    if fov_mem.w1 and math.abs(f1 - fov_mem.w1) < 1e-3 then f1 = fov_mem.b1 end -- the game did not write it again
    local function cell_px(c) return (c[3] - c[1]) * W, (c[4] - c[2]) * H end
    local function fov_for(c)
        local cw, chh = cell_px(c)
        return view_fov(f1, vert, full, cw / chh, chh < H - 0.5 and cw > W - 0.5), cw / chh
    end
    local w1, a1 = fov_for(cells[1])
    fov_mem.b1, fov_mem.w1 = f1, w1
    main.cam:call("set_AspectRatio", a1)
    main.cam:call("set_FOV", w1)
    do local okf, ef = pcall(gui_fit, a1 / full, now, full); if not okf then GUIFIT.err = tostring(ef) end end

    local list = {}
    do
        local cw, chh = cell_px(cells[1])
        local p = main.t:call("get_Position")
        list[1] = { player = 1, x = cells[1][1] * W, y = cells[1][2] * H, w = cw, h = chh, pos = { p.x, p.y, p.z }, rot = mq,
            fov = w1, vertical = vert, aspect = a1, fwd = FWD[1] }
    end
    for k, v in pairs(V.ex) do
        local c = cams[k]
        local fv, asp = fov_for(cells[k])
        if k == "ov" then fv = math.min(150.0, fv * 1.1) end
        v.cam:call("set_AspectRatio", asp)
        v.cam:call("set_VerticalEnable", vert)
        v.cam:call("set_FOV", fv)
        v.cam:call("set_NearClipPlane", main.cam:call("get_NearClipPlane"))
        v.cam:call("set_FarClipPlane", main.cam:call("get_FarClipPlane"))
        write_pose(v.t, c.pos, c.rot)
        local cw, chh = cell_px(cells[k])
        if type(k) == "number" then
            list[#list + 1] = { player = k, x = cells[k][1] * W, y = cells[k][2] * H, w = cw, h = chh, pos = { c.pos[1], c.pos[2], c.pos[3] },
                rot = { c.rot[1], c.rot[2], c.rot[3], c.rot[4] }, fov = fv, vertical = vert, aspect = asp, fwd = FWD[1] }
        end
        if cfg.keep_seen then
            local f = cam_forward(c.rot)
            cull.n = cull.n + 1
            cull.v[cull.n] = { x = c.pos[1], y = c.pos[2], z = c.pos[3], fx = f[1], fy = f[2], fz = f[3],
                half = math.atan(math.tan(math.rad(fv) / 2) * math.max(1.0, asp) * 1.2) }
        end
    end
    table.sort(list, function(a, b) return a.player < b.player end)
    S.view_list_cache = list

    -- dev8 (reported: right-stick turning hitched about every second in four views): the post-effect copy ran for
    -- every view every 0.5 s in one frame, and the sun lights were searched scene-wide each time. Now one component
    -- of one view per frame (a full pass takes about 20 frames per view), and the lights every 5 s.
    if cfg.post_effects then
        local list = {}
        for k, v in pairs(V.ex) do if not v.own or cfg.own_pfx or cfg.own_pfx_light then list[#list + 1] = v end end
        if #list > 0 then
            pfx_rr = (pfx_rr % #list) + 1
            local v = list[pfx_rr]
            -- dev3: player 2's view got 0 post effects once (the main camera's list read empty); build again
            if #(v.pfx or {}) == 0 then pcall(build_pfx, v, main) end
            local pf = v.pfx or {}
            if #pf > 0 then
                v.pfx_i = ((v.pfx_i or 0) % #pf) + 1
                copy_pfx_one(pf[v.pfx_i])
            end
        end
    end
    pfx_t = pfx_t - dt
    if pfx_t <= 0 then
        pfx_t = 5.0
        if cfg.shadows then pcall(find_suns) else restore_shadows() end
    end
    shadow_t = (shadow_t or 0) - dt
    if shadow_t <= 0 then
        shadow_t = 0.2
        if cfg.shadows then apply_shadows() end
    end
    st.frames = st.frames + 1
end

S.fn = { view_fov = view_fov, cells_for = cells_for, yaw_of = yaw_of, cam_forward = cam_forward, turn_for = turn_for } -- tests

re.on_pre_application_entry("BeginRendering", function()
    -- dev10: switched off = nothing at all (no mirroring either)
    if not cfg.enabled then
        if S.active or next(V.ex) then pcall(stop, "switched off") end
        return
    end
    if S.halted then if cfg.mirror then pcall(mirror_main) end; return end
    local ok, err = pcall(tick)
    if not S.active and cfg.mirror then pcall(mirror_main) end
    if ok then return end
    fail("frame", err)
    pcall(stop, "error")
    -- one error stops the split until it is switched on again in the settings
    S.halted = tostring(err)
    st.why_off = "stopped after an error; untick and tick \"Split the screen\" to try again"
end)

re.on_script_reset(function() pcall(stop, "scripts reset"); if api then pcall(api.set_view_turn, nil); if api.set_view_list then pcall(api.set_view_list, nil) end end end)

-- ---------------------------------------------------------------------------------------------------------------
-- Drawing (read only): lines between the views, the blank quarter, the frame generation note
-- ---------------------------------------------------------------------------------------------------------------
re.on_frame(function()
    local sz = imgui.get_display_size()
    V.disp_w, V.disp_h = sz.x, sz.y
    local w, h = sz.x, sz.y
    if fg.note_t and os.clock() < fg.note_t then
        draw.text("Split screen is off while frame generation is on (graphics options). Upscaling is fine.", w * 0.5 - 380, h * 0.08, 0xFF60D0FF)
    end
    if not (S.active and S.cells) then return end
    if S.menu_open then return end -- dev3: no lines or blank quarter over a menu (the menu covers the whole screen)
    local c = S.cells
    if S.kind == "grid3" and not c.ov then draw.filled_rect(w * 0.5, h * 0.5, w * 0.5, h * 0.5, 0xFF000000) end
    if not cfg.divider then return end
    local t = math.max(2, math.floor(math.min(w, h) * 0.003))
    local function vline(x) draw.filled_rect(x - t, 0, 2 * t, h, 0xFF0A0908); draw.filled_rect(x - 1, 0, 2, h, 0xFF4C80A0) end
    local function hline(y) draw.filled_rect(0, y - t, w, 2 * t, 0xFF0A0908); draw.filled_rect(0, y - 1, w, 2, 0xFF4C80A0) end
    if S.kind == "side" then vline(w / 2)
    elseif S.kind == "stack" then hline(h / 2)
    elseif S.kind == "row3" then vline(w / 3); vline(w * 2 / 3)
    elseif S.kind == "row4" then vline(w / 4); vline(w / 2); vline(w * 3 / 4)
    else vline(w / 2); hline(h / 2) end
end)

-- ---------------------------------------------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------------------------------------------
re.on_draw_ui(function()
    if not imgui.tree_node("DPC Split Screen " .. VERSION) then return end
    local ch, c = false, false
    c, cfg.enabled = imgui.checkbox("Split the screen in co-op", cfg.enabled); ch = ch or c
    if c then S.halted = nil end
    if fg.on then imgui.text_colored("Frame generation is on: the split waits until it is off (graphics options).", 0xFF60D0FF) end
    c, cfg.layout = imgui.combo("Layout with 2 players", cfg.layout, { "Auto (side by side on wide screens)", "Side by side", "Top and bottom" }); ch = ch or c
    c, cfg.layout3 = imgui.combo("Layout with 3 players", cfg.layout3, { "Auto (three across on wide screens)", "Three across", "2 x 2 grid" }); ch = ch or c
    c, cfg.spare = imgui.combo("3 players in the 2 x 2 grid: fourth quarter", cfg.spare, { "Blank", "The party from above" }); ch = ch or c
    c, cfg.layout4 = imgui.combo("Layout with 4 players", cfg.layout4, { "2 x 2 grid", "Four across" }); ch = ch or c
    c, cfg.menus_keep = imgui.checkbox("Keep the split while a menu is open", cfg.menus_keep); ch = ch or c
    if imgui.tree_node("Players' cameras") then
        c, cfg.cam_distance = imgui.slider_float("Distance (m)", cfg.cam_distance, 2.0, 8.0, "%.1f"); ch = ch or c
        c, cfg.cam_height = imgui.slider_float("Height (m)", cfg.cam_height, 0.8, 2.5, "%.2f"); ch = ch or c
        c, cfg.cam_speed = imgui.slider_float("Turn speed", cfg.cam_speed, 0.5, 6.0, "%.1f"); ch = ch or c
        c, cfg.invert_x = imgui.checkbox("Invert left / right", cfg.invert_x); ch = ch or c
        c, cfg.invert_y = imgui.checkbox("Invert up / down", cfg.invert_y); ch = ch or c
        c, cfg.fov_scale = imgui.slider_float("Field of view (all views)", cfg.fov_scale, 0.7, 1.6, "x%.2f"); ch = ch or c
        do -- dev13: players 2-4 each pick a Camera Distance preset
            local CD = rawget(_G, "CameraDistance_API")
            local okp, list = pcall(function() return CD and CD.presets and CD.presets() end)
            if okp and list and #list > 0 then
                local names = { "This mod's Distance / Height" }
                for _, pr in ipairs(list) do names[#names + 1] = pr.name end
                cfg.pcam = cfg.pcam or {}
                for p = 2, 4 do
                    local c2, v2 = imgui.combo("Player " .. p .. "'s camera (Camera Distance preset)", (tonumber(cfg.pcam["p" .. p]) or 0) + 1, names)
                    if c2 then cfg.pcam["p" .. p] = v2 - 1; ch = true end
                end
                imgui.text("Player 1's camera is Camera Distance's own preset.")
            end
        end
        c, cfg.turn_flip = imgui.checkbox("Players walk the wrong way: flip", cfg.turn_flip); ch = ch or c
        imgui.tree_pop()
    end
    if imgui.tree_node("Picture and sound") then
        c, cfg.divider = imgui.checkbox("Lines between the views", cfg.divider); ch = ch or c
        c, cfg.post_effects = imgui.checkbox("Copy the picture settings to the other views", cfg.post_effects); ch = ch or c
        c, cfg.mirror = imgui.checkbox("Keep hidden cameras on yours in one view (nameplate placement)", cfg.mirror); ch = ch or c
        c, cfg.own_pfx_light = imgui.checkbox("Players 3-4's views get the game's brightness and colour (from the next start)", cfg.own_pfx_light); ch = ch or c
        c, cfg.own_pfx = imgui.checkbox("...also to players 3-4's cameras (crash test, from the next start)", cfg.own_pfx); ch = ch or c
        c, cfg.shadows = imgui.checkbox("Shadows in every view", cfg.shadows); ch = ch or c
        do -- dev12
            local cur = cfg.sound_from or 2
            imgui.text("Sound heard from")
            local c1 = imgui.checkbox("   Player 1's view (the game's own)##sfrom1", cur == 1)
            local c2 = imgui.checkbox("   The middle of the players##sfrom2", cur == 2)
            if c1 and cur ~= 1 then cfg.sound_from = 1; ch = true end
            if c2 and cur ~= 2 then cfg.sound_from = 2; ch = true end
        end
        c, cfg.fit_hud = imgui.checkbox("Experiment: reshape the game's HUD in player 1's view (not right yet)", cfg.fit_hud); ch = ch or c
        if not cfg.fit_hud then pcall(gui_restore) end
        c, cfg.listener = imgui.checkbox("Also a second listener at player 2's camera (experimental; from the next start)", cfg.listener); ch = ch or c
        c, cfg.see_through = imgui.checkbox("See through walls near player 2's camera (from the next start)", cfg.see_through); ch = ch or c
        c, cfg.no_near_fade = imgui.checkbox("Players don't fade out when player 1's camera is close", cfg.no_near_fade); ch = ch or c
        c, cfg.keep_seen = imgui.checkbox("Draw what the other views see even when player 1's camera does not", cfg.keep_seen); ch = ch or c
        imgui.tree_pop()
    end
    imgui.text(S.active and ("Split (" .. tostring(S.kind) .. ")") or ("One view" .. (st.suspended_by and (" (paused: " .. st.suspended_by .. ")") or (st.why_off and (" (" .. st.why_off .. ")") or ""))))
    imgui.text(string.format("frames %d, views made %d, stops %d, stick turns %d, angle fixes %d, kept drawn %d, errors %d",
        st.frames, st.starts, st.stops, st.turns, st.angle_fix, st.kept, st.errors))
    if st.last_error then imgui.text_colored("Last error: " .. st.last_error, 0xFF6060FF) end
    c, cfg.view_scale = imgui.slider_float("Render scale of players 2-4's views (from the next start)", cfg.view_scale, 0.5, 1.0, "%.2f"); ch = ch or c
    if S.iq then imgui.text("Image quality: " .. S.iq) end
    if S.ro_after then imgui.text("Player 2's output id: " .. S.ro_after .. ", hidden by " .. tostring(S.hide_method)) end
    c, cfg.p2_output_id = imgui.slider_int("Player 2's output id (0 = auto, test only)", cfg.p2_output_id, 0, 16); ch = ch or c
    if ch then save_cfg() end
    imgui.text("Split-screen findings and code ideas: guitarguy1104 (DD2CouchCoop).")
    imgui.tree_pop()
end)

if _G.DPC_API then setup(_G.DPC_API)
else
    _G.DPC_API_QUEUE = _G.DPC_API_QUEUE or {}
    table.insert(_G.DPC_API_QUEUE, setup)
end

log("loaded " .. VERSION)
