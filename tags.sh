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

php_ls_versions() {
    jq -re --arg "VERSION" "$1" \
        '.Tags[]|select(test("^[0-9]+\\.[0-9]+\\.[0-9]+-fpm-alpine$") and startswith($VERSION + "."))[:-11]' \
        <<<"$BASE_IMAGE_REPO_TAGS" | sort_semver
}

sort_semver() {
    sed '/-/!{s/$/_/}' | sort -V -r | sed 's/_$//'
}

BUILD_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
[ -f "$BUILD_DIR/container.env" ] && source "$BUILD_DIR/container.env" \
    || { echo "ERROR: Container environment not found" >&2; exit 1; }

IMAGE_ID="$(podman pull "$BASE_IMAGE" || true)"
if [ -z "$IMAGE_ID" ]; then
    echo "Failed to pull image '$BASE_IMAGE': No image with this tag found" >&2
    exit 1
fi

PHP_VERSION="$(podman image inspect --format '{{range .Config.Env}}{{printf "%q\n" .}}{{end}}' "$BASE_IMAGE" \
    | sed -ne 's/^"PHP_VERSION=\(.*\)"$/\1/p')"
if [ -z "$PHP_VERSION" ]; then
    echo "Unable to read image's env variable 'PHP_VERSION': No such variable" >&2
    exit 1
elif ! [[ "$PHP_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "Unable to read image's env variable 'PHP_VERSION': '$PHP_VERSION' is no valid version" >&2
    exit 1
fi

PHP_VERSION_MINOR="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
PHP_VERSION_MAJOR="${BASH_REMATCH[1]}"

BASE_IMAGE_REPO_TAGS="$(skopeo list-tags "docker://${BASE_IMAGE%:*}" || true)"
if [ -z "$BASE_IMAGE_REPO_TAGS" ]; then
    echo "Unable to read tags from container repository 'docker://${BASE_IMAGE%:*}'" >&2
    exit 1
fi

TAG_DATE="$(date -u +'%Y%m%d%H%M')"

DEFAULT_TAGS=( "v$PHP_VERSION-default" "v$PHP_VERSION-default_$TAG_DATE" )
BASE_TAGS=( "v$PHP_VERSION" "v${PHP_VERSION}_$TAG_DATE" )

if [ "$PHP_VERSION" == "$(php_ls_versions "$PHP_VERSION_MINOR" | head -n 1)" ]; then
    DEFAULT_TAGS+=( "v$PHP_VERSION_MINOR-default" "v$PHP_VERSION_MINOR-default_$TAG_DATE" )
    BASE_TAGS+=( "v$PHP_VERSION_MINOR" "v${PHP_VERSION_MINOR}_$TAG_DATE" )

    if [ "$PHP_VERSION" == "$(php_ls_versions "$PHP_VERSION_MAJOR" | head -n 1)" ]; then
        DEFAULT_TAGS+=( "v$PHP_VERSION_MAJOR-default" "v$PHP_VERSION_MAJOR-default_$TAG_DATE" )
        BASE_TAGS+=( "v$PHP_VERSION_MAJOR" "v${PHP_VERSION_MAJOR}_$TAG_DATE" )

        if ! php_ls_versions "$((PHP_VERSION_MAJOR + 1))" > /dev/null; then
            DEFAULT_TAGS+=( "latest-default" )
            BASE_TAGS+=( "latest" )
        fi
    fi
fi

printf 'VERSION="%s"\n' "$PHP_VERSION"
printf 'DEFAULT_TAGS="%s"\n' "${DEFAULT_TAGS[*]}"
printf 'BASE_TAGS="%s"\n' "${BASE_TAGS[*]}"
