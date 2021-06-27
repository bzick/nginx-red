local ngx   = ngx
local utils = require("utils")
local red_debug = os.getenv("RED_DEBUG")
local debug = false
if red_debug and red_debug == "1" then
    debug = true
end

--- Объект логгера
local log = {}

--- Логгирование в error лог nginx-а c уровнем info
function log.info(...)
    ngx.log(ngx.INFO, utils.dump(...))
end

--- Логгирование в error лог nginx-а c уровнем warning
function log.warn(...)
    ngx.log(ngx.WARN, utils.dump(...))
end

--- Логгирование в error лог nginx-а c уровнем error
function log.err(...)
    ngx.log(ngx.ERR, utils.dump(...))
end

--- Отладочное логгирование в error лог nginx-а c уровнем info.
--- Никто в здравом уме не будет включать debug уровень логгирования у nginx — загадит лог мгновенно.
--- Поэтому используется уровень info для отладки приложения.
function log.debug(...)
    ngx.log(ngx.INFO, utils.dump(...))
end

if not debug then
    -- если дебаг не включен то и логгировать отладку не надо
    log.debug = function() end
end

return log