local clipboard = require('clipboard')
local ffi = require('ffi')
local memory_scanner = require('core.scanner')
local settings = require('settings')
local string = require('string')
local ui = require('core.ui')

local state = require('mv.state')
local mv = require('mv.mv')

local display
do
    local defaults = {
        visible = false,
        signature = '',
    }

    display = settings.load(defaults, 'scanner', true)
end

local data = {
    address = nil,
    address_changed = false,
}

local tonumber = tonumber
local save = settings.save
local init = state.init

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

    save('scanner')
end

do
    local ffi_cast = ffi.cast
    local scanner_scan = memory_scanner.scan
    local string_format = string.format
    local string_gsub = string.gsub

    local int_ptr = ffi.typeof('intptr_t')

    scanner.start = function()
        local signature = string_gsub(display.signature, ' ', '')
        for i = 1, #modules do
            local module = modules[i]
            local ptr = scanner_scan(signature, module)
            if ptr ~= nil then
                data.address = string_format('%.8X', tonumber(ffi_cast(int_ptr, ptr)))
                data.address_changed = true
                break
            end
        end

        save('scanner')
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
    local edit_state = ui.edit_state

    local edit_signature = edit_state()
    local edit_address = edit_state()

    edit_signature.text = display.signature
    edit_address.text = ''

    scanner.dashboard = function(layout, pos)
        pos(0, 40)
        layout:label('[Scanning]{bold 16px}')

        pos(10, 32)
        layout:label('Signature')

        pos(68, -4)
        layout:size(272, 23)
        layout:edit(edit_signature)
        display.signature = edit_signature.text
        pos(0, 4)

        pos(10, 30)
        layout:width(90)
        if layout:button('Scan') and scanner.valid() then
            scanner.start()
        end

        if data.address then
            pos(105, 5)
            layout:label('Result:')

            pos(146, -4)
            layout:size(70, 23)
            -- TODO: Disabled edit box
            if data.address_changed then
                edit_address.text = data.address
                data.address_changed = false
            end
            layout:edit(edit_address)
            pos(0, 4)

            pos(220, -5)
            layout:width(90)
            if layout:button('Copy') then
                clipboard.set(data.address)
            end
        end
    end

    scanner.window = function()
    end

    scanner.save = function()
        save('scanner')
    end
end

return scanner
