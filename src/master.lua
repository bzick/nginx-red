--- производим настройку lua. для этого надо настроить пути подгрузки библиотек через package.path
ngx.log(ngx.WARN, "init master")
--- Функция возвращает директория текущего скрипта.
--- Эта директория будет использоваться для постороения путей до пакетов.
--- @return string
local function script_path()
    local str = debug.getinfo(2, "S").source:sub(2):match("(.*/)")
    return str:match("(.*)/")
end

--- настройка путей до пакетов и скриптов самого приложения.
local root_path = script_path()
local vendor_path = root_path .. "/vendor"
--package.path = root_path .. "/red/?.lua;" .. vendor_path .. "/share/lua/5.1/?.lua;".. vendor_path .. "/share/lua/5.1/?/init.lua;;"

--- подгружаем все либы, которые нам нужны
--require("resty.core")
require("red")
local log = require("log")

--- Настраиваем теперь само приложение
--- @type red
local red = red
if not red.cache then
    log.err("Cache dictionary not defined. Please insert 'lua_shared_dict cache 8m;' into your nginx config.")
end
red.reload() -- загружаем первоначальные данные с сервера