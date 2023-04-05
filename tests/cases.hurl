GET http://127.0.0.1:8088/search/?q=1
HTTP 301
Location: /?s=full&q=1

GET http://127.0.0.1:8088/bzick/nginx-red/?q=iddqd
HTTP 302
Location: https://github.com/bzick/nginx-red?v2&q=iddqd
