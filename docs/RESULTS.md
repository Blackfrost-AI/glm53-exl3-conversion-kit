# Observed result

The 2.04 bpw EXL3 artifact passed structural validation, all 26 shard SHA-256
checks, model loading, model discovery, and an OpenAI-compatible chat smoke
test.

The operator then tested it with the intended snapback harness and reported:

> Great conversion — no snapback.

This is recorded as an operator-reported behavioral result, not as a benchmark
claim. The private harness prompts and outputs are not included in this kit.
Reproductions should preserve their own harness version, decoding parameters,
prompts, raw responses, and comparison baseline.

The initial behavior test deliberately disabled MTP drafting. The converted MTP
component remained present in the artifact.
