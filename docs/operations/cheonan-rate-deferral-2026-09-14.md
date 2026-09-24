# 아산·천안 수동 검색의 천안충무병원 갱신 대기

2026-09-14 KST, 실제 개발 DB와 Backend 18081, Android Pixel_10 emulator에서 조사·수정·재검증했다. 이번 실제 외부 호출은 **BEDS 3회**, LIST/Basic 0회, 외부 재시도 0회다. 전화 launcher는 실행하지 않았다.

## 정확한 원인

대상은 **의료법인영서의료재단천안충무병원 / HPID `A2400012`**이다. 아산충무병원 `A2402257`과 구분했다. 원본 주소는 `충청남도 천안시 서북구 다가말3길 8, 충무병원 (쌍용동)`이다.

09:44:21.225의 보류는 **CALL_RATE_LIMIT**, 즉 기존 endpoint별 **초당 2회 제한**이었다. 일일/rolling 예산 부족이나 병원 미제공, region mapping 실패가 아니다. 이전 보고서의 순간 제한과 동일한 유형임을 이번 병원의 DB·실제 로그로 확인했다.

| 대조 항목 | 보류 당시 실제 기록 |
|---|---|
| 행정구역 / cache key | `4413300000`, 충청남도 천안시 서북구 |
| LIST endpoint 요청 | `getEgytListInfoInqire`, Q0=충청남도 / Q1=천안시 |
| LIST 검증 scope | `REGION_CHECK:4413000000` — 동남구/서북구 공통 시 범위. 실시간 cache key와 다름 |
| BEDS endpoint 예정 요청 | `getEmrrmRltmUsefulSckbdInfoInqire`, STAGE1=충청남도 / STAGE2=천안시 서북구 |
| BEDS scope / cache key | `4413300000` |
| coverageStatus / refreshStatus | `LIVE_UNKNOWN / BUDGET_DEFERRED` |
| error / staleReasons | `CALL_RATE_LIMIT` / `[CALL_RATE_LIMIT, NO_SNAPSHOT]` |
| 서북구 마지막 실제 요청 | NULL — guard에서 보류되어 외부 요청하지 않음 |
| 이전 cache / observation snapshot | batch/fetchedAt/observation/snapshot 모두 없음 |
| mapping 검증 | true. LIST는 HTTP 200, NMC 00, 4개 HPID 전체 완료 |

해당 이벤트 직전 1초의 BEDS 슬롯:

| 원장 ID | 실제 요청 시각 KST | 지역 / scope |
|---|---|---|
| 706 | 09:44:20.717639 | 아산시 / `4420000000` |
| 707 | 09:44:21.221422 | 천안시 동남구 / `4413100000` |

서북구 보류 로그는 09:44:21.225이므로 두 요청이 모두 직전 1초 안에 있었다. 보류된 요청에는 원장 예약이나 provider_response가 없다. 서북구 외부 HTTP 실패를 의미하지 않는다.

그 시점 rolling 24시간 사용량은 LIST **30/900**, BEDS **25/900**, Basic **576/900**이었다. BEDS 잔여 예산은 875회였으며 활성 quota block은 없었다. 초당 제한과 24시간 예산을 구분했다. 서버 설정은 `requests-per-second=2`, 자동 endpoint 예산 900, refresh deadline 12초, HTTP timeout 5초였으며 이번 작업에서 높이지 않았다.

증거: [보류 전 DB](../qa/cheonan-rate-deferral-2026-09-14/stored-before.json), [실제 Detail의 보류 상태](../qa/cheonan-rate-deferral-2026-09-14/detail-before.json), [당시 원장·예산 재구성](../qa/cheonan-rate-deferral-2026-09-14/budget-at-event.json), [09:44 실제 로그](../qa/cheonan-rate-deferral-2026-09-14/provider-before.log).

## 자동·수동 해소 경로

기존 `BUDGET_DEFERRED`는 작업 큐에 등록된 상태가 아니었다. Backend는 지역 실시간 정보를 주기적으로 수집하지 않고, Flutter에도 카드 polling이 없다. Detail은 DB 읽기만 한다. 09:44 보류 후 조사 당시 09:54에도 서북구 actual attempt/snapshot은 NULL이었다. **원래는 사용자 검색·지도 재진입·새로고침 등 새 Search 요청이 있어야 재조회한다.**

수정 후에는 진행 중인 Search 요청 안에서만 순간 제한 슬롯을 기다린다.

1. 한 Search의 기존 12초 deadline을 LIST 검증, 페이지 수집, BEDS 요청까지 전달한다.
2. guard가 CALL_RATE_LIMIT를 반환하면 DB 원장에서 다음 슬롯까지의 시간을 계산한다. DB transaction/advisory lock을 보유한 채 대기하지 않는다.
3. 남은 deadline에 대기 시간과 정상 HTTP timeout이 들어갈 때만 잠깐 기다린다. 이후 **동일한 guard에서 다시 원자적으로 예약**한다. 이 admission 확인 자체는 외부 API 호출이 아니다.
4. 호출할 시간이 부족하면 CALL_RATE_LIMIT/BUDGET_DEFERRED를 반환한다. rolling quota 부족(CALL_BUDGET_LIMIT)은 기다리거나 재시도하지 않는다.
5. 이미 완료된 다른 지역 결과는 유지한다. 실제 요청 전 deadline 만료는 REQUEST_NOT_STARTED/NOT_REQUESTED로 구분하며 LIVE_ERROR를 만들지 않는다.
6. Search가 반환되거나 취소되면 이 대기 경로도 끝난다. **반환 후 자동 재개 작업은 여전히 없다.** 이후 해소에는 시간/예산 회복과 새 Search 요청이 필요하다. 무한 재시도, 카드별 polling, guard 우회는 추가하지 않았다. 기존 외부 일시 오류 재시도 상한도 변경하지 않았다.

정리하면 **진행 중인 검색 내 순간 제한은 제한시간 내 자동으로 이어서 처리**, **이미 반환된 보류 상태는 사용자의 재조회가 필요**하다. 이번 기존 보류 건은 저장된 수동 검색으로 지도에 재진입해 재조회했고, 그 검색 안에서는 다른 지역의 순간 제한이 자동으로 이어서 처리됐다.

## 실제 재조회 결과

Android SharedPreferences의 마지막 `manual-search-center`를 읽어 동일 좌표를 사용했다: `36.77728643324964, 127.05919322485317`, MANUAL, 10km. 재설치 후 이 저장 위치를 복원하도록 에뮬레이터 위치 서비스를 일시적으로 껐다가 검증 후 기존 enabled=true로 복구했다. GPS 좌표를 다른 도시로 조작하지 않았다.

10:01:43–10:01:44, 지도에서 발생한 실제 수집:

| 원장 ID | BEDS 지역 | 응답 ID | NMC 결과 | 결과 |
|---|---|---|---|---|
| 710 | 충청남도 / 천안시 서북구 | 707 | HTTP 200 / 00 / NORMAL SERVICE. | totalCount=1, page1/1 완료, HPID A2400012 존재 |
| 711 | 충청남도 / 아산시 | 708 | HTTP 200 / 00 / NORMAL SERVICE. | totalCount=2, page1/1 완료 |
| 712 | 충청남도 / 천안시 동남구 | 709 | HTTP 200 / 00 / NORMAL SERVICE. | totalCount=3, page1/1 완료 |

동남구는 `nmc_rate_wait waitMillis=974` 후 10:01:44.829935에 예약했다. 서북구 최초 예약은 10:01:43.815154로, 세 번째 호출까지 간격은 **1.015초**였다. 세 지역 전체 수집은 약 **1.06초**로 기존 12초 안에 완료됐다. 아산·서북구의 먼저 완료된 결과는 보존됐다. 모든 응답은 numOfRows=100의 한 페이지였고 timeout/parser/page 실패는 없었다.

천안충무병원의 실제 최종 상태:

- `LIVE_AVAILABLE / CACHE_HIT`, error=NULL, stale=false.
- 원천 `hvec=7`, `hvs01=16` → UI 가용병상 **7**, 일반 기준값 **16**.
- lastAttemptAt: **10:01:43.816566 KST**, fetchedAt: **10:01:44.026445 KST**.
- HospitalObservation에 LIVE_AVAILABLE과 실제 snapshot pointer가 저장됐다.
- 제공기관 입력 `20260914095534`는 UI에서 `2026.09.14 09:55 · 시간대 미확인`으로 표시했다.
- 확인용 후속 Search/GET Detail은 cache를 사용했고, 외부 호출 원장 증분은 **0**이었다.

같은 Search에는 아산충무 6, 현대병원 10, 천안충무 7, 순천향대천안 7이 반환됐다. totalCount=4, realtimeStatus=COMPLETE, warnings=[]이며 모두 LIVE_AVAILABLE이다. 병상 값은 검증 시점의 원천 값이다.

증거: [원천 응답·HPID 집합](../qa/cheonan-rate-deferral-2026-09-14/responses-after.json), [DB JOIN](../qa/cheonan-rate-deferral-2026-09-14/stored-after.json), [Search REST](../qa/cheonan-rate-deferral-2026-09-14/search-after.json), [GET Detail](../qa/cheonan-rate-deferral-2026-09-14/detail-after.json), [실제 호출 3회](../qa/cheonan-rate-deferral-2026-09-14/investigation-calls.json), [읽기 검증 호출 증분 0](../qa/cheonan-rate-deferral-2026-09-14/http-verification-ledger.json), [대기·요청 로그](../qa/cheonan-rate-deferral-2026-09-14/provider-after.log).

## UI 수정과 Android 검증

기존 공통 `RealtimeSummary`가 값 없는 본문과 상태 badge에 같은 `갱신 대기`를 각각 렌더링하고 있었다. 중복 본문을 없애 상태는 한 번만 표시하며, 원인과 다음 행동은 별도 문장으로 표시한다. 같은 컴포넌트를 쓰는 목록과 Detail에 동일하게 적용된다.

| 실제 reason | 상태 | 안내 |
|---|---|---|
| CALL_RATE_LIMIT | 갱신 대기 | 요청이 몰려 조회하지 못했습니다. 잠시 후 지도에서 새로고침해 주세요. |
| CALL_BUDGET_LIMIT | 조회 한도 도달 | 최근 24시간 조회 한도로 지금은 갱신할 수 없습니다. 시간이 지난 뒤 지도에서 새로고침해 주세요. |

이전 snapshot이 있을 때만 상태에 `이전 정보`를 덧붙인다. 자동 갱신, 정확한 복구 시각 또는 자정 초기화를 약속하지 않는다. 정상 HPID 미반환은 그대로 `실시간 병상정보 미제공`이며 순간 제한/예산 부족과 혼동하지 않는다.

Android 최신 dev APK의 실제 native 지도와 카드에서 동일 MANUAL 검색의 천안충무병원 상태 및 7/16 표시를 직접 확인했다. [아산 화면](../qa/cheonan-rate-deferral-2026-09-14/android-asan.png), [천안충무 화면](../qa/cheonan-rate-deferral-2026-09-14/android-cheonan.png), [실제 Android semantics](../qa/cheonan-rate-deferral-2026-09-14/android-cheonan.xml). 보류 원인별 문구와 중복 제거는 fixture widget 회귀 테스트로 별도 검증했으며, 실제 DB를 강제로 보류 상태로 바꾸지 않았다.

## 회귀 검증 및 수정 파일

Backend **60 tests passed**, Flutter **81 tests passed**, Flutter analyze **No issues**, premium strict audit 0 findings. [검증 결과](../qa/cheonan-rate-deferral-2026-09-14/verification.txt). Backend fixture HTTP와 파괴적 DB 테스트는 격리된 `eroute_test`만 사용했다. fixture 테스트에서 NMC를 호출하지 않았다.

추가/강화한 회귀:

- 세 지역 cache가 동시에 만료: 실제 PostgreSQL guard를 초당 2회로 실행, 세 번째 슬롯 대기, 한 Search에서 모두 완료, 모든 1초 구간의 예약 수 ≤2, 이어진 cache hit 추가 호출 0.
- rolling 예산 100/100 사용: 대기 없이 BUDGET_DEFERRED, 외부 요청 0, 이전 snapshot 14 보존.
- deadline 잔여 부족: CALL_RATE_LIMIT 반환 후 슬롯이 풀려도 자동 호출 0; 명시적 재조회 시에만 1회.
- admission 전 deadline 만료: NOT_REQUESTED/LIVE_UNKNOWN, 외부 요청 0, Detail 일치.
- 기존 정상 응답 HPID 미반환 → NOT_PROVIDED, 부분 pagination 실패, 한 지역 실패/다른 지역 정상, 완료된 다른 지역의 공유 deadline 독립성 테스트도 재실행했다.
- Flutter에서 순간 제한/24시간 예산 및 snapshot 유무를 교차 검증: 상태 1개, 원인 안내 1개, 수동 새로고침 안내, 내부 코드/자동 약속 노출 없음.

수정 파일:

- `services/backend/src/main/java/com/eroute/emergency/infrastructure/nmc/NmcCallBudgetGuard.java`: 다음 초당 슬롯 시각 계산. 기존 예약 한도·원장·잠금 규칙 유지.
- 같은 디렉터리의 `NmcApiClient.java`, `NmcPageCollector.java`, `NmcRegionResolver.java`, `NmcEmergencyApiProvider.java`: deadline 전달과 제한된 rate admission, 미호출 분류.
- `services/backend/src/main/java/com/eroute/emergency/domain/port/EmergencyHospitalProvider.java`, `.../application/EmergencyHospitalService.java`: 공유 deadline 전달.
- `.../infrastructure/persistence/JdbcHospitalStore.java`: 미시작 상태의 Detail 일치.
- `apps/mobile/lib/features/emergency_map/domain/hospital_summary.dart`, `.../presentation/widgets/realtime_summary.dart`: 원인별 안내와 중복 제거.
- `services/backend/src/test/java/com/eroute/RegionRealtimeIntegrationTest.java`, `EmergencyHospitalServiceTest.java`, `apps/mobile/test/emergency_map_test.dart`: 회귀 테스트.
- `UX-CONTRACT.md`, `docs/architecture/emergency-map-v0.1.md`, `docs/operations/runbook.md`, 본 보고서와 QA 증거.
