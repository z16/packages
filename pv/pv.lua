local list = require('list')
local settings = require('settings')
local ui = require('core.ui')
local windower = require('core.windower')

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
local state_changed = state.changed
local window = ui.window

local render_window = function(component)
    if not component.visible() then
        return
    end

    component.state.visible = true
    window(component.state, component.window)

    if not component.state.visible then
        component.show(false)
    end
end

local render_button = function(component, layout, offset)
    local component_button_caption = component.button_caption
    local component_button_size = component.button_size
    if not (component_button_caption and component_button_size) then
        return 0
    end

    layout:move(offset, 0)

    local size = component_button_size()
    layout:width(size)

    local visible_old = component.visible()
    if layout:button(component_button_caption(), visible_old) then
        local visible_new = not visible_old
        component.show(visible_new)
        -- component.state.visible = visible_new
    end

    return size
end

do
    local width = 0
    for _, component in pairs(components) do
        local component_button_size = component.button_size
        if component_button_size then
            width = width + component_button_size()
        end
    end

    local button_panel = ui.window_state()
    button_panel.x = 10
    button_panel.style = 'chromeless'
    button_panel.visible = true
    button_panel.width = width
    button_panel.height = 18

    ui.display(function()
        for _, component in pairs(components) do
            render_window(component)
        end

        button_panel.y = windower.settings.ui_size.height - 18
        window(button_panel, function(layout)
            local offset = 0

            for _, component in pairs(components) do
                offset = offset + render_button(component, layout, offset)
            end
        end)

        for _, component in pairs(components) do
            if watch(component.state) == state_changed then
                component.save()
            end
        end
    end)
end
