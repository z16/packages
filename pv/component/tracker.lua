local bit = require('bit')
local entities = require('entities')
local list = require('list')
local math = require('math')
local os = require('os')
local packets = require('packets')
local resources = require('resources')
local set = require('set')
local settings = require('settings')
local shared = require('shared')
local string = require('string')
local table = require('table')
local ui = require('ui')

local state = require('pv.state')
local pv = require('pv.pv')

local client = shared.get('packet_service', 'types')

local ftypes = {
    incoming = {},
    outgoing = {},
}

for i = 0, 0x1FF do
    ftypes.incoming[i] = client:read('incoming', i)
    ftypes.outgoing[i] = client:read('outgoing', i)
end

local display
do
    local defaults = {
        visible = false,
        x = 370,
        y = 0,
        width = 480,
        height = 460,
        incoming = {
            pattern = '',
            exclude = false,
        },
        outgoing = {
            pattern = '',
            exclude = false,
        },
        active = false,
    }

    display = settings.load(defaults, 'tracker', true)
end

local data = {
    incoming = {
        packets = list(),
        exclude = false,
    },
    outgoing = {
        packets = list(),
        exclude = false,
    },
}

local tracked = list()

local process_pattern = pv.process_pattern
local handle_base_command = pv.handle_base_command
local check_filters = pv.check_filters
local save = settings.save
local init = state.init
local watch = state.watch

local display_incoming = display.incoming
local display_outgoing = display.outgoing
local data_incoming = data.incoming
local data_outgoing = data.outgoing

local hex_zero = pv.hex.zero
local hex_zero_3 = pv.hex.zero_3
local hex_space = pv.hex.space
local hex_raw = pv.hex.raw

-- Public operations

local tracker = {}

tracker.name = 'track'

tracker.valid = function()
    return display_incoming.pattern ~= '' or display_incoming.exclude or display_outgoing.pattern ~= '' or display_outgoing.exclude
end

tracker.running = function()
    return display.active
end

tracker.visible = function()
    return display.visible
end

tracker.show = function(value)
    display.visible = value

    save(display)
end

tracker.start = function()
    data_incoming.packets = process_pattern(display_incoming.pattern)
    data_outgoing.packets = process_pattern(display_outgoing.pattern)
    data_incoming.exclude = display_incoming.exclude
    data_outgoing.exclude = display_outgoing.exclude

    display.active = true
    display.visible = true

    save(display)
end

tracker.stop = function()
    data_incoming.packets = list()
    data_outgoing.packets = list()
    data_incoming.exclude = false
    data_outgoing.exclude = false

    display.active = false

    save(display)
end

-- Packet handling

packets:register(function(packet, info)
    if not check_filters(tracker, data, packet, info) then
        return
    end

    tracked:add({
        packet = packet,
        info = info,
    })
end)

-- Command handling

local track_command = function(direction, ...)
    handle_base_command(tracker, display, direction, ...)
end

pv.command:register('track', track_command, '<direction:one_of(i,ni,o,no,b,nb,s)> [ids:number(0x001,0x1FF)]*')

-- Initialization

data_incoming.packets = process_pattern(display_incoming.pattern)
data_outgoing.packets = process_pattern(display_outgoing.pattern)
data_incoming.exclude = display_incoming.exclude
data_outgoing.exclude = display_outgoing.exclude

-- UI

local colors = {}
do
    local math_sqrt = math.sqrt
    local math_pi = math.pi
    local ui_color_rgb = ui.color.rgb
    local ui_color_tohex = ui.color.tohex

    local lut = {
        { 51,153,255},
        { 51,255,153},
        {153, 51,255},
        {255, 51,153},
        {153,255, 51},
        {255,153, 51},
        {255,255,102},
        {255,102,255},
        {102,255,255},
        {102,102,255},
        {102,255,102},
        {255,102,102},
        {255,204,153},
        {204,255,153},
        {255,153,204},
        {153,204,255},
        {204,153,255},
        {153,255,204},
    }

    lut[0] = {204,204,0}

    for i = 1, 0x400 do
        local lu = lut[(i - 1) % 19]
        local color = ui_color_rgb(lu[1], lu[2], lu[3])
        colors[i] = ui_color_tohex(color)
    end
end

local build_packet_fields
do
    local table_concat = table.concat
    local string_byte = string.byte
    local string_format = string.format
    local string_rep = string.rep
    local math_floor = math.floor

    local data_formats = {}
    local data_lengths = {}

    for value_length = 1, 20 do
        data_formats[value_length] = string_rep('%02X ', value_length)
    end

    for label_length = 1, 60 do
        data_lengths[label_length] = math_floor((64 - label_length - 1) / 3)
    end

    local append = function(value, lookup)
        return tostring(value) .. ' (' .. tostring(lookup or '?') .. ')'
    end

    build_packet_fields = function(packet, ftype, color_table)
        local arranged = ftype.arranged
        local fields = ftype.fields
        local lines = {}
        local lines_count = 0
        for i = 1, #arranged do
            local field = arranged[i]
            local label = field.label
            lines_count = lines_count + 1

            local value = packet[field.label]

            local tag = field.type.tag
            if tag == 'data' then
                local data_length = #value
                local max_length = data_lengths[#label]
                local format = data_length > max_length and data_formats[max_length] .. '…' or data_formats[data_length]

                value = string_format(format, string_byte(value, 1, max_length))
            elseif tag == 'entity' then
                local entity = entities:by_id(value)
                value = append(value, entity and entity.name)
            elseif tag == 'entity_index' then
                local entity = entities[value]
                value = append(value, entity and entity.name)
            elseif tag then
                local resource_table = resources[tag]
                if resource_table then
                    local resource = resource_table[value]
                    value = append(value, resource and resource.name)
                end
            end

            lines[lines_count] = hex_space[fields[label].position] .. ' [' .. label .. ': ' .. tostring(value) .. ']{' .. colors[i] .. '}'
        end

        return table_concat(lines, '\n')
    end
end

local build_packet_table
do
    local table_concat = table.concat
    local string_byte = string.byte
    local string_char = string.char
    local math_floor = math.floor
    local band = bit.band
    local bnot = bit.bnot

    local lookup_byte = {}
    for i = 0x20, 0x7E do
        lookup_byte[i] = string_char(i)
    end
    local escape = {
        '\\',
        '[',
        ']',
        '{',
        '}',
    }
    for i = 1, #escape do
        local char = escape[i]
        lookup_byte[string_byte(char)] = '\\' .. char
    end

    build_packet_table = function(data, ftype, color_table)
        local address = 0
        local base_offset = 0
        local end_data = #data
        local end_char = band(end_data + 0xF, bnot(0xF))

        local lookup_hex = {}
        local lookup_char = {}
        for i = end_data, end_char - 1 do
            lookup_hex[i] = '--'
            lookup_char[i] = '-'
            color_table[i] = '#606060'
        end
        for i = base_offset, end_data - 1 do
            local byte = string_byte(data, i - base_offset + 1)
            lookup_hex[i] = hex_zero[byte]
            lookup_char[i] = lookup_byte[byte] or '.'
        end

        local lines = {}
        lines[1] = '  |  0  1  2  3  4  5  6  7  8  9  A  B  C  D  E  F | 0123456789ABCDEF'
        lines[2] = '----------------------------------------------------------------------'
        for row = 0, end_char / 0x10 - 1 do
            local index_offset = 0x10 * row
            local prefix = hex_raw[math_floor((address - base_offset + index_offset) / 0x10)] .. ' | '
            local hex_table = {}
            local char_table = {}
            for i = 0, 0xF do
                local pos = index_offset + i
                local color = color_table[pos] or '#A0A0A0'
                local hex = lookup_hex[pos]
                local char = lookup_char[pos]
                local suffix = ']{' .. color ..'}'
                hex_table[i + 1] = '[' .. hex .. suffix
                char_table[i + 1] = '[' .. char .. suffix
            end

            lines[row + 3] = prefix .. table_concat(hex_table, ' ') .. ' | ' .. table_concat(char_table)
        end

        return table_concat(lines, '\n')
    end
end

local build_color_table
do
    local math_floor = math.floor

    local color_table_cache = {}

    local make_table
    make_table = function(info, ftype, color_table)
        color_table = color_table or {}

        local color_table_count = #color_table
        local arranged = ftype.arranged
        local arranged_count = #arranged
        for i = 1, arranged_count do
            local field = arranged[i]
            local position = field.position
            local type = field.type

            local size = type.size
            local var_size = type.var_size
            local bits = type.bits

            local from, to
            if bits then
                from = position
                to = position + math_floor((field.offset + bits) / 8)
            elseif size == '*' then
                from = position
                to = #info.data - 1
            else
                from = position
                to = position + size - 1
            end

            for index = from, to do
                if not color_table[index] then
                    color_table[index] = colors[color_table_count + i]
                end
            end
        end

        return color_table
    end

    build_color_table = function(info, ftype)
        if not ftype then
            return {}
        end

        local color_table = color_table_cache[ftype]
        if not color_table then
            color_table = make_table(info, ftype)
            color_table_cache[ftype] = color_table
        end

        --TODO ftype.var_size
        return color_table
    end
end

local build_packet_extras
do
    local table_concat = table.concat
    local table_sort = table.sort

    local build_extra_lines
    build_extra_lines = function(t, indent)
        indent = indent or ''

        local lines = {}
        local line_count = 0

        for key in pairs(t) do
            line_count = line_count + 1
            lines[line_count] = key
        end

        table_sort(lines)
        for i = 1, line_count do
            local key = lines[i]
            local value = t[key]
            lines[i] = indent .. '[' .. tostring(key) .. ']{skyblue}: ' .. (type(value) == 'table'
                and '\n' .. build_extra_lines(value, indent .. '    ')
                or '[' .. tostring(value) .. ']{pink}')
        end

        return table_concat(lines, '\n')
    end

    build_packet_extras = function(packet, ftype)
        local arranged = ftype.arranged
        local arranged_count = #arranged
        local arranged_labels = set()
        for i = 1, arranged_count do
            arranged_labels:add(arranged[i].label)
        end

        local subset = {}

        for key, value in pairs(packet) do
            if not arranged_labels:contains(key) then
                subset[key] = value
            end
        end

        return next(subset) and build_extra_lines(subset)
    end
end

local display_packet
do
    local noref = {
        __mode = 'k',
    }

    local packet_display_cache = setmetatable({}, noref)

    display_packet = function(packet, info)
        local cached = packet_display_cache[p]
        if not cached then
            local data = info.data

            local ftype = ftypes[info.direction][info.id]
            local types = ftype and ftype.types
            if types then
                ftype = types[packet[ftype.key]]
            end

            local color_table = build_color_table(info, ftype)

            local table = build_packet_table(data, ftype, color_table)
            local fields = ftype and build_packet_fields(packet, ftype, color_table)

            local extras = ftype and build_packet_extras(packet, ftype)

            cached = '[' .. table .. (fields and '\n\n' .. fields or '') .. (extras and '\n\nDerived fields:\n\n' .. extras or '') .. ']{Consolas 12px}'
            packet_display_cache[packet] = cached
        end

        return cached
    end
end

do
    local button = ui.button
    local check = ui.check
    local edit = ui.edit
    local location = ui.location
    local text = ui.text
    local window = ui.window
    local os_date = os.date

    tracker.dashboard = function(pos)
        local active = tracker.running()

        pos(10, 50)
        text('[Tracking]{bold 16px} ' .. (active and '[on]{green}' or '[off]{red}'))

        pos(20, 30)
        text('Incoming IDs')
        pos(190, 0)
        text('Outgoing IDs')

        pos(20, 20)
        display_incoming.pattern = edit('pv_track_pattern_incoming', display_incoming.pattern)
        pos(190, 0)
        display_outgoing.pattern = edit('pv_track_pattern_outgoing', display_outgoing.pattern)

        pos(18, 30)
        if check('pv_track_exclude_incoming', 'Exclude IDs', display_incoming.exclude) then
            display_incoming.exclude = not display_incoming.exclude
        end
        pos(188, 0)
        if check('pv_track_exclude_outgoing', 'Exclude IDs', display_outgoing.exclude) then
            display_outgoing.exclude = not display_outgoing.exclude
        end

        pos(20, 20)
        if button('pv_track_start', active and 'Restart tracker' or 'Start tracker', { enabled = tracker.valid() }) then
            tracker.start()
        end
        pos(120, 0)
        if button('pv_track_stop', 'Stop tracker', { enabled = active }) then
            tracker.stop()
        end
    end

    tracker.state = init(display, {
        title = 'Packet Viewer Tracker',
    })

    local display_index

    tracker.window = function()
        local tracked_count = #tracked
        local index = display_index or tracked_count

        location(10, 10)
        if button('pv_track_previous', 'Previous', { enabled = index > 1 }) then
            display_index = index - 1
        end

        location(150, 10)
        text('Showing ' .. (display_index and tostring(index) .. '/' or 'latest of ') .. tostring(tracked_count))

        location(300, 10)
        if button('pv_track_next', 'Next', { enabled = index < tracked_count }) then
            display_index = index + 1
        end

        location(395, 10)
        if button('pv_track_last', 'Show latest', { enabled = display_index ~= nil }) then
            display_index = nil
        end

        local entry = tracked[index]
        if not entry then
            return
        end

        local packet = entry.packet
        local info = entry.info

        location(10, 50)
        text('[' .. os_date('%H:%M:%S', info.timestamp) .. ' | ' .. info.direction .. ' 0x' .. hex_zero_3[info.id] .. ']{Consolas}')

        location(10, 80)
        text(display_packet(packet, info))
    end

    tracker.button = function()
        return 'PV - Tracking', 85
    end

    tracker.save = function()
        save(display)
    end
end

return tracker
