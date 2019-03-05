local clipboard = require('clipboard')
local ffi = require('ffi')
local list = require('list')
local os = require('os')
local memory_scanner = require('scanner')
local settings = require('settings')
local string = require('string')
local ui = require('ui')

local state = require('mv.state')
local mv = require('mv.mv')

local display
do
    local defaults = {
        signature = '',
    }

    display = settings.load(defaults, 'scanner.lua', true)
end

local data = {}

local save = settings.save
local init = state.init
local watch = state.watch

local hex_address = mv.hex.address
local hex_zero = mv.hex.zero

local modules = {'FFXiMain.dll', 'polcore.dll', 'polcoreEU.dll'}

-- Public operations

local scanner = {}

scanner.name = 'scan'

do
    local string_match = string.match
    local string_gsub = string.gsub

    scanner.valid = function()
        local signature = string_gsub(display.signature, ' ', '')
        if string_match(signature, '[&*].*[&*]') then
            return false
        end

        signature = string_gsub(signature, '&', '')
        signature = string_gsub(signature, '*', '')

        return #signature % 2 == 0 and string_match(signature, '^[0-9A-Fa-f ?*&]*$') ~= nil
    end
end

scanner.running = function()
    return false
end

scanner.visible = function()
    return display.visible
end

scanner.show = function(value)
    display.visible = value

    save(display)
end

do
    local ffi_cast = ffi.cast
    local scanner_scan = memory_scanner.scan
    local string_format = string.format
    local string_gsub = string.gsub

    local int_ptr = ffi.typeof('intptr_t')

    scanner.start = function()
        local signature = string_gsub(display.signature, ' ', '')
        for _, module in ipairs(modules) do
            local ptr = scanner_scan(display.signature, module)
            if ptr ~= nil then
                data.address = string_format('%.8X', tonumber(ffi_cast(int_ptr, ptr)))
                break
            end
        end

        save(display)
    end
end

-- Command handling

local scan_command = function(text)
    display.address = text

    if scanner.valid() then
        scanner.start()
    end
end

mv.command:register('scan', scan_command, '<signature:text>')

-- UI

do
    local button = ui.button
    local edit = ui.edit
    local location = ui.location
    local size = ui.size
    local text = ui.text
    local window = ui.window

    scanner.dashboard = function(pos)
        pos(10, 50)
        text('[Scanning]{bold 16px}')
        
        pos(20, 32)
        text('Signature')

        pos(78, -2)
        size(272, 23)
        display.signature = edit('mv_scan_signature', display.signature)

        pos(20, 30)
        if button('mv_scan_start', 'Scan', { enabled = scanner.valid() }) then
            scanner.start()
        end

        if data.address then
            pos(105, 2)
            text('Result:')

            pos(146, -2)
            size(70, 23)
            edit('mv_scan_result', data.address, { enabled = false })

            pos(220, 0)
            if button('mv_scan_result_copy', 'Copy') then
                clipboard.set(data.address)
            end
        end
    end

    scanner.state = init(display, {
        title = 'Memory Viewer Scanner',
    })

    scanner.window = function()
    end

    scanner.save = function()
        save(display)
    end
end

return scanner
