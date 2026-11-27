# This server has no XML rules. All redirects must come from remove-suffix.
GET http://127.0.0.1:8089/index.html
HTTP 301
Location: /

GET http://127.0.0.1:8089/idea/index.html
HTTP 301
Location: /idea/

HEAD http://127.0.0.1:8089/idea/index.html?x=1
HTTP 301
Location: /idea/?x=1
[Asserts]
body == ""

GET http://127.0.0.1:8089/de-de/idea/index.html?tag=a&tag=b&x=a%26b+z&empty=
HTTP 301
Location: /de-de/idea/?tag=a&tag=b&x=a%26b+z&empty=

GET http://127.0.0.1:8089/idea/index.htm
HTTP 301
Location: /idea/

GET http://127.0.0.1:8089/idea/index.html?next=//example.invalid/%2F%5c
HTTP 301
Location: /idea/?next=//example.invalid/%2F%5c

# The original request ends in index.html even though the current $uri is /.
GET http://127.0.0.1:8089/rewritten/index.html
HTTP 301
Location: /rewritten/

# A client request for a directory is internally rewritten to an index file.
GET http://127.0.0.1:8089/internal/
HTTP 418
X-Request-Uri: /internal/index.html

GET http://127.0.0.1:8089/internal/index.html
HTTP 301
Location: /internal/

GET http://127.0.0.1:8089/idea/
HTTP 418

POST http://127.0.0.1:8089/idea/index.html?x=1
[FormParams]
value: test
HTTP 301
Location: /idea/?x=1

PUT http://127.0.0.1:8089/idea/index.html
HTTP 301
Location: /idea/

PATCH http://127.0.0.1:8089/idea/index.html
HTTP 301
Location: /idea/

DELETE http://127.0.0.1:8089/idea/index.html
HTTP 301
Location: /idea/

OPTIONS http://127.0.0.1:8089/idea/index.html
HTTP 301
Location: /idea/

GET http://127.0.0.1:8089/idea/no-index.html
HTTP 418

GET http://127.0.0.1:8089/idea/other.html
HTTP 418

GET http://127.0.0.1:8089/idea/INDEX.HTML
HTTP 418

GET http://127.0.0.1:8089/idea/index.html/
HTTP 418

GET http://127.0.0.1:8089/idea/index.html/child
HTTP 418

GET http://127.0.0.1:8089//example.invalid/index.html
HTTP 418

GET http://127.0.0.1:8089/idea//index.html
HTTP 418

GET http://127.0.0.1:8089/%5Cexample.invalid/index.html
HTTP 418

GET http://127.0.0.1:8089/idea%2fpath/index.html
HTTP 418

GET http://127.0.0.1:8089/idea%2Fpath/index.html
HTTP 418

GET http://127.0.0.1:8089/idea%5cpath/index.html
HTTP 418

GET http://127.0.0.1:8089/idea%5Cpath/index.html
HTTP 418
