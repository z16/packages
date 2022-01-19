local list = require('list')
local os = require('os')
local packet = require('packet')
local queue = require('queue')
local settings = require('settings')
local ui = require('core.ui')

local state = require('pv.state')
local pv = require('pv.pv')

local display
do
    local defaults = {
        visible = false,
        position = {
            x = 370,
            y = 21,
        },
        size = {
            width = 960,
            height = 340,
        },
        incoming = {
            pattern = '',
            exclude = false,
        },
        outgoing = {
            pattern = '',
            exclude = false,
        },
        active = false,
    }

    display = settings.load(defaults, 'logger', true)
end

local data = {
    incoming = {
        packets = list(),
        exclude = false,
    },
    outgoing = {
        packets = list(),
        exclude = false,
    },
}

local logged = queue()

local process_pattern = pv.process_pattern
local handle_base_command = pv.handle_base_command
local check_filters = pv.check_filters
local save = settings.save
local init = state.init

local display_incoming = display.incoming
local display_outgoing = display.outgoing
local data_incoming = data.incoming
local data_outgoing = data.outgoing

local tohex = pv.hex.to
local hex_zero_3 = pv.hex.zero_3

-- Public operations

local logger = {}

logger.name = 'log'

logger.valid = function()
    return display_incoming.pattern ~= '' or display_incoming.exclude or display_outgoing.pattern ~= '' or display_outgoing.exclude
end

logger.running = function()
    return display.active
end

logger.visible = function()
    return display.visible
end

logger.show = function(value)
    display.visible = value

    save('logger')
end

logger.start = function()
    data_incoming.packets = process_pattern(display_incoming.pattern)
    data_outgoing.packets = process_pattern(display_outgoing.pattern)
    data_incoming.exclude = display_incoming.exclude
    data_outgoing.exclude = display_outgoing.exclude

    display.active = true
    display.visible = true

    save('logger')
end

logger.stop = function()
    data_incoming.packets = list()
    data_outgoing.packets = list()
    data_incoming.exclude = false
    data_outgoing.exclude = false

    display.active = false

    save('logger')
end

-- Packet handling

do
    local os_date = os.date
    local os_time = os.time

    packet:register(function(p, info)
        if not check_filters(logger, data, p, info) then
            return
        end

        logged:push('[' ..
            os_date('%H:%M:%S', os_time()) ..  '  ' ..
            info.direction .. '  ' ..
            '0x' .. hex_zero_3[info.id] .. '   ' ..
            tohex(info.original, info.original_size) ..
        ']{Consolas}')
        if #logged > 20 then
            logged:pop()
        end
    end)
end

-- Command handling

local log_command = function(direction, ...)
    handle_base_command(logger, display, direction, ...)
end

pv.command:register('log', log_command, '<direction:one_of(i,ni,o,no,b,nb,s)> [ids:number(0x001,0x1FF)]*')

-- Initialization

data_incoming.packets = process_pattern(display_incoming.pattern)
data_outgoing.packets = process_pattern(display_outgoing.pattern)
data_incoming.exclude = display_incoming.exclude
data_outgoing.exclude = display_outgoing.exclude

-- UI

do
    local edit_state = ui.edit_state

    local edit_incoming = edit_state()
    local edit_outgoing = edit_state()

    edit_incoming.text = display_incoming.pattern
    edit_outgoing.text = display_outgoing.pattern

    logger.dashboard = function(layout, pos)
        local active = logger.running()

        pos(0, 0)
        layout:label('[Logging]{bold 16px} ' .. (active and '[on]{green}' or '[off]{red}'))

        pos(10, 30)
        layout:label('Incoming IDs')
        pos(180, 0)
        layout:label('Outgoing IDs')

        pos(10, 20)
        layout:edit(edit_incoming)
        display_incoming.pattern = edit_incoming.text
        pos(180, 0)
        layout:edit(edit_outgoing)
        display_outgoing.pattern = edit_outgoing.text

        pos(10, 30)
        layout:width(160)
        if layout:check('logger_incoming', 'Exclude IDs', display_incoming.exclude) then
            display_incoming.exclude = not display_incoming.exclude
        end
        pos(180, 0)
        layout:width(160)
        if layout:check('logger_outgoing', 'Exclude IDs', display_outgoing.exclude) then
            display_outgoing.exclude = not display_outgoing.exclude
        end

        pos(10, 20)
        layout:width(90)
        -- TODO
        -- layout:enable(logger.valid())
        -- if layout:button(active and 'Restart logger' or 'Start logger') then
        if layout:button(active and 'Restart logger' or 'Start logger') and logger.valid() then
            logger.start()
        end
        pos(110, 0)
        layout:width(90)
        -- TODO
        -- layout:enable(active)
        -- if layout:button('Stop logger') then
        if layout:button('Stop logger') and active then
            logger.stop()
        end
    end

    logger.state = init(display, {
        title = 'Packet Viewer Logger',
    })

    logger.window = function(layout)
        for i = 1, #logged do
            layout:move(0, 16 * (i - 1))
            -- TODO: Remove specific width once non-wrapping layout is enabled
            layout:width(10000)
            layout:label(logged[i])
        end
    end

    logger.button_caption = function()
        return 'PV - Logging'
    end

    logger.button_size = function()
        return 85
    end

    logger.save = function()
        save('logger')
    end
end

return logger
