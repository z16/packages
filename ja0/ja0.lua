local ffi = require('ffi')
local scanner = require('core.scanner')
local string = require('string')
local target = require('target')

local expected = '8B80????????C1E80B83E007C3'
local content_size = #expected / 2

local buffer_type = ffi.typeof('char[' .. tostring(content_size) .. ']')

local replacement_bytes = {0xB8, 0x04, 0x00, 0x00, 0x00, 0xC3, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90}
assert(#replacement_bytes == content_size, 'Invalid collision check replacement size')

local replacement = buffer_type(replacement_bytes)

local backup
ptr = scanner.scan('74' .. string.format('%02X', content_size) .. '&' .. expected)
if ptr == nil then
    print('JA0: Collision check pointer not found')
else
    -- TODO unload: Remove
    ffi.gc(ptr, function()
        if backup == nil then
            return
        end

        ffi.copy(ptr, backup, content_size)
    end)

    backup = buffer_type()
    ffi.copy(backup, ptr, content_size)
    ffi.copy(ptr, replacement, content_size)
end

coroutine.schedule(function()
    while true do
        local player = target.me
        if player then
            player.freeze = false
            player.display.frozen = false
        end
        coroutine.sleep_frame()
    end
end)
