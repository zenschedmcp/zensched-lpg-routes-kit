-- ZenSched LPG Cylinder-Route Local Database Schema
-- SQLite database for customers, delivery stops (places), daily/weekly
-- cadence, cylinder in/out summaries, cash vs account, and billing.
-- Amounts in this file are LOCAL CURRENCY (settings.currency_code).
-- ZenSched meters are always USD and are never stored here.
-- DO NOT duplicate live schedule data from ZenSched (shifts, punches, timesheets).
--
-- HOW TO LOAD THIS FILE
--   Normal path: paste this whole file into your AI chat and say
--   "Create these tables in my lpg-ops database. Run each statement one at a time."
--   The AI runs each statement through the SQLite MCP tool (sqlite_execute).
--   Most SQLite MCP tools accept ONE statement per call, so every statement
--   below ends with a semicolon and stands alone.
--
--   Alternative (if you have the sqlite3 command-line tool):
--     sqlite3 lpg-ops.db < schema.sql
--
-- Every statement is idempotent (IF NOT EXISTS / INSERT OR IGNORE), so it is
-- safe to run this file again on an existing database.
--
-- NOT A TAX INVOICE, NOT CYLINDER TRACEABILITY, AND NOT THE OFFICIAL
-- PERTAMINA MAP / INDANE / CRE / DOE BOOK. cash_log / cylinder_log are the
-- owner's local extract of what the driver typed on the Stop Record
-- (date, stop, fulls in, empties out, paid). They are not an e-Faktur, CFDI,
-- factura, GST invoice, a subsidized-cylinder serial log, Pertamina MAP /
-- MyPertamina subsidy recording, an Indane / Bharatgas / HP Gas portal,
-- CRE volumetric / CFDI, a DOE LTO / RA 11592 registry, or a MITECO price
-- filing. GPS proves the driver was at the door, not that a numbered
-- bottle changed hands.
--
-- PRIVACY: customer names, phones, stops.access_notes (gate, dog,
-- "call first") and customers.deposit_notes (outstanding cylinder deposits)
-- live ONLY in this file on your computer. They are never sent to ZenSched.
-- stops.stop_label is stop code + street (S-1 · Jl. Kemang Raya 12) — the
-- only name sent to ZenSched. SKILL.md forbids the agent from putting
-- names, phones, or notes in any ZenSched field.
--
-- CUSTOMERS → STOPS (places) → VISITS. Cadence lives on the stop so one
-- account can have a daily warung and a weekly house. Daily stops expand
-- to one row per remaining day in the next 7 via date_offsets.

-- Foreign keys are OFF by default in SQLite. This must be run once per
-- connection for ON DELETE CASCADE to work. SKILL.md tells the agent to run it
-- at the start of each session.
PRAGMA foreign_keys = ON;

-- Settings: small key/value store so the agent does not have to be re-told the
-- basics every session (timezone, currency, default driver, form id).
-- default_checkin_radius_m is informational: the radius ZenSched enforces is
-- the account POLICY's, set with policy_update(0, {"checkin_radius_m": N}).
-- currency_code / currency_symbol are LOCAL (IDR, MXN, EUR, PHP, INR, ...).
-- Never send them to ZenSched; meters there are always USD.
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT
);

INSERT OR IGNORE INTO settings (key, value) VALUES ('business_name', 'My LPG Route');
INSERT OR IGNORE INTO settings (key, value) VALUES ('timezone_offset', '+07:00');
INSERT OR IGNORE INTO settings (key, value) VALUES ('currency_code', 'IDR');
INSERT OR IGNORE INTO settings (key, value) VALUES ('currency_symbol', 'Rp');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_worker_id', NULL);
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_shift_start', '07:00');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_shift_minutes', '12');
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_due_days', '7');
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_prefix', 'INV');
INSERT OR IGNORE INTO settings (key, value) VALUES ('stop_record_form_id', NULL);
INSERT OR IGNORE INTO settings (key, value) VALUES ('event_window_days', '60');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_checkin_radius_m', '75');

-- Helper spine: 0..6 so daily stops expand to one due-row per remaining
-- day in the next week. Not a business table; do not edit.
CREATE TABLE IF NOT EXISTS date_offsets (
  offset_days INTEGER PRIMARY KEY
    CHECK (offset_days >= 0 AND offset_days <= 6)
);

INSERT OR IGNORE INTO date_offsets (offset_days) VALUES (0);
INSERT OR IGNORE INTO date_offsets (offset_days) VALUES (1);
INSERT OR IGNORE INTO date_offsets (offset_days) VALUES (2);
INSERT OR IGNORE INTO date_offsets (offset_days) VALUES (3);
INSERT OR IGNORE INTO date_offsets (offset_days) VALUES (4);
INSERT OR IGNORE INTO date_offsets (offset_days) VALUES (5);
INSERT OR IGNORE INTO date_offsets (offset_days) VALUES (6);

-- Cylinder types: your price list in LOCAL currency per full cylinder.
-- Seeded with common sizes; edit prices and add rows for your market
-- (MX 20/30 kg, ES 12.5 kg, PH 11 kg, IN 14.2/19 kg).
CREATE TABLE IF NOT EXISTS cylinder_types (
  type_id INTEGER PRIMARY KEY AUTOINCREMENT,
  code TEXT NOT NULL UNIQUE,                        -- short handle: '3kg'
  type_name TEXT NOT NULL,                          -- shown on invoices
  default_minutes INTEGER NOT NULL,                 -- shift length on ZenSched
  unit_price REAL NOT NULL,                         -- local currency per full cylinder
  is_active INTEGER DEFAULT 1,
  notes TEXT
);

INSERT OR IGNORE INTO cylinder_types (code, type_name, default_minutes, unit_price) VALUES ('3kg', '3 kg cylinder', 10, 20000);
INSERT OR IGNORE INTO cylinder_types (code, type_name, default_minutes, unit_price) VALUES ('12kg', '12 kg cylinder', 12, 185000);
INSERT OR IGNORE INTO cylinder_types (code, type_name, default_minutes, unit_price) VALUES ('15kg', '15 kg cylinder', 12, 220000);
INSERT OR IGNORE INTO cylinder_types (code, type_name, default_minutes, unit_price) VALUES ('45kg', '45 kg cylinder', 20, 550000);

-- Customers: the account (household, warung, restaurant). Deposit notes
-- are LOCAL ONLY. Cadence and the pin live on the stop, not here.
CREATE TABLE IF NOT EXISTS customers (
  customer_id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_name TEXT NOT NULL,
  contact_email TEXT,
  contact_phone TEXT,
  billing_notes TEXT,                               -- 'pays cash at the door', 'invoice weekly'
  deposit_notes TEXT,                               -- LOCAL ONLY: outstanding cylinder deposits
  is_active INTEGER DEFAULT 1,                      -- 0 = paused / cancelled
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Stops: delivery places. One ZenSched LOCATION per stop, created once
-- and kept forever. One ZenSched EVENT per stop per rolling window of
-- at most 60 days (ZenSched caps event length). zensched_event_id is the
-- CURRENT event and event_valid_until is its last valid date.
-- Cadence is daily | weekly | on-demand. Daily stops expand in stops_due.
CREATE TABLE IF NOT EXISTS stops (
  stop_id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER NOT NULL,
  stop_label TEXT NOT NULL,                         -- 'S-1 · Jl. Kemang Raya 12' — stop code + street; never the customer name; the only name sent to ZenSched
  address TEXT NOT NULL,
  address_line2 TEXT,
  city TEXT,
  state TEXT,
  zip TEXT,
  country TEXT,
  access_notes TEXT,                                -- LOCAL ONLY: gate, dog, call-first, alley
  route_label TEXT,                                 -- 'North loop', 'Kemang'
  stop_order INTEGER DEFAULT 1
    CHECK (stop_order IS NULL OR stop_order >= 1),
  cylinder_type_id INTEGER,                         -- default size for this stop
  unit_price REAL NOT NULL,                         -- local currency per full; may differ from the list
  service_frequency TEXT NOT NULL
    CHECK (service_frequency IN ('daily', 'weekly', 'on-demand')),
  next_service_date TEXT,                           -- ISO date: '2026-09-07'
  last_service_date TEXT,
  preferred_start TEXT                              -- 'HH:MM' 24-hour local; NULL = settings.default_shift_start
    CHECK (preferred_start IS NULL OR preferred_start GLOB '[0-2][0-9]:[0-5][0-9]'),
  float_cylinders INTEGER DEFAULT 0,                -- net fulls left at the stop (trigger updates)
  zensched_worker_id INTEGER,                       -- pin this stop to a driver; NULL = default
  zensched_location_id INTEGER,                     -- from location_create (permanent)
  zensched_event_id INTEGER,                        -- from event_create (current <=60-day window)
  event_valid_until TEXT,                           -- ISO date: last day the current event covers
  is_active INTEGER DEFAULT 1,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE CASCADE,
  FOREIGN KEY (cylinder_type_id) REFERENCES cylinder_types(type_id)
);

-- Drivers: your roster. zensched_worker_id comes from worker_invite.
CREATE TABLE IF NOT EXISTS drivers (
  driver_id INTEGER PRIMARY KEY AUTOINCREMENT,
  driver_name TEXT NOT NULL,
  email TEXT,
  phone TEXT,
  zensched_worker_id INTEGER UNIQUE,                -- from worker_invite
  is_active INTEGER DEFAULT 1,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Visits: one row per COMPLETED stop, linked to the ZenSched shift and
-- the Stop Record form submission. Amounts are LOCAL currency.
-- paid_status is CHECK-constrained to the form's option labels.
CREATE TABLE IF NOT EXISTS visits (
  visit_id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER NOT NULL,
  stop_id INTEGER NOT NULL,
  driver_id INTEGER,                                -- local roster row (trigger fills from worker id)
  completed_date TEXT NOT NULL,                     -- ISO date: '2026-09-07'
  amount REAL,                                      -- local currency; trigger fills delivered * unit_price if NULL
  cylinders_delivered INTEGER
    CHECK (cylinders_delivered IS NULL OR cylinders_delivered >= 0),
  empties_collected INTEGER
    CHECK (empties_collected IS NULL OR empties_collected >= 0),
  paid_status TEXT CHECK (paid_status IS NULL OR paid_status IN ('Cash', 'Account', 'Unpaid')),
  zensched_shift_id INTEGER UNIQUE,                 -- prevents recording the same shift twice
  zensched_event_id INTEGER,
  zensched_worker_id INTEGER,
  actual_in TEXT,
  actual_out TEXT,
  duration_minutes INTEGER,
  gps_verified INTEGER,                             -- 1 if the check-in punch was on site
  report_dc_id INTEGER,                             -- Stop Record submission_id
  photo_urls TEXT,                                  -- JSON array of receipt-photo URLs
  notes TEXT,
  invoiced INTEGER DEFAULT 0,                       -- 1 = included in an invoice
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE CASCADE,
  FOREIGN KEY (stop_id) REFERENCES stops(stop_id) ON DELETE CASCADE,
  FOREIGN KEY (driver_id) REFERENCES drivers(driver_id) ON DELETE SET NULL
);

-- Invoices: billing records in LOCAL currency (Account / Unpaid visits).
-- Cash collections are not invoice lines — they live in cash_log.
-- invoice_number is filled in automatically by a trigger if left NULL.
CREATE TABLE IF NOT EXISTS invoices (
  invoice_id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER NOT NULL,
  invoice_number TEXT UNIQUE,                       -- human-readable: 'INV-2026-0001'
  invoice_date TEXT NOT NULL,
  due_date TEXT,
  total_amount REAL NOT NULL,                       -- local currency
  paid INTEGER DEFAULT 0,
  paid_date TEXT,
  sent_date TEXT,
  line_items TEXT,                                  -- JSON array of visit references
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE CASCADE
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_stops_next_service ON stops(next_service_date, is_active);
CREATE INDEX IF NOT EXISTS idx_stops_customer ON stops(customer_id);
CREATE INDEX IF NOT EXISTS idx_stops_route ON stops(route_label, stop_order);
CREATE INDEX IF NOT EXISTS idx_stops_zensched_location ON stops(zensched_location_id);
CREATE INDEX IF NOT EXISTS idx_stops_zensched_event ON stops(zensched_event_id);
CREATE INDEX IF NOT EXISTS idx_drivers_worker ON drivers(zensched_worker_id);
CREATE INDEX IF NOT EXISTS idx_visits_customer ON visits(customer_id, completed_date);
CREATE INDEX IF NOT EXISTS idx_visits_stop ON visits(stop_id, completed_date);
CREATE INDEX IF NOT EXISTS idx_visits_paid ON visits(paid_status);
CREATE INDEX IF NOT EXISTS idx_visits_invoiced ON visits(invoiced);
CREATE INDEX IF NOT EXISTS idx_invoices_customer ON invoices(customer_id);
CREATE INDEX IF NOT EXISTS idx_invoices_paid ON invoices(paid);

-- Keep updated_at current
CREATE TRIGGER IF NOT EXISTS update_customer_timestamp
AFTER UPDATE ON customers
BEGIN
  UPDATE customers SET updated_at = datetime('now') WHERE customer_id = NEW.customer_id;
END;

CREATE TRIGGER IF NOT EXISTS update_stop_timestamp
AFTER UPDATE ON stops
BEGIN
  UPDATE stops SET updated_at = datetime('now') WHERE stop_id = NEW.stop_id;
END;

CREATE TRIGGER IF NOT EXISTS update_driver_timestamp
AFTER UPDATE ON drivers
BEGIN
  UPDATE drivers SET updated_at = datetime('now') WHERE driver_id = NEW.driver_id;
END;

-- Fill driver_id from the roster when the agent only has the ZenSched worker id.
CREATE TRIGGER IF NOT EXISTS fill_visit_driver
AFTER INSERT ON visits
WHEN NEW.driver_id IS NULL AND NEW.zensched_worker_id IS NOT NULL
BEGIN
  UPDATE visits
  SET driver_id = (SELECT driver_id FROM drivers WHERE zensched_worker_id = NEW.zensched_worker_id)
  WHERE visit_id = NEW.visit_id;
END;

-- Fill duration_minutes from punches when the agent leaves it NULL.
CREATE TRIGGER IF NOT EXISTS fill_visit_duration_insert
AFTER INSERT ON visits
WHEN NEW.duration_minutes IS NULL AND NEW.actual_in IS NOT NULL AND NEW.actual_out IS NOT NULL
BEGIN
  UPDATE visits
  SET duration_minutes = CAST(round((julianday(NEW.actual_out) - julianday(NEW.actual_in)) * 1440) AS INTEGER)
  WHERE visit_id = NEW.visit_id;
END;

CREATE TRIGGER IF NOT EXISTS fill_visit_duration_update
AFTER UPDATE OF actual_in, actual_out ON visits
WHEN NEW.duration_minutes IS NULL AND NEW.actual_in IS NOT NULL AND NEW.actual_out IS NOT NULL
BEGIN
  UPDATE visits
  SET duration_minutes = CAST(round((julianday(NEW.actual_out) - julianday(NEW.actual_in)) * 1440) AS INTEGER)
  WHERE visit_id = NEW.visit_id;
END;

-- Fill amount as delivered * the stop's unit_price (local currency) when
-- the agent leaves it NULL. An explicit 0 is kept.
CREATE TRIGGER IF NOT EXISTS fill_visit_amount
AFTER INSERT ON visits
WHEN NEW.amount IS NULL
BEGIN
  UPDATE visits
  SET amount = COALESCE(NEW.cylinders_delivered, 0) *
               COALESCE((SELECT unit_price FROM stops WHERE stop_id = NEW.stop_id), 0)
  WHERE visit_id = NEW.visit_id;
END;

-- Net cylinders left at the stop: float += delivered − empties.
CREATE TRIGGER IF NOT EXISTS update_float_on_visit
AFTER INSERT ON visits
BEGIN
  UPDATE stops
  SET float_cylinders = COALESCE(float_cylinders, 0)
                      + COALESCE(NEW.cylinders_delivered, 0)
                      - COALESCE(NEW.empties_collected, 0)
  WHERE stop_id = NEW.stop_id;
END;

-- Recording a completed visit automatically advances that stop's cadence.
-- daily +1 day, weekly +7 days, on-demand clears the next date.
-- The agent should NOT hand-maintain next_service_date after this.
-- A one-off recorded on a recurring stop also moves the cadence; if the
-- owner wants the regular stop kept, set next_service_date back explicitly.
CREATE TRIGGER IF NOT EXISTS advance_service_date_on_visit
AFTER INSERT ON visits
BEGIN
  UPDATE stops
  SET last_service_date = NEW.completed_date,
      next_service_date = CASE service_frequency
        WHEN 'daily'  THEN date(NEW.completed_date, '+1 day')
        WHEN 'weekly' THEN date(NEW.completed_date, '+7 days')
        ELSE NULL                                    -- on-demand: no automatic next visit
      END
  WHERE stop_id = NEW.stop_id;
END;

-- Auto-number invoices: INV-2026-0001, INV-2026-0002, ...
CREATE TRIGGER IF NOT EXISTS number_invoice
AFTER INSERT ON invoices
WHEN NEW.invoice_number IS NULL
BEGIN
  UPDATE invoices
  SET invoice_number = (SELECT COALESCE(value, 'INV') FROM settings WHERE key = 'invoice_prefix')
                       || '-' || strftime('%Y', NEW.invoice_date)
                       || '-' || printf('%04d', NEW.invoice_id)
  WHERE invoice_id = NEW.invoice_id;
END;

-- Who is due in the next 7 days. Daily stops expand to one row per
-- remaining day (today .. today+6) on or after next_service_date.
-- Weekly / on-demand emit a single row on next_service_date.
-- One row = one shift_create. start_iso / end_iso / idempotency_key
-- are ready to pass through. event_needs_roll = 1 means create a new
-- ZenSched event first (see SKILL.md). access_notes is included so the
-- agent can tell the owner to pass it to the driver; it must never go
-- into a ZenSched field. Uses date('now','localtime') so "today" is
-- the owner's machine, not UTC.
CREATE VIEW IF NOT EXISTS stops_due AS
SELECT
  s.stop_id,
  s.stop_label,
  s.address,
  s.city,
  s.state,
  s.zip,
  s.country,
  s.access_notes,
  s.route_label,
  s.stop_order,
  s.unit_price,
  s.service_frequency,
  s.next_service_date,
  s.float_cylinders,
  s.zensched_location_id,
  s.zensched_event_id,
  s.event_valid_until,
  CASE
    WHEN s.service_frequency = 'daily'
      THEN date('now', 'localtime', '+' || o.offset_days || ' days')
    ELSE s.next_service_date
  END AS visit_date,
  CASE WHEN s.event_valid_until IS NULL
            OR s.event_valid_until < CASE
              WHEN s.service_frequency = 'daily'
                THEN date('now', 'localtime', '+' || o.offset_days || ' days')
              ELSE s.next_service_date
            END
       THEN 1 ELSE 0 END AS event_needs_roll,
  COALESCE(s.preferred_start, (SELECT value FROM settings WHERE key = 'default_shift_start')) AS start_time,
  COALESCE(ct.default_minutes, CAST((SELECT value FROM settings WHERE key = 'default_shift_minutes') AS INTEGER)) AS default_minutes,
  ct.type_id AS cylinder_type_id,
  ct.code AS cylinder_code,
  ct.type_name AS cylinder_name,
  c.customer_id,
  c.customer_name,
  c.contact_phone,
  c.billing_notes,
  COALESCE(s.zensched_worker_id, (SELECT CAST(value AS INTEGER) FROM settings WHERE key = 'default_worker_id')) AS worker_id,
  (SELECT d.driver_name FROM drivers d
    WHERE d.zensched_worker_id = COALESCE(s.zensched_worker_id,
           (SELECT CAST(value AS INTEGER) FROM settings WHERE key = 'default_worker_id'))) AS driver_name,
  CASE
    WHEN s.service_frequency = 'daily'
      THEN date('now', 'localtime', '+' || o.offset_days || ' days')
    ELSE s.next_service_date
  END || 'T'
    || COALESCE(s.preferred_start, (SELECT value FROM settings WHERE key = 'default_shift_start'))
    || ':00' || (SELECT value FROM settings WHERE key = 'timezone_offset') AS start_iso,
  strftime('%Y-%m-%dT%H:%M:%S', datetime(
      CASE
        WHEN s.service_frequency = 'daily'
          THEN date('now', 'localtime', '+' || o.offset_days || ' days')
        ELSE s.next_service_date
      END || ' '
      || COALESCE(s.preferred_start, (SELECT value FROM settings WHERE key = 'default_shift_start'))
      || ':00',
      '+' || COALESCE(ct.default_minutes, CAST((SELECT value FROM settings WHERE key = 'default_shift_minutes') AS INTEGER)) || ' minutes'))
    || (SELECT value FROM settings WHERE key = 'timezone_offset') AS end_iso,
  'shift-stop-' || s.stop_id || '-' || strftime('%Y%m%d',
    CASE
      WHEN s.service_frequency = 'daily'
        THEN date('now', 'localtime', '+' || o.offset_days || ' days')
      ELSE s.next_service_date
    END) AS idempotency_key
FROM stops s
JOIN customers c ON c.customer_id = s.customer_id AND c.is_active = 1
LEFT JOIN cylinder_types ct ON ct.type_id = s.cylinder_type_id
LEFT JOIN date_offsets o ON s.service_frequency = 'daily'
WHERE s.is_active = 1
  AND (
    (s.service_frequency = 'daily'
     AND date('now', 'localtime', '+' || o.offset_days || ' days')
         >= COALESCE(s.next_service_date, date('now', 'localtime'))
     AND date('now', 'localtime', '+' || o.offset_days || ' days')
         <= date('now', 'localtime', '+6 days'))
    OR
    (s.service_frequency IN ('weekly', 'on-demand')
     AND s.next_service_date IS NOT NULL
     AND s.next_service_date <= date('now', 'localtime', '+7 days'))
  )
ORDER BY visit_date,
         COALESCE(s.route_label, ''),
         COALESCE(s.stop_order, 1),
         COALESCE(s.preferred_start, (SELECT value FROM settings WHERE key = 'default_shift_start')),
         s.stop_label;

-- Stops whose current ZenSched event expires within 14 days (or has none)
-- and that belong to an active customer. Roll these proactively.
CREATE VIEW IF NOT EXISTS events_expiring AS
SELECT
  s.stop_id,
  s.stop_label,
  s.address,
  c.customer_name,
  s.zensched_location_id,
  s.zensched_event_id,
  s.event_valid_until
FROM stops s
JOIN customers c ON c.customer_id = s.customer_id AND c.is_active = 1
WHERE s.is_active = 1
  AND (s.event_valid_until IS NULL OR s.event_valid_until <= date('now', 'localtime', '+14 days'))
ORDER BY s.event_valid_until;

-- Active stops in route order, with next date and float.
CREATE VIEW IF NOT EXISTS route_board AS
SELECT
  s.route_label,
  s.stop_order,
  s.stop_id,
  s.stop_label,
  s.address,
  s.city,
  s.service_frequency,
  s.next_service_date,
  s.unit_price,
  s.float_cylinders,
  s.zensched_location_id,
  s.zensched_event_id,
  s.event_valid_until,
  c.customer_id,
  c.customer_name,
  ct.code AS cylinder_code,
  COALESCE(s.zensched_worker_id, (SELECT CAST(value AS INTEGER) FROM settings WHERE key = 'default_worker_id')) AS worker_id,
  (SELECT d.driver_name FROM drivers d
    WHERE d.zensched_worker_id = COALESCE(s.zensched_worker_id,
           (SELECT CAST(value AS INTEGER) FROM settings WHERE key = 'default_worker_id'))) AS driver_name
FROM stops s
JOIN customers c ON c.customer_id = s.customer_id AND c.is_active = 1
LEFT JOIN cylinder_types ct ON ct.type_id = s.cylinder_type_id
WHERE s.is_active = 1
ORDER BY COALESCE(s.route_label, ''), COALESCE(s.stop_order, 1), s.stop_label;

-- Account / Unpaid visits not yet invoiced. Cash is omitted (already collected).
CREATE VIEW IF NOT EXISTS visits_to_invoice AS
SELECT
  c.customer_id,
  c.customer_name,
  c.contact_email,
  c.contact_phone,
  c.billing_notes,
  COUNT(v.visit_id)       AS visit_count,
  SUM(v.amount)           AS total_amount,
  MIN(v.completed_date)   AS first_visit_date,
  MAX(v.completed_date)   AS last_visit_date
FROM visits v
JOIN customers c ON c.customer_id = v.customer_id
WHERE v.invoiced = 0
  AND v.paid_status IN ('Account', 'Unpaid')
  AND COALESCE(v.amount, 0) > 0
GROUP BY c.customer_id
ORDER BY c.customer_name;

-- Unpaid invoices, oldest first, with aging buckets. Amounts are local.
CREATE VIEW IF NOT EXISTS invoices_outstanding AS
SELECT
  i.invoice_id,
  i.invoice_number,
  c.customer_name,
  c.contact_email,
  c.contact_phone,
  i.invoice_date,
  i.due_date,
  i.total_amount,
  i.sent_date,
  CASE WHEN i.due_date < date('now', 'localtime') THEN 1 ELSE 0 END AS overdue,
  CASE WHEN i.due_date >= date('now', 'localtime') THEN 0
       ELSE CAST(julianday(date('now', 'localtime')) - julianday(i.due_date) AS INTEGER) END AS days_overdue,
  CASE WHEN i.due_date >= date('now', 'localtime') THEN 'current'
       WHEN julianday(date('now', 'localtime')) - julianday(i.due_date) <= 30 THEN '1-30'
       WHEN julianday(date('now', 'localtime')) - julianday(i.due_date) <= 60 THEN '31-60'
       WHEN julianday(date('now', 'localtime')) - julianday(i.due_date) <= 90 THEN '61-90'
       ELSE '90+' END AS aging_bucket
FROM invoices i
JOIN customers c ON c.customer_id = i.customer_id
WHERE i.paid = 0
ORDER BY i.due_date;

-- Owner's local cash extract: door collections. Not a tax receipt.
CREATE VIEW IF NOT EXISTS cash_log AS
SELECT
  v.visit_id,
  v.completed_date,
  s.stop_label,
  s.address,
  c.customer_name,
  v.cylinders_delivered,
  v.empties_collected,
  v.amount,
  COALESCE(d.driver_name, 'driver ' || v.zensched_worker_id) AS driver,
  v.zensched_shift_id,
  v.report_dc_id
FROM visits v
JOIN stops s ON s.stop_id = v.stop_id
JOIN customers c ON c.customer_id = v.customer_id
LEFT JOIN drivers d ON d.driver_id = v.driver_id
WHERE v.paid_status = 'Cash'
ORDER BY v.completed_date DESC, c.customer_name;

-- Stops the driver marked Unpaid. Lead with these after "record today's route".
CREATE VIEW IF NOT EXISTS unpaid_flags AS
SELECT
  v.visit_id,
  v.completed_date,
  s.stop_label,
  s.address,
  c.customer_name,
  c.contact_phone,
  v.cylinders_delivered,
  v.empties_collected,
  v.amount,
  v.paid_status,
  COALESCE(d.driver_name, 'driver ' || v.zensched_worker_id) AS driver,
  v.zensched_shift_id
FROM visits v
JOIN stops s ON s.stop_id = v.stop_id
JOIN customers c ON c.customer_id = v.customer_id
LEFT JOIN drivers d ON d.driver_id = v.driver_id
WHERE v.paid_status = 'Unpaid'
ORDER BY v.completed_date DESC, c.customer_name;

-- Owner's local cylinder extract: every recorded stop (in and out).
-- Not a serial / subsidized-bottle log.
CREATE VIEW IF NOT EXISTS cylinder_log AS
SELECT
  v.visit_id,
  v.completed_date,
  s.stop_label,
  s.address,
  s.city,
  c.customer_name,
  ct.code AS cylinder_code,
  v.cylinders_delivered,
  v.empties_collected,
  (COALESCE(v.cylinders_delivered, 0) - COALESCE(v.empties_collected, 0)) AS net_cylinders,
  s.float_cylinders,
  v.paid_status,
  v.amount,
  COALESCE(d.driver_name, 'driver ' || v.zensched_worker_id) AS driver,
  v.zensched_shift_id,
  v.report_dc_id
FROM visits v
JOIN stops s ON s.stop_id = v.stop_id
JOIN customers c ON c.customer_id = v.customer_id
LEFT JOIN cylinder_types ct ON ct.type_id = s.cylinder_type_id
LEFT JOIN drivers d ON d.driver_id = v.driver_id
ORDER BY v.completed_date DESC, c.customer_name;

-- Stops whose running float is not zero (extras left, or more empties
-- collected than delivered — a deposit movement).
CREATE VIEW IF NOT EXISTS float_watch AS
SELECT
  s.stop_id,
  s.stop_label,
  s.address,
  c.customer_name,
  c.deposit_notes,
  s.float_cylinders,
  s.service_frequency,
  s.next_service_date,
  ct.code AS cylinder_code
FROM stops s
JOIN customers c ON c.customer_id = s.customer_id AND c.is_active = 1
LEFT JOIN cylinder_types ct ON ct.type_id = s.cylinder_type_id
WHERE s.is_active = 1
  AND COALESCE(s.float_cylinders, 0) <> 0
ORDER BY s.float_cylinders, c.customer_name;
