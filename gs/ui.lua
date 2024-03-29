local account = require('account')
local bit = require('bit')
local client_data_items = require('client_data.items')
local clipboard = require('clipboard')
local equipment = require('equipment')
local event = require('core.event')
local ffi = require('ffi')
local file = require('file')
local fn = require('expression')
local items = require('items')
local list = require('list')
local math = require('math')
local player = require('player')
local resources = require('resources')
local string = require('string.ext')
local struct = require('struct')
local table = require('table.ext')
local ui = require('core.ui')
local unicode = require('core.unicode')
local windower = require('core.windower')

local tostring = tostring
local setmetatable = setmetatable

local ui_button = ui.button
local ui_display = ui.display
local ui_edit = ui.edit
local ui_location = ui.location
local ui_image = ui.image
local ui_size = ui.size
local ui_text = ui.text
local ui_window = ui.window

local gs

local parse_sets
local get_current_set
local copy
local generate_lines
local parse_set

local visible = false

local grid_type = struct.uint16[16]

local equipment_display
local set_display
local display_grid
do
    local math_floor = math.floor

    local grid_path = windower.package_path .. '\\equipment_grid.png'

    local grid = struct.new(grid_type)

    display_grid = function(x, y, grid)
        ui_location(x, y)
        ui_image(grid_path)

        for i = 0, 15 do
            ui_location(x + (i % 4) * 34, y + math_floor(i / 4) * 34)
            local id = grid[i]
            if id > 0 then
                ui_image(client_data_items[id].icon, { name = 'gs_item_' .. tostring(id) })
            end
        end
    end

    local slot_map = { [0] =
         0,  1,  2,  3,
         4,  9, 11, 12,
         5,  6, 13, 14,
        15, 10,  7,  8,
    }

    equipment_display = function(x, y)
        for i = 0, 15 do
            grid[i] = equipment[slot_map[i]].item.id
        end
        display_grid(x, y, grid)
    end

    local ids = setmetatable({}, {
        __index = function(t, k)
            local id = items:find_ids(k)[1]
            t[k] = id
            return id
        end,
    })

    set_display = function(x, y, set)
        for i = 0, 15 do
            local item = set[slot_map[i]]
            grid[i] = item ~= nil and ids[item.normalized] or 0
        end
        display_grid(x, y, grid)
        return y + 136
    end
end

local visible_sets = false
local visible_swaps = false

local current_player_info
local current_sets_path
local current_rules_path
do
    local window_state = {
        title = 'GearSwap',
        x = 300,
        y = 20,
        width = 290,
        height = 400,
        closable = true,
    }

    ui_display(function()
        if not visible then
            return
        end

        local window_closed
        window_state, window_closed = ui_window('gs_window', window_state, function()
            ui_location(10, 10)
            ui_text('[Character:]{16px}')
            ui_location(100, 10)
            ui_text(current_player_info)

            ui_location(10, 40)
            ui_text('Sets file:')
            ui_location(100, 40)
            ui_text(current_sets_path)

            ui_location(10, 60)
            ui_text('Rules file:')
            ui_location(100, 60)
            ui_text(current_rules_path)

            local width = window_state.width
            ui_location((width - 58.4) / 2, 90)
            ui_text('Equipment:')
            equipment_display((width - 134) / 2, 110)

            ui_location(10, 260)

            if ui_button('gs_main_window_sets_button', 'View and edit gear files') then
                visible_sets = true
            end

            if ui_button('gs_main_window_copy_button', 'Copy equipment to clipboard') then
                gs.copy()
            end

            if ui_button('gs_main_window_open_button', 'Open user folder') then
                gs.open()
            end

            if ui_button('gs_main_window_reload_button', 'Reload user files') then
                gs.reload()
            end

            if ui_button('gs_main_window_swaps_button', 'Show gear swaps') then
                visible_swaps = true
            end
        end)

        if window_closed then
            visible = false
        end
    end)
end

do
    local window_state = {
        x = 598,
        y = 20,
        width = 800,
        height = 932,
        closable = true,
    }

    local state = {}

    local visible_paths
    local changes
    local changes_count
    local new_texts
    local rename_texts
    local container_keys
    local modified_time
    local loaded_time

    local sets
    local sets_map
    local sets_path

    local user_path_prefix = windower.user_path .. '\\'

    local visible_explorer = true

    local top_menu_y = 10
    local content_y = top_menu_y + 50
    local editor_x = 180
    local explorer_x = 10

    local new_change = event.new()

    local copied

    local set_builder_event = event.new()
    local display_builder
    do
        local math_floor = math.floor

        local visible_builder = false
        local path
        local parent
        local key
        local build_set
        local item_name

        local builder_window_state = {
            x = 300,
            y = 20,
            width = 290,
            height = 620,
            closable = true,
        }

        set_builder_event:register(function(set_path, set_parent, set_key)
            path = set_path
            parent = set_parent
            key = set_key

            build_set = {}
            local set = sets_map[set_path]
            for i = 0, 15 do
                build_set[i] = set[i]
            end

            item_name = ''
            builder_window_state.title = 'GearSwap - Set Builder - ' .. set_path
            visible_builder = true
        end)

        local prefix_matches = setmetatable({}, {
            __index = function(t, k)
                local ids = items:search_prefix(k:normalize())
                local found = {}
                local value = list()
                for i = 1, #ids do
                    local item = client_data_items[ids[i]]
                    if item.flags.equippable then
                        local name = item.full_name
                        if found[name] == nil then
                            value:add(item)
                            found[name] = true
                            if #value == 10 then
                                break
                            end
                        end
                    end
                end
                t[k] = value
                return value
            end,
        })

        local slot_infos
        do
            local bit_band = bit.band
            local bit_lshift = bit.lshift

            local slot_names = { [0] =
                'Main',
                'Sub',
                'Range',
                'Ammo',
                'Head',
                'Body',
                'Hands',
                'Legs',
                'Feet',
                'Neck',
                'Waist',
                'L.Ear',
                'R.Ear',
                'L.Ring',
                'R.Ring',
                'Back',
            }

            slot_infos = setmetatable({}, {
                __index = function(t, k)
                    local res = {}
                    local res_count = 0
                    for i = 0, 15 do
                        local value = bit_lshift(1, i)
                        if bit_band(value, k) ~= 0 then
                            res_count = res_count + 1
                            res[res_count] = {
                                slot = i,
                                text = slot_names[i],
                            }
                        end
                    end

                    t[k] = res

                    return res
                end,
            })
        end

        display_builder = function()
            if not visible_builder then
                return
            end

            if sets_map[path] == nil then
                visible_builder = false
                return
            end

            local closed
            builder_window_state, closed = ui_window('gs_set_builder_window', builder_window_state, function()
                ui_location(10, 10)
                ui_text('Set: ' .. path .. ' (' .. sets_path .. ')')

                local width = builder_window_state.width

                ui_location(width - 90, 10)
                if ui_button('gs_set_builder_window_save_button', 'Save') then
                    new_change:trigger('set', {
                        parent = parent,
                        key = key,
                        path = path,
                        value = build_set,
                    })

                    visible_builder = false
                    return
                end

                local grid_x = (width - 136) / 2
                set_display(grid_x, 40, build_set)

                local post_grid_y = 196
                ui_location(10, post_grid_y)
                if ui_button('gs_set_builder_window_set_current_button', 'Set to current gear', { enabled = items.ready }) then
                    build_set = get_current_set()
                end

                ui_location(133, post_grid_y)
                if ui_button('gs_set_builder_window_clear_set_button', 'Clear set') then
                    build_set = {}
                end

                ui_location(10, post_grid_y + 32)
                ui_text('Search item:')

                ui_location(100, post_grid_y + 30)
                item_name = ui_edit('gs_set_builder_window_item_name_edit', item_name)

                local search_results_y = post_grid_y + 60
                if #item_name > 3 then
                    local matches = prefix_matches[item_name]
                    for i = 1, #matches do
                        local item = matches[i]

                        local row_y = search_results_y + (i - 1) * 36
                        ui_location(10, row_y)
                        ui_image(item.icon, { name = 'gs_item_' .. tostring(item.id) })

                        ui_location(50, row_y + 6)
                        ui_text(item.full_name)

                        local infos = slot_infos[item.equipment_slots]
                        for j = 1, #infos do
                            local info = infos[j]
                            ui_size(50, 21)
                            ui_location(width - 120 + (j - 1) * 60, row_y + 3)
                            if ui_button('gs_set_builder_window_match_equip_' .. tostring(i) .. '_' .. tostring(j), info.text) then
                                local full_name = item.full_name
                                build_set[info.slot] = {
                                    name = full_name,
                                    slot = info.slot,
                                    augments = nil, -- TODO
                                    normalized = full_name:normalize(),
                                }
                            end
                        end
                    end
                end
            end)

            if closed then
                visible_builder = false
            end
        end
    end

    local name_selector_event = event.new()
    local display_name_selector
    do
        local name_selector_window_state = {
            x = 1406,
            y = 20,
            width = 300,
            height = 932,
            closable = true,
        }

        local visible_name_selector = false

        local path
        local text_container
        local spells
        local job_abilities
        local weapon_skills
        do
            local make_category = function(label, identifier)
                local names = resources[identifier]:select(fn.index('name')):select(string.normalize):order_by(fn.id):to_list()
                local name_lookup = {}
                for _, action in pairs(resources[identifier]) do
                    name_lookup[action.name:normalize()] = action.name
                end

                local found
                do
                    local string_normalize = string.normalize
                    local string_sub = string.sub
                    local table_prefix_search = table.prefix_search

                    found = setmetatable({}, {
                        __index = function(t, k)
                            local name = string_normalize(k)
                            local prev = rawget(t, string_sub(name, 1, #name - 1))
                            local value = list(table_prefix_search(prev or names, name)):take(10):to_list()
                            t[k] = value
                            return value
                        end,
                    })
                end

                return {
                    identifier = identifier,
                    label = label,
                    name_lookup = name_lookup,
                    found = found,
                }
            end

            spells = make_category('Spells:', 'spells')
            job_abilities = make_category('Job abilities:', 'job_abilities')
            weapon_skills = make_category('Weapon skills', 'weapon_skills')
        end

        name_selector_event:register(function(selected_path, selected_text_container)
            path = selected_path
            text_container = selected_text_container

            spells.search = ''
            job_abilities.search = ''
            weapon_skills.search = ''

            name_selector_window_state.title = 'GearSwap - Name selector - ' .. selected_path
            visible_name_selector = true
        end)

        local categories = {
            'Magic',
            'JobAbility',
            'WeaponSkill',
            'RangedAttack',
            'Item',
            'PetAbility',
        }

        local y
        local button = function(entries, prefix, lookup)
            local length = #entries
            if length == 0 then
                ui_location(40, y)
                ui_text('No ' .. prefix .. ' found.')
                y = y + 30
                return
            end

            for i = 1, length do
                local normalized = entries[i]
                local name = lookup and lookup[normalized] or normalized
                ui_location(40, y)
                if ui_button('gs_name_selector_window_' .. prefix .. '_button_' .. normalized, name) then
                    text_container[path] = name
                    visible_name_selector = false
                end
                y = y + 30
            end
        end

        local search = function(category)
            ui_location(10, y)
            ui_text(category.label)

            local identifier = category.identifier

            y = y + 20
            ui_location(40, y)
            local new_search = ui_edit('gs_name_selector_window_' .. identifier .. '_search', category.search)
            category.search = new_search
            y = y + 30
            if #category.search > 0 then
                button(category.found[new_search], identifier, category.name_lookup)
            else
                y = y + 30
            end
        end

        display_name_selector = function()
            if not visible_name_selector then
                return
            end

            local closed
            name_selector_window_state, closed = ui_window('gs_name_selector_window', name_selector_window_state, function()
                y = 10
                ui_location(10, y)
                ui_text('Categories:')

                y = y + 20
                button(categories, 'categories')

                search(spells)
                search(job_abilities)
                search(weapon_skills)
            end)

            if closed then
                visible_name_selector = false
            end
        end
    end

    local build_container_keys
    do
        local table_sort = table.sort

        build_container_keys = function(container, path)
            local keys = {}
            local keys_count = 0
            local paths = {}
            for name in pairs(container) do
                keys_count = keys_count + 1
                keys[keys_count] = name
                paths[name] = path == '' and name or path .. '/' .. name
            end

            table_sort(keys, function(lhs, rhs)
                local lhs_container = sets_map[paths[lhs]] == nil
                local rhs_container = sets_map[paths[rhs]] == nil
                if lhs_container ~= rhs_container then
                    return lhs_container
                end
                return lhs < rhs
            end)

            return keys
        end
    end

    local ignore_time = false

    local load_file
    local select_file
    do
        local file_new = file.new

        local build_container_keys_full
        do
            build_container_keys_full = function(container, path)
                container_keys[path] = build_container_keys(container, path)

                for key, value in pairs(container) do
                    local child_path = path == '' and key or path .. '/' .. key
                    if not sets_map[child_path] then
                        build_container_keys_full(value, child_path)
                    end
                end
            end
        end

        local setup = function(sets_state)
            sets = sets_state.sets
            sets_map = sets_state.sets_map
            sets_path = sets_state.sets_path
            visible_paths = sets_state.visible_paths
            changes = sets_state.changes
            changes_count = sets_state.changes_count
            new_texts = sets_state.new_texts
            rename_texts = sets_state.rename_texts
            container_keys = sets_state.container_keys
            modified_time = sets_state.modified_time
            loaded_time = sets_state.loaded_time

            build_container_keys_full(sets, '')

            ignore_time = false
        end

        load_file = function(path)
            local sets_state = state[path]

            local sets_file = file_new(user_path_prefix .. path)
            sets_state.sets, sets_state.sets_map, sets_state.sets_path = parse_sets(sets_file)
            local sets_modified_time = sets_file:info().ftLastWriteTime.time
            sets_state.modified_time = sets_modified_time
            sets_state.loaded_time = sets_modified_time
            sets_state.visible_paths = {}
            sets_state.new_texts = {}
            sets_state.rename_texts = {}
            sets_state.container_keys = {}
            sets_state.changes = {}
            sets_state.changes_count = 0

            setup(sets_state)
        end

        select_file = function(path)
            local sets_state = state[path]

            if sets_state.sets == nil then
                load_file(path)
            else
                setup(sets_state)
            end
        end
    end

    local save_file
    do
        local file_new = file.new

        local format_key = function(key)
            return key:match('^%a%w*$') or '[\'' .. key:gsub('\'', '\\\'') .. '\']'
        end

        local generate_container
        do
            generate_container = function(container, path, path_sets_map, path_container_keys)
                local lines = list('{')
                for _, key in ipairs(path_container_keys[path]) do
                    local child_path = path == '' and key or path .. '/' .. key
                    local child_lines = path_sets_map[child_path] and generate_lines(container[key]) or generate_container(container[key], child_path, path_sets_map, path_container_keys)
                    child_lines[1] = format_key(key) .. ' = ' .. child_lines[1]
                    child_lines[#child_lines] = child_lines[#child_lines] .. ','
                    for _, line in pairs(child_lines) do
                        lines:add('    ' .. line)
                    end
                end
                lines:add('}')
                return lines
            end
        end

        save_file = function(sets_state)
            local path = sets_state.sets_path
            local sets_file = file_new(user_path_prefix .. path)
            sets_file:write('return ' .. ('\n'):join(generate_container(sets_state.sets, '', sets_state.sets_map, sets_state.container_keys)) .. '\n')
            local sets_modified_time = sets_file:info().ftLastWriteTime.time
            sets_state.modified_time = sets_modified_time
            sets_state.loaded_time = sets_modified_time

            local new_changes = {}
            sets_state.changes = new_changes
            sets_state.changes_count = 0
            if path == sets_path then
                changes = new_changes
                changes_count = 0
                modified_time = sets_modified_time
                loaded_time = sets_modified_time
            end

            ignore_time = false
        end
    end

    local files = {}
    local files_count = 0

    local display_top_menu
    do
        local check_dir_saving
        do
            local check_ignore_time = function()
                for i = 1, #files do
                    local path_state = state[files[i]]

                    local path_loaded_time = path_state.loaded_time
                    if path_loaded_time then
                        if #path_state.changes > 0 then
                            return true
                        end
                    end
                end

                return false
            end

            check_dir_saving = function()
                if ignore_time then
                    return check_ignore_time()
                end

                local any_changes = false

                for i = 1, #files do
                    local path_state = state[files[i]]

                    local path_loaded_time = path_state.loaded_time
                    if path_loaded_time then
                        if path_state.modified_time > path_loaded_time then
                            return false
                        end

                        if #path_state.changes > 0 then
                            any_changes = true
                        end
                    end
                end

                return any_changes
            end
        end

        display_top_menu = function()
            ui_location(explorer_x, top_menu_y)
            if ui_button('gs_sets_window_explorer_show_hide', visible_explorer and 'Hide explorer' or 'Show explorer') then
                visible_explorer = not visible_explorer
            end

            if sets == nil then
                return
            end

            local has_changes = #changes > 0

            ui_location(editor_x, top_menu_y)
            if ui_button('gs_sets_window_save_current', 'Save', { enabled = has_changes and (modified_time == loaded_time or ignore_time) }) then
                save_file(state[sets_path])
            end

            ui_location(editor_x + 80, top_menu_y)
            if ui_button('gs_sets_window_save_all', 'Save all', { enabled = check_dir_saving() }) then
                for i = 1, #files do
                    local sets_state = state[files[i]]
                    if #sets_state.changes > 0 then
                        save_file(sets_state)
                    end
                end
            end

            if modified_time == loaded_time then
                ui_location(editor_x + 160, top_menu_y)
                if ui_button('gs_sets_window_undo', 'Undo all', { enabled = has_changes }) then
                    load_file(sets_path)
                end
            else
                local caution = not has_changes or ignore_time

                ui_location(editor_x + 160, top_menu_y)
                if ui_button('gs_sets_window_reload', 'Reload', { enabled = caution }) then
                    load_file(sets_path)
                end

                if not has_changes then
                    ui_location(editor_x + 240, top_menu_y + 2)
                    ui_text('[Caution: File changed on disk! Reload recommended.]{orange}')
                else
                    local color = ignore_time and 'orange' or 'red'

                    ui_location(editor_x + 305, top_menu_y - 6)
                    ui_text('[Warning: File changed on disk!]{' .. color .. '}')

                    ui_location(editor_x + 245, top_menu_y + 10)
                    ui_text('[Save will overwrite the file, Reload will undo changes.]{' .. color .. '}')

                    if not ignore_time then
                        ui_location(editor_x + 535, top_menu_y)
                        if ui_button('gs_sets_window_top_ok', 'Ok') then
                            ignore_time = true
                        end
                    end
                end
            end
        end
    end

    local display_explorer
    do
        local file_new = file.new

        do
            local bit_band = bit.band
            local ffi_cast = ffi.cast
            local unicode_from_utf16 = unicode.from_utf16

            local parse_dir
            do
                local table_sort = table.sort

                parse_dir = function(file_path, key_path)
                    local dirs = {}
                    local dirs_count = 0

                    local entries = file_new(file_path):enumerate()
                    for i = 1, #entries do
                        local find_result = entries[i]
                        local name = unicode_from_utf16(ffi_cast('WCHAR*', find_result.cFileName))
                        local is_dir = bit_band(find_result.dwFileAttributes, 0x00000010) ~= 0

                        if is_dir then
                            dirs_count = dirs_count + 1
                            dirs[dirs_count] = {
                                file_path = file_path .. name .. '\\',
                                key_path = key_path == '' and name or key_path .. '/' .. name,
                            }
                        elseif name == 'sets.lua' then
                            local child_key_path = key_path == '' and name or key_path .. '/' .. name
                            if state[child_key_path] == nil then
                                state[child_key_path] = {
                                    visible_paths = {},
                                    changes = {},
                                    changes_count = 0,
                                    new_texts = {},
                                    rename_texts = {},
                                    container_keys = {},
                                }
                            end

                            local file_modified_time = find_result.ftLastWriteTime.time
                            state[child_key_path].modified_time = file_modified_time
                            if sets_path == child_key_path then
                                modified_time = file_modified_time
                            end

                            files_count = files_count + 1
                            files[files_count] = child_key_path
                        end
                    end

                    table_sort(dirs, function(lhs, rhs)
                        return lhs.key_path < rhs.key_path
                    end)

                    for i = 1, dirs_count do
                        local dir = dirs[i]
                        parse_dir(dir.file_path, dir.key_path)
                    end
                end
            end

            local coroutine_sleep = coroutine.sleep
            coroutine.schedule(function()
                while true do
                    files = {}
                    files_count = 0
                    parse_dir(user_path_prefix, '')
                    coroutine_sleep(1)
                end
            end)
        end

        local new_dir_name = ''
        local visible_new_set = false
        local invalid_message = nil

        local write_file = function(path)
            local new_file = file_new(user_path_prefix .. path .. '\\sets.lua')
            local success = pcall(function()
                if new_file:exists() then
                    invalid_message = 'File already exists'
                else
                    new_file:create_directories()
                    new_file:write('return {\n}\n')
                end
            end)

            if not success then
                invalid_message = 'Error trying to create file'
            end
        end

        display_explorer = function()
            if not visible_explorer then
                return
            end

            local y = content_y
            for i = 1, files_count do
                local path = files[i]
                local name = path

                local path_state = state[path]
                if path_state then
                    if #path_state.changes > 0 then
                        name = name .. ' *'
                    end

                    local path_loaded_time = path_state.loaded_time
                    if path_loaded_time and path_loaded_time < path_state.modified_time then
                        name = name .. ' !'
                    end
                end

                ui_location(explorer_x, y)
                if ui_button('gs_sets_window_explorer_file2_' .. path, name) then
                    select_file(path)
                end

                y = y + 30
            end

            if not visible_new_set then
                ui_location(explorer_x, y + 20)
                if ui_button('gs_sets_window_new_set_show', 'Add set file') then
                    visible_new_set = true
                end
            else
                ui_location(explorer_x, y + 25)
                ui_text('Enter folder for new file:')

                ui_location(explorer_x, y + 50)
                local old_name = new_dir_name
                new_dir_name = ui_edit('gs_sets_window_new_set_dir_name', new_dir_name)
                if new_dir_name ~= old_name then
                    invalid_message = nil
                end

                ui_location(explorer_x, y + 80)
                if ui_button('gs_sets_window_new_set_hide', 'Cancel') then
                    visible_new_set = false
                end

                ui_location(explorer_x + 86, y + 80)
                if ui_button('gs_sets_window_new_set_create', 'Create', { enabled = new_dir_name ~= '' and state[new_dir_name .. '/sets.lua'] == nil and state[new_dir_name .. 'sets.lua'] == nil}) then
                    write_file(new_dir_name)
                end

                if invalid_message ~= nil then
                    ui_location(explorer_x, y + 110)
                    ui_text('[' .. invalid_message .. ']{red}')
                end
            end
        end
    end

    local display_file
    do
        local math_floor = math.floor
        local math_max = math.max

        local slot_names = { [0] =
            'Main:',
            'Sub:',
            'Range:',
            'Ammo:',
            'Head:',
            'Body:',
            'Hands:',
            'Legs:',
            'Feet:',
            'Neck:',
            'Waist:',
            'L.Ear:',
            'R.Ear:',
            'L.Ring:',
            'R.Ring:',
            'Back:',
        }

        local display_set = function(set, x, y, path, parent, key)
            ui_location(x, y)
            if ui_button('gs_sets_window_set_current_' .. path, 'Set to current gear', { enabled = items.ready }) then
                new_change:trigger('set', {
                    parent = parent,
                    key = key,
                    path = path,
                    value = get_current_set(),
                })
            end

            ui_location(x + 123, y)
            if ui_button('gs_sets_window_clear_set_' .. path, 'Clear set') then
                new_change:trigger('clear', {
                    parent = parent,
                    key = key,
                    path = path,
                    value = {},
                })
            end

            ui_location(x + 203, y)
            if ui_button('gs_sets_window_builder_' .. path, 'Build set') then
                set_builder_event:trigger(path, parent, key)
            end

            ui_location(x + 283, y)
            if ui_button('gs_sets_window_copy_' .. path, 'Copy') then
                copy(set)
                copied = clipboard.get()
            end

            ui_location(x + 363, y)
            if ui_button('gs_sets_window_paste_' .. path, 'Paste', { enabled = copied ~= nil }) then
                new_change:trigger('set', {
                    parent = parent,
                    key = key,
                    path = path,
                    value = parse_set(loadstring('return ' .. copied)()),
                })
            end

            local end_y = set_display(x, y + 30, set)

            x = x + 150
            y = y + 30
            for i = 0, 15 do
                local diff_x = 200 * math_floor(i / 8)
                local diff_y = 17 * (i % 8)
                ui_location(x + diff_x, y + diff_y)
                ui_text(slot_names[i])
                ui_location(x + diff_x + 50, y + diff_y)
                local item = set[i]
                ui_text(item ~= nil and item.name or '-')
            end

            return end_y + 20
        end

        local display_container
        display_container = function(container, x, y, path)
            local path_str = 'sets' .. (path == '' and path or '/' .. path)
            ui_location(x, y)
            ui_text('[' .. path_str .. ']{Consolas #40C040}/')

            local path_x = x + 6.5 * #path_str
            ui_location(path_x + 10, y - 2)
            local new_text = ui_edit('gs_sets_window_new_edit_' .. path, new_texts[path] or '')
            new_texts[path] = new_text

            local enabled_create = new_text ~= '' and container[new_text] == nil

            ui_location(path_x + 176, y)
            if ui_button('gs_sets_window_new_set_button_' .. path, 'Create set', {enabled = enabled_create}) then
                new_texts[path] = nil
                local child_path = path == '' and new_text or path .. '/' .. new_text
                visible_paths[child_path] = true

                new_change:trigger('new set', {
                    parent = container,
                    key = new_text,
                    path = child_path,
                    value = {},
                })
            end

            ui_location(path_x + 256, y)
            if ui_button('gs_sets_window_new_table_button_' .. path, 'Create table', {enabled = enabled_create}) then
                new_texts[path] = nil
                local child_path = path == '' and new_text or path .. '/' .. new_text
                visible_paths[child_path] = true

                new_change:trigger('new container', {
                    parent = container,
                    key = new_text,
                    path = path,
                    value = {},
                })
            end

            ui_location(path_x + 344, y)
            if ui_button('gs_sets_window_new_select_name_button_' .. path, 'Select name') then
                name_selector_event:trigger(path, new_texts)
            end


            y = y + 30

            local keys = container_keys[path]

            for i = 1, #keys do
                local name = keys[i]
                local child_path = path == '' and name or path .. '/' .. name
                local is_set = sets_map[child_path] ~= nil

                ui_location(x, y)
                if ui_button('gs_sets_window_open_' .. child_path, name) then
                    visible_paths[child_path] = not visible_paths[child_path]
                end

                if visible_paths[child_path] then
                    local base_x = x + math_max(#name * 6 - 55, 0)
                    ui_location(base_x + 84, y + 2)
                    ui_text('Name:')

                    ui_location(base_x + 125, y)
                    local new_name = ui_edit('gs_sets_window_rename_edit_' .. child_path, rename_texts[child_path] or name)
                    rename_texts[child_path] = new_name

                    ui_location(base_x + 291, y)
                    if ui_button('gs_sets_window_rename_button_' .. child_path, 'Rename', { enabled = new_name ~= '' and container[new_name] == nil }) then
                        new_change:trigger('rename', {
                            parent = container,
                            old_key = name,
                            key = new_name,
                            old_path = child_path,
                            path = path == '' and new_name or path .. '/' .. new_name,
                        })
                    end

                    ui_location(base_x + 371, y)
                    if ui_button('gs_sets_window_remove_button_' .. child_path, 'Remove') then
                        new_change:trigger('remove', {
                            parent = container,
                            key = name,
                            path = child_path,
                            parent_path = path,
                        })
                    end

                    ui_location(base_x + 451, y)
                    if ui_button('gs_sets_window_select_name_button_' .. child_path, 'Select name') then
                        name_selector_event:trigger(child_path, rename_texts)
                    end
                end

                y = y + 30

                if visible_paths[child_path] then
                    local child = container[name]
                    local child_x = x + 40
                    if is_set then
                        y = display_set(child, child_x, y, child_path, container, name)
                    else
                        y = display_container(child, child_x, y, child_path)
                    end
                end
            end

            return y
        end

        display_file = function()
            if sets_path == nil then
                return
            end

            display_container(sets, visible_explorer and editor_x or explorer_x, content_y, '')
        end
    end

    local process_changes
    do
        local math_max = math.max
        local string_sub = string.sub

        local rename = function(old, new)
            local caches = {
                sets_map,
                visible_paths,
                container_keys,
                new_texts,
                rename_texts,
            }

            local old_search = old .. '/'
            local old_key_size = #old_search

            for i = 1, #caches do
                local cache = caches[i]

                local found = {}
                local found_count = 0
                for path in pairs(cache) do
                    if path == old or path:starts_with(old_search) then
                        found_count = found_count + 1
                        found[found_count] = path
                    end
                end

                for j = 1, found_count do
                    local old_key = found[j]
                    local new_key = new .. old_key:sub(old_key_size + 1)
                    cache[new_key] = cache[old_key]
                    cache[old_key] = nil
                end
            end
        end

        local change_fns = {
            ['new set'] = function(change)
                local parent = change.parent
                local path = change.path
                local key = change.key
                local value = change.value

                parent[key] = value
                sets_map[path] = value

                local parent_path = string_sub(path, 1, math_max(#path - #key - 1, 0))
                container_keys[parent_path] = build_container_keys(parent, parent_path)
            end,
            ['new container'] = function(change)
                local parent = change.parent
                local path = change.path
                local key = change.key

                parent[key] = change.value

                container_keys[path] = build_container_keys(parent, path)
                container_keys[path == '' and key or path .. '/' .. key] = {}
            end,
            ['remove'] = function(change)
                local parent = change.parent
                local path = change.path
                local key = change.key
                local parent_path = change.parent_path

                parent[key] = nil
                sets_map[path] = nil

                container_keys[parent_path] = build_container_keys(parent, parent_path)
            end,
            ['set'] = function(change)
                local parent = change.parent
                local path = change.path
                local value = change.value

                parent[change.key] = value
                sets_map[path] = value
            end,
            ['clear'] = function(change)
                local value = change.value

                change.parent[change.key] = value
                sets_map[change.path] = value
            end,
            ['rename'] = function(change)
                local parent = change.parent
                local old_path = change.old_path
                local path = change.path
                local old_key = change.old_key
                local key = change.key

                parent[key] = parent[old_key]
                parent[old_key] = nil

                rename(old_path, path)

                local parent_path = string_sub(path, 1, math_max(#path - #key - 1, 0))
                container_keys[parent_path] = build_container_keys(parent, parent_path)
            end,
        }

        local new_changes = {}
        local new_changes_count = 0

        new_change:register(function(type, change)
            change.type = type
            new_changes_count = new_changes_count + 1
            new_changes[new_changes_count] = change
        end)

        process_changes = function()
            for i = 1, new_changes_count do
                local change = new_changes[i]
                changes_count = changes_count + 1
                changes[changes_count] = change
                change_fns[change.type](change)
            end

            new_changes = {}
            new_changes_count = 0
        end
    end

    ui_display(function()
        if not visible_sets then
            return
        end

        window_state.title = 'GearSwap - Set manager - ' .. (sets_path and 'File: ' .. sets_path or 'No sets file selected')

        local closed
        window_state, closed = ui_window('gs_sets_window', window_state, function()
            display_top_menu()
            display_explorer()
            display_file()
        end)

        display_builder()
        display_name_selector()

        process_changes()

        if closed then
            visible_sets = false
        end
    end)
end

local handle_swap
do
    local window_state = {
        title = 'GearSwap - Swap history',
        x = 300,
        y = 447,
        width = 290,
        height = 505,
        closable = true,
    }

    local swaps_count = 3
    local swaps = struct.new(struct.struct({
        tag             = {struct.string(0x100)},
        grid            = {struct.uint16[16]},
        paths           = {struct.string(0x100)[8]},
        count           = {struct.int32},
    })[swaps_count])

    do
        local ffi_fill = ffi.fill
        local math_max = math.max
        local math_min = math.min

        local slot_map = { [0] =
             0,  1,  2,  3,
             4,  8,  9, 14,
            15,  5, 13,  6,
             7, 10, 11, 12,
        }

        handle_swap = function(tag, equipset, equipped_sets)
            for i = 0, swaps_count - 2 do
                swaps[i] = swaps[i + 1]
            end

            local swap = swaps[swaps_count - 1]
            swap.tag = tag
            local grid = swap.grid
            ffi_fill(grid, 32)
            for i = 1, #equipset do
                local set = equipset[i]
                grid[slot_map[set.slot_id]] = items.bags[set.bag_id][set.bag_index].id
            end

            local paths = swap.paths
            local paths_count = #equipped_sets
            swap.count = paths_count
            local offset = math_max(paths_count - 7, 1)
            for i = 0, math_min(paths_count - 1, 7) do
                local paths_index = i + offset
                paths[i] = tostring(paths_index) .. ': ' .. (equipped_sets[paths_index] or '-')
            end
        end
    end

    ui_display(function()
        if not visible_swaps then
            return
        end

        local window_closed
        window_state, window_closed = ui_window('gs_swaps_window', window_state, function()
            for i = 0, swaps_count - 1 do
                local swap = swaps[i]
                if swap.tag ~= '' then
                    local offset = i * 166
                    ui_location(10, 10 + offset)
                    ui_text(swap.tag)

                    local grid_y = 30 + offset
                    display_grid(10, grid_y, swap.grid)

                    local paths = swap.paths
                    for j = 0, swap.count - 1 do
                        ui_location(150, grid_y + j * 17)
                        ui_text(paths[j])
                    end
                end
            end
        end)

        if window_closed then
            visible_swaps = false
        end
    end)
end

local get_player_info = function()
    if not account.logged_in then
        return '-'
    end

    return player.name .. ' (' .. player.main_job.ens .. tostring(player.main_job_level) .. (player.sub_job_id ~= 0 and '/' .. player.sub_job.ens .. tostring(player.sub_job_level) or '') .. ')'
end

local reload = function(state)
    current_player_info = '[' .. get_player_info() .. ']{16px}'
    current_sets_path = (state.sets_path or '-')
    current_rules_path = (state.rules_path or '-')
end

return {
    show = function()
        visible = true
    end,
    hide = function()
        visible = false
    end,
    toggle = function()
        visible = not visible
    end,
    init = function(gs_env)
        gs = gs_env

        parse_sets = gs.parse_sets
        get_current_set = gs.get_current_set
        copy = gs.copy
        generate_lines = gs.generate_lines
        parse_set = gs.parse_set

        gs.reload_event:register(reload)

        gs.swap_event:register(handle_swap)
    end,
}

--[[
Copyright © 2020, Windower Dev Team
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of the Windower Dev Team nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE WINDOWER DEV TEAM BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]
