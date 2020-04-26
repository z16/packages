local command = require('core.command')
local ffi = require('ffi')

ffi.cdef[[
    void* GetConsoleWindow();
    bool ShowWindow(void*, int);
    bool IsWindowVisible(void*);
]]

local C = ffi.C

local hwnd = C.GetConsoleWindow()

local cw = command.new('cw')

local commands = {
    show = true,
    hide = false,
}
local check = function(command)
    if command == nil then
        return not C.IsWindowVisible(hwnd)
    end

    return commands[command]
end

cw:register(function(command)
    C.ShowWindow(hwnd, check(command) and 5 or 0)
end, '[visible:one_of(show,hide)]')
