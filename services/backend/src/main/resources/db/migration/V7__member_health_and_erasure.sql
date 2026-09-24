CREATE TABLE member_health_profile (
 user_id uuid PRIMARY KEY REFERENCES app_user(id), consent_epoch bigint NOT NULL, version bigint NOT NULL,
 body_cipher text NOT NULL, updated_at timestamptz NOT NULL
);
CREATE TABLE member_medication (
 id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES app_user(id), consent_epoch bigint NOT NULL,
 version bigint NOT NULL, body_cipher text NOT NULL, updated_at timestamptz NOT NULL
);
CREATE INDEX member_medication_owner ON member_medication(user_id);
CREATE TABLE health_erasure (
 id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES app_user(id), request_key text NOT NULL,
 erased_epoch bigint NOT NULL, state text NOT NULL, attempts integer NOT NULL DEFAULT 0,
 created_at timestamptz NOT NULL, completed_at timestamptz, backup_due_at timestamptz NOT NULL,
 backup_completed_at timestamptz, UNIQUE(user_id,request_key)
);
CREATE TABLE health_deletion_ledger (
 id uuid PRIMARY KEY, user_id uuid NOT NULL, consent_epoch bigint NOT NULL, resource_id uuid,
 deleted_at timestamptz NOT NULL, retain_until timestamptz NOT NULL
);
