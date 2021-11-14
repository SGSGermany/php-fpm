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

cmd() {
    echo + "$@"
    "$@"
    return $?
}

BUILD_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
[ -f "$BUILD_DIR/../container.env" ] && source "$BUILD_DIR/../container.env" \
    || { echo "ERROR: Container environment not found" >&2; exit 1; }

readarray -t -d' ' TAGS < <(printf '%s' "$BASE_TAGS")
DEFAULT_TAG="${DEFAULT_TAGS%% *}"

echo + "CONTAINER=\"\$(buildah from $IMAGE:$DEFAULT_TAG)\""
CONTAINER="$(buildah from "$IMAGE:$DEFAULT_TAG")"

echo + "MOUNT=\"\$(buildah mount $CONTAINER)\""
MOUNT="$(buildah mount "$CONTAINER")"

echo + "rsync -v -rl --exclude .gitignore ./src/ …/"
rsync -v -rl --exclude '.gitignore' "$BUILD_DIR/src/" "$MOUNT/"

# change UID and GID of user 'www-data'
echo + "OLD_PHP_UID=\"\$(grep ^www-data: "$MOUNT/etc/passwd" | cut -d: -f3)\""
OLD_PHP_UID="$(grep ^www-data: "$MOUNT/etc/passwd" | cut -d: -f3)"

echo + "OLD_PHP_GID=\"\$(grep ^www-data: "$MOUNT/etc/group" | cut -d: -f3)\""
OLD_PHP_GID="$(grep ^www-data: "$MOUNT/etc/group" | cut -d: -f3)"

cmd buildah run "$CONTAINER" -- \
    deluser www-data

cmd buildah run "$CONTAINER" -- \
    adduser -u 65536 -s "/sbin/nologin" -D -h "/usr/local/php" -H www-data

cmd buildah run "$CONTAINER" -- \
    find / -path /sys -prune -o -path /proc -prune -o -user "$OLD_PHP_UID" -exec chown www-data -h {} \;

cmd buildah run "$CONTAINER" -- \
    find / -path /sys -prune -o -path /proc -prune -o -group "$OLD_PHP_GID" -exec chgrp www-data -h {} \;

# add user 'php-sock'
cmd buildah run "$CONTAINER" -- \
    adduser -u 65537 -s "/sbin/nologin" -D -h "/" -H php-sock

cmd buildah run "$CONTAINER" -- \
    addgroup www-data php-sock

# fix permissions
cmd buildah run "$CONTAINER" -- \
    chown www-data:www-data \
        "/run/php-fpm" \
        "/tmp/php" \
        "/tmp/php/php-tmp" \
        "/tmp/php/php-uploads" \
        "/tmp/php/php-session" \
        "/var/log/php"

cmd buildah run "$CONTAINER" -- \
    chmod 750 \
        "/run/php-fpm" \
        "/tmp/php" \
        "/tmp/php/php-tmp" \
        "/tmp/php/php-uploads" \
        "/tmp/php/php-session" \
        "/var/log/php"

cmd buildah run "$CONTAINER" -- \
    chmod +t "/tmp/php"

cmd buildah config \
    --volume "/run/php-fpm" \
    --volume "/var/log/php" \
    "$CONTAINER"

cmd buildah config \
    --workingdir "/var/www/html" \
    "$CONTAINER"

cmd buildah commit "$CONTAINER" "$IMAGE:${TAGS[0]}"
cmd buildah rm "$CONTAINER"

for TAG in "${TAGS[@]:1}"; do
    cmd buildah tag "$IMAGE:${TAGS[0]}" "$IMAGE:$TAG"
done
