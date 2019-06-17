local account = require('account')
local ffi = require('ffi')
local list = require('list')
local string = require('string')
local settings = require('settings')
local table = require('table')
local ui = require('ui')
local world = require('world')

local state = require('mv.state')
local mv = require('mv.mv')

local display
do
    local defaults = {
        visible = false,
        x = 370,
        y = 0,
        width = 600,
        height = 340,
        address = '',
        active = false,
    }

    display = settings.load(defaults, 'browser', true)
end

local data = {}

local save = settings.save
local init = state.init

local hex_address = mv.hex.address
local hex_raw = mv.hex.raw
local hex_space = mv.hex.space
local hex_zero = mv.hex.zero

-- Public operations

local browser = {}

browser.name = 'browse'

browser.valid = function()
    local address = tonumber(display.address, 16)
    return address ~= nil and address > 0 and address < 0xFFFFFFFF
end

browser.running = function()
    return display.active
end

browser.visible = function()
    return display.visible
end

browser.show = function(value)
    display.visible = value

    save(display)
end

browser.start = function()
    data.address = tonumber(display.address, 16)

    display.active = true
    display.visible = true

    save(display)
end

browser.stop = function()
    data.address = nil

    display.active = false

    save(display)
end

-- Command handling

local browse_command = function(address)
    display.address = address

    if browser.valid() then
        browser.start()
    end
end

mv.command:register('browse', browse_command, '<address:integer>')

-- UI

do
    local button = ui.button
    local edit = ui.edit
    local location = ui.location
    local text = ui.text

    browser.dashboard = function(pos)
        local active = browser.running()

        pos(10, 10)
        text('[Browsing]{bold 16px} ' .. (active and '[on]{green}' or '[off]{red}'))

        pos(20, 32)
        text('Address')

        pos(70, -2)
        ui.size(280, 23)
        display.address = edit('mv_browse_address', display.address)

        pos(20, 30)
        if button('mv_browse_start', active and 'Restart browser' or 'Start browser', { enabled = browser.valid() }) then
            browser.start()
        end
        pos(120, 0)
        if button('mv_browse_stop', 'Stop browser', { enabled = active }) then
            browser.stop()
        end
    end

    browser.state = init(display, {
        title = 'Memory Viewer Browser',
    })

    do
        local ffi_cast = ffi.cast
        local ffi_string = ffi.string
        local string_byte = string.byte
        local string_char = string.char
        local string_format = string.format
        local table_concat = table.concat
        local table_insert = table.insert

        local ptr_type = ffi.typeof('void*')

        local lead_lines = {}
        do
            local hex_1 = {}
            local hex_2 = {}
            for i = 0x00, 0x1F do
                hex_1[i] = hex_raw[i % 0x10]
                hex_2[i] = hex_space[i % 0x10]
            end

            for i = 0x0, 0xF do
                lead_lines[i] = '         | ' .. table_concat(hex_2, ' ', i, i + 0xF) .. ' | ' .. table_concat(hex_1, '', i, i + 0xF)
            end
        end

        local lookup_byte = {}
        for i = 0x00, 0xFF do
            lookup_byte[i] = '.'
        end
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

        local offsets = {}
        for i = 0, 4 do
            local value = 0x10^i
            local hex = string_format('0x%x', value)
            table_insert(offsets, 1, {
                name = 'mv_browse_back_' .. hex,
                label = '- ' .. hex,
                value = -value,
            })
            table_insert(offsets, {
                name = 'mv_browse_forward_' .. hex,
                label = '+ ' .. hex,
                value = value,
            })
        end

        browser.window = function()
            local address = data.address
            if not address then
                return
            end

            local lines = list()
            lines:add(lead_lines[address % 0x10])
            lines:add('-----------------------------------------------------------------------------')
            for i = 0x00, 0x1F do
                local line_address = address + i * 0x10
                local line = {string_byte(ffi_string(ffi_cast(ptr_type, line_address), 0x10), 0x01, 0x10)}
                local chars = {}
                for j = 0x01, 0x10 do
                    chars[j] = lookup_byte[line[j]]
                    line[j] = hex_zero[line[j]]
                end
                lines:add(hex_address(line_address) .. ' | ' .. table_concat(line, ' ', 0x01, 0x10) .. ' | ' .. table_concat(chars, '', 0x01, 0x10))
            end

            text('[' .. table_concat(lines, '\n') .. ']{Consolas 12px}')

            location(525, 36)
            for i = 1, #offsets do
                local offset = offsets[i]
                if button(offset.name, offset.label) then
                    data.address = address + offset.value
                end
            end
        end
    end

    browser.button = function()
        return 'MV - Browser', 85
    end

    browser.save = function()
        save(display)
    end
end

-- Initialize

do
    local reset = function()
        browser.stop()
    end

    account.login:register(reset)
    account.logout:register(reset)
    world.zone_change:register(reset)

    reset()
end

return browser
