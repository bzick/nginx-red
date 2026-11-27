GET http://127.0.0.1:8088/search/?q=1
HTTP 301
Location: /?s=full&q=1

# Canonicalization runs before trim-suffix and the existing /search/ rule.
GET http://127.0.0.1:8088/search/index.html?q=1
HTTP 301
Location: /search/?q=1

GET http://127.0.0.1:8088/bzick/nginx-red/?q=iddqd
HTTP 302
Location: https://github.com/bzick/nginx-red?v2&q=iddqd

# A literal external host remains allowed, including after path and query substitution.
GET http://127.0.0.1:8088/nginx-red
HTTP 302
Location: https://github.com/bzick/nginx-red

GET http://127.0.0.1:8088/allowed-external/summer/?source=campaign
HTTP 302
Location: https://example.invalid/promo/summer/?source=campaign

GET http://127.0.0.1:8088/dynamic-host/evil/
HTTP 418

# An unsafe first match lets the next matching rule redirect.
GET http://127.0.0.1:8088/fallback/campaign/
HTTP 302
Location: /campaign/

GET http://127.0.0.1:8088/fallback/%5Cexample.invalid/
HTTP 302
Location: /safe/

# The global trim-target-suffix affects only the final path.
GET http://127.0.0.1:8088/trim/local/?source=campaign
HTTP 302
Location: /docs?view=full&source=campaign

GET http://127.0.0.1:8088/trim/external/
HTTP 302
[Asserts]
header "Location" == "https://example.invalid/docs#intro"

GET http://127.0.0.1:8088/trim/root/
HTTP 302
Location: /

GET http://127.0.0.1:8088/trim/legacy/
HTTP 302
Location: /docs

GET http://127.0.0.1:8088/trim/query/
HTTP 302
Location: /docs/?next=/index.html

GET http://127.0.0.1:8088/trim/forward/
HTTP 418
X-Request-Uri: /forwarded

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

# A local-looking replacement must stay on this host after interpolation.
GET http://127.0.0.1:8088/campaign/specials/summer/page.jsp
HTTP 302
Location: /campaign/promo/summer/

GET http://127.0.0.1:8088/campaign/specials/summer/pageXjsp
HTTP 418

GET http://127.0.0.1:8088/%5Cexample.invalid/specials/summer/page.jsp
HTTP 418
