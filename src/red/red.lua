local tostring  = tostring
local ipairs    = ipairs
local pcall     = pcall
local io        = io
local ngx       = ngx
local cjson     = require("cjson.safe")
local utils     = require("utils")
local log       = require("log")
local parsers   = require("parsers")
local cache = ngx.shared["cache"] or nil
local rules_path    = os.getenv("RED_RULES_PATH")
local langs_path    = os.getenv("RED_LANGS_PATH")
local timeout       = tonumber(os.getenv("RED_RELOAD_TIMEOUT"))
--local stats_path    = os.getenv("RED_STATS_PATH")
--local stats_timeout = tonumber(os.getenv("RED_STATS_TIMEOUT"))
local lock_ttl      = timeout / 2
local wait_time     = 1
if wait_time >= timeout then
    timeout = timeout / 2
end


--- @class red.rule псевдо-тип нужен для хинтов
--- @field note string
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

local CACHE_KEY_WATCHER_LOCK = "watcher:lock"
local CACHE_KEY_RULES_MODIFIED = "rules:mtime"
local CACHE_KEY_RULES_DATA = "rules:data"
local CACHE_KEY_LANGS_MODIFIED = "langs:mtime"
local CACHE_KEY_LANGS_DATA = "langs:data"

--- @class red
--- @field rules red.rule[] список правил
--- @field cache userdata nginx кеш
--- @field langs table<string,boolean> хеш-таблица языков
--- @field rules_modified number время последнего обновляения кеша правил (из диска или словаря)
--- @field langs_modified number время последнего обновляения кеша языка (из диска или словаря)
local red = {
    rules = { },
    langs = { },
    cache = cache,
    rules_modified = 0,
    langs_modified = 0,
}

--- Запускает таймер, который обновляет язки и правила с диска, если файлы поменялись.
--- Так как у nginx и lua нет какого-либо filewatcher то будем проверять файлы на изменение раз в N секунд
function red.start_file_watcher()
    local _, err = ngx.timer.every(timeout, red.reload)
    if err then
        log.err("Failed to setup file watcher: " .. tostring(err))
    end
end

--- Метод производит перезагрузку правил и языка с диска.
--- Если это первый запуск то производится первоначалная загрузка правил и языка.
--- Алгоритм:
--- 1) ставится глобальная блокировка CACHE_KEY_WATCHER_LOCK на lock_ttl секунд,
---    что бы выбрать какой воркер будет обновлять кеш
--- 2) Удалось установить блокировку. Этот воркер будет обновлять кеш с диска.
--- 2.1) Загружаются с диска правила, если файл поменялся с последнего запуска метода
--- 2.2) Правила парсятся, и сохраняются в словарь в CACHE_KEY_RULES_DATA и в red.rules
--- 2.3) Загружаются с диска языки, если файл поменялся с последнего запуска метода
--- 2.4) Языки парсятся, и сохраняются в словарь в CACHE_KEY_LANGS_DATA и в red.langs
--- 3) Не удалось установить блокировку. Это воркер не будет работать с диском. Заберёт данные из словаря.
--- 3.1) Ожидается wait_time, что бы другой воркер успел обновить кеш
--- 3.2) Забирается кеш из словаря из CACHE_KEY_RULES_DATA и в red.rules
--- 3.2) Забирается кеш из словаря из CACHE_KEY_LANGS_DATA и в red.langs
function red.reload()
    log.info("reload rules")
    if not red.cache then
        return
    end
    -- Выставляем блокировку на эксклюзивный доступ к файловой системе.
    -- Другие воркеры должны вернутся позже за результатом.
    -- Блокировка ставится на половину времени от timeout что бы следующий воркер мог взяться за дело.
    local ok = red.cache:add(CACHE_KEY_WATCHER_LOCK, 1, lock_ttl)
    if ok then
        log.debug("load rules from fs...")
        -- так как получили эксклюзивную блокировку то начинаем обновление
        -- Сначало обновляем кеш правил
        local rules, rules_err = red.load_to_cache(rules_path, parsers.rules_parser, CACHE_KEY_RULES_MODIFIED, CACHE_KEY_RULES_DATA)
        if rules_err then
            log.err("Failed to load rules from " .. (rules_path or "none") .. ": " .. rules_err)
        elseif rules then
            red.rules = rules
        else
            log.debug("rules not modified")
        end
        -- Потом обновляем кеш языков
        local langs, langs_err = red.load_to_cache(langs_path, parsers.langs_parser, CACHE_KEY_LANGS_MODIFIED, CACHE_KEY_LANGS_DATA)
        if langs_err then
            log.err("Failed to load languages from `" .. (langs_path or "none") .. "`: " .. langs_err)
        elseif langs then
            red.langs = langs
        else
            log.debug("langs not modified")
        end
        -- Не будем зачищать CACHE_KEY_WATCHER_LOCK что бы другие воркеры не пытались обновить данные так рано.
        -- Особенно проблема актуальна когда nginx работает на одном CPU ядре и таймеры срабатывают у всех последовательно.
    elseif wait_time > 0 then
        ngx.sleep(wait_time)
        local rules_modified = red.cache:get(CACHE_KEY_RULES_MODIFIED)
        if not red.rules_modified or red.rules_modified ~= rules_modified then
            local data  = red.cache:get(CACHE_KEY_RULES_DATA)
            if data then
                local rules = cjson.decode(data)
                if rules then
                    red.rules = rules
                    red.rules_modified = rules_modified
                end
            end
        end
        local langs_modified = red.cache:get(CACHE_KEY_LANGS_MODIFIED)
        if not red.langs_modified or red.langs_modified ~= langs_modified then
            local data  = red.cache:get(CACHE_KEY_LANGS_DATA)
            if data then
                local langs = cjson.decode(data)
                if langs then
                    red.langs = langs
                    red.langs_modified = langs_modified
                end
            end
        end
    end
    log.info("rules reloaded")

end


--- Выполняет загрузку данных c диска, парсит и результат парсера возвращает и сохраняет в кеш.
--- @return table распаршенный массив данных
--- @return string описание ошибки, nil если ошибок нет
function red.load_to_cache(path, parser, modified_lock, data_lock)
    local mtime = utils.get_file_mtime(path)
    if mtime == nil then -- файла не существует
        return nil, "file " .. tostring(path) .. " doesn't exists"
    end
    local cache_mtime = red.cache:get(modified_lock)
    -- Обновляем кеш если одно из двух:
    -- 1) cache_mtime равен nil — это первый запуск, когда кеша ещё нет => кеш надо создать
    -- 2) когда mtime файла и mtime кеша не совпадают => обновился файл => кеш надо обновить
    if not cache_mtime or mtime ~= cache_mtime then
        local file, err = io.open(path, "r")
        if not file then
            return nil, "failed to open file " .. path .. ": " .. tostring(err or "no error")
        end
        local data = file:read("*all") -- вычитваем всё из файла специальным флагом
        file:close()
        -- используем pcall для безопасного вызова парсера, даже если там произойдёт паника
        -- наш метод это никак не заденет.
        -- pcall() возвращает первым результатом флаг успеха, а вторым либо ошибку (если провал),
        -- либо результат вызова (если успех), то есть то что вернёт функция.
        local success, result = pcall(parser, data)
        if not success then
            return nil, result
        elseif result then
            -- вот теперь, на конец-то, можно обновить кеш в шареной памяти.
            red.cache:set(data_lock, cjson.encode(result))
            red.cache:set(modified_lock, mtime)
            return result, nil
        end
    end
end


--- Ищет и применяет правило к текущему запросу
function red.route()
    local uri = ngx.var.uri
    local lang
    if uri == "/" then
        return
    end
    red.reload()
    -- определяем язык в URL, если есть и забираем кусок URL без языка в начале
    if uri:len() > 6 and uri:sub(7,7) == "/" then
        lang = uri:sub(2, 6)
        if red.langs[ lang ] then
            uri = uri:sub(7)
        else
            lang = nil
        end
    end

    --- нужно перебрать каждое правило и попробовать применить к текущему uri
    for _, rule in ipairs(red.rules) do
        if red.try_rule(uri, lang, rule) then
            return
        end
    end
end

--- Пробует применить правило.
--- Если правило проходит все условия то вызывается редирект. Прямо в методе.
--- В случае редиректа скрипт закончится прямо в методе.
--- @param uri string текущий URI запроса, без языкового префикса
--- @param lang string|nil языковый префикс, если он был у запроса
--- @param rule red.rule само правило которое надо попробовать применить
--- @return boolean false — условия не удовлетворяют правилам, true - всё применилось.
---                 хотя при редиректе до возврата из метода не дойдёт — скрипт закончится на редиректе.
function red.try_rule(uri, lang, rule)
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
    if rule.cond and rule.cond_type == parsers.COND_QUERY_STRING then -- проверка condition
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
    if rule.to_type == parsers.REDIRECT_PERM then
        ngx.redirect(to, 301)
        return true
    elseif rule.to_type == parsers.REDIRECT_TEMP then
        ngx.redirect(to, 302)
        return true
    end
    return false
end

_G.red = red -- устанавливаем приложение глобально синглтоном