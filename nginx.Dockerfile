FROM alpine:3.14

ARG NGINX_VERSION=1.20.1
ARG NGINX_DEVEL_KIT=0.3.1
ARG LUA_NGINX_MODULE=0.10.19

# see https://github.com/openresty/docker-openresty/blob/master/alpine/Dockerfile
ENV CONFIG="\
    --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/lib/nginx/modules \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/var/run/nginx.pid \
    --lock-path=/var/run/nginx.lock \
    --http-client-body-temp-path=/var/cache/nginx/client_temp \
    --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
    --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
    --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
    --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
    --user=nginx \
    --group=nginx \
    --with-http_ssl_module \
    --with-http_realip_module \
    --with-http_addition_module \
    --with-http_sub_module \
    --with-http_mp4_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_secure_link_module \
    --with-http_stub_status_module \
    --with-http_auth_request_module \
    --with-threads \
    --with-stream \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --with-stream_realip_module \
    --with-http_slice_module \
    --with-compat \
    --with-http_v2_module \
    --with-pcre \
    --with-cc-opt='-DNGX_LUA_ABORT_AT_PANIC -I/usr/include -I/usr/include/luajit-2.1' \
    --with-ld-opt='-L/usr/lib -Wl,-rpath,/usr/lib/' \
    --add-dynamic-module=/build/ngx_devel_kit-$NGINX_DEVEL_KIT\
    --add-dynamic-module=/build/lua-nginx-module-$LUA_NGINX_MODULE\
    "

RUN apk update && apk upgrade && apk add --no-cache curl \
    gcc make libc-dev linux-headers \
    openssl-dev pcre-dev zlib-dev \
    luajit-dev luajit

RUN mkdir /build
WORKDIR /build

RUN curl -fSL https://github.com/vision5/ngx_devel_kit/archive/refs/tags/v$NGINX_DEVEL_KIT.tar.gz -o /build/ngx_devel_kit.tar.gz && \
    tar -zxf ngx_devel_kit.tar.gz

RUN curl -fSL https://github.com/openresty/lua-nginx-module/archive/refs/tags/v$LUA_NGINX_MODULE.tar.gz -o /build/lua-nginx-module.tar.gz && \
    tar -zxf lua-nginx-module.tar.gz

RUN curl -SL https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz -o /build/nginx.tar.gz && \
    ls -la && \
    tar -zxf nginx.tar.gz

ENV LUAJIT_LIB=/usr/lib/
ENV LUAJIT_INC=/usr/include/luajit-2.1/

RUN cd /build/nginx-$NGINX_VERSION && echo "configure" && ./configure $CONFIG && echo "make" && make -j$(nproc)