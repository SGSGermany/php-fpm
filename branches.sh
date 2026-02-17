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

BUILD_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

VERSION_URL="https://www.php.net/releases/index.php?json"
EXIT_CODE=0

echo + "BRANCHES_LOCAL=\"\$(find ./branches/ -mindepth 1 -maxdepth 1 -type d -printf '%f\n')\"" >&2
BRANCHES_LOCAL="$(find "$BUILD_DIR/branches/" -mindepth 1 -maxdepth 1 -type d -printf '%f\n')"

echo + "BRANCHES_GLOBAL_JSON=\"\$(_curl_json $(quote "$VERSION_URL"))\"" >&2
BRANCHES_GLOBAL_JSON="$(_curl_json "$VERSION_URL")"

echo + "BRANCHES_GLOBAL=\"\$(jq -re '.[].supported_versions[]' <<< \"\$BRANCHES_GLOBAL_JSON\")\"" >&2
BRANCHES_GLOBAL="$(jq -re '.[].supported_versions[]' <<< "$BRANCHES_GLOBAL_JSON")"

echo + "BRANCHES_MISSING=\"\$(comm -13 <(sort <<< \"\$BRANCHES_LOCAL\") <(sort <<< \"\$BRANCHES_GLOBAL\"))\"" >&2
BRANCHES_MISSING="$(comm -13 <(sort <<< "$BRANCHES_LOCAL") <(sort <<< "$BRANCHES_GLOBAL"))"

if [ -n "$BRANCHES_MISSING" ]; then
    echo "Explicit build instructions for the following PHP branches are missing" >&2
    sed -e 's/^/- /' <<< "$BRANCHES_MISSING" >&2
    EXIT_CODE=1
fi

echo + "sort_semver <<< \"\$BRANCHES_LOCAL\"" >&2
[ -z "$BRANCHES_LOCAL" ] || sort_semver <<< "$BRANCHES_LOCAL"

exit $EXIT_CODE
