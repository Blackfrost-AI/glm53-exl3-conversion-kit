# Evidence bundle

This directory contains compact, non-weight evidence from the successful run.

- `provenance.json`: source identity, toolchain pins, recipe, output metadata,
  and result status.
- `output-sha256.txt`: SHA-256 for every known-good output weight shard. Run
  `sha256sum -c` from inside the converted model directory.
- `conversion-summary.txt`: key converter output without the full machine log.

The output hash manifest itself has SHA-256
`c8da9e18e669db54ef3aae8e15d3dab0633e15e11cf6e50fee39c21dac4ceecc`
in the original machine-path form. This repository stores the same hashes with
paths reduced to basenames for portability.
