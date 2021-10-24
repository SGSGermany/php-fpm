#!/bin/bash
# php-fpm
# A php-fpm container with an improved configuration structure.
#
# Copyright (c) 2021  SGS Serious Gaming & Simulations GmbH
#
# This work is licensed under the terms of the MIT license.
# For a copy, see LICENSE file or <https://opensource.org/licenses/MIT>.
#
# SPDX-License-Identifier: MIT
# License-Filename: LICENSE

set -e
export LC_ALL=C
shopt -s nullglob

cmd() {
    echo + "$@"
    "$@"
    return $?
}

BUILD_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
[ -f "$BUILD_DIR/../container.env" ] && source "$BUILD_DIR/../container.env" \
    || { echo "ERROR: Container environment not found" >&2; exit 1; }

readarray -t -d' ' TAGS < <(printf '%s' "$DEFAULT_TAGS")

echo + "CONTAINER=\"\$(buildah from $BASE_IMAGE)\""
CONTAINER="$(buildah from "$BASE_IMAGE")"

echo + "MOUNT=\"\$(buildah mount $CONTAINER)\""
MOUNT="$(buildah mount "$CONTAINER")"

echo + "rsync -v -rl --exclude .gitignore ./src/ …/"
rsync -v -rl --exclude '.gitignore' "$BUILD_DIR/src/" "$MOUNT/"

# php config
echo + "mv -t …/etc/php/ …/usr/local/etc/php/php.ini-{production,development}"
mv -t "$MOUNT/etc/php/" \
    "$MOUNT/usr/local/etc/php/php.ini-production" \
    "$MOUNT/usr/local/etc/php/php.ini-development"

echo + "rm -rf …/usr/local/etc/php/conf.d"
rm -rf "$MOUNT/usr/local/etc/php/conf.d"

echo + "ln -s /etc/php/php.ini …/usr/local/etc/php/php.ini"
ln -s "/etc/php/php.ini" "$MOUNT/usr/local/etc/php/php.ini"

echo + "ln -s /etc/php/conf.d/ …/usr/local/etc/php/conf.d"
ln -s "/etc/php/conf.d/" "$MOUNT/usr/local/etc/php/conf.d"

# php-fpm config
echo + "rm -f …/usr/local/etc/php-fpm.conf{,.default}"
rm -f "$MOUNT/usr/local/etc/php-fpm.conf" "$MOUNT/usr/local/etc/php-fpm.conf.default"

echo + "rm -rf …/usr/local/etc/php-fpm.conf.d"
rm -rf "$MOUNT/usr/local/etc/php-fpm.conf.d"

echo + "ln -s /etc/php-fpm/php-fpm.conf …/usr/local/etc/php-fpm.conf"
ln -s "/etc/php-fpm/php-fpm.conf" "$MOUNT/usr/local/etc/php-fpm.conf"

# pear config
echo + "mv …/usr/local/etc/pear.conf …/etc/pear.conf"
mv "$MOUNT/usr/local/etc/pear.conf" "$MOUNT/etc/pear.conf"

echo + "ln -s /etc/pear.conf …/usr/local/etc/pear.conf"
ln -s "/etc/pear.conf" "$MOUNT/usr/local/etc/pear.conf"

echo + "PHP_VERSION=\"\$(buildah run $CONTAINER -- /bin/sh -c 'echo \"\$PHP_VERSION\"')\""
PHP_VERSION="$(buildah run "$CONTAINER" -- /bin/sh -c 'echo "$PHP_VERSION"')"

cmd buildah config \
    --annotation org.opencontainers.image.title="php-fpm" \
    --annotation org.opencontainers.image.description="A php-fpm container with an improved configuration structure." \
    --annotation org.opencontainers.image.version="$PHP_VERSION" \
    --annotation org.opencontainers.image.url="https://github.com/SGSGermany/php-fpm" \
    --annotation org.opencontainers.image.authors="SGS Serious Gaming & Simulations GmbH" \
    --annotation org.opencontainers.image.vendor="SGS Serious Gaming & Simulations GmbH" \
    --annotation org.opencontainers.image.licenses="MIT" \
    --annotation org.opencontainers.image.base.name="$BASE_IMAGE" \
    --annotation org.opencontainers.image.base.digest="$(podman image inspect --format '{{.Digest}}' "$BASE_IMAGE")" \
    "$CONTAINER"

cmd buildah commit "$CONTAINER" "$IMAGE:${TAGS[0]}"
cmd buildah rm "$CONTAINER"

for TAG in "${TAGS[@]:1}"; do
    cmd buildah tag "$IMAGE:${TAGS[0]}" "$IMAGE:$TAG"
done
