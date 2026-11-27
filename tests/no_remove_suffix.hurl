# Same nginx fixture, with remove-suffix absent from its RED configuration.
GET http://127.0.0.1:8090/index.html
HTTP 418
X-Request-Uri: /index.html

GET http://127.0.0.1:8090/idea/index.html?x=1
HTTP 418
X-Request-Uri: /idea/index.html

HEAD http://127.0.0.1:8090/idea/index.html
HTTP 418

POST http://127.0.0.1:8090/idea/index.html
HTTP 418

GET http://127.0.0.1:8090/idea/index.htm
HTTP 418

GET http://127.0.0.1:8090/internal/
HTTP 418
X-Request-Uri: /internal/index.html
