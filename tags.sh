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

[ -x "$(which jq)" ] \
    || { echo "Invalid build environment: Missing runtime dependency: jq" >&2; exit 1; }

source "$CI_TOOLS_PATH/helper/common.sh.inc"
source "$CI_TOOLS_PATH/helper/git.sh.inc"

php_latest_version() {
    local VERSIONS_FILE="$1"
    local BRANCH="${2:-}"

    if [[ "$BRANCH" =~ ^[0-9]+(\.[0-9]+(\.[0-9]+([+~-].+)?)?)?$ ]]; then
        if [ -n "${BASH_REMATCH[2]}" ]; then
            # returns exact version
            jq -re '.[].version // empty' "$VERSIONS_FILE" \
                | grep -Fx "$BRANCH"
        elif [ -n "${BASH_REMATCH[1]}" ]; then
            # returns latest version of a given minor branch
            jq -re --arg BRANCH "$BRANCH" \
                '.[$BRANCH].version // empty' \
                "$VERSIONS_FILE"
        else
            # returns the latest versions of a given major branch
            jq -re --arg BRANCH "$BRANCH." \
                'with_entries(select(.key | startswith($BRANCH) and (endswith("-rc")|not))) | .[].version // empty' \
                "$VERSIONS_FILE" \
                | sort_semver \
                | head -n 1
        fi
    elif [ -z "$BRANCH" ]; then
        # returns the latest versions of all branches
        jq -re \
            'with_entries(select(.key | endswith("-rc")|not)) | .[].version // empty' \
            "$VERSIONS_FILE" \
            | sort_semver \
            | head -n 1
    else
        # invalid branch given
        return 1
    fi
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

BUILD_INFO=""
if [ $# -gt 0 ] && [[ "$1" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
    BUILD_INFO=".${1,,}"
fi

git_clone "$MERGE_IMAGE_GIT_REPO" "$MERGE_IMAGE_GIT_REF" "$BUILD_DIR/vendor" "./vendor"

echo + "VERSION=\"\$(php_latest_version ./vendor/versions.json $(quote "$VERSION"))\"" >&2
PHP_VERSION="$(php_latest_version "$BUILD_DIR/vendor/versions.json" "$VERSION" || true)"

if [ -z "$PHP_VERSION" ]; then
    echo "Unable to read PHP version from './vendor/versions.json': No version matching '$VERSION' found" >&2
    exit 1
elif ! [[ "$PHP_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)([+~-]|$) ]]; then
    echo "Unable to read PHP version from './vendor/versions.json': '$PHP_VERSION' is no valid version" >&2
    exit 1
fi

VERSION="$PHP_VERSION"
VERSION_MINOR="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
VERSION_MAJOR="${BASH_REMATCH[1]}"

echo + "VERSION_LATEST=\"\$(php_latest_version ./vendor/versions.json)\"" >&2
VERSION_LATEST="$(php_latest_version "$BUILD_DIR/vendor/versions.json")"

echo + "VERSION_LATEST_MINOR=\"\$(php_latest_version ./vendor/versions.json $(quote "$VERSION_MINOR"))\"" >&2
VERSION_LATEST_MINOR="$(php_latest_version "$BUILD_DIR/vendor/versions.json" "$VERSION_MINOR")"

echo + "VERSION_LATEST_MAJOR=\"\$(php_latest_version ./vendor/versions.json $(quote "$VERSION_MAJOR"))\"" >&2
VERSION_LATEST_MAJOR="$(php_latest_version "$BUILD_DIR/vendor/versions.json" "$VERSION_MAJOR")"

BUILD_INFO="$(date --utc +'%Y%m%d')$BUILD_INFO"

TAGS=( "v$VERSION" "v$VERSION-$BUILD_INFO" )

if [ "$VERSION" == "$VERSION_LATEST_MINOR" ]; then
    TAGS+=( "v$VERSION_MINOR" "v$VERSION_MINOR-$BUILD_INFO" )

    if [ "$VERSION" == "$VERSION_LATEST_MAJOR" ]; then
        TAGS+=( "v$VERSION_MAJOR" "v$VERSION_MAJOR-$BUILD_INFO" )

        if ! php_latest_version "$BUILD_DIR/vendor/versions.json" "$((VERSION_MAJOR + 1))" > /dev/null; then
            TAGS+=( "latest" )
        fi
    fi
fi

printf 'MILESTONE="%s"\n' "$VERSION_MINOR"
printf 'VERSION="%s"\n' "$VERSION"
printf 'TAGS="%s"\n' "${TAGS[*]}"
