local settings = require('settings')

local state = require('mv.state')

local defaults = {
    visible = false,
    position = {
        x = 5,
        y = 547,
    },
    size = {
        width = 355,
        height = 474,
    },
}

local display = settings.load(defaults, 'dashboard', true)

local pairs = pairs
local save = settings.save
local init = state.init

-- Public operations

local dashboard = {}

dashboard.name = 'dashboard'

dashboard.visible = function()
    return display.visible
end

dashboard.show = function(value)
    display.visible = value

    save('dashboard')
end

dashboard.save = function()
    save('dashboard')
end

local components
dashboard.init = function(options)
    components = options.components
end

-- UI

do
    dashboard.state = init(display, {
        title = 'Memory Viewer',
    })

    dashboard.window = function(layout)
        local y_current = 0
        local pos = function(x, y_off)
            y_current = y_current + y_off
            layout:move(x, y_current)
        end

        for _, component in pairs(components) do
            local render_dashboard = component.dashboard
            if render_dashboard then
                render_dashboard(layout, pos)
            end
        end
    end

    dashboard.button_caption = function()
        return 'Memory Viewer'
    end

    dashboard.button_size = function()
        return 96
    end

    dashboard.save = function()
        save('dashboard')
    end
end

return dashboard
