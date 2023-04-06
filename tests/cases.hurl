GET http://127.0.0.1:8088/search/?q=1
HTTP 301
Location: /?s=full&q=1

GET http://127.0.0.1:8088/bzick/nginx-red/?q=iddqd
HTTP 302
Location: https://github.com/bzick/nginx-red?v2&q=iddqd

# test `languages` attribute
GET http://127.0.0.1:8088/pt-pt/lp/mono/
HTTP 302
Location: /pt-br/lp/mono/

GET http://127.0.0.1:8088/de-de/lp/mono/
HTTP 418

GET http://127.0.0.1:8088/lp/mono/
HTTP 418

# test `default-lang` config option
GET http://127.0.0.1:8088/de-de/dashboard/
HTTP 302
Location: /dashboard2/

GET http://127.0.0.1:8088/zh-cn/dashboard/
HTTP 302
Location: /dashboard2/

GET http://127.0.0.1:8088/dashboard/
HTTP 302
Location: /dashboard2/

GET http://127.0.0.1:8088/nl-nl/dashboard/
HTTP 418