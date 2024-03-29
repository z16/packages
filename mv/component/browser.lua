local account = require('account')
local ffi = require('ffi')
local list = require('list')
local string = require('string')
local settings = require('settings')
local table = require('table')
local ui = require('core.ui')
local world = require('world')
local clipboard = require('clipboard')

local state = require('mv.state')
local mv = require('mv.mv')

local display
do
    local defaults = {
        visible = false,
        position = {
            x = 370,
            y = 21,
        },
        size = {
            width = 610,
            height = 490,
        },
        address = '',
        active = false,
    }

    display = settings.load(defaults, 'browser', true)
end

local data = {}

local tonumber = tonumber
local save = settings.save
local init = state.init

local hex_address = mv.hex.address
local hex_raw = mv.hex.raw
local hex_space = mv.hex.space
local hex_zero = mv.hex.zero

-- Adjusting _G to allow arbitrary module loading

setmetatable(_G, {
    __index = function(t, k)
        local ok, res = pcall(require, k)
        if not ok then
            return nil
        end

        rawset(t, k, res)
        return res
    end,
})

-- Public operations

local browser = {}

browser.name = 'browse'

local getters = {}

browser.get_value = function()
    local value = display.address
    local address = tonumber(value, 16)
    if address ~= nil and address > 0 and address <= 0xFFFFFFFF then
        return address
    end

    local getter = getters[value]
    if not getter then
        getter = loadstring('return ' .. value)
        getters[value] = getter
    end

    local ok, result = pcall(getter)
    if ok and type(result) == 'cdata' then
        return value
    end

    return nil
end

browser.running = function()
    return display.active
end

browser.visible = function()
    return display.visible
end

browser.show = function(value)
    display.visible = value

    save('browser')
end

browser.start = function(value)
    data.address = value

    display.active = true
    display.visible = true

    save('browser')
end

browser.stop = function()
    data.address = nil

    display.active = false

    save('browser')
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
    local edit_state = ui.edit_state

    local edit_address = edit_state()

    edit_address.text = display.address

    browser.dashboard = function(layout, pos)
        local active = browser.running()

        pos(0, 0)
        layout:label('[Browsing]{bold 16px} ' .. (active and '[on]{green}' or '[off]{red}'))

        pos(10, 32)
        layout:label('Address')

        pos(60, -4)
        layout:size(280, 23)
        layout:edit(edit_address)
        display.address = edit_address.text
        pos(0, 4)

        pos(10, 30)
        local value = browser.get_value()
        layout:width(90)
        -- TODO
        -- layout:enable(value ~= nil)
        -- if layout:button(active and 'Restart browser' or 'Start browser') then
        if layout:button(active and 'Restart browser' or 'Start browser') and value ~= nil then
            browser.start(value)
        end
        pos(110, 0)
        layout:width(90)
        -- TODO
        -- layout:enable(active)
        -- if layout:button('Stop browser') then
        if layout:button('Stop browser') and active then
            browser.stop()
        end
        pos(210, 0)
        layout:width(90)
        if layout:button('Paste') then
            edit_address.text = clipboard.get()
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

        browser.window = function(layout)
            local address = data.address
            if not address then
                return
            end

            if type(address) == 'string' then
                local ok, result = pcall(getters[address])
                if not ok or result == nil then
                    layout:label('Invalid expression: ' .. address .. ' (' .. tostring(result) .. ')')
                    return
                end

                address = tonumber(ffi_cast('intptr_t', result))
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

            layout:label('[' .. table_concat(lines, '\n') .. ']{Consolas 12px}')

            layout:move(525, 36)
            for i = 1, #offsets do
                local offset = offsets[i]
                if layout:button(offset.label) then
                    data.address = address + offset.value
                end
            end
        end
    end

    browser.button_caption = function()
        return 'MV - Browser'
    end

    browser.button_size = function()
        return 85
    end

    browser.save = function()
        save('browser')
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
