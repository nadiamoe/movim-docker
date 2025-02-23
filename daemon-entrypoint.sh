#!/usr/bin/env sh

set -e

php vendor/bin/phinx migrate
php daemon.php start
