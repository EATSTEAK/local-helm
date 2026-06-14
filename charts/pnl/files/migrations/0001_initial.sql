CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS venues (
  id text PRIMARY KEY,
  name text NOT NULL,
  kind text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS accounts (
  id text PRIMARY KEY,
  venue_id text REFERENCES venues(id),
  name text NOT NULL,
  kind text NOT NULL,
  base_currency text NOT NULL DEFAULT 'KRW',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS wallets (
  id text PRIMARY KEY,
  account_id text REFERENCES accounts(id),
  chain text NOT NULL,
  address text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (chain, address)
);

CREATE TABLE IF NOT EXISTS instruments (
  id text PRIMARY KEY,
  symbol text NOT NULL,
  name text,
  asset_class text NOT NULL,
  currency text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS raw_ingest_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source text NOT NULL,
  source_event_id text NOT NULL,
  payload jsonb NOT NULL,
  payload_sha256 text NOT NULL,
  parse_status text NOT NULL DEFAULT 'pending',
  error_message text,
  received_at timestamptz NOT NULL DEFAULT now(),
  replayed_from uuid REFERENCES raw_ingest_events(id),
  UNIQUE (source, source_event_id, payload_sha256)
);

CREATE TABLE IF NOT EXISTS transaction_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source text NOT NULL,
  source_event_id text NOT NULL,
  raw_ingest_event_id uuid REFERENCES raw_ingest_events(id),
  occurred_at timestamptz NOT NULL,
  account_id text NOT NULL REFERENCES accounts(id),
  instrument_id text REFERENCES instruments(id),
  kind text NOT NULL,
  amount numeric(38, 18) NOT NULL,
  currency text NOT NULL,
  quantity numeric(38, 18),
  price numeric(38, 18),
  fee_amount numeric(38, 18),
  fee_currency text,
  cash_flow_effect text NOT NULL,
  description text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (source, source_event_id, kind, account_id, occurred_at)
);

CREATE TABLE IF NOT EXISTS account_snapshots (
  id uuid DEFAULT gen_random_uuid(),
  captured_at timestamptz NOT NULL,
  account_id text NOT NULL REFERENCES accounts(id),
  source text NOT NULL,
  balance numeric(38, 18) NOT NULL,
  currency text NOT NULL,
  balance_krw numeric(38, 18),
  balance_usd numeric(38, 18),
  raw_ingest_event_id uuid REFERENCES raw_ingest_events(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (id, captured_at)
);

SELECT create_hypertable('account_snapshots', 'captured_at', if_not_exists => TRUE);

CREATE TABLE IF NOT EXISTS position_snapshots (
  id uuid DEFAULT gen_random_uuid(),
  captured_at timestamptz NOT NULL,
  account_id text NOT NULL REFERENCES accounts(id),
  venue_id text NOT NULL REFERENCES venues(id),
  instrument_id text NOT NULL REFERENCES instruments(id),
  source text NOT NULL,
  quantity numeric(38, 18) NOT NULL,
  market_value_krw numeric(38, 18),
  market_value_usd numeric(38, 18),
  unrealized_pnl_krw numeric(38, 18),
  raw_ingest_event_id uuid REFERENCES raw_ingest_events(id),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (id, captured_at)
);

SELECT create_hypertable('position_snapshots', 'captured_at', if_not_exists => TRUE);

CREATE TABLE IF NOT EXISTS price_points (
  id uuid DEFAULT gen_random_uuid(),
  captured_at timestamptz NOT NULL,
  instrument_id text NOT NULL REFERENCES instruments(id),
  price numeric(38, 18) NOT NULL,
  currency text NOT NULL,
  source text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (id, captured_at)
);

SELECT create_hypertable('price_points', 'captured_at', if_not_exists => TRUE);

CREATE TABLE IF NOT EXISTS fx_rates (
  id uuid DEFAULT gen_random_uuid(),
  captured_at timestamptz NOT NULL,
  base_currency text NOT NULL,
  quote_currency text NOT NULL,
  rate numeric(38, 18) NOT NULL,
  source text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (id, captured_at)
);

SELECT create_hypertable('fx_rates', 'captured_at', if_not_exists => TRUE);

CREATE TABLE IF NOT EXISTS sync_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  connector text NOT NULL,
  status text NOT NULL,
  started_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  cursor jsonb,
  error_message text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE OR REPLACE FUNCTION prevent_transaction_event_updates()
RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'transaction_events is append-only';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS transaction_events_append_only ON transaction_events;
CREATE TRIGGER transaction_events_append_only
BEFORE UPDATE OR DELETE ON transaction_events
FOR EACH ROW EXECUTE FUNCTION prevent_transaction_event_updates();

