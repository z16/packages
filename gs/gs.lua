local account = require('account')
local action = require('action')
local bit = require('bit')
local client_data_items = require('client_data.items')
local clipboard = require('clipboard')
local command = require('core.command')
local equipment = require('equipment')
local event = require('core.event')
local file = require('file')
local fn = require('expression')
local items = require('items')
local list = require('list')
local os = require('os.ext')
local packet = require('packet')
local player = require('player')
local resources = require('resources')
local string = require('string.ext')
local table = require('table')
local unicode = require('core.unicode')
local win32 = require('win32')
local windower = require('core.windower')
local world = require('world')
local ui = require('ui')

local unicode_to_utf16 = unicode.to_utf16

local user_path = windower.user_path
do
    local create_dir = win32.def({
        name = 'CreateDirectoryW',
        returns = 'bool',
        parameters = {
            'wchar_t const*',
            'void*',
        },
        failure = false,
        ignore_codes = {183},
    })

    create_dir(unicode_to_utf16(user_path .. '\\..'), nil)
    create_dir(unicode_to_utf16(user_path), nil)
end

local gs = {}

local gsc = command.new('gs')

local state = {}
gs.state = state
local user

do
    local magic_category = action.category.magic
    local job_ability_category = action.category.job_ability
    local weapon_skill_category = action.category.weapon_skill
    local ranged_attack_category = action.category.ranged_attack
    local item_category = action.category.item
    local pet_ability_category = action.category.pet_ability
    local reset_category = 0x10
    local state_category = 0x11
    local zone_category = 0x12

    local prepare
    do
        local lookups = {
            skill = resources.skills,
            element = resources.elements,
        }

        prepare = function(base, category)
            local res = {}

            for k, v in pairs(base) do
                local lookup = lookups[k]
                res[k] = lookup and lookup[v] or v
            end

            res.category = category

            return res
        end
    end

    local resources_spells = resources.spells
    local resources_job_abilities = resources.job_abilities
    local resources_weapon_skills = resources.weapon_skills
    local resources_items = resources.items

    local parse_action = function(act)
        local category = type(act) == 'cdata' and act.category or act

        if category == magic_category then
            return prepare(resources_spells[act.id], 'Magic')
        end

        if category == job_ability_category then
            return prepare(resources_job_abilities[act.id], 'JobAbility')
        end

        if category == weapon_skill_category then
            return prepare(resources_weapon_skills[act.id], 'WeaponSkill')
        end

        if category == ranged_attack_category then
            return prepare({ }, 'RangedAttack')
        end

        if category == item_category then
            return prepare(resources_items[act.id], 'Item')
        end

        if category == reset_category then
            return prepare({ }, 'Reset')
        end

        if category == state_category then
            return prepare(player.state, 'State')
        end

        if category == zone_category then
            return prepare(world.zone, 'Zone')
        end

        error('Unknown action category: ' .. tostring(category))
    end

    local bags = resources.bags

    local swap_event = event.new()
    gs.swap_event = swap_event

    local trigger = function(tag, fn, act)
        if fn == nil then
            return
        end

        local current_set = {}
        state.current_set = current_set
        local equipped_sets = {}
        state.equipped_sets = equipped_sets
        local parsed = parse_action(act)
        fn(parsed)

        local count = 0
        local equipset = {}
        for slot = 0, 15 do
            local item = current_set[slot]
            if item ~= nil then
                local occurrences = items:search_inventories(item.normalized)
                local length = #occurrences
                if length ~= 0 then
                    for i = 1, length do
                        local occurrence = occurrences[i]
                        local bag_id = occurrence[1]
                        if bags[bag_id].equippable then
                            count = count + 1
                            equipset[count] = {
                                bag_index = occurrence[2],
                                slot_id = slot,
                                bag_id = bag_id,
                            }
                            break
                        end
                    end
                end
            end
        end

        if count ~= 0 then
            packet.outgoing[0x051]:inject({
                count = count,
                equipment = equipset,
            })
        end

        local name = parsed.name
        swap_event:trigger(name and tag .. name or tag, equipset, equipped_sets)

        state.current_set = nil
        state.equipped_sets = nil
    end

    action.pre_action:register(function(act)
        trigger('pre_action: ', user.pre_action, act)
    end)

    action.mid_action:register(function(act)
        trigger('mid_action: ', user.action, act)
    end)

    action.post_action:register(function(act)
        trigger('reset (post): ', user.reset, act)
    end)

    gsc:register('reset', function()
        trigger('reset (command)', user.reset, reset_category)
    end)

    player.state_change:register(function()
        trigger('reset (state): ', user.reset, state_category)
    end)

    world.zone_change:register(function()
        trigger('reset (zone): ', user.reset, zone_category)
    end)
end

local slot_name_id_map = {
    main = 0,
    sub = 1,
    range = 2,
    ammo = 3,
    head = 4,
    body = 5,
    hands = 6,
    legs = 7,
    feet = 8,
    neck = 9,
    waist = 10,
    ear1 = 11,
    ear2 = 12,
    ring1 = 13,
    ring2 = 14,
    back = 15,
}

local slot_id_name_map = {
    [0] = 'main',
    [1] = 'sub',
    [2] = 'range',
    [3] = 'ammo',
    [4] = 'head',
    [5] = 'body',
    [6] = 'hands',
    [7] = 'legs',
    [8] = 'feet',
    [9] = 'neck',
    [10] = 'waist',
    [11] = 'ear1',
    [12] = 'ear2',
    [13] = 'ring1',
    [14] = 'ring2',
    [15] = 'back',
}

local load
do
    local sets_map
    local paths_map

    local path_offset = #user_path + 2

    local load_sets
    do
        local bit_band = bit.band
        local string_normalize = string.normalize
        local table_concat = table.concat

        local determine_slot = function(item, key, used_slots, name)
            if type(key) == 'string' then
                local slot = slot_name_id_map[key]
                if slot == nil then
                    error('Unknown slot value: ' .. tostring(key))
                end
                return slot
            end

            if not item.flags.equippable then
                error('Item is not equippable: ' .. name)
            end

            local slots = item.equipment_slots
            local used_count = 0
            local used = {}
            for i = 0, 15 do
                if bit_band(2^i, slots) ~= 0 then
                    local used_slot = used_slots[i]
                    if not used_slot then
                        return i
                    else
                        used_count = used_count + 1
                        used[used_count] = used_slot
                    end
                end
            end

            if used_count > 0 then
                error('Too many items for slot: ' .. table_concat(used, ', '))
            end

            error('Unknown slots value: ' .. tostring(slots))
        end

        local parse_item = function(value, key, used_slots)
            local name_raw = type(value) == 'string' and value or value.name
            local name_normalized = string_normalize(name_raw)
            local ids = items:find_ids(name_normalized)
            if ids == nil then
                error('Unknown item: ' .. name_raw)
            end

            local item = client_data_items[ids[1]]
            local name = item.full_name

            return {
                name = name,
                slot = determine_slot(item, key, used_slots, name),
                augments = type(value) == 'table' and value.augments or nil,
                normalized = name_normalized,
            }
        end
        gs.parse_item = parse_item

        local parse_set = function(container)
            local res = {}

            local used_slots = {}
            for key, value in pairs(container) do
                local item = parse_item(value, key, used_slots)
                local slot = item.slot
                used_slots[slot] = item.name
                res[slot] = item
            end

            return res
        end
        gs.parse_set = parse_set

        local is_set = function(container)
            for key, value in pairs(container) do
                local value_type = type(value)
                if value_type == 'string' or value_type == 'table' and value.name ~= nil then
                    return true
                elseif value_type ~= 'table' then
                    error('Unknown definition for key \'' .. tostring(key) .. '\': ' .. tostring(value))
                end
            end

            return false
        end

        local parse_node
        local parse_container = function(container, path, sets)
            local res = {}

            for key, value in pairs(container) do
                res[key] = parse_node(value, path == '' and key or path .. '/' .. key, sets)
            end

            return res
        end

        parse_node = function(container, path, sets)
            if is_set(container) then
                local set = parse_set(container)
                sets[path] = set
                return set
            end

            return parse_container(container, path, sets)
        end

        local parse_sets = function(file)
            local sets = {}
            local sub_path = file.path:sub(path_offset)
            return parse_node(file:load(), '', sets), sets, sub_path
        end
        gs.parse_sets = parse_sets

        load_sets = function(sets_file)
            if sets_file == nil then
                user.sets = {}
                state.sets_map = {}
                state.sets_path = nil
                state.paths_map = {}
                return;
            end

            user.sets, sets_map, state.sets_path = parse_sets(sets_file)
            state.sets_map = sets_map

            paths_map = {}
            for path, set in pairs(state.sets_map) do
                paths_map[set] = path
            end
            state.paths_map = paths_map
        end
    end

    local load_rules = function(rules_file)
        if rules_file == nil then
            return;
        end

        local rules_path = rules_file.path:sub(path_offset)
        state.rules_path = rules_path
        rules_file:load_env(user)
    end

    local equip = function(set)
        if set == nil then
            return
        end

        if type(set) == 'string' then
            set = sets_map[set]
        end

        local current = state.current_set
        local equipped_sets = state.equipped_sets
        equipped_sets[#equipped_sets + 1] = paths_map[set]

        for slot, item in pairs(set) do -- TODO performance array?
            current[slot] = item
        end
    end

    load = function(sets_file, rules_file)
        user = {}
        state.user = user

        for k, v in pairs(_G) do
            user[k] = v
        end

        load_sets(sets_file)

        local root_sets = user.sets or {}
        local pre_sets = root_sets.pre or {}

        user.pre_action = function(act)
            equip(pre_sets[act.category])
            if act.skill then
                equip(pre_sets[act.skill.name])
            end
            equip(pre_sets[act.name])
        end

        user.action = function(act)
            equip(root_sets[act.category])
            if act.skill then
                equip(root_sets[act.skill.name])
            end
            equip(root_sets[act.name])
        end

        user.reset = function()
            equip(root_sets[player.state.name])
        end

        user.equip = equip

        load_rules(rules_file)
    end
end

local reload_event = event.new()
gs.reload_event = reload_event

local strip
do
    local naked_set = {}
    for i = 0, 15 do
        naked_set[i] = {
            bag_index = 0,
            slot_id = i,
            bag_id = 0,
        }
    end

    strip = function()
        packet.outgoing[0x051]:inject({
            count = 16,
            equipment = naked_set,
        })
    end
end
gs.strip = strip

gsc:register('strip', strip)

local reload
do
    local make_path = function(filename)
        return function(path)
            return user_path .. '\\' .. path .. '\\' .. filename .. '.lua'
        end
    end

    reload = function()
        if account.logged_in then
            local name = player.name:lower()
            local main = player.main_job.ens:lower()
            local sub = player.sub_job.ens:lower()
            local has_sub = player.sub_job_id ~= 0 or nil
            local filenames = list(
                has_sub and name .. '\\' .. main .. '\\' .. sub,
                name .. '\\' .. main,
                name,
                has_sub and main .. '\\' .. sub,
                main,
                ''):where(fn.exists)

            local sets_file = filenames:select(make_path('sets')):select(file.new):first(fn.method('exists'))
            local rules_file = filenames:select(make_path('rules')):select(file.new):first(fn.method('exists'))
            load(sets_file, rules_file)
        else
            load(nil, nil)
        end

        reload_event:trigger(state)
    end
end
gs.reload = reload

local open
do
    local os_open = os.open

    local user_path_w = unicode_to_utf16(user_path)

    open = function()
        os_open(user_path_w)
    end
end
gs.open = open

gsc:register('open', open)

local get_current_set = function()
    if not account.logged_in then
        return {}
    end

    local res = {}
    for slot, equip in pairs(equipment) do
        local item = equip.item
        local id = item.id
        if id > 0 then
            local resource = client_data_items[id]
            local full_name = resource.full_name
            res[slot] = {
                name = full_name,
                slot = slot,
                augments = nil, -- TODO parse augments
                normalized = full_name:normalize(),
            }
        end
    end

    return res
end
gs.get_current_set = get_current_set

local generate
local generate_lines
do
    local generate_augment_string = function(augments)
        --TODO
        if augments == nil then
            return ''
        end

        error('nyi')
    end

    generate_lines = function(set)
        set = set or get_current_set()

        local lines = list('{')
        for slot, item in pairs(set) do
            local prefix = '    ' .. slot_id_name_map[slot] .. ' = '
            local item_string = '\'' .. item.name:gsub('\'', '\\\'') .. '\''
            if item.augments ~= nil then
                lines:add(prefix .. '{ name = ' .. item_string .. ', augments = ' .. generate_augment_string(item.augments) .. ' },')
            else
                lines:add(prefix .. item_string .. ',')
            end
        end
        lines:add('}')

        return lines
    end

    generate = function(set)
        return ('\n'):join(generate_lines(set))
    end
end
gs.generate_lines = generate_lines
gs.generate = generate

local copy = function(set)
    clipboard.set(generate(set))
end
gs.copy = copy

gsc:register('copy', function()
    local ok, err = pcall(copy)
    if not ok then
        print('Error: ' .. err)
    end
end)

gsc:register('new', function(name, main, sub)
    if (not name or not main) and not account.logged_in then
        print('Not logged in.')
        return
    end

    local base_filename = (name or player.name) .. '_' .. (main or player.main_job.ens):lower()
    local filename = sub and (base_filename .. '_' .. sub) or base_filename
    local user_file = file.new(windower.user_path .. '\\' .. filename .. '.lua')
    if user_file:exists() then
        print('File already exists.')
        return
    end

    local template = file.new(windower.package_path .. '\\file_template.lua')
    user_file:write(template:read())
end, '[player:string(%a+)] [main:string(%a%a%a)] [sub:string(%a%a%a)]')

gsc:register('menu', function(option)
    if option == 'show' then
        ui.show()
    elseif option == 'hide' then
        ui.hide()
    elseif option == 'toggle' then
        ui.toggle()
    end
end, '[option:one_of(show,hide,toggle)=toggle]')

account.login:register(reload)
account.logout:register(reload)
player.job_change:register(reload)

ui.init(gs)

reload()

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
