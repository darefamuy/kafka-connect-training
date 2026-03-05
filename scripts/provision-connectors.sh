#!/bin/sh
# =============================================================================
# provision-connectors.sh
# Waits for the Kafka Connect REST API to become available, then registers
# all source and sink connectors in numbered order.
#
# Runs as a one-shot Docker container (see docker-compose.yml: provisioner).
# =============================================================================

set -e

CONNECT_URL="${CONNECT_URL:-http://connect:8083}"
MAX_WAIT=120
SLEEP_INTERVAL=5

echo "=================================================="
echo "HCI Kafka Connect — Connector Provisioner"
echo "Target: ${CONNECT_URL}"
echo "=================================================="

# ── Wait for Connect REST API ─────────────────────────────────────────────────
echo "Waiting for Kafka Connect to be ready..."
elapsed=0
until curl -sf "${CONNECT_URL}/connectors" > /dev/null 2>&1; do
  if [ $elapsed -ge $MAX_WAIT ]; then
    echo "ERROR: Kafka Connect did not become ready within ${MAX_WAIT}s. Aborting."
    exit 1
  fi
  echo "  Connect not ready yet (${elapsed}s elapsed) — retrying in ${SLEEP_INTERVAL}s..."
  sleep $SLEEP_INTERVAL
  elapsed=$((elapsed + SLEEP_INTERVAL))
done

echo "Connect is ready."
echo ""

# ── Helper: register or update a connector ────────────────────────────────────
register_connector() {
  local config_file="$1"
  local connector_name

  connector_name=$(grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_file" | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')

  echo "--------------------------------------------------"
  echo "Registering: ${connector_name}"
  echo "Config file: ${config_file}"

  # Check if connector already exists
  http_status=$(curl -s -o /dev/null -w "%{http_code}" "${CONNECT_URL}/connectors/${connector_name}")

  if [ "$http_status" = "200" ]; then
    echo "  Connector exists — deleting before recreating..."
    curl -s -X DELETE "${CONNECT_URL}/connectors/${connector_name}"
    # Wait a second for delete to propagate in the worker
    sleep 1
  fi

  echo "  Creating connector..."
  response=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    --data "@${config_file}" \
    "${CONNECT_URL}/connectors")

  # Check for error in response
  if echo "$response" | grep -q '"error_code"'; then
    echo "  ERROR registering ${connector_name}:"
    echo "  $response"
  else
    echo "  OK: ${connector_name} registered."
  fi
}

# ── Register source connectors ────────────────────────────────────────────────
echo ""
echo "=== SOURCE CONNECTORS (PostgreSQL → Confluent Cloud) ==="
echo ""

for f in /connectors/source/*.json; do
  register_connector "$f"
done

# ── Register sink connectors ──────────────────────────────────────────────────
echo ""
echo "=== SINK CONNECTORS (Confluent Cloud → Elasticsearch) ==="
echo ""

for f in /connectors/sink/*.json; do
  register_connector "$f"
done

# ── Print final status ────────────────────────────────────────────────────────
echo ""
echo "=================================================="
echo "All connectors provisioned. Current status:"
echo ""
curl -s "${CONNECT_URL}/connectors?expand=status" | \
  grep -o '"name":"[^"]*"\|"state":"[^"]*"' | \
  paste - -
echo ""
echo "=================================================="
echo "Done."
