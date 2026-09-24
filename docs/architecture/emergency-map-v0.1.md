# Emergency Map v0.1 implementation

## Boundaries

Flutter owns permission/GPS/manual selection, native map adaptation and presentation. REST validates coordinates and returns domain projections. EmergencyHospitalService owns geometric search, radius expansion and HPID LEFT JOIN. EmergencyHospitalProvider is the external-data port; NmcEmergencyApiProvider implements regional on-demand refresh. ResourceInterpreter is a domain port whose NMC implementation uses the explicit V13 codebook.

PostgreSQL is the shared cache and authoritative call ledger. No user GPS history is persisted. Straight-line Haversine distances are computed from input coordinates; a future PostGIS repository can replace retrieval without changing REST. The current bounded national catalog is loaded as one repeatable-read snapshot, then geometrically filtered.

## Sources and interpretation

The pinned original PDF determines official semantics. The empirical v0.2 document records observations, including mixed types and absent rows. Older timezone/UI suggestions in that document do not override the approved policy. Codebook entries identify endpoint, original field and aliases, official label, PDF pages and uncertainty. Raw XML and every raw field remain available even if no normalization is allowed.

The MVP only interprets the fields needed for its UI and Master. Future or unknown resource fields are deliberately retained as UNVERIFIED. This is an allowlist, not a claim to implement every field in V13.

`hvec` is the real-time general emergency-bed field. `HVS01/hvs01` is 일반_기준 (UI 일반 기준값). Basic endpoint hv*, hperyn and hpbdn cannot supply either live beds or a missing HVS value. No occupancy/acceptance inference exists.

`sourceRawTimestamp` is always preserved. `parsedSourceTimestamp` has no offset when timezone is unverified; `sourceUpdatedAt` stays null. `fetchedAt`/`lastAttemptAt` are server instants. `sourceFreshness=UNKNOWN` is independent of cache expiry. Unknown timezone cannot be made fresh merely by re-fetching.

## Cache and states

A whole regional batch is promoted only after all pages pass count, pagination and HPID checks. A missing row in a complete batch is LIVE_NOT_PROVIDED. A failed batch does not replace the previous complete batch. A confirmed empty observation supersedes older numeric values, although historical raw snapshots stay stored.

Shared regional leases suppress concurrent duplicate refreshes. Fresh cache hits consume no external budget. Expired regions refresh only on demand; the server never polls all regions. The app has no periodic network timer.

Before every external HTTP attempt, PostgreSQL atomically reserves an endpoint call under an advisory lock. Page calls, retries and discovery count separately. Failed and ambiguous requests count. The rolling 24-hour guard survives restarts and avoids assuming the provider's reset timezone. Daily-cap responses block further calls conservatively. Local rate deferral and budget deferral never become LIVE_ERROR. An active regional search passes one monotonic deadline through LIST validation, pagination and BEDS. On CALL_RATE_LIMIT, admission waits outside the DB transaction until the next ledger slot, only if the deadline leaves room for a normal HTTP attempt; it then calls the same guard again. Rolling quota exhaustion never waits. Search completion/cancellation ends this admission window; no deferred job or client polling is scheduled.

`LIVE_ERROR` describes a real failed refresh, while a previous snapshot may remain in the same response with stale=true. BUDGET_DEFERRED with no snapshot produces LIVE_UNKNOWN and null values. Unknown field codes do not become false, zero or refusal.

## Master and nationwide coverage

A persisted passing discovery result, tied to the PDF hash, is required before synchronization. Nationwide optional filters alone are insufficient. The real discovery report records tested page sizes and actual unique count; an untested maximum remains UNVERIFIED.

Master is published atomically after complete collection. Missing hospitals require two successful complete runs before deactivation; failed runs do not remove hospitals. Unusable coordinates are preserved in Master/raw data but excluded from distance search.

Official administrative reference is data, not executable region-specific branches. Longest whole-address-prefix matching supports hierarchical districts and legacy names. Each region's NMC filter is checked on demand against current Master HPIDs. Single-tier regions remain explicit data; empty subordinate filter behavior must be validated through real responses.

Administrative regions and endpoint request filters are separate. `nmc_region_query_mapping` uses the versioned `nmc/region-query-mappings.json` resource to map general districts to municipality filters for LIST validation. BEDS retains its full city-and-district STAGE2 unless that endpoint has an explicit mapping. Complete LIST validation covers the union of active Master HPIDs in the mapped municipality; sibling districts share that validation. The 2026-09-14 actual measurements are documented in `docs/operations/region-refresh-investigation-2026-09-14.md`.

A failed pre-BEDS mapping/validation is REGION_MAPPING_ERROR with NOT_REQUESTED, not a fabricated LIVE_ERROR. The response retains any previous snapshot. Region refresh Futures remain independent: expiration of the shared deadline cannot discard another region's already completed result. Only an actual attempted refresh failure is classified as LIVE_ERROR; budget/rate deferral stays BUDGET_DEFERRED.

## Public contract and scope

See contracts/openapi/emergency-map-v1.yaml. Search returns all candidates in the effective radius and sorts by center distance then HPID. User distance is nullable. Empty live data never triggers radius expansion; only an empty Master candidate set does.

`GET /api/v1/emergency-hospitals/{hpid}` is a database-only detail projection. It combines the active Master row with the current `hospital_observation` pointer. A confirmed missing realtime row therefore stays `LIVE_NOT_PROVIDED` and cannot resurrect an older snapshot. Detail entry never calls NMC. Master phone values retain their V13 sources: `dutyTel1` is 대표전화1 and `dutyTel3` is 대표전화2.

The basic-info endpoint is collected by an explicit or weekly Backend job behind its own discovery gate and endpoint budget. Immutable static snapshots and a published dataset pointer remain separate from realtime observations. Detail reads the published repository and reports `NOT_REQUESTED` only before collection. Basic-endpoint `hv*` values are not realtime beds, and clinic times are not described as emergency-room operating hours.

Hospital selection remains an HPID boundary. Severe capabilities and messages have domain/storage extension boundaries but no v0.1 network calls or UI. Naver types are isolated inside the map adapter. An absent GPS cannot generate a fabricated current-location marker.
