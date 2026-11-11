-- Run once in the Neon SQL editor as the project owner (Flutter app, two-way sync).
-- Lets the app read rows back (new phone, reinstall, a second phone). Still no UPDATE and no DELETE:
-- rows can only be added, so nothing on Neon can be changed or erased by the app.
-- Note: the connection string is inside the app, so whoever extracts it from the APK can now read this data too.

GRANT SELECT ON product_events, supplier_events, sales, voids, carcasses, waste,
  closings, cash_moves, stock_counts, credit_events, purchases TO app_writer;

-- The app reads "what arrived since last time" by uploaded_at.
CREATE INDEX IF NOT EXISTS product_events_up ON product_events (uploaded_at);
CREATE INDEX IF NOT EXISTS supplier_events_up ON supplier_events (uploaded_at);
CREATE INDEX IF NOT EXISTS sales_up ON sales (uploaded_at);
CREATE INDEX IF NOT EXISTS voids_up ON voids (uploaded_at);
CREATE INDEX IF NOT EXISTS carcasses_up ON carcasses (uploaded_at);
CREATE INDEX IF NOT EXISTS waste_up ON waste (uploaded_at);
CREATE INDEX IF NOT EXISTS closings_up ON closings (uploaded_at);
CREATE INDEX IF NOT EXISTS cash_moves_up ON cash_moves (uploaded_at);
CREATE INDEX IF NOT EXISTS stock_counts_up ON stock_counts (uploaded_at);
CREATE INDEX IF NOT EXISTS credit_events_up ON credit_events (uploaded_at);
CREATE INDEX IF NOT EXISTS purchases_up ON purchases (uploaded_at);
