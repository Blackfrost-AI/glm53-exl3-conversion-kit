# Exact conversion recipe

## Input gate

The successful input was a full BF16 `GlmMoeDsaForCausalLM` checkpoint with:

- 753,329,940,480 parameters, including MTP
- 78 decoder layers plus one MTP layer
- 161 safetensor shards totaling 1,506,667,419,168 bytes
- `model.safetensors.index.json` SHA-256:
  `ea558ab1584b518fec4bbc928cfe66018d8c38b0a94c9b8ae336e7fc82b79479`

Set `SOURCE_INDEX_SHA256` to the checksum of the source you intend to convert.
The launcher refuses to proceed if the value does not match. Leaving the value
blank deliberately disables that identity check, but is not recommended for a
reproduction claim.

## Strategy-only preflight

`scripts/preflight.sh` invokes ExLlamaV3 with `--max_module -1`. This loads the
model configuration and tokenizer, builds calibration input, computes the
quantization allocation, prints the effective bitrate, and stops before full
quantization.

The expected allocation summary includes:

- most routed-expert tensors: 2 bpw
- selected dense MLP tensors: 3 bpw
- selected attention/shared-expert tensors: 4 bpw
- `lm_head`: 6 bpw
- effective decoder bitrate: 2.04 bpw with HQ enabled

Do not start the multi-hour run if the architecture, MTP discovery, or final
bitrate differs.

## Production invocation

The new-job arguments resolve to:

```text
convert.py \
  --in_dir /source \
  --out_dir /kit-work/output/GLM-5.3-DERISKED-EXL3-2.0bpw-HQ \
  --work_dir /kit-work/state \
  --bits 2.0 \
  --hq \
  --head_bits 6 \
  --mtp_bits 2 \
  --cal_rows 250 \
  --cal_cols 2048 \
  --codebook mul1 \
  --out_scales always \
  --devices 0,1,2,3,4,5,6,7
```

An interrupted job is resumed only with:

```text
convert.py --work_dir /kit-work/state --resume
```

ExLlamaV3 loads the original arguments from the work state. Do not change
bitrate or architecture settings during resume.

## Original run result

- Start: `2026-08-28T23:43:54Z`
- Finish: `2026-08-29T03:45:09Z`
- Wall time: 4 hours, 1 minute, 15 seconds
- Output: 26 shards, 197,648,095,811 bytes
- Retained work state: 222,708,121,206 bytes
- `bad_rows`: empty
- Last completed module index: 79
- Full conversion log SHA-256:
  `961161ade5aca6471af40066aeb3820e2014d365e5a5596358fc400c6c3095dc`

The full 7.7 MB log is intentionally excluded because it is machine-specific.
The key provenance and per-shard hashes are retained under `evidence/`.
