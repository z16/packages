local bit = require('bit')
local lists = require('lists')
local math = require('math')
local os = require('os')
local packets = require('packets')
local shared = require('shared')
local string = require('string')
local table = require('table')
local ui = require('ui')
local windower = require('windower')

local client = shared.get('packet_service', 'types')

local ftypes = {
    incoming = {},
    outgoing = {},
}

for i = 0, 0x1FF do
    ftypes.incoming[i] = client:read('incoming', i)
    ftypes.outgoing[i] = client:read('outgoing', i)
end

local window_size = windower.settings.client_size

local dashboard = {
    show = false,
    window_state = {
        title = 'Packet Viewer',
        style = 'normal',
        x = 0,
        y = 0,
        width = 360,
        height = 260,
        closable = true,
    },
}

local logging = {
    window_state = {},
}

local tracking = {
    show = false,
    packets_incoming = lists({}),
    packets_outgoing = lists({}),
    pattern_temp_incoming = '',
    pattern_temp_outgoing = '',
    exclude_incoming = false,
    exclude_outgoing = false,
    exclude_temp_incoming = false,
    exclude_temp_outgoing = false,
    window_state = {
        title = 'Packet Viewer Tracker',
        style = 'normal',
        x = 370,
        y = 0,
        width = 490,
        height = 460,
        closable = true,
    }
}

local tracked = lists({})

local scanning = {
    state = {},
}

local process_pattern
do
    local string_gmatch = string.gmatch
    local string_match = string.match

    process_pattern = function(pattern)
        local parsed = lists({})

        for match in string_gmatch(pattern, '[^%s]+') do
            local single = {}

            local id, rest = string_match(match, '(0?x?[A-Fa-f0-9]+)/?(.*)')
            single[1] = tonumber(id)

            for sub in string_gmatch(rest, '[^/]+') do
                local key, value = string_match(sub, '(.*)=\'(.*)\'')
                if value then
                    single[key] = value
                else
                    key, value = string_match(sub, '(.*)=(.*)')
                    single[key] = value == 'true' or value ~= 'false' and tonumber(value) or false
                end
            end

            parsed:add(single)
        end

        return parsed
    end
end

local colors = {}
do
    local math_sqrt = math.sqrt
    local math_pi = math.pi
    local ui_color_hsv = ui.color.hsv
    local ui_color_tohex = ui.color.tohex

    for i = 1, 0x400 do
        local color = ui_color_hsv((i * 67 + 210) % 360, 0.7, 1)
        colors[i] = ui_color_tohex(color)
    end
end

local build_packet_fields
do
    local table_concat = table.concat

    build_packet_fields = function(packet, ftype, color_table)
        local arranged = ftype.arranged
        local lines = {}
        local lines_count = 0
        for i = 1, #arranged do
            local field = arranged[i]
            lines_count = lines_count + 1
            lines[lines_count] = '[' .. field.label .. ': ' .. tostring(packet[field.label]) .. ']{' .. colors[i] .. '}'
        end

        return table_concat(lines, '\n')
    end
end

local build_packet_table
do
    local table_concat = table.concat
    local string_byte = string.byte
    local string_char = string.char
    local string_format = string.format
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
            lookup_hex[i] = string_format('%02X', byte)
            lookup_char[i] = lookup_byte[byte] or '.'
        end

        local lines = {}
        lines[1] = '   |  0  1  2  3  4  5  6  7  8  9  A  B  C  D  E  F | 0123456789ABCDEF'
        lines[2] = '-----------------------------------------------------------------------'
        for row = 0, end_char / 0x10 - 1 do
            local index_offset = 0x10 * row
            local prefix = string_format('%2X | ', (address - base_offset + index_offset) / 0x10)
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
        local color_table = color_table_cache[ftype]
        if not color_table then
            color_table = make_table(info, ftype)
            color_table_cache[ftype] = color_table
        end

        --TODO ftype.var_size
        return color_table
    end
end

local display_packet
do
    local packet_display_cache = {}

    display_packet = function(packet)
        local text = packet_display_cache[p]
        if not text then
            local info = packet._info
            local data = info.data

            ui.location(10, 10)

            local ftype = ftypes[info.direction][info.id]
            if ftype.types then
                ftype = ftype.types[p[ftype.key]]
            end

            local color_table = build_color_table(info, ftype)

            local table = build_packet_table(data, ftype, color_table)
            local fields = ftype and build_packet_fields(packet, ftype, color_table)

            text = '[' .. table .. '\n\n' .. fields .. ']{Consolas 12px}'
            packet_display_cache[packet] = text
        end

        ui.text(text)
    end
end

ui.display(function()
    local bottom_x = 10
    local bottom_y = window_size.height - 18

    if dashboard.show then
        local closed
        dashboard.window_state, closed = ui.window('pv_window', dashboard.window_state, function()
            -- Logging
            local is_logging = false

            local y_log = 10
            ui.location(10, y_log + 0)
            ui.text('[Logging]{bold 16px} ' .. (is_logging and '[on]{green}' or '[off]{red}'))

            ui.location(20, y_log + 30)
            ui.text('Not yet implemented...')

            -- Tracking
            local is_tracking = tracking.packets_incoming:any() or tracking.packets_outgoing:any() or tracking.exclude_incoming or tracking.exclude_outgoing

            local y_track = y_log + 60
            ui.location(10, y_track + 0)
            ui.text('[Tracking]{bold 16px} ' .. (is_tracking and '[on]{green}' or '[off]{red}'))

            ui.location(20, y_track + 30)
            ui.text('Incoming IDs')
            ui.location(190, y_track + 30)
            ui.text('Outgoing IDs')

            ui.location(20, y_track + 50)
            tracking.pattern_temp_incoming = ui.edit('pv_track_pattern_incoming', tracking.pattern_temp_incoming)
            ui.location(190, y_track + 50)
            tracking.pattern_temp_outgoing = ui.edit('pv_track_pattern_outgoing', tracking.pattern_temp_outgoing)

            ui.location(18, y_track + 80)
            if ui.check('pv_track_exclude_incoming', 'Exclude IDs', tracking.exclude_temp_incoming) then
                tracking.exclude_temp_incoming = not tracking.exclude_temp_incoming
            end
            ui.location(188, y_track + 80)
            if ui.check('pv_track_exclude_outgoing', 'Exclude IDs', tracking.exclude_temp_outgoing) then
                tracking.exclude_temp_outgoing = not tracking.exclude_temp_outgoing
            end

            ui.location(20, y_track + 100)
            if ui.button('pv_track_start', 'Start tracking') then
                tracking.packets_incoming = process_pattern(tracking.pattern_temp_incoming)
                tracking.packets_outgoing = process_pattern(tracking.pattern_temp_outgoing)
                tracking.exclude_incoming = tracking.exclude_temp_incoming
                tracking.exclude_outgoing = tracking.exclude_temp_outgoing
                tracking.show = true
            end
            ui.location(120, y_track + 100)
            if ui.button('pv_track_stop', 'Stop tracking') then
                tracking.packets_incoming = lists({})
                tracking.packets_outgoing = lists({})
                tracking.exclude_incoming = false
                tracking.exclude_outgoing = false
                tracking.show = false
            end

            -- Scanning
            local is_scanning = scanning.value ~= nil

            local y_scan = y_track + 130
            ui.location(10, y_scan + 0)
            ui.text('[Scanning]{bold 16px} ' .. (is_scanning and '[on]{green}' or '[off]{red}'))
            ui.location(20, y_scan + 30)
            ui.text('Not yet implemented...')
        end)

        if closed then
            dashboard.show = false
        end
    end

    if logging.show then
        local closed
        logging.window_state, closed = ui.window('pv_log_window', logging.window_state, function()
        end)

        if closed then
            logging.show = false
        end
    end

    if tracking.show then
        local closed
        tracking.window_state, closed = ui.window('pv_track_window', tracking.window_state, function()
            if not tracked:any() then
                return
            end

            display_packet(tracked[index or #tracked])
        end)

        if closed then
            tracking.show = false
        end
    end

    if scanning.show then
        local closed
        scanning.window_state, closed = ui.window('pv_scan_window', scanning.window_state, function()
        end)

        if closed then
            scanning.show = false
        end
    end

    do
        ui.location(bottom_x, bottom_y)
        if ui.button('pv_window_maximize', 'Packet Viewer') then
            dashboard.show = not dashboard.show
        end
        bottom_x = bottom_x + 89
        ui.location(bottom_x, bottom_y)
        if ui.button('pv_log_window_maximize', 'PV - Logging', {enabled = false}) then
            logging.show = not logging.show
        end
        bottom_x = bottom_x + 85
        ui.location(bottom_x, bottom_y)
        if ui.button('pv_track_window_maximize', 'PV - Tracking') then
            tracking.show = not tracking.show
        end
        bottom_x = bottom_x + 85
        ui.location(bottom_x, bottom_y)
        if ui.button('pv_scan_window_maximize', 'PV - Scanning', {enabled = false}) then
            scanning.show = not scanning.show
        end
    end
end)

local check_filter = function(filter, packet)
    local info = packet._info
    if info.id ~= filter[1] then
        return false
    end

    for key, value in pairs(filter) do
        if key ~= 1 then
            local packet_value = p[key]
            if packet_value ~= value then
                return false
            end
        end
    end

    return true
end

local track_packet = function(packet)
    local filters = tracking['packets_' .. packet._info.direction]
    if not filters:any(check_filter, packet) then
        return
    end

    tracked:add(packet)
end

packets:register(function(packet)
    -- Logging
    --TODO

    -- Tracking
    track_packet(packet)

    -- Scanning
    --TODO
end)
