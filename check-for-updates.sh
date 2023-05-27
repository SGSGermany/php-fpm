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
source "$CI_TOOLS_PATH/helper/chkupd.sh.inc"
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

TAG="${TAGS%% *}"

# check whether the base image was updated
chkupd_baseimage "$REGISTRY/$OWNER/$IMAGE" "$TAG" || exit 0

# check whether ./vendor/versions.json indicates a new version
git_clone "$MERGE_IMAGE_GIT_REPO" "$MERGE_IMAGE_GIT_REF" "$BUILD_DIR/vendor" "./vendor"

echo + "VERSION=\"\$(jq -re --arg BRANCH $(quote "$MILESTONE") '.[\$BRANCH].version // empty' ./vendor/versions.json)\"" >&2
VERSION="$(jq -re --arg BRANCH "$MILESTONE" '.[$BRANCH].version // empty' "$BUILD_DIR/vendor/versions.json" || true)"

if [ -z "$VERSION" ]; then
    echo "Unable to read PHP version from './vendor/versions.json': No version matching '$MILESTONE' found" >&2
    exit 1
elif ! [[ "$VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)([+~-]|$) ]]; then
    echo "Unable to read PHP version from './vendor/versions.json': '$VERSION' is no valid version" >&2
    exit 1
fi

chkupd_image_version "$REGISTRY/$OWNER/$IMAGE:$TAG" "$VERSION" || exit 0
