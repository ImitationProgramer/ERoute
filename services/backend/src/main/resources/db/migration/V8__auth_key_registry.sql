-- Non-secret fingerprints detect accidental replacement of material under a reused key ID.
CREATE TABLE auth_key_registry (environment text NOT NULL,purpose text NOT NULL,key_version text NOT NULL,fingerprint text NOT NULL,PRIMARY KEY(environment,purpose,key_version));
