local list = require('list')
local settings = require('settings')
local ui = require('ui')

local state = require('mv.state')
local mv = require('mv.mv')

local defaults = {
    visible = false,
    x = 0,
    y = 526,
    width = 360,
    height = 210,
}

local display = settings.load(defaults, 'dashboard', true)

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
        title = 'Memory Viewer',
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
        return 'Memory Viewer', 96
    end

    dashboard.save = function()
        save(display)
    end
end

return dashboard
