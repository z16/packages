local lists = require('lists')
local os = require('os')
local packets = require('packets')
local string = require('string')
local ui = require('ui')
local util = require('util')
local windower = require('windower')

local window_size = windower.settings.client_size

local pv_window = {
    title = 'Packet Viewer',
    style = 'normal',
    x = 0,
    y = 0,
    width = 360,
    height = 260,
    closable = true,
}

local pv_log_window = {}

local pv_track_window = {
    title = 'Packet Viewer Tracker',
    style = 'normal',
    x = 370,
    y = 0,
    width = 490,
    height = 360,
    closable = true,
}

local pv_scan_window = {}

local main_window = {
    show = true,
}

local logging = {}

local tracking = {
    show = false,
    packets_incoming = lists({}),
    packets_outgoing = lists({}),
    pattern_temp_incoming = '23',
    pattern_temp_outgoing = '',
    exclude_incoming = false,
    exclude_outgoing = false,
    exclude_temp_incoming = false,
    exclude_temp_outgoing = false,
}

local tracked = lists({})

local scanning = {}

local process_pattern = function(pattern)
    local parsed = lists({})

    for match in pattern:gmatch('[^%s]+') do
        local single = {}

        local id, rest = match:match('(0?x?%d+)/?(.*)')
        single[1] = tonumber(id)

        for sub in rest:gmatch('[^/]+') do
            local key, value = sub:match('(.*)=\'(.*)\'')
            if value then
                single[key] = value
            else
                key, value = sub:match('(.*)=(.*)')
                single[key] = value == 'true' or value ~= 'false' and tonumber(value) or false
            end
        end

        parsed:add(single)
    end

    return parsed
end

ui.display(function()
    local bottom_x = 10
    local bottom_y = window_size.height - 18

    if main_window.show then
        local closed
        pv_window, closed = ui.window('pv_window', pv_window, function()
            -- Logging
            local is_logging = false

            local y_log = 10
            ui.location(10, y_log + 0)
            ui.text('[Logging]{bold 16px} ' .. (is_logging and '[on]{green}' or '[off]{red}'))

            ui.location(20, y_log + 30)
            ui.text('Not yet implemented...')

            -- Tracking
            local is_tracking = tracking.packets_incoming:any() or tracking.packets_outgoing:any() or tracking.exclude_incoming or tracking.exclude_outgoing

            local y_track = y_log + 60
            ui.location(10, y_track + 0)
            ui.text('[Tracking]{bold 16px} ' .. (is_tracking and '[on]{green}' or '[off]{red}'))

            ui.location(20, y_track + 30)
            ui.text('Incoming IDs')
            ui.location(190, y_track + 30)
            ui.text('Outgoing IDs')

            ui.location(20, y_track + 50)
            tracking.pattern_temp_incoming = ui.edit('pv_log_pattern_incoming', tracking.pattern_temp_incoming)
            ui.location(190, y_track + 50)
            tracking.pattern_temp_outgoing = ui.edit('pv_log_pattern_outgoing', tracking.pattern_temp_outgoing)

            ui.location(18, y_track + 80)
            if ui.check('pv_log_exclude_incoming', 'Exclude IDs', tracking.exclude_temp_incoming) then
                tracking.exclude_temp_incoming = not tracking.exclude_temp_incoming
            end
            ui.location(188, y_track + 80)
            if ui.check('pv_log_exclude_outgoing', 'Exclude IDs', tracking.exclude_temp_outgoing) then
                tracking.exclude_temp_outgoing = not tracking.exclude_temp_outgoing
            end

            ui.location(20, y_track + 100)
            if ui.button('pv_log_start', 'Start tracking') then
                tracking.packets_incoming = process_pattern(tracking.pattern_temp_incoming)
                tracking.packets_outgoing = process_pattern(tracking.pattern_temp_outgoing)
                tracking.exclude_incoming = tracking.exclude_temp_incoming
                tracking.exclude_outgoing = tracking.exclude_temp_outgoing
                tracking.show = true
            end
            ui.location(120, y_track + 100)
            if ui.button('pv_log_stop', 'Stop tracking') then
                tracking.pattern_incoming = ''
                tracking.pattern_outgoing = ''
            end

            -- Scanning
            local is_scanning = scanning.value ~= nil

            local y_scan = y_track + 130
            ui.location(10, y_scan + 0)
            ui.text('[Scanning]{bold 16px} ' .. (is_scanning and '[on]{green}' or '[off]{red}'))
            ui.location(20, y_scan + 30)
            ui.text('Not yet implemented...')
        end)

        if closed then
            main_window.show = false
        end
    end

    if logging.show then
        local closed
        pv_log_window, closed = ui.window('pv_log_window', pv_log_window, function()
        end)

        if closed then
            logging.show = false
        end
    end

    if tracking.show then
        local closed
        pv_track_window, closed = ui.window('pv_track_window', pv_track_window, function()
            if not tracked:any() then
                return
            end

            local p = tracked[index or #tracked]
            local info = p._info
            p._info = nil

            ui.location(10, 10)
            ui.text('[' .. util.hex_table(info.data) .. '\n\n' .. util.vstring(p) .. ']{Consolas 12px}')

            p._info = info
        end)

        if closed then
            tracking.show = false
        end
    end

    if scanning.show then
        local closed
        pv_scan_window, closed = ui.window('pv_scan_window', pv_scan_window, function()
        end)

        if closed then
            scanning.show = false
        end
    end

    do
        ui.location(bottom_x, bottom_y)
        if ui.button('pv_window_maximize', 'Packet Viewer') then
            main_window.show = not main_window.show
        end
        bottom_x = bottom_x + 89
        ui.location(bottom_x, bottom_y)
        if ui.button('pv_log_window_maximize', 'PV - Logging', {enabled = false}) then
            logging.show = not logging.show
        end
        bottom_x = bottom_x + 85
        ui.location(bottom_x, bottom_y)
        if ui.button('pv_track_window_maximize', 'PV - Tracking') then
            tracking.show = not tracking.show
        end
        bottom_x = bottom_x + 85
        ui.location(bottom_x, bottom_y)
        if ui.button('pv_scan_window_maximize', 'PV - Scanning', {enabled = false}) then
            scanning.show = not scanning.show
        end
    end
end)

local check_filter = function(filter, p)
    local info = p._info
    if info.id ~= filter[1] then
        return false
    end

    for key, value in pairs(filter) do
        if key ~= 1 then
            local packet_value = p[key]
            if packet_value ~= value then
                return false
            end
        end
    end

    return true
end

local track_packet = function(p)
    local filters = tracking['packets_' .. p._info.direction]
    if not filters:any(check_filter, p) then
        return
    end

    tracked:add(p)
end

packets:register(function(p)
    -- Logging
    --TODO

    -- Tracking
    track_packet(p)

    -- Scanning
    --TODO
end)
