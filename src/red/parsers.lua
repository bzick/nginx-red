local type = type
local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local table = table
local tonumber = tonumber
local ngx   = ngx
local log       = require("log")
local xml2lua   = require("xml2lua")
local handler = require("xmlhandler.tree")
local utils     = require("utils")
local varset     = require("varset")

--- @class red.parsers
--- Набор парсеров для разбора языков и правил редиректов.
local parsers = {
    --- Постоянный редирект кодом 301
    REDIRECT_PERM = 1,
    --- Временный редирект кодом 302
    REDIRECT_TEMP = 2,
    --- Изменение URL
    FORWARDING   = 3,
    --- Дополнительное условие на query (тег <condition>)
    COND_QUERY_STRING   = 1
}

--- Парсит список допустимых для URL языки.
--- Метод не использует nginx api, и, как следствие, можно вызвать в любом месте.
--- @param xml string xml данные языков вида
--- @return table|nil в случае успеха
function parsers.config_parser(xml)
    local h = handler:new()
    local parser = xml2lua.parser(h)
    parser:parse(xml)
    --- @type red.config
    local config = {
        langs = nil,
        prefix = nil,
        rules = {},
        variables = {}
    }

    -- Нужно убедиться что конфиг распарсился
    if not h.root or not h.root.urlrewrite then
        log.warn("Invalid XML config")
        return
    end
    local root = h.root.urlrewrite

    if root.langs then -- есть тег <langs>
        if root.langs.lang and type(root.langs.lang) == "table"  then   -- есть "массив" из <lang>
            config.langs = {}
            for _, lang in pairs(root.langs.lang) do
                config.langs[lang] = true
            end
        end
        if root.langs.prefix and type(root.langs.prefix) == "table" then
            config.prefix = {}
            for _, prefix in pairs(root.langs.prefix) do
                -- <prefix type="unlocalized">/store</prefix>:
                -- prefix = {
                --   _attr = {
                --     type = (string) unlocalized
                --   }
                --   [1] = (string) /store
                -- }
                if type(prefix) == "table" and prefix._attr["type"] and prefix._attr["type"] == "unlocalized" then
                    table.insert(config.prefix, prefix[1])
                else
                    log.warn("Invalid prefix rule", prefix)
                end
            end
        end
    end
    if root.config and type(root.config) == "table" then
        if root.config._attr and root.config._attr["param"] then -- это всего одна запись <param>
            parsers.config_param(config, root.config._attr["param"], root.config[1])
        else -- иначе это массив параметров
            for _, c in ipairs(root.config) do
                parsers.config_param(config, c._attr["param"], c[1])
            end
        end
    end
    -- разбор тегов <variable>
    if root.variable and type(root.variable) == "table" then
        if root.variable._attr then -- один элемент <variable>
            config.variables[root.variable._attr["name"]] = parsers.variable(root.variable)
        else -- несколько элементов <variable>
            for _, variable in ipairs(root.variable) do
                config.variables[variable._attr["name"]] = parsers.variable(variable)
            end
        end
    end
    -- Список правил
    -- <urlrewrite>
    --  <rule>
    --    <note>Create date: 16.04.2021</note>
    --    <from>^/search/$</from>
    --    <to type="permanent-redirect">/?s=full</to>
    --  </rule>
    if root.rule and type(root.rule) == "table" then
        for _, v in pairs(root.rule) do
            local rule, err = parsers.build_rule(v)
            if err then
                log.warn(tostring(err) .. " Skip rule", v)
            else
                table.insert(config.rules, rule)
            end
        end
    end

    return config
end

--- @param config red.config
--- @param param string
--- @param value string
function parsers.config_param(config, param, value)
    if param == "rules" then
        config.rules_path = value
    elseif param == "reload-timeout" then
        config.check_timeout = tonumber(value) or 10
    end
end

--- Перепаковывает таблицу от <variable>
--- @param variable table распашенный тег <variable>
--- @return table
function parsers.variable(variable)
    local var = {
        name = variable._attr["name"],
        default = variable._attr["default"],
        loaders = {}
    }
    for name, value in pairs(variable) do
        table.insert(var.loaders, {name = name, value = value})
    end
    return var
end

--- Собирает правило из кусков XML данных.
--- Вынесено из parser_rules() для удобства возврата ошибки, а то в luajit нет continue.
--- @param v table распаршенный вариант XML
--- @return red.rule собраное правило, nil если были ошибки при сборке
--- @return string ошибка если правило кривое
function parsers.build_rule(v)
    --- @type red.rule
    local rule = {}
    rule.valid = true
    rule.opts = "i"
    rule.to_has_query = false
    rule.auto_lang_prefix = true
    rule.query_append = true
    rule.to_type = parsers.REDIRECT_TEMP
    -- обрабатываем различные варианты тега <to ...>...</to>. Возможные варинаты:
    -- <to>/some/path.html</to>
    -- <to type="permanent-redirect">/some/path.html</to>
    -- <to type="temporary-redirect">/some/path.html</to>
    -- <to auto-lang-prefix="false">/pt-br//some/path.html</to>
    -- <to qsappend="false">/$1/path.html</to>
    if type(v.to) == "string" then -- тег без атрибутов
        rule.to = v.to
    elseif type(v.to) == "table" and v.to[1] then -- тег с атрибутами
        rule.to = v.to[1]
        if v.to._attr then
            if v.to._attr["type"] == "permanent-redirect" then -- атрибут type
                rule.to_type = parsers.REDIRECT_PERM
            elseif v.to._attr["type"] == "forwarding" then
                rule.to_type = parsers.FORWARDING
            elseif v.to._attr["type"] == "temporary-redirect" then
                rule.to_type = parsers.REDIRECT_TEMP
            end
            if v.to._attr["auto-lang-prefix"] == "false" then -- атрибут auto-lang-prefix
                rule.auto_lang_prefix = false
            end
            if v.to._attr["qsappend"] == "false" then -- атрибут qsappend
                rule.query_append = false
            end
        end
    else
        return nil, "Invalid 'rule.to' field format."
    end
    -- исправляем URL которые начинаются с // на https://
    if rule.to:sub(1,2) == "//" then
        rule.to = "https:" .. rule.to
    end
    -- проверяем что to поле может уже иметь query параметры
    if rule.to:find("?", 1, true) ~= nil then
        rule.to_has_query = true
    end

    -- обрабатываем различные варианты тега <from ...>...</from>. Возможные варинаты:
    -- <from>^/some/path.html$</from>
    -- <from casesensitive="true">^/some/.*$</from>
    if type(v.from) == "string" then -- тег без атрибутов
        rule.from = v.from
    elseif type(v.from) == "table" and v.from[1] then -- тег с атрибутами
        rule.from = v.from[1]
        if v.from._attr then
            if v.from._attr["casesensitive"] == "true" then -- флаг чувстивтельности к регистру <from casesensitive="true">
                rule.opts = nil
            end
        end
    else
        return nil, "Invalid tag 'rule.from' field format."
    end

    -- обрабатываем различные варианты тега <condition ...>...</condition>. Возможные варинаты:
    -- <condition type="query-string">.*Keyword.*</condition>
    if v.condition and type(v.condition) == "table" then  -- тег с атрибутами
        if v.condition._attr and v.condition[1] then -- проверяем что сигнатура верна, есть и аттрибуы и значение тега
            rule.cond = v.condition[1]
            if v.condition._attr.type == "query-string" then
                rule.cond_type = parsers.COND_QUERY_STRING
            else
                return nil , "Invalid rule.condition[query-string]: '" .. rule.cond_type
            end
            -- нужно проверить регулярое выражение для condition
            local _, err = ngx.re.match("test", rule.cond)
            if err then
                return nil, "Invalid regex rule.condition '" .. rule.from .. "': " .. tostring(err)
            end
        end
    end
    -- перед укладкой правила надо протестировать заранее регулярное выражение
    local _, err = ngx.re.match("test", rule.from)
    if err then
        return nil, "Invalid regex rule.from '" .. rule.from .. "': " .. tostring(err)
    end

    return rule, nil
end


return parsers