local ui = require('core.ui')

local ui_window_state = ui.window_state

local state_unchanged = {}
local state_changing = {}
local state_changed = {}

local watch
local init
do
    local state_cache = {}

    init = function(options, state_base)
        local state = ui_window_state()

        state.style = 'standard'
        state.closeable = true
        state.resizable = true

        state.position = options.position
        state.size = options.size

        for key, value in pairs(state_base) do
            state[key] = value
        end

        state_cache[state.title] = {
            position = state.position,
            size = state.size,
            changed = false,
            compared = 0,
            options = options,
        }

        return state
    end

    local update_cache = function(cached, state)
        local new_position = state.position
        local new_size = state.size

        local same =
            cached.position.x == new_position.x and
            cached.position.y == new_position.y and
            cached.size.width == new_size.width and
            cached.size.height == new_size.height

        if same then
            return same
        end

        cached.position = state.position
        cached.size = state.size

        return same
    end

    watch = function(state)
        local cached = state_cache[state.title]

        local same = update_cache(cached, state)

        if not same then
            cached.changed = true
            cached.compared = 0
            return state_changing
        end

        if not cached.changed then
            return state_unchanged
        end

        local compare_count = cached.compared
        if compare_count < 10 then
            cached.compared = compare_count + 1
            return state_changing
        end

        cached.changed = false
        cached.compared = 0

        local options = cached.options
        options.position = cached.position
        options.size = cached.size

        return state_changed
    end
end

return {
    init = init,
    watch = watch,
    unchanged = state_unchanged,
    changing = state_changing,
    changed = state_changed,
}
