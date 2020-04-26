local bit = require('bit')
local debug = require('debug')
local ffi = require('ffi')
local string = require('string')
local struct = require('struct')
local table = require('table')

local util = {}

do
    local string_byte = string.byte
    local string_find = string.find
    local string_format = string.format
    local string_sub = string.sub
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
        local values = {}
        local key_count = 0
        local has_pairs = pcall(pairs, t)
        if has_pairs then
            for key, value in pairs(t) do
                key_count = key_count + 1
                keys[key_count] = key
                values[key] = value
            end
        else
            for key = 0, -1, 1 do
                if pcall(function(t, k) return t[k] end, t, key) then
                    key_count = key_count + 1
                    keys[key_count] = key
                    values[key] = t[key]
                end
            end
        end

        table_sort(keys, function(k1, k2)
            local num1 = type(k1) == 'number'
            local num2 = type(k2) == 'number'
            return num1 == num2 and k1 < k2 or num1 and not num2
        end)

        local line_count = 1
        for i = 1, key_count do
            local k = keys[i]
            local v = values[k]
            local cycle = cache[v]
            local value = tostring(v)
            if string_find(value, '\x00') then
                local res = ''
                for i = 1, #value do
                    local c = string_sub(value, i, i)
                    if i > 1 then
                        res = res .. ' '
                    end
                    res = res .. string_format('%.2X', string_byte(c))
                end
                value = res
            end

            line_count = line_count + 1
            lines[line_count] = (indent .. '    [' .. tostring(k) .. '] = ' .. value .. (cycle and ' -- cycle' or ''))

            if not cycle and not value:find('windower.event') and pcall(pairs, v) then
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
    local string_byte = string.byte
    local string_char = string.char
    local string_format = string.format
    local band = bit.band
    local bnot = bit.bnot
    local ffi_cast = ffi.cast

    local lookup_byte = {}
    for i = 0x20, 0x7E do
        lookup_byte[i] = string_char(i)
    end

    local str_hex_table = function(str)
        local address = 0
        local base_offset = 0
        local end_data = #str
        local end_display = band(end_data + 0xF, bnot(0xF))

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
        lines[1] = '   |  0  1  2  3  4  5  6  7  8  9  A  B  C  D  E  F | 0123456789ABCDEF'
        lines[2] = '-----------------------------------------------------------------------'
        for row = 0, end_display / 0x10 - 1 do
            local index_offset = 0x10 * row
            local res =
                string_format('%2X | ', (address - base_offset + index_offset) / 0x10) ..
                table_concat(lookup_hex, ' ', index_offset, index_offset + 0xF) .. ' | ' ..
                table_concat(lookup_display, '', index_offset, index_offset + 0xF)
            lines[row + 3] = res
        end

        return table_concat(lines, '\n')
    end

    local ptr_hex_table = function(ptr, size)
        ptr = ffi_cast('uint8_t*', ptr)
        local address = tonumber(ffi_cast('intptr_t', ptr))
        local base_offset = address % 0x10
        local end_data = base_offset + size
        local end_display = band(end_data + 0xF, bnot(0xF))

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
        lines[1] = '         |  0  1  2  3  4  5  6  7  8  9  A  B  C  D  E  F | 0123456789ABCDEF'
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

    util.hex_table = function(...)
        if type(...) == 'string' then
            return str_hex_table(...)
        elseif type(...) == 'cdata' or type(...) == 'number' then
            return ptr_hex_table(...)
        end
    end
end

do
    local prev = {}

    local table_concat = table.concat
    local string_format = string.format
    local band = bit.band
    local bnot = bit.bnot
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
        local end_display = band(end_data + 0xF, bnot(0xF))

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
            '         |       0       1       2       3       4       5       6       7       8       9       A       B       C       D       E       F | 0123456789ABCDEF',
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

do
    local string_gmatch = string.gmatch
    local string_gsub = string.gsub
    local string_match = string.match
    local string_rep = string.rep
    local string_sub = string.sub
    local table_concat = table.concat

    local indents = {}
    for i = 0, 20 do
        indents[i] = string_rep('    ', i)
    end

    util.vdef = function(ftype)
        local def = ftype.cdef

        local changed = 1
        while changed > 0 do
            for key, value in pairs(struct.typedefs) do
                def, changed = string_gsub(def, key .. ' ', value .. ' ')
            end
        end

        def = string_gsub(def, '{', ' {\n')
        def = string_gsub(def, ';', ';\n') .. '\n'

        local lines = {}
        local count = 0
        for line in string_gmatch(def, '(.-)\n') do
            count = count + 1
            lines[count] = line
        end

        local indent = 0
        for i = 1, count do
            local line = lines[i]

            if string_sub(line, 1, 1) == '}' then
                indent = indent - 1
            end

            lines[i] = indents[indent] .. line

            if string_sub(line, #line, #line) == '{' then
                indent = indent + 1
            end
        end

        return table_concat(lines, '\n')
    end
end

util.line = function(frame)
    return debug.getinfo((frame or 1) + 1).currentline
end

util.lprint = function(frame)
    print(util.line((frame or 1) + 1))
end

return util
