#!/usr/bin/env bash

set -Eeuo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname -- "$0")/lib.sh"

require_commands git docker nvidia-smi
mkdir -p "$TOOLS_DIR" "$WORK_ROOT" "$RUNTIME_DIR" "$EXTENSION_DIR"

checkout_pinned() {
    local url="$1" destination="$2" commit="$3"
    if [[ ! -e "$destination" ]]; then
        git clone "$url" "$destination"
    fi
    [[ -d "$destination/.git" ]] || {
        printf 'Existing path is not a Git checkout: %s\n' "$destination" >&2
        return 1
    }
    if [[ -n "$(git -C "$destination" status --porcelain)" ]]; then
        printf 'Refusing to modify dirty checkout: %s\n' "$destination" >&2
        return 1
    fi
    if ! git -C "$destination" cat-file -e "$commit^{commit}" 2>/dev/null; then
        git -C "$destination" fetch origin "$commit"
    fi
    git -C "$destination" checkout --detach "$commit"
    [[ "$(git -C "$destination" rev-parse HEAD)" == "$commit" ]]
}

checkout_pinned https://github.com/turboderp-org/exllamav3.git "$EXL3_DIR" "$EXL3_COMMIT"
checkout_pinned https://github.com/theroyallab/tabbyAPI.git "$TABBY_DIR" "$TABBY_COMMIT"

if ! docker image inspect "$CONTAINER_IMAGE" >/dev/null 2>&1; then
    docker pull "$CONTAINER_IMAGE"
fi

docker run --rm \
    --gpus all \
    --ipc host \
    --entrypoint bash \
    -e FLA_VERSION="$FLASH_LINEAR_ATTENTION_VERSION" \
    -v "$WORK_ROOT:/kit-work" \
    -v "$EXL3_DIR:/exllamav3:ro" \
    -v "$TABBY_DIR:/tabbyAPI:ro" \
    "$CONTAINER_IMAGE" \
    -lc '
        set -Eeuo pipefail
        if [[ ! -x /kit-work/venv/bin/python ]]; then
            python3 -m venv --system-site-packages /kit-work/venv
        fi
        source /kit-work/venv/bin/activate
        python -m pip install --upgrade pip
        python -m pip install "flash-linear-attention==${FLA_VERSION}"
        python -m pip install --no-deps /exllamav3

        mkdir -p /kit-work/runtime
        if [[ ! -x /kit-work/runtime/venv/bin/python ]]; then
            python3 -m venv --system-site-packages /kit-work/runtime/venv
        fi
        source /kit-work/runtime/venv/bin/activate
        python -m pip install --upgrade pip
        cp -a /tabbyAPI /tmp/tabbyAPI
        python -m pip install /tmp/tabbyAPI

        PYTHONPATH=/exllamav3:/kit-work/venv/lib/python3.12/site-packages \
            python - <<"PY"
from importlib.metadata import version
assert version("exllamav3") == "1.4.4", version("exllamav3")
print("exllamav3", version("exllamav3"))
print("flash-linear-attention", version("flash-linear-attention"))
print("tabbyAPI", version("tabbyAPI"))
PY
    '

assert_toolchain
printf 'Pinned toolchain ready under %s\n' "$WORK_ROOT"
