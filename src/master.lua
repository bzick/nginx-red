--- подгружаем все либы, которые нам нужны, прогревая кеш и проверя их наличие
require("resty.core")
require("red")
require("MessagePack")
require("resty.lrucache")
require("xml2lua")
local log = require("log")

--- @type red
local red = red
if not red.cache then
    log.err("Cache dictionary not defined. Please insert 'lua_shared_dict cache 8m;' into your nginx config.")
end
red.init() -- загружаем первоначальные данные
log.debug("Master initialized")