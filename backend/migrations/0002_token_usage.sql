-- Token usage per day, feature and source, for cost tracking (budget_daily keeps the circuit-breaker total).
CREATE TABLE token_usage_daily (
  day TEXT NOT NULL,
  feature TEXT NOT NULL,            -- 'title' | 'summary' | 'article' | 'agent' | 'questions'
  source TEXT NOT NULL,             -- 'user' | 'cron'
  calls INTEGER NOT NULL DEFAULT 0,
  input_tokens INTEGER NOT NULL DEFAULT 0,
  cached_input_tokens INTEGER NOT NULL DEFAULT 0,  -- part of input_tokens billed at the cache-hit price
  output_tokens INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, feature, source)
);
