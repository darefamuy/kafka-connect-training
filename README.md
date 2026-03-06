# Pharma — Kafka Connect Demo

## Components

### Source Connectors (PostgreSQL → Confluent Cloud)

| Connector | Table | Mode | Target Topic |
|---|---|---|---|
| `hci-source-medicinal-products` | `medicinal_products` | `TIMESTAMP+INCREMENTING` on `updated_at` | `hci.medicinal_products` |
| `hci-source-price-updates` | `price_updates` | `TIMESTAMP+INCREMENTING` on `created_at` | `hci.price_updates` |
| `hci-source-drug-alerts` | `drug_alerts` | `INCREMENTING` on `id` | `hci.drug_alerts` |

**Change detection modes explained:**
- `medicinal_products` uses `TIMESTAMP+INCREMENTING` because product records are **updated** (e.g. marketing status changes, price corrections). The `updated_at` trigger fires on every `UPDATE`, and `id` breaks ties for rows with the same timestamp.
- `price_updates` and `drug_alerts` are **append-only** tables. `INCREMENTING` mode is sufficient — only new rows are ever published.

### Sink Connectors (Confluent Cloud → Elasticsearch)

| Connector | Source Topic | Elasticsearch Index |
|---|---|---|
| `hci-sink-alert-enriched` | `hci.alerts.enriched.v1` | `hci.alerts.enriched.v1` |
| `hci-sink-narcotics-alerts` | `hci.alerts.narcotics.v1` | `hci.alerts.narcotics.v1` |
| `hci-sink-price-surge` | `hci.prices.surge-notifications.v1` | `hci.prices.surge-notifications.v1` |
| `hci-sink-product-alert-summary` | `hci.products.alert-summary.v1` | `hci.products.alert-summary.v1` |
| `hci-sink-price-anomalies` | `hci.prices.anomalies.v1` | `hci.prices.anomalies.v1` |

---

## Prerequisites

- Docker Desktop (with at least 4GB RAM allocated)
- A running Confluent Cloud cluster with API keys
- The output topics must exist on Confluent Cloud before the sink connectors start  
  (or enable auto-create in your Confluent Cloud cluster settings)

---

## Quick Start

### 1. Configure credentials

```bash
cp .env.example .env
# Edit .env and fill in your Confluent Cloud values
```

### 2. Start all local services

```bash
docker compose up -d
```

Execute `./scripts/create-topics.sh` to provision relevant Kafka topics on Confluent cloud.

This starts PostgreSQL, Elasticsearch, Kibana, Kafka Connect, and the provisioner in order. The provisioner container waits for Connect to be ready, then registers all 8 connectors automatically.

### 3. Check everything is healthy

```bash
./scripts/check-status.sh
```

Expected output:
```
── PostgreSQL ──────
  ✓ PostgreSQL is ready
  ✓ medicinal_products: 16 rows
  ✓ price_updates:       7 rows
  ✓ drug_alerts:         6 rows

── Elasticsearch ───
  ✓ Elasticsearch is healthy (status: yellow)

── Kafka Connect ───
  ✓ Kafka Connect is running (version: 7.6.1)
  ✓ hci-source-medicinal-products: RUNNING
  ✓ hci-source-price-updates: RUNNING
  ✓ hci-source-drug-alerts: RUNNING
  ✓ hci-sink-alert-enriched: RUNNING
  ✓ hci-sink-narcotics-alerts: RUNNING
  ...
```

### 4. Verify initial data in Confluent Cloud

The seed data (16 products, 7 price updates, 6 drug alerts) will be picked up by the source connectors on first poll and published to Confluent Cloud. Check the topics in the Confluent Cloud UI.

### 5. Run live demo scenarios

```bash
# Run all scenarios in sequence (guided, interactive)
./scripts/simulate-events.sh all

# Or run a specific scenario
./scripts/simulate-events.sh recall          # CLASS_I narcotic recall
./scripts/simulate-events.sh price-surge     # 22% price increase → surge notification
./scripts/simulate-events.sh new-product     # New Swissmedic authorisation
./scripts/simulate-events.sh suspend         # Product suspension
```

---

## Useful Commands

### Kafka Connect REST API

```bash
# List all connectors
curl -s http://localhost:8083/connectors | jq

# Check a specific connector's status
curl -s http://localhost:8083/connectors/hci-source-drug-alerts/status | jq

# Pause a connector (useful for demo pauses)
curl -X PUT http://localhost:8083/connectors/hci-source-medicinal-products/pause

# Resume a connector
curl -X PUT http://localhost:8083/connectors/hci-source-medicinal-products/resume

# View connector config
curl -s http://localhost:8083/connectors/hci-source-medicinal-products/config | jq

# Delete a connector
curl -X DELETE http://localhost:8083/connectors/hci-source-medicinal-products


### PostgreSQL (direct inspection)

```bash
# Connect to psql
docker compose exec postgres psql -U hci_user -d hci_pharma

# Count rows per table
docker compose exec postgres psql -U hci_user -d hci_pharma -c \
  "SELECT 'medicinal_products' AS tbl, COUNT(*) FROM medicinal_products
   UNION ALL SELECT 'price_updates', COUNT(*) FROM price_updates
   UNION ALL SELECT 'drug_alerts', COUNT(*) FROM drug_alerts;"

# Watch for real-time changes (run before simulate-events.sh)
docker compose exec postgres psql -U hci_user -d hci_pharma -c \
  "SELECT gtin, product_name, marketing_status, updated_at
   FROM medicinal_products ORDER BY updated_at DESC LIMIT 5;"
```

---

## Single Message Transforms (SMTs)

Each connector uses Kafka Connect's built-in SMTs to reshape records without writing code:

| SMT | Used in | Purpose |
|---|---|---|
| `ReplaceField` | Source connectors | Rename `snake_case` SQL columns to `camelCase` Avro fields |
| `ValueToKey` | Source connectors | Promote `gtin` from the value to the Kafka message key |
| `TimestampConverter` | Source connectors | Convert SQL `TIMESTAMP` → Unix epoch milliseconds (Avro logical type) |
| `ReplaceField` (blacklist) | Price source | Drop internal columns (`id`, `created_at`) before publishing |
| `ExtractField` | Sink connectors | Use `gtin` from the key as the Elasticsearch document `_id` |

---

## Dead-Letter Queue (DLQ)

Every connector has error tolerance configured:

```json
"errors.tolerance": "all",
"errors.log.enable": "true",
"errors.deadletterqueue.topic.name": "hci.dlq.connect-source-products",
"errors.deadletterqueue.context.headers.enable": "true"
```

