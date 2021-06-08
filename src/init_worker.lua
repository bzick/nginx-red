-- тут запускаем таймеры, которые будут обновлять XML и списко редиректов с некоторой периодичностью
local xml2lua = require("xml2lua")
local redirect_file = os.getenv("REDIRECT_FILE")

ngx.log(ngx.ERR, "starting timer in worker for file " .. (redirect_file or "<none>"))
local _, err = ngx.timer.every(5, function ()
    -- Uses a handler that converts the XML to a Lua table
    local handler = require("xmlhandler.tree")
    local file = io.open(redirect_file, "r")
    if not file then
        ngx.log(ngx.WARN, "File " .. redirect_file .. " not found")
        return
    end
    local xml_data = file:read("*all")
    if not xml_data then
        ngx.log(ngx.WARN, "File " .. redirect_file .. " is empty")
        return
    end
    -- в result будет результат вызова локации @read_urlrewrite: статус, заголовки, тело ответа

    ngx.log(ngx.NOTICE, dump_table(xml_data))
    --Instantiates the XML parser
    local parser = xml2lua.parser(handler)
    parser:parse(result.body)
    ngx.log(ngx.NOTICE, dump_table(handler.root))
end)

if err then
    ngx.log(ngx.ERR, "Failed to start timer", err)
end