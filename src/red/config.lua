local type = type
local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local table = table
local tonumber = tonumber
local io    = io
local ngx   = ngx
local log       = require("log")
local xml2lua   = require("xml2lua")
local handler = require("xmlhandler.tree")
local utils     = require("utils")
local varset     = require("varset")

--- @class red.rule псевдо-тип нужен для хинтов по правилам
--- @field from string правило совпадения URI, регулярка
--- @field opts string флаги регулярки, обычно это "i"
--- @field to string правела замещение URI для редиректа или forwarding
--- @field to_type string действие при совпадении правила: редирект или forwarding
--- @field to_has_query boolean to поле имеет параметры запроса (имеет ?)
--- @field cond string
--- @field cond_type string
--- @field auto_lang_prefix boolean
--- @field absolute boolean это абсолютная урла на другой ресурс
--- @field query_append boolean прикреплять параметры запроса (после ?) к редиректу/реврайту

--- @class red.locale
--- @field langs table<string,boolean>
--- @field prefix string[]

--- @class red.config конфигурация red сервера
--- @field prefix string[] массив префиксов, которые должны откинуть свой префикс языка.
--- @field rules_path string дополнительный файл откуда брать другие правила, если путь не указан или файла нет - берутся дефолтные правила из конфига
--- @field langs_path string дополнительный файл откуда брать языки, если путь не указан или файла нет - берутся дефолтные языки из конфига
--- @field dynamic_mode boolean импорт включает в себя динамические подстановки в langs_path и/или rules_path
--- @field check_timeout number как часто проверять изменения файлов
--- @field rules red.rule[] список правил
--- @field locale red.locale список правил
--- @field variables red.varset набор переменных
local config = {
    --- Постоянный редирект кодом 301
    REDIRECT_PERM = 1,
    --- Временный редирект кодом 302
    REDIRECT_TEMP = 2,
    --- Изменение URL
    FORWARDING   = 3,
    --- Дополнительное условие на query (тег <condition>)
    COND_QUERY_STRING   = 1
}
local meta = { __index = config }

function config.new()
    return setmetatable({
        prefix  = nil,
        rules_path = nil,
        langs_path = nil,
        dynamic_mode = false,
        check_timeout = 10,
        rules = {},
        root_path = nil,
        locale = {
            langs = {},
            prefix = {}
        },
        variables = varset:new()
    }, meta)
end

--- Добавляет языковый префикс
--- @param name string сам префикс, например ru-ru, en-us
function config:add_lang(name)
    self.locale.langs[name] = true
end

--- Добавляет язковую настройку по началу URL
--- @param name string префикс URL, например /store, /help
function config:add_lang_prefix(name)
    table.insert(self.locale.prefix, name)
end

--- Задаёт корневой путь относительно которого будет производиться загрузка файлов в конфиге.
--- @param root_path string
function config:set_root_path(root_path)
    self.root_path = root_path
end

--- Читает и парсит XML конфиг файл
--- Всё спаршенное раскидывает по свойствам объекта
--- @param path string путь до файла
--- @return string|nil возвращает ошибку либо nil, если без ошибок
function config:parse_xml_file(path)
    local file, err = io.open(path, "r")
    if not file then
        return "failed to open file " .. path .. ": " .. tostring(err or "no error")
    end
    local data = file:read("*all") -- вычитываем всё из файла специальным флагом
    file:close()
    if data == "" then
        return "file ".. tostring(path) .. " is empty"
    end

    return self:parse_xml(data)
end

--- Парсит XML конфигурацию
--- Метод не использует nginx api, и, как следствие, можно вызвать в любом месте.
--- @param xml string xml данные языков вида
--- @return string|nil строка с ошибкой, если она произошла
function config:parse_xml(xml)
    local h = handler:new()
    local parser = xml2lua.parser(h)
    parser:parse(xml)

    -- Нужно убедиться что конфиг распарсился
    if not h.root or not h.root.urlrewrite then
        return "Invalid XML config"
    end
    local root = h.root.urlrewrite

    if root.langs then -- есть тег <langs>
        if root.langs.lang then   -- есть "массив" из <lang>
            if type(root.langs.lang) == "table" then
                for _, lang in pairs(root.langs.lang) do
                    self:add_lang(lang)
                end
            elseif type(root.langs.lang) == "string" then
                self:add_lang(root.langs.lang)
            end
        end
        if root.langs.prefix and type(root.langs.prefix) == "table" then
            for _, prefix in pairs(root.langs.prefix) do
                -- <prefix type="unlocalized">/store</prefix>:
                -- prefix = {
                --   _attr = {
                --     auto-lang-prefix = (string) false
                --   }
                --   [1] = (string) /store
                -- }
                if type(prefix) == "table" and prefix._attr["auto-lang-prefix"] and prefix._attr["auto-lang-prefix"] == "false" then
                    self:add_lang_prefix(prefix[1])
                else
                    log.warn("Invalid prefix rule", prefix)
                end
            end
        end
    end
    if root.config and type(root.config) == "table" then
        if root.config._attr and root.config._attr["param"] then -- это всего одна запись <param>
            self:set_param(root.config._attr["param"], root.config[1])
        else -- иначе это массив параметров
            for _, c in ipairs(root.config) do
                self:set_param(c._attr["param"], c[1])
            end
        end
    end
    -- разбор тегов <variable>
    if root.variable and type(root.variable) == "table" then
        if root.variable._attr then -- один элемент <variable>
            self:add_variable(root.variable._attr["name"], root.variable._attr["default"], root.variable)
        else -- несколько элементов <variable>
            for _, variable in ipairs(root.variable) do
                self:add_variable(variable._attr["name"], variable._attr["default"], variable)
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
            local rule, err = config.build_rule_from_xml(v)
            if err then
                log.warn(tostring(err) .. " Skip rule", v)
            else
                table.insert(self.rules, rule)
            end
        end
    end
    return nil
end

--- Разбирает различные значения параметров [param] конфига
--- @param config red.config
--- @param param string
--- @param value string
function config:set_param(param, value)
    if param == "rules" then
        if value:sub(1,1) == "/" then
            self.rules_path = value
        elseif self.root_path then
            self.rules_path = self.root_path .. "/" .. value
        end
        if varset.has_placeholders(self.rules_path) then
            self.dynamic_mode = true
        end
    elseif param == "langs" then
        if value:sub(1,1) == "/" then
            self.langs_path = value
        elseif self.root_path then
            self.langs_path = self.root_path .. "/" .. value
        end
        if varset.has_placeholders(self.langs_path) then
            self.dynamic_mode = true
        end
    elseif param == "reload-timeout" then
        self.check_timeout = tonumber(value) or 10
    end
end

--- Перепаковывает таблицу от <variable> в массив переменных
--- @param vars red.varset массив переменных
--- @param variable table распашенный тег <variable>
function config:add_variable(name, default, loaders)
    if not name then
        return
    end
    local var = self.variables:add_variable(name, default)
    for from, what in pairs(loaders) do
        var:add_loader(from, what)
    end
end

--- Собирает правило из кусков XML данных.
--- Вынесено из parser_rules() для удобства возврата ошибки, а то в luajit нет continue.
--- @param v table распаршенный вариант XML
--- @return red.rule собраное правило, nil если были ошибки при сборке
--- @return string ошибка если правило кривое
--- @private
function config.build_rule_from_xml(v)
    --- @type red.rule
    local rule = {}
    rule.valid = true
    rule.opts = ""
    --rule.opts = "i"
    rule.to_has_query = false
    rule.auto_lang_prefix = true
    rule.query_append = true
    rule.absolute = false
    rule.to_type = config.REDIRECT_TEMP
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
                rule.to_type = config.REDIRECT_PERM
            elseif v.to._attr["type"] == "forwarding" then
                rule.to_type = config.FORWARDING
            elseif v.to._attr["type"] == "temporary-redirect" then
                rule.to_type = config.REDIRECT_TEMP
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
        rule.absolute = true
    elseif rule.to:sub(1,5) == "http:" or rule.to:sub(1,6) == "https:" then -- проверяем что это абсолютные урлы
        rule.absolute = true
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
                rule.cond_type = config.COND_QUERY_STRING
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


return config