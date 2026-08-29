#!/usr/bin/env bash

set -Eeuo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname -- "$0")/lib.sh"

require_commands jq sha256sum find sort xargs du
assert_source

[[ -s "$OUTPUT_DIR/config.json" ]]
[[ -s "$OUTPUT_DIR/model.safetensors.index.json" ]]
[[ -s "$OUTPUT_DIR/quantization_config.json" ]]

jq -e '
    .architectures == ["GlmMoeDsaForCausalLM"] and
    .quantization_config.quant_method == "exl3" and
    .quantization_config.version == "1.4.4" and
    (.quantization_config.bits >= 2.0 and .quantization_config.bits <= 2.1) and
    .quantization_config.head_bits == 6 and
    .quantization_config.mtp_bits == 2 and
    .quantization_config.calibration.rows == 250 and
    .quantization_config.calibration.cols == 2048 and
    .quantization_config.codebook == "mul1"
' "$OUTPUT_DIR/config.json" >/dev/null

jq -e '
    .quant_method == "exl3" and
    .version == "1.4.4" and
    (.tensor_storage | type == "object" and length > 0)
' "$OUTPUT_DIR/quantization_config.json" >/dev/null

mapfile -t shards < <(jq -r '.weight_map[]' "$OUTPUT_DIR/model.safetensors.index.json" | sort -u)
[[ "${#shards[@]}" -eq "$EXPECTED_OUTPUT_SHARDS" ]] || {
    printf 'Expected %s output shards; index lists %s.\n' \
        "$EXPECTED_OUTPUT_SHARDS" "${#shards[@]}" >&2
    exit 1
}
for shard in "${shards[@]}"; do
    [[ "$shard" != */* ]]
    [[ -s "$OUTPUT_DIR/$shard" ]]
done

mkdir -p "$EVIDENCE_DIR"
hash_file="$EVIDENCE_DIR/output-sha256.txt"
(
    cd "$OUTPUT_DIR"
    find . -maxdepth 1 -type f -name '*.safetensors' -printf '%f\0' \
        | sort -z | xargs -0 sha256sum
) > "$hash_file.tmp"
mv "$hash_file.tmp" "$hash_file"
(cd "$OUTPUT_DIR" && sha256sum -c "$hash_file")

if [[ "$STRICT_REFERENCE_HASHES" == "true" ]]; then
    (cd "$OUTPUT_DIR" && sha256sum -c "$KIT_ROOT/evidence/output-sha256.txt")
fi

output_bytes="$(du -sb "$OUTPUT_DIR" | awk '{print $1}')"
printf 'Validated %s shards; output size: %s bytes\nHashes: %s\n' \
    "${#shards[@]}" "$output_bytes" "$hash_file"
