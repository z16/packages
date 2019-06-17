local list = require('list')
local settings = require('settings')
local ui = require('ui')
local windower = require('windower')

local state = require('pv.state')

local defaults = {
    components = {
        'logger',
        'tracker',
        'scanner',
    },
}

local options = settings.load(defaults, 'pv', true)

local components = list(require('pv.dashboard'))
for _, component in ipairs(options.components) do
    components:add(require('component.' .. component))
end

for _, component in pairs(components) do
    local init = component.init
    if init then
        init({
            components = components,
        })
    end
end

local watch = state.watch
local button = ui.button
local location = ui.location
local window = ui.window

local render_window = function(component)
    if not component.visible() then
        return
    end

    local closed
    component.state, closed = window('pv_' .. component.name .. '_window', component.state, component.window)

    if closed then
        component.show(false)
    end
end

local render_button = function(component, x, y)
    local component_button = component.button
    if not component_button then
        return 0
    end

    location(x, y)
    local caption, size = component_button()
    if button('pv_' .. component.name .. '_window_toggle', caption) then
        component.show(not component.visible())
    end
    return size
end

ui.display(function()
    for _, component in pairs(components) do
        render_window(component)
    end

    do
        local x = 10
        local y = windower.settings.client_size.height - 18

        for _, component in pairs(components) do
            x = x + render_button(component, x, y)
        end
    end

    for _, component in pairs(components) do
        if watch(component.state) == 'changed' then
            component.save()
        end
    end
end)
