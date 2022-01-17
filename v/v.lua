local command = require('core.command')
local list = require('list')
local ui = require('core.ui')
local util = require('util')

local expressions = list()

do
    local v = command.new('v')

    local add = function(expression)
        expressions:add({
            label = expression,
            getter = loadstring('return ' .. expression),
        })
    end

    local remove = function(index)
        expressions:remove(index)
    end

    local clear = function()
        expressions:clear()
    end

    v:register('add', add, '<expression:text>')
    v:register('remove', remove, '<index:integer>')
    v:register('clear', clear)
end

setmetatable(_G, {
    __index = function(t, k)
        local ok, res = pcall(require, k)
        if not ok then
            return nil
        end

        rawset(t, k, res)
        return res
    end,
})

local window_state = ui.window_state()
window_state.title = 'Watched values'
window_state.style = 'standard'
window_state.resizable = true
window_state.position.x = 1000
window_state.position.y = 0
window_state.size.height = 400
window_state.size.width = 295

ui.display(function()
    ui.window(window_state, function(layout)
        for index, expression in pairs(expressions) do
            local ok, res = pcall(expression.getter)
            if not ok then
                res = 'Error evaluating expression!' .. res
            else
                if type(res) == 'table' or type(res) == 'cdata' then
                    res = util.vstring(res)
                end

                if res == nil then
                    res = 'nil'
                end
            end

            layout:width(10000)
            layout:label('[' .. tostring(index) .. '] ' .. expression.label .. ':\n    ' .. tostring(res))
        end
    end)
end)
