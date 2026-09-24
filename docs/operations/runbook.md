# Operations

## Detail delivery and selected marker verification

Detail is a database-only `GET /api/v1/emergency-hospitals/{hpid}`. Trace the selected HPID through the route, actual request URL, HTTP status, response HPID, parser, and visible fields. Do not diagnose a field as missing merely because a request failed. Flutter's `API_BASE_URL` is a compile-time value: changing a shell variable after building does not change an installed APK. The local development server uses port 18081; the Android emulator reaches it at `http://10.0.2.2:18081`. Physical devices need their own reachable URL.

For a read-only repository smoke check, run `dart run tool/verify_hospital_detail.dart BASE_URL HPID` from `apps/mobile`, substituting the actual URL and selected HPID. It uses the production detail repository/parser, emits only field-presence and coverage diagnostics, and never searches or launches a phone. Compare `SELECT count(*) FROM nmc_call_attempt` before/after repeated detail calls while no other workflow is querying NMC. Never clear the ledger or run catalog sync to make this check pass.

`scripts/test_mobile_integration.py` runs native-map fixtures by default. Optionally supply `API_BASE_URL` and `DETAIL_SMOKE_HPID` to also verify stored HTTP detail through Android Map→Detail→Back. This test seeds its search from the stored detail instead of calling the search endpoint, uses fake hospital contacts and MockEmergencyDialer, and blocks native phone-launch channels. All PostgreSQL integration tests must use the isolated `_test` database; they truncate test tables.

Naver Map 1.4.4 accepts nullable captions in Dart but its Android marker handler force-unwraps updates. Remove an existing caption with `NOverlayCaption(text: '')`, never `setCaption(null)`. Initial icon-only markers explicitly use an empty caption; deselection also sends an empty caption to the native overlay. Selection updates preserve overlay identity, and the native test checks caption/chip exclusivity, 40-hospital fixtures, viewport changes without camera motion, and ordinary Map restoration. Zoom-based unselected labels and clustering remain out of scope.

Verification on 2026-09-13: actual stored HPIDs A1100001/A1100002 returned HTTP 200 and parsed their address/contact fields. Android Map→Detail→Back passed against A1100002 through `10.0.2.2:18081`; detail queries left the development NMC ledger at 76. Backend tests: 36 passed including HTTP and PostgreSQL tests. Flutter tests: 69 passed; Android integration: 2 passed. State QA PNGs are generated under `apps/mobile/build/qa/detail-*.png`. Native OS handoff on a physical device remains a manual, explicit-user-tap check; automated tests do not dial or hand off.

## Secrets and source access

Keep `.env` outside Git and restrict its permissions (`chmod 600 .env`). Never pass the full environment to `--dart-define-from-file`; scripts/run_mobile.py exports only API_BASE_URL and NAVER_MAP_CLIENT_ID. NMC uses an explicit decoded/encoded key setting. Request URLs and service keys must not be logged.

Before changing NMC parsing run scripts/verify_sources.py and read the cited PDF pages. If the PDF is not committed, provision it into the implementation/CI workspace or set NMC_V13_PDF. CI deliberately fails when the source is unavailable; production jars need only the reviewed codebook.

## Readiness and initial setup

`GET /actuator/health` checks application/database health. `GET /api/v1/readyz` returns 503 until a usable catalog exists. `/api/v1/map-config` returns null bounds before catalog initialization; no fixed fallback city is supplied.

Run discovery with the same DB and key alias as the server. A failed authorization call is charged but cannot establish a national pagination failure. The report contains no credentials. Import region reference, then run `--sync-catalog`. The default background job checks Master age hourly and only attempts refresh after the configured Master interval; it does not poll live regional beds.

## Call budget

Defaults: 1,000 provider calls per endpoint/day, automatic budget 900 per rolling 24 hours, 300-second regional TTL, two requests/second per endpoint, max four refresh workers per server. No client refresh action bypasses cache or guard. Do not reuse the same key in untracked tools and assume this ledger can observe those requests.

The provider's exact daily reset timezone remains unverified. The rolling window is intentionally conservative. On service-limit errors the endpoint is blocked for 24 hours; correct account settings before resuming. Never delete the call ledger to recover quota.

Useful SQL (no user coordinates or secrets):

```sql
SELECT endpoint, count(*) AS calls
FROM nmc_call_attempt
WHERE requested_at > clock_timestamp() - interval '24 hours'
GROUP BY endpoint;

SELECT endpoint, outcome, count(*)
FROM nmc_call_attempt
WHERE requested_at > clock_timestamp() - interval '24 hours'
GROUP BY endpoint, outcome;

SELECT status, started_at, completed_at, details
FROM provider_sync_run ORDER BY started_at DESC LIMIT 10;

SELECT count(*) FILTER (WHERE region_id IS NULL) AS unmapped,
       count(*) FILTER (WHERE latitude IS NULL OR longitude IS NULL) AS unlocated
FROM hospital WHERE active;

SELECT last_error, count(*) FROM region_cache GROUP BY last_error;
```

Micrometer records endpoint request/failure counters. Only health/info HTTP actuator endpoints are exposed by default. If metrics are exported later, keep them on a protected management network. HTTP search requests are limited per source address; proxy deployment must explicitly configure trusted forwarding and gateway limits.

## Failure handling

- Discovery missing: no catalog sync; run the controlled discovery tool.
- REGION_MAPPING_ERROR: keep Master row and any previous snapshot; compare original address, administrative ID, endpoint query mapping and complete LIST coverage. Legacy REGION_UNVERIFIED/REGION_UNRESOLVED records have the same meaning. If BEDS was never called, do not classify this as LIVE_ERROR. The user sees a general information-loading message.
- API/network/page error: previous complete regional snapshot remains; response marks error/stale.
- Budget/rate deferred: return last snapshot or null/UNKNOWN. No API failure is fabricated.
- Unknown timestamp timezone: show formatted parsed provider wall-clock input (timezone unverified) and ERoute collection time separately; never expose compact raw input or compute provider age.
- Unknown HVS/equipment/capability semantics: preserve raw and do not convert to 0/false/refusal.

For cities with general districts, LIST Q1 and BEDS STAGE2 are not interchangeable. The versioned `services/backend/src/main/resources/nmc/region-query-mappings.json` records LIST municipality aliases; Flyway V5 loads them for an existing DB, and `scripts/import_regions.py` loads them after a fresh reference import. Unverified scopes must pass complete Master HPID coverage before BEDS collection. Preserve the administrative hospital region ID and region-specific cache/observations. See [the measured Paju/Goyang investigation](region-refresh-investigation-2026-09-14.md).

```sql
SELECT r.id, r.address_prefix, r.stage1 AS beds_stage1, r.stage2 AS beds_stage2,
       COALESCE(t.stage1,r.stage1) AS list_q0,
       COALESCE(t.stage2,r.stage2) AS list_q1,
       r.verified, c.last_attempt_at, c.last_error
FROM nmc_region_mapping r
LEFT JOIN nmc_region_query_mapping q
  ON q.region_id=r.id AND q.endpoint='getEgytListInfoInqire'
LEFT JOIN nmc_region_mapping t ON t.id=q.request_region_id
LEFT JOIN region_cache c ON c.region_id=r.id
WHERE c.region_id IS NOT NULL;
```

`nmc_request`, `nmc_http`, `nmc_page`, `nmc_failure`, and `region_refresh` logs contain endpoint, safe region/page parameters, response IDs and error codes without request URLs or credentials. Inspect stored provider_response headers/HPIDs and the call ledger first. A three-region cold refresh waits for the next ledger slot within the existing search deadline while retaining completed regions. If insufficient time remains, CALL_RATE_LIMIT still returns a manual-refresh deferral. CALL_BUDGET_LIMIT returns immediately and requires budget availability plus a later search; no background resume is scheduled. `nmc_rate_wait` logs the bounded admission delay without charging an unmade HTTP call. See [the Asan/Cheonan diagnosis](cheonan-rate-deferral-2026-09-14.md). Do not clear quota records or disable the guard to test it.

## Retention and recovery

Default retention is seven days. Keep each hospital's last numeric snapshot, active observation pointers, current regional raw responses and the current catalog's source response IDs. Discovery evidence is retained. Budget records older than retention can be pruned only outside the enforced 24-hour window.

Back up PostgreSQL before schema upgrades. Flyway migrations run at startup. If an adapter change causes errors, revert the application release while preserving existing snapshots and the call ledger. Do not promote incomplete Master or regional batches.

## Mobile verification limits

Unit/widget tests use a native-map test double and a bundled Korean font. Actual Naver authentication, platform permission dialogs and GPS accuracy require device/emulator testing. Android debug permits local HTTP; production does not. iOS requires full Xcode/CocoaPods and the registered Bundle ID.

## NMC Basic Info static collection

V13 p31–35 and `docs/api/nmc-basic-discovery-report.md` govern this endpoint. The source API is **not** queried by Detail. Initial automatic refresh policy is seven days, an ERoute policy rather than a provider update guarantee.

```sh
python3 scripts/verify_sources.py
./services/backend/mvnw -f services/backend/pom.xml -DskipTests package
python3 scripts/run_backend.py --discover-basic
# If discovery stopped at its 40-attempt invocation limit:
python3 scripts/run_backend.py --resume-basic-discovery=DISCOVERY_ID
python3 scripts/run_backend.py --sync-basic
# Resume an interrupted, failed or budget-deferred run after its cause clears:
python3 scripts/run_backend.py --resume-basic=RUN_UUID
```

These Basic commands are one-shot, database-backed jobs with web serving and scheduled jobs disabled. Discovery only writes audit/raw responses; it does not publish clinical data. Configuration keeps the NMC key on Backend, including its encoded/decoded handling.

Only after a passed discovery and complete initial publication, enable `BASIC_INFO_SCHEDULER_ENABLED=true`. `BASIC_INFO_REFRESH_INTERVAL=7d` is the default (minimum 24 hours). The scheduler checks DB due dates, not nationwide NMC data. Failed transient work gets one additional automatic resumption after 24 hours; authentication/schema failures require an explicit retry. Budget deferral follows the rolling window, never calendar midnight.

A run freezes its targets and rechecks the active Master set before publication. Successful work survives process restarts. One lease owner publishes; another worker cannot replace its results. No failed/pending page or HPID can be published. Confirmed per-HPID empty responses are complete absence observations, not failed work. They preserve any previous hospital snapshot and never change Master active status.

Bulk continuations revalidate the first-page HPID sequence/metadata and final coverage. An inconsistent bulk generation becomes `SUPERSEDED`; its data are never published. Re-run discovery and start `--sync-basic` to select/retry a fresh generation. NMC exposes no snapshot token, so consistency across one exact provider instant is not promised. Staging older than seven days is recollected.

Budget formula: bulk `ceil(T/S)` requests, HPID mode `count(hospital WHERE active)`; add discovery and every retry. `NmcApiClient` permits at most one immediate transient retry, each separately reserved in `nmc_call_attempt`. Both discovery and jobs share the endpoint/key-alias rolling 24-hour budget. The 2026-09-13 bootstrap used 23 discovery + 530 collection requests = 553, with no retries. Bulk returned 529 HPIDs and missed one of 530 active Master records, so PER_HPID was selected for that generation. The 2026-09-14 acceptance run re-probed the current 529-record Master: discovery 7 selected NATIONWIDE at page size 100, and a new six-request sync published 529 records. Always inspect the latest passed discovery; the historical strategy is not permanent.

```sql
SELECT endpoint,status,started_at,completed_at,next_attempt_at,details->>'error' AS error
FROM provider_sync_run ORDER BY started_at DESC;
SELECT run_id,status,count(*) FROM provider_sync_work GROUP BY run_id,status;
SELECT endpoint,count(*) FROM nmc_call_attempt
WHERE requested_at>clock_timestamp()-interval '24 hours' GROUP BY endpoint;
SELECT current_run_id,previous_run_id,published_at FROM hospital_basic_info_state;
```

Raw retention protects current and previous datasets, carried-forward snapshots, discovery, and unfinished runs. `fetchedAt` belongs to the displayed snapshot; HTTP reads, retries and dataset publication never replace it with the current clock. Latest attempts and run errors remain separate.

Runtime verification must compare endpoint-ledger totals before/after repeated Detail requests with unrelated schedulers excluded. The expected difference is zero. Native tests use fixture searches, a DB-selected real Detail HPID, mock emergency dialing, and fake hospital contact launchers. No native phone handoff occurs.


Android acceptance can check several actual stored institutions in one invocation:

```sh
API_BASE_URL=http://10.0.2.2:18081 DETAIL_SMOKE_HPIDS=HPID1,HPID2,HPID3 python3 scripts/test_mobile_integration.py emulator-5554
```

Select these HPIDs from the active published DB dataset. Native tests temporarily install a test APK and may remove it on exit; this run confirmed that the test package was removed. To leave the current user-facing build installed after QA, run:

```sh
API_BASE_URL=http://10.0.2.2:18081 python3 scripts/run_mobile.py -d emulator-5554 --no-resident
```

Confirm the actual screen after installation; passing integration tests alone does not establish that the user's normal APK includes the current implementation.
