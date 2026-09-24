CREATE TABLE nmc_call_attempt (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 key_alias text NOT NULL, endpoint text NOT NULL, requested_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 outcome text NOT NULL DEFAULT 'RESERVED'
);
CREATE INDEX nmc_call_budget_idx ON nmc_call_attempt(key_alias,endpoint,requested_at);
CREATE TABLE nmc_budget_block (key_alias text NOT NULL,endpoint text NOT NULL,blocked_until timestamptz NOT NULL,PRIMARY KEY(key_alias,endpoint));
CREATE TABLE provider_response (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, endpoint text NOT NULL, scope text NOT NULL,
 page_no integer NOT NULL, fetched_at timestamptz NOT NULL, raw_xml text NOT NULL, raw_json jsonb,
 outcome text NOT NULL
);
CREATE TABLE provider_sync_run (
 id uuid PRIMARY KEY, mode text NOT NULL,status text NOT NULL,started_at timestamptz NOT NULL,
 completed_at timestamptz,details jsonb NOT NULL DEFAULT '{}'
);
CREATE TABLE discovery_result (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 passed boolean NOT NULL,mode text NOT NULL,page_size integer,report jsonb NOT NULL,
 pdf_sha256 text NOT NULL
);
CREATE TABLE nmc_region_mapping (
 id text PRIMARY KEY,address_prefix text NOT NULL UNIQUE,stage1 text NOT NULL,stage2 text NOT NULL,
 source_version text NOT NULL,verified boolean NOT NULL DEFAULT false
);
CREATE TABLE hospital (
 hpid text PRIMARY KEY,name text NOT NULL,class_code text,class_name text,address text,
 latitude double precision,longitude double precision,main_phone text,secondary_phone text,
 region_id text REFERENCES nmc_region_mapping(id),raw_json jsonb NOT NULL,
 catalog_version uuid NOT NULL,active boolean NOT NULL DEFAULT true,missing_runs integer NOT NULL DEFAULT 0,
 updated_at timestamptz NOT NULL,
 CHECK(latitude IS NULL OR latitude BETWEEN -90 AND 90),CHECK(longitude IS NULL OR longitude BETWEEN -180 AND 180)
);
CREATE INDEX hospital_coordinates_idx ON hospital(latitude,longitude) WHERE active;
CREATE TABLE catalog_state (singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),version uuid NOT NULL,fetched_at timestamptz NOT NULL);
CREATE TABLE region_cache (
 region_id text PRIMARY KEY,batch_json jsonb,fetched_at timestamptz,last_attempt_at timestamptz,
 last_error text,lease_owner uuid,lease_until timestamptz
);
CREATE TABLE hospital_realtime_snapshot (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,hpid text NOT NULL,region_id text NOT NULL,
 fetched_at timestamptz NOT NULL,source_raw_timestamp text,parsed_source_timestamp timestamp,
 source_timezone text,source_updated_at timestamptz,raw_json jsonb NOT NULL,
 response_ids jsonb NOT NULL
);
CREATE INDEX realtime_hpid_time_idx ON hospital_realtime_snapshot(hpid,fetched_at DESC);
CREATE TABLE hospital_observation (
 hpid text PRIMARY KEY,snapshot_id bigint REFERENCES hospital_realtime_snapshot(id),coverage_status text NOT NULL,
 checked_at timestamptz NOT NULL
);
CREATE TABLE hospital_resource_value (
 snapshot_id bigint REFERENCES hospital_realtime_snapshot(id) ON DELETE CASCADE,endpoint text NOT NULL,
 field_name text NOT NULL,raw_value text,parsed_type text NOT NULL,numeric_value bigint,interpretation_status text NOT NULL,
 PRIMARY KEY(snapshot_id,endpoint,field_name)
);
CREATE TABLE severe_capability_snapshot (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,hpid text NOT NULL,fetched_at timestamptz NOT NULL,raw_json jsonb NOT NULL);
CREATE TABLE severe_capability_value (snapshot_id bigint REFERENCES severe_capability_snapshot(id),endpoint text NOT NULL,field_name text NOT NULL,raw_value text,normalized_status text NOT NULL,PRIMARY KEY(snapshot_id,endpoint,field_name));
CREATE TABLE hospital_message (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,hpid text NOT NULL,endpoint text NOT NULL,fetched_at timestamptz NOT NULL,raw_json jsonb NOT NULL);
