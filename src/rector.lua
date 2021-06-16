local xml2lua = require("xml2lua")
local ngx = ngx
local cjson = require("cjson.safe")
local utils = require("utils")
local cache = ngx.shared["urlrewrite_cache"] or nil

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

--- @class rector.rule псевдо-тип нужен для хинтов
--- @field note string
--- @field valid boolean флаг обозначает что правило составлено правильно и готово к использованию
--- @field from string
--- @field opts string
--- @field to string
--- @field to_type string
--- @field to_has_query boolean to поле имеет параметры запроса (имеет ?)
--- @field cond string
--- @field cond_type string
--- @field auto_lang_prefix boolean
--- @field case_sensitive boolean
--- @field languages table языки, которые вначале
--- @field query_append boolean прикреплять параметры запроса (после ?) к редиректу/реврайту

--- Типы поведения при совпадении правила
--- Постоянный редирект кодом 301
local REDIRECT_PERM = 1
--- Временный редирект кодом 302
local REDIRECT_TEMP = 2
--- Изменение URL
local REWRITE_URL   = 3
--- Дополнительное условие на query (тег <condition>)
local COND_QUERY_STRING   = 1

local CACHE_KEY_WATCHER_LOCK = "watcher:lock"
local CACHE_KEY_RULES_MODIFIED = "rules:mtime"
local CACHE_KEY_RULES_DATA = "rules:data"
local CACHE_KEY_LANGS_MODIFIED = "langs:mtime"
local CACHE_KEY_LANGS_DATA = "langs:data"

--- @type table
--- @field rules rector.rule[] список правил
--- @field cache userdata nginx кеш
--- @field langs table<string,boolean> хеш-таблица языков
local rector = {
    rules = { },
    langs = { },
    cache = cache,
    rules_modified = 0,
    langs_modified = 0,
}

--- Так как у nginx и lua нет какого-либо filewatcher то будем проверять файлы на изменение раз в timeout секунд
--- @param timeout number количество секунд между проверками файла
function rector.file_watcher(timeout, rules_path, langs_path)
    local wait_time = 1
    if wait_time >= timeout then
        timeout = timeout / 2
    end
    local _, err = ngx.timer.every(timeout, function()
        -- Выставляем блокировку на эксклюзивный доступ к файловой системе.
        -- Другие воркеры должны вернутся позже за результатом.
        -- Блокировка ставится на половину времени от timeout что бы следующий воркер мог взяться за дело.
        local ok = rector.cache:add(CACHE_KEY_WATCHER_LOCK, 1, timeout / 2)
        if ok then
            -- так как получили эксклюзивную блокировку то начинаем обновление
            if utils.get_file_mtime(rules_path) ~= rector.cache:get(CACHE_KEY_RULES_MODIFIED) then
                -- используем pcall для безопасного вызова метода, даже если там произойдёт паника
                local success, err = pcall(rector.load_rules, rules_path)
                if not success then
                    log.err("Failed to load rules from " .. rules_path .. ": " .. tostring(err))
                else
                    rector.rules_modified = ngx.now()
                    rector.cache:set(CACHE_KEY_RULES_MODIFIED, rector.rules_modified)
                    rector.cache:set(CACHE_KEY_RULES_DATA, cjson.encode(rector.rules))
                end
            end
            if utils.get_file_mtime(langs_path) ~= rector.cache:get(CACHE_KEY_LANGS_MODIFIED) then
                -- используем pcall для безопасного вызова метода, даже если там произойдёт паника
                local success, err = pcall(rector.load_langs, langs_path)
                if not success then
                    log.err("Failed to load langs from " .. rules_path .. ": " .. tostring(err))
                else
                    rector.langs_modified = ngx.now()
                    rector.cache:set(CACHE_KEY_LANGS_MODIFIED, rector.langs_modified)
                    rector.cache:set(CACHE_KEY_LANGS_DATA, cjson.encode(rector.langs))
                end
            end
            rector.cache:delete(CACHE_KEY_WATCHER_LOCK)
        else
            ngx.sleep(wait_time)
            local rules_modified = rector.cache:get(CACHE_KEY_RULES_MODIFIED)
            if not rector.rules_modified or rector.rules_modified ~= rules_modified then
                local data  = rector.cache:get(CACHE_KEY_RULES_DATA)
                if data then
                    local rules = cjson.decode(data)
                    if rules then
                        rector.rules = rules
                        rector.rules_modified = rules_modified
                    end
                end
            end
            local langs_modified = rector.cache:get(CACHE_KEY_LANGS_MODIFIED)
            if not rector.langs_modified or rector.langs_modified ~= langs_modified then
                local data  = rector.cache:get(CACHE_KEY_LANGS_DATA)
                if data then
                    local langs = cjson.decode(data)
                    if langs then
                        rector.langs = langs
                        rector.langs_modified = langs_modified
                    end
                end
            end
        end
    end)
    if err then
        log.err("Failed to setup timer: " .. tostring(err))
    end
end

--- Загружает доступные языки с файловой системы.
--- Метод не использует nginx api, и, как следствие, можно вызвать в любом месте.
--- @param langs_path string json файл языков вида ["ru-ru", "en-us", ...]
function rector.load_langs(langs_path)
    local file = io.open(langs_path, "r")
    if not file then
        log.warn("File with languages " .. langs_path .. " not found")
        return
    end
    local json = file:read("*all")
    json = cjson.decode(json)
    if not json then
        log.warn("No one language found or invalid json (file " .. langs_path .. ")")
        return
    end
    local langs = {}
    for _, lang in pairs(json) do
        langs[lang] = true
    end
    log.info("Loaded languages from " .. langs_path .. ":", langs)
    rector.langs = langs
end

--- Загружает правила редиректов из XML файла.
--- Метод не использует nginx api, и, как следствие, можно вызвать в любом месте.
--- @param rules_path string полный путь до XML с правилами
function rector.load_rules(rules_path)
    local handler = require("xmlhandler.tree")
    local file = io.open(rules_path, "r")
    if not file then
        log.warn("File " .. rules_path .. " not found")
        return
    end
    local xml_data = file:read("*all")
    if not xml_data then
        log.warn("File " .. rules_path .. " is empty")
        return
    end
    local parser = xml2lua.parser(handler)
    parser:parse(xml_data)
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
    if handler.root                         -- есть рутовый элемент
        and handler.root.urlrewrite         -- есть тег <urlrewrite>
        and handler.root.urlrewrite.rule    -- есть "массив" из <rule>
        and type(handler.root.urlrewrite.rule) == "table" then

        local rules = {}
        for _, v in pairs(handler.root.urlrewrite.rule) do
            --- @type rector.rule
            local rule = {}
            rule.note = v.note or "" -- замечание может потребоваться для лога при отладки
            rule.valid = true
            rule.opts = "i"
            rule.to_has_query = false
            rule.auto_lang_prefix = true
            rule.query_append = true
            rule.case_sensitive = false
            rule.to_type = REDIRECT_TEMP
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
                        rule.to_type = REDIRECT_PERM
                    end
                    if v.to._attr["auto-lang-prefix"] == "false" then -- атрибут auto-lang-prefix
                        rule.auto_lang_prefix = false
                    end
                    if v.to._attr["qsappend"] == "false" then -- атрибут qsappend
                        rule.query_append = false
                    end
                end
            else
                log.info("Invalid 'rule.to' field format. Skip the rule.")
                rule.valid = false
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
            elseif type(v.from) == "table" then -- тег с атрибутами
                rule.from = v.from[1]
                if v.from._attr then
                    if v.from._attr["casesensitive"] == "true" then -- флаг чувстивтельности к регистру <from casesensitive="true">
                        rule.opts = nil
                    end
                    if v.from._attr["languages"] then -- есть условия на языки <from languages="pt-pt">
                        log.info("Languages ", v.from._attr["languages"])
                        for _, l in ipairs(utils.split(v.from._attr["languages"], ", ")) do
                            if not rule.languages then
                                rule.languages = {}
                            end
                            rule.languages[l] = true -- складываем языки хеш-таблицей, что бы потом быстрее искать
                        end
                    end
                end
            else
                log.info("Invalid 'rule.from' field format. Skip rule")
                rule.valid = false
            end

            -- обрабатываем различные варианты тега <condition ...>...</condition>. Возможные варинаты:
            -- <condition type="query-string">.*Keyword.*</condition>
            if v.condition and type(v.condition) == "table" then  -- тег с атрибутами
                if v.condition._attr and v.condition[1] then
                    rule.cond = v.condition[1]
                    if v.condition._attr.type == "query-string" then
                        rule.cond_type = COND_QUERY_STRING
                    else
                        log.err("Invalid rule.condition: '" .. rule.cond_type)
                        rule.valid = false
                    end
                    -- нужно проверить регулярое выражение для condition
                    local _, err = ngx.re.match("test", rule.cond)
                    if err then
                        log.err("Invalid regex rule.condition '" .. rule.from .. "': " .. tostring(err))
                        rule.valid = false
                    end
                end
            end
            -- перед укладкой правила надо протестировать заранее регулярное выражение
            local _, err = ngx.re.match("test", rule.from)
            if err then
                log.info("Invalid regex rule.from '" .. rule.from .. "': " .. tostring(err))
                rule.valid = false
            end

            if rule.valid then
                table.insert(rules, rule)
            else
                log.warn("Skip rule (due errors)", v)
            end
        end
        rector.rules = rules
    end
end

function rector.route(langs_path, rules_path)
    local uri = ngx.var.uri
    local lang
    if uri == "/" then
        return
    end
    rector.load_langs(langs_path)
    rector.load_rules(rules_path)
    -- определяем язык в URL, если есть и забираем кусок URL без языка в начале
    if uri:len() > 6 and uri:sub(7,7) == "/" then
        lang = uri:sub(2, 6)
        if rector.langs[ lang ] then
            uri = uri:sub(7)
        else
            lang = nil
        end
    end
    log.info("URI", uri, lang)

    --- нужно перебрать каждое правило и попробовать применить к текущему uri
    for _, rule in ipairs(rector.rules) do
        if rector.try_rule(uri, lang, rule) then
            return
        end
    end
end

--- Пробует применить правило.
--- Если правило проходит все условия то вызывается редирект. Прямо в методе.
--- В случае редиректа скрипт закончится прямо в методе.
--- @param uri string текущий URI запроса, без языкового префикса
--- @param lang string|nil языковый префикс, если он был у запроса
--- @param rule rector.rule само правило которое надо попробовать применить
--- @return boolean false — условия не удовлетворяют правилам, true - всё применилось.
---                 хотя при редиректе до возврата из метода не дойдёт — скрипт закончится на редиректе.
function rector.try_rule(uri, lang, rule)
    local to, n = ngx.re.gsub(uri, rule.from, rule.to, rule.opts)
    -- сработало правило, нужно определиться с действиями
    -- но перед эти надо проверить если ли улсовия на язык у правила и они совпадают с полученым lang
    if n == 0 then -- нет совпадения по rule.from
        return false
    end
    log.info("Rule matched", rule)
    if rule.languages and not lang then -- есть правила по языку, но запрос не содержит языка
        log.info("Skip rule by empty lang")
        return false
    end
    if rule.languages and not rule.languages[lang] then -- есть правила по языку, но запрос имеет другой язык
        log.info("Skip rule by `not rule.languages[lang]`", rule.languages, lang)
        return false
    end
    local query = ngx.var.args
    if rule.cond and rule.cond_type == COND_QUERY_STRING then -- проверка condition
        local cond_check = ngx.re.match(query, rule.cond, "i")
        if not cond_check then
            return false
        end
    end
    if rule.auto_lang_prefix and lang then -- прикрепляем обратно языковый префикс, если он был в запросе
        to = "/" .. lang .. to
    end
    if rule.query_append and query and query ~= "" then -- прикрепляем query строку
        if rule.to_has_query then
            to = to .. "&" .. query
        else
            to = to .. "?" .. query
        end
    end
    -- далее выполняем правило, если правило кривое (кривой to_type) то будем возвращать false
    if rule.to_type == REDIRECT_PERM then
        ngx.redirect(to, 301)
        return true
    elseif rule.to_type == REDIRECT_TEMP then
        ngx.redirect(to, 302)
        return true
    end
    return false
end


return rector