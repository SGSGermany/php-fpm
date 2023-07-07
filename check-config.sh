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
source "$CI_TOOLS_PATH/helper/chkconf.sh.inc"

chkconf_clean() {
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

echo + "MERGE_IMAGE=\"\$(podman image inspect --format '{{.Id}}' $(quote "localhost/$IMAGE-upstream"))\"" >&2
MERGE_IMAGE="$(podman image inspect --format '{{.Id}}' "localhost/$IMAGE-upstream" 2> /dev/null || true)"

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

# prepare image for diffing
echo + "CONTAINER=\"\$(buildah from $(quote "$MERGE_IMAGE"))\"" >&2
CONTAINER="$(buildah from "$MERGE_IMAGE")"

trap_exit buildah rm "$CONTAINER"

echo + "MOUNT=\"\$(buildah mount $(quote "$CONTAINER"))\"" >&2
MOUNT="$(buildah mount "$CONTAINER")"

echo + "CHKCONF_DIR=\"\$(mktemp -d)\"" >&2
CHKCONF_DIR="$(mktemp -d)"

trap_exit rm -rf "$CHKCONF_DIR"

LOCAL_FILES=()
UPSTRAM_FILES=()

# php config
LOCAL_FILES+=( "php/php.ini" "php/php.ini" )
for FILE in "$BUILD_DIR/branches/$MILESTONE/base-conf/php/conf.d/"*".ini"; do
    LOCAL_FILES+=( "php/conf.d/$(basename "$FILE")" "php/conf.d/$(basename "$FILE")" )
done

UPSTREAM_FILES+=( "usr/local/etc/php/php.ini-production" "php/php.ini" )
for FILE in "$MOUNT/usr/local/etc/php/conf.d/"*".ini"; do
    UPSTREAM_FILES+=( "usr/local/etc/php/conf.d/$(basename "$FILE")" "php/conf.d/$(basename "$FILE")" )
done

# php-fpm config
LOCAL_FILES+=( "php-fpm/php-fpm.conf" "php-fpm/php-fpm.conf" )
for FILE in "$BUILD_DIR/branches/$MILESTONE/base-conf/php-fpm/conf.d/"*".conf"; do
    LOCAL_FILES+=( "php-fpm/conf.d/$(basename "$FILE")" "php-fpm/conf.d/$(basename "$FILE")" )
done

UPSTREAM_FILES+=( "usr/local/etc/php-fpm.conf" "php-fpm/php-fpm.conf" )
for FILE in "$MOUNT/usr/local/etc/php-fpm.d/"*".conf"; do
    UPSTREAM_FILES+=( "usr/local/etc/php-fpm.d/$(basename "$FILE")" "php-fpm/conf.d/$(basename "$FILE")" )
done

# diff configs
chkconf_prepare \
    --local "$BUILD_DIR/branches/$MILESTONE/base-conf" "./branches/$MILESTONE/base-conf" \
    "$CHKCONF_DIR" "/tmp/…" \
    "${LOCAL_FILES[@]}"

chkconf_prepare \
    --upstream "$MOUNT" "…" \
    "$CHKCONF_DIR" "/tmp/…" \
    "${UPSTREAM_FILES[@]}"

chkconf_diff "$CHKCONF_DIR" "/tmp/…"
