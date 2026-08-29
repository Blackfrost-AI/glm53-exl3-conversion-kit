#!/usr/bin/env bash

set -Eeuo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname -- "$0")/lib.sh"

require_commands docker
if docker ps --format '{{.Names}}' | grep -Fxq "$SERVER_CONTAINER"; then
    docker stop --timeout 30 "$SERVER_CONTAINER"
    printf 'Stopped %s. The container and logs were preserved.\n' "$SERVER_CONTAINER"
elif docker ps -a --format '{{.Names}}' | grep -Fxq "$SERVER_CONTAINER"; then
    printf 'Container is already stopped and preserved: %s\n' "$SERVER_CONTAINER"
else
    printf 'No container named %s exists.\n' "$SERVER_CONTAINER"
fi
