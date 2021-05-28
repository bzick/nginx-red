
FROM ubuntu:18.04

# Install LuaJIT and Nginx
RUN apt-get update && apt-get install -y --no-install-recommends \
    luajit libluajit-5.1-common \
    libcurl3-gnutls \
    nginx-extras \
    ca-certificates

RUN mkdir -p /var/www

COPY nginx.conf /etc/nginx/nginx.conf
COPY ./ /var/www/

RUN chown -R www-data:www-data /var/www

VOLUME "/var/www"

CMD ["/usr/sbin/nginx", "-c", "/etc/nginx/nginx.conf", "-g", "daemon off;"]

