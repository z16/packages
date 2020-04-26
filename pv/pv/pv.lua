local command = require('core.command')
local ffi = require('ffi')
local list = require('list')
local string = require('string')
local table = require('table')

-- Precomputing hex display arrays

local hex_raw = {}
local hex_space = {}
local hex_zero = {}
local hex_zero_3 = {}
do
    local string_format = string.format

    for i = 0x00, 0xFF do
        hex_raw[i] = string_format('%X', i)
        hex_space[i] = string_format('%2X', i)
        hex_zero[i] = string_format('%.2X', i)
    end

    for i = 0x000, 0x200 do
        hex_zero_3[i] = string_format('%.3X', i)
    end
end

local hex
do
    local ffi_string = ffi.string
    local string_byte = string.byte
    local string_format = string.format

    local buffer = ffi.new('char[0x400]')

    hex = function(v, length)
        if type(v) == 'number' then
            return string_format('%X', v)
        elseif type(v) == 'string' then
            length = length or #v
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

local pv_command = command.new('pv')

local handle_base_command
do
    local string_byte = string.byte
    local string_sub = string.sub
    local table_concat = table.concat

    local n_byte = string_byte('n')

    local handle_packet_filter = function(direction, exclude, ...)
        local ids = {}
        for i = 1, select('#', ...) do
            ids[i] = '0x' .. hex_zero_3[select(i, ...)]
        end
        direction.pattern = table_concat(ids, ' ')
        direction.exclude = exclude
    end

    handle_base_command = function(handler, display, direction, ...)
        if direction == 's' then
            handler.stop()
            return
        end

        local exclude = string_byte(direction) == n_byte
        if exclude then
            direction = string_sub(direction, 2)
        end

        if direction == 'i' then
            handle_packet_filter(display.incoming, exclude, ...)
        elseif direction == 'o' then
            handle_packet_filter(display.outgoing, exclude, ...)
        elseif direction == 'b' then
            handle_packet_filter(display.incoming, exclude, ...)
            handle_packet_filter(display.outgoing, exclude, ...)
        end

        if handler.valid() then
            handler.start()
        end
    end
end

local check_filters
do
    local check_filter = function(filter, packet, info)
        if info.id ~= filter[1] then
            return false
        end

        for key, value in pairs(filter) do
            if key ~= 1 then
                local packet_value = packet[key]
                if packet_value ~= value then
                    return false
                end
            end
        end

        return true
    end

    check_filters = function(handler, data, packet, info)
        if not handler.running() then
            return false
        end

        local dir = data[info.direction]
        return dir.exclude ~= dir.packets:any(check_filter, packet, info)
    end
end

return {
    process_pattern = process_pattern,
    check_filters = check_filters,
    handle_base_command = handle_base_command,
    command = pv_command,
    hex = {
        to = hex,
        raw = hex_raw,
        space = hex_space,
        zero = hex_zero,
        zero_3 = hex_zero_3,
    }
}
