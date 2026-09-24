ALTER TABLE provider_sync_run ADD COLUMN lease_owner uuid;
ALTER TABLE provider_sync_run ADD COLUMN lease_until timestamptz;
ALTER TABLE provider_sync_run ADD COLUMN next_attempt_at timestamptz;
ALTER TABLE provider_sync_run ADD COLUMN automatic_retries integer NOT NULL DEFAULT 0;
CREATE UNIQUE INDEX one_unfinished_basic_run ON provider_sync_run(endpoint)
 WHERE endpoint='getEgytBassInfoInqire' AND status IN ('RUNNING','BUDGET_DEFERRED','FAILED');
CREATE TABLE provider_sync_work (
 run_id uuid NOT NULL REFERENCES provider_sync_run(id),unit_key text NOT NULL,kind text NOT NULL,
 hpid text,page_no integer NOT NULL,num_of_rows integer NOT NULL,status text NOT NULL DEFAULT 'PENDING',
 response_id bigint REFERENCES provider_response(id),attempts integer NOT NULL DEFAULT 0,
 last_attempt_at timestamptz,error text,next_attempt_at timestamptz,
 PRIMARY KEY(run_id,unit_key)
);
CREATE TABLE hospital_basic_info_snapshot (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,sync_run_id uuid NOT NULL REFERENCES provider_sync_run(id),
 hpid text NOT NULL,fetched_at timestamptz NOT NULL,fetch_status text NOT NULL CHECK(fetch_status='SUCCESS'),
 provider_response_id bigint NOT NULL REFERENCES provider_response(id),raw_payload jsonb NOT NULL,
 raw_department_text text,departments_status text NOT NULL,source_schema_version text NOT NULL,normalizer_version text NOT NULL,
 UNIQUE(sync_run_id,hpid)
);
CREATE INDEX basic_snapshot_hpid_idx ON hospital_basic_info_snapshot(hpid,fetched_at DESC);
CREATE TABLE hospital_department (
 snapshot_id bigint NOT NULL REFERENCES hospital_basic_info_snapshot(id) ON DELETE CASCADE,
 ordinal integer NOT NULL,department_name text,raw_value text,source text NOT NULL,interpretation_status text NOT NULL,
 PRIMARY KEY(snapshot_id,ordinal)
);
CREATE TABLE hospital_operating_hours (
 snapshot_id bigint NOT NULL REFERENCES hospital_basic_info_snapshot(id) ON DELETE CASCADE,
 day_type text NOT NULL CHECK(day_type IN ('MON','TUE','WED','THU','FRI','SAT','SUN','HOLIDAY')),
 open_time time without time zone,close_time time without time zone,raw_open_value text,raw_close_value text,
 open_presence text NOT NULL,close_presence text NOT NULL,open_status text NOT NULL,close_status text NOT NULL,
 interpretation_status text NOT NULL,source text NOT NULL,PRIMARY KEY(snapshot_id,day_type)
);
CREATE TABLE hospital_basic_info_dataset_member (
 run_id uuid NOT NULL REFERENCES provider_sync_run(id),hpid text NOT NULL,
 snapshot_id bigint REFERENCES hospital_basic_info_snapshot(id),record_status text NOT NULL,
 checked_at timestamptz NOT NULL,response_id bigint NOT NULL REFERENCES provider_response(id),PRIMARY KEY(run_id,hpid)
);
CREATE TABLE hospital_basic_info_state (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),current_run_id uuid NOT NULL REFERENCES provider_sync_run(id),
 previous_run_id uuid REFERENCES provider_sync_run(id),published_at timestamptz NOT NULL
);
