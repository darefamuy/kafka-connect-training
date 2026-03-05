#!/bin/bash
# =============================================================================
# simulate-events.sh
# Live demo script: inserts new pharmaceutical events into PostgreSQL to
# demonstrate Kafka Connect source connectors picking up changes in real time.
#
# Usage:
#   chmod +x scripts/simulate-events.sh
#   ./scripts/simulate-events.sh [scenario]
#
# Scenarios:
#   all          Run all scenarios in sequence (default)
#   new-product  Insert a new medicinal product
#   price-surge  Insert a price update above the 15% surge threshold
#   price-normal Insert a normal price update (below threshold)
#   recall       Insert a CLASS_I drug recall
#   shortage     Insert a shortage alert
#   suspend      Suspend a product (status change)
# =============================================================================

set -euo pipefail

PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
PGDB="${PGDB:-hci_pharma}"
PGUSER="${PGUSER:-hci_user}"
PGPASSWORD="${PGPASSWORD:-hci_secret}"
export PGPASSWORD

PSQL="psql -h $PGHOST -p $PGPORT -d $PGDB -U $PGUSER -v ON_ERROR_STOP=1"

SCENARIO="${1:-all}"

log() { echo "[$(date '+%H:%M:%S')] $*"; }
section() { echo ""; echo "=================================================="; echo "  $*"; echo "=================================================="; }
pause() { echo ""; read -rp "  → Press ENTER to continue to next step..." _; echo ""; }

# ── Scenario: new product registration ───────────────────────────────────────
scenario_new_product() {
  section "SCENARIO: New Product Registration"
  log "Inserting a newly authorised Swissmedic product into PostgreSQL..."
  log "The JDBC Source connector will detect this (updated_at mode) and"
  log "publish to hci.medicinal_products on Confluent Cloud within 5 seconds."
  echo ""

  $PSQL <<'SQL'
INSERT INTO medicinal_products
  (gtin, authorization_number, product_name, atc_code, dosage_form,
   manufacturer, active_substance, marketing_status,
   ex_factory_price_chf, public_price_chf, package_size, narcotics_category)
VALUES
  ('7680800010002', '80001', 'Dupilumab Sanofi Inj 300 mg',
   'D11AH05', 'Injektionslösung', 'Sanofi-Aventis (Suisse) SA', 'Dupilumab',
   'ACTIVE', 892.50, 2084.50, '2 Fertigspritzen 2ml', NULL);

SELECT id, gtin, product_name, marketing_status, public_price_chf, updated_at
FROM medicinal_products
WHERE gtin = '7680800010002';
SQL

  log "✓ Product inserted. Watch hci.medicinal_products on Confluent Cloud for the event."
}

# ── Scenario: price surge ─────────────────────────────────────────────────────
scenario_price_surge() {
  section "SCENARIO: Price Surge (>15% increase — triggers surge detector)"
  log "Inserting a large price increase for Insulin Humalog."
  log "The Kafka Streams PriceSurgeDetectionTopology will detect this and"
  log "emit a notification to hci.prices.surge-notifications.v1,"
  log "which the ES Sink connector will write to Elasticsearch."
  echo ""

  $PSQL <<'SQL'
-- First, show current price
SELECT gtin, product_name, public_price_chf FROM medicinal_products WHERE gtin = '7680566730021';

-- Insert a 22% price increase (CHF 99.90 → CHF 122.00)
INSERT INTO price_updates
  (gtin, previous_ex_factory_price_chf, new_ex_factory_price_chf,
   previous_public_price_chf, new_public_price_chf,
   effective_date_utc, change_reason, changed_by, approval_reference)
VALUES
  ('7680566730021', 42.80, 52.20, 99.90, 122.00,
   NOW(), 'MANUFACTURER_REQUEST', 'Eli Lilly (Suisse) SA', 'MR-2025-0201');

SELECT id, gtin, previous_public_price_chf, new_public_price_chf,
       ROUND(((new_public_price_chf - previous_public_price_chf) / previous_public_price_chf * 100)::numeric, 1) AS change_pct,
       change_reason
FROM price_updates ORDER BY id DESC LIMIT 1;
SQL

  log "✓ Price surge inserted (+22%). Check hci.prices.surge-notifications.v1"
  log "  and the Elasticsearch index: hci.prices.surge-notifications.v1"
}

# ── Scenario: normal price update ─────────────────────────────────────────────
scenario_price_normal() {
  section "SCENARIO: Normal Price Update (below 15% threshold)"
  log "Inserting a small BAG-mandated price reduction for Omeprazol."
  log "This will be published to hci.price_updates but will NOT trigger the surge detector."
  echo ""

  $PSQL <<'SQL'
INSERT INTO price_updates
  (gtin, previous_ex_factory_price_chf, new_ex_factory_price_chf,
   previous_public_price_chf, new_public_price_chf,
   effective_date_utc, change_reason, changed_by, approval_reference)
VALUES
  ('7680603410015', 9.60, 9.10, 22.40, 21.20,
   NOW(), 'BAG_REVIEW', 'BAG-Preisbehoerde', 'BAG-SL-2025-06');

SELECT id, gtin, previous_public_price_chf, new_public_price_chf,
       ROUND(((new_public_price_chf - previous_public_price_chf) / previous_public_price_chf * 100)::numeric, 1) AS change_pct
FROM price_updates ORDER BY id DESC LIMIT 1;
SQL

  log "✓ Normal price update inserted (-5.4%). No surge notification expected."
}

# ── Scenario: CLASS_I recall ──────────────────────────────────────────────────
scenario_recall() {
  section "SCENARIO: CLASS_I Drug Recall (Narcotic)"
  log "Inserting a new Swissmedic CLASS_I recall for a narcotic product."
  log "The Kafka Streams AlertEnrichmentTopology will:"
  log "  1. Join the alert with the product catalogue"
  log "  2. Emit to hci.alerts.enriched.v1 (all enriched alerts)"
  log "  3. Also emit to hci.alerts.narcotics.v1 (narcotics-only split)"
  log "Both topics will be sinked to Elasticsearch by separate connectors."
  echo ""

  $PSQL <<'SQL'
INSERT INTO drug_alerts
  (gtin, alert_type, severity, headline, description,
   affected_lots, issued_by_utc, source_url)
VALUES
  ('7680312440033',
   'RECALL', 'CLASS_I',
   'ZWINGENDER RÜCKRUF: Morphin HCl Streuli Inj 10mg/ml — sterile Kontamination',
   'Swissmedic ordnet den zwingenden Rückruf weiterer Chargen von Morphin HCl Streuli Inj 10mg/ml an. Mikrobiologische Nachuntersuchungen haben in einer zusätzlichen Charge das Vorhandensein von Kontaminanten bestätigt. Alle betroffenen Produkte sind unverzüglich aus dem Verkehr zu ziehen und in der Apotheke zu sperren.',
   'CH-2025-0101,CH-2025-0102',
   NOW(),
   'https://www.swissmedic.ch/swissmedic/de/home/humanarzneimittel/marktueberwachung/2025/morphin-streuli-recall-2.html');

SELECT id, gtin, alert_type, severity, headline, issued_by_utc
FROM drug_alerts ORDER BY id DESC LIMIT 1;
SQL

  log "✓ CLASS_I recall inserted for narcotic GTIN 7680312440033."
  log "  Check: hci.alerts.enriched.v1 AND hci.alerts.narcotics.v1"
  log "  Elasticsearch indices: hci.alerts.enriched.v1, hci.alerts.narcotics.v1"
}

# ── Scenario: shortage alert ──────────────────────────────────────────────────
scenario_shortage() {
  section "SCENARIO: Shortage Alert"
  log "Inserting a new shortage alert for Amoxicillin 1000mg."
  echo ""

  $PSQL <<'SQL'
INSERT INTO drug_alerts
  (gtin, alert_type, severity, headline, description,
   affected_lots, issued_by_utc, expires_utc, source_url)
VALUES
  ('7680421830038',
   'SHORTAGE', 'CLASS_II',
   'Lieferengpass: Amoxicillin Sandoz Kaps 1000mg — temporäre Unterversorgung',
   'Aufgrund eines Kapazitätsengpasses beim europäischen Wirkstofflieferanten kommt es zu einem vorübergehenden Lieferengpass bei Amoxicillin Sandoz Kaps 1000mg. Ersatzprodukte sind verfügbar.',
   '',
   NOW(),
   NOW() + INTERVAL '90 days',
   'https://www.swissmedic.ch/swissmedic/de/home/humanarzneimittel/marktueberwachung/lieferengpaesse.html');

SELECT id, gtin, alert_type, severity, headline
FROM drug_alerts ORDER BY id DESC LIMIT 1;
SQL

  log "✓ Shortage alert inserted."
}

# ── Scenario: product suspension ─────────────────────────────────────────────
scenario_suspend() {
  section "SCENARIO: Product Suspension (Marketing Status Change)"
  log "Suspending Atorvastatin 40mg — the updated_at trigger will fire,"
  log "and the JDBC Source connector will re-publish the updated row to Kafka."
  log "The KTable in Kafka Streams will update its local state store entry."
  echo ""

  $PSQL <<'SQL'
-- Show current status
SELECT gtin, product_name, marketing_status, updated_at
FROM medicinal_products WHERE gtin = '7680487220026';

-- Suspend the product
UPDATE medicinal_products
SET marketing_status = 'SUSPENDED'
WHERE gtin = '7680487220026';

-- Confirm update (updated_at will have changed)
SELECT gtin, product_name, marketing_status, updated_at
FROM medicinal_products WHERE gtin = '7680487220026';
SQL

  log "✓ Product suspended. The updated_at trigger has fired."
  log "  The JDBC connector will detect this change on next poll (~5s)"
  log "  and publish the updated record to hci.medicinal_products."
}

# ── Run selected scenario ─────────────────────────────────────────────────────
case "$SCENARIO" in
  all)
    section "FULL DEMO — All Scenarios"
    echo "This script will walk through all demonstration scenarios."
    echo "After each step, check Confluent Cloud topics and Elasticsearch."
    pause

    scenario_new_product
    pause

    scenario_price_normal
    pause

    scenario_price_surge
    pause

    scenario_recall
    pause

    scenario_shortage
    pause

    scenario_suspend

    echo ""
    section "DEMO COMPLETE"
    echo "All scenarios executed. Check:"
    echo "  - Confluent Cloud UI → Topics → hci.*"
    echo "  - Elasticsearch:  curl http://localhost:9200/_cat/indices?v"
    echo "  - Kibana:         http://localhost:5601"
    ;;
  new-product)  scenario_new_product ;;
  price-surge)  scenario_price_surge ;;
  price-normal) scenario_price_normal ;;
  recall)       scenario_recall ;;
  shortage)     scenario_shortage ;;
  suspend)      scenario_suspend ;;
  *)
    echo "Unknown scenario: $SCENARIO"
    echo "Valid: all | new-product | price-surge | price-normal | recall | shortage | suspend"
    exit 1
    ;;
esac
