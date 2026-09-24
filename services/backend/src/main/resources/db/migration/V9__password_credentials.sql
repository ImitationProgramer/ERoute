CREATE TABLE password_credential (
 user_id uuid PRIMARY KEY REFERENCES app_user(id),
 password_hash text NOT NULL,
 policy_version text NOT NULL,
 created_at timestamptz NOT NULL,
 updated_at timestamptz NOT NULL
);
-- A login identifier does not assert phone ownership or verified identity.
CREATE TABLE phone_login_identifier (
 environment text NOT NULL,
 key_version text NOT NULL,
 digest text NOT NULL,
 user_id uuid NOT NULL REFERENCES app_user(id),
 PRIMARY KEY(environment,key_version,digest),
 UNIQUE(user_id,key_version)
);
