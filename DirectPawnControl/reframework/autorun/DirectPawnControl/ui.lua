-- Direct Pawn Control: ImGui settings window, skill palette HUD, diagnostics, startup.
-- Part of DirectPawnControl.lua, which loads the files in this folder in order (this one is 26 of 26).
-- Never run on its own: REFramework only runs the files directly in reframework/autorun.
local S = require("DirectPawnControl/shared")
local VERSION, dev, robot, cfg, save_cfg, R, logs = S.VERSION, S.dev, S.robot, S.cfg, S.save_cfg, S.R, S.logs
local log_msg, enqueue_game_thread, JOB_NAMES = S.log_msg, S.enqueue_game_thread, S.JOB_NAMES
local VOCATION_ACTION_NAMES, skill_name, state, ui_cache = S.VOCATION_ACTION_NAMES, S.skill_name, S.state, S.ui_cache
local brain, coop, apply_native_hud_skills, native = S.brain, S.coop, S.apply_native_hud_skills, S.native
local native_release, native_build, release_possession = S.native_release, S.native_build, S.release_possession
local start_possession, coop_write_status, coop_start = S.start_possession, S.coop_write_status, S.coop_start
local coop_stop, switch_control_mode, warp_arisen_to_pawn = S.coop_stop, S.switch_control_mode, S.warp_arisen_to_pawn
local pawn_do_draw, pawn_do_sheathe, pawn_do_attack = S.pawn_do_draw, S.pawn_do_sheathe, S.pawn_do_attack
local pawn_do_skill_slot, pawn_do_jump = S.pawn_do_skill_slot, S.pawn_do_jump
local pawn_set_fighter_guard, TEST_ENEMY_NAMES = S.pawn_set_fighter_guard, S.TEST_ENEMY_NAMES
local TEST_PRESETS, spawner, test_mark, spawn_test = S.TEST_PRESETS, S.spawner, S.test_mark, S.spawn_test
local despawn_tests = S.despawn_tests

-- ----------------------------------------------------------------------------
-- ImGui UI, Skill Palette HUD & Live Diagnostic Panel
-- ----------------------------------------------------------------------------
local MODE_LABELS = {
    [2] = "Mode 2 (Recommended Safe): ActionSelector Puppeteer (Angle C)",
    [1] = "Mode 1 (Experimental): Native InputProcessor Swap (Angle B)",
    [3] = "Mode 3 (Experimental): Hybrid (Native Processor + Puppeteer Assist)",
}

local SLOT_BIND_LABELS = { -- four-skill layout
    [1] = "[Num1 / L1+Square]",
    [2] = "[Num2 / L1+Triangle]",
    [3] = "[Num3 / L1+Cross]",
    [4] = "[Num4 / L1+Circle]",
    [5] = "[Num5]",
    [6] = "[Num6]",
    six = { -- v0.9.22: the game's layout once slot 5 or 6 holds a skill
        "[Num1 / L1+Square]", "[Num2 / L1+Triangle]", "[Num3 / L1+Cross]", "[Num4 / L1+Circle]", -- 0.9.124: the default layout
        "[Num5 / L1+Triangle+Circle]", "[Num6 / L1+Square+Cross]",
    },
}
R.SLOT_BIND_LABELS = SLOT_BIND_LABELS -- 0.9.171: the player-2 palette (declared earlier in the file) reads it here

re.on_draw_ui(function()
    if imgui.tree_node("Direct Pawn Control (v" .. VERSION .. ")") then
        local chg
        chg, cfg.window_open = imgui.checkbox("Show the settings window", cfg.window_open)
        if chg then save_cfg() end
        imgui.tree_pop()
    end
end)

-- v0.9.16: the rectangle overlays are placed in. On an ultrawide screen the middle 16:9, so a 16:9 recording
-- (OBS crop) shows them. The windows can still be dragged while the REFramework menu is open.
function R.hud_rect()
    local disp = imgui.get_display_size()
    local W = (disp and disp.x and disp.x > 400) and disp.x or 1920
    local H = (disp and disp.y and disp.y > 300) and disp.y or 1080
    local safe = cfg.hud_safe_169
    if safe == "auto" then safe = (W / H) > 1.9 end
    if safe and W / H > 16 / 9 then
        local w = H * 16 / 9
        return (W - w) * 0.5, 0, w, H
    end
    return 0, 0, W, H
end

R.hud_hide_t, R.hud_hide = 0, false
function R.hud_hidden()
    local now = os.clock()
    if R.world ~= true then R.hud_hide = true; return true end
    if now < R.hud_hide_t then return R.hud_hide end
    R.hud_hide_t = now + 0.1
    local hide = false
    pcall(function()
        local function num(v)
            if type(v) == "userdata" then
                local okv, x = pcall(v.get_field, v, "value__")
                v = okv and x or nil
            end
            return tonumber(v)
        end
        local gm = sdk.get_managed_singleton("app.GuiManager")
        if gm and gm:call("isPausedGUI") == true then hide = true; return end
        local fm = sdk.get_managed_singleton("app.FacilityManager")
        if fm and (num(fm:call("get_ExecFacility")) or 0) ~= 0 then hide = true; return end
        -- 0.9.172-dev37 (the tester: "get rid of the co-op camera in the rift"): the Rift is the game's "Rim"
        -- (app.FacilityManager.RimStateNow: None 0 / End 15 outside it). Co-op stays on; the overlays hide there.
        local rs = fm and num(fm:get_field("RimStateNow"))
        R.rift = rs ~= nil and rs ~= 0 and rs ~= 15
        R.rift_state = rs
        if R.rift then hide = true; return end
        if coop.active then
            local cm = sdk.get_managed_singleton("app.CameraManager")
            local mc = cm and cm:call("getMainCameraController", 0)
            -- 0.9.172-dev26: the climbing camera (control type 6) too, like the bow aim (7): the target markers and
            -- player 2's bars vanished as soon as player 1 started climbing (the tester, coop-climb-2)
            -- 0.9.172-dev27: the game cameras agreed with the tester (2026-11-21) where play goes on: normal, combat, narrow,
            -- notice, climbing, bow aim, ballista, following an NPC, shot. Cutscenes, talk, cinematic grabs, photo,
            -- character edit and the rest still hide the overlays.
            local ctv = num(mc and mc:call("get_CurrentControlType"))
            if mc and mc:call("get_CurrentPlayerCamera") == false and not R.OVERLAY_CAMS[ctv or -1] then
                hide = true
            end
        end
    end)
    R.hud_hide = hide
    return hide
end

re.on_frame(function()
    local hx, hy, hw, hh = R.hud_rect()
    local cond = 1 << 1                       -- ImGuiCond_Once
    if (R.hud_repos or 0) > 0 then R.hud_repos = R.hud_repos - 1; cond = 1 end -- Always, for a few frames
    if not R.hud_hidden() then
    -- 1. Top-Left Status HUD Banner while possessing a Pawn
    if state.active and cfg.hud_overlay then
        imgui.set_next_window_pos(Vector2f.new(hx + 24, hy + 24), cond)
        imgui.begin_window("DirectPawnControl_HUD", nil, (1 << 0) | (1 << 1) | (1 << 3) | (1 << 6))
        local hp = ui_cache.hp or 0
        local max_hp = ui_cache.max_hp or 1
        local job_str = JOB_NAMES[state.pawn_job] or "Pawn"
        imgui.text_colored(string.format("CONTROLLING PAWN: %s (%s)", state.pawn_name, job_str), 0xFF55FF55)
        imgui.text(string.format("HP: %.0f / %.0f  |  Speed: %.1f m/s  |  Action: %s", hp, max_hp, state.live_speed_mps, state.last_action_str))
        imgui.text_colored(string.format("[%s] Select   [%s] Go to selection   [Numpad 1-6] Order it   [%s] Warp Arisen here", R.key_label("cycle_pawn"), R.key_label("toggle_possess"), R.key_label("warp_arisen")), 0xFFCCCCCC)
        if coop.active then
            imgui.text_colored("CO-OP  P1: Arisen (mouse+keyboard)   P2: " .. tostring(state.pawn_name) .. " (controller)", 0xFFCCCCCC)
        else
        imgui.text_colored(state.arisen_stay and "Arisen: WAITING  (Come = follow)" or "Arisen: FOLLOWING  (Wait = stay)", 0xFFCCCCCC)
        imgui.text_colored("Selection: " .. tostring(R.sel_name or "the Arisen"), 0xFF30D0FF)
        end
        if brain.on then
            imgui.text_colored(string.format("Arisen brain: %s  %s %.0fm", tostring(brain.mode), tostring(brain.target_id), brain.dist or 0), 0xFFCCCCCC)
        end
        imgui.end_window()
    end

    -- v0.9.42 co-op: thin yellow stamina bar under player 2's pawn's health bar. The game's plate is not read; the bar
    -- is anchored to a point above the pawn's feet (the plate looked anchored there in the tester's screenshots: health
    -- bar about 252 px wide at 2160 p, centred over the root, roughly 1.9 m up) and tuned with two settings.
    if cfg.arisen_bars and state.active and not coop.active then
        if not R.stam_cb_ok then R.ar_calc() end
        if R.ar_ok and R.ar_hp and os.clock() - (R.ar_t or 0) < 0.25 then
            pcall(function()
                local k = hh / 2160.0
                local h = math.max(2.0, (cfg.coop_bars_thick or 4.0) * k)
                local al = math.floor(255 * math.max(0.15, math.min(1.0, cfg.coop_bars_alpha or 0.65)))
                local function col(rgb, f) return (math.floor(al * (f or 1.0)) << 24) | rgb end
                local w, x, y, label
                if R.ar_sx then
                    w = 252.0 * k
                    x, y = math.floor(R.ar_sx - w * 0.5 + 0.5), math.floor(R.ar_sy + 0.5)
                else
                    w = hw * 0.16 * (cfg.coop_stamina_width or 1.0)
                    x = hx + hw * (cfg.coop_stamina_hud_x or 0.5) - w * 0.5
                    y = hy + hh * (cfg.coop_stamina_hud_y or 0.9)
                    label = true
                end
                draw.filled_rect(x, y, w, h, col(0x000000, 0.55))
                if R.ar_cap and R.ar_cap > R.ar_hp then draw.filled_rect(x, y, w * R.ar_cap, h, col(0x2A502A)) end
                -- v0.9.75: below the danger share his health bar turns red and pulses
                if R.ar_hp < (R.danger_rate or 0.25) then
                    draw.filled_rect(x, y, w * R.ar_hp, h * 1.5, col(0x3030F0, 0.75 + 0.75 * math.abs(math.sin(os.clock() * 5.0))))
                else
                    draw.filled_rect(x, y, w * R.ar_hp, h, col(0x60A878))
                end
                if R.ar_st then
                    local y2 = y + h + math.max(2.0, hh * 0.003)
                    draw.filled_rect(x, y2, w, h, col(0x000000, 0.55))
                    draw.filled_rect(x, y2, w * R.ar_st, h, col(0x50B4D2))
                end
                if label then draw.text("Arisen", x, y - math.max(16.0, hh * 0.02), col(0xD8D8D8)) end
            end)
        end
    end

    -- v0.9.43: the position is computed in R.stam_calc at LockScene (scene and camera final for the frame); computing
    -- it here, at draw time, wiggled on every movement (the tester).
    if coop.active and cfg.coop_stamina_bar and state.pawn_chara and not (cfg.coop_player_card ~= false and cfg.coop_skill_palette) then
        if not R.stam_cb_ok then R.stam_calc() end
        local fresh = R.stam_ratio and os.clock() - (R.stam_t or 0) < 0.25
        if fresh and cfg.coop_stamina_attach then
            if R.stam_x then
                pcall(function()
                    draw.filled_rect(R.stam_x - 1, R.stam_y - 1, R.stam_w + 2, R.stam_h + 2, 0xB0000000)
                    draw.filled_rect(R.stam_x, R.stam_y, R.stam_w * R.stam_ratio, R.stam_h, 0xFF2BD0FF)
                end)
            end
        elseif fresh then
            -- v0.9.48: fixed HUD bar (default). Three anchors for a bar under the game's plate (feet, LockScene,
            -- Head_0) all drifted against it: with the head the height matched but the plate sat 100 - 260 px to
            -- either side. The plate's own position is not readable, so player 2's stamina gets a fixed place.
            pcall(function()
                -- v0.9.50: thin and muted so the pair sits behind the Arisen's own gauges (the tester: 0.9.49 was about
                -- 12 px thick and brighter than the game's bars). Thickness and opacity are settings.
                local w = hw * 0.16 * (cfg.coop_stamina_width or 1.0)
                local h = math.max(2.0, (cfg.coop_bars_thick or 4.0) * hh / 2160.0)
                local x = hx + hw * (cfg.coop_stamina_hud_x or 0.5) - w * 0.5
                local y = hy + hh * (cfg.coop_stamina_hud_y or 0.9)
                local al = math.floor(255 * math.max(0.15, math.min(1.0, cfg.coop_bars_alpha or 0.65)))
                local function col(rgb, f) return (math.floor(al * (f or 1.0)) << 24) | rgb end
                local gap = h + math.max(2.0, hh * 0.003)
                local ty = y - math.max(16.0, hh * 0.02)
                if cfg.coop_health_bar and R.stam_hp then
                    draw.filled_rect(x, y, w, h, col(0x000000, 0.55))
                    if R.stam_hp_cap and R.stam_hp_cap > R.stam_hp then draw.filled_rect(x, y, w * R.stam_hp_cap, h, col(0x2A502A)) end
                    draw.filled_rect(x, y, w * R.stam_hp, h, col(0x60A878))
                    y = y + gap
                end
                draw.filled_rect(x, y, w, h, col(0x000000, 0.55))
                draw.filled_rect(x, y, w * R.stam_ratio, h, col(0x50B4D2))
                draw.text((R.cp_pawn_label and R.cp_pawn_label() or "P2") .. "  " .. tostring(state.pawn_name or ""), x, ty, col(0xD8D8D8))
            end)
        end
    end

    -- v0.9.110 selection name on the HUD (the marker cannot be seen when the pick is off screen). Requested: a name label left of the health and stamina bars.
    -- Bright for 4 s after a change; stays dim while a pawn other than the default pick is selected.
    -- v0.9.114: the same line also says, for 3 s, who you just started playing ("Playing as <name>", "Back to the
    -- Arisen", "Co-op: player 2 plays <name>"): the only on-screen word from the mod now that the status panel is off.
    if cfg.sel_label ~= false and (R.sel_label or R.note) then
        pcall(function()
            local now = os.clock()
            local note = R.note and now < R.note.t_end and R.note.text or nil
            local fresh = now < (R.sel_label_until or 0)
            local keep = state.active and not coop.active and R.sel_kind == "pawn" and R.sel_idx ~= nil
            if not (note or (R.sel_label and (fresh or keep))) then return end
            if note then fresh = true end
            local a = fresh and 255 or 150
            local x = hx + hw * (cfg.sel_label_x or 0.215)
            local y = hy + hh * (cfg.sel_label_y or 0.957)
            -- v0.9.111 bigger text (requested: a larger font): the default font loaded at a size that
            -- follows the screen height (sel_label_size, share of the height; 30 px at 2160). Loaded once per size;
            -- if the font cannot be loaded the label falls back to the small built-in text.
            local px = math.floor(hh * (cfg.sel_label_size or 0.014) + 0.5)
            if px ~= R.sel_font_px then
                R.sel_font_px, R.sel_font = px, nil
                pcall(function() R.sel_font = imgui.load_font(nil, px) end)
                R.sel_font_t = now
            end
            local pushed = false
            -- not on the frames right after loading: the font atlas is rebuilt first
            if R.sel_font and now - (R.sel_font_t or now) > 0.5 then pushed = pcall(imgui.push_font, R.sel_font) end
            if pushed then y = y - px * 0.45 end
            local okd = pcall(draw.text, note or ("Selected:  " .. tostring(R.sel_label)), x, y, (a << 24) | (note and 0xFFFFFF or 0x30D0FF))
            if pushed then pcall(imgui.pop_font) end
            R.sel_font_ok = pushed and okd
        end)
    end

    -- v0.9.149 the controls hint: one dim line over the selection label
    if cfg.hint_controls and R.hint then
        pcall(function()
            local now = os.clock()
            local px = math.floor(hh * (cfg.sel_label_size or 0.014) + 0.5)
            if px ~= R.sel_font_px then
                R.sel_font_px, R.sel_font = px, nil
                pcall(function() R.sel_font = imgui.load_font(nil, px) end)
                R.sel_font_t = now
            end
            local x = hx + hw * (cfg.sel_label_x or 0.215)
            local y = hy + hh * (cfg.hint_y or 0.925)
            local pushed = false
            if R.sel_font and now - (R.sel_font_t or now) > 0.5 then pushed = pcall(imgui.push_font, R.sel_font) end
            if pushed then y = y - px * 0.45 end
            pcall(draw.text, R.hint, x + 1, y + 1, 0xA0000000)
            pcall(draw.text, R.hint, x, y, 0xC0E0E0E0)
            if pushed then pcall(imgui.pop_font) end
        end)
    end

    -- v0.9.90 selection marker: a yellow wedge and the name over the picked character for 3 s after F7
    if R.cr.want and R.cr.down then
        pcall(function()
            local x, y = R.ta_screen(R.cr.down)
            local k = hh / 2160.0
            local pulse = 0.5 + 0.5 * math.sin(os.clock() * 6.0)
            local txt = "Revive " .. tostring(R.cr.name or "player 2")
            if x then
                y = y - 90.0 * k
                draw.filled_circle(x, y, (18.0 + 6.0 * pulse) * k, 0xC0000000, 24)
                draw.filled_circle(x, y, (14.0 + 6.0 * pulse) * k, 0xF02020E0, 24)
                draw.text(txt, x - 40, y - 34.0 * k - 16, 0xF0FFFFFF)
            else
                draw.text("Player 2 is down: " .. txt, hx + hw * 0.5 - 110, hy + hh * 0.12, 0xF04040FF)
            end
        end)
    end
    if cfg.coop_aim and coop.active then
        local okd, errd = pcall(R.ta_draw, hh)
        if not okd then R.ta_dbg = "aim error: " .. tostring(errd) end
    end
    if R.ping and R.ping.pos then
        pcall(function()
            local sp = draw.world_to_screen(Vector3f.new(R.ping.pos[1], R.ping.pos[2], R.ping.pos[3]))
            if not sp then return end
            local k = hh / 2160.0
            local left = math.max(0.0, R.ping.t_end - os.clock())
            local a = math.floor(255 * math.min(1.0, left / 0.6))
            local bob = math.sin(os.clock() * 6.0) * 6.0 * k
            local w, h = 26.0 * k, 34.0 * k
            local x, y = sp.x, sp.y + bob
            local col = (a << 24) | 0x30D0FF
            draw.filled_quad(x - w, y - h, x + w, y - h, x, y, x, y, col)
            -- v0.9.112: no name here (the game's own name plate is already over his head; the HUD label names him)
        end)
    end

    -- v0.9.26 DPC's own Gather / Loot prompt for the possessed pawn
    if state.active and cfg.pawn_interact and (R.int_obj or R.int_wake or R.int_rev) then
        -- v0.9.37: the prompt sits over the thing itself (in co-op the pawn can be anywhere on screen); the fixed
        -- lower-middle spot is only the fallback when the object is off screen.
        local ix, iy = hx + hw * 0.5 - 110, hy + hh * 0.62
        local ipos = R.int_pos or (R.int_rev and R.int_rev.pos)
        if ipos then
            local oksp, sp = pcall(draw.world_to_screen, Vector3f.new(ipos[1], ipos[2] + 0.35, ipos[3]))
            if oksp and sp then
                local ds = imgui.get_display_size()
                if sp.x > 20 and sp.y > 20 and sp.x < ds.x - 220 and sp.y < ds.y - 40 then ix, iy = sp.x - 70, sp.y - 30 end
            end
        end
        -- v0.9.69 hold ring for Revive: a dim ring left of the prompt, filled clockwise from the top
        if R.int_wake and R.int_wake_kind == "Revive" and (cfg.pawn_revive_hold or 0) > 0 then
            pcall(function()
                local k = hh / 2160.0
                local cx, cy = ix - 34.0 * k, iy + 22.0 * k
                local r1, r0 = 24.0 * k, 16.0 * k
                local N = 48
                local prog = R.rev_prog or 0.0
                for i = 0, N - 1 do
                    local a0 = (i / N) * 2 * math.pi - math.pi / 2
                    local a1 = ((i + 1) / N) * 2 * math.pi - math.pi / 2
                    local c0, s0, c1, s1 = math.cos(a0), math.sin(a0), math.cos(a1), math.sin(a1)
                    local col = ((i + 0.5) / N <= prog) and 0xFFF0F0F0 or 0x70000000
                    draw.filled_quad(cx + c0 * r0, cy + s0 * r0, cx + c0 * r1, cy + s0 * r1,
                                     cx + c1 * r1, cy + s1 * r1, cx + c1 * r0, cy + s1 * r0, col)
                end
            end)
        end
        imgui.set_next_window_pos(Vector2f.new(ix, iy), 1)
        imgui.begin_window("DirectPawnControl_Interact", nil, (1 << 0) | (1 << 1) | (1 << 3) | (1 << 6))
        -- 0.9.177 (the tester: "should this prompt have a hint of colour matching the player colour?"): the prompt is in the
        -- colour of the player whose pawn it is, with that player's button, and says "Open chest" on chests
        local pn = (coop.active and not (R.cp and R.cp.on and R.cp.arisen_side == 2)) and 2 or 1
        local okc, pcol = pcall(R.player_abgr, pn)
        local btn = "[Interact]"
        if pn == 2 or not (R.p1_on_kb and R.p1_on_kb() and not coop.active) then
            local t = R.btn_text(R.bind_mask("Interact"))
            if t then
                local okl, gl = pcall(R.pad_label, "[" .. t .. "]", pn == 2 and R.dev_style(R.tp.p2) or R.pad_style())
                if okl and gl and (pn == 2 or R.pad_style() and (R.pad_kind or 0) > 0) then btn = tostring(gl) end
            end
        end
        local what = R.int_wake and (((R.int_wake_kind == "Revive" and (cfg.pawn_revive_hold or 0) > 0) and "Hold: Revive" or tostring(R.int_wake_kind or "Wake")) .. " " .. tostring(R.int_wake_name))
            or (R.int_obj and R.int_label_for(R.int_name, R.int_dead, R.int_item))
            or (R.int_rev and R.rev_npc_label and R.rev_npc_label())
            or ""
        imgui.text_colored(string.format("%s%s  %s", coop.active and ("P" .. pn .. "  ") or "", btn, what), (okc and pcol) or 0xFF66FFFF)
        imgui.end_window()
    end

    -- 2. Bottom-Right Dynamic Pawn Skill Palette HUD Overlay (Issue 1 Fix)
    -- v0.9.70: in co-op the palette is back for player 2 (the game's own skill HUD belongs to player 1's Arisen),
    -- with the controller buttons only.
    local p2_pal = coop.active and cfg.coop_skill_palette
    if state.active and p2_pal and cfg.coop_player_card ~= false and R.card_draw then
        -- 0.9.177: player 2's card (classic co-op: player 2 on a pawn)
        local v = R.c2view or {}
        if R.cp and R.cp.on and R.cp.arisen_side == 2 then -- dev7: player 2 is on the Arisen (job / skills from R.item_tick)
            v.name, v.dev = "the Arisen", R.cp_dev(2) -- dev18: his own controller (R.tp.p2 is the pawn side's: player 1's)
        else
            v.name, v.job, v.skills, v.dev = state.pawn_name, state.pawn_job, state.pawn_skills, R.tp.p2
        end
        R.card_req(v, 2, "DirectPawnControl_SkillHUD", hx + hw * (cfg.coop_palette_left or 0.60), hy + hh * (cfg.coop_palette_bottom or 0.93), 0.0)
        p2_pal = false
    elseif state.active and (cfg.skill_hud_overlay or p2_pal) then
        local wx, wy = hx + hw - 340, hy + hh - 230
        if p2_pal then
            -- v0.9.71: right of player 2's bars, bottom edge level with them (the 0.9.70 spot covered the game's
            -- own button hints). Anchored by its bottom-left corner so a longer list grows upward.
            wx, wy = hx + hw * (cfg.coop_palette_left or 0.60), hy + hh * (cfg.coop_palette_bottom or 0.93)
            imgui.set_next_window_pos(Vector2f.new(wx, wy), 1, Vector2f.new(0.0, 1.0))
        else
            imgui.set_next_window_pos(Vector2f.new(wx, wy), cond)
        end
        imgui.begin_window("DirectPawnControl_SkillHUD", nil, (1 << 0) | (1 << 1) | (1 << 3) | (1 << 6))
        local job_str = JOB_NAMES[state.pawn_job] or "Pawn"
        local voc_act = VOCATION_ACTION_NAMES[state.pawn_job] or "Vocation Action"
        imgui.text_colored(string.format(p2_pal and "Player 2: %s (%s)" or "%s — %s Skills", state.pawn_name, job_str), 0xFF88EEFF)
        imgui.separator()
        local active_sk = ui_cache.active_sk or 0
        for s = 1, 6 do
          local sid = state.pawn_skills and state.pawn_skills[s] or 0
          if s <= 4 or sid ~= 0 then
            local sname = skill_name(sid)
            local is_active = (sid ~= 0 and active_sk == sid)
            local color = is_active and 0xFF44FF44 or (sid ~= 0 and 0xFFFFFFFF or 0xFF888888)
            local prefix = is_active and ">> " or "   "
            local six = state.pawn_skills and ((state.pawn_skills[5] or 0) ~= 0 or (state.pawn_skills[6] or 0) ~= 0)
            local lbl = six and SLOT_BIND_LABELS.six[s] or SLOT_BIND_LABELS[s]
            local gl = R.bind_label(s) -- 0.9.100: the game's own assignment when it could be read
            if gl then lbl = "[Num" .. s .. " / " .. gl .. "]" end
            if p2_pal then lbl = R.pad_label("[" .. (lbl:match("/ ([^%]]+)%]") or lbl:gsub("[%[%]]", "")) .. "]", R.dev_style(R.tp.p2)) end
            if not p2_pal or sid ~= 0 then
                imgui.text_colored(string.format("%s%s  %s", prefix, lbl, sname), color)
            end
          end
        end
        imgui.separator()
        local voc_color = (state.is_guarding or state.is_aiming or state.is_quickspelling) and 0xFF44FF44 or 0xFFCCCCCC
        local voc_btn = R.btn_text(R.bind_mask("JobSpecialAction")) or "R1" -- v0.9.124: from the game's assignment
        imgui.text_colored(string.format(p2_pal and ("   " .. R.pad_label("[" .. voc_btn .. "]", R.dev_style(R.tp.p2)) .. "  %s") or ("   [" .. R.pad_label(voc_btn) .. "]  %s"), voc_act), voc_color)
        imgui.end_window()
    end
    end

    if not cfg.window_open then return end
    -- v0.9.114: the settings window belongs to the REFramework menu; it never sits over the game on its own
    do
        local okd, drawing = pcall(reframework.is_drawing_ui, reframework)
        if okd and drawing == false then return end
    end

    cfg.window_open = imgui.begin_window("Direct Pawn Control  v" .. VERSION, cfg.window_open, 1 << 6)
    if not cfg.window_open then
        save_cfg()
        imgui.end_window()
        return
    end
    -- v0.9.124: a key of the mod that the game also uses (after a remap in the game's options)
    do
        local okc, cl = pcall(R.key_clashes)
        if okc and cl and #cl > 0 then
            for _, c in ipairs(cl) do imgui.text_colored("Key clash: " .. c, 0xFF40C0FF) end
        end
    end

    local party = ui_cache.party or {}
    local chg
    local GREEN, GREY, BLUE, RED, YELLOW = 0xFF55FF55, 0xFFAAAAAA, 0xFFFFCC88, 0xFF5555FF, 0xFF55DDFF

    -- ===== 1. Possession =====================================================================================
    if state.active then
        imgui.text_colored(string.format("POSSESSING %s (%s)", state.pawn_name, JOB_NAMES[state.pawn_job] or "Pawn"), GREEN)
        if imgui.button("Release [F6]") then
            enqueue_game_thread("UI release_possession", function() release_possession("UI button") end)
        end
        imgui.same_line()
        if imgui.button("Warp Arisen here [F8]") then enqueue_game_thread("UI warp_arisen", warp_arisen_to_pawn) end
    else
        imgui.text_colored("Playing as the Arisen", BLUE)
    end
    for _, e in ipairs(party) do
        local is_sel = (cfg.selected_pawn_idx == e.idx)
        local is_possessed = (state.active and state.pawn_idx == e.idx)
        local label = string.format("%s%s (%s)##pawn%d", is_possessed and "* " or (is_sel and "> " or ""), e.name, e.job_name, e.idx)
        if e.idx > 0 then imgui.same_line() end
        if imgui.button(label) then
            local idx = e.idx
            cfg.selected_pawn_idx = idx
            save_cfg()
            enqueue_game_thread("UI possess", function() start_possession(idx) end)
        end
    end
    if #party == 0 then imgui.text_colored("No party pawns found", RED) end
    imgui.text_colored(string.format("Click a pawn to possess it.  %s select (marker)   %s take control of the selection   Numpad 1-6 order it   %s warp Arisen", R.key_label("cycle_pawn"), R.key_label("toggle_possess"), R.key_label("warp_arisen")), GREY)

    -- Couch co-op (v0.9)
    if coop.active then
        imgui.text_colored(string.format("CO-OP: player 2 (controller) plays %s   map: %s", tostring(state.pawn_name), tostring(coop.map_src)), GREEN)
        if imgui.button("Stop co-op [Ctrl+F6]") then enqueue_game_thread("UI coop stop", coop_stop) end
        if cfg.show_legacy then
            imgui.same_line()
            imgui.text(string.format("pad 0x%X -> 0x%X", coop.last_btn or 0, coop.last_flags or 0))
        end
        if coop.err then imgui.text_colored("co-op error: " .. tostring(coop.err), RED) end
        if R.ta_dbg and cfg.show_legacy then imgui.text(R.ta_dbg) end
        if cfg.coop_two_pads and (R.tp.n or 0) >= 2 then
            if R.tp_on() then
                imgui.text_colored("Two controllers: player 1 = Arisen, player 2 = pawn", GREEN)
                if imgui.button("Swap controllers") then R.tp_swap() end
                imgui.same_line()
                if imgui.button("Choose again (player 2 holds L3 + R3)") then R.tp_reset(); pcall(json.dump_file, "DPC_two_pads.json", {}) end
                local t = R.tp
                local p2v = { b = 0 }
                for _, d in ipairs(R.tp_devs()) do if d:get_address() == t.p2 then p2v = R.tp_read(d) end end
                local ai = state.arisen_input
                local aon = 0
                pcall(function() aon = ai and (ai:get_field("ButtonOnFlags") or 0) or 0 end)
                if cfg.show_legacy then
                    imgui.text(string.format("P1 pad 0x%X   P2 pad 0x%X   game -> Arisen 0x%X   Arisen actions 0x%X",
                        R.tp_p1().b or 0, p2v.b or 0, t.pb_in or 0, aon))
                    imgui.text(string.format("processButton: %d calls, %d this frame, arg 0x%X", t.pb or 0, t.pb_same or 0, t.pb_a3 or 0))
                end
            else
                imgui.text_colored("Two controllers: player 2, hold L3 + R3 on your controller", YELLOW or GREEN)
            end
        end
    else
        local sel_name = "selected pawn"
        for _, e in ipairs(party) do if e.idx == cfg.selected_pawn_idx then sel_name = e.name end end
        if imgui.button("Start couch co-op: controller plays " .. sel_name .. " [Ctrl+F6]") then
            enqueue_game_thread("UI coop start", function() coop_start(cfg.selected_pawn_idx) end)
        end
    end

    -- ===== 2. Settings (v0.9.82: grouped; advanced, test and legacy options live in a separate, hidden bin) ====
    imgui.separator()
    local function cb(label, key)
        local c
        c, cfg[key] = imgui.checkbox(label, cfg[key])
        if c then save_cfg() end
        return c
    end
    local function sl(label, key, lo, hi, fmt)
        local c
        c, cfg[key] = imgui.slider_float(label, cfg[key], lo, hi, fmt or "%.2f")
        if c then save_cfg() end
    end
    local function group(title, open_first)
        if open_first and imgui.set_next_item_open then pcall(imgui.set_next_item_open, true, 1 << 1) end
        return imgui.tree_node(title)
    end

    -- 0.9.172-dev21 settings layout (the tester: "hide/remove options that no longer make sense, hide away options that are
    -- rarely necessary, and put the most high impact modes at the top where players can tune the feel"). Top: a few
    -- choices that change how the mod plays, each one line. Then co-op. Everything else folds away; diagnostics and
    -- superseded switches only with "Show advanced, test and legacy options".
    local function pick(label, key, values, labels)
        local cur = 1
        for i, v in ipairs(values) do if cfg[key] == v then cur = i end end
        local c, v = imgui.combo(label, cur, labels)
        if c then cfg[key] = values[v]; save_cfg() end
        return c
    end
    local CD = rawget(_G, "CameraDistance_API")
    -- dev48 (the tester: choices "where it's one of a few very different ones appear as buttons like radio buttons so they
    -- can see all options at once"). REFramework's imgui has no radio_button: one tick box per option, ticking one
    -- picks it (unticking the picked one keeps it). inline = the options on one line (short labels).
    -- dev51 (the tester, with a screenshot of another mod's row of preset buttons: "let's try something like these buttons
    -- where the options are each a button"): one button per option on one line, the picked one in blue. A label may
    -- be "Short|what it does": the button shows the short part, the picked option's long part is written under the row.
    local function choose(title, cur, labels, id, inline, indent)
        indent = indent or ""
        imgui.text(indent .. title)
        local picked, desc = nil, nil
        for k, lab in ipairs(labels) do
            local short, long = lab:match("^(.-)|(.*)$")
            short = short or lab
            if k == cur then desc = long end
            if k > 1 then imgui.same_line() end
            local np = 0
            if k == cur and imgui.push_style_color then
                imgui.push_style_color(21, 0xFFC07830) -- Button (ABGR): blue
                imgui.push_style_color(22, 0xFFD08A40) -- ButtonHovered
                imgui.push_style_color(23, 0xFFE09C50) -- ButtonActive
                np = 3
            end
            if imgui.button(short .. "##" .. id .. k) and k ~= cur then picked = k end
            if np > 0 then imgui.pop_style_color(np) end
        end
        if desc and desc ~= "" then imgui.text_colored(indent .. "   " .. desc, GREY) end
        return picked ~= nil, picked
    end
    local function pick_r(title, key, values, labels, id, inline, indent)
        local cur = 1
        for k, v in ipairs(values) do if cfg[key] == v then cur = k end end
        local c, v = choose(title, cur, labels, id, inline, indent)
        if c then cfg[key] = values[v]; save_cfg() end
        return c
    end

    -- 0.9.177-dev47 settings layout (the tester: "clean up the settings so the most impactful and important ones are on
    -- top (such as which co-op camera to use) so people even know they exist"). Top: the handful of choices that
    -- change how the game plays, always visible. Then one folder per subject, each named for what it holds. Old HUD
    -- pieces the player cards replaced, and troubleshooting switches, are under "Show advanced, test and legacy options".
    local SS = rawget(_G, "DPC_SplitScreen")
    imgui.text_colored("Main choices", BLUE)
    do -- one co-op camera choice: Camera Distance's two styles, or the Split Screen add-on
        local labels, vals = {}, {}
        if CD and CD.get then
            labels[#labels + 1], vals[#vals + 1] = "Shared: middle|One shared view, aimed at the middle of everyone", "classic"
            labels[#labels + 1], vals[#vals + 1] = "Shared: follow P1|One shared view, follows player 1 and pulls back for the others", "follow"
        end
        if SS and SS.cfg then labels[#labels + 1], vals[#vals + 1] = "Split screen (early)|Every player gets their own view. Early release: see Known limits in the README", "split" end
        if #labels > 0 then
            local now = (SS and SS.cfg and SS.cfg.enabled) and "split" or ((CD and CD.get and CD.get("coop_style") == "follow") and "follow" or "classic")
            local cur = 1
            for k, v in ipairs(vals) do if v == now then cur = k end end
            local c, v = choose("Co-op camera", cur, labels, "coopcam")
            if c then
                local want = vals[v]
                if SS and SS.cfg then SS.cfg.enabled = (want == "split"); if SS.save then pcall(SS.save) end end
                if want ~= "split" and CD and CD.set then CD.set("coop_style", want) end
            end
            if SS and SS.cfg and SS.cfg.enabled then
                local function spick(label, key, labs)
                    local c2, v2 = choose(label, SS.cfg[key] or 1, labs, "ss" .. key, true, "      ")
                    if c2 then SS.cfg[key] = v2; if SS.save then pcall(SS.save) end end
                end
                spick("2 players:", "layout", { "Auto", "Side by side", "Top and bottom" })
                spick("3 players:", "layout3", { "Auto", "Three across", "2 x 2 grid" })
                if (SS.cfg.layout3 or 1) == 3 then spick("   fourth quarter:", "spare", { "Blank", "The party from above" }) end
                spick("4 players:", "layout4", { "2 x 2 grid", "Four across" })
                spick("Sound heard from:", "sound_from", { "Player 1's view", "Middle of the players" }) -- dev50
                -- dev54: each player's camera from Camera Distance's presets (player 1: Camera Distance's own preset;
                -- players 2-4: Split Screen 0.2.0-dev13 applies the preset to their view)
                local okp, plist = pcall(function() return CD and CD.presets and CD.presets() end)
                if okp and plist and #plist > 0 then
                    local labs = {}
                    for _, pr in ipairs(plist) do
                        local short = (pr.name or "?"):match("^(.-)%s*[%(/]") or pr.name
                        labs[#labs + 1] = (short ~= "" and short or pr.name) .. "|" .. (pr.desc or pr.name)
                    end
                    local okc, cur1 = pcall(CD.active_preset)
                    local c1, v1 = choose("Player 1's camera:", (okc and tonumber(cur1)) or 1, labs, "p1cam", true, "      ")
                    if c1 and CD.apply_preset then pcall(CD.apply_preset, v1) end
                    SS.cfg.pcam = SS.cfg.pcam or {}
                    local labs2 = { "Split default|The split screen's own Distance / Height" }
                    for _, l in ipairs(labs) do labs2[#labs2 + 1] = l end
                    for pn = 2, 4 do
                        local cur = (tonumber(SS.cfg.pcam["p" .. pn]) or 0) + 1
                        local c2, v2 = choose("Player " .. pn .. "'s camera:", cur, labs2, "p" .. pn .. "cam", true, "      ")
                        if c2 then SS.cfg.pcam["p" .. pn] = v2 - 1; if SS.save then pcall(SS.save) end end
                    end
                end
                imgui.text_colored("      Auto: side by side / three across on a wide screen, stacked / a grid on a 16:9 one.", GREY)
                imgui.text_colored("   More split-screen options: \"DPC Split Screen\" in the REFramework menu.", GREY)
            elseif not (CD and CD.get) then
                imgui.text_colored("   Install Camera Distance for the shared co-op cameras.", GREY)
            end
        end
    end
    if not (SS and SS.cfg and SS.cfg.enabled) then
        pick_r("Co-op camera turning", "coop_cam_turn", { "shared", "p1", "auto" },
            { "Every player|Every player's right stick turns it (slow push turns, quick flick switches target)", "Player 1|Player 1's right stick turns it", "Automatic|It turns by itself; a slow push on a right stick still turns it" }, "camturn")
        if cfg.coop_cam_turn ~= "p1" then
            -- 0.9.172-dev36: which players' sticks turn it (all by default)
            cfg.coop_cam_from = cfg.coop_cam_from or {}
            local top = math.max(2, (R.np_count and R.np_count() or 0) + 2, 4)
            imgui.text("      Turns the camera:")
            for n = 1, top do
                imgui.same_line()
                local c, v = imgui.checkbox("P" .. n .. "##camfrom" .. n, cfg.coop_cam_from["p" .. n] ~= false)
                if c then
                    -- dev38: was "(not v) and false or nil", always nil in Lua, so a box never stayed unticked
                    if v then cfg.coop_cam_from["p" .. n] = nil else cfg.coop_cam_from["p" .. n] = false end
                    save_cfg()
                end
            end
        end
    end
    imgui.spacing()
    cb("Two controllers: player 1 plays on one too (a second controller joins by holding L3 + R3)", "coop_two_pads")
    cb("Any combination: each player can take any free character, the Arisen included", "coop_any")
    if cfg.coop_any then cb("   The Arisen cannot die while player 2 plays him", "coop_p2_arisen_no_death") end
    imgui.spacing()
    do -- the Arisen while you play a pawn: one choice for the two brain switches
        local cur = (cfg.arisen_brain and 1) or (cfg.arisen_brain_follow and 2) or 3
        local c, v = choose("The Arisen while you play a pawn", cur, { "Fights and follows|He fights on his own and follows you", "Follows only|He follows you and does not fight", "Stays put|He stays where he is" }, "arisenmode")
        if c then
            cfg.arisen_brain = (v == 1)
            cfg.arisen_brain_follow = (v ~= 3)
            cfg.arisen_auto_follow = cfg.arisen_brain_follow
            save_cfg()
        end
    end
    cb("The Arisen cannot die", "arisen_no_death")
    imgui.spacing()
    do -- switching characters: style + glow on one line each
        local cur = cfg.switch_cine and (cfg.switch_cine_profile or 2) or 1
        local c, v = choose("Switching characters (camera)", cur, { "Instant|A cut", "Establish|Pulls back, then in", "Bird's-eye|Up into the sky, then down", "Custom|Your own timing (Switching characters: speed and timing)" }, "switchcine")
        if c then cfg.switch_cine, cfg.switch_cine_profile = true, v; save_cfg() end
        local GLOWS = R.CINE_GLOWS
        local gcur = 1
        for i, g in ipairs(GLOWS) do if g[1] == (cfg.switch_glow or "") then gcur = i end end
        local labels = {}
        for i, g in ipairs(GLOWS) do labels[i] = g[2] end
        local c3, gv = imgui.combo("   Glow on who you take over", gcur, labels)
        if c3 then cfg.switch_glow = GLOWS[gv][1]; save_cfg() end
        local g = GLOWS[c3 and gv or gcur]
        if g and g[3] then imgui.same_line(); imgui.text_colored("||||||", g[3]); imgui.same_line(); imgui.text_colored("||||||", g[4]) end
    end
    if R.cr.want then
        imgui.text_colored("Co-op resumes when " .. tostring(R.cr.name or "the pawn") .. " is back (" .. tostring(R.cr.reason) .. ")", YELLOW)
        imgui.same_line()
        if imgui.button("Don't resume") then R.cr.want, R.cr.down = false, nil end
    end
    if R.cp and R.cp.on then
        local nm = R.cp.names or {}
        imgui.text(string.format("   Now: P1 %s, P2 %s%s", tostring(nm[1]), tostring(nm[2]), R.cp.kb and " (one controller)" or ""))
        if R.s2.active and (R.s2.failed or R.s2.in_err) then imgui.text_colored("   P2's pawn: " .. tostring(R.s2.err or R.s2.in_err), 0xFF5555FF) end
    end
    if cfg.coop_two_pads then
        local t = R.tp
        imgui.text(string.format("   %d controller(s) found. %s", t.n or 0,
            (t.p2 and not t.wait_release) and "Player 2's controller is set." or "Player 2: hold L3 + R3 on your controller (also starts co-op)."))
        if t.p2 and imgui.button("   Swap the two controllers") then R.tp_swap() end
        if t.p2 then imgui.same_line(); if imgui.button("Choose again") then R.tp_reset(); pcall(json.dump_file, "DPC_two_pads.json", {}) end end
    end
    if imgui.button("   Reset controllers (if a controller stops working)") then R.pad_reset() end

    imgui.spacing()
    if group("Co-op: player cards, aiming, glow, colours, rumble") then
        -- dev58 (the tester: "Anything truly shared-screen only should be in a section so that's clear. Things that could be
        -- used in both can be in both places and only apply for that camera"): three parts. Target markers are two
        -- switches: shared screen (on) and split screen (off).
        imgui.text_colored("Both kinds of co-op camera", BLUE)
        do -- the card needs both old switches on; one box for both here (the separate ones are under advanced)
            local on = cfg.coop_skill_palette ~= false and cfg.coop_player_card ~= false
            local c, v = imgui.checkbox("A card per player (name, health, stamina, skills, D-pad items)", on)
            if c then cfg.coop_skill_palette, cfg.coop_player_card = v, v; if v then cfg.coop_stamina_bar = true end; save_cfg() end
        end
        if cfg.coop_player_card ~= false then
            local c2, v2 = imgui.combo("      Card shows", cfg.card_palette or 4, { "Skills always", "Like the game, as a list", "Skills and actions", "Like the game, controller-shaped (fixed size)" })
            if c2 then cfg.card_palette = v2; save_cfg() end
            local c3, v3 = imgui.combo("      Health / stamina", cfg.card_bars or 5, { "In the card", "Over the character", "Under the character", "Card and over the character", "Card and under the character" })
            if c3 then cfg.card_bars = v3; save_cfg() end
            local c4, v4 = imgui.combo("      Item lines", cfg.card_items or 1, { "Always", "When the D-pad is used or an item runs low", "Never" })
            if c4 then cfg.card_items = v4; save_cfg() end
        end
        local c6, v6 = imgui.combo("   Co-op players' D-pad (no button held)", ((cfg.coop_dpad_orders or 2) == 2) and 2 or 1, { "Does nothing", "Orders the AI pawns (they answer aloud; Come calls them to the Arisen)" })
        if c6 then cfg.coop_dpad_orders = v6; save_cfg() end
        chg, cfg.coop_pad_names = imgui.combo("   Button names in the skill list", cfg.coop_pad_names or 1, { "Auto (from the controller)", "PlayStation", "Xbox" })
        if chg then save_cfg() end
        cb("Aiming for every player (R3 keeps a target, a quick right-stick flick moves to the next)", "coop_aim")
        if cfg.coop_aim then
            cb("   Player 1: R3 (middle mouse) keeps the enemy nearest the screen centre", "coop_aim_p1")
            if cfg.coop_aim_p1 then
                cb("      and the Arisen's attacks aim at it while he fights", "coop_aim_p1_assist")
                cb("      player 1's flicks move it too (two controllers)", "coop_aim_p1_flick")
            end
            local c3
            c3, cfg.coop_aim_size = imgui.slider_float("   Marker size", cfg.coop_aim_size or 1.0, 0.5, 2.0)
            if c3 then save_cfg() end
        end
        cb("A player's character glows in their colour when they join or change character", "coop_join_glow")

        imgui.spacing()
        imgui.text_colored("Shared screen only", BLUE)
        if cfg.coop_player_card ~= false then
            local c1, v1 = choose("   Cards", cfg.card_layout or 4,
                { "Own spot|Each player's own spot on the screen", "Row|In a row at the bottom middle", "Stack|Stacked at the bottom middle", "Side|Stacked at the side, off the characters" }, "cardshared")
            if c1 then cfg.card_layout = v1; save_cfg() end
            local m7 = tonumber(cfg.card_p1_mode) or 1
            if m7 == 1 and cfg.card_p1 then m7 = 2 end
            local c7, v7 = imgui.combo("   Player 1's HUD", m7, { "The game's own", "The game's own and a card", "A card only (the game's skills and gauges hidden)" })
            if c7 then cfg.card_p1_mode, cfg.card_p1 = v7, v7 >= 2; save_cfg() end
        end
        if cfg.coop_aim then cb("   Target markers on the enemies each player aims at", "coop_aim_markers") end
        if cfg.coop_join_glow ~= false then
            -- dev45 (the tester): "Make sub-ticks for each player glow under the all keep glowing, so they can do all glow or
            -- do them individually". Ticking the top one switches every player on again.
            local was = cfg.coop_glow_keep
            cb("   The glow stays on while they play (everyone)", "coop_glow_keep")
            if cfg.coop_glow_keep and not was then cfg.coop_glow_keep_p = {}; save_cfg() end
            if cfg.coop_glow_keep then
                cfg.coop_glow_keep_p = cfg.coop_glow_keep_p or {}
                local top = math.max(4, (R.np_count and R.np_count() or 0) + 2)
                imgui.text("      Keep glowing:")
                for n = 1, top do
                    imgui.same_line()
                    local c, v = imgui.checkbox("P" .. n .. "##glowkeep" .. n, cfg.coop_glow_keep_p["p" .. n] ~= false)
                    if c then
                        if v then cfg.coop_glow_keep_p["p" .. n] = nil else cfg.coop_glow_keep_p["p" .. n] = false end
                        save_cfg()
                    end
                end
            end
        end

        imgui.spacing()
        imgui.text_colored("Split screen only", BLUE)
        if cfg.coop_player_card ~= false then
            local c1, v1 = choose("   Cards (each in its player's own view)", cfg.card_layout_split or 1,
                { "At the side|At the side of each view, off the character", "Bottom middle|At the bottom middle of each view" }, "cardsplit")
            if c1 then cfg.card_layout_split = v1; save_cfg() end
            cb("   Player 1 keeps the game's own HUD (they have a view of their own)", "card_p1_split_native")
        end
        if cfg.coop_aim then cb("   Target markers (off: each player sees their own target in their view anyway)", "coop_aim_markers_split") end
        if cfg.coop_join_glow ~= false then cb("   The glow stays on while they play (off: only the short glow when someone joins)", "coop_glow_split") end
        imgui.spacing()
        imgui.text_colored("More", BLUE)
        -- 0.9.173-dev1: one colour per player for their target marker, glow and Camera Distance's off-screen marker
        if imgui.tree_node("Player colours (target marker, glow, off-screen marker)") then
            local names, pos_of = {}, {}
            for i, id in ipairs(R.COLOR_ORDER) do names[i] = R.ta_colors[id][1]; pos_of[id] = i end
            local top = math.max(4, (R.np_count and R.np_count() or 0) + 2)
            for n = 1, top do
                local c, v = imgui.combo("Player " .. n .. "##pcol" .. n, pos_of[R.player_color(n)] or 1, names)
                v = R.COLOR_ORDER[v]
                if c and v and R.ta_colors[v] then R.set_player_color(n, v); save_cfg(); coop.status_key = nil; coop.tgt_status_due = true end -- rewrite DPC_coop.json next frame (Camera Distance)
                imgui.same_line()
                if imgui.button("Preview##pcolprev" .. n) then pcall(R.color_preview, n) end
            end
            imgui.text_colored("Preview lights up that player's character (or yours) for 2.5 s.", GREY)
            imgui.tree_pop()
        end
        if cfg.coop_cam_turn == "p1" then cb("   Player 1's stick mode: the camera turns toward his target by itself", "coop_cam_p1_steer") end
        if cfg.coop_cam_turn == "auto" or (cfg.coop_cam_turn == "p1" and cfg.coop_cam_p1_steer) then
            imgui.text_colored("Camera turning by itself", GREY)
            sl("   Speed", "coop_cam_auto_speed", 0.1, 1.0)
            sl("   Starts when this far off (deg)", "coop_cam_deadband", 2.0, 30.0, "%.0f")
        end
        cb("Player 2's controller rumbles", "coop_p2_rumble")
        if cfg.coop_p2_rumble then
            imgui.text_colored("Rumble", GREY)
            sl("   Strength", "coop_p2_rumble_power", 0.1, 1.0)
            cb("   on player 2's hits (stronger for big hits and kills)", "coop_rb_dealt")
            cb("   when a skill starts", "coop_rb_skill")
            cb("   knocked down, out of stamina, healed / revived, blocked hits", "coop_rb_status")
            if imgui.button("   Test player 2 rumble") then
                if R.rb_dev() then R.rb_pulse(0.8, 0.5) else R.note = { text = "Two controllers: player 2 has no controller set yet", t_end = os.clock() + 3.0 } end
            end
            imgui.same_line()
            imgui.text(R.rb.shape and "works" or (R.rb.err and "failed" or "not tried yet"))
        end
        cb("Resume co-op by itself after cutscenes, loading or a downed pawn", "coop_auto_resume")
        cb("When co-op starts, bring player 2's pawn next to the Arisen (if it is far away)", "coop_start_bring")
        cb("The warp key (Numpad 7) also brings player 2's pawn", "coop_warp_p2")
        cb("The controller's motion sensor does not aim the Arisen", "coop_no_gyro")
        if package.loaded["PawnTacticalWheel.input"] then cb("Pawn Tactical Wheel (another mod) doesn't open from controllers in co-op (its keyboard key still works)", "coop_block_ptw") end
        imgui.tree_pop()
    end

    if group("Playing a pawn: looting, reviving, items, screen") then
        cb("Pick up, gather, loot and open chests as the pawn", "pawn_interact")
        if cfg.pawn_interact then cb("   what the pawn picks up goes into the Arisen's bag", "pawn_loot_to_arisen") end
        cb("Wake a sleeping companion (Interact next to them)", "pawn_wake")
        cb("Revive a downed pawn (hold Interact next to them)", "pawn_revive")
        if cfg.pawn_revive then sl("   seconds to hold (the game's own revive: 3.8)", "pawn_revive_hold", 0.0, 6.0, "%.1f") end
        cb("Quick-use recovery items go to the pawn you control", "pawn_quick_item")
        if cfg.pawn_quick_item then cb("   the quick-item cross shows that pawn's own items", "pawn_quick_item_labels") end
        cb("The skill list shows the played pawn's own special-arrow counts", "pawn_arrow_counts")
        cb("The lantern shortcut works the Arisen's lantern", "pawn_quick_lantern")
        if cb("The game's skill display shows the pawn's skills", "native_hud_skill_hook") and state.active then
            enqueue_game_thread("UI toggle native_hud_skill_hook", function() apply_native_hud_skills(cfg.native_hud_skill_hook) end)
        end
        cb("Red low-health screen edge follows the pawn you control", "possess_danger_pawn")
        cb("Show the Arisen's health and stamina while you play a pawn", "arisen_bars")
        if cfg.arisen_bars then cb("   over his head (off: at the bottom of the screen)", "arisen_bars_overhead") end
        cb("Warn when someone in the party is down (while you play a pawn or in co-op)", "down_alert")
        imgui.text_colored("Archer pawn", GREY)
        cb("Bow aim camera (zoom, body follows the camera)", "pawn_aim_camera")
        cb("Aim reticle", "pawn_aim_reticle")
        cb("Arrows go to the reticle", "pawn_aim_point")
        cb("Skills while aiming on a controller (aim button + skill buttons)", "pawn_aim_skills")
        cb("Skills from the hip keep their aim until they fire", "pawn_hip_skill_aim")
        imgui.tree_pop()
    end

    if group("The Arisen fighting on his own") then
        cb("Only while the party is in a fight (ignores wildlife)", "arisen_brain_battle_only")
        cb("Uses his weapon skills", "arisen_brain_skills")
        cb("Fights as Fighter, Thief, Warrior, Mystic Spearhand", "arisen_brain_melee")
        cb("Fights as Mage, Sorcerer", "arisen_brain_caster")
        cb("   speeds up spells with Quickspell (uses stamina)", "arisen_brain_quickspell")
        cb("   heals the party (the pawn you control first)", "arisen_brain_heal")
        cb("   tops everyone up after a fight", "arisen_brain_topup_on")
        cb("   cures debilitations when he has the spell", "arisen_brain_cure")
        cb("Fights as Magick Archer, Trickster, Warfarer (basic)", "arisen_brain_hybrid")
        cb("   Warfarer: swaps weapons during a fight (Rearmament must be in a skill slot)", "arisen_brain_rearm")
        if cfg.arisen_brain_rearm then sl("   seconds between weapon swaps", "arisen_brain_rearm_every", 5.0, 120.0, "%.0f") end
        cb("Magick Archer: his Remedy Arrow revives a downed pawn (assisted: the mod completes the revive)", "arisen_brain_ma_remedy_assist")
        cb("The warp key (Numpad 7) also brings the Arisen while you play a pawn", "party_warp_arisen")
        imgui.tree_pop()
    end

    if group("Switching characters: speed and timing") then
        sl("Game speed while switching (1 = normal)", "switch_cine_slowmo", 0.1, 1.0)
        if (cfg.switch_cine_slowmo or 1) < 0.99 then
            sl("   Full speed back before the camera lands (s)", "switch_cine_speed_back_s", 0.0, 2.0)
            sl("   ... easing up over (s)", "switch_cine_speed_ramp_s", 0.05, 1.5)
        end
        if (cfg.switch_glow or "") ~= "" then sl("Glow (s)", "switch_cine_glow_s", 0.2, 4.0) end
        if (cfg.switch_cine_profile or 2) == 4 then
            imgui.text_colored("Custom style", GREY)
            sl("   Look (s)", "switch_cine_look_s", 0.0, 1.5)
            sl("   Hold (s)", "switch_cine_hold_s", 0.0, 1.5)
            cb("   Pull back first so both are in view", "switch_cine_pull")
            if cfg.switch_cine_pull then
                sl("      Extra distance (m)", "switch_cine_pull_m", 0.0, 8.0)
                sl("      Height (m)", "switch_cine_rise_m", 0.0, 20.0)
            end
            sl("   Glide (s)", "switch_cine_glide_s", 0.1, 3.0)
        end
        imgui.tree_pop()
    end

    if group("Sound and feel") then
        pick_r("Loudness by distance from", "pf_sound_listener", { 1, 2, 0 }, { "Camera|The camera (recommended)", "Played pawn|The pawn you play", "Arisen|The Arisen (the game's own)" }, "listener")
        imgui.text_colored("   The game treats the Arisen as the player. These treat whoever you play as the player instead.", GREY)
        cb("The pawn you play sounds like the player (breathing, steps, voice)", "pf_sound_voice")
        cb("The place's echo and ambience follow the pawn you play", "pf_sound_space")
        cb("Co-op: the listener moves toward the players (a pulled-back camera does not cut sounds off)", "coop_listener_move")
        if cfg.coop_listener_move then cb("   loudness from the same point", "coop_listener_loudness") end
        cb("Skills' own slow motion (Riotous Fury, ...) for the pawn you play", "pf_skill_slow")
        imgui.tree_pop()
    end

    if group("Keys and controller buttons") then
        cb("Show the controls hint on screen (which button controls whom)", "hint_controls")
        if cfg.hint_controls then sl("   hint height on the screen", "hint_y", 0.05, 0.98, "%.3f") end
        local function row(label, kind, id, shown)
            imgui.text(string.format("%-34s %s", label, shown))
            imgui.same_line()
            if R.cap and R.cap.kind == kind and R.cap.id == id then
                imgui.text_colored(kind == "key" and "press a key (Esc cancels)" or "hold two or more buttons for a second (Esc cancels)", 0xFF30D0FF)
            elseif imgui.button("Change##" .. kind .. id) then
                R.cap, R.cap_msg = { kind = kind, id = id, t0 = os.clock() }, nil
            end
            -- 0.9.173: any key can be left unset (a player asked to free the numpad for other mods)
            if kind == "key" and (cfg.keys[id] or 0) ~= 0 then
                imgui.same_line()
                if imgui.button("Clear##k" .. id) then
                    cfg.keys[id], cfg.keys[id .. "_ctrl"] = 0, false
                    R.clash_logged, R.cap_msg = nil, label .. ": no key"
                    save_cfg()
                end
            end
        end
        cb("Keyboard shortcuts on (untick to use DPC from the controller only)", "hotkeys_on")
        imgui.text_colored("Keyboard (hold Ctrl while you press the new key to make it Ctrl + that key)", GREY)
        row("Take control / go back", "key", "toggle_possess", R.key_label("toggle_possess"))
        row("Select the next character", "key", "cycle_pawn", R.key_label("cycle_pawn"))
        row("Warp the Arisen to you", "key", "warp_arisen", R.key_label("warp_arisen"))
        row("Warp every pawn to you", "key", "party_warp", R.key_label("party_warp"))
        row("Heal / revive the party", "key", "party_heal", R.key_label("party_heal"))
        row("Start / stop couch co-op", "key", "coop", R.key_label("coop"))
        -- 0.9.172: straight to a character
        row("Go straight to: the Arisen", "key", "jump_arisen", R.key_label("jump_arisen"))
        local nshow = math.max(3, math.min(R.JUMP_MAX, #(R.jump_names or {})))
        for k = 1, nshow do
            local nm = R.jump_names and R.jump_names[k]
            row(string.format("Go straight to: pawn %d%s", k, nm and (" (" .. nm .. ")") or ""), "key", "jump_pawn" .. k, R.key_label("jump_pawn" .. k))
        end
        for n = 1, 6 do row("Order: skill slot " .. n, "key", "skill" .. n, R.key_label("skill" .. n)) end
        cb("   an ordered skill is kept until it is done (the pawn's own AI waits meanwhile)", "quick_skill_hold_ai")
        cb("   with no enemy about, an ordered attack skill is performed on the spot", "quick_skill_no_target")
        imgui.text_colored("Controller", GREY)
        cb("Hold D-pad left / right to select a character; hold down to go back to the Arisen", "pad_hold_select")
        cb("L1 + left stick click takes control of the selection (while playing a pawn: the next pawn)", "pad_l1_l3_possess")
        row("Take control / next character", "pad", "take", tostring(R.combo_name(R.take_mask()) or "?"))
        cb("   keep the Arisen out of that round (pawns only; go back with the line below)", "cycle_skip_arisen")
        row("Back to the Arisen", "pad", "back", (tonumber(cfg.pad.back) or 0) ~= 0 and tostring(R.combo_name(cfg.pad.back)) or "hold D-pad down")
        cb("   in co-op, player 2 changes pawn with that same combination (pawns only)", "coop_p2_switch")
        row("Start / stop couch co-op", "pad", "coop", (tonumber(cfg.pad.coop) or 0) ~= 0 and tostring(R.combo_name(cfg.pad.coop)) or "none")
        if R.cap_msg then imgui.text_colored("Last change: " .. R.cap_msg, GREY) end
        if imgui.button("Reset all controls to the defaults") then
            cfg.hotkeys_on = true
            for k in pairs(cfg.keys) do if tostring(k):sub(-5) == "_ctrl" then cfg.keys[k] = false end end
            for k, v in pairs(R.KEY_DEFAULTS) do cfg.keys[k] = v end
            cfg.pad.take, cfg.pad.back, cfg.pad.coop = 0, 0, 0
            R.clash_logged, R.cap_msg = nil, "defaults restored"
            save_cfg()
        end
        imgui.tree_pop()
    end

    if group("Cheats") then
        cb("Special arrows are not used up while you play a pawn", "cheat_free_arrows")
        if cfg.cheat_free_arrows then cb("   and a played Archer without them gets one of each (those weigh nothing)", "free_arrows_give") end
        cb("Numpad . heals and revives the party", "party_heal_key")
        if cfg.party_heal_key then cb("   ... and the Arisen", "party_heal_arisen") end
        imgui.tree_pop()
    end

    if group("Screen: card look, bar size, overlay positions") then
        if cfg.coop_player_card ~= false then
            sl("Card background", "card_bg_alpha", 0.1, 1.0)
            if (cfg.card_layout or 4) == 4 then -- dev49
                local c, v = imgui.combo("Cards at the side: which side", cfg.card_side or 1, { "Left", "Right" })
                if c then cfg.card_side = v; save_cfg() end
                sl("Cards at the side: distance from the edge", "card_side_x", 0.0, 0.4, "%.2f")
                sl("Cards at the side: height of the lowest card's bottom", "card_side_bottom", 0.3, 1.0, "%.2f")
            end
        end
        sl("Bars: thickness (px)", "coop_bars_thick", 1.0, 14.0, "%.0f")
        sl("Bars: opacity", "coop_bars_alpha", 0.15, 1.0)
        if imgui.button("Reset overlay positions") then R.hud_repos = 3 end
        imgui.tree_pop()
    end
    if group("Connected mods (" .. #R.api.regs .. ")##dpcapi") then -- v0.9.170 mod API
        R.api_draw()
        imgui.tree_pop()
    end
    imgui.separator()
    cb("Show advanced, test and legacy options", "show_legacy")
    if cfg.show_legacy then
    if imgui.tree_node("Advanced and legacy switches") then
        imgui.text_colored("Leave these alone unless you are chasing a problem.", GREY)
        -- dev47: the co-op HUD before the player cards (the card needs both "bars" and "skill list" on)
        imgui.text_colored("Old co-op HUD (before the player cards)", GREY)
        cb("Health and stamina bars for player 2", "coop_stamina_bar")
        cb("Skill list for player 2", "coop_skill_palette")
        cb("   One card per player (off: the old bars and list)", "coop_player_card")
        sl("Player 2's bars: left / right", "coop_stamina_hud_x", 0.05, 0.95)
        sl("Player 2's bars: up / down", "coop_stamina_hud_y", 0.05, 0.98)
        sl("Player 2's bars: width", "coop_stamina_width", 0.5, 2.0)
        sl("Player 2's skill list: left / right", "coop_palette_left", 0.0, 0.9)
        sl("Player 2's skill list: up / down (bottom edge)", "coop_palette_bottom", 0.1, 1.0)
        if cb("Native controls (the game's own player controls drive the pawn)", "native_controls") and state.active then
            enqueue_game_thread("UI toggle native_controls", function()
                if cfg.native_controls then native_build() else native_release() end
            end)
        end
        cb("Stop the pawn's current AI action when taking control", "possess_interrupt_ai")
        cb("F7 while playing a pawn switches pawn at once (old behaviour) instead of selecting", "cycle_switches_now")
        cb("Arisen brain: holds fire and flanks without line of sight", "arisen_brain_los")
        cb("Archer pawn: aim at what the reticle is on (ray cast)", "pawn_aim_ray")
        sl("Archer pawn: aim distance when nothing is hit (m)", "pawn_aim_point_dist", 5.0, 100.0, "%.0f")
        cb("Old skill palette outside co-op (debug)", "skill_hud_overlay")
        cb("Interact brings the Arisen to your pawn (also fires on dash)", "interact_bring")
        -- 0.9.172-dev21: moved here from the main page (rarely needed, troubleshooting or superseded)
        imgui.text_colored("Screen", GREY)
        cb("Status panel while playing a pawn (top left; detailed, for troubleshooting)", "hud_overlay")
        do
            local on = cfg.hud_safe_169 == true or (cfg.hud_safe_169 == "auto" and select(3, R.hud_rect()) < imgui.get_display_size().x)
            local c2, v = imgui.checkbox("Keep overlays inside the middle 16:9 (ultrawide recording)", on)
            if c2 then cfg.hud_safe_169 = v; R.hud_repos = 3; save_cfg() end
        end
        imgui.text_colored("Co-op", GREY)
        cb("A second controller starts co-op by holding L3 + R3 (either player ends it holding them 3 s)", "coop_pad_join")
        cb("The controller you use drives the Arisen (switches the game's active controller)", "pad_active_follow")
        do
            local okc, v = imgui.checkbox("Player 2 changes target only with a quick flick (off: any push past 70 %)", cfg.coop_aim_flick ~= "quick")
            if okc then cfg.coop_aim_flick = v and "deliberate" or "quick"; save_cfg() end
        end
        if cfg.coop_two_pads then
            local c1, v1 = imgui.combo("The Arisen's buttons (two controllers)", cfg.coop_two_pads_buttons or 1,
                { "Take out only player 2's (try first)", "Leave them to the game", "Player 1's controller only" })
            if c1 then cfg.coop_two_pads_buttons = v1; save_cfg() end
            local c2, v2 = imgui.combo("Camera while player 2 moves their right stick", cfg.coop_two_pads_cam or 1,
                { "Player 1's right stick", "Holds still" })
            if c2 then cfg.coop_two_pads_cam = v2; save_cfg() end
            if R.tp.err then imgui.text_colored("two controllers error: " .. tostring(R.tp.err), 0xFF5555FF) end
        end
        if R.rb.nodes_seen then imgui.text("player 2's action (rumble): " .. tostring(R.rb.nodes_seen):gsub("%%", "%%%%")) end
        if R.rb.err then imgui.text("rumble error: " .. tostring(R.rb.err):sub(1, 60):gsub("%%", "%%%%")) end
        imgui.text_colored("Playing as the player (experimental)", GREY)
        cb("Hit-stop (the short freeze on a hit) as if the pawn you play were the player", "pf_hitstop")
        cb("Big-kill slow motion as if the pawn you play were the player", "pf_world_slow")
        if not cfg.coop_listener_move and (cfg.pf_sound_listener or 0) == 1 then
            cb("Co-op: hear both players from an ear near them (superseded by the moving listener)", "pf_sound_coop_ear")
            if cfg.pf_sound_coop_ear then sl("   Ear distance from the players (m)", "pf_sound_ear_dist", 2.0, 15.0, "%.1f") end
        end
        do
            local L = R.lis
            if cfg.coop_listener_move then
                local st = L.found and ("moved by " .. L.found) or (L.failed and "no way found to move it") or (L.active and ("finding the way: trying " .. tostring(L.ways[L.way_i])) or "waiting for co-op")
                imgui.text("Listener: " .. st)
                if L.active and L.err then imgui.text(string.format("   camera %.0f m from the players; listener %.1f m from the camera, %.1f m off target", L.d or 0, L.from_cam or 0, L.err)) end
                if L.tried then imgui.text("   tried: " .. table.concat(L.tried, ", ")) end
                if L.err_msg or L.hook_err then imgui.text_colored("   listener error: " .. tostring(L.err_msg or L.hook_err), 0xFF5555FF) end
            end
            local parts = {}
            for k, n in pairs(R.pf.n) do parts[#parts + 1] = k .. " " .. n end
            table.sort(parts)
            if #parts > 0 then imgui.text("Ran: " .. table.concat(parts, ", ")) end
            if R.pf.voice_seen then imgui.text("Sound settings: " .. R.pf.voice_seen) end
            if R.pf.voice_err then imgui.text_colored("sound error: " .. R.pf.voice_err, 0xFF5555FF) end
            if R.pf.listener_err then imgui.text_colored("distance error: " .. R.pf.listener_err, 0xFF5555FF) end
        end
        imgui.tree_pop()
    end

    -- ===== 3. Test bench =====================================================================================
    if R.dev and imgui.tree_node("Test bench") then -- v0.9.114: developer mode only
        if imgui.button("Down the selected pawn (Ctrl+F10)") then R.down_pawn() end -- v0.9.121
        -- live readout
        if state.active then
            local ctl = "puppeteer (Mode 2)"
            if cfg.native_controls and native.pip and not native.failed then
                ctl = string.format("native, %d frames, %d errors", native.frames, native.errors)
            elseif cfg.native_controls and native.failed then
                ctl = "native FAILED -> puppeteer (see log)"
            end
            imgui.text(string.format("Pawn controls: %s", ctl))
        else
            imgui.text_colored("Pawn controls: not possessing", GREY)
        end
        local bcol = brain.on and GREEN or GREY
        imgui.text_colored(string.format("Arisen brain: %s%s", tostring(brain.mode), brain.solo and "  [SOLO]" or ""), bcol)
        if brain.on or brain.solo then
            imgui.text(string.format("  target %s  hp %s  %.1fm  off %.0f deg", tostring(brain.target_id),
                brain.target_hp and string.format("%.0f", brain.target_hp) or "-", brain.dist or 0, brain.off or 0))
            imgui.text(string.format("  shots %d  skills %d  injected %d  errors %d", brain.presses, brain.skill_uses, brain.inj, brain.errs))
            if brain.err then imgui.text_colored("  last error: " .. tostring(brain.err), RED) end
        end
        imgui.text(string.format("Test enemies: %d alive / %d spawned  (%d loading)", spawner.alive, spawner.spawned, #spawner.pending))

        -- spawn presets
        imgui.separator()
        imgui.text("Spawn (relative to the " .. (cfg.test_custom.around == "pawn" and "possessed pawn" or "Arisen") .. "):")
        for i, p in ipairs(TEST_PRESETS) do
            if (i - 1) % 4 ~= 0 then imgui.same_line() end
            local sel = (cfg.test_preset == i)
            if imgui.button((sel and "> " or "") .. p.label .. "##preset" .. i) then
                cfg.test_preset = i
                save_cfg()
                local spec = { enemy = p.enemy, count = p.count, dist = p.dist, angle = p.angle, still = p.still, around = cfg.test_custom.around }
                enqueue_game_thread("UI spawn " .. p.label, function() spawn_test(spec) end)
            end
        end
        if cfg.test_preset > 0 and TEST_PRESETS[cfg.test_preset] then
            imgui.text_colored("  F9 repeats: " .. TEST_PRESETS[cfg.test_preset].label .. "  (" .. TEST_PRESETS[cfg.test_preset].note .. ")", GREY)
        end
        if imgui.tree_node("Custom spawn") then
            local c = cfg.test_custom
            local ch1, ch2, ch3, ch4, ch5, ch6
            ch1, c.enemy = imgui.combo("Enemy", c.enemy, TEST_ENEMY_NAMES)
            ch2, c.count = imgui.slider_int("Count", c.count, 1, 8)
            ch3, c.dist = imgui.slider_float("Distance (m)", c.dist, 3.0, 40.0)
            ch4, c.angle = imgui.slider_int("Angle (deg, + = right)", c.angle, -180, 180)
            ch5, c.still = imgui.checkbox("Target dummy (stands still)", c.still)
            imgui.same_line()
            local around_pawn = c.around == "pawn"
            ch6, around_pawn = imgui.checkbox("Around the possessed pawn", around_pawn)
            c.around = around_pawn and "pawn" or "arisen"
            if ch1 or ch2 or ch3 or ch4 or ch5 or ch6 then save_cfg() end
            if imgui.button("Spawn custom [Ctrl+F9]") then
                cfg.test_preset = 0
                save_cfg()
                local spec = { enemy = c.enemy, count = c.count, dist = c.dist, angle = c.angle, still = c.still, around = c.around }
                enqueue_game_thread("UI spawn custom", function() spawn_test(spec) end)
            end
            imgui.tree_pop()
        end
        if imgui.button("Despawn test enemies [F10]") then enqueue_game_thread("UI despawn", despawn_tests) end
        imgui.same_line()
        if imgui.button("Mark this moment [Shift+F9]") then enqueue_game_thread("UI mark", function() test_mark("button") end) end

        -- test switches
        imgui.separator()
        chg, cfg.test_hotkeys = imgui.checkbox("Test hotkeys: F9 spawn, Ctrl+F9 custom spawn, Shift+F9 mark, F10 despawn, F11 brain on/off", cfg.test_hotkeys)
        if chg then save_cfg() end
        chg, brain.solo = imgui.checkbox("Brain drives the Arisen with nothing possessed (your input is ignored!)", brain.solo)
        chg, cfg.arisen_brain_telemetry = imgui.checkbox("Brain telemetry -> data/DPC_arisen_brain.json", cfg.arisen_brain_telemetry)
        if chg then save_cfg() end
        imgui.same_line()
        chg, cfg.debug_input = imgui.checkbox("Input log", cfg.debug_input)
        if chg then save_cfg() end
        imgui.tree_pop()
    end

    -- ===== 4. Pawn action buttons (possessed) ================================================================
    if state.active and imgui.tree_node("Pawn action buttons") then
        if imgui.button("Light attack") then enqueue_game_thread("UI Light Attack", function() pawn_do_attack(false, 0, 0, 0, 0) end) end
        imgui.same_line()
        if imgui.button("Heavy attack") then enqueue_game_thread("UI Heavy Attack", function() pawn_do_attack(true, 0, 0, 0, 0) end) end
        imgui.same_line()
        if state.pawn_job == 1 then
            if imgui.button(state.is_guarding and "Stop defend" or "Defend") then
                enqueue_game_thread("UI Toggle Guard", function() pawn_set_fighter_guard(not state.is_guarding, 0, 0, 0) end)
            end
            imgui.same_line()
        end
        if imgui.button("Jump") then enqueue_game_thread("UI Jump", function() pawn_do_jump(0, 0, 0, 0) end) end
        imgui.same_line()
        if imgui.button("Draw") then enqueue_game_thread("UI Draw", function() pawn_do_draw() end) end
        imgui.same_line()
        if imgui.button("Sheathe") then enqueue_game_thread("UI Sheathe", function() pawn_do_sheathe() end) end
        local cur_skills = state.pawn_skills or { 0, 0, 0, 0, 0, 0 }
        for s = 1, 6 do
            local slot_idx = s
            if s <= 4 or (cur_skills[s] or 0) ~= 0 then
                if s > 1 then imgui.same_line() end
                if imgui.button(string.format("[%d] %s##sk%d", s, skill_name(cur_skills[s]), s)) then
                    enqueue_game_thread("UI Skill " .. s, function() pawn_do_skill_slot(slot_idx, 0, 0, 0, 0) end)
                end
            end
        end
        imgui.tree_pop()
    end

    -- ===== 5. Tuning & experimental ==========================================================================
    if imgui.tree_node("Brain, co-op and control tuning") then
        imgui.text("Arisen brain")
        local c1, c2, c3, c4, c5, c6
        c1, cfg.arisen_brain_keep_min = imgui.slider_float("Back off inside (m)", cfg.arisen_brain_keep_min, 2.0, 15.0)
        c2, cfg.arisen_brain_keep_max = imgui.slider_float("Approach beyond (m)", cfg.arisen_brain_keep_max, 8.0, 35.0)
        c3, cfg.arisen_brain_shot_cd = imgui.slider_float("Seconds between shots", cfg.arisen_brain_shot_cd, 0.3, 3.0)
        c4, cfg.arisen_brain_skill_cd = imgui.slider_float("Seconds between skills", cfg.arisen_brain_skill_cd, 2.0, 30.0)
        c5, cfg.arisen_brain_skill_hold = imgui.slider_float("Skill button hold (s)", cfg.arisen_brain_skill_hold, 0.1, 2.0)
        c6, cfg.arisen_brain_face_tol = imgui.slider_float("Facing tolerance (deg)", cfg.arisen_brain_face_tol, 2.0, 30.0)
        local c7
        c7, cfg.arisen_brain_stuck_s = imgui.slider_float("Sidestep after no damage for (s, 0 = never)", cfg.arisen_brain_stuck_s, 0.0, 20.0)
        if c1 or c2 or c3 or c4 or c5 or c6 or c7 then save_cfg() end
        chg, cfg.arisen_own_lockon = imgui.checkbox("Give the Arisen his own lock-on while a pawn is played", cfg.arisen_own_lockon)
        if chg then save_cfg() end
        chg, cfg.arisen_brain_lock = imgui.checkbox("Lock his lock-on onto the brain's target (needed for hits and skills)", cfg.arisen_brain_lock)
        if chg then save_cfg() end
        chg, cfg.arisen_brain_keep_hud_redirect = imgui.checkbox("Keep HUD job/skill redirect while the brain runs (may break his archery)", cfg.arisen_brain_keep_hud_redirect)
        if chg then save_cfg() end
        chg, cfg.arisen_brain_any_job = imgui.checkbox("Ranged brain on every other vocation (untested)", cfg.arisen_brain_any_job)
        if chg then save_cfg() end

        imgui.separator()
        imgui.text("Couch co-op")
        chg, cfg.coop_zero_pad_for_arisen = imgui.checkbox("Arisen ignores the controller's buttons (processButton)", cfg.coop_zero_pad_for_arisen)
        if chg then save_cfg() end
        chg, cfg.coop_block_p2_stick = imgui.checkbox("Player 2's left stick doesn't move the Arisen", cfg.coop_block_p2_stick)
        if chg then save_cfg() end
        chg, cfg.coop_block_p2_camera = imgui.checkbox("Player 2's right stick doesn't turn the camera", cfg.coop_block_p2_camera)
        if chg then save_cfg() end
        local ch_b
        ch_b, cfg.coop_map_assign = imgui.checkbox("Player 2's buttons follow the game's controller settings", cfg.coop_map_assign)
        if ch_b then
            coop.map = nil
            save_cfg()
        end
        if coop.map_src then imgui.text("   in use: " .. tostring(coop.map_src)) end

        imgui.separator()
        imgui.text("Pawn controls")
        chg, cfg.native_skip_thief = imgui.checkbox("Thief pawns use the puppeteer instead of native controls", cfg.native_skip_thief)
        if chg then
            save_cfg()
            if state.active then
                enqueue_game_thread("UI toggle native_skip_thief", function()
                    if cfg.native_controls then native_build() else native_release() end
                end)
            end
        end
        chg, cfg.raw_mouse_fallback = imgui.checkbox("Raw LMB/RMB fallback (only if AttackS/AttackL are unbound)", cfg.raw_mouse_fallback)
        if chg then save_cfg() end
        for _, m in ipairs({ 2, 1, 3 }) do
            local active_m = (cfg.control_mode == m)
            local chg_m, new_val = imgui.checkbox(MODE_LABELS[m], active_m)
            if chg_m and new_val and not active_m then
                local target_m = m
                enqueue_game_thread("UI switch_control_mode", function() switch_control_mode(target_m) end)
            end
        end
        if imgui.tree_node("Subsystems") then
            chg, cfg.sub_camera_attach = imgui.checkbox("Attach camera to pawn", cfg.sub_camera_attach)
            if chg then save_cfg() end
            chg, cfg.sub_disable_arisen_pip = imgui.checkbox("Block Arisen input processor while possessing", cfg.sub_disable_arisen_pip)
            if chg then save_cfg() end
            chg, cfg.sub_suppress_ai = imgui.checkbox("Suppress pawn AI", cfg.sub_suppress_ai)
            if chg then save_cfg() end
            chg, cfg.sub_puppeteer_move = imgui.checkbox("Puppeteer movement", cfg.sub_puppeteer_move)
            if chg then save_cfg() end
            chg, cfg.sub_puppeteer_combat = imgui.checkbox("Puppeteer combat & skills", cfg.sub_puppeteer_combat)
            if chg then save_cfg() end
            chg, cfg.sub_mirror_input_flags = imgui.checkbox("Mirror buttons & stick to pawn input", cfg.sub_mirror_input_flags)
            if chg then save_cfg() end
            imgui.tree_pop()
        end
        if imgui.tree_node("Mode 1 / Mode 3 flags") then
            chg, cfg.exp_rebind_lockon = imgui.checkbox("Rebind LockOnCtrl.Chara to pawn", cfg.exp_rebind_lockon)
            if chg then save_cfg() end
            chg, cfg.exp_swap_inputs = imgui.checkbox("Swap CharacterInput between Arisen & pawn", cfg.exp_swap_inputs)
            if chg then save_cfg() end
            chg, cfg.swap_player_comp_refs = imgui.checkbox("Rebind app.Player.Chara/Human to pawn", cfg.swap_player_comp_refs)
            if chg then save_cfg() end
            chg, cfg.swap_manual_player = imgui.checkbox("CharacterManager:setManualPlayer(pawn)", cfg.swap_manual_player)
            if chg then save_cfg() end
            chg, cfg.set_human_is_arisen = imgui.checkbox("Pawn Human.IsArisen = true while possessed", cfg.set_human_is_arisen)
            if chg then save_cfg() end
            imgui.tree_pop()
        end
        imgui.tree_pop()
    end

    -- ===== 6. Diagnostics ====================================================================================
    if imgui.tree_node("Diagnostics & log") then
        imgui.text("Camera target: " .. tostring(ui_cache.cam_id))
        if state.active and state.pawn_chara then
            imgui.text(string.format("Frames possessed %d | Arisen processor blocked %d", state.frames_since_start, state.arisen_pip_blocked_count))
            imgui.text(string.format("On 0x%X | Trg 0x%X | weapon drawn %s", state.last_on_flags, state.last_trg_flags, tostring(ui_cache.weapon_drawn)))
            imgui.text(string.format("Stick %.2f | sprint %s | guard %s | last action %s",
                state.last_stick_mag, tostring(state.is_sprinting), tostring(state.is_guarding), state.last_action_str))
        end
        imgui.separator()
        for i = math.max(1, #logs - 15), #logs do imgui.text(logs[i]) end
        imgui.tree_pop()
    end
    end -- cfg.show_legacy

    imgui.end_window()
end)

re.on_frame(function()
    local now = os.clock()
    if coop.tgt_status_due then coop.tgt_status_due = false; coop_write_status() end
    if now < dev.next then return end
    dev.next = now + 1.0
    if (brain.errs or 0) > dev.seen_brain_errs then
        dev.errors = dev.errors + (brain.errs - dev.seen_brain_errs)
        dev.seen_brain_errs = brain.errs
        dev.last_error, dev.last_error_t = "brain: " .. tostring(brain.err), now
    end
    local info = (coop.active and "co-op" or (state.active and ("possessing " .. tostring(state.pawn_name)) or "idle"))
        .. " | brain " .. tostring(brain.mode)
        .. ((coop.active and cfg.coop_auto_target) and (" | p2 target " .. tostring(coop.tgt_name or "none") .. string.format(" (range %.0f m)", coop.tgt_range or 0)) or "")
        .. ((robot.pad or robot.arisen) and " | ROBOT" or "")
    R.dump("dev_status/DirectPawnControl.json", {
        mod = "DirectPawnControl", version = VERSION, t = now, errors = dev.errors,
        last_error = dev.last_error, last_error_t = dev.last_error_t, save_ok = dev.save_ok, info = info,
        aim = { hold = R.aim_hold == true, blocked = R.aim_blocked or 0, reqs = R.aim_reqs or 0, learned = R.aim_enter ~= nil, off = R.aim_off == true,
dash_label = { text = R.dash_n_text or 0, seen = R.dash_seen, repoints = R.hud_repoints or 0, slots = R.dash_slots, puts = R.dash_puts or 0 },
    flash = { skips = R.danger_skips or 0, flag_clears = R.danger_flag_clears or 0, flow_resets = R.danger_flow_resets or 0, hides = R.danger_hides or 0, unstuck = R.danger_unstuck or 0 },
            pt_x = R.aim_pt_x, pt_y = R.aim_pt_y, dp_x = R.aim_dp_x, dp_y = R.aim_dp_y, fixes = R.aim_fixes or 0, hip_aims = R.hip_aim_n or 0, ret_fail = R.aim_ret_fail == true, setting = R.aim_set, setups = R.aim_setups or 0, evals = R.aim_evals or 0, aim_skills = R.aim_skill_n or 0,
            dist = R.aim_last_d, ray_errs = R.aim_ray_errs or 0, ray_off = R.aim_ray_off == true },
        gyro = { blocked = R.gyro_blocked or 0, cleared = R.gyro_cleared or 0 },
        arrows = R.arrows and R.arrows.n or nil,
        stam_joint = R.stam_joint_name,
        galvanize = R.galv_last, stale_dash = R.stale_dash_n or 0, ferrystone = R.ferry and { n = R.ferry.n, live = R.ferry.live, hooks = R.ferry.hooks } or nil,
    })
end)

-- 0.9.177: the player cards and their world bars, after every other on_frame has asked for its cards
-- 0.9.178-dev14: a note meant for a game menu (R.note.menu) is drawn while the HUD is hidden for the menu too (the
-- normal note line above is skipped then; seen with "Player 1 controls the menus", dev13)
re.on_frame(function()
    local n = R.note
    if not (n and n.menu and os.clock() < (n.t_end or 0)) then return end
    if not R.hud_hidden() then return end -- shown by the normal note line
    pcall(function()
        local hx, hy, hw, hh = R.hud_rect()
        -- dev15 (the tester: "higher and a bit bigger"): its own larger font, near the top of the screen
        local px = math.floor(hh * (cfg.menu_note_size or 0.021) + 0.5)
        local now = os.clock()
        if px ~= R.mnote_px then
            R.mnote_px, R.mnote_font = px, nil
            pcall(function() R.mnote_font = imgui.load_font(nil, px) end)
            R.mnote_t = now
        end
        local pushed = false
        if R.mnote_font and now - (R.mnote_t or now) > 0.5 then pushed = pcall(imgui.push_font, R.mnote_font) end
        if not pushed then px = math.floor(hh * 0.010 + 0.5) end -- the small built-in font until the big one is ready
        local tw = #n.text * px * 0.5
        local okc, sz = pcall(imgui.calc_text_size, n.text)
        if okc and sz and sz.x and sz.x > 0 then tw = sz.x end
        local x, y = hx + hw * 0.5 - tw * 0.5, hy + hh * (cfg.menu_note_y or 0.10)
        draw.filled_rect(x - px * 0.7, y - px * 0.4, tw + px * 1.4, px * 1.8, 0xC0000000)
        draw.text(n.text, x, y, 0xFFFFFFFF)
        if pushed then pcall(imgui.pop_font) end
    end)
end)
re.on_frame(function() if R.cards_flush then local ok, e = pcall(R.cards_flush); if not ok then R.cards_err = tostring(e) end end end)

log_msg("DirectPawnControl v" .. VERSION .. " loaded (Default: Safe Mode 2). Press F6 to possess Main Pawn.")
coop_write_status() -- v0.9: CameraDistance polls this file; make sure it exists (inactive) from the start
