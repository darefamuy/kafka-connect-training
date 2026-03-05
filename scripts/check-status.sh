#!/bin/bash
# =============================================================================
# check-status.sh
# Quick health check for all components in the HCI Kafka Connect demo.
# =============================================================================

CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"
ES_URL="${ES_URL:-http://localhost:9200}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $*"; }

section() { echo ""; echo "── $* ──────────────────────────────────────────"; }

echo "=================================================="
echo "  HCI Kafka Connect — Status Check"
echo "=================================================="

# ── PostgreSQL ────────────────────────────────────────────────────────────────
section "PostgreSQL"
if docker compose exec -T postgres pg_isready -U hci_user -d hci_pharma > /dev/null 2>&1; then
  ok "PostgreSQL is ready"

  product_count=$(docker compose exec -T postgres psql -U hci_user -d hci_pharma -tAc "SELECT COUNT(*) FROM medicinal_products")
  price_count=$(docker compose exec -T postgres psql -U hci_user -d hci_pharma -tAc "SELECT COUNT(*) FROM price_updates")
  alert_count=$(docker compose exec -T postgres psql -U hci_user -d hci_pharma -tAc "SELECT COUNT(*) FROM drug_alerts")
  ok "medicinal_products: ${product_count} rows"
  ok "price_updates:      ${price_count} rows"
  ok "drug_alerts:        ${alert_count} rows"
else
  fail "PostgreSQL is not ready"
fi

# ── Elasticsearch ─────────────────────────────────────────────────────────────
section "Elasticsearch"
if curl -sf "${ES_URL}/_cluster/health" > /dev/null 2>&1; then
  health=$(curl -sf "${ES_URL}/_cluster/health" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
  if [ "$health" = "green" ] || [ "$health" = "yellow" ]; then
    ok "Elasticsearch is healthy (status: ${health})"
  else
    fail "Elasticsearch is in status: ${health}"
  fi

  echo ""
  echo "  Indices:"
  curl -sf "${ES_URL}/_cat/indices?h=index,docs.count,store.size&s=index" 2>/dev/null | \
    grep "^hci" | while read -r line; do
      echo "    $line"
    done || echo "    (no hci.* indices yet)"
else
  fail "Elasticsearch is not reachable at ${ES_URL}"
fi

# ── Kafka Connect ─────────────────────────────────────────────────────────────
section "Kafka Connect Worker"
if curl -sf "${CONNECT_URL}/" > /dev/null 2>&1; then
  version=$(curl -sf "${CONNECT_URL}/" | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
  ok "Kafka Connect is running (version: ${version})"

  echo ""
  echo "  Connector status:"
  connectors=$(curl -sf "${CONNECT_URL}/connectors" 2>/dev/null | tr -d '[]"' | tr ',' '\n')

  if [ -z "$(echo $connectors | tr -d ' ')" ]; then
    warn "No connectors registered yet. Run: scripts/provision-connectors.sh"
  else
    for connector in $connectors; do
      if [ -n "$connector" ]; then
        state=$(curl -sf "${CONNECT_URL}/connectors/${connector}/status" 2>/dev/null | \
          grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)
        case "$state" in
          RUNNING) ok "${connector}: ${state}" ;;
          PAUSED)  warn "${connector}: ${state}" ;;
          *)       fail "${connector}: ${state:-UNKNOWN}" ;;
        esac
      fi
    done
  fi
else
  fail "Kafka Connect REST API not reachable at ${CONNECT_URL}"
fi

# ── Kibana ────────────────────────────────────────────────────────────────────
section "Kibana"
if curl -sf "http://localhost:5601/api/status" > /dev/null 2>&1; then
  ok "Kibana is running at http://localhost:5601"
else
  warn "Kibana not reachable yet (may still be starting)"
fi

echo ""
echo "=================================================="
