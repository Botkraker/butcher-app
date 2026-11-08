-- Run once in the Neon SQL editor as the project owner (app v0.2).
-- Adds the credit and purchase tables. Old tables do not change.
-- cash_moves: personal spending is a negative amount; reason holds the details.

CREATE TABLE IF NOT EXISTS credit_events (
  uuid uuid PRIMARY KEY, person text NOT NULL, amount double precision NOT NULL, kind text NOT NULL,
  sale_uuid uuid, device_time timestamptz NOT NULL,
  sent_device_time timestamptz, uploaded_at timestamptz NOT NULL DEFAULT now());

CREATE TABLE IF NOT EXISTS purchases (
  uuid uuid PRIMARY KEY, item text NOT NULL, kg double precision NOT NULL,
  price_per_kg double precision NOT NULL, cost double precision NOT NULL, paid double precision NOT NULL,
  device_time timestamptz NOT NULL,
  sent_device_time timestamptz, uploaded_at timestamptz NOT NULL DEFAULT now());

GRANT INSERT ON credit_events, purchases TO app_writer;
