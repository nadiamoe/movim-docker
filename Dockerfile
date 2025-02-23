FROM php:8.4.4-fpm-alpine

WORKDIR /var/www

RUN <<EOF
  set -e

  rmdir html # Included in the default image

  apk add --no-cache \
    git \
    unzip \
    php-curl \
    php-gd \
    php-dom \
    php-pdo \
    php-pdo_pgsql \
    php-pgsql \
    php-pecl-imagick \
    composer
EOF

# Renovate updates the version below, which is also grepped by CI/CD to produce the build tag. Do not chage its format.
ARG MOVIM_VERSION=v0.29.2
RUN curl -sSL https://github.com/movim/movim/archive/refs/tags/${MOVIM_VERSION}.tar.gz | tar -xz && mv movim-* movim # Remove version suffix.

WORKDIR /var/www/movim

RUN <<EOF
  set -e

  composer install

  mkdir -p log cache public
  chown www-data log cache public
EOF
