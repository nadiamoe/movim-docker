FROM php:8.4.4-fpm

WORKDIR /var/www
RUN rmdir html # Included in the default image

RUN <<EOF
  set -e

  apt-get update
  apt-get install -qq --no-install-suggests --no-install-recommends \
    git \
    unzip \
		libmagickwand-dev \
		libjpeg-dev \
		libpng-dev \
		libwebp-dev \
		libpq-dev \
		libzip-dev

  docker-php-ext-install -j "$(nproc)" gd pdo_pgsql
  pecl install imagick-3.7.0
  docker-php-ext-enable imagick
  rm -r /tmp/pear

EOF

# Renovate updates the version below, which is also grepped by CI/CD to produce the build tag. Do not chage its format.
ARG MOVIM_VERSION=v0.29.2

RUN <<EOF
  set -e

  curl -sSL https://github.com/movim/movim/archive/refs/tags/${MOVIM_VERSION}.tar.gz | tar -xz
  mv movim-* movim # Remove version suffix.

  cd movim

  curl -sS https://getcomposer.org/installer | php
  php composer.phar install
  rm composer.phar

  mkdir -p log cache public
  chown www-data log cache public
EOF
