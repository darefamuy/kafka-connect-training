-- =============================================================================
-- HCI Pharma — PostgreSQL Schema
-- Source database for Kafka Connect JDBC Source connectors
--
-- Three tables mirror the three input Kafka topics:
--   medicinal_products  →  hci.medicinal_products
--   price_updates       →  hci.price_updates
--   drug_alerts         →  hci.drug_alerts
--
-- The JDBC Source connector uses the `updated_at` timestamp column on
-- medicinal_products and price_updates (TIMESTAMP mode) to detect new and
-- changed rows without requiring a Kafka-side change-data-capture setup.
--
-- drug_alerts uses an auto-incrementing `id` column (INCREMENTING mode)
-- because alerts are immutable — they are never updated, only appended.
-- =============================================================================

-- Enable the uuid extension for alert IDs
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- -----------------------------------------------------------------------------
-- medicinal_products
-- Represents the Swissmedic-authorised product catalogue.
-- JDBC connector mode: TIMESTAMP+INCREMENTING on (updated_at, id)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS medicinal_products (
    id                      SERIAL          PRIMARY KEY,
    gtin                    VARCHAR(14)     NOT NULL UNIQUE,
    authorization_number    VARCHAR(20)     NOT NULL,
    product_name            VARCHAR(255)    NOT NULL,
    atc_code                VARCHAR(10)     NOT NULL,
    dosage_form             VARCHAR(100)    NOT NULL,
    manufacturer            VARCHAR(255)    NOT NULL,
    active_substance        VARCHAR(255)    NOT NULL,
    marketing_status        VARCHAR(20)     NOT NULL DEFAULT 'ACTIVE'
                                CHECK (marketing_status IN ('ACTIVE','SUSPENDED','WITHDRAWN','PENDING')),
    ex_factory_price_chf    NUMERIC(10,2)   NOT NULL CHECK (ex_factory_price_chf >= 0),
    public_price_chf        NUMERIC(10,2)   NOT NULL CHECK (public_price_chf >= 0),
    data_source             VARCHAR(100)    NOT NULL DEFAULT 'hci-master',
    package_size            VARCHAR(100),
    narcotics_category      VARCHAR(20),
    -- Timestamp used by JDBC connector to detect changed rows
    updated_at              TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Index on the JDBC connector timestamp column (required for performance)
CREATE INDEX IF NOT EXISTS idx_medicinal_products_updated_at
    ON medicinal_products(updated_at);

-- Trigger: auto-update updated_at on row modification
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_medicinal_products_updated_at
    BEFORE UPDATE ON medicinal_products
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -----------------------------------------------------------------------------
-- price_updates
-- Immutable price change events. Each row is a new event, never updated.
-- JDBC connector mode: TIMESTAMP+INCREMENTING on (effective_date_utc, id)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS price_updates (
    id                          SERIAL          PRIMARY KEY,
    gtin                        VARCHAR(14)     NOT NULL,
    previous_ex_factory_price_chf NUMERIC(10,2) NOT NULL,
    new_ex_factory_price_chf    NUMERIC(10,2)   NOT NULL CHECK (new_ex_factory_price_chf >= 0),
    previous_public_price_chf   NUMERIC(10,2)   NOT NULL,
    new_public_price_chf        NUMERIC(10,2)   NOT NULL CHECK (new_public_price_chf >= 0),
    effective_date_utc          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    change_reason               VARCHAR(100)    NOT NULL,
    changed_by                  VARCHAR(100)    NOT NULL DEFAULT 'hci-system',
    approval_reference          VARCHAR(100),
    -- Connector uses this to detect new rows (insert-only table)
    created_at                  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_price_updates_created_at
    ON price_updates(created_at);
CREATE INDEX IF NOT EXISTS idx_price_updates_gtin
    ON price_updates(gtin);

-- -----------------------------------------------------------------------------
-- drug_alerts
-- Swissmedic drug alert events. Immutable — append only.
-- JDBC connector mode: INCREMENTING on id
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS drug_alerts (
    id                  SERIAL          PRIMARY KEY,
    alert_id            UUID            NOT NULL DEFAULT uuid_generate_v4() UNIQUE,
    gtin                VARCHAR(14)     NOT NULL,
    alert_type          VARCHAR(30)     NOT NULL
                            CHECK (alert_type IN ('RECALL','SHORTAGE','QUALITY_DEFECT','PRICE_SUSPENSION','IMPORT_BAN')),
    severity            VARCHAR(20)     NOT NULL
                            CHECK (severity IN ('CLASS_I','CLASS_II','CLASS_III','ADVISORY')),
    headline            VARCHAR(500)    NOT NULL,
    description         TEXT            NOT NULL,
    -- affected_lots stored as comma-separated string for SQL simplicity;
    -- the SMT (Single Message Transform) in the connector config splits this
    -- into an array before publishing to Kafka.
    affected_lots       TEXT            DEFAULT '',
    issued_by_utc       TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    expires_utc         TIMESTAMP WITH TIME ZONE,
    source_url          VARCHAR(500)    NOT NULL DEFAULT 'https://www.swissmedic.ch'
);

CREATE INDEX IF NOT EXISTS idx_drug_alerts_gtin
    ON drug_alerts(gtin);
CREATE INDEX IF NOT EXISTS idx_drug_alerts_issued_by_utc
    ON drug_alerts(issued_by_utc);
CREATE INDEX IF NOT EXISTS idx_drug_alerts_alert_type
    ON drug_alerts(alert_type);

-- Grant permissions to application user
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO hci_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO hci_user;
