Nginx Red
=========

Nginx Redirector на базе OpenResty компонентов (nginx + ngx_http_lua_module + luajit + resty-core)


## Установка

## Обновление/добавление/удаление пакетов

Не используются Си расширения, испольуются только pure lua пакеты.

Изменить списко зависимых пакетов в `./red-git-1.rockspec` и обновить зависимости:

```bash
luarocks install --tree ./src/vendor --no-doc --no-manifest --only-deps ./red-git-1.rockspec
```

## Тестовые запросы

```
curl -I '127.0.0.1/search/?q=1'

HTTP/1.1 301 Moved Permanently
Location: /?s=full&q=1
```