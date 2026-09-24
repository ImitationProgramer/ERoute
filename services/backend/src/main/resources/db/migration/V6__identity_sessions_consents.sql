CREATE TABLE auth_environment (singleton boolean PRIMARY KEY CHECK(singleton), environment text NOT NULL CHECK(environment IN ('local','test','production')));
CREATE TABLE app_user (
 id uuid PRIMARY KEY, environment text NOT NULL, source text NOT NULL CHECK(source IN ('DEVELOPMENT','PRODUCTION')),
 role text NOT NULL CHECK(role IN ('MEMBER','OPERATOR')), status text NOT NULL DEFAULT 'ACTIVE',
 phone_cipher text NOT NULL, created_at timestamptz NOT NULL
);
CREATE TABLE verified_identity (
 user_id uuid NOT NULL REFERENCES app_user(id), scope text NOT NULL, key_version text NOT NULL, digest text NOT NULL,
 verified_at timestamptz NOT NULL, PRIMARY KEY(scope,key_version,digest), UNIQUE(user_id,scope,key_version)
);
CREATE TABLE verification_transaction (
 id uuid PRIMARY KEY, environment text NOT NULL, source text NOT NULL, purpose text NOT NULL,
 requester_hash text NOT NULL, phone_cipher text NOT NULL, provider_ref text UNIQUE,
 bound_user uuid REFERENCES app_user(id), bound_session uuid, state text NOT NULL,
 created_at timestamptz NOT NULL, expires_at timestamptz NOT NULL, verified_at timestamptz,
 verified_cipher text, consumed_at timestamptz, completion_key text, completion_cipher text, completion_until timestamptz
);
CREATE TABLE auth_session (
 id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES app_user(id), environment text NOT NULL,
 created_at timestamptz NOT NULL, last_activity_at timestamptz NOT NULL, expires_at timestamptz NOT NULL,
 reauthenticated_at timestamptz NOT NULL, revoked_at timestamptz, logout_hash text NOT NULL UNIQUE
);
CREATE INDEX auth_session_user ON auth_session(user_id);
CREATE TABLE session_token (
 digest text PRIMARY KEY, session_id uuid NOT NULL REFERENCES auth_session(id), kind text NOT NULL,
 expires_at timestamptz NOT NULL, consumed_at timestamptz,
 request_key text, replay_cipher text, replay_until timestamptz
);
CREATE INDEX session_token_session ON session_token(session_id);
CREATE TABLE consent_record (
 id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES app_user(id), kind text NOT NULL,
 version text NOT NULL, action text NOT NULL, source text NOT NULL, recorded_at timestamptz NOT NULL
);
CREATE TABLE health_consent (
 user_id uuid PRIMARY KEY REFERENCES app_user(id), state text NOT NULL DEFAULT 'UNSET', epoch bigint NOT NULL DEFAULT 0,
 document_version text, updated_at timestamptz NOT NULL
);
CREATE TABLE auth_rate_window (bucket text NOT NULL, window_at timestamptz NOT NULL, attempts integer NOT NULL, PRIMARY KEY(bucket,window_at));
CREATE TABLE crypto_key_usage (key_id text PRIMARY KEY, encryptions bigint NOT NULL CHECK(encryptions<=4294967296));
CREATE TABLE crypto_nonce (key_id text NOT NULL, nonce text NOT NULL, PRIMARY KEY(key_id,nonce));
