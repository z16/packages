local string = require('string')
local ui = require('ui')
local util = require('util')

account = require('account')
equipment = require('equipment')
items = require('items')
linkshell = require('linkshell')
memory = require('memory')
player = require('player')
target = require('target')
treasure = require('treasure')
world = require('world')

local expressions = {
}

for i, expression in ipairs(expressions) do
    expressions[i] = {
        label = expression,
        getter = loadstring('return ' .. expression),
    }
end

local window_state = {
    title = 'Watched values',
    style = 'normal',
    x = 1100,
    y = 0,
    height = 900,
    width = 324,
}

ui.display(function()
    window_state = ui.window('v', window_state, function()
        for _, expression in ipairs(expressions) do
            local ok, res = pcall(expression.getter)
            if type(res) == 'table' or type(res) == 'cdata' then
                res = util.vstring(res)
            end
            ui.text(expression.label .. ': ' .. (ok and res or '-'))
        end
    end)
end)
