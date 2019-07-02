local list = require('list')
local os = require('os')
local packets = require('packets')
local queue = require('queue')
local settings = require('settings')
local ui = require('ui')

local state = require('pv.state')
local pv = require('pv.pv')

local display
do
    local defaults = {
        visible = false,
        x = 370,
        y = 0,
        width = 960,
        height = 340,
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

    packets:register(function(packet, info)
        if not check_filters(logger, data, packet, info) then
            return
        end

        logged:push('[' ..
            os_date('%H:%M:%S', os_time()) .. '  ' ..
            info.direction .. '  ' ..
            '0x' .. hex_zero_3[info.id] .. '   ' ..
            tohex(info.data) ..
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
    local button = ui.button
    local check = ui.check
    local edit = ui.edit
    local location = ui.location
    local text = ui.text

    logger.dashboard = function(pos)
        local active = logger.running()

        pos(10, 10)
        text('[Logging]{bold 16px} ' .. (active and '[on]{green}' or '[off]{red}'))

        pos(20, 30)
        text('Incoming IDs')
        pos(190, 0)
        text('Outgoing IDs')

        pos(20, 20)
        display_incoming.pattern = edit('pv_log_pattern_incoming', display_incoming.pattern)
        pos(190, 0)
        display_outgoing.pattern = edit('pv_log_pattern_outgoing', display_outgoing.pattern)

        pos(18, 30)
        if check('pv_log_exclude_incoming', 'Exclude IDs', display_incoming.exclude) then
            display_incoming.exclude = not display_incoming.exclude
        end
        pos(188, 0)
        if check('pv_log_exclude_outgoing', 'Exclude IDs', display_outgoing.exclude) then
            display_outgoing.exclude = not display_outgoing.exclude
        end

        pos(20, 20)
        if button('pv_log_start', active and 'Restart logger' or 'Start logger', { enabled = logger.valid() }) then
            logger.start()
        end
        pos(120, 0)
        if button('pv_log_stop', 'Stop logger', { enabled = active }) then
            logger.stop()
        end
    end

    logger.state = init(display, {
        title = 'Packet Viewer Logger',
    })

    logger.window = function()
        for i = 1, #logged do
            location(10, 16 * (i - 1) + 10)
            text(logged[i])
        end
    end

    logger.button = function()
        return 'PV - Logging', 85
    end

    logger.save = function()
        save('logger')
    end
end

return logger
