local packets = require('packets')
local command = require('command')
local util = require('util')
local os = require('os')

local pprint = function(packet)
    local info = packet._info
    print()
    print()
    print()
    print(('%s 0x%03X, at %s'):format(info.direction, info.id, os.date('%c')))
    print(util.hex_table(info.data))

    local payload = packet.data
    packet._info = nil
    util.vprint(packet)
end

local pv = command.new('pv')

command.arg.register_type('multi_int', {
    check = function(str, options)
        local res = {}
        local count = 0
        for value in str:gmatch('([%dxa-fA-F]+)|?') do
            count = count + 1
            res[count] = tonumber(value)
        end
        return res
    end,
})

local dirs = {
    i = 'incoming',
    o = 'outgoing',
}

pv:register('t', function(dir, ...)
    local root = packets[dirs[dir]]
    for i = 1, select('#', ...) do
        local indices = select(i, ...)
        local p = root
        for j = 1, #indices do
            p = p[indices[j]]
        end
        p:register(pprint)
    end
end, '<dir:one_of(i,o)> <ids:multi_int>*')
