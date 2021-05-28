local log = ngx.log
-- тут запускаем таймеры, которые будут обновлять XML и списко редиректов с некоторой периодичностью
-- Gets a parser
local xml2lua = require("xml2lua")

ngx.timer.at(5, function ()
    -- Uses a handler that converts the XML to a Lua table
    local handler = require("xmlhandler.tree")
    -- в result будет результат вызова локации @read_urlrewrite: статус, заголовки, тело ответа
    local result = ngx.location.capture("@read_urlrewrite", {
        method = ngx.HTTP_GET
    })
    if result.status ~= 200 then
        ngx.log(ngx.ERR, "Failed to load rewrites: status " .. tostring(result.status))
        return
    end
    ngx.log(ngx.NOTICE, dump_table(result.headers))
    --Instantiates the XML parser
    local parser = xml2lua.parser(handler)
    parser:parse(result.body)
    ngx.log(ngx.NOTICE, dump_table(handler.root))
end)