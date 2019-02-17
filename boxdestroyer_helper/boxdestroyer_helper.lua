local account = require('account')
local command = require('command')
local clipboard = require('clipboard')
local list = require('list')
local os = require('os')
local queue = require('queue')
local resources = require('resources')
local table = require('table')
local world = require('world')
local zone = require('client_data.strings').zone

if account.server.id ~= 0 then
    error('This addon can only be run on a private server with a GM account!')
end

local start = os.clock()

local zones = queue(
    100, -- West Ronfaure
    101, -- East Ronfaure
    102, -- La Theine Plateau
    103, -- Valkurm Dunes
    104, -- Jugner Forest
    105, -- Batallia Downs
    106, -- North Gustaberg
    107, -- South Gustaberg
    108, -- Konschtat Highlands
    109, -- Pashhow Marshlands
    110, -- Rolanberry Fields
    111, -- Beaucedine Glacier
    112, -- Xarcabard
    113, -- Cape Teriggan
    114, -- Eastern Altepa Desert
    115, -- West Sarutabaruta
    116, -- East Sarutabaruta
    117, -- Tahrongi Canyon
    118, -- Buburimu Peninsula
    119, -- Meriphataud Mountains
    120, -- Sauromugue Champaign
    121, -- The Sanctuary of Zi'Tah
    122, -- Ro'Maeve
    123, -- Yuhtunga Jungle
    124, -- Yhoator Jungle
    125, -- Western Altepa Desert
    126, -- Qufim Island
    127, -- Behemoth's Dominion
    128, -- Valley of Sorrows
    130, -- Ru'Aun Gardens
    153, -- The Boyahda Tree
    158, -- Upper Delkfutt's Tower
    159, -- Temple of Uggalepih
    160, -- Den of Rancor
    166, -- Ranguemont Pass
    167, -- Bostaunieux Oubliette
    169, -- Toraimarai Canal
    172, -- Zeruhn Mines
    173, -- Korroloka Tunnel
    174, -- Kuftal Tunnel
    176, -- Sea Serpent Grotto
    177, -- Ve'Lugannon Palace
    178, -- The Shrine of Ru'Avitau
    190, -- King Ranperre's Tomb
    191, -- Dangruf Wadi
    192, -- Inner Horutoto Ruins
    193, -- Ordelle's Caves
    194, -- Outer Horutoto Ruins
    195, -- The Eldieme Necropolis
    196, -- Gusgen Mines
    197, -- Crawlers' Nest
    198, -- Maze of Shakhrami
    200, -- Garlaige Citadel
    204, -- Fei'Yin
    205, -- Ifrit's Cauldron
    208, -- Quicksand Caves
    212, -- Gustav Tunnel
    213  -- Labyrinth of Onzozo
)

local offsets = list(
    { offset =  1, op = 'greater_less' },
    { offset =  2, op = 'failure' },
    { offset =  4, op = 'success' },
    { offset =  5, op = 'second_even_odd' },
    { offset =  6, op = 'first_even_odd' },
    { offset =  7, op = 'range' },
    { offset =  8, op = 'less' },
    { offset =  9, op = 'greater' },
    { offset = 10, op = 'equal' },
    { offset = 11, op = 'second_multiple' },
    { offset = 12, op = 'first_multiple' },
    { offset = 13, op = 'tool_failure' }
)

local messages = list()

local write = function()
    local prefix = list(
        '-- This file was automatically generated',
        '',
        'messages = { -- These dialogue IDs match "You were unable to enter a combination" for the associated zone IDs'
    )

    local infix = list(
        '}',
        '',
        'offsets = {'
    )

    local suffix = list(
        '}',
        ''
    )

    local res = table.concat(prefix
        :concat(messages)
        :concat(infix)
        :concat(offsets:select(function(entry) return '    ' .. entry.op .. ' = ' .. tostring(entry.offset) .. ',' end))
        :concat(suffix)
        :totable(),
        '\n'
    )

    print(res)
    clipboard.set(res)

    print('Done! Result copied to clipboard.')
    print('The whole process took ' .. tostring(os.clock() - start) .. 's.')
end

local next_zone = function()
    command.input('/say !zone ' .. tostring(zones:pop()))
end

local check_zone = function()
    coroutine.schedule(function()
        coroutine.sleep_frame(30)
        local check = 'You were unable to enter a combination.\xEF\xA0\x80'
        for id, message in pairs(zone) do
            if message == check then
                messages:add('    [' .. world.zone.id .. '] = ' .. id .. ',')
                break
            end
        end

        if zones:any() then
            next_zone()
        else
            write()
        end
    end)
end

world.zone_change:register(check_zone)

next_zone()
