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

[ -x "$(which curl)" ] \
    || { echo "Invalid build environment: Missing runtime dependency: curl" >&2; exit 1; }

source "$CI_TOOLS_PATH/helper/common.sh.inc"
source "$CI_TOOLS_PATH/helper/git.sh.inc"

php_local_branches() {
    local VERSIONS_FILE="$1"

    jq -re 'to_entries[] | select(.key | endswith("-rc")|not) | .key' "$VERSIONS_FILE" \
        | sort_semver
}

php_global_branches() {
    local VERSION_URL="https://www.php.net/releases/index.php?json"

    local VERSION_JSON="$(curl -sSL -o - "$VERSION_URL")"
    if [ -z "$VERSION_JSON" ]; then
        echo "Unable to read supported PHP branches: HTTP request '$VERSION_URL' failed" >&2
        return 1
    elif ! jq -e '.' > /dev/null 2>&1 <<< "$VERSION_JSON"; then
        echo "Unable to read supported PHP branches: HTTP request '$VERSION_URL' returned a malformed response: $(head -n1 <<< "$VERSION_JSON")" >&2
        return 1
    fi

    jq -re '.[].supported_versions[]' <<< "$VERSION_JSON" \
        | sort_semver
}

php_latest_local_version() {
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

php_latest_global_version() {
    local BRANCH="${1:-}"

    local VERSION_URL="https://www.php.net/releases/index.php?json"
    [ -z "$BRANCH" ] || VERSION_URL+="&max=1&version=$BRANCH"

    local VERSION_JSON="$(curl -sSL -o - "$VERSION_URL")"
    if [ -z "$VERSION_JSON" ]; then
        echo "Unable to read latest PHP version: HTTP request '$VERSION_URL' failed" >&2
        return 1
    elif ! jq -e '.' > /dev/null 2>&1 <<< "$VERSION_JSON"; then
        echo "Unable to read latest PHP version: HTTP request '$VERSION_URL' returned a malformed response: $(head -n1 <<< "$VERSION_JSON")" >&2
        return 1
    fi

    local VERSION
    [ -n "$BRANCH" ] \
        && VERSION="$(jq -re 'keys[]' <<< "$VERSION_JSON")" \
        || VERSION="$(jq -re 'first(.[].version)' <<< "$VERSION_JSON")"

    [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+~-]|$) ]] || return 1
    echo "$VERSION"
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

git_clone "$MERGE_IMAGE_GIT_REPO" "$MERGE_IMAGE_GIT_REF" "$BUILD_DIR/vendor" "./vendor"

echo + "VERSION=\"\$(php_latest_local_version ./vendor/versions.json $(quote "$MILESTONE"))\"" >&2
VERSION="$(php_latest_local_version "$BUILD_DIR/vendor/versions.json" "$MILESTONE" || true)"

if [ -z "$VERSION" ]; then
    echo "Unable to read PHP version from './vendor/versions.json': No version matching '$MILESTONE' found" >&2
    exit 1
elif ! [[ "$VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)([+~-]|$) ]]; then
    echo "Unable to read PHP version from './vendor/versions.json': '$VERSION' is no valid version" >&2
    exit 1
fi

VERSION_MINOR="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
VERSION_MAJOR="${BASH_REMATCH[1]}"

echo + "BRANCHES_LOCAL=\"\$(php_local_branches ./vendor/versions.json)\"" >&2
BRANCHES_LOCAL="$(php_local_branches "$BUILD_DIR/vendor/versions.json")"

echo + "VERSION_LATEST=\"\$(php_latest_local_version ./vendor/versions.json)\"" >&2
VERSION_LATEST_LOCAL="$(php_latest_local_version "$BUILD_DIR/vendor/versions.json")"

echo + "VERSION_LATEST_MINOR=\"\$(php_latest_local_version ./vendor/versions.json $(quote "$VERSION_MINOR"))\"" >&2
VERSION_LATEST_LOCAL_MINOR="$(php_latest_local_version "$BUILD_DIR/vendor/versions.json" "$VERSION_MINOR")"

echo + "VERSION_LATEST_MAJOR=\"\$(php_latest_local_version ./vendor/versions.json $(quote "$VERSION_MAJOR"))\"" >&2
VERSION_LATEST_LOCAL_MAJOR="$(php_latest_local_version "$BUILD_DIR/vendor/versions.json" "$VERSION_MAJOR")"

echo + "BRANCHES_GLOBAL=\"\$(php_global_branches)\"" >&2
BRANCHES_GLOBAL="$(php_global_branches)"

echo + "VERSION_LATEST_GLOBAL=\"\$(php_latest_global_version)\"" >&2
VERSION_LATEST_GLOBAL="$(php_latest_global_version)"

echo + "VERSION_LATEST_GLOBAL_MINOR=\"\$(php_latest_global_version $(quote "$VERSION_MINOR"))\"" >&2
VERSION_LATEST_GLOBAL_MINOR="$(php_latest_global_version "$VERSION_MINOR")"

echo + "VERSION_LATEST_GLOBAL_MAJOR=\"\$(php_latest_global_version $(quote "$VERSION_MAJOR"))\"" >&2
VERSION_LATEST_GLOBAL_MAJOR="$(php_latest_global_version "$VERSION_MAJOR")"

echo + "SUPPORT_STATUS=\"\$([ $(quote "$VERSION_MINOR") == $(quote "$VERSION_LATEST_GLOBAL_MAJOR") ] && echo \"Latest\"" \
    "|| { grep -q -Fx $(quote "$VERSION_MINOR") <<< \"\$BRANCHES_GLOBAL\" && echo \"Supported\" || echo \"End of life\"; })\"" >&2
SUPPORT_STATUS="$([ "$VERSION_MINOR" == "$VERSION_LATEST_GLOBAL_MAJOR" ] && echo "Latest" \
    || { grep -q -Fx "$VERSION_MINOR" <<< "$BRANCHES_GLOBAL" && echo "Supported" || echo "End of life"; })"

echo "Milestone: $MILESTONE"
echo "Version: $VERSION"
echo "Status: $SUPPORT_STATUS"
echo

echo "Versions according to ./vendor/versions.json"
echo "- Supported branches: ${BRANCHES_LOCAL//$'\n'/ }"
echo "- Latest version of v$VERSION_MAJOR branch: $VERSION_LATEST_LOCAL_MAJOR"
echo "- Latest version of v$VERSION_MINOR branch: $VERSION_LATEST_LOCAL_MINOR"
echo "- Latest version: $VERSION_LATEST_LOCAL"
echo

echo "Versions according to php.net"
echo "- Supported branches: ${BRANCHES_GLOBAL//$'\n'/ }"
echo "- Latest version of v$VERSION_MAJOR branch: $VERSION_LATEST_GLOBAL_MAJOR"
echo "- Latest version of v$VERSION_MINOR branch: $VERSION_LATEST_GLOBAL_MINOR"
echo "- Latest version: $VERSION_LATEST_GLOBAL"
