-- =============================================================================
-- HCI Pharma — Seed Data
-- Realistic Swiss pharmaceutical product data for demo purposes.
-- Products, prices, and alerts are based on the Swiss Spezialitätenliste (SL)
-- structure with fictional but plausible values.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Medicinal Products
-- Represents a snapshot of Swissmedic-authorised products in the HCI catalogue.
-- -----------------------------------------------------------------------------
INSERT INTO medicinal_products
    (gtin, authorization_number, product_name, atc_code, dosage_form,
     manufacturer, active_substance, marketing_status,
     ex_factory_price_chf, public_price_chf, package_size, narcotics_category)
VALUES
-- Analgesics / Antipyretics (ATC: N02)
('7680500350178', '54656', 'Dafalgan Filmtabl 500 mg',
 'N02BE01', 'Filmtablette', 'UPSA SAS', 'Paracetamol',
 'ACTIVE', 3.20, 7.50, '20 Tabletten', NULL),

('7680500350185', '54656', 'Dafalgan Filmtabl 1000 mg',
 'N02BE01', 'Filmtablette', 'UPSA SAS', 'Paracetamol',
 'ACTIVE', 5.80, 13.40, '40 Tabletten', NULL),

('7680321760017', '32176', 'Brufen Filmtabl 400 mg',
 'M01AE01', 'Filmtablette', 'Abbott AG', 'Ibuprofen',
 'ACTIVE', 4.10, 9.80, '20 Tabletten', NULL),

('7680321760024', '32176', 'Brufen Filmtabl 600 mg',
 'M01AE01', 'Filmtablette', 'Abbott AG', 'Ibuprofen',
 'ACTIVE', 6.20, 14.50, '20 Tabletten', NULL),

-- Antibiotics (ATC: J01)
('7680421830021', '42183', 'Amoxicillin Sandoz Kaps 500 mg',
 'J01CA04', 'Kapsel', 'Sandoz Pharmaceuticals AG', 'Amoxicillin',
 'ACTIVE', 8.40, 19.60, '20 Kapseln', NULL),

('7680421830038', '42183', 'Amoxicillin Sandoz Kaps 1000 mg',
 'J01CA04', 'Kapsel', 'Sandoz Pharmaceuticals AG', 'Amoxicillin',
 'ACTIVE', 12.20, 28.40, '20 Kapseln', NULL),

-- Antihypertensives (ATC: C09)
('7680534120011', '53412', 'Valsartan Mepha Tabl 80 mg',
 'C09CA03', 'Tablette', 'Mepha Pharma AG', 'Valsartan',
 'ACTIVE', 14.80, 34.60, '28 Tabletten', NULL),

('7680534120028', '53412', 'Valsartan Mepha Tabl 160 mg',
 'C09CA03', 'Tablette', 'Mepha Pharma AG', 'Valsartan',
 'ACTIVE', 22.40, 52.30, '28 Tabletten', NULL),

-- Proton Pump Inhibitors (ATC: A02)
('7680603410015', '60341', 'Omeprazol Helvepharm Kaps 20 mg',
 'A02BC01', 'Kapsel', 'Helvepharm AG', 'Omeprazol',
 'ACTIVE', 9.60, 22.40, '28 Kapseln', NULL),

-- Statins (ATC: C10)
('7680487220019', '48722', 'Atorvastatin Spirig HC Tabl 20 mg',
 'C10AA05', 'Tablette', 'Spirig HealthCare AG', 'Atorvastatin',
 'ACTIVE', 18.20, 42.50, '30 Tabletten', NULL),

('7680487220026', '48722', 'Atorvastatin Spirig HC Tabl 40 mg',
 'C10AA05', 'Tablette', 'Spirig HealthCare AG', 'Atorvastatin',
 'ACTIVE', 26.80, 62.60, '30 Tabletten', NULL),

-- Narcotics (BetmG) — Category A
('7680312440033', '31244', 'Morphin HCl Streuli Inj 10 mg/ml',
 'N02AA01', 'Injektionslösung', 'Streuli Pharma AG', 'Morphin',
 'ACTIVE', 8.90, 20.80, '10 Ampullen 1ml', 'BetmG-A'),

('7680312440040', '31244', 'Morphin HCl Streuli Inj 20 mg/ml',
 'N02AA01', 'Injektionslösung', 'Streuli Pharma AG', 'Morphin',
 'ACTIVE', 15.20, 35.50, '10 Ampullen 1ml', 'BetmG-A'),

-- Insulin (ATC: A10)
('7680566730021', '56673', 'Humalog 100 E/ml Inj Lös',
 'A10AB04', 'Injektionslösung', 'Eli Lilly (Suisse) SA', 'Insulin lispro',
 'ACTIVE', 42.80, 99.90, '5 Pen 3ml', NULL),

-- PENDING — new registration
('7680712340001', '71234', 'Semaglutide Novo Test Inj 0.5 mg',
 'A10BJ06', 'Injektionslösung', 'Novo Nordisk Pharma AG', 'Semaglutid',
 'PENDING', 85.00, 198.50, '1 Pen 1.5ml', NULL),

-- SUSPENDED — under review
('7680445670012', '44567', 'Metformin Helvepharm Tabl 500 mg',
 'A10BA02', 'Tablette', 'Helvepharm AG', 'Metformin',
 'SUSPENDED', 3.80, 8.90, '100 Tabletten', NULL);

-- -----------------------------------------------------------------------------
-- Price Updates
-- Recent BAG price review cycle — March 2025
-- -----------------------------------------------------------------------------
INSERT INTO price_updates
    (gtin, previous_ex_factory_price_chf, new_ex_factory_price_chf,
     previous_public_price_chf, new_public_price_chf,
     effective_date_utc, change_reason, changed_by, approval_reference)
VALUES
-- BAG three-year review — Paracetamol
('7680500350178', 3.50, 3.20, 8.20, 7.50,
 '2025-03-01 00:00:00+00', 'BAG_REVIEW', 'BAG-Preisbehoerde', 'BAG-SL-2025-03'),

('7680500350185', 6.40, 5.80, 14.90, 13.40,
 '2025-03-01 00:00:00+00', 'BAG_REVIEW', 'BAG-Preisbehoerde', 'BAG-SL-2025-03'),

-- Generic market entry — Ibuprofen price reduction
('7680321760017', 5.20, 4.10, 12.10, 9.80,
 '2025-03-01 00:00:00+00', 'GENERIC_ENTRY', 'BAG-Preisbehoerde', 'BAG-SL-2025-03'),

-- Manufacturer price increase request — Atorvastatin
('7680487220019', 16.40, 18.20, 38.30, 42.50,
 '2025-03-01 00:00:00+00', 'MANUFACTURER_REQUEST', 'Spirig HealthCare AG', 'MR-2025-0047'),

('7680487220026', 24.10, 26.80, 56.30, 62.60,
 '2025-03-01 00:00:00+00', 'MANUFACTURER_REQUEST', 'Spirig HealthCare AG', 'MR-2025-0047'),

-- Large surge: Insulin price increase (>15% — will trigger surge detector)
('7680566730021', 36.20, 42.80, 84.50, 99.90,
 '2025-03-01 00:00:00+00', 'MANUFACTURER_REQUEST', 'Eli Lilly (Suisse) SA', 'MR-2025-0112'),

-- Morphin price update
('7680312440033', 9.40, 8.90, 21.90, 20.80,
 '2025-03-01 00:00:00+00', 'BAG_REVIEW', 'BAG-Preisbehoerde', 'BAG-SL-2025-03');

-- -----------------------------------------------------------------------------
-- Drug Alerts
-- Mix of severity classes, types, and products for demo variety
-- -----------------------------------------------------------------------------
INSERT INTO drug_alerts
    (gtin, alert_type, severity, headline, description,
     affected_lots, issued_by_utc, expires_utc, source_url)
VALUES
-- CLASS_I RECALL — Morphin (narcotic) — highest severity, will hit narcotics topic
('7680312440033',
 'RECALL', 'CLASS_I',
 'Chargenrückruf: Morphin HCl Streuli Inj 10 mg/ml — Kontamination festgestellt',
 'Swissmedic hat einen zwingenden Rückruf der nachfolgend aufgeführten Chargen von Morphin HCl Streuli Inj 10 mg/ml angeordnet. Mikrobiologische Untersuchungen haben eine potenzielle Kontamination mit gramnegative Bakterien festgestellt. Alle betroffenen Chargen sind unverzüglich aus dem Verkehr zu ziehen.',
 'CH-2024-0891,CH-2024-0892,CH-2024-0893',
 '2025-02-15 09:30:00+00', NULL,
 'https://www.swissmedic.ch/swissmedic/de/home/humanarzneimittel/marktueberwachung/qualitaetsmaengel-und-chargenrueckrufe/2025/morphin-streuli-recall.html'),

-- CLASS_I RECALL — Amoxicillin — broad recall
('7680421830021',
 'RECALL', 'CLASS_I',
 'Pflichtiger Rückruf: Amoxicillin Sandoz 500mg — fehlerhafte Deklaration',
 'Aufgrund einer fehlerhaften Deklaration des Wirkstoffgehalts auf der Verpackung wird ein Chargenrückruf für Amoxicillin Sandoz Kaps 500 mg durchgeführt. Der tatsächliche Wirkstoffgehalt liegt ausserhalb der zugelassenen Spezifikationen.',
 'SZ-2025-0114,SZ-2025-0115',
 '2025-02-20 14:00:00+00', NULL,
 'https://www.swissmedic.ch/swissmedic/de/home/humanarzneimittel/marktueberwachung/qualitaetsmaengel-und-chargenrueckrufe/2025/amoxicillin-sandoz-recall.html'),

-- CLASS_II — Ibuprofen shortage
('7680321760017',
 'SHORTAGE', 'CLASS_II',
 'Lieferengpass: Brufen Filmtabl 400 mg — vorübergehend nicht lieferbar',
 'Infolge eines Produktionsunterbruchs beim Hersteller kommt es zu einem vorübergehenden Lieferengpass bei Brufen Filmtabl 400 mg. Als Therapiealternative stehen andere Ibuprofen-haltige Präparate zur Verfügung.',
 '',
 '2025-02-25 10:00:00+00', '2025-05-31 23:59:59+00',
 'https://www.swissmedic.ch/swissmedic/de/home/humanarzneimittel/marktueberwachung/lieferengpaesse.html'),

-- CLASS_II RECALL — Morphin 20mg (second alert for same product — triggers frequency window)
('7680312440040',
 'RECALL', 'CLASS_II',
 'Chargenrückruf: Morphin HCl Streuli Inj 20 mg/ml — Stabilitätsproblem',
 'Stabilitätsuntersuchungen haben ergeben, dass einzelne Chargen von Morphin HCl Streuli Inj 20 mg/ml die Spezifikation für den Wirkstoffgehalt nach 18 Monaten nicht erfüllen. Als Vorsichtsmassnahme wird ein freiwilliger Rückruf durchgeführt.',
 'CH-2024-1201',
 '2025-02-15 11:00:00+00', NULL,
 'https://www.swissmedic.ch/swissmedic/de/home/humanarzneimittel/marktueberwachung/qualitaetsmaengel-und-chargenrueckrufe/2025/morphin-streuli-20mg-recall.html'),

-- ADVISORY — Valsartan safety warning
('7680534120011',
 'QUALITY_DEFECT', 'CLASS_III',
 'Qualitätsmangel: Valsartan Mepha 80mg — erhöhte Nitrosamin-Gehalte',
 'Analysen haben ergeben, dass einzelne Chargen von Valsartan Mepha Tabl 80 mg geringfügig erhöhte Nitrosamin-Gehalte aufweisen. Der festgestellte Wert überschreitet den Grenzwert leicht, stellt aber kein unmittelbares Gesundheitsrisiko dar.',
 'VM-2024-3301',
 '2025-01-10 08:00:00+00', NULL,
 'https://www.swissmedic.ch/swissmedic/de/home/humanarzneimittel/marktueberwachung/qualitaetsmaengel-und-chargenrueckrufe/2025/valsartan-mepha-nitrosamin.html'),

-- ADVISORY — Insulin import ban
('7680566730021',
 'IMPORT_BAN', 'ADVISORY',
 'Einfuhrverbot aufgehoben: Humalog 100 E/ml — neue Charge freigegeben',
 'Das vorübergehende Einfuhrverbot für Humalog 100 E/ml Injektionslösung wurde aufgehoben. Die neu importierten Chargen erfüllen alle Anforderungen der Swissmedic-Zulassung.',
 '',
 '2025-03-01 16:00:00+00', NULL,
 'https://www.swissmedic.ch/swissmedic/de/home/humanarzneimittel/marktueberwachung/einfuhrverbote.html');
