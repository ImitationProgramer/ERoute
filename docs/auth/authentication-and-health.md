# Active phase-two password contract

General ERoute now uses POST /api/v1/auth/signup, /login and /reauth. Set EROUTE_AUTH_PROVIDER=password with explicit local/test/production environment and existing key file. PASS/stable identity verification is not a prerequisite. Legacy transaction APIs below are isolated development tooling only. Production still rejects development classes/accounts/environments, and requires HTTPS transport. Local HTTP exceptions remain development-only.

Phone: Korean 010, ASCII spaces and hyphens removed, exactly 11 digits; no ownership verification. UUID userId remains owner. V9 adds password_credential and keyed phone_login_identifier; existing accounts/numbers are reserved without a credential or automatic merge. Startup backfills accepted HMAC key versions under a shared lock, using existing encrypted phones. Keep existing account encryption keys until re-encryption completes.

Password: NFC Unicode17 using ICU4J 78.3/unorm_dart 0.3.2, codepoints 15..128, input ceiling 4096 UTF-16 units before normalization, preserve case/spaces, reject malformed surrogate sequences, no truncation. Argon2id m=19456KiB/t=2/p=1, 16-byte random salt/32-byte hash; nfc-codepoints-v1 policy. Offline versioned common/breached top100000 blocklist plus identical-character passwords; this is not an exhaustive breach lookup. Four concurrent hash slots, existing IP 60/minute and identifier 10/minute, separate from NMC. Raw passwords/tokens/phone/health are never logged.

Signup requires signup-password-v1 acceptance and age-14-self-v1 self-declaration; health-v1 consent is separate. Never inserts verified_identity for password signup. Recovery/phone changes are unsupported; phone-only reset/merge forbidden. Phone squatting/reassignment/recovery risks remain deployment review items, without blocking development login. No real-user public deployment was authorized.

Health: GET /api/v1/me/health-snapshot holds the consent row lock through profile+medication reads. Every medication mutation requires baseVersion and consentEpoch; updates/deletes also require medication version. Missing/null preconditions: PRECONDITION_REQUIRED/400; invalid values: INVALID_HEALTH_INPUT/400; stale version/epoch: 409. No legacy bypass or latest-value substitution. General UI retains exact edit-start snapshots for profile PUT. No MFDS capability; manual source and null productCode only. Withdrawal keeps sessions and deletes health/medications with the existing erasure and backup evidence policy.

Explicit credential provisioning for an existing DEVELOPMENT user requires PasswordBootstrap with a private manifest of exact userId/phone/password mappings and matching local/test DB marker. It preserves existing credentials on repeat, rejects wrong passwords/conflicting numbers and never resets data. The old development credential is never copied into a password.

The session lifetime, encryption, ownership, erasure and restoration details below remain applicable. Historical verification results below describe the earlier phase, not this implementation; see docs/qa/member-real-integration-2026-09-15/README.md for current results.

---

# Authentication and member health

## Current direction (2026-09-15)

Member signup/login will use phone number + password. PASS is excluded from the roadmap and is not a release prerequisite. SMS is not part of phase one. Phone input alone is not ownership, identity or age verification.

Phase one implements reusable Flutter member screens in an isolated UI preview. Existing general dev/production authentication, Backend, HTTP contracts and migrations remain temporarily unchanged; this does not renew the former PASS plan. After UI approval, phase two will implement password authentication and connect the same widgets to actual repositories. See `../ui/member-ui-preview.md`.

The implementation/operations details below describe the existing authentication path. Provider-bound identity and age rules are historical/current-server behavior, not requirements for the future password UI. Provider failure still never becomes a development success.

## Local setup

Use a dedicated PostgreSQL database ending in `_local` or `_test`. Provisioning the environment marker requires an explicit bootstrap option; subsequent startups verify the marker, not just the database name. The existing hospital database is not seeded automatically.

1. Build `services/backend`: `./mvnw -Pdevelopment-auth -DskipTests package`.
2. Supply `DB_URL`, `DB_USERNAME`, `DB_PASSWORD` explicitly in the shell; the bootstrap script does not source `.env`.
3. Run `python scripts/bootstrap_dev_accounts.py --environment local --initialize-local-database`.
4. Set `EROUTE_AUTH_ENVIRONMENT=local`, `EROUTE_AUTH_PROVIDER=development`, `EROUTE_ALLOW_DEVELOPMENT_AUTH=true`, and `EROUTE_AUTH_KEY_FILE` to the printed private file path, then start the Backend normally.
5. Use `scripts/run_mobile.py` with the same explicit environment/allow flag and a reachable `API_BASE_URL`. Enter `dev:member-a`, `dev:member-b` or `dev:operator` and the respective credential from the private file. Do not copy credentials into tracked Dart configuration.

The command creates three synthetic accounts and test signup-consent evidence marked `DEVELOPMENT_BOOTSTRAP`. Health consent is not pre-granted. Account source and all identity results are `DEVELOPMENT`. Operator is limited to `/ops/status`; it cannot access member health. Credentials are random, hashed in the development fixture table and written to `.runtime/auth-local/credentials.json` with mode 0600. Key files are mode 0600; directories are private. Re-running does not reset health data or reveal secrets. `--rotate-credentials` explicitly rotates fixture credentials and revokes corresponding sessions. No account or fixture is created on normal startup.

Build production with a **clean** default Maven build. `python scripts/verify_auth_release.py --jar services/backend/target/emergency-api-0.1.0.jar` rejects development classes and contradictory runtime settings. `--artifact-only` performs just artifact inspection. Development sources live in `src/development/java` and are added only by `-Pdevelopment-auth`; they are absent from the default artifact. Authentication is disabled by default. The production profile currently only supports explicit disabled authentication while public hospital features remain available.

## Account and transaction rules

Internal UUIDs own all member records. A phone number is encrypted contact data, never an account key or automatic data migration instruction. Backend-verified provider scope plus stable subject identifies the account through versioned HMAC aliases. New members require verified age >=14 and current signup consent. February 29 birthdays use Java LocalDate.plusYears: February 28 in a non-leap target year; this must be reviewed with the real provider's age specification before launch. A different verified person using the same number never inherits an account.

Client-generated 256-bit request proof is bound via SHA-256 to a five-minute server transaction. Proof headers, callback evidence and tokens are not logged. The development adapter receives a random fixture credential and returns a server-owned synthetic subject/date, not a client-supplied role or success boolean. It cannot issue sessions. Real provider initiation, callbacks, SDK/deeplinks and cryptography are not guessed. Only server verification may move PENDING to VERIFIED. Consent completion is allowed for five minutes after verification; consumed/cancelled/expired trades cannot issue new sessions. Completion retransmissions use the same Idempotency-Key for a 30-second encrypted replay window.

A verified new phone is accepted only for the same stable identity and explicit confirmation. Existing sessions are revoked. A bound reauthentication also checks the initiating user/session. Without a matching stable identity the operation fails; no number-only operator recovery is offered.

## Sessions and public access

Opaque access tokens expire in 5 minutes. Member sessions expire after 7 days without explicit authenticated member activity and absolutely 30 days after creation. Operators use 15 minutes idle/8 hours absolute. Refresh rotation does not move either original creation or last activity. User-driven member data operations count as activity; `/me/activity` records explicitly opening account functionality. `/me`, consent status, notification polling, refresh and public hospital traffic do not keep sessions alive.

Every protected request checks token, database session revocation, account state and environment. The token HMAC includes environment and purpose. Logout proofs are random, hashed and revocation-only. Completed logout rejects both access and refresh for that session; other sessions remain until logout-all/phone change. A health withdrawal leaves the session and refresh usable for `/me` and consent/deletion status while rejecting health reads/writes.

The Flutter repository keeps access tokens only in memory and refresh/revocation proofs in the platform secure store. Storage failure never falls back to preferences. A single shared refresh Future prevents parallel client refreshes. Repeated transport requests retain an idempotency key; the server atomically rotates and retains an encrypted exact response for 30 seconds. Reuse with a different key, or outside that window, revokes the session. Offline logout clears local authentication/health state and keeps only the revocation-only proof for explicit or startup retry. Server revocation is not falsely reported as complete.

Public hospital reads/search and minimal health endpoints bypass session checks. Landing/Map/Drawer 119 entry remains independent of auth, age, GPS and Backend. The existing MockEmergencyDialer remains default. No live PASS, SMS or telephone launcher is used in development/automated validation.

## Health semantics and withdrawal

All health operations use the authenticated principal; ownership is never taken from body userId. A/B and operator permission checks run through Spring Security and owner-constrained JDBC queries. Cross-owner medication IDs and missing IDs both return 404. Unknown input fields are rejected. All current consent checks are database checks, not token claims.

Allergies and conditions distinguish UNSET, NONE and RECORDED. Notes are optional. Medication lists distinguish UNSET/NONE/RECORDED; deleting the last entry produces UNSET. Medication name and optional note are manual, productCode stays null, and there is no drug advice or automatic matching. Health rows use owner UUID, consent epoch, optimistic version, encrypted body and server timestamp. Changes are pessimistic; success means server acknowledgement.

Withdrawal first commits REVOKING plus a new consent epoch and a durable deletion job. All health operations serialize on the owner's consent row. A job physically deletes health rows, records a body-free restore exclusion and moves consent to REVOKED. A failed job remains blocked and exposes FAILED/retry; it does not restore consent. Automatic retries are bounded to five, then explicit retry is available. Duplicate request keys identify the same operation. Reconsent is allowed only after successful service deletion; a new epoch never restores previous content. Account, public hospital data and other members are untouched.

## Screen protection and memory drafts

`MemberHealthPage` owns sensitive state and `HealthDraft` owns the bounded in-memory draft contract. The route uses Android FLAG_SECURE plus a native pause cover and an iOS scene-resignation cover. Flutter covers the health body on inactivity and verifies session/current consent before displaying it again. Native covers are removed only after the protected Flutter frame is ready, independently of network availability, so the app's public emergency navigation is not gated on the server.

Last actual edit starts/restarts a 10-minute monotonic draft TTL. App switches, polling and retries do not extend it. The draft is never written to disk, restoration state or logging. Returning from another app preserves the draft only for the same user, session generation, consent epoch and data version. Verification failure keeps the body covered with a retry action; the draft can remain until its original deadline. A server-version conflict does not overwrite newer data. Logout, account change, withdrawal confirmation, nonrenewable session expiry and TTL expiration clear the associated information. Process death loses the draft.

While visible, the page checks body-free consent status every 10 seconds; the poll is not user activity. Poll connection loss is not withdrawal and does not delete the draft. Subsequent requests still have server authorization; lifecycle resume always revalidates. Late results are rejected by client generation and server consent/version checks. This is bounded polling, not a promise of instantaneous remote screen recall.

## Encryption and key rotation

`SecretBox` uses Java JCA AES-256-GCM, a 128-bit tag and a new SecureRandom 96-bit IV for every encryption, including retry and re-encryption. A database reservation prevents nonce reuse across processes and survives rollback; usage is capped at 2^32 attempts per key. No custom algorithm or large key-management service is introduced. Envelope is `v1.keyId.iv.ciphertext.tag` (base64url components). AAD binds environment, purpose, owner/resource/epoch and format; ciphertext moved to another member fails authentication.

The private JSON key file has `environment`, and five rings: `health`, `account`, `temporary`, `identity`, `session`. Each ring contains `active` and `keys` (version-to-32-byte-base64url map). Use independent random material across purposes and environments. Production uses existing platform Secret mounting, never keys in source, image, database or logs. Database fingerprints reject replacing key material under an existing version ID. Missing keys, invalid tags, unknown versions or corrupted envelopes fail closed with ENCRYPTED_DATA_UNAVAILABLE. They never become empty health data or trigger overwrite. Deletion requires no decryption.

To rotate encryption: deploy a new version to all instances as a readable key, then switch the active write version, and run the non-web `--auth-reencrypt` command. It reads in bounded batches and updates only unchanged ciphertext; concurrent edits win and deleted rows are never inserted. Re-run safely after interruption. Verify all live rows and retained backups before retiring the old decryption key. Do not re-use key versions or key material. After restoring a database, revoke restored sessions and activate fresh encryption material before accepting writes, because restored nonce reservations may be stale.

Identity HMAC-SHA256 is versioned separately. On fresh verified input, all configured lookup keys are tried, and the active alias is added to the **same** user atomically. Raw CI/DI is never retained to facilitate rotation. A user/scope with no usable HMAC key prevents startup; a cold account keeps its previous lookup key required. Hashes cannot be translated without re-verification. Lost/compromised key recovery must not silently create duplicate accounts or join by phone. Session-key rotation must keep old lookup keys for still-live tokens, or deliberately revoke affected sessions.

## Retention and release prerequisites

Expired/cancelled/consumed transaction secrets and short replay ciphertext are cleaned by bounded maintenance. Expired session tokens and rate buckets are removed. Current consent evidence remains while needed; superseded/withdrawn records have the proposed 30-day evidence retention. Medical bodies have no application history or permanent mobile copy. Body-free deletion exclusions cover the proposed maximum 30-day backup retention plus a 7-day restore-validation margin; unresolved backup jobs prevent exclusion removal.

Service DB deletion and backup destruction are separate. `backupComplete` remains false until an operator verifies the storage platform's actual destruction. Do not infer completion merely from time passing. Before serving a restored database, export the current minimal deletion ledger to a separate protected location, run `scripts/reconcile_health_restore.py` on the isolated restore, revoke restored sessions, rotate write keys, verify exclusions and only then allow traffic. Backup policy, access-log retention/legal basis, storage lifecycle and independent deletion-ledger exports require deployment-owner review before real health data. A runbook is not evidence that an unconfigured backup provider has deleted its copies.

The previous PASS release checklist is retired. The next authentication phase must define password storage/verification, account compatibility and recovery policy, and finalize separate signup/health consent copy before enabling real signup. Phase one does not implement these decisions or modify the current server gates. No fallback mock success is possible in general execution.

## Validation

Backend: explicit bootstrap, then `./mvnw -Pdevelopment-auth verify` with EROUTE_TEST_JDBC_URL/EROUTE_TEST_DB_USER/EROUTE_TEST_DB_PASSWORD and EROUTE_AUTH_TEST_KEYS/EROUTE_AUTH_TEST_CREDENTIALS pointing to the isolated setup. The auth suite exercises real HTTP filters, fixture Provider, DB sessions, encryption and ownership. Existing hospital tests continue to run. Clean production packaging plus verify_auth_release checks that dev classes are absent.

Flutter: `flutter analyze`, `flutter test --dart-define=EROUTE_AUTOMATION=true`; `health_privacy_test.dart` checks draft TTL, identity/epoch/version binding, app switches, failed resume validation, notification outage and withdrawal. Device flow: `python scripts/test_auth_mobile.py --device <emulator> --api-base-url <local Backend URL> --credentials <private development credentials file>`. The temporary test configuration is never committed. No external identity or phone handoff is part of these tests.

### Verified in this workspace (2026-09-15)

- Backend full verification: 74 tests, zero failures/errors/skips, including 11 real HTTP authentication/health scenarios and 3 environment/session policy tests. The final phone-change purpose and cross-member profile assertions also passed in the HTTP suite.
- Flutter analysis: no issues. Flutter unit/widget suite: 90 tests passed, including delayed responses after logout and nonrenewable expiry combined with secure-store failure.
- Android dev APK built and the emulator flow passed against the isolated PostgreSQL-backed development server. It covers real login, separate health consent, simulated app lifecycle transitions preserving a memory draft, profile/medication writes, withdrawal with the account session retained, and logout. The test dialer received zero requests.
- Health form at 430px was rendered and visually inspected. Production artifact inspection passed; the development artifact and three conflicting deployment configurations were rejected. Repeated explicit bootstrap retained and validated the existing private credentials.
- iOS includes the native recent-app cover and app-scoped Keychain entitlement for all Runner build configurations. Plist/project syntax is valid, but iOS compilation and real OS background/recent-app behavior still require Xcode and device QA; this workspace has only Command Line Tools. Android OS recent-app behavior should also be checked on release devices before handling real health information.

All validation used virtual identity and health information. No PASS app, SMS or telephone launcher was invoked. Production authentication remains on the existing disabled path until the separate password implementation phase.
