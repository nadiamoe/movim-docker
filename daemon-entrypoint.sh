#!/usr/bin/env sh

set -e

echo "Running migrations"
php vendor/bin/phinx migrate

echo "Running daemon"
php daemon.php start --debug
