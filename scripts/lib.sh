#!/usr/bin/env bash
# shellcheck disable=SC2034

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$KIT_ROOT/.env}"

if [[ ! -r "$CONFIG_FILE" ]]; then
    printf 'Missing configuration: %s\nCopy .env.example to .env and edit it.\n' "$CONFIG_FILE" >&2
    exit 2
fi

set -a
# shellcheck disable=SC1090
source "$CONFIG_FILE"
set +a

: "${SOURCE_DIR:?Set SOURCE_DIR in .env}"
: "${WORK_ROOT:?Set WORK_ROOT in .env}"

OUTPUT_NAME="${OUTPUT_NAME:-GLM-5.3-DERISKED-EXL3-2.0bpw-HQ}"
GPU_DEVICES="${GPU_DEVICES:-0,1,2,3,4,5,6,7}"
SERVE_GPUS="${SERVE_GPUS:-0,1}"
EXPECTED_SOURCE_SHARDS="${EXPECTED_SOURCE_SHARDS:-161}"
EXPECTED_OUTPUT_SHARDS="${EXPECTED_OUTPUT_SHARDS:-26}"
SOURCE_INDEX_SHA256="${SOURCE_INDEX_SHA256:-}"
STRICT_REFERENCE_HASHES="${STRICT_REFERENCE_HASHES:-true}"
BIND_HOST="${BIND_HOST:-127.0.0.1}"
BIND_PORT="${BIND_PORT:-8000}"
DISABLE_AUTH="${DISABLE_AUTH:-true}"
SERVER_CONTAINER="${SERVER_CONTAINER:-glm53-exl3-2bpw-hq-tabby}"

EXL3_COMMIT="${EXL3_COMMIT:-0c49587a7c235e6303a6bbedc8b665272ad3a2ea}"
TABBY_COMMIT="${TABBY_COMMIT:-fcc1a1078e1f766dad305045c7c4d30aaefa6458}"
FLASH_LINEAR_ATTENTION_VERSION="${FLASH_LINEAR_ATTENTION_VERSION:-0.5.2}"
CONTAINER_IMAGE="${CONTAINER_IMAGE:-lmsysorg/sglang@sha256:16aba8925507e631e1dc1e23d95d026533602591775f6a8db68b74ee99746155}"

TOOLS_DIR="$WORK_ROOT/tools"
EXL3_DIR="$TOOLS_DIR/exllamav3"
TABBY_DIR="$TOOLS_DIR/tabbyAPI"
CONVERSION_VENV="$WORK_ROOT/venv"
RUNTIME_DIR="$WORK_ROOT/runtime"
TABBY_VENV="$RUNTIME_DIR/venv"
EXTENSION_DIR="$WORK_ROOT/torch_extensions"
PREFLIGHT_DIR="$WORK_ROOT/preflight-state"
PREFLIGHT_OUTPUT_DIR="$WORK_ROOT/preflight-output"
STATE_DIR="$WORK_ROOT/state"
OUTPUT_PARENT="$WORK_ROOT/output"
OUTPUT_DIR="$OUTPUT_PARENT/$OUTPUT_NAME"
LOG_DIR="$WORK_ROOT/logs"
EVIDENCE_DIR="$WORK_ROOT/evidence"

[[ "$WORK_ROOT" != "/" ]] || { echo 'WORK_ROOT must not be /' >&2; exit 2; }
[[ "$SOURCE_DIR" != "/" ]] || { echo 'SOURCE_DIR must not be /' >&2; exit 2; }
[[ "$OUTPUT_NAME" =~ ^[A-Za-z0-9._-]+$ ]] || { echo 'OUTPUT_NAME contains unsafe characters' >&2; exit 2; }
[[ "$BIND_PORT" =~ ^[0-9]+$ ]] || { echo 'BIND_PORT must be numeric' >&2; exit 2; }
[[ "$DISABLE_AUTH" == "true" || "$DISABLE_AUTH" == "false" ]] || {
    echo 'DISABLE_AUTH must be true or false' >&2
    exit 2
}
[[ "$STRICT_REFERENCE_HASHES" == "true" || "$STRICT_REFERENCE_HASHES" == "false" ]] || {
    echo 'STRICT_REFERENCE_HASHES must be true or false' >&2
    exit 2
}

require_commands() {
    local missing=0 command_name
    for command_name in "$@"; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            printf 'Missing required command: %s\n' "$command_name" >&2
            missing=1
        fi
    done
    (( missing == 0 ))
}

assert_source() {
    local actual_shards actual_sha
    [[ -s "$SOURCE_DIR/config.json" ]]
    [[ -s "$SOURCE_DIR/tokenizer.json" ]]
    [[ -s "$SOURCE_DIR/model.safetensors.index.json" ]]
    actual_shards="$(find "$SOURCE_DIR" -maxdepth 1 -type f -name '*.safetensors' -printf '.' | wc -c)"
    [[ "$actual_shards" -eq "$EXPECTED_SOURCE_SHARDS" ]] || {
        printf 'Expected %s source shards; found %s\n' "$EXPECTED_SOURCE_SHARDS" "$actual_shards" >&2
        return 1
    }
    if [[ -n "$SOURCE_INDEX_SHA256" ]]; then
        actual_sha="$(sha256sum "$SOURCE_DIR/model.safetensors.index.json" | awk '{print $1}')"
        [[ "$actual_sha" == "$SOURCE_INDEX_SHA256" ]] || {
            printf 'Source index hash mismatch\nexpected: %s\nactual:   %s\n' \
                "$SOURCE_INDEX_SHA256" "$actual_sha" >&2
            return 1
        }
    fi
}

assert_toolchain() {
    [[ "$(git -C "$EXL3_DIR" rev-parse HEAD)" == "$EXL3_COMMIT" ]]
    [[ "$(git -C "$TABBY_DIR" rev-parse HEAD)" == "$TABBY_COMMIT" ]]
    [[ -x "$CONVERSION_VENV/bin/python" ]]
    docker image inspect "$CONTAINER_IMAGE" >/dev/null
}

assert_gpus_idle() {
    local devices="$1" active
    active="$(nvidia-smi -i "$devices" --query-compute-apps=pid --format=csv,noheader,nounits \
        | sed '/^[[:space:]]*$/d' | sort -u)"
    if [[ -n "$active" ]]; then
        printf 'GPU compute processes are active on %s (PIDs: %s).\n' \
            "$devices" "$(tr '\n' ' ' <<<"$active")" >&2
        return 1
    fi
}

conversion_site_packages() {
    local result
    result="$(find "$CONVERSION_VENV/lib" -mindepth 2 -maxdepth 2 \
        -type d -name site-packages -print -quit)"
    [[ -n "$result" ]]
    printf '%s\n' "$result"
}

health_host() {
    if [[ "$BIND_HOST" == "0.0.0.0" ]]; then
        printf '127.0.0.1\n'
    else
        printf '%s\n' "$BIND_HOST"
    fi
}
