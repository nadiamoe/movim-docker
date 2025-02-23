FROM alpine:3.21.3 as downloader

WORKDIR /work

# Renovate updates the version below, which is also grepped by CI/CD to produce the build tag. Do not chage its format.
ARG MOVIM_VERSION=v0.29.2
ADD https://github.com/movim/movim/archive/refs/tags/${MOVIM_VERSION}.tar.gz .
RUN tar -xzf "${MOVIM_VERSION}.tar.gz" && mv movim-* movim # Remove version suffix.

FROM nginx:1.27.4-alpine as nginx

COPY --from=downloader /work/movim /var/www/movim
COPY default.nginx.conf /etc/nginx/conf.d/default.conf

FROM alpine:3.21.3 as fpm

# https://github.com/docker-library/php/blob/7deb69be16bf95dfd1f37183dc20e8fd21306bbc/8.4/alpine3.21/fpm/Dockerfile#L32
RUN adduser -u 82 -D -S -G www-data www-data

WORKDIR /var/www

RUN <<EOF
  set -e 

  apk add --no-cache \
    git \
    unzip \
    tini \
    php \
    php-fpm \
    php-curl \
    php-gd \
    php-dom \
    php-pdo \
    php-pdo_pgsql \
    php-pgsql \
    php-pecl-imagick \
    composer

  which php-fpm || ln -s /usr/sbin/php-fpm* /usr/sbin/php-fpm
  test -d /etc/php || ln -s /etc/php* /etc/php
EOF

RUN <<EOF
  set -e 

  sed -i 's|;error_log = .*|error_log = /proc/self/fd/2|' /etc/php/php-fpm.conf

  echo 'access.log = /proc/self/fd/2' >> /etc/php/php-fpm.d/www.conf
  echo 'catch_workers_output = yes' >> /etc/php/php-fpm.d/www.conf
  echo 'listen = 9000' >> /etc/php/php-fpm.d/www.conf
EOF

COPY --from=downloader /work/movim /var/www/movim
WORKDIR /var/www/movim

RUN <<EOF
  set -e

  composer install

  # Create directories where movim needs to write things.
  mkdir -p log cache public
  chown www-data log cache public
EOF

WORKDIR /var/www/movim
USER www-data
ENTRYPOINT [ "tini", "--", "php-fpm" ]
CMD [ "-F", "-O" ]

FROM fpm as daemon

WORKDIR /var/www/movim
COPY --chmod=0555 daemon-entrypoint.sh .

USER www-data
ENTRYPOINT [ "tini", "--", "/var/www/movim/daemon-entrypoint.sh" ]
