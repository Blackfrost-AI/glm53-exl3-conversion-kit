#!/usr/bin/env bash

set -Eeuo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname -- "$0")/lib.sh"

require_commands curl jq
probe_host="$(health_host)"
base_url="http://$probe_host:$BIND_PORT"

curl -fsS --connect-timeout 5 --max-time 10 "$base_url/health" \
    | jq -e '.status == "healthy"' >/dev/null

models_json="$(curl -fsS --connect-timeout 5 --max-time 10 "$base_url/v1/models")"
model_count="$(jq '.data | length' <<<"$models_json")"
model_id="$(jq -r '.data[0].id' <<<"$models_json")"
[[ "$model_count" -eq 1 ]]
[[ "$model_id" == "$OUTPUT_NAME" ]]

request_json="$(jq -cn --arg model "$OUTPUT_NAME" '{
    model: $model,
    messages: [{role: "user", content: "Reply with exactly: reachable"}],
    temperature: 0,
    max_tokens: 32,
    reasoning_effort: "low",
    stream: false
}')"

response="$(curl -fsS --connect-timeout 5 --max-time 120 \
    "$base_url/v1/chat/completions" \
    -H 'Content-Type: application/json' \
    --data-binary "$request_json")"

jq -e '(.choices[0].message.content // .choices[0].message.reasoning_content // "") | length > 0' \
    <<<"$response" >/dev/null
jq '{model, finish_reason: .choices[0].finish_reason, content: .choices[0].message.content}' \
    <<<"$response"
printf 'Smoke test passed with exactly one advertised model.\n'
