ALTER TABLE discovery_result ADD COLUMN endpoint text NOT NULL DEFAULT 'getEgytListInfoInqire';
ALTER TABLE provider_sync_run ADD COLUMN endpoint text NOT NULL DEFAULT 'getEgytListInfoInqire';
CREATE INDEX discovery_endpoint_idx ON discovery_result(endpoint,id DESC);
CREATE INDEX sync_endpoint_idx ON provider_sync_run(endpoint,started_at DESC);
