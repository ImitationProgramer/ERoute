# 질환 개인화 v1 — 확장 가능한 기준정보와 기록·활용 분리

2026-09-18 구현. 기능 구현과 의료 관계 승인, production 공개를 분리한다. 현재 승인 관계는 **0개**이며 정상 상태다. `publicDiseaseMapEnabled=false`; production 공개/배포는 수행하지 않는다. 의료 관계·출처·검수자·승인을 자동 생성하지 않는다.

## 기준정보와 현재 데이터

### v0.5 development runtime 전환 완료 — 2026-09-19

사용자가 제공한 공식 source matrix SHA `309eacdbb321c63883ee88ef589a35e78fdd80454c87ff3f66874ed41a874eee`를 검증했고, 사용자 batch sign-off를 HUMAN_SOURCE_REVIEW로 기록했다. 사용자가 허용한 실행 시점 시스템 UTC `2026-09-19T05:47:57Z`를 checkedAt으로 사용했다. 원본 matrix는 보존하고 reviewed 파생본에 humanCheckedAtUtc/checkedAt과 provenance를 남겼으며 researchVerifiedAtUtc를 복사하지 않았다. Immutable v0.5는 evidence complete 61/61, EXACT_CANONICAL 36/BROAD_PARENT 25, version=2, DRAFT 61/approval=null/APPROVED 0이다. Runtime Evidence schema는 확장하지 않고 source provenance를 notes에 기록했다.

기존 stale referenceVersion integration helper를 실제 주입된 runtimeReference 기반으로 수정했다. 서버 409 validation은 유지하며 stale v0.4 요청 거절/현재 runtime 요청 정상 저장 테스트를 추가했다. Backend 120/120, Flutter 220 PASS/기존 조건부 skip 1/analyze, preview filled 6/hollow 30/none 25 및 46×51 matcher 회귀, Android 대표 2 tests가 통과했다. [최신 runtime 검증](../qa/disease-evidence-v05-2026-09-19/runtime-transition/README.md)을 참고한다.

일반 앱은 기존 RemoteDiseaseDataRepository의 실제 reference API를 그대로 사용한다. production 기본 DiseaseReference.RESOURCE는 v0.4이며, development-auth artifact의 local/test에서 primary인 DevelopmentDiseaseReference.RESOURCE는 v0.5다. 실행 중인 격리 개발 backend의 public API와 앱 repository에서 document.datasetVersion=v0.5를 확인했다. 실제 DB/NMC/HIRA 변경이나 production 배포는 없었다.

MVP evidence staging은 종료했다. APPROVED=0/production flag OFF를 유지하고, 별도 approval version·추가 의료 승인 workflow·거버넌스 확장은 진행하지 않는다. 의료전문가 검수/production release가 실제 필요한 시점에만 다시 연다. 다음 작업은 실제 앱의 ‘내 응급정보 → 질환 → 관련 진료과 → 병원 탐색’ 기능 개발이다.

v0.5에는 사용자 지정 mappingScope만 사용했다: EXACT_CANONICAL 36개, BROAD_PARENT 25개. EXACT는 disease evidence의 공식 진료과 원문에 canonical이 직접 등장하는 관계다. BROAD_PARENT는 disease evidence와 별도의 공식 parent hierarchy evidence를 함께 기록한다. 서울대학교병원 내과 조직 자료의 실제 URL·사람 확인 UTC instant·원문이 필요하며, 코드가 분과/부모 관계를 추론하지 않는다. 같은 출처가 여러 관계를 지원해도 각 mapping 안에 evidence record를 명시한다.

BROAD_PARENT notes에는 세부 내과→ERoute broad 내과 crosswalk을 검수한 관계임을 기록하고, 내과 존재가 실제 질환 진료를 보장하지 않으며 현재 환자 수용 가능성이나 추천/적합성 점수를 의미하지 않음을 보존한다. rawDepartmentText는 공식 원문 그대로, checkedAt은 사람이 source를 확인한 실제 UTC instant만 기록한다. 누락 자료를 검색·추측·현재 시각으로 보완하지 않는다.

evidence 또는 mappingScope를 반영한 관계는 새 immutable v0.5에서 mapping.version을 증가시키고 DRAFT/approval=null을 유지한다. ID/endpoint/catalog/vocabulary/purposeVersion과 v0.4 bytes는 보존한다. `--previous v0.4.json` 검증 및 기존 development reviewClass adapter 회귀를 통과한 뒤 실제 runtime loader를 전환한다. 현재 reviewClass(EXACT 6/미확정 30/BROAD 25)를 새 scope(EXACT 36/BROAD 25)로 대체하여 marker 표시를 바꾸지 않는다. 이후 별도 approval version에서 동일 내용에 대한 사람 승인을 검토하며 staging 완료 자체는 승인이 아니다. Production flag는 OFF를 유지한다.

Backend reference가 단일 source of truth다. 현재 development-auth local/test는 `services/backend/src/main/resources/reference/disease-departments/v0.5.json`, production 기본은 보존된 v0.4를 사용한다. disease catalog(2026-09-18 Batch 2 기준 활성 46개), department catalog(실측 51종), mappings, departmentAliases를 분리한다. Flutter 기준정보 asset은 없다. `ReferenceData` / `ReferenceValidator` / `ReferenceRepository`는 파일 저장 형식과 독립적이며 `FileReferenceRepository`가 JSON adapter다. 향후 관리자 UI/DB adapter도 동일 검증기를 사용해야 한다.

D001–D016 안정 ID는 초기 seed다. D017 이상을 추가해도 코드를 수정할 필요가 없다. displayName/aliases/category/active/lifecycleStatus/version을 관리하며 삭제 대신 INACTIVE/RETIRED를 사용한다. RETIRED ID 재사용·재활성화, 기존 ID 누락, 별칭 충돌을 거부한다. INACTIVE 항목은 새 선택에서 제외하되 기존 건강기록에는 남길 수 있다.

진료과 ID는 실제 저장 이름을 가리킨다. NMC `dgidIdName` → snapshot `raw_department_text` → `hospital_department` raw/name/source/status를 변경하지 않는다. 현재 canonical 이름 51개는 실측 literal vocabulary다. 이름 정리는 회원 matcher에서 NFC/양끝 공백만 적용한다. 유사 명칭을 병합하거나 내과에서 호흡기내과를 추론하지 않는다.

이전 `v0.1.json`의 30개 DRAFT 관계와 원본 evidence는 **파일 그대로 보존**한다. 과거 17종 진료과와 실측 51종이 다르므로 기존 관계를 자동 치환하지 않는다. v0.2의 빈 mappings는 원본 그대로 보존한다. v0.3의 사용자 제공 DRAFT 후보 43개를 그대로 보존하고, v0.4에는 D001–D016의 현행 vocabulary 기준 후보 18개를 추가했다. 전체 DRAFT 61개이며 승인 관계는 여전히 0개다. 과거 6/16은 DRAFT 개발용 명칭 coverage이며 의료 승인 coverage가 아니다. 현재 51종 적용 후 APPROVED+DIRECT coverage는 **0/46**, 해당 병원 **0개**다.

## 추가·수정·검수 작업

관리자 UI나 자동 승인 명령은 없다. 검수자가 파일을 편집하고 Git review를 통해 새 immutable version을 발행한다. 기존 파일을 덮어쓰지 않는다. schema는 `contracts/reference/disease-reference-v2.schema.json`; 실제 발행 검증의 권위는 Java 도메인 validator다.

새 질환 추가:

1. 현재 파일을 다음 버전 파일로 복사한다. datasetVersion/catalogVersion을 올린다.
2. 미사용 안정 ID, displayName, aliases(없으면 []), category, active=true, lifecycleStatus=ACTIVE, version=1을 입력한다.
3. 아래 검증 명령에 `--previous`를 지정한다. 관계가 없어도 검증을 통과하며 기록용 태그로 사용할 수 있다.
4. 코드의 `DiseaseReference.RESOURCE`만 새 파일로 전환하고 catalog/API/보존 회귀를 수행한다. 기존 ID는 그대로 유지한다.

새 mapping:

1. 미사용 mapping id, 기존 diseaseId/departmentId, relationType(DIRECT/CONTEXTUAL/REVIEW_REQUIRED), reviewStatus=DRAFT, evidence, approval=null, version=1을 작성한다.
2. 사람이 관계와 출처를 조사·검수한다. evidence는 sourceName, sourceUrl(HTTP(S)), checkedAt(UTC instant), rawDepartmentText, notes를 포함한다. 빈 DRAFT evidence는 작성 중 상태로 허용하지만 승인에는 적어도 하나의 완전한 evidence가 필요하다.
3. **별도 다음 reference version**에서 내용이 동일한 DRAFT에만 APPROVED와 approval={reviewer, approvedAt, version}을 입력한다. approval.version은 mapping.version과 같아야 한다. 도구는 구조만 검증하며 검수자의 신원·의료적 정당성을 인증하지 않는다. 저장소 접근권한과 사람의 PR 승인이 필요하다.
4. 관계/evidence를 수정할 때 version을 올리고 DRAFT/approval=null로 되돌린다. 수정과 재승인을 한 번의 transition으로 합치지 않는다. 승인된 내용을 그대로 둔 채 승인 메타데이터만 바꾸거나 mapping ID의 양끝을 재사용하지 않는다.
5. 관계 철회는 REJECTED/RETIRED와 approval=null을 새 reference에 기록한다. 이전 승인 이력은 immutable 파일/Git에 남긴다. RETIRED는 되살리지 않는다.
6. 새 version/hash와 coverage를 검증한 뒤 loader와 테스트를 갱신한다. 공개 API에는 APPROVED 관계만 전달되며 matcher는 그중 DIRECT만 사용한다. 회원은 referenceVersion 변경 후 지도 활용을 재확인해야 한다.

DepartmentAlias도 evidence/approval/version을 가지며 같은 DRAFT→APPROVED 검수를 거친다. canonical 충돌, 중복 alias, 다른 ID로의 재연결, alias chain은 허용하지 않는다. 현행 alias는 0개다. 별칭 추가는 의료 관계를 승인하는 행위가 아니다.

```sh
# 현재 reference의 구조/승인 coverage 확인: DB·.env·NMC 접근 없음
python3 scripts/validate_disease_reference.py \
  services/backend/src/main/resources/reference/disease-departments/v0.4.json \
  --hospitals contracts/fixtures/department-coverage-2026-09-17.json

# 새 버전 검수: 실제 다음 버전 파일 경로로 대체
python3 scripts/validate_disease_reference.py path/to/next.json \
  --previous services/backend/src/main/resources/reference/disease-departments/v0.4.json \
  --hospitals contracts/fixtures/department-coverage-2026-09-17.json
```

출력 hash는 공개 projection을 직렬화한 정확한 UTF-8 document의 SHA-256과 같다. DRAFT를 승인하거나 파일/DB를 쓰지 않는다. coverage는 활성 질환 중 승인 DIRECT가 있는 질환 수, 공개 fixture 이름에 일치하는 질환별 병원 수와 고유 병원 수다. 후자는 freshness/회원 동의와 별개인 이름 coverage임을 명시한다. 낮거나 0인 coverage는 기능 구현 Gate가 아니다.

## 회원 저장과 API

별도 DB migration/평문 선택 table은 없다. 기존 `member_health_profile.body_cipher`에 `standardDiseaseSelection`을 추가한다. AES-GCM, AAD(user/consentEpoch), 사용자 소유권, 낙관적 version, 삭제/철회 처리를 그대로 사용한다. 구 암호문은 빈 standard selection으로 읽으며 자동 태그 추출은 없다.

- GET/PUT `/api/v1/me/conditions`: 회원 본인의 `{version,consentEpoch,status,freeText,diseaseIds,catalogVersion}` 원자적 저장. 응답에는 standardDiseaseSelection(IDs/catalogVersion/서버 confirmedAt), mapDiseaseSelection, 통합 status를 포함한다. 다른 건강필드는 보존한다.
- GET/PUT/DELETE `/api/v1/me/map-disease-selection`: 별도 지도 활용. 저장은 기존 기록 태그의 부분집합, 활성 질환, 현재 purpose/purposeVersion/referenceVersion, confirmed=true를 요구한다. 승인 mapping 유무는 저장 조건이 아니다.
- GET `/api/v1/reference/disease-departments`: 공개 `{document,sha256}`. catalog 전체, APPROVED 관계와 alias만 포함한다. 파일 손상은 개인화만 unavailable로 만든다.
- POST `/api/v1/emergency-hospitals/departments/query`: HPID만 1~100개씩. 기존 DB의 public snapshot projection만 조회하며 provider refresh가 없다. 회원 token/질환/ID는 보내지 않는다.

회원 GET/PUT에는 no-store가 적용된다. profile/selection/version/epoch의 수동 조작이나 다른 사용자 ID 전달은 허용하지 않는다. 상세 계약: `contracts/openapi/disease-personalization-v1.json`.

## 태그·자유입력 UX와 상태

기저질환 편집은 기존 MemberScaffold/MemberGuard/초안 보호를 재사용한다. 등록 태그 제거, 질환 검색·선택, 별도 자유입력, 명시적 저장이다. alias 검색은 검색어의 후보 탐색에만 쓰며 자유입력 원문은 matcher 입력이 아니다. mapping이 없거나 DRAFT이면 ‘관련 진료과 정보 준비 중’으로 표시한다.

- 태그 등록만으로 지도 활용에 동의하지 않는다. 별도 화면에서 기록 태그 중 활용할 항목과 목적·한계를 확인한다.
- 태그 추가는 map selection에 추가하지 않는다. 한 태그 제거는 그 태그만 map selection에서 제거하고 다른 확정 항목을 보존한다.
- 자유입력 수정/삭제는 태그를 보존하고 남은 map selection을 RECONFIRM_REQUIRED로 바꾼다. 재확인 전 matcher가 제외한다.
- ‘기저질환 없음’은 명시적 NONE, ‘전체 초기화’는 UNSET이다. 두 동작은 확인 후 초안에 반영되고 저장 시 태그·원문·지도 활용 선택을 모두 지운다. 내용이 있는 RECORDED와 서로 모순되는 payload는 거부한다.
- 지도 활용 해제는 건강기록을 보존한다. profile 삭제는 태그·선택까지 삭제한다. health consent 철회는 epoch 차단 및 기존 암호문 erasure에 포함된다.
- 기존 지도 선택은 사용자 확인 후 기록 태그로 옮길 수 있다. 자동 migration/원문 추론은 없다. 기준정보 변경으로 기존 map selection은 재확인을 요구한다.
- 실패는 초안을 보존하고 충돌은 최신내용 확인, 로그아웃/계정 전환/동의 상실은 민감 초안을 제거한다. 기존 10분 TTL과 background cover/재검증을 유지한다.

## matcher·지도·개인정보

클라이언트가 최소 map selection, 공개 reference, 현재 검색 HPID들의 공개 진료과를 읽어 순수 matcher를 실행한다. 서버에 병원별 개인 질환을 보내지 않고 기존 검색·정렬·마커 모델을 유지한다. 결과는 matched/matchedDiseases/matchedDepartments/matchCount(고유 진료과)/mappingVersion과 질환·mapping·병원 원문/source/snapshot 이유를 가진다. APPROVED+DIRECT exact/승인 alias만 가능하다. CONTEXTUAL, DRAFT, 미확인·기한 만료 snapshot, reference 불일치, 재확인 상태는 강조하지 않는다. 기존 v0.1 DRAFT override는 과거 개발 비교 테스트에만 남아 있고 v2에서 사용할 수 없다.

Dev debug에서만 OFF 기본 ‘내 질환 관련 진료과’ 스위치를 보여준다. 실제 reference 0승인 상태에서는 준비 중이며, native 양성 검증은 test-only TEST_DISEASE/TEST_DEPARTMENT fixture를 주입한다. production 전체 flag는 OFF, 일반 검색은 정상이다.

Naver SDK는 공개 marker/좌표만 받는다. 작은 gold dot은 Flutter 별도 overlay이며 SDK marker의 빨강/파랑 의미를 바꾸지 않는다. 지도 이동 중 숨기고 idle/viewport 변경 후 모든 공개 병원 좌표를 다시 투영한다. 목록 badge ‘내 질환 관련 진료과’에서 이유와 의미 제한을 펼친다. 순위·결과 수·거리·응급의료기관 의미를 변경하지 않는다.

토글 OFF는 회원 질환/진료과 읽기를 발생시키지 않는다. ON 결과는 개인 메모리에만 유지하고 공용 hospital cache, analytics, logs, toString, NMC/SDK에 전달하지 않는다. 활성 동안 native FLAG_SECURE/cover의 기존 lease를 공유한다. 로컬 건강정보 변경 요청·철회·계정 전환·로그아웃·다른 화면 이동·background 진입 즉시 결과/토글을 지우고 지연 응답을 폐기한다. 다른 기기의 철회는 서버 확인 없이는 즉시 알 수 없으므로 10초 재검증/최대 10초 표시 TTL로 제한한다. 요청 지연/실패에도 만료 결과가 남지 않는다. 공개 진료과를 읽은 뒤 회원 version/epoch를 다시 확인한다.

## migration / rollback / 공개

실제 DB migration, 기존 암호문 일괄 재저장, Master 수정·재수집은 없다. 새 태그 필드는 첫 명시적 저장 시에만 들어간다. 서버를 먼저 호환 배포한 뒤 앱을 배포하는 순서를 문서화하되 이번에는 배포하지 않는다.

문제 시 지도 flag OFF/개인화 토글 차단이 우선이다. reference만 되돌릴 때도 새 datasetVersion으로 취소 상태를 발행해 재확인을 요구한다. 질환 ID·기록 태그를 삭제하는 rollback은 하지 않는다. **새 standardDiseaseSelection을 모르는 구 Backend는 profile 저장 시 새 필드를 유실할 수 있으므로 단순 binary downgrade를 금지**한다. 현재 보존 로직을 가진 호환 수정 버전으로 되돌리거나 건강정보 쓰기를 일시 차단한 상태에서 검증한다. DB 파괴 migration은 필요 없다.

production 공개는 별도 승인 변경이다. 승인 관계 검수, 현재 coverage, 개인정보/기기 QA 및 공개 승인을 확인하고 flag를 변경해야 한다. 자료가 없다는 이유로 기능 기반 구현은 중단하지 않는다. HIRA/지식백과/LLM/의학적 추론/실제 진료 보장/production 배포는 포함하지 않는다.

릴리스 경계 검증: `python3 scripts/verify_disease_release.py --apk apps/mobile/build/app/outputs/flutter-apk/app-production-release.apk --jar services/backend/target/emergency-api-0.1.0.jar`. 공개 flag OFF와 synthetic fixture 부재를 검사한다. production APK 빌드 검증은 배포를 의미하지 않는다.

기존 네트워크 차단 UI preview는 host adapter로 이전 자유입력 편집기를 유지한다. 새 태그 UI는 실제 Backend reference와 widget/native synthetic 테스트에서 검증하며 preview에 의료 catalog 복제본을 추가하지 않는다.


## Batch 2 — 2026-09-18

D017–D046 30개를 v0.3에 추가했다. datasetVersion=`eroute-disease-departments-v0.3`, catalogVersion=`diseases-v2`; vocabularyVersion과 purposeVersion은 그대로다. 기존 D001–D016의 데이터와 51개 진료과를 그대로 유지했고 v0.1/v0.2 파일은 byte-level 불변이다. 현재 46개라는 수는 이 버전의 관측치이며 catalog 길이/active 상태에서 동적으로 계산한다. UI나 matcher의 질환 수 제한을 46으로 코딩하지 않았다. 신규 질환 추가 절차는 위의 기존 절차와 동일하다.

신규 alias는 사용자가 제공한 10개만 추가했다: D017 당뇨, D023 IPF, D025 루푸스/SLE, D028 MS, D029 알츠하이머, D035 전립선비대증/BPH, D042 PCOS, D044 허리디스크. 기존 이름/alias와 충돌하지 않는다. 검색 후보 탐색에만 쓰며 의료 관계 추론에 사용하지 않는다.

신규 후보 43개는 모두 DIRECT/DRAFT/version=1/approval=null/evidence=[]이다. 실제 sourceName/sourceUrl/rawDepartmentText/checkedAt/의료적 근거를 작성하지 않았다. runtime schema를 늘리지 않고 DRAFT의 빈 evidence 목록을 사용한다. 따라서 APPROVED 0개, 공개 실행 projection의 mappings 0개, APPROVED+DIRECT coverage 0/46, 강조 병원 0개가 정상 상태다. 신규 태그 기록과 별도 지도 활용 확인은 가능하며 지도에는 ‘관련 진료과 정보 준비 중’으로 나타난다. 태그 추가가 mapDiseaseSelection에 자동 추가되지 않는다.

내과 연결 13개는 사용자 제공 broad-parent 후보이며 세부 내과를 내과로 자동 변환한 결과가 아니다. 출처가 세부 내과를 언급하더라도 ‘내과가 있는 모든 병원이 해당 질환을 진료한다’는 결론을 내리지 않는다. 독립적인 사람 검수와 승인이 필요하다. 나머지 관계의 canonical 직접 등장 여부도 미확인이고 전부 DRAFT다.

[관계별 검수표](../qa/disease-catalog-batch2-2026-09-18/review-checklist.md)와 [입력 worksheet](../qa/disease-catalog-batch2-2026-09-18/review-inputs.json)에 43개 관계와 누락 항목을 명시했다. worksheet는 앱 입력 파일이 아니다. 사람은 실제 출처를 확인해 입력한 후 **새 immutable version**에 evidence를 반영한다. evidence 변경은 mapping.version 증가 및 DRAFT/approval=null 유지, 이후 별도 version에서 동일 내용을 승인하는 순서를 따른다. v0.3에 덮어쓰거나 현 날짜를 근거 확인일로 채우지 않는다.

v0.3 검증 명령:

```sh
python3 scripts/validate_disease_reference.py \
  services/backend/src/main/resources/reference/disease-departments/v0.3.json \
  --previous services/backend/src/main/resources/reference/disease-departments/v0.2.json \
  --hospitals contracts/fixtures/department-coverage-2026-09-17.json
```

자료를 추가해도 기존 referenceVersion으로 확인한 지도 활용은 재확인을 요구한다. 건강기록 태그는 유지된다. production personalization flag는 계속 OFF이며 이번 작업은 실제 개발 DB 쓰기, NMC/HIRA 호출, 의료 승인 또는 앱 공개가 아니다. [Batch 2 QA](../qa/disease-catalog-batch2-2026-09-18/README.md).


## v0.4 evidence staging — 2026-09-18

현재 runtime reference는 `v0.4.json`이다. datasetVersion=`eroute-disease-departments-v0.4`; 질환/진료과 catalog 자체는 바뀌지 않아 catalogVersion=`diseases-v2`, vocabularyVersion=`departments-v1`, purposeVersion=`map-disease-use-v2`를 유지한다. 활성 질환 수 46과 진료과 수 51은 이번 데이터의 관측치이며 일반 runtime 계산은 catalog에서 동적으로 수행한다.

D001–D016의 18개 관계는 이번에 사용자가 지정한 현행 51종 vocabulary 기준 검수 후보로 새로 작성했다. v0.1 관계를 복사하거나 세부 내과를 내과로 자동 치환하지 않았다. 신규 mapping ID는 `V04-{diseaseId}-{departmentId}`로 발급해 legacy ID와 구별하며, 후속 version에서도 안정적으로 유지한다. v0.1/v0.2/v0.3 원본 파일은 byte-level 불변이다. 기존 v0.3의 43개 mapping은 ID/양끝/version/evidence/status까지 그대로 계승했다.

통합 [review-inputs.json](../qa/disease-evidence-v04-2026-09-18/review-inputs.json)은 **NON_RUNTIME_REVIEW_WORKSHEET**다. 앱/API/loader의 입력이 아니며 전체 61개 관계를 한 곳에서 검수한다. 기존 Batch 2 worksheet도 역사 자료로 보존한다. 신규 18개는 broad-parent 12개와 exact-canonical 6개, 기존 43개는 broad-parent 13개와 일반 검수 30개로 유지한다. 합계 broad-parent 25개 / exact-canonical 6개 / 일반 검수 30개다. 이 분류는 검수 업무 구분일 뿐 의료 관계의 타당성이나 승인 수준이 아니다.

모든 관계는 DIRECT/DRAFT/version=1/approval=null/evidence=[]이며 누락 evidence 61개다. reviewNote와 reviewClass는 worksheet에만 둔다. 사람이 출처를 실제로 확인하기 전 sourceName/sourceUrl/checkedAt/rawDepartmentText는 null이고 checklist는 false다. 현재 날짜나 추론한 URL/분과명, legacy/다른 질환 근거를 채우지 않는다. notes에는 검수 절차 설명만 기록할 수 있으며 그 자체가 의료 evidence가 되지 않는다.

후속 evidence 입력 절차:

1. 통합 worksheet에서 관계별 실제 출처·확인시각·원문과 검수 checklist를 사람이 채운다. 확인일은 실제 확인시각이며 자동 입력하지 않는다.
2. broad-parent는 출처의 세부 분과와 ERoute canonical ‘내과’의 연결을 독립적으로 검수한다. 내과가 존재한다고 모든 병원이 해당 질환을 진료/수용한다는 뜻이 아니다. exact 후보도 직접 출처 검수와 사람 승인이 필요하다.
3. 완전한 evidence를 **다음 immutable reference**에 반영한다. 변경된 관계만 mapping.version을 증가시키고 DRAFT/approval=null로 유지한다. worksheet만 작성하거나 evidence 내용이 동일하면 runtime mapping.version을 임의로 올리지 않는다. v0.4를 덮어쓰지 않는다.
4. `--previous v0.4.json`으로 검증한다. 같은 transition에서 evidence 수정과 APPROVED 승격을 합치지 않는다. 이후 별도 immutable version에서 사람이 동일 내용을 검수·승인하고 approval.version을 mapping.version과 맞춘다.
5. 새 reference/hash와 coverage를 재계산하고 loader/API/동의 재확인을 검증한다. worksheet의 체크 완료를 자동 승인으로 해석하지 않는다.

```sh
python3 scripts/validate_disease_reference.py \
  services/backend/src/main/resources/reference/disease-departments/v0.4.json \
  --previous services/backend/src/main/resources/reference/disease-departments/v0.3.json \
  --hospitals contracts/fixtures/department-coverage-2026-09-17.json
```

v0.4 공개 projection에는 mapping 0개, APPROVED+DIRECT coverage 0/46, 실데이터 강조 병원 0개다. 모든 활성 질환의 기록 태그 저장과 별도 지도 활용 선택은 가능하다. 미승인 관계는 ‘관련 진료과 정보 준비 중’이며 NO_MATCH/진료 불가가 아니다. v0.3으로 확인했던 지도 선택은 referenceVersion 변경에 따라 재확인이 필요하고 기록 태그는 유지된다. production flag는 OFF로 유지한다. [통합 QA/검수 결과](../qa/disease-evidence-v04-2026-09-18/README.md).

## Development review preview (2026-09-18)

`GET /api/v1/dev/reference/disease-departments-review-preview` is compiled only by
`mvn -Pdevelopment-auth`. The bean requires local/test auth environment; Security
requires an authenticated MEMBER. Password login is supported in this development
artifact. Production builds must use `mvn clean package` and pass
`scripts/verify_disease_release.py --jar ...`; the controller and review-class
resource must be absent. Production environment also denies this route.

The response contains `documentType=DEVELOPMENT_REVIEW_PREVIEW`, `referenceVersion`
and DRAFT+DIRECT candidates (`id`, `diseaseId`, `departmentId`, `relationType`,
`reviewStatus`, `reviewClass`, `version`). Resolve names through the unchanged public
catalog, requiring equal referenceVersion. No member details, evidence URLs or
approval information are returned. `src/development/resources/reference/review-classes-v0.4.json`
is a development-only ID/class projection of the existing review worksheet; tests
compare it with that worksheet. It does not modify the immutable reference.

Flutter visibility requires debug, dev flavor and AUTH_ENVIRONMENT=local/test.
Normal `lib/main.dart` owns the app; no synthetic fixture entrypoint is involved.
The switch defaults OFF, is not persisted, and uses existing separately confirmed
mapDiseaseSelection. Preview cannot approve mappings or change public projection.
DRAFT matching is in `lib/development/disease_review_preview.dart`; exact canonical
comparison and privacy lifecycle are shared primitives with separate input policy.

QA stores screenshots/results under `docs/qa/disease-review-preview-2026-09-18/`.
Use only an isolated account and public hospital data copied read-only from the
current development DB. Keep original snapshot times/statuses and TTL; stale data
stays UNKNOWN. NMC credentials must be absent and schedulers disabled. No source
collection is needed. This QA explicitly leaves the ordinary development APK
installed for user inspection; do not restore the prior APK automatically.


## Relation scope / visual policy — 2026-09-18

`mappingScope` is an optional schema-v2 Mapping field: EXACT_CANONICAL, BROAD_PARENT,
or omitted/null (unclassified). Existing immutable files and public v0.4 document/hash
are unchanged. MappingDeserializer allows only this omission; all old required fields
remain strict. Null is omitted on serialization. No backfill or new reference is issued.
Scope changes are semantic changes: increment mapping version, return to DRAFT and
clear approval in a new immutable reference. New DIRECT approval transitions require
an explicit scope. Evidence and reviewClass never infer it. Old approved references
without scope remain readable and card-only. Scope is not a matching algorithm or score.

APPROVED+DIRECT yields related card information; only explicit EXACT adds an eligible
8dp filled dot. Broad/unknown scope is card-only, including selection. The development
adapter alone interprets existing reviewClass: exact filled, ordinary review hollow,
broad none. Raw evidence, approvals and the v0.4 worksheet are untouched. The dot renderer
suppresses actual geometric collisions without affecting counts, order, radius or fits.
No percentage threshold or opacity policy is implemented.

### Reusable regional QA

Use an isolated clone containing public stored hospital/snapshot data and synthetic
members only. Read source DB in a READ ONLY transaction; never launch the QA application
against the source. Build development-auth and start its isolated server with
`--eroute.qa.stored-only=true --eroute.jobs-enabled=false`, empty NMC_SERVICE_KEY,
BASIC_INFO_SCHEDULER_ENABLED=false and NMC_BASE_URL=http://127.0.0.1:9. The QA adapter
rejects collection-enabled configuration and replaces realtime provider calls with
stored observation reads. It and its X-ERoute-Stored-QA response header are absent from
production artifacts. The capture script probes the header before login or search.

```sh
python3 scripts/capture_personalization_qa.py \
  --base-url http://127.0.0.1:18091 --account-file path/to/isolated-account.json \
  --center 37.5664983 126.9779983 --radius 10000 --diseases D001 D045 \
  --output /absolute/path/seoul-bundle.json
cd apps/mobile
flutter test test/personalization_qa_replay_test.dart \
  --dart-define=QA_BUNDLE_PATH=/absolute/path/seoul-bundle.json \
  --dart-define=QA_REPORT_PATH=/absolute/path/seoul-results.json
```

The bundle contains public reference/preview/search/department responses and explicit
QA inputs, never credentials, session tokens or real member selections. Offline replay
uses the actual Dart matcher and resolver at captured evaluatedAt. Fresh captures use
current time; stale source data remains UNKNOWN. Do not adjust original snapshot times.
Output includes requested/effective radius, distance order, MATCH/UNKNOWN/NO_MATCH,
matchRatio (null for zero hospitals), multipleRelationMatches (>=2 unique mappings),
allSelectedDiseasesMatched and accent candidate counts. Android capture adds paintedDots;
headless replay cannot claim screen geometry or Android visual success. This output is
QA data, not runtime analytics. Source/provider ledger and public-data hashes must remain
unchanged. Existing Seoul artifacts are historical and must not be overwritten.

No DB migration, profile rewriting or reference switch is needed. Keep production OFF.
Rollback disables preview and reverts compatible presentation code; it never edits
immutable medical data. A future scope-bearing publication must separately verify old
client compatibility before exposing mappings: an old client can ignore scope.


For Android native QA after the stored-only server is running:

```sh
python3 scripts/test_disease_personalization_ui.py \
  --defines /absolute/path/dev-qa-defines.json \
  --output docs/qa/your-new-qa-directory --device emulator-5554
```

Defines must target local/test, use the emulator's local server URL, set
EROUTE_AUTOMATION=true and ENABLE_SYSTEM_EMERGENCY_DIALER=false, and provide the
existing Naver client configuration. Do not put credentials in the defines. The
suite creates isolated synthetic accounts, tests Seoul single/multiple selections
and privacy invalidation, then captures Busan and Yeongwol with the same stored data.
The capture/replay commands accept any center/radius/disease IDs independently of
these regression examples. Native PNGs are test-owned surfaces; FLAG_SECURE is not disabled.


### Attached marker badge polish

The 8dp accent now overlaps the visible NE circle rim by 2dp, excluding transparent
icon padding. The visibility gate is conservative: uninstalled/pending, clipped,
occluded, or equal-z overlapping marker geometry has no badge. Selected z ordering
is unchanged; badge collision suppression still applies. Matching, scope, summary
and card information do not depend on badge visibility. No ratio threshold is added.

Debug preview reasons use Korean relation scope and review-state labels. Raw mappingId
and reviewClass exist only in a collapsed 개발 정보 disclosure in debug preview, never
approved/production reasons. One scroll owner keeps details and 닫기 reachable at 200%.
The frontend design is now limited to this attached badge and existing text disclosures;
no additional personalization decoration is planned.

Before/after Android evidence: `docs/qa/disease-marker-association-2026-09-18/README.md`.
Both runs use the stored-only isolated server. This QA mode intentionally does not
refresh realtime beds; restoring a normal dev APK with these QA defines keeps that
same stored-only backend connection. It must not be described as live-bed verification.

The reason sheet body is the sole flexible scroller; its existing 닫기 TextButton stays
in the SafeArea footer, visible at 200% even when development details are expanded.

### 독립 DiseaseCatalog 연결 (2026-09-21)

질환 입력/검색/카테고리/alias는 [DiseaseCatalog v1](disease-catalog-v1.md)에서 관리한다.
catalog의 질환 추가는 v0.5 evidence나 mapping 추가를 의미하지 않는다. STANDARD ID만
기존 별도 지도 활용 동의 경로에 전달하며 CUSTOM 및 mapping 없는 ID는 병원 매칭에서 제외한다.
개발 preview DTO는 mappingScope를 전달하지만 표시 분류는 기존 reviewClass를 유지한다.
질환 저장의 local pending/conflict가 남아 있으면 관련 진료과 personalization을 시작하지 않는다.
이번 변경은 evidence staging 종료 상태와 production OFF 경계를 유지한다.
