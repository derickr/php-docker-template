# Created based on the oficial PHP and nginx containers
#
# Info:
# - https://hub.docker.com/_/php/
# - https://hub.docker.com/_/nginx/

FROM alpine:3.6

RUN apk add --no-cache --virtual .persistent-deps ca-certificates curl tar xz

# <necessary users>
RUN set -x \
    && addgroup -g 1000 usabilla \
    && adduser -u 1000 -D -G usabilla usabilla \
    && addgroup -S nginx \
    && adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx -G usabilla nginx
# </necessary users>

# <env definition>
ENV GPG_SERVERS ha.pool.sks-keyservers.net hkp://keyserver.ubuntu.com:80 hkp://p80.pool.sks-keyservers.net:80 pgp.mit.edu
ENV GPG_KEYS A917B1ECDA84AEC2B568FED6F50ABC807BD5DCD0 528995BFEDFBA7191D46839EF9BA0ADA31CBD89E B0F4253373F8F6F510D42178520A9993A1C052F8

ENV PHPIZE_DEPS autoconf dpkg-dev dpkg file g++ gcc libc-dev make pcre-dev pkgconf re2c
ENV PHP_INI_DIR /usr/local/etc/php
ENV PHP_EXTRA_CONFIGURE_ARGS --enable-fpm --with-fpm-user=usabilla --with-fpm-group=usabilla
ENV PHP_VERSION 7.1.9
ENV PHP_SHA256="ec9ca348dd51f19a84dc5d33acfff1fba1f977300604bdac08ed46ae2c281e8c"
ENV PHP_URL="https://secure.php.net/get/php-$PHP_VERSION.tar.xz/from/this/mirror"
ENV PHP_ASC_URL="https://secure.php.net/get/php-$PHP_VERSION.tar.xz.asc/from/this/mirror"

## Apply stack smash protection to functions using local buffers and alloca()
## Make PHP's main executable position-independent (improves ASLR security mechanism, and has no performance impact on x86_64)
## Enable optimization (-O2)
## Enable linker optimization (this sorts the hash buckets to improve cache locality, and is non-default)
## Adds GNU HASH segments to generated executables (this is used if present, and is much faster than sysv hash; in this configuration, sysv hash is also generated)
## https://github.com/docker-library/php/issues/272
ENV PHP_CFLAGS="-fstack-protector-strong -fpic -fpie -O2"
ENV PHP_CPPFLAGS="$PHP_CFLAGS"
ENV PHP_LDFLAGS="-Wl,-O1 -Wl,--hash-style=both -pie"

ENV NGINX_VERSION 1.13.5
ENV NGINX_DOCUMENT_ROOT="/var/www/html"
ENV NGINX_SERVER_NAME=localhost
# </env definition>

# <copy installation>
COPY php/install/* /root/php-install/
COPY nginx/install/* /root/nginx-install/
COPY gnupg/fetch-keys.sh /usr/src/
# </copy installation>

# <download packages>
RUN apk add --no-cache --virtual .fetch-deps gnupg openssl \
    && export GNUPGHOME="$(mktemp -d)" \
    && /usr/src/fetch-keys.sh \
    && /root/php-install/download.sh \
    && /root/nginx-install/download.sh \
    && apk del .fetch-deps \
    && rm -rf "$GNUPGHOME"
# </download packages>

# <installation>
COPY php/docker-php-source /usr/local/bin/
COPY nginx/docker-nginx-source /usr/local/bin/

## PHP & Nginx installation
RUN apk add --no-cache --virtual .build-deps $PHPIZE_DEPS \
    coreutils \
    curl-dev \
    geoip-dev \
    gd-dev \
    libedit-dev \
    libxml2-dev \
    libxslt-dev \
    linux-headers \
    openssl-dev \
    sqlite-dev \
    zlib-dev \
    && /root/php-install/compile.sh \
    && /root/php-install/configure-fpm.sh \
    && /root/nginx-install/compile.sh \
    && apk del .build-deps

## Supervisord installation
RUN apk add --no-cache --virtual .supervisor-deps supervisor \
    && mkdir /etc/supervisor.d

COPY php/docker-php-ext-* php/docker-php-entrypoint /usr/local/bin/
COPY php/conf/*.conf /usr/local/etc/php-fpm.d/
COPY nginx/conf/nginx.conf /etc/nginx/nginx.conf
COPY nginx/conf/vhost.conf.template /root/ 
COPY supervisord/services.ini /etc/supervisor.d/

RUN docker-php-ext-install opcache \
    && rm -rf /root/php-install/ \
    && rm -rf /root/nginx-install/
# </installation>

EXPOSE 80 
STOPSIGNAL SIGTERM

CMD ["/usr/bin/supervisord"]