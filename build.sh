#!/bin/bash
# php-fpm
# A php-fpm container with an improved configuration.
#
# Copyright (c) 2021  SGS Serious Gaming & Simulations GmbH
#
# This work is licensed under the terms of the MIT license.
# For a copy, see LICENSE file or <https://opensource.org/licenses/MIT>.
#
# SPDX-License-Identifier: MIT
# License-Filename: LICENSE

set -eu -o pipefail
export LC_ALL=C.UTF-8

[ -v CI_TOOLS ] && [ "$CI_TOOLS" == "SGSGermany" ] \
    || { echo "Invalid build environment: Environment variable 'CI_TOOLS' not set or invalid" >&2; exit 1; }

[ -v CI_TOOLS_PATH ] && [ -d "$CI_TOOLS_PATH" ] \
    || { echo "Invalid build environment: Environment variable 'CI_TOOLS_PATH' not set or invalid" >&2; exit 1; }

source "$CI_TOOLS_PATH/helper/common.sh.inc"
source "$CI_TOOLS_PATH/helper/container.sh.inc"
source "$CI_TOOLS_PATH/helper/container-alpine.sh.inc"
source "$CI_TOOLS_PATH/helper/git.sh.inc"

BUILD_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

if [ -v MILESTONE ]; then
    if [ ! -f "$BUILD_DIR/branches/$MILESTONE/container.env" ]; then
        echo "Invalid build environment: Invalid environment variable 'MILESTONE':" \
            "Container environment file '$BUILD_DIR/branches/$MILESTONE/container.env' not found" >&2
        exit 1
    fi

    source "$BUILD_DIR/branches/$MILESTONE/container.env"
else
    source "$BUILD_DIR/container.env"
fi

if [ "$VERSION" != "$MILESTONE" ] && [[ "$VERSION" != "$MILESTONE".* ]]; then
    echo "Invalid build environment: Invalid environment variable 'MILESTONE':" \
        "Version '$VERSION' is no part of the '$MILESTONE' branch" >&2
    exit 1
fi

readarray -t -d' ' TAGS < <(printf '%s' "$TAGS")

echo + "CONTAINER=\"\$(buildah from $(quote "$BASE_IMAGE"))\"" >&2
CONTAINER="$(buildah from "$BASE_IMAGE")"

echo + "MOUNT=\"\$(buildah mount $(quote "$CONTAINER"))\"" >&2
MOUNT="$(buildah mount "$CONTAINER")"

echo + "sed -i -E 's/^@community (.+)$/\1/' …/etc/apk/repositories" >&2
sed -i -E 's/^@community (.+)$/\1/' "$MOUNT/etc/apk/repositories"

con_commit "$CONTAINER" "$IMAGE-base"

git_clone "$MERGE_IMAGE_GIT_REPO" "$MERGE_IMAGE_GIT_REF" "$BUILD_DIR/vendor" "./vendor"

con_build --tag "$IMAGE-upstream" \
    --from "$IMAGE-base" --check-from "$MERGE_IMAGE_BASE_IMAGE_PATTERN" \
    "$BUILD_DIR/vendor/$MERGE_IMAGE_BUD_CONTEXT" "./vendor/$MERGE_IMAGE_BUD_CONTEXT"

echo + "CONTAINER=\"\$(buildah from $(quote "$IMAGE-upstream"))\"" >&2
CONTAINER="$(buildah from "$IMAGE-upstream")"

echo + "MOUNT=\"\$(buildah mount $(quote "$CONTAINER"))\"" >&2
MOUNT="$(buildah mount "$CONTAINER")"

echo + "rsync -v -rl --exclude .gitignore ./src/ …/" >&2
rsync -v -rl --exclude '.gitignore' "$BUILD_DIR/src/" "$MOUNT/"

if [ -d "$BUILD_DIR/branches/$MILESTONE/src" ]; then
    echo + "rsync -v -rl --exclude .gitignore $(quote "./branches/$MILESTONE/src/") …/" >&2
    rsync -v -rl --exclude '.gitignore' "$BUILD_DIR/branches/$MILESTONE/src/" "$MOUNT/"
fi

# prepare users
user_changeuid "$CONTAINER" www-data 65536 "/usr/local/php"

user_add "$CONTAINER" php-sock 65537

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

# php config
echo + "mv -t …/etc/php/ …/usr/local/etc/php/php.ini-{production,development}" >&2
mv -t "$MOUNT/etc/php/" \
    "$MOUNT/usr/local/etc/php/php.ini-production" \
    "$MOUNT/usr/local/etc/php/php.ini-development"

echo + "rm -rf …/usr/local/etc/php/conf.d" >&2
rm -rf "$MOUNT/usr/local/etc/php/conf.d"

echo + "ln -s /etc/php/php.ini …/usr/local/etc/php/php.ini" >&2
ln -s "/etc/php/php.ini" "$MOUNT/usr/local/etc/php/php.ini"

echo + "ln -s /etc/php/conf.d/ …/usr/local/etc/php/conf.d" >&2
ln -s "/etc/php/conf.d/" "$MOUNT/usr/local/etc/php/conf.d"

# php-fpm config
echo + "rm -f …/usr/local/etc/php-fpm.conf{,.default}" >&2
rm -f "$MOUNT/usr/local/etc/php-fpm.conf" "$MOUNT/usr/local/etc/php-fpm.conf.default"

echo + "rm -rf …/usr/local/etc/php-fpm.conf.d" >&2
rm -rf "$MOUNT/usr/local/etc/php-fpm.conf.d"

echo + "ln -s /etc/php-fpm/php-fpm.conf …/usr/local/etc/php-fpm.conf" >&2
ln -s "/etc/php-fpm/php-fpm.conf" "$MOUNT/usr/local/etc/php-fpm.conf"

# pear config
echo + "mv …/usr/local/etc/pear.conf …/etc/pear.conf" >&2
mv "$MOUNT/usr/local/etc/pear.conf" "$MOUNT/etc/pear.conf"

echo + "ln -s /etc/pear.conf …/usr/local/etc/pear.conf" >&2
ln -s "/etc/pear.conf" "$MOUNT/usr/local/etc/pear.conf"

# branch-specific build script
if [ -f "$BUILD_DIR/branches/$MILESTONE/build.sh.inc" ]; then
    echo + "source $(quote "./branches/$MILESTONE/build.sh.inc")" >&2
    source "$BUILD_DIR/branches/$MILESTONE/build.sh.inc"
fi

# finalize image
cleanup "$CONTAINER"

cmd buildah config \
    --port "-" \
    "$CONTAINER"

cmd buildah config \
    --volume "/run/php-fpm" \
    --volume "/var/log/php" \
    "$CONTAINER"

echo + "PHP_VERSION=\"\$(buildah run $CONTAINER -- /bin/sh -c 'echo \"\$PHP_VERSION\"')\"" >&2
PHP_VERSION="$(buildah run "$CONTAINER" -- /bin/sh -c 'echo "$PHP_VERSION"')"

cmd buildah config \
    --annotation org.opencontainers.image.title="php-fpm" \
    --annotation org.opencontainers.image.description="A php-fpm container with an improved configuration." \
    --annotation org.opencontainers.image.version="$PHP_VERSION" \
    --annotation org.opencontainers.image.url="https://github.com/SGSGermany/php-fpm" \
    --annotation org.opencontainers.image.authors="SGS Serious Gaming & Simulations GmbH" \
    --annotation org.opencontainers.image.vendor="SGS Serious Gaming & Simulations GmbH" \
    --annotation org.opencontainers.image.licenses="MIT" \
    --annotation org.opencontainers.image.base.name="$BASE_IMAGE" \
    --annotation org.opencontainers.image.base.digest="$(podman image inspect --format '{{.Digest}}' "$BASE_IMAGE")" \
    "$CONTAINER"

con_commit "$CONTAINER" "$IMAGE" "${TAGS[@]}"
