# 파주·고양 실시간 병상 갱신 오류 조사 및 수정

검증일: 2026-09-14 KST. 실행 환경: PostgreSQL `127.0.0.1:55432/eroute`, Backend `127.0.0.1:18081`, Android Pixel_10 emulator / `com.eroute.eroute_mobile` dev APK. 배경 동기화는 비활성화한 상태로 조사했다. 로그인·HIRA·길찾기·추천 등 신규 기능은 추가하지 않았다.

## 판정

**고양 주소에서 일반구만 잘라낸 문제가 아니었다.** 기존 resolver는 일산백병원을 `경기도 / 고양시 일산서구`, 일산복음병원을 `경기도 / 고양시 일산동구`로 해석했다. 문제는 이 문자열을 **다른 endpoint의 LIST 사전 검증에도 그대로 사용**한 것이었다.

`getEgytListInfoInqire`의 `Q1=고양시 일산동구/일산서구`는 HTTP 200, NMC `00 / NORMAL SERVICE.`, totalCount=0으로 정상 완료되었다. 이 결과로 Master HPID 검증이 실패해 `REGION_UNVERIFIED`가 발생했다. 실제 BEDS 호출은 실행되지 않았고 `last_attempt_at`도 NULL이었다. 그런데 provider가 이를 `Refresh.ERROR`로 반환하여 REST `LIVE_ERROR`와 Flutter `갱신 실패`가 만들어졌다.

반면 실측한 BEDS `getEmrrmRltmUsefulSckbdInfoInqire`는 **`STAGE2=고양시 일산동구/일산서구`를 정상 지원**했다. LIST 검증에는 `Q1=고양시`가 유효했다. 따라서 BEDS를 무조건 시 단위로 합치거나 병원별 예외를 넣지 않고, endpoint별 요청 지역 매핑을 분리했다.

## 원래 요청과 공식 명세 확인

저장된 DB와 provider_response를 먼저 조사했다. [수정 전 증거](../qa/region-refresh-2026-09-14/stored-before.json), [수정 전 Detail](../qa/region-refresh-2026-09-14/detail-before.json).

| 재현 기관 | 원본 주소 | 행정구역 ID / 해석 | 기존 LIST 검증 | BEDS 예정 STAGE1 / STAGE2 |
|---|---|---|---|---|
| 메디인병원 | 경기도 파주시 금릉역로 190(금촌동) | 4148000000 / 경기도 파주시 | 검증 완료 | 경기도 / 파주시 |
| 인제대학교일산백병원 | 경기도 고양시 일산서구 주화로 170 (대화동) | 4128700000 / 경기도 고양시 일산서구 | Q0=경기도, Q1=고양시 일산서구 → 0건 | 경기도 / 고양시 일산서구 — 당시 미호출 |
| 의료법인일산복음병원 | 경기도 고양시 일산동구 고양대로 760, 가동 (중산동, 일산복음병원) | 4128500000 / 경기도 고양시 일산동구 | Q0=경기도, Q1=고양시 일산동구 → 0건 | 경기도 / 고양시 일산동구 — 당시 미호출 |

실패 당시 provider_response 674/676은 각각 동구/서구 LIST 검증이며, 모두 HTTP 200, NMC 00, totalCount=0, pageNo=1, numOfRows=100이다. 파주 BEDS response 675는 동일하게 정상 응답하면서 HPID 2개를 반환했다. **실패한 BEDS 요청의 STAGE 값은 없다. 사전 검증에서 차단되었기 때문이다.**

저장된 공식 V13 PDF의 요청 표를 실제 렌더링하여 읽고 `scripts/verify_sources.py`의 해시 검증을 통과했다. V13 p14는 BEDS STAGE1=시도/STAGE2=시군구, p24는 LIST Q0/Q1 필터를 설명하며 서울특별시/강남구를 예시로 든다. 일반구 도시에서 두 endpoint의 문자열 호환성이 같다는 보장은 명세에 없다. 아래 실측 결과를 별도로 근거로 사용했다. [공식 V13 원문](../references/NIA-IFT-OpenAPI활용가이드-01.국립중앙의료원-응급의료정보조회서비스_V13.pdf).

## 제한된 실제 API 실측

모든 호출은 실제 Java `NmcApiClient` → `NmcCallBudgetGuard`를 통과했다. URL·인증키는 증거와 로그에 기록하지 않았다. 아래 모든 응답은 **HTTP 200, resultCode=00, resultMsg=NORMAL SERVICE., pageNo=1, numOfRows=100, 전체 수집 완료**였다. timeout/parser/page collection 실패는 없었다. returned HPID 전체 집합은 [실측 응답](../qa/region-refresh-2026-09-14/responses-after.json)에 기록했다.

| STAGE1 또는 Q0 | STAGE2 또는 Q1 | LIST totalCount | BEDS totalCount | response ID |
|---|---|---:|---:|---|
| 경기도 | 고양시 | 8 | 7 | 677, 678 |
| 경기도 | 고양시 일산서구 | 기존 0 | 1 | 기존 676, 실측 687 |
| 경기도 | 고양시 일산동구 | 기존 0 | 4 | 기존 674, 실측 688 |
| 경기도 | 파주시 | 기존 검증 사용 | 2 | 689 |
| 경기도 | 성남시 | 9 | 7 | 679, 680 |
| 경기도 | 수원시 | 9 | 7 | 681, 682 |
| 경기도 | 용인시 | 5 | 5 | 683, 684 |
| 충청북도 | 청주시 | 9 | 6 | 685, 686 |
| 경기도 | 성남시 분당구 | — | 4 | 694 |
| 경기도 | 수원시 영통구 | — | 1 | 695 |
| 경기도 | 용인시 기흥구 | — | 2 | 696 |
| 충청북도 | 청주시 상당구 | — | 2 | 697 |

고양시 LIST 8개 HPID 중 `A2100283`(일산복음)만 시 전체 BEDS 7개 집합에 없었다. 동구 BEDS 4개 집합에도 없었다. 일산백 `A2100038`은 서구 BEDS 1개 집합에 존재했다. 일산복음의 미반환은 이 시점의 provider 제공 상태이며, 병상 0개나 병원 비운영을 뜻하지 않는다.

## 수정한 데이터 흐름과 상태

1. 후보 병원은 기존 Master에서 선택하며 원본 주소와 공식 행정구역 ID를 보존한다. 주소 resolver의 가장 긴 전체 prefix 매칭을 유지한다.
2. 새 `nmc_region_query_mapping`에서 **endpoint + administrative region ID → request region ID**를 조회한다. LIST 검증은 일반구의 상위 시 필터를 사용한다. BEDS 별칭이 없으면 원래 일반구 STAGE1/STAGE2를 그대로 사용한다.
3. `region-query-mappings.json`에 공식 참조에서 도출한 일반구 매핑 74개를 버전 데이터로 관리한다. 고양·성남·수원·용인·청주 및 다른 일반구 도시를 같은 로직으로 처리한다. 기존/폐지 주소 prefix 모두 참조 데이터에 포함된다. 병원명/HPID에 따른 production 분기는 없다.
4. 시 단위 LIST가 모든 페이지를 정상 수집하고 해당 시에 매핑된 활성 Master HPID를 포함해야 검증 완료 처리한다. 형제 일반구 검증은 같은 시 범위로 합쳐 중복 호출을 줄인다. 이번에는 고양시 LIST 8개로 검증했고 BEDS는 동구/서구 별도로 수집했다.
5. 완성된 BEDS 배치만 해당 행정구역의 cache/observation에 반영한다. HPID LEFT JOIN에서 row가 없으면 `LIVE_NOT_PROVIDED`, 있으면 `LIVE_AVAILABLE`이다. 부분 페이지는 게시하지 않는다.
6. BEDS 미호출 상태의 검증·매핑 문제는 `REGION_MAPPING_ERROR`, `NOT_REQUESTED`로 기록한다. 기존 DB의 REGION_UNVERIFIED/REGION_UNRESOLVED도 Detail에서 같은 의미로 해석한다. 실제 BEDS 수집 실패만 `LIVE_ERROR`가 된다.
7. 추가 발견한 공유 deadline 문제도 수정했다. 앞 지역의 지연으로 deadline이 지나더라도 다른 지역의 이미 완료된 Future 결과는 정상 반영한다. 외부 요청 여부를 확인해 미호출을 LIVE_ERROR로 만들지 않는다.

전국 74개를 모두 실측했다고 주장하지 않는다. 이번 실측은 위 다섯 일반구 도시와 파주이며, 나머지 데이터 매핑은 실행 시 동일한 Master coverage 검증을 통과해야 사용할 수 있다.

| 서버 상태 | 사용자 표시 / 데이터 처리 |
|---|---|
| LIVE_AVAILABLE | 실시간 정보 제공, 실제 숫자 표시. 실제 0도 0으로 유지 |
| LIVE_NOT_PROVIDED | 실시간 병상정보 미제공 |
| LIVE_ERROR | 갱신 실패; 마지막 정상 snapshot이 있으면 이전 정보와 함께 유지 |
| LIVE_UNKNOWN | 미조회·미확정 상태를 오류/0으로 바꾸지 않음 |
| BUDGET_DEFERRED | 갱신 대기; snapshot이 있을 때만 이전 정보 표시 |
| REGION_MAPPING_ERROR | 실시간 정보를 불러오지 못했습니다. 내부 코드는 서버 오류 필드와 안전한 로그에 유지 |

## 수정 후 DB → REST → Android

기존 재현 위치(37.722073, 126.736478), 반경 10km를 유지했다. 동일 검색에 파주 2개와 고양 6개가 포함됐다. 09:34–09:35 수집 및 Android 화면 기준:

| 기관 / HPID | 행정구역 BEDS 응답 | DB observation | snapshot ID | GET/Search 가용병상 | Android 표시 |
|---|---|---|---:|---:|---|
| 메디인 / A2100131 | 파주 response 698, total2 | LIVE_AVAILABLE | 45 | 8 | 실시간 정보 제공 / 8 |
| 파주병원 / A2100035 | 파주 response 698, total2 | LIVE_AVAILABLE | 43 | 10 | 실시간 정보 제공 / 10 |
| 일산백 / A2100038 | 서구 response 699, total1 | LIVE_AVAILABLE | 44 | 21 | 실시간 정보 제공 / 21 |
| 일산복음 / A2100283 | 동구 response 700, total4, 해당 HPID 없음 | LIVE_NOT_PROVIDED | NULL | NULL | 실시간 병상정보 미제공 |

국립암센터 0, 동국대일산 12, 일산차 4, 국민건강보험공단일산 5도 각각 LIVE_AVAILABLE이었다. 최종 Search는 COMPLETE, totalCount=8, warnings=[]이며 모든 error가 NULL이다. 시점별 병상 수 변동은 정상이며, 최초 수정 직후 일산백 22에서 Android 재검증 시 21로 변했다.

증거:

- [원본 주소·endpoint 매핑·cache·HPID observation/snapshot JOIN](../qa/region-refresh-2026-09-14/stored-after.json)
- [최종 Search REST](../qa/region-refresh-2026-09-14/search-final.json)
- 실제 GET Detail: [메디인](../qa/region-refresh-2026-09-14/detail-A2100131.json), [파주병원](../qa/region-refresh-2026-09-14/detail-A2100035.json), [일산백](../qa/region-refresh-2026-09-14/detail-A2100038.json), [일산복음](../qa/region-refresh-2026-09-14/detail-A2100283.json)
- Android 실제 native 지도/일반 앱 APK: [파주 카드](../qa/region-refresh-2026-09-14/android-paju.png), [일산백 카드](../qa/region-refresh-2026-09-14/android-goyang.png), [일산백과 일산복음 동시 표시](../qa/region-refresh-2026-09-14/android-not-provided.png)
- [같은 목록의 파주·일산백·일산복음 Android semantics](../qa/region-refresh-2026-09-14/android-not-provided.xml): REST 상태와 대조하여 확인. 앱은 실제 서버 `10.0.2.2:18081`을 사용했다. 전화/길찾기는 실행하지 않았다.

에뮬레이터의 저장 snapshot 복구가 멈춰 cold boot 후 최신 APK를 재설치했다. 정상 앱 화면을 직접 확인했으며 자동 fixture 결과를 실제 provider 결과로 대체 보고하지 않았다.

## 호출 예산과 실패 독립성

조사 전 ledger 마지막 ID는 679였다. 조사 종료 ID 703까지 **24회**: LIST 6회, BEDS 18회, 모두 SUCCESS. 명시적 실측 17회와 수정 후 실제 검색/Android 수집 7회이며 재시도는 없었다. Basic endpoint 추가 호출은 0회, 기존 총 576회 그대로다. [호출 원장](../qa/region-refresh-2026-09-14/call-budget.json).

세 지역의 TTL이 동시에 만료되면 기존 endpoint 초당 2회 제한 때문에 한 지역은 CALL_RATE_LIMIT/BUDGET_DEFERRED가 될 수 있다. 최초 검증에서는 서구, Android 새로고침에서는 동구가 보류됐다. 그 지역의 외부 요청은 하지 않았고 다른 두 지역 결과는 정상 유지했다. 이어진 수동 새로고침은 신선한 두 지역 cache를 재사용하고 대기 지역만 수집했다. 예산/TTL/초당 제한과 호출 원장은 변경하거나 지우지 않았다. [보류가 포함된 실제 응답](../qa/region-refresh-2026-09-14/search-after.json), [안전한 provider 로그](../qa/region-refresh-2026-09-14/safe-provider.log).

## 회귀 테스트

Backend `mvn verify`: **56 passed, 0 failures/errors/skips**. PostgreSQL 통합 테스트는 격리된 `eroute_test` DB와 로컬 fixture HTTP server를 사용했다. 실제 NMC 호출은 하지 않는다. Flutter test: **80 passed**. Flutter analyze: **No issues found**. 공식 출처 해시 검증 통과, premium strict audit 0 findings. [검증 결과](../qa/region-refresh-2026-09-14/verification.txt).

`RegionRealtimeIntegrationTest`에 다음 8개를 추가했다.

- 단순 군 + 시/일반구가 같은 경계 검색에 존재: LIST 시 필터 1회, BEDS는 각각 행정구역 필터, 실제 0 유지.
- 한 지역 HTTP 실패 + 다른 지역 정상: 오류 전파 없음, Detail도 일치.
- 정상 전체 응답에 특정 HPID 없음: NOT_PROVIDED.
- pagination 일부 실패: 배치/미제공 observation 게시 금지.
- budget deferred: 외부 BEDS 0회, UNKNOWN, attemptedAt NULL.
- 이전 정상 snapshot + 현재 실패: 숫자 보존, error/stale 표시.
- 정상 빈 LIST 검증: mapping error/UNKNOWN, BEDS 미호출.
- 전국 일반구 데이터 매핑과 요청된 예시 도시들의 prefix/대상 확인.

`EmergencyHospitalServiceTest`에는 앞 지역이 공유 deadline을 소진해도 완료된 다른 지역 결과를 유지하는 테스트를 추가했다. Flutter 위젯 테스트에는 실제 0, 미제공, 오류+이전 정보, snapshot 없는 갱신 대기, 매핑 오류의 일반 사용자 문구를 검증했다.

## 수정 파일

- `services/backend/src/main/java/com/eroute/emergency/infrastructure/nmc/NmcRegionResolver.java`: endpoint 매핑과 공동 LIST 검증.
- `services/backend/src/main/java/com/eroute/emergency/infrastructure/nmc/NmcEmergencyApiProvider.java`: 요청 지역 분리와 미호출/실패/보류 분류.
- `services/backend/src/main/java/com/eroute/emergency/infrastructure/nmc/NmcApiClient.java`: 키를 제외한 요청 파라미터·HTTP·NMC 페이지·실패 로그.
- `services/backend/src/main/java/com/eroute/emergency/infrastructure/persistence/JdbcHospitalStore.java`: Detail의 기존 mapping 오류 상태 해석.
- `services/backend/src/main/java/com/eroute/emergency/application/EmergencyHospitalService.java`: 지역별 완료 결과 보존, 요청 여부와 freshness 분류.
- `services/backend/src/main/java/com/eroute/emergency/application/HospitalDetailService.java`: 매핑 미확정 오류 코드 일치.
- `services/backend/src/main/java/db/migration/V5__endpoint_region_mapping.java`: endpoint 매핑 테이블 및 기존 데이터 마이그레이션. 실제 DB 적용 완료.
- `services/backend/src/main/resources/nmc/region-query-mappings.json`, `scripts/import_regions.py`: 버전 매핑 데이터와 초기/갱신 import.
- `apps/mobile/lib/features/emergency_map/domain/hospital_summary.dart`: 보류/매핑 오류 카드 문구.
- `services/backend/src/test/java/com/eroute/RegionRealtimeIntegrationTest.java`, `services/backend/src/test/java/com/eroute/EmergencyHospitalServiceTest.java`, `apps/mobile/test/emergency_map_test.dart`: 회귀 테스트.
- `UX-CONTRACT.md`, `docs/architecture/emergency-map-v0.1.md`, `docs/operations/runbook.md`, 본 보고서와 QA 증거.
