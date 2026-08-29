# Serving with TabbyAPI

`scripts/serve.sh` runs the pinned TabbyAPI and ExLlamaV3 revisions in the same
pinned container family used for conversion. It renders
`configs/tabbyapi.yml.in` into the external work directory and starts an
OpenAI-compatible API.

## Endpoint

The base URL is:

```text
http://BIND_HOST:BIND_PORT/v1
```

The model ID is the value of `OUTPUT_NAME` in `.env`.

The default bind address is `127.0.0.1`. For a remote harness, bind to a
specific private LAN or WireGuard address. Avoid `0.0.0.0` while
`DISABLE_AUTH=true` unless the host firewall strictly limits access.

## One-model catalog

The Docker launch mounts only:

```text
OUTPUT_DIR -> /models/OUTPUT_NAME
```

Do not replace it with a mount of the whole local model library. TabbyAPI lists
all directories visible under `model_dir` for an admin/unauthenticated request,
even when inline loading is disabled. Some clients treat the resulting list as
multiple live models and choose the wrong ID.

`scripts/smoke_test.sh` enforces exactly one advertised model before sending a
chat completion.

## MTP

The artifact includes a 2-bit MTP layer, but the initial no-snapback evaluation
used `draft_mode: disabled`. This keeps speculative decoding from confounding
an output-behavior comparison. Enable drafting only as a separate experiment.

## Memory profile from the successful smoke test

The tested server used local GPUs 0 and 1 with automatic layer splitting and a
32,768-token FP16 cache. After a short generation, GPU 0 used approximately
180.9 GiB and GPU 1 used approximately 9.9 GiB. This split was highly
imbalanced but completed successfully. If a longer workload runs out of
memory, increase `autosplit_reserve` or use a tested explicit split.

Stop the container without deleting it by running:

```bash
./scripts/stop_server.sh
```
