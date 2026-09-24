ALTER TABLE nmc_call_attempt ADD COLUMN scope text;
CREATE INDEX nmc_attempt_scope_idx ON nmc_call_attempt(scope,requested_at);
