local bit = require('bit')
local entities = require('entities')
local ffi = require('ffi')
local list = require('list')
local math = require('math')
local os = require('os')
local packets = require('packets')
local queue = require('queue')
local resources = require('resources')
local settings = require('settings')
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

local options = settings.load({
    dashboard = {
        visible = false,
        show = {
            logger = true,
            tracker = true,
            scanner = true,
        },
        x = 0,
        y = 0,
        width = 360,
        height = 360,
    },
    logger = {
        visible = false,
        x = 370,
        y = 0,
        width = 960,
        height = 330,
        incoming = {
            pattern = '',
            exclude = false,
        },
        outgoing = {
            pattern = '',
            exclude = false,
        },
        active = false,
    },
    tracker = {
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
    },
    scanner = {
        visible = false,
        x = 370,
        y = 0,
        width = 360,
        height = 240,
        value = '',
        type = '',
        length = 1,
        incoming = {
            pattern = '',
            exclude = true,
        },
        outgoing = {
            pattern = '',
            exclude = true,
        },
        active = false,
    },
}, true)

local watch_state
local init_state
do
    local state_cache = {}

    init_state = function(options, state)
        state.closable = true
        state.style = 'normal'

        local x = options.x
        local y = options.y
        local width = options.width
        local height = options.height

        state.x = x
        state.y = y
        state.width = width
        state.height = height

        state_cache[state.title] = {
            x = x,
            y = y,
            width = width,
            height = height,
            changed = false,
            compared = 0,
            options = options,
        }
        return state
    end

    local update_cache = function(cached, state)
        local new_x = state.x
        local new_y = state.y
        local new_width = state.width
        local new_height = state.height

        local same =
            cached.x == new_x and
            cached.y == new_y and
            cached.width == new_width and
            cached.height == new_height

        if same then
            return same
        end

        cached.x = new_x
        cached.y = new_y
        cached.width = new_width
        cached.height = new_height

        return same
    end

    watch_state = function(state)
        local cached = state_cache[state.title]

        local same = update_cache(cached, state)

        if not same then
            cached.changed = true
            cached.compared = 0
            return 'changing'
        end

        if not cached.changed then
            return 'unchanged'
        end

        local compare_count = cached.compared
        if compare_count < 10 then
            cached.compared = compare_count + 1
            return 'changing'
        end

        cached.changed = false
        cached.compared = 0

        local options = cached.options
        options.x = cached.x
        options.y = cached.y
        options.width = cached.width
        options.height = cached.height

        return 'changed'
    end
end

local process_pattern
do
    local string_gmatch = string.gmatch
    local string_match = string.match

    process_pattern = function(pattern)
        local parsed = list()

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

local dashboard = {
    display = options.dashboard,
    window_state = init_state(options.dashboard, {
        title = 'Packet Viewer',
    }),
    visible = function(t, value)
        t.display.visible = value

        settings.save(options)
    end,
    show_logger = function(t, value)
        t.display.show.logger = value

        settings.save(options)
    end,
    show_tracker = function(t, value)
        t.display.show.tracker = value

        settings.save(options)
    end,
    show_scanner = function(t, value)
        t.display.show.scanner = value

        settings.save(options)
    end,
}

local logger = {
    display = options.logger,
    window_state = init_state(options.logger, {
        title = 'Packet Viewer Logger',
    }),
    data = {
        incoming = {
            packets = list(),
            exclude = false,
        },
        outgoing = {
            packets = list(),
            exclude = false,
        },
    },
    running = function(t)
        return t.display.active
    end,
    visible = function(t, value)
        t.display.visible = value

        settings.save(options)
    end,
    start = function(t)
        local data = t.data
        local display = t.display

        data.incoming.packets = process_pattern(display.incoming.pattern)
        data.outgoing.packets = process_pattern(display.outgoing.pattern)
        data.incoming.exclude = display.incoming.exclude
        data.outgoing.exclude = display.outgoing.exclude

        display.active = true
        display.visible = true

        settings.save(options)
    end,
    stop = function(t)
        local data = t.data
        local display = t.display

        data.incoming.packets = list()
        data.outgoing.packets = list()
        data.incoming.exclude = false
        data.outgoing.exclude = false

        display.active = false

        settings.save(options)
    end,
}

local tracker = {
    display = options.tracker,
    window_state = init_state(options.tracker, {
        title = 'Packet Viewer Tracker',
    }),
    data = {
        incoming = {
            packets = list(),
            exclude = false,
        },
        outgoing = {
            packets = list(),
            exclude = false,
        },
    },
    running = function(t)
        return t.display.active
    end,
    visible = function(t, value)
        t.display.visible = value

        settings.save(options)
    end,
    start = function(t)
        local data = t.data
        local display = t.display

        data.incoming.packets = process_pattern(display.incoming.pattern)
        data.outgoing.packets = process_pattern(display.outgoing.pattern)
        data.incoming.exclude = display.incoming.exclude
        data.outgoing.exclude = display.outgoing.exclude

        display.active = true
        display.visible = true

        settings.save(options)
    end,
    stop = function(t)
        local data = t.data
        local display = t.display

        data.incoming.packets = list()
        data.outgoing.packets = list()
        data.incoming.exclude = false
        data.outgoing.exclude = false

        display.active = false

        settings.save(options)
    end,
}

local parse_string_value
do
    local math_abs = math.abs
    local string_char = string.char

    parse_string_value = function(value, type, length)
        if type == 'int' then
            local num = tonumber(value)
            if num < 0x100 and (length <= 1 or length == nil) then
                return string_char(num % 0x100)
            elseif num < 0x10000 and (length <= 2 or length == nil) then
                return string_char(num % 0x100, num / 0x100 % 0x100)
            else
                return string_char(num % 0x100, num / 0x100 % 0x100, num / 0x10000 % 0x10, num / 0x1000000 % 0x1000)
            end

        elseif type == 'string' then
            return value

        elseif type == 'hex' then
            local index = 1
            local length = #value
            local current = nil
            local str = ''

            while index < length do
                local char = value[index]
                if char ~= ' ' and chat ~= '-' then
                    local num = tonumber(char, 0x10)
                    if not num then
                        return ''
                    end

                    if current then
                        str = str .. string_char(current + num)
                        current = nil
                    else
                        current = num * 0x10
                    end
                end

                index = index + 1
            end

            return str
        end
    end
end

local scanner = {
    display = options.scanner,
    window_state = init_state(options.scanner, {
        title = 'Packet Viewer Scanner',
    }),
    data = {
        value = '',
        incoming = {
            packets = list(),
            exclude = true,
        },
        outgoing = {
            packets = list(),
            exclude = true,
        },
    },
    running = function(t)
        return t.display.active
    end,
    visible = function(t, value)
        t.display.visible = value

        settings.save(options)
    end,
    start = function(t)
        local data = t.data
        local display = t.display

        data.value = parse_string_value(display.value, display.type)
        data.incoming.packets = process_pattern(display.incoming.pattern)
        data.outgoing.packets = process_pattern(display.outgoing.pattern)
        data.incoming.exclude = display.incoming.exclude
        data.outgoing.exclude = display.outgoing.exclude

        display.active = true
        display.visible = true

        settings.save(options)
    end,
    stop = function(t)
        local data = t.data
        local display = t.display

        data.value = nil
        data.incoming.packets = list()
        data.outgoing.packets = list()
        data.incoming.exclude = true
        data.outgoing.exclude = true

        display.active = false

        settings.save(options)
    end,
}

-- Initialize logger
do
    local data = logger.data
    local display = logger.display

    data.incoming.packets = process_pattern(display.incoming.pattern)
    data.outgoing.packets = process_pattern(display.outgoing.pattern)
    data.incoming.exclude = display.incoming.exclude
    data.outgoing.exclude = display.outgoing.exclude
end

-- Initialize tracker
do
    local data = tracker.data
    local display = tracker.display

    data.incoming.packets = process_pattern(display.incoming.pattern)
    data.outgoing.packets = process_pattern(display.outgoing.pattern)
    data.incoming.exclude = display.incoming.exclude
    data.outgoing.exclude = display.outgoing.exclude
end

-- Initialize scanner
do
    local data = scanner.data
    local display = scanner.display

    data.value = parse_string_value(display.value, display.type)
    data.incoming.packets = process_pattern(display.incoming.pattern)
    data.outgoing.packets = process_pattern(display.outgoing.pattern)
    data.incoming.exclude = display.incoming.exclude
    data.outgoing.exclude = display.outgoing.exclude
end

local tracked = list()
local logged = queue()

-- Precomputing hex display arrays

local hex_raw = {}
local hex_raw_3 = {}
local hex_space = {}
local hex_zero = {}
do
    local string_format = string.format

    for i = 0x00, 0xFF do
        hex_raw[i] = string_format('%X', i)
        hex_space[i] = string_format('%2X', i)
        hex_zero[i] = string_format('%02X', i)
    end

    for i = 0x000, 0x200 do
        hex_raw_3[i] = string_format('%03X', i)
    end
end

local hex
do
    local ffi_string = ffi.string
    local string_byte = string.byte
    local string_format = string.format
    local table_concat = table.concat

    local buffer = ffi.new('char[0x400]')

    hex = function(v)
        if type(v) == 'number' then
            return string_format('%X', v)
        elseif type(v) == 'string' then
            local length = #v
            for i = 0, length - 1 do
                local str = hex_zero[string_byte(v, i + 1)]
                buffer[3 * i] = string_byte(str, 1)
                buffer[3 * i + 1] = string_byte(str, 2)
                buffer[3 * i + 2] = 0x20
            end
            return ffi_string(buffer, 3 * length)
        elseif type(v) == 'boolean' then
            return v and '1' or '0'
        end
    end
end

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
                local entity = entities.get_by_id(value)
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
            local types = ftype and ftype.types
            if types then
                ftype = types[p[ftype.key]]
            end

            local color_table = build_color_table(info, ftype)

            local table = build_packet_table(data, ftype, color_table)
            local fields = ftype and build_packet_fields(packet, ftype, color_table)

            text = '[' .. table .. (fields and '\n\n' .. fields or '') .. ']{Consolas 12px}'
            packet_display_cache[packet] = text
        end

        ui.text(text)
    end
end

ui.display(function()
    local y_current = 0

    local window = ui.window
    local location = ui.location
    local text = ui.text
    local edit = ui.edit
    local check = ui.check
    local radio = ui.radio
    local button = ui.button
    local size = ui.size

    local pos = function(x, y_off)
        y_current = y_current + y_off
        location(x, y_current)
    end

    local bottom_x = 10
    local bottom_y = windower.settings.client_size.height - 18

    local show = dashboard.display.show
    dashboard.window_state.height =
        (show.logger and 150 or 50) +
        (show.tracker and 150 or 50) +
        (show.scanner and 200 or 50)

    if dashboard.display.visible then
        local closed
        dashboard.window_state, closed = window('pv_window', dashboard.window_state, function()
            -- Logging
            do
                local display = logger.display
                local incoming = display.incoming
                local outgoing = display.outgoing

                local active = logger:running()

                pos(10, 10)
                text('[Logging]{bold 16px} ' .. (active and '[on]{green}' or '[off]{red}'))

                if show.logger then
                    pos(20, 30)
                    text('Incoming IDs')
                    pos(190, 0)
                    text('Outgoing IDs')

                    pos(20, 20)
                    incoming.pattern = edit('pv_log_pattern_incoming', incoming.pattern)
                    pos(190, 0)
                    outgoing.pattern = edit('pv_log_pattern_outgoing', outgoing.pattern)

                    pos(18, 30)
                    if check('pv_log_exclude_incoming', 'Exclude IDs', incoming.exclude) then
                        incoming.exclude = not incoming.exclude
                    end
                    pos(188, 0)
                    if check('pv_log_exclude_outgoing', 'Exclude IDs', outgoing.exclude) then
                        outgoing.exclude = not outgoing.exclude
                    end

                    pos(20, 20)
                    if button('pv_log_start', active and 'Restart logger' or 'Start logger') then
                        logger:start()
                    end
                    pos(120, 0)
                    if button('pv_log_stop', 'Stop logger', { enabled = active }) then
                        logger:stop()
                    end
                end
            end

            -- Tracking
            do
                local display = tracker.display
                local incoming = display.incoming
                local outgoing = display.outgoing

                local active = tracker:running()

                pos(10, 50)
                text('[Tracking]{bold 16px} ' .. (active and '[on]{green}' or '[off]{red}'))

                if show.tracker then
                    pos(20, 30)
                    text('Incoming IDs')
                    pos(190, 0)
                    text('Outgoing IDs')

                    pos(20, 20)
                    incoming.pattern = edit('pv_track_pattern_incoming', incoming.pattern)
                    pos(190, 0)
                    outgoing.pattern = edit('pv_track_pattern_outgoing', outgoing.pattern)

                    pos(18, 30)
                    if check('pv_track_exclude_incoming', 'Exclude IDs', incoming.exclude) then
                        incoming.exclude = not incoming.exclude
                    end
                    pos(188, 0)
                    if check('pv_track_exclude_outgoing', 'Exclude IDs', outgoing.exclude) then
                        outgoing.exclude = not outgoing.exclude
                    end

                    pos(20, 20)
                    if button('pv_track_start', active and 'Restart tracker' or 'Start tracker') then
                        tracker:start()
                    end
                    pos(120, 0)
                    if button('pv_track_stop', 'Stop tracker', { enabled = active }) then
                        tracker:stop()
                    end
                end
            end

            -- Scanning
            do
                local display = scanner.display
                local incoming = display.incoming
                local outgoing = display.outgoing

                local active = scanner:running()

                pos(10, 50)
                text('[Scanning]{bold 16px} ' .. (active and '[on]{green}' or '[off]{red}'))

                if show.scanner then
                    pos(20, 30)
                    text('Scan for value')
                    pos(100, -3)
                    size(250, 23)
                    display.value = edit('pv_scan_value', display.value)
                    pos(0, 3)

                    pos(20, 30)
                    text('Type')
                    pos(100, 0)
                    if radio('pv_scan_type_int', 'Integer', display.type == 'int') then
                        display.type = 'int'
                    end
                    pos(180, 0)
                    if radio('pv_scan_type_string', 'String', display.type == 'string') then
                        display.type = 'string'
                    end
                    pos(260, 0)
                    if radio('pv_scan_type_hex', 'Hex array', display.type == 'hex') then
                        display.type = 'hex'
                    end

                    pos(20, 30)
                    text('Incoming IDs')
                    pos(190, 0)
                    text('Outgoing IDs')

                    pos(20, 20)
                    incoming.pattern = edit('pv_scan_pattern_incoming', incoming.pattern)
                    pos(190, 0)
                    outgoing.pattern = edit('pv_scan_pattern_outgoing', outgoing.pattern)

                    pos(18, 30)
                    if check('pv_scan_exclude_incoming', 'Exclude IDs', incoming.exclude) then
                        incoming.exclude = not incoming.exclude
                    end
                    pos(188, 0)
                    if check('pv_scan_exclude_outgoing', 'Exclude IDs', outgoing.exclude) then
                        outgoing.exclude = not outgoing.exclude
                    end

                    pos(20, 20)
                    if button('pv_scan_start', active and 'Restart scanner' or 'Start scanner') then
                        scanner:start()
                    end
                    pos(120, 0)
                    if button('pv_scan_stop', 'Stop scanner', { enabled = active }) then
                        scanner:stop()
                    end
                end
            end
        end)

        if closed then
            dashboard.display.visible = false
        end
    end

    if logger.display.visible then
        local closed
        logger.window_state, closed = window('pv_log_window', logger.window_state, function()
            for i = 1, #logged do
                text(logged[i])
            end
        end)

        if closed then
            logger:visible(false)
        end
    end

    if tracker.display.visible then
        local closed
        tracker.window_state, closed = window('pv_track_window', tracker.window_state, function()
            if not tracked:any() then
                return
            end

            display_packet(tracked[index or #tracked])
        end)

        if closed then
            tracker:visible(false)
        end
    end

    if scanner.display.visible then
        local closed
        scanner.window_state, closed = window('pv_scan_window', scanner.window_state, function()
        end)

        if closed then
            scanner.display.visible = false
        end
    end

    do
        location(bottom_x, bottom_y)
        if button('pv_window_maximize', 'Packet Viewer') then
            dashboard:visible(not dashboard.display.visible)
        end
        bottom_x = bottom_x + 89
        location(bottom_x, bottom_y)
        if button('pv_log_window_maximize', 'PV - Logging') then
            logger:visible(not logger.display.visible)
        end
        bottom_x = bottom_x + 85
        location(bottom_x, bottom_y)
        if button('pv_track_window_maximize', 'PV - Tracking') then
            tracker:visible(not tracker.display.visible)
        end
        bottom_x = bottom_x + 85
        location(bottom_x, bottom_y)
        if button('pv_scan_window_maximize', 'PV - Scanning') then
            scanner:visible(not scanner.display.visible)
        end
    end

    do
        local statuses = list(
            dashboard.window_state,
            logger.window_state,
            tracker.window_state,
            scanner.window_state
        ):select(watch_state)

        if statuses:any(function(status) return status == 'changed' end) and statuses:all(function(status) return status ~= 'changing' end) then
            settings.save(options)
        end
    end
end)

local check_filter = function(filter, packet, exclude)
    local info = packet._info
    if info.id ~= filter[1] then
        return exclude
    end

    for key, value in pairs(filter) do
        if key ~= 1 then
            local packet_value = packet[key]
            if packet_value ~= value then
                return exclude
            end
        end
    end

    return not exclude
end

local log_packet = function(packet)
    if not logger:running() then
        return
    end

    local info = packet._info
    local data = logger.data[info.direction]
    if not data.packets:any(check_filter, packet, data.exclude) then
        return
    end

    logged:push('[' .. os.date('%H:%M:%S', os.time()) .. ']  ' .. info.direction .. ' 0x' .. hex_raw_3[info.id] .. ':    ' .. hex(info.data))
    if #logged > 0x10 then
        logged:pop()
    end
end

local track_packet = function(packet)
    if not tracker:running() then
        return
    end

    local data = tracker.data[packet._info.direction]
    if not data.packets:any(check_filter, packet, data.exclude) then
        return
    end

    tracked:add(packet)
end

packets:register(function(packet)
    -- Logging
    log_packet(packet)

    -- Tracking
    track_packet(packet)

    -- Scanning
    --TODO
end)
