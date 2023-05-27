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
shopt -s nullglob

[ -v CI_TOOLS ] && [ "$CI_TOOLS" == "SGSGermany" ] \
    || { echo "Invalid build environment: Environment variable 'CI_TOOLS' not set or invalid" >&2; exit 1; }

[ -v CI_TOOLS_PATH ] && [ -d "$CI_TOOLS_PATH" ] \
    || { echo "Invalid build environment: Environment variable 'CI_TOOLS_PATH' not set or invalid" >&2; exit 1; }

source "$CI_TOOLS_PATH/helper/common.sh.inc"
source "$CI_TOOLS_PATH/helper/common-traps.sh.inc"

prepare_local_conf() {
    if [ ! -d "$DIFF_DIR/raw/local/$(dirname "$2")" ]; then
        echo + "mkdir $(quote "\$DIFF_DIR/{raw,clean}/local/$(dirname "$2")")" >&2
        mkdir "$DIFF_DIR/raw/local/$(dirname "$2")" \
            "$DIFF_DIR/clean/local/$(dirname "$2")"
    fi

    echo + "cp $(quote "./branches/$MILESTONE/base-conf/$1") $(quote "\$DIFF_DIR/raw/local/$2")" >&2
    cp "$BUILD_DIR/branches/$MILESTONE/base-conf/$1" "$DIFF_DIR/raw/local/$2"

    echo + "clean_conf $(quote "\$DIFF_DIR/raw/local/$2") $(quote "\$DIFF_DIR/clean/local/$2")" >&2
    clean_conf "$DIFF_DIR/raw/local/$2" "$DIFF_DIR/clean/local/$2"
}

prepare_upstream_conf() {
    if [ ! -d "$DIFF_DIR/raw/upstream/$(dirname "$2")" ]; then
        echo + "mkdir $(quote "\$DIFF_DIR/{raw,clean}/upstream/$(dirname "$2")")" >&2
        mkdir "$DIFF_DIR/raw/upstream/$(dirname "$2")" \
            "$DIFF_DIR/clean/upstream/$(dirname "$2")"
    fi

    echo + "cp $(quote "…/$1") $(quote "\$DIFF_DIR/raw/upstream/$2")" >&2
    cp "$MOUNT/$1" "$DIFF_DIR/raw/upstream/$2"

    echo + "clean_conf $(quote "\$DIFF_DIR/raw/upstream/$2") $(quote "\$DIFF_DIR/clean/upstream/$2")" >&2
    clean_conf "$DIFF_DIR/raw/upstream/$2" "$DIFF_DIR/clean/upstream/$2"
}

clean_conf() {
    sed -e 's/^\([^;]*\);.*$/\1/' -e '/^\s*$/d' "$1" > "$2"
}

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

TAG="${TAGS%% *}"

# check local image storage
echo + "IMAGE_ID=\"\$(podman image inspect --format '{{.Id}}' $(quote "localhost/$IMAGE:$TAG"))\"" >&2
IMAGE_ID="$(podman image inspect --format '{{.Id}}' "localhost/$IMAGE:$TAG" 2> /dev/null || true)"

if [ -z "$IMAGE_ID" ]; then
    echo "Failed to check base config of image 'localhost/$IMAGE:$TAG': No image with this tag found" >&2
    exit 1
fi

echo + "MERGE_IMAGE=\"\$(podman image inspect --format '{{.Id}}' $(quote "localhost/$IMAGE-base"))\"" >&2
MERGE_IMAGE="$(podman image inspect --format '{{.Id}}' "localhost/$IMAGE-base" 2> /dev/null || true)"

if [ -z "$MERGE_IMAGE" ]; then
    echo "Failed to check base config of image 'localhost/$IMAGE:$TAG':" \
        "Invalid intermediate image 'localhost/$IMAGE-base': No image with this tag found" >&2
    exit 1
fi

echo + "IMAGE_PARENT=\"\$(podman image inspect --format '{{.Parent}}' $(quote "localhost/$IMAGE:$TAG"))\"" >&2
IMAGE_PARENT="$(podman image inspect --format '{{.Parent}}' "localhost/$IMAGE:$TAG" || true)"

if [ -z "$IMAGE_PARENT" ]; then
    echo "Failed to check base config of image 'localhost/$IMAGE:$TAG': Image metadata lacks information about the image's parent image" >&2
    exit 1
elif [ "$IMAGE_PARENT" != "$MERGE_IMAGE" ]; then
    echo "Failed to check base config of image 'localhost/$IMAGE:$TAG': Invalid intermediate image 'localhost/$IMAGE-base':" \
        "Image ID doesn't match with the parent image ID of 'localhost/$IMAGE:$TAG'" >&2
    echo "ID of parent image of 'localhost/$IMAGE:$TAG': $IMAGE_PARENT" >&2
    echo "ID of intermediate image 'localhost/$IMAGE-base': $MERGE_IMAGE" >&2
    exit 1
fi

# prepare image
echo + "CONTAINER=\"\$(buildah from $(quote "$MERGE_IMAGE"))\"" >&2
CONTAINER="$(buildah from "$MERGE_IMAGE")"

trap_exit buildah rm "$CONTAINER"

echo + "MOUNT=\"\$(buildah mount $(quote "$CONTAINER"))\"" >&2
MOUNT="$(buildah mount "$CONTAINER")"

echo + "DIFF_DIR=\"\$(mktemp -d)\"" >&2
DIFF_DIR="$(mktemp -d)"

trap_exit rm -rf "$DIFF_DIR"

# prepare diff
echo + "mkdir $(quote "\$DIFF_DIR/{raw,clean}" "\$DIFF_DIR/{raw,clean}/{local,upstream}")" >&2
mkdir \
    "$DIFF_DIR/raw" "$DIFF_DIR/raw/local" "$DIFF_DIR/raw/upstream" \
    "$DIFF_DIR/clean" "$DIFF_DIR/clean/local" "$DIFF_DIR/clean/upstream"

# php config
prepare_local_conf "php/php.ini" "php/php.ini"
for FILE in "$BUILD_DIR/branches/$MILESTONE/base-conf/php/conf.d/"*".ini"; do
    prepare_local_conf "php/conf.d/$(basename "$FILE")" "php/conf.d/$(basename "$FILE")"
done

prepare_upstream_conf "usr/local/etc/php/php.ini-production" "php/php.ini"
for FILE in "$MOUNT/usr/local/etc/php/conf.d/"*".ini"; do
    prepare_upstream_conf "usr/local/etc/php/conf.d/$(basename "$FILE")" "php/conf.d/$(basename "$FILE")"
done

# php-fpm config
prepare_local_conf "php-fpm/php-fpm.conf" "php-fpm/php-fpm.conf"
for FILE in "$BUILD_DIR/branches/$MILESTONE/base-conf/php-fpm/conf.d/"*".conf"; do
    prepare_local_conf "php-fpm/conf.d/$(basename "$FILE")" "php-fpm/conf.d/$(basename "$FILE")"
done

prepare_upstream_conf "usr/local/etc/php-fpm.conf" "php-fpm/php-fpm.conf"
for FILE in "$MOUNT/usr/local/etc/php-fpm.d/"*".conf"; do
    prepare_upstream_conf "usr/local/etc/php-fpm.d/$(basename "$FILE")" "php-fpm/conf.d/$(basename "$FILE")"
done

# diff configs
echo + "diff -q -r \$DIFF_DIR/clean/local/ \$DIFF_DIR/clean/upstream/" >&2
if ! diff -q -r "$DIFF_DIR/clean/local/" "$DIFF_DIR/clean/upstream/" > /dev/null; then
    ( cd "$DIFF_DIR/raw" ; diff -u -r ./local/ ./upstream/ )
    exit 1
fi
