local target = require('target')

coroutine.schedule(function()
    while true do
        local player = target.me
        if player then
            player.freeze = false
            player.display.frozen = false
        end
        coroutine.sleep_frame()
    end
end)
