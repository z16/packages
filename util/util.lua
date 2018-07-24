local table = require('table')
local string = require('string')
local ffi = require('ffi')

local util = {}

do
    local table_sort = table.sort
    local table_concat = table.concat

    local vstring

    vstring = function(t, level, cache)
        local root = not cache

        level = level or 0
        cache = cache or {}
        local indent = (' '):rep(4 * level)

        cache[t] = true

        local lines = {}
        lines[1] = indent .. '{' .. (root and (' -- ' .. tostring(t)) or '')
        local keys = {}
        local key_count = 0
        for key in pairs(t) do
            key_count = key_count + 1
            keys[key_count] = key
        end

        table_sort(keys, function(k1, k2)
            local num1 = type(k1) == 'number'
            local num2 = type(k2) == 'number'
            return num1 == num2 and k1 < k2 or num1 and not num2
        end)

        local line_count = 1
        for i = 1, key_count do
            local k = keys[i]
            local v = t[k]
            local cycle = cache[v]
            line_count = line_count + 1
            lines[line_count] = (indent .. '    [' .. tostring(k) .. '] = ' .. tostring(v) .. (cycle and ' -- cycle' or ''))
            if type(v) == 'table' and not cycle then
                local inner = vstring(v, level + 1, cache)
                for i = 1, #inner do
                    line_count = line_count + 1
                    lines[line_count] = inner[i]
                end
            end
        end

        line_count = line_count + 1
        lines[line_count] = indent .. '}'

        return lines
    end

    util.vstring = function(t)
        return table_concat(vstring(t), '\n')
    end
    util.vprint = function(t)
        print(util.vstring(t))
    end
end

do
    local table_concat = table.concat
    local string_format = string.format
    local string_byte = string.byte

    local lookup_byte = {}
    for i = 0x20, 0x7E do
        lookup_byte[i] = string.char(i)
    end

    util.str_hex_table = function(str)
        local address = 0
        local base_offset = 0
        local end_data = #str
        local end_display = end_data + 0x10 - end_data % 0x10

        local lookup_hex = {}
        local lookup_display = {}
        for i = 0, base_offset - 1 do
            lookup_hex[i] = '--'
            lookup_display[i] = '-'
        end
        for i = end_data, end_display - 1 do
            lookup_hex[i] = '--'
            lookup_display[i] = '-'
        end
        for i = base_offset, end_data - 1 do
            local char = string_byte(str, i - base_offset + 1)
            lookup_hex[i] = string_format('%02X', char)
            lookup_display[i]= lookup_byte[char] or '.'
        end

        local lines = {}
        lines[1] = '   | 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F | 0123456789ABCDEF'
        lines[2] = '-----------------------------------------------------------------------'
        for row = 0, end_display / 0x10 - 1 do
            local index_offset = 0x10 * row
            local res =
                string_format('%02X | ', address - base_offset + index_offset) ..
                table_concat(lookup_hex, ' ', index_offset, index_offset + 0xF) .. ' | ' ..
                table_concat(lookup_display, '', index_offset, index_offset + 0xF)
            lines[row + 3] = res
        end

        return table_concat(lines, '\n')
    end
end

do
    local table_concat = table.concat
    local string_format = string.format
    local ffi_cast = ffi.cast

    local lookup_byte = {}
    for i = 0x20, 0x7E do
        lookup_byte[i] = string.char(i)
    end

    util.ptr_hex_table = function(ptr, size)
        ptr = ffi_cast('uint8_t*', ptr)
        local address = tonumber(ffi_cast('intptr_t', ptr))
        local base_offset = address % 0x10
        local end_data = base_offset + size
        local end_display = end_data + 0x10 - end_data % 0x10

        local lookup_hex = {}
        local lookup_display = {}
        for i = 0, base_offset - 1 do
            lookup_hex[i] = '--'
            lookup_display[i] = '-'
        end
        for i = end_data, end_display - 1 do
            lookup_hex[i] = '--'
            lookup_display[i] = '-'
        end
        for i = base_offset, end_data - 1 do
            local char = ptr[i - base_offset]
            lookup_hex[i] = string_format('%02X', char)
            lookup_display[i]= lookup_byte[char] or '.'
        end

        local lines = {}
        lines[1] = '         | 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F | 0123456789ABCDEF'
        lines[2] = '-----------------------------------------------------------------------------'
        for row = 0, end_display / 0x10 - 1 do
            local index_offset = 0x10 * row
            local res =
                string_format('%08X | ', address - base_offset + index_offset) ..
                table_concat(lookup_hex, ' ', index_offset, index_offset + 0xF) .. ' | ' ..
                table_concat(lookup_display, '', index_offset, index_offset + 0xF)
            lines[row + 3] = res
        end

        return table_concat(lines, '\n')
    end
end

do
    local prev = {}

    local table_concat = table.concat
    local string_format = string.format
    local ffi_cast = ffi.cast

    local lookup_byte = {}
    for i = 0x20, 0x7E do
        lookup_byte[i] = string.char(i)
    end

    util.ptr_hex_table_compare = function(ptr, size)
        ptr = ffi_cast('uint8_t*', ptr)
        local address = tonumber(ffi_cast('intptr_t', ptr))
        local base_offset = address % 0x10
        local end_data = base_offset + size
        local end_display = end_data + 0x10 - (end_data - 1) % 0x10 + 1

        local new_prev = {}
        local lookup_hex = {}
        local lookup_display = {}
        for i = 0, base_offset - 1 do
            lookup_hex[i] = '      --'
            lookup_display[i] = '-'
        end
        for i = end_data, end_display - 1 do
            lookup_hex[i] = '      --'
            lookup_display[i] = '-'
        end
        for i = base_offset, end_data - 1 do
            local index = i - base_offset
            local char = ptr[index]
            local prev_char = prev and prev[index]
            if prev_char and char ~= prev_char then
                lookup_hex[i] = string_format(' (%02X) %02X', prev_char, char)
            else
                lookup_hex[i] = string_format('      %02X', char)
            end
            lookup_display[i]= lookup_byte[char] or '.'
            new_prev[index] = char
        end

        prev = new_prev

        local lines = {
            '\n',
            '         |      00      01      02      03      04      05      06      07      08      09      0A      0B      0C      0D      0E      0F | 0123456789ABCDEF',
            '-------------------------------------------------------------------------------------------------------------------------------------------------------------',
        }

        for row = 0, end_display / 0x10 - 1 do
            local index_offset = 0x10 * row
            local res =
                string_format('%08X |', address - base_offset + index_offset) ..
                table_concat(lookup_hex, '', index_offset, index_offset + 0xF) .. ' | ' ..
                table_concat(lookup_display, '', index_offset, index_offset + 0xF)
            lines[row + 4] = res
        end

        return table.concat(lines, '\n')
    end
end

return util
