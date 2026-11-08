-- Run once in the Neon SQL editor as the project owner.
-- Every table is append-only. uploaded_at is set by the server.
-- sent_device_time is the phone clock at send time (separates clock error from offline delay).

CREATE TABLE IF NOT EXISTS product_events (
  uuid uuid PRIMARY KEY, product_uuid uuid NOT NULL, name text NOT NULL, kind text NOT NULL,
  price_per_kg double precision, device_time timestamptz NOT NULL,
  sent_device_time timestamptz, uploaded_at timestamptz NOT NULL DEFAULT now());

CREATE TABLE IF NOT EXISTS supplier_events (
  uuid uuid PRIMARY KEY, supplier_uuid uuid NOT NULL, name text NOT NULL, kind text NOT NULL,
  device_time timestamptz NOT NULL,
  sent_device_time timestamptz, uploaded_at timestamptz NOT NULL DEFAULT now());

CREATE TABLE IF NOT EXISTS sales (
  uuid uuid PRIMARY KEY, product_uuid uuid NOT NULL, total double precision NOT NULL,
  price_per_kg double precision NOT NULL, kg double precision NOT NULL, kind text NOT NULL,
  credit boolean NOT NULL, device_time timestamptz NOT NULL,
  sent_device_time timestamptz, uploaded_at timestamptz NOT NULL DEFAULT now());

CREATE TABLE IF NOT EXISTS voids (
  uuid uuid PRIMARY KEY, target_table text NOT NULL, target_uuid uuid NOT NULL,
  device_time timestamptz NOT NULL,
  sent_device_time timestamptz, uploaded_at timestamptz NOT NULL DEFAULT now());

CREATE TABLE IF NOT EXISTS carcasses (
  uuid uuid PRIMARY KEY, supplier_uuid uuid, kg_bought double precision NOT NULL,
  cost double precision NOT NULL, device_time timestamptz NOT NULL,
  sent_device_time timestamptz, uploaded_at timestamptz NOT NULL DEFAULT now());

CREATE TABLE IF NOT EXISTS waste (
  uuid uuid PRIMARY KEY, carcass_uuid uuid NOT NULL, kg double precision NOT NULL,
  device_time timestamptz NOT NULL,
  sent_device_time timestamptz, uploaded_at timestamptz NOT NULL DEFAULT now());

CREATE TABLE IF NOT EXISTS closings (
  uuid uuid PRIMARY KEY, cash_counted double precision NOT NULL, device_time timestamptz NOT NULL,
  sent_device_time timestamptz, uploaded_at timestamptz NOT NULL DEFAULT now());

CREATE TABLE IF NOT EXISTS cash_moves (
  uuid uuid PRIMARY KEY, amount double precision NOT NULL, reason text NOT NULL,
  device_time timestamptz NOT NULL,
  sent_device_time timestamptz, uploaded_at timestamptz NOT NULL DEFAULT now());

CREATE TABLE IF NOT EXISTS stock_counts (
  uuid uuid PRIMARY KEY, product_uuid uuid NOT NULL, kg double precision NOT NULL,
  device_time timestamptz NOT NULL,
  sent_device_time timestamptz, uploaded_at timestamptz NOT NULL DEFAULT now());

-- v2 (also in neon_migration_002.sql)
CREATE TABLE IF NOT EXISTS credit_events (
  uuid uuid PRIMARY KEY, person text NOT NULL, amount double precision NOT NULL, kind text NOT NULL,
  sale_uuid uuid, device_time timestamptz NOT NULL,
  sent_device_time timestamptz, uploaded_at timestamptz NOT NULL DEFAULT now());

CREATE TABLE IF NOT EXISTS purchases (
  uuid uuid PRIMARY KEY, item text NOT NULL, kg double precision NOT NULL,
  price_per_kg double precision NOT NULL, cost double precision NOT NULL, paid double precision NOT NULL,
  device_time timestamptz NOT NULL,
  sent_device_time timestamptz, uploaded_at timestamptz NOT NULL DEFAULT now());

-- Debug button only. Not part of the analysis.
CREATE TABLE IF NOT EXISTS debug_pings (
  uuid uuid PRIMARY KEY, note text NOT NULL, device_time timestamptz NOT NULL,
  sent_device_time timestamptz, uploaded_at timestamptz NOT NULL DEFAULT now());

-- Insert-only role used by the app. Replace the password before you run this.
CREATE ROLE app_writer LOGIN PASSWORD 'CHANGE_ME';
GRANT USAGE ON SCHEMA public TO app_writer;
GRANT INSERT ON product_events, supplier_events, sales, voids, carcasses, waste,
  closings, cash_moves, stock_counts, debug_pings, credit_events, purchases TO app_writer;
-- No SELECT, UPDATE, DELETE. Bare "ON CONFLICT DO NOTHING" needs only INSERT.
