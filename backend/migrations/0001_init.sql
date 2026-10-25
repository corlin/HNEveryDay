-- HNEveryDay backend schema v1. See docs/PRO_PAYWALL_AND_BACKEND_SPEC.md §6.
-- Migrations only ever add; never drop columns that a deployed Worker may still read.

-- Hot window: stories requested or prewarmed within the last 30 days.
-- The authoritative source is the HN API, so this table can be rebuilt at any time.
CREATE TABLE stories (
  id INTEGER PRIMARY KEY,
  title TEXT NOT NULL,
  url TEXT,
  by TEXT,
  score INTEGER NOT NULL DEFAULT 0,
  descendants INTEGER NOT NULL DEFAULT 0,
  time INTEGER NOT NULL,
  fetched_at INTEGER NOT NULL
);
CREATE INDEX idx_stories_time ON stories(time);

-- AI outputs are kept long-term and only become stale when the prompt version or model changes.
CREATE TABLE ai_outputs (
  story_id INTEGER NOT NULL,
  kind TEXT NOT NULL,              -- 'title' | 'summary' | 'questions'
  lang TEXT NOT NULL,
  prompt_version INTEGER NOT NULL,
  model TEXT NOT NULL,
  content TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (story_id, kind, lang, prompt_version, model)
);
CREATE INDEX idx_ai_outputs_created ON ai_outputs(created_at);

-- Minimal archive of stories that left the hot window.
CREATE TABLE story_archive (
  id INTEGER PRIMARY KEY,
  title TEXT NOT NULL,
  url TEXT,
  time INTEGER NOT NULL,
  final_score INTEGER NOT NULL
);

-- Stories whose AI outputs were taken down; nothing is generated or served for them.
CREATE TABLE blocked_stories (
  story_id INTEGER PRIMARY KEY,
  reason TEXT,
  created_at INTEGER NOT NULL
);

CREATE TABLE reports (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  device_id TEXT NOT NULL,
  story_id INTEGER NOT NULL,
  kind TEXT NOT NULL,
  reason TEXT,
  created_at INTEGER NOT NULL
);
CREATE INDEX idx_reports_story ON reports(story_id);

-- Devices identified by their App Attest key id (or a random id for anonymous tokens).
CREATE TABLE devices (
  id TEXT PRIMARY KEY,
  public_key TEXT,                 -- base64 SPKI; NULL for anonymous devices
  counter INTEGER NOT NULL DEFAULT 0,
  attested INTEGER NOT NULL DEFAULT 0,
  environment TEXT,
  created_at INTEGER NOT NULL,
  last_seen INTEGER NOT NULL
);

CREATE TABLE attest_challenges (
  challenge TEXT PRIMARY KEY,
  expires_at INTEGER NOT NULL
);

-- Per-device daily usage. day = 'YYYY-MM-DD' (UTC).
CREATE TABLE usage_daily (
  device_id TEXT NOT NULL,
  day TEXT NOT NULL,
  kind TEXT NOT NULL,              -- 'summary' | 'article' | 'agent'
  count INTEGER NOT NULL DEFAULT 0,
  last_at INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (device_id, day, kind)
);

-- Global daily token budget (circuit breaker).
CREATE TABLE budget_daily (
  day TEXT PRIMARY KEY,
  tokens INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE subscriptions (
  original_transaction_id TEXT PRIMARY KEY,
  product_id TEXT NOT NULL,
  status TEXT NOT NULL,            -- 'active' | 'expired' | 'revoked' | 'refunded' | 'billing_retry'
  expires_at INTEGER,              -- unix ms
  environment TEXT NOT NULL,
  app_account_token TEXT,
  auto_renew INTEGER,
  updated_at INTEGER NOT NULL
);

CREATE TABLE subscription_devices (
  original_transaction_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  last_seen INTEGER NOT NULL,
  PRIMARY KEY (original_transaction_id, device_id)
);
CREATE INDEX idx_subscription_devices_device ON subscription_devices(device_id);

CREATE TABLE notification_log (
  notification_uuid TEXT PRIMARY KEY,
  notification_type TEXT NOT NULL,
  subtype TEXT,
  original_transaction_id TEXT,
  received_at INTEGER NOT NULL
);
