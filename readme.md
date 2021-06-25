Nginx Red
=========

<img align="right" src="./red-logo.svg" width="200">

Nginx Redirector на базе OpenResty компонентов:
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
env RED_RULES_PATH=/var/www/urlrewrite.xml;
env RED_LANGS_PATH=/var/www/langs.xml;
env RED_RELOAD_TIMEOUT=10;
```

* `RED_DEBUG` — включает отладку у red. `0` или `1`
* `RED_RULES_PATH` — путь до правил в [формате xml](./urlrewrite.samples.xml).
* `RED_LANGS_PATH` — путь до языков в [формате xml](./langs.samples.xml).
* `RED_RELOAD_TIMEOUT` — интервал проверки файлов правил и языков на изменение, что бы загрузить свежую версию. Секунды.

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

## Обновление/добавление/удаление пакетов

Не используются Си расширения, используются только pure lua пакеты.

Для обновления зависимостей или применения изменений в зависимостях, достаточно изменить список зависимых 
пакетов в `./red-git-1.rockspec` и обновить зависимости через luarocks.

Зависимости red:

```bash
luarocks install --tree ./src/vendor --no-doc --no-manifest --only-deps ./rockspec/red-git-1.rockspec
```

Обновление `resty-core`. `resty-core` обновляется отдельно так как завязано на nginx модуль `lua-nginx-module`.
```bash
luarocks install  --lua-dir=/usr/local/opt/lua@5.1 --tree ./src/vendor --no-doc --no-manifest ./rockspec/lua-resty-core-0.1.21-1.rockspec
```
Обновление `lua-resty-lrucache`, зависит от `resty-core`
```bash
luarocks install  --lua-dir=/usr/local/opt/lua@5.1 --tree ./src/vendor --no-doc --no-manifest ./rockspec/lua-resty-lrucache-0.10-1.rockspec
```
Все зависимости должны быть в git.

## Тестовые запросы

```
curl -I '127.0.0.1/search/?q=1'

HTTP/1.1 301 Moved Permanently
Location: /?s=full&q=1
```

```
curl -I '127.0.0.1/goodies/code2art/?q=1'

HTTP/1.1 302 Moved Temporarily
Location: https://code2art.jetbrains.com/?v3&q=1
```
