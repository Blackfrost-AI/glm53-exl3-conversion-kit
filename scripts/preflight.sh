#!/usr/bin/env bash

set -Eeuo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname -- "$0")/lib.sh"

require_commands docker git jq nvidia-smi sha256sum tee
assert_source
assert_toolchain
assert_gpus_idle "$GPU_DEVICES"

mkdir -p "$LOG_DIR" "$PREFLIGHT_DIR" "$PREFLIGHT_OUTPUT_DIR" "$EXTENSION_DIR"
if [[ -e "$PREFLIGHT_DIR/args.json" ]]; then
    printf 'Preserving existing preflight state at %s; use a fresh WORK_ROOT to rerun it.\n' \
        "$PREFLIGHT_DIR" >&2
    exit 1
fi

log_file="$LOG_DIR/preflight-2.0bpw-hq.log"

docker run --rm \
    --name glm53-exl3-2bpw-hq-preflight \
    --gpus all \
    --ipc host \
    --shm-size=64g \
    --cap-add IPC_LOCK \
    --ulimit memlock=-1:-1 \
    --entrypoint bash \
    -e TORCH_CUDA_ARCH_LIST=10.0 \
    -e TORCH_EXTENSIONS_DIR=/kit-work/torch_extensions \
    -e MAX_JOBS=8 \
    -e HF_HUB_OFFLINE=1 \
    -e TRANSFORMERS_OFFLINE=1 \
    -v "$EXL3_DIR:/exllamav3:ro" \
    -v "$WORK_ROOT:/kit-work" \
    -v "$SOURCE_DIR:/source:ro" \
    "$CONTAINER_IMAGE" \
    -lc 'cd /exllamav3 && exec /kit-work/venv/bin/python convert.py "$@"' \
    convert \
        -i /source \
        -o /kit-work/preflight-output \
        -w /kit-work/preflight-state \
        -b 2.0 \
        -hq \
        -hb 6 \
        -mb 2 \
        -cr 250 \
        -cc 2048 \
        -cb mul1 \
        --out_scales always \
        -d "$GPU_DEVICES" \
        --max_module -1 2>&1 | tee "$log_file"

grep -Fq 'Final bitrate (excluding head): 2.04 (--hq enabled)' "$log_file"
grep -Fq 'Created MTP model instance' "$log_file"
printf 'Preflight passed: 2.04 bpw HQ, 6-bit head, MTP discovered.\n'
