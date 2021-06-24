local red = red
local pcall = pcall
local tostring = tostring
local log = require("log")

-- защищаем себя от различных сбоев через pcall
local ok, err = pcall(red.route)
if not ok then
    log.err("Failed to route redirect: " .. tostring(err))
end