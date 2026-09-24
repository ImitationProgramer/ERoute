# Basic Info 최종 사용자 검증 — 2026-09-14

실제 로컬 서버 `http://127.0.0.1:18081`, PostgreSQL `127.0.0.1:55432/eroute`, Android `emulator-5554`에서 검증했다. 테스트 종료 후 일반 dev 앱을 01:39 KST에 새로 설치하고 실제 GPS 검색 → 메디인병원 → 진료 정보 화면을 다시 확인했다. 최종 앱은 실행 상태로 남겨 두었다.

## 1. 최신 discovery와 최종 수집 전략

- 이번에 `python3 scripts/run_backend.py --discover-basic` 실행: discovery **7**, `PASSED`, **NATIONWIDE(bulk)**, page size **100**.
- 529 unique HPID = 현재 active Master 529개. missing/extra HPID 없음. 6페이지·종료 페이지·첫 페이지 반복·10/100/500/1000 요청 크기 검증. 17회 호출 모두 성공.
- 과거 discovery 6은 Master 530개 중 Basic이 529개여서 PER_HPID였다. 이후 정상 Master 갱신에서 `A1500078`이 inactive가 돼 이번에는 bulk가 통과했다. 이 검증에서 Master나 discovery 결과를 수동 조작하지 않았다.

## 2. 이번 실제 Basic sync 및 게시

`python3 scripts/run_backend.py --sync-basic`를 실행해 **2026-09-14 01:37:12 KST COMPLETE**를 확인했다.

- 새 dataset: `e32ce259-b8d8-432b-8612-eaa36402f5b6`
- 이전 dataset: `4e4277c5-312c-41df-b468-5837fbd85a6b`
- 작업 6개 모두 SUCCESS, 호출 6회, 재시도 0회.
- 529개 published member / 529 snapshots / normalized department 8,233행 / operating hours 4,232행(기관당 8행).
- raw department text는 513개 기관에 존재한다. 원천에서 진료과가 없는 16개를 임의로 채우지 않았다.
- 이번 discovery + sync = 23회. Basic ledger 553 → 576으로 기존 900회 rolling budget 안에서 완료했다.

## 3–4. 여러 기관의 DB와 실제 GET 응답 비교

active Master의 HPID 접두어별 최소 HPID와 요청한 메디인병원을 선택해 **26개 기관**을 검증했다. 비교 항목은 `raw_department_text` ↔ `departmentsRaw`, 정규화 진료과 이름·상태, 8일별 open/close/status, `datasetVersion`이다. 모두 실제 `GET /api/v1/emergency-hospitals/{hpid}`와 일치했다.

| 기관 | HPID | raw_department_text | 정규화 진료과 | 진료시간 행 | dataset |
|---|---|---|---:|---:|---|
| 메디인병원 | A2100131 | 저장됨 | 10 | 8 | e32ce259… |
| 화천군보건의료원 | E2200025 | 저장됨 | 6 | 8 | e32ce259… |
| 단양군보건의료원 | E2300011 | 저장됨 | 10 | 8 | e32ce259… |
| 경희대학교병원 | A1100001 | 저장됨 | 25 | 8 | e32ce259… |
| 인제대학교부산백병원 | A1200001 | 저장됨 | 28 | 8 | e32ce259… |

메디인병원 원문은 `내과,마취통증의학과,비뇨의학과,산부인과,신경과,신경외과,영상의학과,외과,정형외과,진단검사의학과`이다. 정규화 10행이 같은 순서로 저장·응답된다. 월~금 09:00–18:00, 토 09:00–13:00, 일/공휴일은 MISSING이다.

26개 기관의 원문·정규화 행·요일·version·discovery·sync 데이터는 [evidence.json](../qa/basic-info-2026-09-14/evidence.json), 대표 실제 응답은 [메디인병원](../qa/basic-info-2026-09-14/A2100131.json), [화천군보건의료원](../qa/basic-info-2026-09-14/E2200025.json), [단양군보건의료원](../qa/basic-info-2026-09-14/E2300011.json)에 보관했다.

## 5. Android 진료 정보 탭

메디인병원·화천군보건의료원·단양군보건의료원의 실제 HTTP Detail로 production repository/parser/state/widget 경로를 검증했다. 테스트 검색과 위치만 주입하며 병원 상세 데이터는 실제 서버에서 받는다. 진료과목과 월~공휴일 8행, 제공된 시간 또는 `정보 미제공`, 원천의 병원 진료시간 설명이 표시됐다. 탭·Back 이동 후 검색 snapshot과 선택도 유지된다.

- [메디인 진료과](../qa/basic-info-2026-09-14/eroute-clinical-departments-A2100131.png), [메디인 시간](../qa/basic-info-2026-09-14/eroute-clinical-hours-A2100131.png)
- [화천 진료시간](../qa/basic-info-2026-09-14/eroute-clinical-hours-E2200025.png), [단양 진료시간](../qa/basic-info-2026-09-14/eroute-clinical-hours-E2300011.png)
- 마지막 일반 앱에서도 실제 8개 병원 GPS 검색 후 진입해 [메디인 진료시간](../qa/basic-info-2026-09-14/clinical-hours-after.png)을 확인했다.

## 6. 고정 안내 문구의 정확한 원인

문제 발생 중 메디인 API는 `fetchStatus=SUCCESS`, `dataStatus=PROVIDED`, `refreshStatus=CACHE_HIT`, `departmentsStatus=KNOWN`, 진료과 10개/시간 8행이었다. **NOT_COLLECTED / NOT_PROVIDED / ERROR 어느 상태도 아니다. 데이터가 있는데 UI가 고정 placeholder를 표시하는 실행 앱 연결 버그**로 판정했다.

검증 시작 시 설치 APK의 lastUpdateTime은 2026-09-13 01:30:47이었다. 최신 소스의 `HospitalClinicalInformation`과 formatter/selected-only caption 구현이 그 APK에 반영되지 않았다. [수정 전 UI dump](../qa/basic-info-2026-09-14/detail-before.xml)에는 고정 문구와 raw timestamp가 함께 남아 있다. 최신 dev APK 설치 후 [실제 UI dump](../qa/basic-info-2026-09-14/clinical-after.xml)에서 진료정보가 연결되고 문구가 사라졌다. 현재 소스에 중복 DTO 변환이나 임의 데이터 보정은 추가하지 않았다.

원천에서 특정 요일이 없는 것은 해당 필드의 `MISSING`이며 화면은 `정보 미제공`으로 표시한다. 기관 전체 미수집이나 수집 실패와 혼동하지 않는다.

## 7. 지도 이름 겹침과 native overlay

[수정 전 실제 지도](../qa/basic-info-2026-09-14/map-before.png)의 십자 마커 아래 겹치는 병원명은 **ERoute marker caption**이다. 같은 지역·반경·8개 실제 병원을 표시한 [새 일반 앱 지도](../qa/basic-info-2026-09-14/map-after.png)에서 모든 미선택 병원 caption이 사라지고 Naver basemap의 파주시/고양시·도로·IC·공항 POI는 유지된다.

현재 adapter의 `NOverlayCaption(text: '')`는 flutter_naver_map 1.4.4 Android `OverlayController.setCaption` → Naver Marker `setCaptionText` 경로로 빈 문자열을 보낸다. `null`은 Android handler에서 강제 역참조하므로 사용하지 않는다. 기존 수정이 새 APK에 실제 적용됐음을 확인했다.

40개 fixture 마커를 실제 native Naver 지도에 올리고 선택 없음 → DENSE-0 → DENSE-1 전환을 검증했다. [미선택](../qa/basic-info-2026-09-14/eroute-dense-unselected.png), [DENSE-0 선택](../qa/basic-info-2026-09-14/eroute-dense-selected-DENSE-0.png), [DENSE-1 선택](../qa/basic-info-2026-09-14/eroute-dense-selected-DENSE-1.png)에서 이전 caption 제거와 새 caption 하나만 남음을 시각 확인했다. Dart 상태 검사만으로 통과시키지 않고 native 렌더링 대기 후 캡처했다. 지도 이동·검색·병원 Detail 진입은 선택 자체로 발생하지 않는다.

## 8. 사용자 timestamp 표시

수정 전 `20260914012533` 노출을 실제 UI dump에서 재현했다. 새 앱은 `RealtimeSummary`의 공통 formatter로 Backend `parsedSourceTimestamp`를 `2026.09.14 01:25` 형식으로 표시한다. 원천 시각은 시간대를 추정 변환하지 않고 `시간대 미확인`을 붙이며 ERoute 조회시각과 구별한다. 원문은 API 감사 데이터에만 남는다.

[Android 시간 표시](../qa/basic-info-2026-09-14/eroute-detail-time-A2100131.png)는 이후 원천 갱신값인 `2026.09.14 01:30`을 표시한다. 테스트는 실제 파싱된 시각의 formatter 결과와 화면을 비교하고 14자리 timestamp 텍스트가 없음을 확인한다. 일반 앱 재설치 후 지도·상세에서도 human-readable 표시를 확인했다.

## 실행 검증 및 변경 범위

- `flutter analyze`: 문제 없음.
- `flutter test`: 79개 통과.
- Android native integration: 4개 통과(지도 1 + 실제 기관 3). [로그](../qa/basic-info-2026-09-14/integration.log)
- DB/API 대조 및 두 번째 native integration 전후 모든 NMC endpoint ledger 차이 0. 일반 앱 GPS 검색은 별도 실시간 조회 흐름으로 실행했다.
- Premium strict audit: 오류·경고 0. [결과](../qa/basic-info-2026-09-14/premium-audit.json)
- `DETAIL_SMOKE_HPIDS` 복수 기관 검증, 월~공휴일/formatter assertion, native caption 전환 스크린샷과 렌더링 대기를 추가했다. 최신 discovery 결과와 테스트 후 일반 앱 설치 절차를 runbook에 기록했다.
- 제품 동작 수정은 기존 소스에 이미 존재했으며, 이번에는 이를 최신 일반 APK로 빌드·설치해 사용자 환경에 반영했다.
- HIRA·로그인·길찾기·기저질환 기능 추가 없음. 원천 미제공 시간을 휴진·24시간·응급실 운영시간으로 추정하지 않았다.
