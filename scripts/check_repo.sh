#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$KIT_ROOT"

status=0

while IFS= read -r -d '' script; do
    bash -n "$script" || status=1
done < <(find scripts -type f -name '*.sh' -print0)

if command -v shellcheck >/dev/null 2>&1; then
    mapfile -d '' shell_scripts < <(find scripts -type f -name '*.sh' -print0)
    shellcheck -x "${shell_scripts[@]}" || status=1
else
    echo 'NOTE: shellcheck is not installed; bash syntax checks still ran.'
fi

large_files="$(find . -path './.git' -prune -o -type f -size +5M -print)"
if [[ -n "$large_files" ]]; then
    printf 'Files larger than 5 MiB are not allowed:\n%s\n' "$large_files" >&2
    status=1
fi

weight_files="$(find . -path './.git' -prune -o -type f \
    \( -name '*.safetensors' -o -name '*.gguf' -o -name '*.bin' -o -name '*.pt' \
       -o -name '*.pth' -o -name '*.ckpt' -o -name '*.cubin' -o -name '*.so' \) -print)"
if [[ -n "$weight_files" ]]; then
    printf 'Forbidden model/build artifacts found:\n%s\n' "$weight_files" >&2
    status=1
fi

if command -v rg >/dev/null 2>&1; then
    if rg -n --hidden --glob '!.git/**' \
        '(gh[opusr]_[A-Za-z0-9]{20,}|hf_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY-----)' .; then
        echo 'Possible credential detected.' >&2
        status=1
    fi
    if rg -n --hidden --glob '!.git/**' --glob '!scripts/check_repo.sh' \
        '(/home/[^/[:space:]]+|/mnt/qwen38-work)' .; then
        echo 'Machine-specific absolute path detected.' >&2
        status=1
    fi
fi

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git diff --check || status=1
fi

(( status == 0 )) || exit 1
echo 'Repository checks passed.'
