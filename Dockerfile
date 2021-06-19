
FROM openresty/openresty:alpine

RUN apk update && apk add curl wget htop bash

COPY build/openresty/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY ./ /var/www/

VOLUME "/var/www"

CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]

