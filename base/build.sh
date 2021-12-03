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

set -eu -o pipefail
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

cmd buildah config --port "-" "$CONTAINER"

cmd buildah config \
    --volume "/run/php-fpm" \
    --volume "/var/log/php" \
    "$CONTAINER"

cmd buildah config \
    --workingdir "/var/www/html" \
    "$CONTAINER"

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
    --annotation org.opencontainers.image.base.name="$REGISTRY/$OWNER/$IMAGE:$DEFAULT_TAG" \
    --annotation org.opencontainers.image.base.digest="$(podman image inspect --format '{{.Digest}}' "$IMAGE:$DEFAULT_TAG")" \
    "$CONTAINER"

cmd buildah commit "$CONTAINER" "$IMAGE:${TAGS[0]}"
cmd buildah rm "$CONTAINER"

for TAG in "${TAGS[@]:1}"; do
    cmd buildah tag "$IMAGE:${TAGS[0]}" "$IMAGE:$TAG"
done
