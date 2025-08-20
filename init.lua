local modname = minetest.get_current_modname()
local modpath = minetest.get_modpath(modname)
local worldpath = minetest.get_worldpath()

-- 権限登録（保存・配置用）
minetest.register_privilege("save_mts", {
    description = "Allows saving and placing .mts schematics",
    give_to_singleplayer = false,
})

-- マーカー定義（視覚フィードバック）
minetest.register_entity(modname .. ":marker", {
    initial_properties = {
        visual = "cube",
        textures = {"default_mese_block.png"},
        visual_size = {x=1, y=1},
        glow = 10,
        collide_with_objects = false,
        pointable = false,
    },
    on_activate = function(self)
        minetest.after(5, function()
            if self and self.object then
                self.object:remove()
            end
        end)
    end,
})

-- === プレビュー管理 ===
local preview_ps = {} -- name -> id

local function clear_preview(name)
    local id = preview_ps[name]
    if id then
        minetest.delete_particlespawner(id, name)
        preview_ps[name] = nil
    end
end

local function show_preview(name, p1, p2)
    clear_preview(name)
    local minp = vector.new(
        math.min(p1.x, p2.x),
        math.min(p1.y, p2.y),
        math.min(p1.z, p2.z)
    )
    local maxp = vector.new(
        math.max(p1.x, p2.x),
        math.max(p1.y, p2.y),
        math.max(p1.z, p2.z)
    )
    local id = minetest.add_particlespawner({
        amount = 400,
        time = 0,
        minpos = minp,
        maxpos = maxp,
        minvel = {x=0,y=0,z=0},
        maxvel = {x=0,y=0,z=0},
        minacc = {x=0,y=0,z=0},
        maxacc = {x=0,y=0,z=0},
        minsize = 0.25,
        maxsize = 0.5,
        glow = 5,
        texture = "basic_mts_saver_preview.png", -- 半透明白推奨
        playername = name,
        vertical = false,
        exptime = 1.2,
    })
    preview_ps[name] = id
end

-- 権限チェック関数（シングルプレイなら常にOK）
local function has_save_priv(name)
    return name == "singleplayer" or minetest.check_player_privs(name, {save_mts=true})
end

-- === 保存GUIコマンド ===
minetest.register_chatcommand("save_area_gui", {
    description = "Open GUI to save selected area as .mts",
    privs = {}, -- GUIは誰でも開けるが、操作は権限必須
    func = function(name)
        if not has_save_priv(name) then
            minetest.chat_send_player(name, "この操作には 'save_mts' 権限が必要です。")
            return true
        end

        local fs = [[
            size[6,5]
            field[0.4,0.6;1.5,1;x1;X1;0]
            field[2.0,0.6;1.5,1;y1;Y1;0]
            field[3.6,0.6;1.5,1;z1;Z1;0]
            field[0.4,2.0;1.5,1;x2;X2;10]
            field[2.0,2.0;1.5,1;y2;Y2;10]
            field[3.6,2.0;1.5,1;z2;Z2;10]
            field[0.4,3.4;4.7,1;filename;保存名;saved_map1]
            button[0.1,4.2;1.6,1;preview;プレビュー]
            button[1.9,4.2;1.6,1;preview_clear;解除]
            button[3.7,4.2;2,1;save_only;保存する]
        ]]
        minetest.show_formspec(name, modname .. ":save_form", fs)
        return true
    end,
})

-- 保存フォーム処理（プレビュー追加済み）
minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname ~= modname .. ":save_form" then return end
    local name = player:get_player_name()

    -- プレビュー
    if fields.preview then
        if not has_save_priv(name) then
            minetest.chat_send_player(name, "'save_mts' 権限が必要です。")
            return
        end
        local pos1 = {x=tonumber(fields.x1) or 0, y=tonumber(fields.y1) or 0, z=tonumber(fields.z1) or 0}
        local pos2 = {x=tonumber(fields.x2) or 10, y=tonumber(fields.y2) or 10, z=tonumber(fields.z2) or 10}
        show_preview(name, pos1, pos2)
        return
    end

    -- プレビュー解除
    if fields.preview_clear then
        clear_preview(name)
        return
    end

    -- 保存
    if fields.save_only then
        if not has_save_priv(name) then
            minetest.chat_send_player(name, "保存には 'save_mts' 権限が必要です。")
            return
        end

        local pos1 = {x=tonumber(fields.x1) or 0, y=tonumber(fields.y1) or 0, z=tonumber(fields.z1) or 0}
        local pos2 = {x=tonumber(fields.x2) or 10, y=tonumber(fields.y2) or 10, z=tonumber(fields.z2) or 10}
        local filename = fields.filename or "saved_map1"
        local fullpath = worldpath .. "/" .. filename .. ".mts"

        minetest.add_entity(pos1, modname .. ":marker")
        minetest.add_entity(pos2, modname .. ":marker")

        minetest.create_schematic(pos1, pos2, nil, fullpath)
        minetest.chat_send_player(name, "保存しました: " .. filename .. ".mts")

        -- ログ
        local log_file = worldpath .. "/save_log.txt"
        local log_entry = os.date("[%Y-%m-%d %H:%M:%S] ") ..
                          name .. " saved '" .. filename .. "' from " ..
                          minetest.pos_to_string(pos1) .. " to " ..
                          minetest.pos_to_string(pos2) .. "\n"
        local f = io.open(log_file, "a")
        if f then
            f:write(log_entry)
            f:close()
        end

        clear_preview(name)
        minetest.close_formspec(name, formname)
    end
end)

-- === 配置GUIコマンド ===
minetest.register_chatcommand("place_mts_gui", {
    description = "Open GUI to place a saved .mts file",
    privs = {},
    func = function(name)
        if not has_save_priv(name) then
            minetest.chat_send_player(name, "この操作には 'save_mts' 権限が必要です。")
            return true
        end

        local fs = [[
            size[6,2]
            field[0.3,0.8;5,1;filename;ファイル名;saved_map1]
            button[0.5,1.5;5,1;place_only;配置する]
        ]]
        minetest.show_formspec(name, modname .. ":place_form", fs)
        return true
    end,
})

-- 配置処理
minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname ~= modname .. ":place_form" or not fields.place_only then return end

    local name = player:get_player_name()
    if not has_save_priv(name) then
        minetest.chat_send_player(name, "配置には 'save_mts' 権限が必要です。")
        return
    end

    local filename = fields.filename or "saved_map1"
    local fullpath = worldpath .. "/" .. filename .. ".mts"

    local file = io.open(fullpath, "r")
    if not file then
        minetest.chat_send_player(name, "ファイルが見つかりません: " .. filename .. ".mts")
        return
    end
    file:close()

    local pos = vector.round(player:get_pos())
    minetest.place_schematic(pos, fullpath, nil, true)
    minetest.chat_send_player(name, "配置しました: " .. filename .. ".mts")

    minetest.close_formspec(name, formname)
end)

-- 後片付け
minetest.register_on_leaveplayer(function(player)
    clear_preview(player:get_player_name())
end)

minetest.register_on_shutdown(function()
    for name,_ in pairs(preview_ps) do
        clear_preview(name)
    end
end)
