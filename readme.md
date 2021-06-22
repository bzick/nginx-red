Nginx Red
=========

Nginx Redirector на базе OpenResty компонентов (nginx + ngx_http_lua_module + luajit + resty-core)


## Установка

## Настройка

Добавьте в nginx сделующие переменные окружения

```nginx
env RED_DEBUG=0;
env RED_RULES_PATH=/var/www/urlrewrite.xml;
env RED_LANGS_PATH=/var/www/langs.xml;
env RED_RELOAD_TIMEOUT=10;
```

* `RED_DEBUG` — включает отладку у red.
* `RED_RULES_PATH` — путь до правил в [формате xml](./urlrewrite.samples.xml).
* `RED_LANGS_PATH` — путь до языков в [формате xml](./langs.samples.xml).
* `RED_RELOAD_TIMEOUT` — интервал проверки файлов правил и языков на изменение, что бы загрузить свежую версию. Секунды.

## Обновление/добавление/удаление пакетов

Не используются Си расширения, испольуются только pure lua пакеты.

Для обновления зависимостей или применения изменений в зависимостях, достаточно изменить список зависимых 
пакетов в `./red-git-1.rockspec` и обновить зависимости через luarocks:

```bash
luarocks install --tree ./src/vendor --no-doc --no-manifest --only-deps ./red-git-1.rockspec
```

Все зависимости должны быть в git.

## Тестовые запросы

```
curl -I '127.0.0.1/search/?q=1'

HTTP/1.1 301 Moved Permanently
Location: /?s=full&q=1
```