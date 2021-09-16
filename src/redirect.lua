local red = red
local xpcall = xpcall
local tostring = tostring
local log = require("log")
local traceback = debug.traceback

-- защищаем себя от различных сбоев через pcall
xpcall(red.route, function(err)
    if log.is_debug then
        log.err("Failed to route redirect: " .. tostring(err) .. ". Traceback: " .. traceback())
    else
        log.err("Failed to route redirect: " .. tostring(err))
    end
end)