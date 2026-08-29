# GLM-5.3 EXL3 Conversion Kit

Reproducible tooling for converting a full GLM-5.3 DWM BF16 checkpoint to an
EXL3 artifact tuned for constrained-memory inference.

The validated recipe is:

- EXL3 `2.0 bpw` with `--hq` (`2.04 bpw` effective decoder rate)
- `lm_head` at 6 bpw
- MTP layer at 2 bpw
- `mul1` codebook and output-channel scales enabled
- bundled ExLlamaV3 calibration mix, 250 rows by 2048 tokens
- resumable conversion state
- TabbyAPI serving with a single advertised model

The completed artifact contained 26 safetensor shards and occupied
197,648,095,811 bytes (197.65 GB / 184.08 GiB). The conversion ran from
2026-08-28 23:43:54 UTC to 2026-08-29 03:45:09 UTC on eight NVIDIA B200 GPUs.
The operator's subsequent harness test reported no snapback.

This repository contains the recipe and evidence only. It intentionally does
not contain source weights, converted weights, checkpoints, compiled CUDA
extensions, virtual environments, prompts, responses, credentials, or full
machine logs.

## Pinned stack

| Component | Pin |
| --- | --- |
| ExLlamaV3 | `0c49587a7c235e6303a6bbedc8b665272ad3a2ea` (`1.4.4`) |
| TabbyAPI | `fcc1a1078e1f766dad305045c7c4d30aaefa6458` |
| Runtime image | `lmsysorg/sglang@sha256:16aba8925507e631e1dc1e23d95d026533602591775f6a8db68b74ee99746155` |
| PyTorch / CUDA in image | `2.11.0+cu130` / `13.0` |
| flash-linear-attention | `0.5.2` |
| B200 compute target | `sm_100` |

## Quick start

Requirements: Linux, Bash, Git, Docker with NVIDIA Container Toolkit, `jq`,
`curl`, `sha256sum`, and enough local storage. The successful full run used
about 184.08 GiB for the output and 207.44 GiB for retained resumable work
state. Keep at least 900,000,000 KiB free before starting.

```bash
cp .env.example .env
# Edit SOURCE_DIR, WORK_ROOT, GPU_DEVICES, and SOURCE_INDEX_SHA256.

./scripts/setup_toolchain.sh
./scripts/preflight.sh
./scripts/convert.sh
./scripts/validate.sh
```

Interrupted conversions are resumed by rerunning `./scripts/convert.sh`. The
launcher recognizes ExLlamaV3's `args.json` and `ckpt/job.json` state and uses
`convert.py --resume`. It never deletes or moves the BF16 source.

To serve and verify the result:

```bash
./scripts/serve.sh
./scripts/smoke_test.sh
```

The server mounts only the converted model beneath `/models`. This is
intentional: mounting a whole model library makes TabbyAPI's `/v1/models`
endpoint advertise every directory even though only one model is loaded. Some
harnesses then select an unloaded entry and misleadingly report the API as
unreachable.

See [the exact recipe](docs/RECIPE.md), [serving notes](docs/SERVING.md), and
[troubleshooting](docs/TROUBLESHOOTING.md) before adapting the workflow.

## Hardware notes

The conversion recipe was validated with eight 183,359 MiB B200 GPUs. Fewer
GPUs may work but were not tested and will change runtime substantially.

The artifact is smaller than the combined 256 GB unified memory of two DGX
Spark systems, but ExLlamaV3/TabbyAPI does not make two separate Spark hosts a
single multi-node EXL3 runtime. A compatible distributed runtime is still
required; the interconnect alone is not sufficient. The included serving
recipe targets multiple GPUs in one host.

## Repository safety

Run `./scripts/check_repo.sh` before publishing. `.gitignore` blocks common
weight, checkpoint, environment, credential, and runtime files. Review the
source model's license separately before distributing any converted weights.

GitHub publishing commands are in [docs/GITHUB.md](docs/GITHUB.md). They do not
run automatically.
