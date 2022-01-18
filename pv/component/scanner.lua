local list = require('list')
local os = require('os')
local packet = require('packet')
local queue = require('queue')
local settings = require('settings')
local string = require('string')
local table = require('table')
local ui = require('core.ui')

local state = require('pv.state')
local pv = require('pv.pv')

local display
do
    local defaults = {
        visible = false,
        x = 370,
        y = 21,
        width = 480,
        height = 340,
        value = '',
        type = 'int',
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
    }

    display = settings.load(defaults, 'scanner', true)
end

local data = {
    value = '',
    incoming = {
        packets = list(),
        exclude = false,
    },
    outgoing = {
        packets = list(),
        exclude = false,
    },
}

local scanned = queue()

local tonumber = tonumber
local process_pattern = pv.process_pattern
local handle_base_command = pv.handle_base_command
local check_filters = pv.check_filters
local save = settings.save
local init = state.init

local display_incoming = display.incoming
local display_outgoing = display.outgoing
local data_incoming = data.incoming
local data_outgoing = data.outgoing

local hex_zero = pv.hex.zero
local hex_zero_3 = pv.hex.zero_3

-- Helpers

local parse_string_value
do
    local string_char = string.char
    local string_sub = string.sub

    parse_string_value = function(value, type)
        if type == 'int' then
            local num = tonumber(value)
            if not num then
                return ''
            elseif num < 0x100 then
                return string_char(num % 0x100)
            elseif num < 0x10000 then
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

            while index <= length do
                local char = string_sub(value, index, index)
                if char ~= ' ' and char ~= '-' then
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

-- Public operations

local scanner = {}

scanner.name = 'scan'

scanner.valid = function()
    return display.value ~= ''
end

scanner.running = function()
    return display.active
end

scanner.visible = function()
    return display.visible
end

scanner.show = function(value)
    display.visible = value

    save('scanner')
end

scanner.start = function()
    data.value = parse_string_value(display.value, display.type)
    data_incoming.packets = process_pattern(display_incoming.pattern)
    data_outgoing.packets = process_pattern(display_outgoing.pattern)
    data_incoming.exclude = display_incoming.exclude
    data_outgoing.exclude = display_outgoing.exclude

    display.active = true
    display.visible = true

    save('scanner')
end

scanner.stop = function()
    data.value = nil
    data_incoming.packets = list()
    data_outgoing.packets = list()
    data_incoming.exclude = true
    data_outgoing.exclude = true

    display.active = false

    save('scanner')
end

-- Packet handling

do
    local os_date = os.date
    local os_time = os.time
    local string_find = string.find
    local string_sub = string.sub
    local table_concat = table.concat

    packet:register(function(p, info)
        if not check_filters(scanner, data, p, info) then
            return
        end

        local raw = string_sub(info.original, 1, info.original_size)
        local positions = list()
        local start = 0
        repeat
            start = string_find(raw, data.value, start + 1)
            if start then
                positions:add(start)
            end
        until not start

        if positions:any() then
            scanned:push('[' ..
                os_date('%H:%M:%S', os_time()) .. '  ' ..
                info.direction .. '  ' ..
                '0x' .. hex_zero_3[info.id] .. '   ' ..
                'Found at positions: ' .. table_concat(positions:select(function(pos) return '0x' .. hex_zero[pos - 1] end):to_table(), ', ') ..
            ']{Consolas}')
            if #scanned > 20 then
                scanned:pop()
            end
        end
    end)
end

-- Command handling

do
    local scan_filter_command = function(direction, ...)
        handle_base_command(scanner, display, direction, ...)
    end

    local scan_for_command = function(type, value)
        local scanner_display = scanner.display
        scanner_display.value = value
        scanner_display.type = type

        if scanner.valid() then
            scanner.start()
        end
    end

    pv.command:register('scan', 'for', scan_for_command, '<type:one_of(int,string,hex)> <value:text>')
    pv.command:register('scan', 'filter', scan_filter_command, '<direction:one_of(i,ni,o,no,b,nb,s)> [ids:number(0x001,0x1FF)]*')
end

-- Initialization

data.value = parse_string_value(display.value, display.type)
data_incoming.packets = process_pattern(display_incoming.pattern)
data_outgoing.packets = process_pattern(display_outgoing.pattern)
data_incoming.exclude = display_incoming.exclude
data_outgoing.exclude = display_outgoing.exclude

-- UI

do
    local edit_state = ui.edit_state

    local edit_value = edit_state()
    local edit_incoming = edit_state()
    local edit_outgoing = edit_state()

    edit_value.text = display.value
    edit_incoming.text = display_incoming.pattern
    edit_outgoing.text = display_outgoing.pattern

    scanner.dashboard = function(layout, pos)
        local active = scanner.running()

        pos(0, 50)
        layout:label('[Scanning]{bold 16px} ' .. (active and '[on]{green}' or '[off]{red}'))

        pos(10, 30)
        layout:label('Scan for value')
        pos(90, -4)
        layout:size(250, 23)
        layout:edit(edit_value)
        display.value = edit_value.text
        pos(0, 4)

        pos(10, 30)
        layout:label('Type')
        pos(90, 0)
        layout:width(70)
        if layout:radio('scanner_value_int', 'Integer', display.type == 'int') then
            display.type = 'int'
        end
        pos(170, 0)
        layout:width(70)
        if layout:radio('scanner_value_string', 'String', display.type == 'string') then
            display.type = 'string'
        end
        pos(250, 0)
        layout:width(70)
        if layout:radio('scanner_value_hex', 'Hex array', display.type == 'hex') then
            display.type = 'hex'
        end

        pos(10, 30)
        layout:label('Incoming IDs')
        pos(180, 0)
        layout:label('Outgoing IDs')

        pos(10, 20)
        layout:edit(edit_incoming)
        display_incoming.pattern = edit_incoming.text
        pos(180, 0)
        layout:edit(edit_outgoing)
        display_outgoing.pattern = edit_outgoing.text

        pos(10, 30)
        layout:width(160)
        if layout:check('scanner_incoming', 'Exclude IDs', display_incoming.exclude) then
            display_incoming.exclude = not display_incoming.exclude
        end
        pos(180, 0)
        layout:width(160)
        if layout:check('scanner_outgoing', 'Exclude IDs', display_outgoing.exclude) then
            display_outgoing.exclude = not display_outgoing.exclude
        end

        pos(10, 20)
        layout:width(90)
        -- TODO: Move "and" clause to enabled property
        if layout:button(active and 'Restart scanner' or 'Start scanner') and scanner.valid() then
            scanner.start()
        end
        pos(110, 0)
        layout:width(90)
        -- TODO: Move "and" clause to enabled property
        if layout:button('Stop scanner') and active then
            scanner.stop()
        end
    end

    scanner.state = init(display, {
        title = 'Packet Viewer Scanner',
    })

    scanner.window = function(layout)
        for i = 1, #scanned do
            layout:move(0, 20 * (i - 1))
            -- TODO: Remove specific width once non-wrapping layout is enabled
            layout:width(10000)
            layout:label(scanned[i])
        end
    end

    scanner.button_caption = function()
        return 'PV - Scanning'
    end

    scanner.button_size = function()
        return 85
    end

    scanner.save = function()
        save('scanner')
    end
end

return scanner
