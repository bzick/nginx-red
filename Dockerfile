
# OpenResty 1.31.1.1 ships ngx_http_lua_module 0.10.31, required by lua-resty-core 0.1.34rc3
FROM openresty/openresty:1.31.1.1-alpine

RUN apk update && apk add curl wget htop bash

COPY build/openresty/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY ./ /var/www/

VOLUME "/var/www"

CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]

