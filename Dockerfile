
FROM openresty/openresty:alpine

RUN apk update && apk add curl wget htop bash

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY ./ /var/www/


VOLUME "/var/www"

CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]

