local list = require('list')
local settings = require('settings')
local ui = require('ui')

local state = require('pv.state')
local pv = require('pv.pv')

local defaults = {
    visible = false,
    x = 0,
    y = 0,
    width = 360,
    height = 500,
}

local display = settings.load(defaults, 'dashboard.lua', true)

local save = settings.save
local init = state.init
local watch = state.watch

-- Public operations

local dashboard = {}

dashboard.name = 'dashboard'

dashboard.visible = function()
    return display.visible
end

dashboard.show = function(value)
    display.visible = value

    save(display)
end

dashboard.save = function()
    save(display)
end

local components
dashboard.init = function(options)
    components = options.components
end

-- UI

do
    local button = ui.button
    local location = ui.location
    local window = ui.window

    dashboard.state = init(display, {
        title = 'Packet Viewer',
    })

    dashboard.window = function()
        local y_current = 0
        local pos = function(x, y_off)
            y_current = y_current + y_off
            location(x, y_current)
        end

        for _, component in pairs(components) do
            local render_dashboard = component.dashboard
            if render_dashboard then
                render_dashboard(pos)
            end
        end
    end

    dashboard.button = function()
        return 'Packet Viewer', 89
    end

    dashboard.save = function()
        save(display)
    end
end

return dashboard
