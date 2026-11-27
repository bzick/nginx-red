Nginx Red
=========

<img align="right" src="./red-logo.svg" width="200">

Nginx Redirector — [Tuckey urlrewrite](https://tuckey.org/urlrewrite/) на базе OpenResty или Nginx + Lua.

Поддерживаются все правила [urlrewrite.xml](http://cdn.rawgit.com/paultuckey/urlrewritefilter/master/src/doc/manual/4.0/urlrewrite.xml) версии 4.0.
Поддержка префиксов языков.

Отличия от Tuckey urlrewrite:

- поведение правила по умолчанию - temporary-redirect

## Состав

- сам nginx
- nginx модуль [ngx_devel_kit](https://github.com/vision5/ngx_devel_kit) фреймворк для C API Nginx
- nginx модуль [lua-nginx-module](https://github.com/openresty/lua-nginx-module) модуль запуска Lua
- интерпретатор [luajit](https://luajit.org/) версии 2.1. 
  Одна из самых быстрых JIT машин, с самым быстрым [FFI](https://en.wikipedia.org/wiki/Foreign_function_interface)
- библиотеки [resty-core](https://github.com/openresty/lua-resty-core). Lua API Nginx-а на базе FFI
- исходный код [Red](./src)

## Установка

- Установка на основе [OpenResty](https://openresty.org/en/): [Dockerfile](./Dockerfile). 
  Всё уже встроено и настроено. Нет точечного выбора версии ПО.
- Установка с нуля, на основе Nginx: [Dockerfile](./nginx.Dockerfile). 
  Сборка nginx, luajit, nginx модулей ngx_devel_kit и lua-nginx-module. Можно выбирать версии ПО.

## Требования

- сервер Nginx
  - с модулем ngx_devel_kit
  - с модулем lua-nginx-module
- пакет luajit-dev версии 2.1

## Настройка

Добавьте в nginx следующие переменные окружения

```nginx
env RED_DEBUG=0;
env RED_CONFIG_PATH=/var/www/config.xml;
```

* `RED_DEBUG` — включает отладку у red. `0` или `1`
* `RED_RULES_PATH` — путь до конфига в [формате xml](./urlrewrite.samples.xml), где могут быть языки и правила, либо ссылки на файлы. И прочие настройки.

Директивы настройки lua:

- `lua_package_path 'PATH/src/red/?.lua;PATH/src/vendor/share/lua/5.1/?.lua;';` пути до исходников
- `lua_code_cache off;` включает/выключает кеш бай-кода JIT компилятора. На проде всегда должно быть `on`! 
- `lua_shared_dict cache 8m;` общий словарь для кеша. Нужно от `2m` и выше.

Директивы запуска lua:

- `init_by_lua_file "PATH/src/master.lua";` запускается в master-процессе nginx, сильно ограничен по функциональности.
  Используется для загрузки компонентов проекта, их проверки. Загружает первоначальные правила и настройки.
- `init_worker_by_lua_file "PATH/src/worker.lua";` запускается в worker-процессе nginx сразу после создания воркера.
  Используется для запуска таймера, проверяющего файлы конфигурации и прочих фоновых задач.
- `rewrite_by_lua_file "PATH/src/redirect.lua";` встраивается в локацию где надо проверить правило редиректа и, если правило нашлось,
  сделать редирект.

Перед ответом с редиректом RED проверяет итоговый `Location` после подстановок из URL. Абсолютный HTTP(S)-адрес разрешён, только если его схема и хост (с портом, если он задан) указаны в `<to>` буквально. Подстановка не может превратить локальный адрес во внешний или выбрать другой хост. Если цель небезопасна, RED пропускает это правило и проверяет следующие.

Для внешнего редиректа индексных страниц на каталог задайте в общем XML-конфиге:

```xml
<config param="remove-suffix">index.html</config>
<config param="remove-suffix">index.htm</config>
```

RED ответит `301` на прямой запрос независимо от HTTP-метода: `/index.html` → `/`, `/idea/index.html?tag=a&tag=b` → `/idea/?tag=a&tag=b`. Сравнивается полное имя последнего сегмента с учётом регистра; `no-index.html` и `index.html/` не совпадают. Query string, включая кодирование и порядок параметров, сохраняется без изменений. Каждый тег добавляет одно имя файла; без параметра функция выключена.

Проверка выполняется по исходному `$request_uri` в начале маршрутизации, до загрузки XML-правил, обработки локали и `trim-suffix`. Она работает и без правил; при наличии бизнес-редиректа сначала выполняется переход на каталог, что может добавить ещё один переход. Внутреннее переписывание обычного URL в `index.html` само по себе редирект не вызывает. Новая каноникализация пропускается для путей с двойными слешами, обратными слешами, управляющими символами или `%2F`/`%5C` в любом регистре; дальше выполняется обычная обработка запроса.

Настройка действует в locations, где подключён RED. После изменения общего XML-конфига нужен reload nginx: автоматическое обновление относится к файлам правил и локалей.

Отдельно в общем XML-конфиге можно задать несколько суффиксов цели совпавшего правила:

```xml
<config param="trim-target-suffix">/index.html</config>
<config param="trim-target-suffix">/index.htm</config>
```

После подстановок RED удалит из пути цели редиректа или forwarding самый длинный подходящий суффикс: `/docs/index.html?view=full` станет `/docs?view=full`. Если задать `index.html` без слеша, результатом будет `/docs/?view=full`. Для корневого `/index.html` результатом всегда будет `/`, а для относительного `index.html` — `./`. При обрезке query и fragment не меняются. Если параметр не задан, итоговый URL не меняется. Входной `trim-suffix` продолжает работать отдельно, до поиска правил.

## Обновление/добавление/удаление пакетов

Все зависимости установленные в `src/vendor` отчего не требуется установка и работа с `luarocks`. 
Так же не используются Си расширения, а только зависимости на чистом lua.

Для обновления зависимостей или применения изменений в зависимостях, достаточно изменить список зависимых 
пакетов в `./red-git-1.rockspec` и обновить зависимости через luarocks.

Зависимости red:

```bash
luarocks install --lua-dir=/usr/local/opt/lua@5.1 --tree ./src/vendor --no-doc --no-manifest --only-deps ./rockspec/red-git-1.rockspec
```

Часть зависимостей не указаны в списке зависмостей, так как они сильно завязаны на версию `nginx` и модуль `lua-nginx-module`
Обновление `resty-core`, версия зависит от `lua-nginx-module`.
```bash
luarocks install --lua-dir=/usr/local/opt/lua@5.1 --tree ./src/vendor --no-doc --no-manifest ./rockspec/lua-resty-core-0.1.34rc3-1.rockspec
```
Обновление `lua-resty-lrucache`, версия зависит от `resty-core`
```bash
luarocks install --lua-dir=/usr/local/opt/lua@5.1 --tree ./src/vendor --no-doc --no-manifest ./rockspec/lua-resty-lrucache-0.10-1.rockspec
```
Все зависимости должны быть git.

## Тестовые запросы

```
curl -I '127.0.0.1/search/?q=1'

HTTP/1.1 301 Moved Permanently
Location: /?s=full&q=1
```

```
curl -I '127.0.0.1/bzick/nginx-red/?q=iddqd'

HTTP/1.1 302 Moved Temporarily
Location: https://github.com/bzick/nginx-red?type=code&q=iddqd
```

```
curl -I '127.0.0.1/bzick/nginx-red/?q=iddqd'

HTTP/1.1 302 Moved Temporarily
Location: https://github.com/bzick/nginx-red?type=code&q=iddqd
```

```
curl -I --cookie "some_name=samples" '127.0.0.1/search/?q=1'
```
