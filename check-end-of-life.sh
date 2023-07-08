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

# request PHP version info from php.net
VERSION_URL="https://www.php.net/releases/index.php?json&version=$MILESTONE"

echo + "VERSION_JSON=\"\$(curl -sSL -o - $(quote "$VERSION_URL"))\"" >&2
VERSION_JSON="$(curl -sSL -o - "$VERSION_URL")"

if [ -z "$VERSION_JSON" ]; then
    echo "Unable to determine PHP support status: HTTP request '$VERSION_URL' failed" >&2
    return 1
elif ! jq -e '.' > /dev/null 2>&1 <<< "$VERSION_JSON"; then
    echo "Unable to determine PHP support status: HTTP request '$VERSION_URL' returned a malformed response: $(head -n1 <<< "$VERSION_JSON")" >&2
    return 1
fi

# print PHP support status
EXIT_CODE=0

echo + "SUPPORT_STATUS=\"\$(jq -r --arg BRANCH $(quote "$MILESTONE") 'any(.supported_versions[] == \$BRANCH; .)' <<< \"\$VERSION_JSON\")"\" >&2
SUPPORT_STATUS="$(jq -r --arg BRANCH "$MILESTONE" 'any(.supported_versions[] == $BRANCH; .)' <<< "$VERSION_JSON")"

echo + "[ $(quote "$SUPPORT_STATUS") == true ]" >&2
if [ "$SUPPORT_STATUS" == "true" ]; then
    echo "PHP $MILESTONE is still supported"
else
    echo + "[ $(quote "$SUPPORT_STATUS") == false ]" >&2
    if [ "$SUPPORT_STATUS" != "false" ]; then
        echo "Unable to determine PHP support status: Invalid API response" >&2
        exit 1
    fi

    echo "PHP $MILESTONE has reached its end of life"
    EXIT_CODE=1
fi

LATEST_VERSION="$(jq -r '.version // empty' <<< "$VERSION_JSON")"
LATEST_VERSION_DATE="$(jq -r '.date // empty' <<< "$VERSION_JSON")"
[ -z "$LATEST_VERSION" ] || [ -z "$LATEST_VERSION_DATE" ] \
    || echo "The latest version $LATEST_VERSION was released on $(date --date="$LATEST_VERSION_DATE" +%Y-%m-%d)"

if [ $EXIT_CODE -ne 0 ] && [ "$VERSION_ENDOFLIFE" == "yes" ]; then
    echo "Ignoring error, branch is expected to be end-of-life"
    exit 0
fi

exit $EXIT_CODE
