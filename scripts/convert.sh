#!/usr/bin/env bash

set -Eeuo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname -- "$0")/lib.sh"

require_commands docker git jq nvidia-smi sha256sum tee df
assert_source
assert_toolchain
assert_gpus_idle "$GPU_DEVICES"

mkdir -p "$STATE_DIR" "$OUTPUT_PARENT" "$LOG_DIR" "$EXTENSION_DIR"

if [[ -s "$OUTPUT_DIR/config.json" && -s "$OUTPUT_DIR/model.safetensors.index.json" ]]; then
    printf 'Output already appears complete: %s\nRun scripts/validate.sh.\n' "$OUTPUT_DIR"
    exit 0
fi

available_kib="$(df -Pk "$WORK_ROOT" | awk 'NR == 2 {print $4}')"
if (( available_kib < 900000000 )); then
    printf 'At least 900,000,000 KiB free is required; found %s KiB.\n' "$available_kib" >&2
    exit 1
fi

if [[ -f "$STATE_DIR/args.json" && -f "$STATE_DIR/ckpt/job.json" ]]; then
    conversion_args=(-w /kit-work/state -r)
    mode=resume
elif [[ -n "$(find "$STATE_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    printf 'State directory is nonempty but not resumable: %s\n' "$STATE_DIR" >&2
    exit 1
else
    conversion_args=(
        -i /source
        -o "/kit-work/output/$OUTPUT_NAME"
        -w /kit-work/state
        -b 2.0
        -hq
        -hb 6
        -mb 2
        -cr 250
        -cc 2048
        -cb mul1
        --out_scales always
        -d "$GPU_DEVICES"
    )
    mode=new
fi

log_file="$LOG_DIR/convert-2.0bpw-hq.log"
printf 'EXL3_CONVERSION_BEGIN %s mode=%s commit=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$mode" "$EXL3_COMMIT" | tee -a "$log_file"

docker run --rm \
    --name glm53-exl3-2bpw-hq-convert \
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
    convert "${conversion_args[@]}" 2>&1 | tee -a "$log_file"

[[ -s "$OUTPUT_DIR/config.json" ]]
[[ -s "$OUTPUT_DIR/model.safetensors.index.json" ]]
printf 'EXL3_CONVERSION_COMPLETE %s output=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$OUTPUT_DIR" | tee -a "$log_file"
