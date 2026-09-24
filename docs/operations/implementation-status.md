# MVP v0.1 verification — 2026-09-09

The dated sections below are historical verification records. The latest Basic Info implementation status is recorded at the end of this document.

## Completed

- V13 PDF accessibility/hash and endpoint-aware codebook source gate passed.
- Authenticated national discovery passed: totalCount 531; page sizes 10/100/500/1000 tested; size 100 traversed six populated pages plus the empty seventh page, with 531 unique HPIDs. This is not proof of an absolute numOfRows maximum.
- PostgreSQL Master contains 531 institutions. Real regional requests exercised geographically separated locations derived from catalog coordinates, including a single-tier administrative region.
- Latest server smoke: live results returned; immediate repeated search added zero NMC requests; manual search kept user distance null; missing latitude returned HTTP 400; readiness returned HTTP 200.
- Backend: 28 tests, zero failures/errors, including PostgreSQL integration tests against the isolated eroute_test database.
- Flutter map UX update: 22 unit/widget tests passed, analyzer clean, dev Android debug APK built. Pixel 10 native-map integration passed with viewport projection, manual search, selection, zoom/Sheet camera preservation, Drawer and mock 119 flow checks. Emergency launcher invocations were zero.
- Source candidates were scanned for the configured NMC key and its decoded form: no matches. The local .env is excluded from Git.

## Local runtime

Backend: http://127.0.0.1:18081. PostgreSQL: 127.0.0.1:55432. These are local development processes, not installed system services.

The final debug APK uses http://10.0.2.2:18081 for an Android emulator. This is build configuration, not a production default. A physical device needs a different reachable API_BASE_URL and a rebuild.

## Outstanding external validation

- NAVER_MAP_CLIENT_ID is configured locally. Pixel 10 native map authentication/rendering and location permission were verified; the running development app displayed the GPS search radius and eight returned hospital markers above the Sheet. Physical-device location/compass accuracy remains unverified.
- Full Xcode/CocoaPods are unavailable; iOS build/device verification remains pending.
- Regional fallback code is present but has not been exercised across all administrative regions because national discovery succeeded. Incomplete collection never replaces Master; a failed regional run currently restarts collection after quota recovery, rather than resuming saved chunks.
- Source hvidate timezone and absolute maximum numOfRows remain unverified.
- flutter_naver_map currently emits a future Kotlin Gradle compatibility warning; the pinned Android toolchain builds successfully.

No deployment or Git commit was performed.

## UI redesign verification — 2026-09-12

- App launch now opens the 119-centered Emergency Landing Page without requesting GPS, initializing the native map, or searching the Backend.
- Landing → Map → HPID Detail and the shared Drawer routes are implemented. Unsupported authenticated, medical-content, phone, navigation, share, and favorite features remain explicit placeholders.
- Map radii still come from map-config. Effective-radius fitting, Circle, distinct marker roles, dynamic Sheet viewport, and MANUAL fitting that excludes remote user GPS remain intact.
- Light and dark ERoute themes, shared design tokens/components, 48dp controls, narrow-screen layout, 200% text scaling, and landscape layouts are covered.
- All Landing, Map, and Drawer 119 entry points use the shared coordinator and MockEmergencyDialer in development and tests. Native emergency-channel calls were zero.
- Flutter analyzer passed, 28 unit/widget tests passed, the strict UI audit reported zero findings, DESIGN.md lint reported zero errors, and the final dev debug APK built successfully.
- The redesigned Landing, Map shell, and Detail were rendered at 430×932 and visually inspected. The emulator was not running during this verification, so the prior Pixel 10 native-map gate was not repeated.

## Landing polish and stored Hospital Detail — 2026-09-13

- Landing keeps the runtime gradient and real Flutter controls. Separate transparent light/dark illustration assets sit behind the content and are removed on landscape, narrow/short layouts, and large text.
- `GET /api/v1/emergency-hospitals/{hpid}` now combines the active stored Master row and the current realtime observation without calling NMC. A current confirmed absence does not read an older numeric snapshot.
- Flutter Detail asynchronously loads the HPID endpoint while preserving Map distance and realtime fallback. It renders stored address, 대표전화1, and 대표전화2; `dutyTel3` is never labeled as an emergency-room phone.
- The regular hospital contact action opens an OS dial screen after a user tap. Malformed values and 119/112 are rejected. The existing emergency-call coordinator and production gates are unchanged.
- `getEgytBassInfoInqire` department and raw weekly clinic-time definitions are recorded in the V13 codebook for a future static cache. The endpoint is not called in v0.1 and the Detail contract reports `NOT_REQUESTED`.
- Source verification and JSON contract validation passed. Backend ran 32 tests with zero failures against the isolated local `eroute_test` database; the stored-detail smoke returned HTTP 200 and added zero NMC calls.
- Flutter analyzer passed and 31 unit/widget tests passed. The dev debug APK built, was installed on the running Android emulator, and the generated illustration rendered correctly on the real app surface. The strict UI audit had zero findings and DESIGN.md lint had zero errors.

## NMC Basic Info implementation — 2026-09-14

- V13 pages 31–35 and authenticated Basic responses were checked before collection. See [discovery evidence](../api/nmc-basic-discovery-report.md). Nationwide pagination produced 529 unique records but missed one of the then-active 530 Master institutions; that HPID also returned a successful empty response. Collection therefore uses the verified PER_HPID mode. Master counts are queried dynamically, never production constants.
- Initial Basic publication completed on September 13 at 20:33 KST: 530 dataset members, 529 provided snapshots and one explicit source absence. Stored normalized data contain 8,233 department rows (raw order and duplicates retained) and 4,232 day rows: 3,004 KNOWN, 141 UNVERIFIED and 1,087 MISSING. The independent Master refresh subsequently changed the active count to 529; Basic collection does not deactivate hospitals.
- The Basic endpoint consumed 23 discovery calls and 530 collection calls, with no retries (553 total, within its 900 automatic budget). No additional Basic requests were made while resuming this implementation. Default static refresh is seven days, enabled locally only after the successful initial publication. No provider update cadence is assumed.
- PostgreSQL staging, durable work checkpoints, leases and atomic publication keep unfinished results hidden. Budget deferral resumes pending work; partial failure, source absence and retries preserve previously published values and their original fetchedAt. Raw XML, field presence, unknown fields, raw department text and raw time values remain stored.
- The additive Detail API reads PostgreSQL only. Its independent Basic data/refresh/stale states distinguish NOT_COLLECTED, source absence, parsing uncertainty and refresh failure. Realtime beds retain their existing endpoint and semantics.
- Flutter's 진료 정보 tab now displays real departments and eight hospital day rows with missing/unverified states, readable ERoute timestamps and the hospital-hours notice. It does not infer emergency-room hours, department hours, current availability or patient acceptance. Provider timestamp formatting preserves the unverified timezone policy.
- Detail uses an opaque top bar with the existing scroll layout. Native map caption clearing and lifecycle/projection checks preserve selected-only captions. No HIRA integration or broader redesign was introduced.
- Final backend verification: 47 tests passed against the isolated eroute_test database, with zero failures/errors/skips; Maven verify packaged the latest server. Flutter analyzer reported no issues; 79 unit/widget tests passed. Source/codebook checks and the strict UI audit passed with zero findings.
- Ten repeated HTTP Detail requests against the latest local Backend returned seven real departments and eight day rows. All endpoint ledgers were identical before/after: Basic 553, Master 75, realtime 14; total NMC call delta was zero. The older overnight Master ledger increased from 69 to 75 because of its independent scheduled catalog refresh, not Detail reads.
- Android native integration passed both tests on Pixel 10 against the latest Backend: dense 40-marker selection, Map→stored Detail→Back, actual departments, eight hospital day rows, scrolling and mock-only phone flows. Its before/after ledger delta was also zero across all NMC endpoints. Captured department/hour/selected-map images under `apps/mobile/build/qa/native/` were visually reviewed; light/dark widget captures are under `apps/mobile/build/qa/`.
- The final `lib/main.dart` development APK was built, installed and launched on the emulator with the local Backend URL and mock emergency dialing. The standalone Dart Detail verifier also parsed the latest contract successfully (PROVIDED/CACHE_HIT, seven departments, eight day rows, not stale). The latest packaged Backend is running on local port 18081.

No production deployment or Git commit was performed. iOS build/device verification remains pending because full Xcode/CocoaPods are unavailable.

## Disease personalization foundation — 2026-09-18

Extensible Backend reference v0.2 contains 16 stable disease IDs and the actual 51 department names, with zero approved mappings. Recording tags work without mappings; separate map-use confirmation and APPROVED+DIRECT client matching are implemented. Dev-only gold overlay augments the native marker; production flag remains OFF. Original DRAFT, hospital Master/NMC rows and migrations are unchanged. Backend 98 tests, Flutter 192 tests and Android member/overlay/map regression passed; NMC delta 0. No production deployment. See [current runbook](disease-personalization-v1.md) and [verification](../qa/disease-foundation-2026-09-18/README.md).
