-- Direct Pawn Control: co-op player cards, skill windows and world bars.
-- Part of DirectPawnControl.lua, which loads the files in this folder in order (this one is 21 of 26).
-- Never run on its own: REFramework only runs the files directly in reframework/autorun.
local S = require("DirectPawnControl/shared")
local cfg, R, field, JOB_NAMES, VOCATION_ACTION_NAMES = S.cfg, S.R, S.field, S.JOB_NAMES, S.VOCATION_ACTION_NAMES
local skill_name, state, coop, coop_pad_values = S.skill_name, S.state, S.coop, S.coop_pad_values

-- 0.9.172: one player's skill list window (player 2's, and players 3+'s beside their bars). pivot_x 0 = the window's
-- left edge at wx, 1 = its right edge. The window is always closed, whatever goes wrong inside (an error here left it
-- open once: ImGui "Missing End()").
R.palette_draw = function(s, pn, win, wx, wy, pivot_x)
    if cfg.coop_player_card ~= false and R.card_req then return R.card_req(s, pn, win, wx, wy, pivot_x) end
    imgui.set_next_window_pos(Vector2f.new(wx, wy), 1, Vector2f.new(pivot_x or 0.0, 1.0))
    imgui.begin_window(win, nil, (1 << 0) | (1 << 1) | (1 << 3) | (1 << 6))
    local okb, errb = pcall(function()
        imgui.text_colored(string.format("Player %d: %s (%s)", pn, tostring(s.name), JOB_NAMES[s.job] or "Pawn"), 0xFF88EEFF)
        imgui.separator()
        local sk = s.skills or {}
        local six = (sk[5] or 0) ~= 0 or (sk[6] or 0) ~= 0
        for n = 1, 6 do
            local sid = sk[n] or 0
            if sid ~= 0 then
                local sbl = R.SLOT_BIND_LABELS or {} -- set where the table is declared (later in the file)
                local lbl = (six and sbl.six and sbl.six[n]) or sbl[n] or ("[Skill " .. n .. "]")
                local okg, gl = pcall(R.bind_label, n)
                if okg and gl then lbl = "[Num" .. n .. " / " .. tostring(gl) .. "]" end
                local inner = lbl:match("/ ([^%]]+)%]") or (lbl:gsub("[%[%]]", ""))
                local okp, pl = pcall(R.pad_label, "[" .. inner .. "]", R.dev_style(s.dev or (pn == 2 and R.tp.p2) or nil))
                imgui.text_colored(string.format("   %s  %s", okp and tostring(pl) or ("[" .. inner .. "]"), skill_name(sid)), 0xFFFFFFFF)
            end
        end
    end)
    if not okb then s.hud_err = tostring(errb) end
    imgui.end_window()
end

-- 0.9.177: one card per co-op player (the tester: "a nice tight full interface for each co-op player with a colored title
-- bar and their interface that behaves just like the main player's"). Title bar in the player's colour with name and
-- vocation; health and stamina; the skills on that player's controller buttons (the running one highlighted); the
-- D-pad item cross (what up / down will use and how many, and whose bag; the lantern). Player 1's interface is the
-- game's own. Colours: P1 blue, P2 red, P3 green, P4 gold, then repeating.
R.PLAYER_RGB = { 0x4A90E2, 0xE2584A, 0x5BC26B, 0xE2C14A }
R.abgr = function(rgb, a)
    return ((a or 0xFF) << 24) | ((rgb & 0xFF) << 16) | (rgb & 0xFF00) | ((rgb >> 16) & 0xFF)
end
-- dev22 (the tester: "I don't like that the palette wiggles - changes vertical size when L1 is held ... native has places
-- for each button relative to a core"): the controller's shape, fixed size. Shoulders on top, face buttons as a
-- diamond; each place shows what that button does now (the actions; the skills while the skill shift is held, as
-- the game's palette does); a held button lights up. Read from the game's own assignment (R.bind.list).
-- dev30 (reported: "Arisen is on M+KB but shows PS controls"): player 1 on keyboard and mouse gets his own keys,
-- from the game's key bindings (R.kbind, read from KeyBindController), in fixed spots like the pad card.
R.KB_EXTRA = { [1] = "Left mouse", [2] = "Right mouse", [4] = "Middle mouse", [5] = "Mouse 4", [6] = "Mouse 5",
               [0x10] = "Shift", [0x11] = "Ctrl", [0x12] = "Alt", [0xA0] = "Shift", [0xA1] = "R Shift", [0xA2] = "Ctrl",
               [0xA3] = "R Ctrl", [0xA4] = "Alt", [0xA5] = "R Alt" }
R.kb_key = function(action)
    local a = S.ACTION_ENUM and S.ACTION_ENUM[action]
    local ks = a and R.kbind and R.kbind[a]
    local k = ks and ks[1]
    if not k then return nil end
    return R.KB_EXTRA[k] or R.vk_name(k)
end
R.card_short = function(t, n)
    t = tostring(t or "")
    n = n or 17
    if #t > n then return t:sub(1, n - 1) .. "." end
    return t
end
R.card_kb_grid = function(s, shift, held)
    local sk = s.skills or {}
    local items
    if shift then
        items = { { "Shift1", "Skills" } }
        for n = 1, 6 do
            if (sk[n] or 0) ~= 0 then items[#items + 1] = { "Skill" .. n, skill_name(sk[n]) } end
        end
    else
        items = { { "AttackS", "Light attack" }, { "AttackL", "Heavy attack" }, { "JobSpecialAction", VOCATION_ACTION_NAMES[s.job] or "Vocation" },
                  { "Jump", "Jump" }, { "Dash", "Dash" }, { "Grab", "Grab" }, { "Sheathe", "Sheathe / draw" }, { "Shift1", "Skills (hold)" },
                  { "Interact", "Interact" } }
    end
    local w = cfg.card_grid_w or 460
    if not imgui.begin_table("kb##" .. tostring(s.name), 2, (4 << 13), Vector2f.new(w, 0), 0) then return end
    local okt, errt = pcall(function()
        for i = 1, 10 do -- always five rows of two: the card keeps its size
            if i % 2 == 1 then imgui.table_next_row() end
            imgui.table_next_column()
            local e = items[i]
            if e then
                local key = R.kb_key(e[1])
                local on = held(e[1])
                imgui.text_colored("[" .. (key or "?") .. "] " .. R.card_short(e[2], 18), on and 0xFF66DDFF or (shift and 0xFFFFFFFF or 0xFFCCCCCC))
            else
                imgui.text(" ")
            end
        end
    end)
    imgui.end_table()
    if not okt then error(errt) end
end
R.card_pad_grid = function(s, shift, held, glyph, btn)
    if s.kb then return R.card_kb_grid(s, shift, held) end
    local pv = coop_pad_values()
    local B = { L1 = pv.LTrigTop or 0x100, L2 = pv.LTrigBottom or 0x200, R1 = pv.RTrigTop or 0x400, R2 = pv.RTrigBottom or 0x800,
                Tri = pv.RUp or 0x10, Sq = pv.RLeft or 0x40, Ci = pv.RRight or 0x80, Cr = pv.RDown or 0x20 }
    local ACT = { "AttackS", "AttackL", "JobSpecialAction", "Jump", "Dash", "Grab", "Sheathe", "Interact" }
    local NAMES = { AttackS = "Light attack", AttackL = "Heavy attack", JobSpecialAction = VOCATION_ACTION_NAMES[s.job] or "Vocation",
                    Jump = "Jump", Dash = "Dash", Grab = "Grab", Sheathe = "Sheathe / draw", Interact = "Interact" }
    local sk = s.skills or {}
    local bp = R.bind and R.bind.pad or {}
    local function what(mask)
        if shift then
            if mask == B.L1 then return "Skills", true end
            for n = 1, 6 do
                if (sk[n] or 0) ~= 0 and bp[n] == mask then return skill_name(sk[n]), held("Skill" .. n) end
            end
            return "", false
        end
        if mask == B.L1 then return "Skills (hold)", false end
        for _, a in ipairs(ACT) do
            for _, e in ipairs(R.bind and R.bind.list or {}) do
                if e.name == a and e.pad == mask and not e.pre then return NAMES[a], held(a) end
            end
        end
        return "", false
    end
    local function cell(key)
        local mask = B[key]
        local t, on = what(mask)
        local g = glyph(R.btn_text(mask) or key)
        if t == "" then imgui.text_colored(g, 0xFF606060) return end
        imgui.text_colored(g .. " " .. R.card_short(t, 16), on and 0xFF66DDFF or (shift and 0xFFFFFFFF or 0xFFCCCCCC))
    end
    local w = cfg.card_grid_w or 360
    if not imgui.begin_table("pad##" .. tostring(s.name), 3, (4 << 13), Vector2f.new(w, 0), 0) then return end
    -- the table is always closed, whatever goes wrong inside (an open ImGui table / window can take the game down)
    local okt, errt = pcall(function()
    local rows = { { "L2", nil, "R2" }, { "L1", nil, "R1" }, { nil, "Tri", nil }, { "Sq", nil, "Ci" }, { nil, "Cr", nil } }
    for _, r in ipairs(rows) do
        imgui.table_next_row()
        for c = 1, 3 do
            imgui.table_next_column()
            if r[c] then cell(r[c]) else imgui.text(" ") end
        end
    end
    -- chord skills (slots 5 / 6) keep one fixed row
    local six = (sk[5] or 0) ~= 0 or (sk[6] or 0) ~= 0
    imgui.table_next_row()
    for c = 1, 3 do
        imgui.table_next_column()
        local n = (c == 1) and 5 or ((c == 3) and 6 or nil)
        if six and n and (sk[n] or 0) ~= 0 then
            local g = glyph(R.btn_text(bp[n] or 0) or "?") -- dev30: the row is the L1 chords; "L1+" left out to fit
            imgui.text_colored(g .. " " .. R.card_short(skill_name(sk[n]), 14), (shift and held("Skill" .. n)) and 0xFF66DDFF or 0xFFAAAAAA)
        else
            imgui.text(" ")
        end
    end
    end)
    imgui.end_table()
    if not okt then error(errt) end
end
R.card_draw = function(s, pn, win, wx, wy, pivot_x)
    -- the player's own colour (the one their glow, target dot and off-screen marker use; the tester: the cards' colours
    -- didn't match the glows)
    local okc, pc = pcall(R.player_abgr, pn)
    local base = (okc and pc) and (pc & 0x00FFFFFF) or R.abgr(R.PLAYER_RGB[((pn - 1) % #R.PLAYER_RGB) + 1], 0)
    local np = 0
    if imgui.push_style_color then
        imgui.push_style_color(10, base | 0xD0000000) -- TitleBg
        imgui.push_style_color(11, base | 0xFF000000) -- TitleBgActive
        imgui.push_style_color(12, base | 0xB0000000) -- TitleBgCollapsed
        imgui.push_style_color(2, (math.floor(255 * math.max(0.1, math.min(1.0, cfg.card_bg_alpha or 0.5))) << 24) | 0x141414) -- WindowBg
        np = 4
    end
    imgui.set_next_window_pos(Vector2f.new(wx, wy), 1, Vector2f.new(pivot_x or 0.0, 1.0))
    local title = string.format("P%d  %s  -  %s###%s", pn, tostring(s.name or "?"), JOB_NAMES[s.job] or "Pawn", win)
    -- no resize / move / scrollbar / collapse, sized to fit, never takes focus
    imgui.begin_window(title, nil, (1 << 1) | (1 << 2) | (1 << 3) | (1 << 5) | (1 << 6) | (1 << 12))
    local okb, errb = pcall(function()
        local function bar(v, rgbb, label)
            if v == nil then return end
            if imgui.progress_bar then
                local n = 0
                if imgui.push_style_color then
                    -- the bar's fill colour (PlotHistogram) sits at a different index in different ImGui versions; 42 /
                    -- 44 were not it in REFramework's build (grey bars). Only the bar is drawn while these are pushed,
                    -- so colouring the whole plot / table range is harmless.
                    for i = 36, 50 do imgui.push_style_color(i, R.abgr(rgbb)); n = n + 1 end
                end
                imgui.progress_bar(v, Vector2f.new(240, 12), "")
                if n > 0 then imgui.pop_style_color(n) end
                imgui.same_line()
                imgui.text(string.format("%s %d%%", label, math.floor(v * 100 + 0.5)))
            else
                imgui.text(string.format("%s %d%%", label, math.floor(v * 100 + 0.5)))
            end
        end
        local bm = cfg.card_bars or 5
        if bm == 1 or bm == 4 or bm == 5 then
            bar(s.hp, 0x60A878, "HP")
            bar(s.st, 0xD2B450, "ST")
            imgui.separator()
        end
        local style = R.dev_style(s.dev or (pn == 2 and R.tp.p2) or nil)
        local function glyph(inner) local ok, pl = pcall(R.pad_label, "[" .. inner .. "]", style); return ok and tostring(pl) or ("[" .. inner .. "]") end
        local btn = s.btn or 0
        -- 0.9.177: like the game's own palette: the skill shift held shows the skills, otherwise the actions; a held
        -- button lights its line. Player 1's card (keyboard or the game's input) uses the game's action flags.
        local fl = s.flags
        local shift
        if fl then shift = (fl & (S.ACTION_FLAGS.Shift1 or 0)) ~= 0 else shift = R.bind_held("Shift1", btn, 0x100) end
        local pm = cfg.card_palette or 4
        local show_sk = pm == 1 or pm == 3 or (pm == 2 and shift)
        local show_act = pm == 3 or (pm == 2 and not shift)
        local function held(action)
            if fl then local f = S.ACTION_FLAGS[action]; return f ~= nil and (fl & f) ~= 0 end
            local m = R.bind_mask(action); return m ~= nil and m ~= 0 and (btn & m) == m
        end
        if pm == 4 then pcall(R.card_pad_grid, s, shift, held, glyph, btn) end
        if show_sk then
            local sk = s.skills or {}
            local six = (sk[5] or 0) ~= 0 or (sk[6] or 0) ~= 0
            for n = 1, 6 do
                local sid = sk[n] or 0
                if sid ~= 0 then
                    local sbl = R.SLOT_BIND_LABELS or {}
                    local lbl = (six and sbl.six and sbl.six[n]) or sbl[n] or ("[Skill " .. n .. "]")
                    local okg, gl = pcall(R.bind_label, n)
                    if okg and gl then lbl = "[Num" .. n .. " / " .. tostring(gl) .. "]" end
                    local inner = lbl:match("/ ([^%]]+)%]") or (lbl:gsub("[%[%]]", ""))
                    local live = (s.sk_now or 0) == sid
                    local press = shift and held("Skill" .. n)
                    local colr = live and 0xFF44FF44 or (press and 0xFF66DDFF or 0xFFFFFFFF)
                    imgui.text_colored(string.format("%s %s  %s", (live or press) and ">" or " ", glyph(inner), skill_name(sid)), colr)
                end
            end
        end
        if show_act then
            if show_sk then imgui.separator() end
            local acts = {
                { "AttackS", "Light attack" }, { "AttackL", "Heavy attack" },
                { "JobSpecialAction", VOCATION_ACTION_NAMES[s.job] or "Vocation action" },
                { "Jump", "Jump" }, { "Dash", "Dash" }, { "Grab", "Grab" }, { "Sheathe", "Sheathe / draw" },
            }
            for _, a in ipairs(acts) do
                local t = R.btn_text(R.bind_mask(a[1]))
                if t then
                    local press = held(a[1]) and not shift
                    imgui.text_colored(string.format("%s %s  %s", press and ">" or " ", glyph(t), a[2]), press and 0xFF66DDFF or 0xFFCCCCCC)
                end
            end
            if pm == 2 then imgui.text_colored(string.format("   %s  skills", glyph(R.btn_text(R.bind_mask("Shift1")) or "L1")), 0xFF909090) end
        end
        if s.int_label then
            imgui.text_colored(string.format("  %s  %s", glyph(R.btn_text(R.bind_mask("Interact") or 0x80) or "Circle"), s.int_label), 0xFF66FFFF)
        end
        local it = s.items or {}
        local im = cfg.card_items or 1
        local ipre = R.qi_pre_mask and R.qi_pre_mask("RecoverHpItem") or 0
        local ipre_t = ipre ~= 0 and R.btn_text(ipre) or nil
        local low = (it.hp and it.hp.n <= 1) or (it.stamina and it.stamina.n <= 1)
        if im == 3 or (im == 2 and not low and os.clock() - (s.dpad_t or 0) > 2.5) then
            s.card_w, s.card_h = imgui.get_window_size and (function() local z = imgui.get_window_size(); return z.x, z.y end)()
            return
        end
        imgui.separator()
        local function item_line(kind, dir)
            local e = it[kind]
            local txt = e and string.format("%s x%d%s", e.name, e.n, e.arisen and "  (Arisen's)" or "") or "none"
            -- dev30: grey until the held button the game wants (ipre) is held
            imgui.text_colored(string.format("  %s  %s", glyph(dir), txt), (e and (ipre == 0 or shift)) and 0xFFE0E0E0 or 0xFF808080)
        end
        if s.kb then
            -- dev30: player 1 on keyboard and mouse: his own keys for the items, the lantern and the orders
            local function kk(a) return "[" .. (R.kb_key(a) or "?") .. "]" end
            -- reported: show the modifier, and grey the line until it is held (the shortcut needs it, as in the game)
            local mod = R.kb_key("Shift1") or "Ctrl"
            local function kline(kind, a)
                local e = it[kind]
                local txt = e and string.format("%s x%d%s", e.name, e.n, e.arisen and "  (Arisen's)" or "") or "none"
                local pre = R.qi_pre_mask and R.qi_pre_mask(a) ~= 0
                local key = pre and ("[" .. mod .. "+" .. (R.kb_key(a) or "?") .. "]") or kk(a)
                imgui.text_colored(string.format("  %s  %s", key, txt), (e and (shift or not pre)) and 0xFFE0E0E0 or 0xFF808080)
            end
            kline("hp", "RecoverHpItem")
            kline("stamina", "RecoverStaminaItem")
            local lpre = R.qi_pre_mask and R.qi_pre_mask("Lantern") ~= 0
            imgui.text_colored(string.format("  %s  Lantern: %s", lpre and ("[" .. mod .. "+" .. (R.kb_key("Lantern") or "?") .. "]") or kk("Lantern"), s.lantern and "on" or "off"),
                (shift or not lpre) and (s.lantern and 0xFF66DDFF or 0xFFC0C0C0) or 0xFF808080)
            imgui.text_colored(string.format("  Orders:  %s Go  %s Come  %s Help  %s Wait", kk("Go"), kk("Come"), kk("Help"), kk("Wait")), 0xFF909090)
        else
        item_line("hp", ipre_t and (ipre_t .. "+Up") or "Up")
        item_line("stamina", ipre_t and (ipre_t .. "+Down") or "Down")
        if cfg.pawn_quick_lantern then
            imgui.text_colored(string.format("  %s  Lantern: %s", glyph("Right"), s.lantern and "on" or "off"), s.lantern and 0xFF66DDFF or 0xFF808080)
        end
        if (cfg.coop_dpad_orders or 2) ~= 1 then -- dev23: the plain D-pad
            if (cfg.coop_dpad_orders or 2) == 2 then imgui.text_colored("  D-pad:  Go / Come / Wait / Help", 0xFF909090) end
        end
        end
        if imgui.get_window_size then local z = imgui.get_window_size(); s.card_w, s.card_h = z.x, z.y end
    end)
    if not okb then s.hud_err = tostring(errb) end
    imgui.end_window()
    if np > 0 then imgui.pop_style_color(np) end
end

-- 0.9.177: cards are requested during the frame and drawn together at its end (layout 2 / 3), or at once where
-- they were asked for (layout 1). The world bars use the same list.
R.cards_q = {}
R.card_req = function(s, pn, win, wx, wy, pivot_x)
    R.cards_q[pn] = { s = s, win = win, wx = wx, wy = wy, px = pivot_x }
    if (cfg.card_layout or 2) == 1 and not (R.views_now and R.views_now()) then return R.card_draw(s, pn, win, wx, wy, pivot_x) end
end
R.cards_flush = function()
    local q = R.cards_q
    R.cards_q = {}
    -- dev22 (the tester: "is there a mode where P1 gets the same card as others in co-op?"): card_p1
    if R.card_p1_on() and next(q) and R.c1view and R.c1view.chara and os.clock() - (R.c1view.card_t or 0) < 1.0 then
        q[1] = { s = R.c1view, win = "DirectPawnControl_SkillHUD_P1" }
    end
    if not next(q) then return end
    -- dev7 (test PC: "Own Spot doesn't work, it's missing P1 card"): with layout 1 every other card was drawn where
    -- it was asked for (R.card_req); player 1's card is only added here, so it is drawn here, in player 1's spot
    if (cfg.card_layout or 2) == 1 and not R.views_now() and q[1] and q[1].s == R.c1view then
        local hx1, hy1, hw1, hh1 = R.hud_rect()
        pcall(R.card_draw, q[1].s, 1, q[1].win, hx1 + hw1 * (cfg.card_p1_left or 0.25), hy1 + hh1 * (cfg.coop_palette_bottom or 0.93), 0.0)
    end
    local ns = {}
    for n in pairs(q) do ns[#ns + 1] = n end
    table.sort(ns)
    local lay = cfg.card_layout or 2
    local hx, hy, hw, hh = R.hud_rect()
    local bottom = hy + hh * (cfg.card_bottom or 0.985)
    local views = R.views_now()
    -- dev49 (the tester: "move the co-op player cards off to one side so it's not rendering over the character model"):
    -- layout 4 stacks the cards up from a point near the left (or right) edge; in split screen, of each player's view.
    local function side_stack(list, x0, y0, w0, h0)
        local right = (cfg.card_side or 1) == 2
        local x = right and (x0 + w0 * (1.0 - (cfg.card_side_x or 0.01))) or (x0 + w0 * (cfg.card_side_x or 0.01))
        local y = y0 + h0 * (cfg.card_side_bottom or 0.80)
        for i = #list, 1, -1 do
            local n = list[i]
            local e = q[n]
            pcall(R.card_draw, e.s, n, e.win, x, y, right and 1.0 or 0.0)
            y = y - (e.s.card_h or 200.0) - 6.0
        end
    end
    -- dev53 (the tester: card options "should be tied to the kind of co-op camera"; "each player's own spot" made no sense
    -- in a quad view): split screen has its own choice, card_layout_split (1 at the side of each view, 2 its bottom
    -- middle); card_layout is for a shared screen only.
    local split_lay = cfg.card_layout_split or 1
    if views and split_lay == 1 then
        local loose = {}
        for _, n in ipairs(ns) do
            local v = R.view_of(views, n)
            if v then side_stack({ n }, v.x, v.y, v.w, v.h) else loose[#loose + 1] = n end
        end
        if #loose > 0 then side_stack(loose, hx, hy, hw, hh) end
    elseif lay == 4 and not views then
        side_stack(ns, hx, hy, hw, hh)
    elseif views then
        -- dev39: split screen: each player's card at the bottom of their own view
        local loose = {}
        for _, n in ipairs(ns) do
            local e, v = q[n], R.view_of(views, n)
            if v then
                local w = e.s.card_w or 260.0
                pcall(R.card_draw, e.s, n, e.win, v.x + v.w * 0.5 - w * 0.5, v.y + v.h * (cfg.card_bottom or 0.985), 0.0)
            else loose[#loose + 1] = n end
        end
        local x = hx + hw * 0.5
        for _, n in ipairs(loose) do
            local e = q[n]
            pcall(R.card_draw, e.s, n, e.win, x, bottom, 0.0)
            x = x + (e.s.card_w or 260.0) + 8.0
        end
    elseif lay == 2 then
        local gap, total = 8.0, 0.0
        for _, n in ipairs(ns) do total = total + (q[n].s.card_w or 260.0) end
        total = total + gap * (#ns - 1)
        local x = hx + hw * 0.5 - total * 0.5
        for _, n in ipairs(ns) do
            local e = q[n]
            pcall(R.card_draw, e.s, n, e.win, x, bottom, 0.0)
            x = x + (e.s.card_w or 260.0) + gap
        end
    elseif lay == 3 then
        local y = bottom
        for i = #ns, 1, -1 do
            local e = q[ns[i]]
            pcall(R.card_draw, e.s, ns[i], e.win, hx + hw * 0.5, y, 0.5)
            y = y - (e.s.card_h or 200.0) - 6.0
        end
    end
    -- 0.9.177: each extra player's interact prompt at the object, in their colour
    for _, n in ipairs(ns) do
        local s = q[n].s
        if s.int_label and s.int_pos then
            pcall(function()
                local sp
                local v = views and R.view_of(views, n)
                if v then
                    local sx, sy = R.vproj(v, s.int_pos[1], s.int_pos[2] + 0.6, s.int_pos[3])
                    sp = sx and { x = sx, y = sy } or nil
                elseif not views then
                    sp = draw.world_to_screen(Vector3f.new(s.int_pos[1], s.int_pos[2] + 0.6, s.int_pos[3]))
                end
                local okc, abgr = pcall(R.player_abgr, n)
                if sp then draw.text(string.format("P%d  %s", n, s.int_label), sp.x, sp.y, okc and abgr or 0xFFFFFFFF) end
            end)
        end
    end
    -- health / stamina over or under each player's character
    local bm = cfg.card_bars or 5
    R.cards_last = q
    if bm == 2 or bm == 3 or bm == 4 or bm == 5 then
        for _, n in ipairs(ns) do
            local s = q[n].s
            local spots = s.spos_multi or (s.spos and { s.spos }) or {}
            for _, spot in ipairs(spots) do
            local sp = spot
            if (s.hp or s.st) and os.clock() - (s.spos_t or 0) < 0.2 then
                pcall(function()
                    local w = math.max(60.0, hw * 0.045)
                    local h = math.max(3.0, hh * 0.0035)
                    local lh = 16.0 -- dev44: the label sits just above the bar's left end (it was a long way left of it,
                    -- and crossed into the next view)
                    if sp.v then -- dev39: keep the bar and its label inside its view
                        w = math.min(w, sp.v.w * 0.25)
                        sp = { x = math.max(sp.v.x + w * 0.5 + 4, math.min(sp.v.x + sp.v.w - w * 0.5 - 4, sp.x)),
                            y = math.max(sp.v.y + lh + 4, sp.y) }
                    end
                    local x, y = sp.x - w * 0.5, sp.y
                    local okc, abgr = pcall(R.player_abgr, n)
                    draw.text("P" .. n, x, y - lh, okc and abgr or 0xFFFFFFFF)
                    if s.hp then
                        draw.filled_rect(x, y, w, h, 0x99000000)
                        draw.filled_rect(x, y, w * s.hp, h, R.abgr(0x60A878))
                        y = y + h + 2.0
                    end
                    if s.st then
                        draw.filled_rect(x, y, w, h, 0x99000000)
                        draw.filled_rect(x, y, w * s.st, h, R.abgr(0xD2B450))
                    end
                end)
            end
            end
        end
    end
end

-- dev22: player 1's card data (card_p1): his character, the game's input flags he presses, his skills
R.c1_tick = function()
    if not R.card_p1_on() then return end
    if not (coop.active or (R.cp and R.cp.on)) then return end
    local on_pawn = (not coop.active and state.active) or (coop.active and R.cp and R.cp.on and R.cp.arisen_side == 2 and state.active)
    local ch = on_pawn and state.pawn_chara or state.arisen_chara
    if not ch then return end
    local v = R.c1view or {}
    R.c1view = v
    v.want_skills, v.dev = true, (R.cp_dev and R.cp_dev(1)) or (R.tp and R.tp.p1) -- dev18: his own controller (R.tp.p1 is the Arisen side's)
    v.kb = R.p1_on_kb and R.p1_on_kb() or false -- dev30: keyboard and mouse: the card shows his keys
    v.name = on_pawn and tostring(state.pawn_name) or "the Arisen"
    if on_pawn then v.flags = state.last_on_flags or 0
    else v.flags = state.arisen_input and field(state.arisen_input, "ButtonOnFlags") or 0 end
    R.card_refresh(v, ch, nil)
end
re.on_pre_application_entry("UpdateBehavior", function() if R.world_now and R.c1_tick then pcall(R.c1_tick) end end)

-- dev22: the world bars' screen positions are worked out at LockScene, when scene and camera are final for the
-- frame (computed at draw time they wiggle as the characters move: the 0.9.43 lesson for player 2's bar). Over =
-- above the head joint; under = at the feet.
R.cards_pos_calc = function()
    local q = R.cards_last
    if not q then return end
    local bm = cfg.card_bars or 5
    if not (bm == 2 or bm == 3 or bm == 4 or bm == 5) then return end
    for _, e in pairs(q) do
        local s = e.s
        local ch = s.chara
        if ch then
            pcall(function()
                local tr = ch:call("get_Transform")
                local p
                if bm == 3 or bm == 5 then
                    p = tr:call("get_Position"); p = Vector3f.new(p.x, p.y - 0.05, p.z)
                else
                    local j = tr:call("getJointByName", "Head_0")
                    local jp = j and j:call("get_Position") or tr:call("get_Position")
                    p = Vector3f.new(jp.x, jp.y + (j and 0.55 or 2.05), jp.z)
                end
                local views = R.views_now()
                if views then -- dev39: in every view that sees the character
                    local m = {}
                    for _, v in ipairs(views) do
                        local sx, sy = R.vproj(v, p.x, p.y, p.z)
                        if sx then m[#m + 1] = { x = sx, y = sy, v = v } end
                    end
                    s.spos, s.spos_multi, s.spos_t = nil, m, os.clock()
                    return
                end
                s.spos_multi = nil
                local sp = draw.world_to_screen(p)
                if sp then s.spos, s.spos_t = { x = sp.x, y = sp.y }, os.clock() else s.spos = nil end
            end)
        end
    end
end
pcall(re.on_pre_application_entry, "LockScene", function() if R.cards_pos_calc then pcall(R.cards_pos_calc) end end)
