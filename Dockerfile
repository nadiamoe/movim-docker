FROM alpine:3.21.3 AS downloader

WORKDIR /work
RUN apk add --no-cache patch

# Renovate updates the version below, which is also grepped by CI/CD to produce the build tag. Do not chage its format.
ARG MOVIM_VERSION=v0.29.2
ADD https://github.com/movim/movim/archive/refs/tags/${MOVIM_VERSION}.tar.gz .
RUN tar -xzf "${MOVIM_VERSION}.tar.gz" && mv movim-* movim # Remove version suffix.

COPY *.patch .
WORKDIR /work/movim
RUN <<EOF
  set -e
  for p in ../*.patch; do
    patch -p1 < "$p"
  done
EOF

# Build-time assert that no 'paths.log' remains in the codebase
RUN if grep -Rle "'paths.log'" .; then exit 1; fi

FROM nginx:1.27.4-alpine AS nginx

COPY --from=downloader /work/movim/ /var/www/movim/

FROM alpine:3.21.3 AS fpm

# https://github.com/docker-library/php/blob/7deb69be16bf95dfd1f37183dc20e8fd21306bbc/8.4/alpine3.21/fpm/Dockerfile#L32
RUN adduser -u 82 -D -S -G www-data www-data

WORKDIR /var/www

RUN <<EOF
  set -e 

  apk add --no-cache \
    unzip \
    tini \
    ca-certificates \
    php \
    php-fpm \
    php-curl \
    php-gd \
    php-dom \
    php-pdo \
    php-pdo_pgsql \
    php-pgsql \
    php-pecl-imagick \
    php-opcache \
    php-xml \
    php-simplexml \
    php-openssl \
    composer

  which php-fpm || ln -s /usr/sbin/php-fpm* /usr/sbin/php-fpm
  test -d /etc/php || ln -s /etc/php* /etc/php
EOF

# docker-compose.yml sets this to `0.0.0.0` instead, you'll want that outside of kubernetes.
ARG FPM_LISTEN=localhost

RUN <<EOF
  set -e 

  # The format of php-fpm.conf is such that appending would make the directive belong to a different seciton.
  sed -i 's|;error_log = .*|error_log = /proc/self/fd/2|' /etc/php/php-fpm.conf # Log to stderr.
  sed -i 's|;error_log = .*|error_log = /proc/self/fd/2|' /etc/php/php.ini # Log to stderr.

  {
    echo 'access.log = /proc/self/fd/2' # Log to stderr.
    echo 'catch_workers_output = yes' # Log workers to stderr.
    echo "listen = ${FPM_LISTEN}:9000"
  } >> /etc/php/php-fpm.d/www.conf
EOF

COPY --from=downloader /work/movim /var/www/movim
WORKDIR /var/www/movim

RUN <<EOF
  set -e

  composer install

  # Create directories where movim needs to write things.
  for d in cache public public/cache; do
    test -d "$d" || mkdir "$d"
    chown www-data "$d"
  done
EOF

WORKDIR /var/www/movim
USER www-data
ENTRYPOINT [ "tini", "--", "php-fpm" ]
CMD [ "-F", "-O" ]

FROM fpm AS daemon

WORKDIR /var/www/movim
COPY --chmod=0555 daemon-entrypoint.sh .

USER www-data
ENTRYPOINT [ "tini", "--", "/var/www/movim/daemon-entrypoint.sh" ]
