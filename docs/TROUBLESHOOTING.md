# Troubleshooting

## Harness reports “unreachable,” but `/v1/models` returns data

Inspect the server log and response:

```bash
docker logs --tail 100 "$SERVER_CONTAINER"
curl -fsS "http://$BIND_HOST:$BIND_PORT/v1/models" | jq .
```

If several IDs appear, the model directory mount is too broad. Use the
included `serve.sh`, which exposes exactly one directory. A harness may label a
wrong-model or ambiguous-discovery error as a connectivity failure.

## Localhost fails while a private address works

TabbyAPI listens only on the configured `BIND_HOST`. Binding to a WireGuard
address does not also bind `127.0.0.1` or a LAN address. Use the same address in
the harness, or choose a different bind address and restart.

## Extension rebuild on first run

The first process on a new GPU architecture compiles the ExLlamaV3 CUDA
extension. Keep `TORCH_EXTENSIONS_DIR` on persistent fast storage. The B200 run
used `TORCH_CUDA_ARCH_LIST=10.0` (`sm_100`). An initial startup can therefore
take longer than later launches.

## Resume is rejected

Resume requires both `state/args.json` and `state/ckpt/job.json`. Do not edit
`args.json`. Confirm the same pinned ExLlamaV3 commit and rerun `convert.sh`.
If the state is incomplete, preserve it for investigation rather than deleting
it or starting over in the same directory.

## Disk gate fails

The source is about 1.51 TB, output about 197.65 GB, and retained conversion
state about 222.71 GB. The script requires at least 900,000,000 KiB free at
launch to allow for checkpoints, temporary files, and output.

## GPU-process gate fails

Conversion intentionally refuses to stop other GPU workloads. Stop the serving
container or other jobs yourself, then rerun. This prevents the conversion kit
from killing unrelated work.

## Two DGX Spark systems

The artifact's 184.08 GiB size is below two Sparks' combined unified memory,
but the included ExLlamaV3 server is a single-host runtime. Two physical Spark
hosts require a runtime with compatible EXL3 multi-node execution; changing
only `SERVE_GPUS` cannot span hosts.
