#!/usr/bin/env bash

set -Eeuo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname -- "$0")/lib.sh"

require_commands docker git nvidia-smi curl jq sed ss
assert_toolchain
[[ -x "$TABBY_VENV/bin/python" ]]
[[ -s "$OUTPUT_DIR/config.json" ]]
[[ -s "$OUTPUT_DIR/model.safetensors.index.json" ]]
compgen -G "$OUTPUT_DIR/*.safetensors" >/dev/null
assert_gpus_idle "$SERVE_GPUS"

if docker ps -a --format '{{.Names}}' | grep -Fxq "$SERVER_CONTAINER"; then
    printf 'Container already exists: %s\nPreserve, rename, or remove it explicitly before relaunching.\n' \
        "$SERVER_CONTAINER" >&2
    exit 1
fi
if ss -H -ltn "sport = :$BIND_PORT" | grep -q .; then
    printf 'Port %s is already in use.\n' "$BIND_PORT" >&2
    exit 1
fi

mkdir -p "$RUNTIME_DIR" "$EXTENSION_DIR"
config_file="$RUNTIME_DIR/config.yml"
sed \
    -e "s/__BIND_HOST__/$BIND_HOST/g" \
    -e "s/__BIND_PORT__/$BIND_PORT/g" \
    -e "s/__DISABLE_AUTH__/$DISABLE_AUTH/g" \
    -e "s/__MODEL_NAME__/$OUTPUT_NAME/g" \
    "$KIT_ROOT/configs/tabbyapi.yml.in" > "$config_file"

conversion_site="$(conversion_site_packages)"

docker run -d \
    --name "$SERVER_CONTAINER" \
    --network host \
    --gpus all \
    --ipc host \
    --entrypoint /runtime/venv/bin/python \
    -e CUDA_VISIBLE_DEVICES="$SERVE_GPUS" \
    -e HF_HUB_OFFLINE=1 \
    -e TRANSFORMERS_OFFLINE=1 \
    -e TORCH_CUDA_ARCH_LIST=10.0 \
    -e TORCH_EXTENSIONS_DIR=/root/.cache/torch_extensions \
    -e PYTHONPATH=/app/tabbyAPI:/app/exllamav3:/conversion-site \
    -v "$RUNTIME_DIR:/runtime" \
    -v "$TABBY_DIR:/app/tabbyAPI:ro" \
    -v "$EXL3_DIR:/app/exllamav3:ro" \
    -v "$conversion_site:/conversion-site:ro" \
    -v "$OUTPUT_DIR:/models/$OUTPUT_NAME:ro" \
    -v "$EXTENSION_DIR:/root/.cache/torch_extensions" \
    -w /runtime \
    "$CONTAINER_IMAGE" \
    /app/tabbyAPI/start.py --config /runtime/config.yml >/dev/null

probe_host="$(health_host)"
for _ in $(seq 1 90); do
    if ! docker ps --format '{{.Names}}' | grep -Fxq "$SERVER_CONTAINER"; then
        docker logs --tail 200 "$SERVER_CONTAINER" >&2 || true
        exit 1
    fi
    if curl -fsS --connect-timeout 2 --max-time 3 \
        "http://$probe_host:$BIND_PORT/health" | jq -e '.status == "healthy"' >/dev/null 2>&1; then
        printf 'Server healthy: http://%s:%s/v1\nModel: %s\n' \
            "$BIND_HOST" "$BIND_PORT" "$OUTPUT_NAME"
        exit 0
    fi
    sleep 2
done

docker logs --tail 200 "$SERVER_CONTAINER" >&2 || true
exit 1
