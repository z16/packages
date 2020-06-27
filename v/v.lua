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

local window_state = {
    title = 'Watched values',
    style = 'normal',
    x = 1000,
    y = 0,
    height = 400,
    width = 295,
}

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

ui.display(function()
    window_state = ui.window('v', window_state, function()
        for index, expression in pairs(expressions) do
            local ok, res = pcall(expression.getter)
            if not ok then
                res = 'Error evaluating expression!'
            end

            if type(res) == 'table' or type(res) == 'cdata' then
                res = util.vstring(res)
            end

            if res == nil then
                res = 'nil'
            end

            ui.text('[' .. tostring(index) .. '] ' .. expression.label .. ':\n    ' .. tostring(res))
        end
    end)
end)
