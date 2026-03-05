#!/bin/bash
# =============================================================================
# create-topics.sh
# Creates all required Kafka topics on Confluent Cloud for the HCI Pharma
# Kafka Connect + Kafka Streams demo.
#
# Prerequisites:
#   - Confluent CLI installed: https://docs.confluent.io/confluent-cli/current/install.html
#   - Logged in to Confluent Cloud: confluent login
#   - .env file present with credentials filled in
#
# Usage:
#   chmod +x scripts/create-topics.sh
#   ./scripts/create-topics.sh
#
# To delete all topics (full reset between demos):
#   ./scripts/create-topics.sh --delete
# =============================================================================

set -euo pipefail

# ── Load credentials from .env ─────────────────────────────────────────────────
if [ ! -f ".env" ]; then
  echo "ERROR: .env file not found. Copy .env.example to .env and fill in your credentials."
  exit 1
fi
# shellcheck disable=SC1091
set -o allexport && source .env && set +o allexport

# ── Validate required variables ────────────────────────────────────────────────
: "${CONFLUENT_BOOTSTRAP_SERVERS:?ERROR: CONFLUENT_BOOTSTRAP_SERVERS not set in .env}"
: "${CONFLUENT_API_KEY:?ERROR: CONFLUENT_API_KEY not set in .env}"
: "${CONFLUENT_API_SECRET:?ERROR: CONFLUENT_API_SECRET not set in .env}"

# ── Mode flags ─────────────────────────────────────────────────────────────────
DELETE_MODE=false
[ "${1:-}" = "--delete" ] && DELETE_MODE=true

# ── Colour helpers ─────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()      { echo -e "  ${GREEN}✓${NC} $*"; }
fail_msg(){ echo -e "  ${RED}✗${NC} $*"; }
info()    { echo -e "  ${CYAN}→${NC} $*"; }
warn()    { echo -e "  ${YELLOW}⚠${NC} $*"; }
section() { echo ""; echo -e "${CYAN}── $* ──────────────────────────────────────────────${NC}"; }

# ── Counters ───────────────────────────────────────────────────────────────────
created=0; skipped=0; failed=0; deleted=0

# ── Topic registry ─────────────────────────────────────────────────────────────
SOURCE_INPUT_TOPICS=(
  "hci.medicinal_products|6|604800000|delete"
  "hci.price_updates|6|604800000|delete"
  "hci.drug_alerts|6|604800000|delete"
)

STREAMS_OUTPUT_TOPICS=(
  "hci.alerts.enriched.v1|6|2592000000|delete"
  "hci.alerts.narcotics.v1|6|2592000000|delete"
  "hci.prices.surge-notifications.v1|6|2592000000|delete"
  "hci.products.alert-summary.v1|6|2592000000|delete"
  "hci.prices.anomalies.v1|6|2592000000|delete"
)

STREAMS_INTERNAL_TOPICS=(
  "hci-pharma-streams-product-catalog-store-changelog|6|-1|compact"
  "hci-pharma-streams-alert-counts-store-changelog|6|-1|compact"
  "hci-pharma-streams-confirmed-public-price-store-changelog|6|-1|compact"
  "hci-pharma-streams-alert-product-join-subscription-registration-topic|6|604800000|delete"
  "hci-pharma-streams-alert-product-join-subscription-response-topic|6|604800000|delete"
)

CONNECT_INTERNAL_TOPICS=(
  "_hci-connect-configs|1|-1|compact"
  "_hci-connect-offsets|25|-1|compact"
  "_hci-connect-status|5|-1|compact"
)

DLQ_TOPICS=(
  "hci.dlq.products.v1|3|1209600000|delete"
  "hci.dlq.prices.v1|3|1209600000|delete"
  "hci.dlq.alerts.v1|3|1209600000|delete"
  "hci.dlq.connect-source-products|3|1209600000|delete"
  "hci.dlq.connect-source-prices|3|1209600000|delete"
  "hci.dlq.connect-source-alerts|3|1209600000|delete"
  "hci.dlq.connect-sink-alert-enriched|3|1209600000|delete"
  "hci.dlq.connect-sink-narcotics|3|1209600000|delete"
  "hci.dlq.connect-sink-price-surge|3|1209600000|delete"
  "hci.dlq.connect-sink-price-anomalies|3|1209600000|delete"
  "hci.dlq.connect-sink-alert-summary|3|1209600000|delete"
)

ALL_TOPICS=(
  "${SOURCE_INPUT_TOPICS[@]}"
  "${STREAMS_OUTPUT_TOPICS[@]}"
  "${STREAMS_INTERNAL_TOPICS[@]}"
  "${CONNECT_INTERNAL_TOPICS[@]}"
  "${DLQ_TOPICS[@]}"
)

# ── Helper: create one topic ──────────────────────────────────────────────────
create_topic() {
  local entry="$1"
  local topic_name partitions retention cleanup extra_config output

  topic_name=$(echo "$entry" | cut -d'|' -f1)
  partitions=$(echo "$entry"  | cut -d'|' -f2)
  retention=$(echo "$entry"   | cut -d'|' -f3)
  cleanup=$(echo "$entry"     | cut -d'|' -f4)

  info "Creating: ${topic_name} (partitions=${partitions}, retention=${retention}ms, cleanup=${cleanup})"

  extra_config=""
  if [ "$cleanup" = "compact" ]; then
    extra_config="--config min.cleanable.dirty.ratio=0.1 --config segment.ms=600000"
  fi

  # shellcheck disable=SC2086
  if output=$(confluent kafka topic create "$topic_name" \
      --partitions "$partitions" \
      --config "retention.ms=${retention}" \
      --config "cleanup.policy=${cleanup}" \
      $extra_config 2>&1); then
    ok "Created:  $topic_name"
    created=$((created + 1))
  else
    # Logic: If it's a known "already exists" error, skip it.
    # Otherwise, report the failure and show the error.
    if echo "$output" | grep -qi "already exists\|topic already"; then
      warn "Exists (skipping): $topic_name"
      skipped=$((skipped + 1))
    else
      fail_msg "FAILED:   $topic_name"
      echo "          Error: $output"
      failed=$((failed + 1))
    fi
  fi
}

# ── Helper: delete one topic ───────────────────────────────────────────────────
delete_topic() {
  local topic_name="$1"
  if confluent kafka topic delete "$topic_name" --force 2>/dev/null; then
    ok "Deleted: $topic_name"
    deleted=$((deleted + 1))
  else
    warn "Not found (skipping): $topic_name"
  fi
}

# ── Pre-flight checks ──────────────────────────────────────────────────────────
if ! command -v confluent &>/dev/null; then
  echo -e "\nERROR: 'confluent' CLI not found. Install from: https://docs.confluent.io/confluent-cli/current/install.html\n"
  exit 1
fi

if ! confluent kafka cluster list &>/dev/null 2>&1; then
  warn "Not logged in to Confluent Cloud. Attempting login..."
  confluent login --save
fi

# Mandatory cluster selection if ID is provided
if [ -n "${CONFLUENT_CLUSTER_ID:-}" ]; then
  if confluent kafka cluster use "$CONFLUENT_CLUSTER_ID" &>/dev/null; then
    ok "Selected cluster: $CONFLUENT_CLUSTER_ID"
  else
    fail_msg "CRITICAL: Could not select cluster $CONFLUENT_CLUSTER_ID. Check your .env file."
    exit 1
  fi
else
  warn "CONFLUENT_CLUSTER_ID not set in .env — using currently selected cluster"
fi

# ── Show active context ────────────────────────────────────────────────────────
ACTIVE_ENV=$(confluent environment list | grep '*' | awk '{print $NF}' | tr -d '()')
ACTIVE_CLUSTER=$(confluent kafka cluster list | grep '*' | awk '{print $2}')
info "Active Environment: ${ACTIVE_ENV:-unknown}"
info "Active Cluster:     ${ACTIVE_CLUSTER:-unknown}"

# ── Banner ─────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════"
if $DELETE_MODE; then
  echo "  HCI Pharma — DELETE all Confluent Cloud topics"
else
  echo "  HCI Pharma — CREATE all Confluent Cloud topics"
fi
echo "  Bootstrap:  $CONFLUENT_BOOTSTRAP_SERVERS"
echo "  Topics:     ${#ALL_TOPICS[@]} total"
echo "════════════════════════════════════════════════════════"

# ── Delete mode ────────────────────────────────────────────────────────────────
if $DELETE_MODE; then
  echo -e "\n  ${RED}WARNING: This permanently deletes all topic data.${NC}"
  read -rp "  Type 'delete' to confirm: " confirm
  [ "$confirm" = "delete" ] || { echo "Aborted."; exit 0; }

  section "Deleting all HCI topics"
  for entry in "${ALL_TOPICS[@]}"; do
    delete_topic "$(echo "$entry" | cut -d'|' -f1)"
  done

  echo -e "\n────────────────────────────────────────────────────"
  echo "  Deleted: $deleted topic(s)"
  echo "────────────────────────────────────────────────────"
  exit 0
fi

# ── Create mode ────────────────────────────────────────────────────────────────

section "1 of 4 Source Input Topics"
for entry in "${SOURCE_INPUT_TOPICS[@]}"; do create_topic "$entry"; done

section "2 of 4 Kafka Streams Output Topics"
for entry in "${STREAMS_OUTPUT_TOPICS[@]}"; do create_topic "$entry"; done

section "3 of 4 Internal Topics"
for entry in "${STREAMS_INTERNAL_TOPICS[@]}"; do create_topic "$entry"; done
for entry in "${CONNECT_INTERNAL_TOPICS[@]}"; do create_topic "$entry"; done

section "4 of 4 Dead-Letter Queue Topics"
for entry in "${DLQ_TOPICS[@]}"; do create_topic "$entry"; done

# ── Summary ────────────────────────────────────────────────────────────────────
echo -e "\n════════════════════════════════════════════════════════"
echo "  Results"
echo "  ✓ Created:  $created"
echo "  ⚠ Skipped:  $skipped (already existed)"
echo -e "  ✗ Failed:   $([ $failed -gt 0 ] && echo -e "${RED}$failed${NC}" || echo "$failed")"
echo "════════════════════════════════════════════════════════"

if [ $failed -gt 0 ]; then
  echo ""
  warn "$failed topic(s) failed. Check API key permissions and cluster status."
  exit 1
fi

ok "All $((created + skipped)) topics are ready on Confluent Cloud."
echo -e "\n  Next steps:"
echo "  1. Start local services: docker compose up -d"
echo "  2. Check status:         ./scripts/check-status.sh"
echo "  3. Run the demo:         ./scripts/simulate-events.sh all"
echo ""
