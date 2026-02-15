#!/usr/bin/env bash
set -euo pipefail

# Portainer Stack API Probe
# - Reads API key from env (PORTAINER_API_KEY) or 1Password ref (OP_PORTAINER_API_KEY_REF)
# - Fetches /api/status and /api/swagger.json (if available)
# - Prints stack-related endpoints + example curl commands for create/update
#
# Required:
#   PORTAINER_URL            e.g. https://portainer.example.com
#   STACK_NAME               e.g. my-app
# Optional:
#   ENDPOINT_ID              default: 2
#   STACK_FILE               default: docker-compose.yml
#   STACK_ID                 existing stack id to probe update/delete routes
#   PORTAINER_API_KEY        Portainer access token (preferred if already available)
#   OP_PORTAINER_API_KEY_REF 1Password secret reference, e.g. op://Dev/Portainer/api-key
#
# Notes:
# - This script is intentionally conservative: it does NOT create/update a stack.
#   It prints commands you can run manually once you confirm the endpoint syntax.
# - If swagger is not exposed (common), set PROBE_CREATE_ROUTES=1 to have the script
#   probe common create endpoints with an intentionally invalid stack file content.
#   A 400 response usually means the route exists; a 404 means it doesn't.

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 2
  }
}

normalize_portainer_url() {
  local raw="$1"
  local base
  base="${raw%%\?*}"
  base="${base%/}"
  base="${base%%/api/*}"
  base="${base%%/api}"
  printf '%s' "$base"
}

http_json() {
  local method="$1"
  local url="$2"
  local data="${3-}"

  local curl_args=(-sS -w "\n%{http_code}" -X "$method" -H "X-API-Key: ${PORTAINER_API_KEY}")
  if [[ -n "${data}" ]]; then
    curl_args+=(-H "Content-Type: application/json" -d "$data")
  fi

  local response body code
  response=$(curl "${curl_args[@]}" "$url" || true)
  body="${response%$'\n'*}"
  code="${response##*$'\n'}"

  printf '%s\n%s' "$code" "$body"
}

print_probe_result() {
  local label="$1"
  local method="$2"
  local url="$3"
  local payload="${4-}"

  local resp code body
  resp="$(http_json "$method" "$url" "${payload}")"
  code="${resp%%$'\n'*}"
  body="${resp#*$'\n'}"

  echo
  echo "-- ${label}"
  echo "${method} ${url}"
  echo "HTTP ${code}"
  if [[ -n "${body}" ]]; then
    echo "${body}" | jq -C . 2>/dev/null || echo "${body}"
  fi
}

: "${PORTAINER_URL:?Set PORTAINER_URL}" 
: "${STACK_NAME:?Set STACK_NAME}" 
ENDPOINT_ID="${ENDPOINT_ID:-2}"
STACK_FILE="${STACK_FILE:-docker-compose.yml}"
STACK_ID="${STACK_ID:-}"

require_cmd curl
require_cmd jq

if [[ -z "${PORTAINER_API_KEY:-}" ]]; then
  if [[ -z "${OP_PORTAINER_API_KEY_REF:-}" ]]; then
    echo "Set PORTAINER_API_KEY or OP_PORTAINER_API_KEY_REF (1Password secret reference)." >&2
    exit 2
  fi
  require_cmd op
  PORTAINER_API_KEY="$(op read "${OP_PORTAINER_API_KEY_REF}")"
fi

BASE_URL="$(normalize_portainer_url "${PORTAINER_URL}")"

echo "Portainer base URL: ${BASE_URL}"
echo "Endpoint ID: ${ENDPOINT_ID}"
echo "Stack name: ${STACK_NAME}"
echo "Stack file: ${STACK_FILE}"
if [[ -n "${STACK_ID}" ]]; then
  echo "Stack id (probe): ${STACK_ID}"
fi

echo

echo "== /api/status =="
status_resp="$(http_json GET "${BASE_URL}/api/status")"
status_code="${status_resp%%$'\n'*}"
status_body="${status_resp#*$'\n'}"
echo "HTTP ${status_code}"
if [[ -n "${status_body}" ]]; then
  echo "${status_body}" | jq -C . || echo "${status_body}"
fi

echo

echo "== Swagger (best-effort) =="
swagger_body=""
for p in "/api/swagger.json" "/api/swagger.yaml" "/api/swagger.yml"; do
  resp="$(http_json GET "${BASE_URL}${p}")"
  code="${resp%%$'\n'*}"
  body="${resp#*$'\n'}"
  if [[ "${code}" == "200" && -n "${body}" ]]; then
    if [[ "${p}" == *.json ]]; then
      swagger_body="${body}"
      echo "Found: ${p}"
      break
    else
      echo "Found: ${p} (YAML) — this probe only parses JSON."
      echo "You can inspect it manually: curl -H \"X-API-Key: ...\" ${BASE_URL}${p}"
      break
    fi
  fi
  echo "Tried ${p}: HTTP ${code}"
done

if [[ -n "${swagger_body}" ]]; then
  echo
  echo "== Stack-related endpoints (from swagger) =="
  echo "${swagger_body}" | jq -r '
    .paths
    | to_entries
    | map(select(.key | test("(^|/)stacks($|/|\\?)")))
    | .[]
    | .key as $path
    | ("\n" + $path),
      ("  methods: " + ((.value | keys) | join(", ")))
  '

  echo
  echo "== Hints: likely create/update routes =="
  echo "${swagger_body}" | jq -r '
    .paths | keys[]
    | select(test("stacks"))
    | select(test("create|update|standalone|compose|swarm|git"; "i"))
  ' | sed 's/^/  - /'

  echo
  echo "If Portainer exposes request schemas here, search for stack payload models:" 
  echo "  jq '.components.schemas | keys[] | select(test("stack|compose|swarm"; "i"))'"
fi

echo

echo "== Existing stacks (for this endpoint) =="
stacks_resp="$(http_json GET "${BASE_URL}/api/stacks")"
stacks_code="${stacks_resp%%$'\n'*}"
stacks_body="${stacks_resp#*$'\n'}"
echo "HTTP ${stacks_code}"
if [[ "${stacks_code}" == "200" ]]; then
  stack_id="$(echo "${stacks_body}" | jq -r --arg name "${STACK_NAME}" --argjson endpoint "${ENDPOINT_ID}" '
    .[]
    | select(.Name == $name and ((.EndpointId // .EndpointID) == $endpoint))
    | (.Id // .ID // empty)
  ' | head -n 1)"
  if [[ -n "${stack_id}" ]]; then
    echo "Found stack: id=${stack_id}"
  else
    echo "No matching stack found for name='${STACK_NAME}' and endpointId=${ENDPOINT_ID}"
  fi
else
  echo "${stacks_body}" | jq -C . || echo "${stacks_body}"
fi

echo

echo "== Manual curl commands to try =="
cat <<EOF
# 0) Common headers
export PORTAINER_URL='${BASE_URL}'
export PORTAINER_ENDPOINT_ID='${ENDPOINT_ID}'
export STACK_NAME='${STACK_NAME}'
export STACK_FILE='${STACK_FILE}'

# 1) List stacks
curl -sS -H "X-API-Key: \$PORTAINER_API_KEY" "\$PORTAINER_URL/api/stacks" | jq .

# 2) Create stack payload
#    Payload keys (commonly accepted): Name, StackFileContent, Env
payload_old_create=\$(jq -n \
  --arg name "\$STACK_NAME" \
  --arg content "\$(cat \"\$STACK_FILE\")" \
  --argjson env '{}' \
  '{Name: \$name, StackFileContent: \$content, Env: (\$env | to_entries | map({name: .key, value: .value}))}'
)

# 3) NEW create (Portainer 2.33+ common)
curl -sS -i -X POST \
  -H "X-API-Key: \$PORTAINER_API_KEY" \
  -H "Content-Type: application/json" \
  "\$PORTAINER_URL/api/stacks/create/standalone/string?endpointId=\$PORTAINER_ENDPOINT_ID" \
  -d "\$payload_old_create"

# 4) OLD create (legacy; may return 405 on newer Portainer)
curl -sS -i -X POST \
  -H "X-API-Key: \$PORTAINER_API_KEY" \
  -H "Content-Type: application/json" \
  "\$PORTAINER_URL/api/stacks?type=2&method=string&endpointId=\$PORTAINER_ENDPOINT_ID" \
  -d "\$payload_old_create"

# 5) Common update payload (what this action uses)
#    Endpoint: PUT /api/stacks/{id}?endpointId=...
#    Payload keys (note lowercase): stackFileContent, env, prune, pullImage
payload_update=\$(jq -n \
  --arg content "\$(cat \"\$STACK_FILE\")" \
  --argjson env '{}' \
  --argjson prune true \
  '{stackFileContent: \$content, env: (\$env | to_entries | map({name: .key, value: .value})), prune: \$prune, pullImage: true}'
)

# Replace STACK_ID with the one from step (1)
STACK_ID=123
curl -sS -i -X PUT \
  -H "X-API-Key: \$PORTAINER_API_KEY" \
  -H "Content-Type: application/json" \
  "\$PORTAINER_URL/api/stacks/\$STACK_ID?endpointId=\$PORTAINER_ENDPOINT_ID" \
  -d "\$payload_update"

# 6) Delete stack (DESTRUCTIVE)
#    Some Portainer setups require external=true (depends how the stack was created).
STACK_ID=123
curl -sS -i -X DELETE \
  -H "X-API-Key: \$PORTAINER_API_KEY" \
  "\$PORTAINER_URL/api/stacks/\$STACK_ID?endpointId=\$PORTAINER_ENDPOINT_ID"

STACK_ID=123
curl -sS -i -X DELETE \
  -H "X-API-Key: \$PORTAINER_API_KEY" \
  "\$PORTAINER_URL/api/stacks/\$STACK_ID?endpointId=\$PORTAINER_ENDPOINT_ID&external=true"

# 7) Other create candidates (varies by version)
#    Check swagger output above to confirm the exact route and params on YOUR instance.
#    These are the two most common alternatives:
#
#    (a) POST /api/stacks/create/standalone/string?endpointId=...
curl -sS -i -X POST \
  -H "X-API-Key: \$PORTAINER_API_KEY" \
  -H "Content-Type: application/json" \
  "\$PORTAINER_URL/api/stacks/create/standalone/string?endpointId=\$PORTAINER_ENDPOINT_ID" \
  -d "\$payload_old_create"

#    (b) POST /api/stacks/create/standalone/file?endpointId=...  (multipart) — varies by version
#        Use swagger to confirm if this exists.
EOF

if [[ "${PROBE_CREATE_ROUTES:-0}" == "1" ]]; then
  echo
  echo "== Probing common CREATE endpoints (safe) =="
  echo "This uses intentionally invalid stack content so Portainer should reject it."
  echo "Interpretation: HTTP 404 => route not present; HTTP 400/401/403 => route exists."

  # Intentionally invalid compose/stack content. This should be rejected with a 400
  # without creating anything.
  invalid_content="this-is-not-a-compose-file"

  # Two common payload shapes seen across Portainer versions.
  payload_create_caps=$(jq -n \
    --arg name "probe-${STACK_NAME}-$(date +%s)" \
    --arg content "$invalid_content" \
    --argjson env '{}' \
    '{Name: $name, StackFileContent: $content, Env: ($env | to_entries | map({name: .key, value: .value}))}'
  )

  payload_create_lower=$(jq -n \
    --arg name "probe-${STACK_NAME}-$(date +%s)" \
    --arg content "$invalid_content" \
    --argjson env '{}' \
    '{name: $name, stackFileContent: $content, env: ($env | to_entries | map({name: .key, value: .value}))}'
  )

  # Candidate endpoints to probe. These cover the historical and newer routes.
  # We try both payload key casings to spot syntax changes.
  declare -a create_urls=(
    "${BASE_URL}/api/stacks?type=2&method=string&endpointId=${ENDPOINT_ID}"
    "${BASE_URL}/api/stacks?type=1&method=string&endpointId=${ENDPOINT_ID}"
    "${BASE_URL}/api/stacks/create/standalone/string?endpointId=${ENDPOINT_ID}"
    "${BASE_URL}/api/stacks/create/standalone/string?type=2&endpointId=${ENDPOINT_ID}"
    "${BASE_URL}/api/stacks/create/swarm/string?endpointId=${ENDPOINT_ID}"
  )

  for url in "${create_urls[@]}"; do
    print_probe_result "create (caps keys)" POST "$url" "$payload_create_caps"
    print_probe_result "create (lower keys)" POST "$url" "$payload_create_lower"
  done
fi

if [[ "${PROBE_UPDATE_ROUTES:-0}" == "1" ]]; then
  if [[ -z "${STACK_ID}" ]]; then
    echo "Set STACK_ID to probe update/delete routes (e.g. STACK_ID=80)." >&2
    exit 2
  fi

  echo
  echo "== Probing UPDATE endpoints (safe-ish) =="
  echo "This uses intentionally invalid stack content; Portainer should reject it."
  echo "Interpretation: HTTP 404/405 => route not present; HTTP 400/500 => route exists; HTTP 200/204 => WARNING (it may have accepted the update)."

  invalid_content="this-is-not-a-compose-file"

  payload_update_lower=$(jq -n \
    --arg content "$invalid_content" \
    --argjson env '{}' \
    --argjson prune true \
    '{stackFileContent: $content, env: ($env | to_entries | map({name: .key, value: .value})), prune: $prune, pullImage: true}'
  )

  payload_update_caps=$(jq -n \
    --arg content "$invalid_content" \
    --argjson env '{}' \
    --argjson prune true \
    '{StackFileContent: $content, Env: ($env | to_entries | map({name: .key, value: .value})), Prune: $prune, PullImage: true}'
  )

  declare -a update_urls=(
    "${BASE_URL}/api/stacks/${STACK_ID}?endpointId=${ENDPOINT_ID}"
    "${BASE_URL}/api/stacks/${STACK_ID}?endpointId=${ENDPOINT_ID}&method=string"
    "${BASE_URL}/api/stacks/${STACK_ID}?endpointId=${ENDPOINT_ID}&type=2"
  )

  for url in "${update_urls[@]}"; do
    print_probe_result "update (lower keys)" PUT "$url" "$payload_update_lower"
    print_probe_result "update (caps keys)" PUT "$url" "$payload_update_caps"
  done

  echo
  echo "== Probing DELETE support (no deletion performed) =="
  echo "Uses OPTIONS to discover whether DELETE is allowed on the stack resource."
  echo "If you're behind a reverse proxy, OPTIONS may return 405 even when DELETE is permitted."

  # OPTIONS often returns 200/204 with an Allow header (not guaranteed).
  # We show headers so you can spot 'Allow: ...'.
  for url in \
    "${BASE_URL}/api/stacks/${STACK_ID}?endpointId=${ENDPOINT_ID}" \
    "${BASE_URL}/api/stacks/${STACK_ID}"; do
    echo
    echo "-- options"
    echo "OPTIONS ${url}"
    curl -sS -i -X OPTIONS -H "X-API-Key: ${PORTAINER_API_KEY}" "$url" | sed -n '1,25p'
  done

  echo
  echo "If DELETE is allowed, the usual delete call is:"
  echo "  curl -sS -i -X DELETE -H \"X-API-Key: \$PORTAINER_API_KEY\" \"${BASE_URL}/api/stacks/${STACK_ID}?endpointId=${ENDPOINT_ID}\""
  echo "If that fails for an external stack, try:"
  echo "  curl -sS -i -X DELETE -H \"X-API-Key: \$PORTAINER_API_KEY\" \"${BASE_URL}/api/stacks/${STACK_ID}?endpointId=${ENDPOINT_ID}&external=true\""
fi
