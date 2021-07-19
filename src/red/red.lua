local tostring  = tostring
local ipairs, pairs    = ipairs, pairs
local ngx       = ngx
local msgpack   = require("MessagePack")
local utils     = require("utils")
local log       = require("log")
local varset    = require("varset")
local cfg   = require("config")
local cache = ngx.shared["cache"] or nil
local config_path = os.getenv("RED_CONFIG_PATH") or ""
local root_path   = utils.basedir(config_path) -- путь относительно конфига, со слешом на конце

local CACHE_CHECK_TIMEOUT = 5
local CACHE_KEY_WATCHER_LOCK = "watcher:lock"
local CACHE_KEY_RULES_MODIFIED = "rules:mtime"
local CACHE_KEY_MODIFIED = "cache:mtime"
local CACHE_KEY_RULES_DATA = "rules:data"
local CACHE_KEY_LOCALE_MODIFIED = "locale:mtime"
local CACHE_KEY_LOCALE_DATA = "locale:data"

--- @class red
--- @field rules red.rule[] список правил
--- @field cache userdata nginx кеш
--- @field config red.config настройки поведения
--- @field langs table<string,boolean> хеш-таблица языков
local red = {
    rules = { },
    config = cfg.new(),
    vars = varset.new(),
    cache = cache,
}

--- Начальная инициализация приложения
--- 1) загрузка базового конифга
function red.init()
    red.config:set_root_path(root_path)
    local err = red.config:parse_xml_file(config_path)
    if err then
        log.err("Failed to load config " .. config_path .. ":" .. err)
    end
    if not red.config.dynamic_mode then
        -- если не у нас статические пути в конифге то делаем предзагрузку всего что можем сразу и в память
        red.reload()
        red.cache_checked = ngx.now() -- кеш уже обновлён так как только что его загрузили
    end
    log.debug("Config initialized", red.config)

end

--- Запускает таймер, который обновляет языки и правила с диска, если файлы поменялись.
--- Так как у nginx и lua нет какого-либо filewatcher то будем проверять файлы на изменение раз в N секунд
function red.start_file_watcher()
    if red.config.dynamic_mode then
        -- при использовании динамической загрузки мы не кешируем на постоянную данные,
        -- а как следствие не перепроверяем их по таймеру
        -- проверяя актуальность их при каждом хите
        return
    end
    -- кеши будет обновлять всегда самый первый воркер с id 0, он всегда будет существовать
    -- если воркер будет убит, master сам поднимет новый воркер с тем же id.
    if ngx.worker.id() == nil then -- очень старые nginx (nginx < 1.9.1) версии не имели фиксированные id воркеров.
        local _, err = ngx.timer.every(red.config.check_timeout, red.reload)
        if err then
            log.err("Failed to setup file watcher: " .. tostring(err))
        end
    else
        if ngx.worker.id() == 0 then
            local _, err = ngx.timer.every(red.config.check_timeout, red.reload)
            if err then
                log.err("Failed to setup file watcher: " .. tostring(err))
            end
        end
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
--- 3) Не удалось установить блокировку. Этот воркер не будет работать с диском.
function red.reload()
    if not red.cache then
        return
    end
    local lock_ttl      = red.config.check_timeout / 2
    local wait_time     = 1
    if wait_time >= red.config.check_timeout then
        wait_time = red.config.check_timeout / 2
    end
    if red.config.dynamic_mode then
        -- при dynamic_mode мы не перезагружаем конфигурацию в red
        -- reload не должен происходить так как при dynamic_mode не запускаются таймеры, но поставим проверку, на всякий.
        return
    end
    -- Выставляем блокировку на эксклюзивный доступ к файловой системе.
    -- Блокировка ставится на половину времени от timeout что бы следующий воркер уже мог взяться за дело.
    local ok = red.cache:add(CACHE_KEY_WATCHER_LOCK, 1, lock_ttl)
    if ok then
        local cache_is_modified = false

        if red.config.langs_path then
            local locale_config, locale_err = red.load_to_cache(red.config.langs_path, CACHE_KEY_LOCALE_MODIFIED, CACHE_KEY_LOCALE_DATA)
            if locale_err then
                log.err("Failed to load locales from `" .. (red.config.langs_path or "none") .. "`: " .. locale_err)
            elseif locale_config then
                cache_is_modified = true
                red.locale = locale_config.locale
            end
        end

        -- если есть путь и он без подстановок то правило по нему можно загрузить
        if red.config.rules_path then
            -- @type red.rules
            local rules_config, rules_err = red.load_to_cache(red.config.rules_path, CACHE_KEY_RULES_MODIFIED, CACHE_KEY_RULES_DATA)
            if rules_err then
                log.err("Failed to load rules from " .. (red.config.rules_path or "none") .. ": " .. rules_err)
            elseif rules_config then
                cache_is_modified = true
                red.rules = rules_config.rules
            end
        end

        if cache_is_modified then
            red.cache:set(CACHE_KEY_MODIFIED, ngx.now())
            log.debug("configuration reloaded from fs")
        else
            log.debug("configuration not modified")
        end
        -- Не будем зачищать CACHE_KEY_WATCHER_LOCK что бы другие воркеры (если они есть) не пытались обновить данные так рано.
        -- Особенно проблема актуальна когда nginx работает на одном CPU ядре и таймеры срабатывают у всех последовательно.
    end
end

--- Выполняет загрузку конфига c диска, парсит и результат парсера сохраняет в кеш и возвращает.
--- @param path string путь до файла данных
--- @param modified_lock string ключ словаря где хранится последний mtime файла
--- @param data_lock string ключ словаря где хранятся данные
--- @return table распаршенный массив данных
--- @return string описание ошибки, nil если ошибок нет
function red.load_to_cache(path, modified_lock, data_lock)
    local mtime = utils.get_file_mtime(path)
    if mtime == nil then -- файла не существует
        return nil, "file " .. tostring(path) .. " doesn't exists"
    end
    local cache_mtime = red.cache:get(modified_lock)
    -- Обновляем кеш если одно из двух:
    -- 1) cache_mtime равен nil — это первый запуск, когда кеша ещё нет => кеш надо создать
    -- 2) когда mtime файла и mtime кеша не совпадают => обновился файл => кеш надо обновить

    if not cache_mtime or mtime ~= cache_mtime then
        local config = cfg.new()
        local err = config:parse_xml_file(path)
        if err then
            return nil, err
        else
            -- вот теперь, на конец-то, можно обновить кеш в шареной памяти.
            red.cache:set(data_lock, msgpack.pack(config))
            red.cache:set(modified_lock, mtime)
            return config
        end
    end
end

--- Возвращает список правил по которым надо проверить URL
--- Метод работает в двух режимах: динамический и статический.
--- Вид режима зависит от того есть ли подстановки в пути до правил в конифге.
--- 1) Динамический режим не очень быстрый так как каждый раз проверяет кеши
--- и если данных там нет то прямо в методе загружает правила с файловой системы,
--- что негативно сказывается на производительности.
--- 2) Статичный же режим наоборот - самый производительный.
--- В этом режиме проверяется есть ли обновление кеша, если кеш обновился то выгружает новые правила и языки из кеша,
--- не трогая файловую систему. В этом режиме метод работает только с памятью nginx и является очень производительным.
--- Так же метод не будет проверять кеш если буквально недавно проверял,
--- расстояние между проверками составляет CACHE_CHECK_TIMEOUT
--- @return red.rule[]
--- @return red.locale
function red.get_runtime()
    if red.config.dynamic_mode then
        log.debug("Using slow dynamic mode")
        local rules, locale = red.rules, red.locale
        if red.config.rules_path then
            local config, err = red.fetch_dynamic_config(red.config.rules_path, CACHE_KEY_RULES_MODIFIED, CACHE_KEY_RULES_DATA)
            if not config then
                log.warn("Failed to dynamically load rules by " .. red.config.rules_path .. ":" .. tostring(err or "no error"))
            else
                rules = config.rules
            end
        end
        if red.config.langs_path then
            local config, err = red.fetch_dynamic_config(red.config.langs_path, CACHE_KEY_LOCALE_MODIFIED, CACHE_KEY_LOCALE_DATA)
            if not config then
                log.warn("Failed to dynamically load locales by " .. red.config.langs_path .. ":" .. tostring(err or "no error"))
            else
                locale = config.locale
            end
        end
        return rules, locale
    else
        log.debug("Using fast static mode")
        -- мы работаем без динамики, можем кешировать прямо в память.
        -- но что бы не терибить часто память будем проверять кеш периодично раз в CACHE_CHECK_TIMEOUT секунд.
        if red.cache_checked + CACHE_CHECK_TIMEOUT < ngx.now() then -- проверям как давно проверяли кеш
            local cache_modified = red.cache:get(CACHE_KEY_MODIFIED)  -- получаем последнее изменение кеша
            if not red.cache_modified or red.cache_modified ~= cache_modified then -- сверяемся были ли изменения в кеше
                local data
                data = red.cache:get(CACHE_KEY_RULES_DATA) -- забираем кеш правил
                if data then
                    local config = msgpack.unpack(data)
                    if config and config.rules then
                        red.rules = config.rules
                        log.debug("rules reloaded from cache")
                    end
                end
                data = red.cache:get(CACHE_KEY_LOCALE_DATA) -- забираем кеш языка
                if data then
                    local config = msgpack.unpack(data)
                    if config then
                        red.locale = config.locale
                        log.debug("config reloaded from cache")
                    end
                end
                red.cache_modified = cache_modified
            end
            red.cache_checked = ngx.now()
        end
        return red.rules, red.locale
    end
end

--- Возвращает конфиг соответвующий указанному пути.
--- Если в кеше нет конфига, то производит его загрузку в кеш.
--- @param config_filename string путь до файла
--- @param modified_key_prefix string ключ/префикс кеша в который писать дату обновления
--- @param data_key_prefix string ключ/префикс кеша в который писать загруженные данные
--- @return red.config
function red.fetch_dynamic_config(config_filename, modified_key_prefix, data_key_prefix)
    -- в случае динамического пути нам нужно:
    -- 1) вычислить новый путь
    local path = red.config.variables:replace(config_filename)
    local key_modified = modified_key_prefix
    local key_data = data_key_prefix
    if path ~= config_filename then
        -- меняем ключи у кеша если пути реально динамические
        key_modified = key_modified .. ":" .. path
        key_data = key_data .. ":" .. path
    end

    -- 2) загрузить в кеш конфиг. в кеш загрузятся конфиг только если нет его в кеше или файл изменился.
    --    если были изменения кеша то мы получим новые данные сразу.
    local config, err = red.load_to_cache(path, key_modified, key_data)
    if err then
        return nil, "Failed to load config from `" .. (path or "none") .. "`: " .. err
    elseif config then
        return config
    else
        -- 3) если загрузка в кеш ничего не дала - значит в кеше уже актуальные данные, забираем из кеша
        local data = red.cache:get(key_data)
        if data then
            return msgpack.unpack(data) or {}
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
    local rules, locale = red.get_runtime()
    if not rules then
        log.warn("No one rules loaded")
        return
    end

    -- определяем язык в URL, если есть и забираем кусок URL без языка в начале
    if uri:len() > 6 and uri:sub(7,7) == "/" then
        lang = uri:sub(2, 6)
        if locale.langs[ lang ] then
            uri = uri:sub(7)
        else
            lang = nil
        end
    end
    --- нужно перебрать каждое правило и попробовать применить к текущему uri
    for _, rule in ipairs(rules) do
        if red.try_rule(uri, lang, rule, locale) then
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
--- @param locale red.locale настройки локализации
--- @return boolean false — условия не удовлетворяют правилам, true - всё применилось.
---                 хотя при редиректе до возврата из метода не дойдёт — скрипт закончится на редиректе.
function red.try_rule(uri, lang, rule, locale)
    local to, n = ngx.re.gsub(uri, rule.from, rule.to, rule.opts)
    -- сработало правило, нужно определиться с действиями
    -- но перед эти надо проверить если ли улсовия на язык у правила и они совпадают с полученым lang
    if n == 0 or not to then -- нет совпадения по rule.from
        return false
    end
    log.debug("Rule matched", rule)
    local query = ngx.var.args -- параметры запроса, всё после `?`, строкой
    if rule.cond and rule.cond_type == cfg.COND_QUERY_STRING then -- проверка condition
        local cond_check = ngx.re.match(query, rule.cond, "i")
        if not cond_check then
            return false
        end
    end
    if lang and locale then
        -- если задан языковый префикс, проверяем префиксы на наличие unlocalized адресов
        for _, p in ipairs(locale.prefix) do
            if to:find(p, 1, true) == 1 then
                rule.auto_lang_prefix = false
                break
            end
        end
    end

    -- прикрепляем обратно языковый префикс, если он был в запросе и урла не абсолютная
    if rule.auto_lang_prefix and lang and not rule.absolute then
        to = "/" .. lang .. to
    end
    if rule.query_append and query and query ~= "" then -- прикрепляем query строку, если указано
        if rule.to_has_query then
            to = to .. "&" .. query
        else
            to = to .. "?" .. query
        end
    end
    -- далее выполняем правило, если правило кривое (кривой to_type) то будем возвращать false
    if rule.to_type == cfg.REDIRECT_PERM then
        ngx.redirect(to, 301)
        return true
    elseif rule.to_type == cfg.REDIRECT_TEMP then
        ngx.redirect(to, 302)
        return true
    elseif rule.to_type == cfg.FORWARDING then
        local frags = utils.split(to, "?")
        if frags[2] then
            ngx.req.set_uri_args(query)
        end
        ngx.req.set_uri(frags[1], false)
        return true
    end
    return false
end

_G.red = red -- устанавливаем приложение глобально синглтоном