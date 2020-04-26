local command = require('core.command')
local ffi = require('ffi')
local string = require('string')

-- Precomputing hex display arrays

local hex_raw = {}
local hex_space = {}
local hex_zero = {}
do
    local string_format = string.format

    for i = 0x00, 0xFF do
        hex_raw[i] = string_format('%X', i)
        hex_space[i] = string_format('%2X', i)
        hex_zero[i] = string_format('%.2X', i)
    end
end

local hex
do
    local ffi_string = ffi.string
    local string_byte = string.byte
    local string_format = string.format

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

local mv_command = command.new('mv')

local hex_address
do
    local ffi_cast = ffi.cast
    local string_format = string.format

    local int_ptr = ffi.typeof('intptr_t')

    hex_address = function(address)
        if type(address == 'cdata') then
            address = tonumber(ffi_cast(int_ptr, address))
        end

        return string_format('%.8X', address)
    end
end

return {
    command = mv_command,
    hex = {
        to = hex,
        raw = hex_raw,
        space = hex_space,
        zero = hex_zero,
        address = hex_address,
    }
}
