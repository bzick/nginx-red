local type = type
local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local table = table
local ngx   = ngx
local log       = require("log")
local xml2lua   = require("xml2lua")
local handler = require("xmlhandler.tree")
local utils     = require("utils")


--- @class red.parsers
--- Набор парсеров для разбора языков и правил редиректов.
local parsers = {
    --- Постоянный редирект кодом 301
    REDIRECT_PERM = 1,
    --- Временный редирект кодом 302
    REDIRECT_TEMP = 2,
    --- Изменение URL
    REWRITE_URL   = 3,
    --- Дополнительное условие на query (тег <condition>)
    COND_QUERY_STRING   = 1
}

--- Парсит список допустимых для URL языки.
--- Метод не использует nginx api, и, как следствие, можно вызвать в любом месте.
--- <langs><lang>ru-ru</lang></langs>
--- @param xml string xml данные языков вида
--- @return table|nil в случае успеха
function parsers.langs_parser(xml)
    local h = handler:new()
    local parser = xml2lua.parser(h)
    parser:parse(xml)

    if h.root                    -- есть рутовый элемент
        and h.root.langs         -- есть тег <langs>
        and h.root.langs.lang    -- есть "массив" из <lang>
        and type(h.root.langs.lang) == "table" then

        local langs = {}
        for _, lang in pairs(h.root.langs.lang) do
            langs[lang] = true
        end
        return langs
    else
        log.warn("failed to parse XML of languages")
    end
end

--- Загружает правила редиректов из XML файла.
--- Метод не использует nginx api, и, как следствие, можно вызвать в любом месте.
--- @param xml string XML с правилами
--- @return table
function parsers.rules_parser(xml)
    local h = handler:new()
    local parser = xml2lua.parser(h)
    parser:parse(xml)
    xml = nil -- высвобождем память
    -- проверяем что xml вообще распарсился и в нём есть массив <rule>
    -- handler.root — является корневым элементов всего xml. Пример xml:
    -- <?xml version="1.0" encoding="UTF-8"?>
    -- <urlrewrite>
    --  <rule>
    --    <note>Create date: 16.04.2021</note>
    --    <from>^/search/$</from>
    --    <to type="permanent-redirect">/?s=full</to>
    --  </rule>
    --  ...
    -- </urlrewrite>
    if h.root                         -- есть рутовый элемент
            and h.root.urlrewrite         -- есть тег <urlrewrite>
            and h.root.urlrewrite.rule    -- есть "массив" из <rule>
            and type(h.root.urlrewrite.rule) == "table" then

        local rules = {}

        for _, v in pairs(h.root.urlrewrite.rule) do
            local rule, err = parsers.build_rule(v)
            if err then
                log.warn(tostring(err) .. " Skip rule", v)
            else
                table.insert(rules, rule)
            end
        end
        return rules
    else
        log.warn("failed to parse XML of rules")
    end
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
    rule.case_sensitive = false
    rule.to_type = parsers.REDIRECT_TEMP
    -- обрабатываем различные варианты тега <to ...>...</to>. Возможные варинаты:
    -- <to>/legal/docs/youtrack/youtrack_incloud.html</to>
    -- <to type="permanent-redirect">/company/customers/experience/</to>
    -- <to type="temporary-redirect">/products/</to>
    -- <to auto-lang-prefix="false">/pt-br/lp/devecosystem-2020/</to>
    -- <to qsappend="false">/$1/documentation/documentation.html</to>
    if type(v.to) == "string" then -- тег без атрибутов
        rule.to = v.to
    elseif type(v.to) == "table" and v.to[1] then -- тег с атрибутами
        rule.to = v.to[1]
        if v.to._attr then
            if v.to._attr["type"] == "permanent-redirect" then -- атрибут type
                rule.to_type = parsers.REDIRECT_PERM
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
    -- <from>^/search/$</from>
    -- <from casesensitive="true">^/(dotTrace|dottrace).*$</from>
    -- <from languages="pt-pt">^/lp/devecosystem-2020/$</from>
    if type(v.from) == "string" then -- тег без атрибутов
        rule.from = v.from
    elseif type(v.from) == "table" and v.from[1] then -- тег с атрибутами
        rule.from = v.from[1]
        if v.from._attr then
            if v.from._attr["casesensitive"] == "true" then -- флаг чувстивтельности к регистру <from casesensitive="true">
                rule.opts = nil
            end
            if v.from._attr["languages"] then -- есть условия на языки <from languages="pt-pt">
                for _, l in ipairs(utils.split(v.from._attr["languages"], ", ")) do
                    if not rule.languages then
                        rule.languages = {}
                    end
                    rule.languages[l] = true -- складываем языки хеш-таблицей, что бы потом быстрее искать
                end
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