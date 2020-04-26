local watch
local init
do
    local state_cache = {}

    init = function(options, state)
        state.closable = true
        state.style = 'normal'

        local x = options.x
        local y = options.y
        local width = options.width
        local height = options.height

        state.x = x
        state.y = y
        state.width = width
        state.height = height

        state_cache[state.title] = {
            x = x,
            y = y,
            width = width,
            height = height,
            changed = false,
            compared = 0,
            options = options,
        }
        return state
    end

    local update_cache = function(cached, state)
        local new_x = state.x
        local new_y = state.y
        local new_width = state.width
        local new_height = state.height

        local same =
            cached.x == new_x and
            cached.y == new_y and
            cached.width == new_width and
            cached.height == new_height

        if same then
            return same
        end

        cached.x = new_x
        cached.y = new_y
        cached.width = new_width
        cached.height = new_height

        return same
    end

    watch = function(state)
        local cached = state_cache[state.title]

        local same = update_cache(cached, state)

        if not same then
            cached.changed = true
            cached.compared = 0
            return 'changing'
        end

        if not cached.changed then
            return 'unchanged'
        end

        local compare_count = cached.compared
        if compare_count < 10 then
            cached.compared = compare_count + 1
            return 'changing'
        end

        cached.changed = false
        cached.compared = 0

        local options = cached.options
        options.x = cached.x
        options.y = cached.y
        options.width = cached.width
        options.height = cached.height

        return 'changed'
    end
end

return {
    init = init,
    watch = watch,
}
