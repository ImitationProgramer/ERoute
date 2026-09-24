# DiseaseCatalog v1 운영

질환 기록 catalog와 질환–진료과 관계는 독립적이다. 최초 catalog는 v0.5의 46개 ID/표시명/alias를 가져오고, 사용자가 확정한 14개 UX 카테고리 및 `D018: 고지혈증` alias를 결합했다. `D001`부터 `D046`은 다른 질환에 재사용하지 않는다. 이번 변경은 evidence/approval 작업을 다시 열지 않는다.

## 데이터와 API

- 편집 대상: `services/backend/src/main/resources/reference/diseases/catalog.json`
- GET `/api/v1/reference/diseases` (비회원 접근 가능)
- 최상위: `catalogVersion`, `mappingDatasetVersion`(실행 중 reference에서 계산), `categories`, `diseases`, `quickPickDiseaseIds`
- category: `id`, 한국어 `name`, `sortOrder`. 질환별 단일 `categoryId`는 탐색 UX에만 사용한다.
- disease: `id`, `canonicalName`, `categoryId`, `aliases`, `active`. inactive도 기존 기록 해석을 위해 응답에 남기며 신규 선택에서는 제외한다.
- `hasDepartmentMapping`을 별도로 저장하지 않는다. public APPROVED 관계와 development DRAFT preview는 각각의 기존 matcher가 실제 관계로 판정한다. 현재 public mappings는 0이다.
- `/api/v1/reference/disease-departments`와 immutable v0.4/v0.5의 계약/hash는 그대로다. 개발 v0.5 / production 기본 v0.4 / flag OFF.

## 저장 계약

기존 `/api/v1/me/conditions` PUT에 `conditionEntries` 형식을 추가했다. `version`, `consentEpoch`, `status`, `catalogVersion`은 필수다.

```json
{
  "version": 3,
  "consentEpoch": 1,
  "status": "RECORDED",
  "catalogVersion": "eroute-disease-catalog-v1",
  "conditionEntries": [
    {"type": "STANDARD", "diseaseId": "D001", "displayName": "천식"},
    {"type": "CUSTOM", "customName": "목록에 없는 질환"}
  ]
}
```

STANDARD 이름은 서버가 canonicalName으로 재확인한다. CUSTOM 원문은 유지한다. 전체 100개, CUSTOM 합계는 호환 projection의 줄바꿈을 포함하여 2,000자 이내다. STANDARD는 ID, CUSTOM은 NFC/앞뒤 공백/연속 공백/영문 대소문자 기준 단순 중복 제거다.

기존 `UNSET/NONE/RECORDED` wire enum은 `NOT_SET/NONE/HAS_CONDITIONS` 의미로 유지한다. 마지막 질환 삭제는 미입력이며 NONE은 명시적 확인이다. `conditionEntries`와 legacy `diseaseIds/freeText`의 혼합 요청은 거절한다. 기존 legacy 요청은 기존 reference catalogVersion을 사용하며, 이미 구조화된 기록의 손실 가능성이 있는 구형 편집에는 409를 반환한다. 다른 응급정보 필드를 편집해도 구조화된 질환은 보존된다. 기존 암호화 profile JSON을 사용하며 DB schema 변경은 없다.

## 마이그레이션과 기기 저장

구조화 field가 없는 legacy 기록만 최초 편집 시 변환한다. 기존 표준 ID는 보존하고, 원문 전체가 정규화 후 정확히 하나의 canonical/alias와 일치할 때만 STANDARD로 변환한다. 문장 분리·fuzzy·LLM 추론을 하지 않는다. 불확실한 원문은 전체를 한 CUSTOM으로 보존한다. GET은 DB를 쓰지 않으며 첫 명시적 저장 시 구조화한다. 원문 provenance는 암호화 profile에 보관하고 명시적 전체 초기화/없음 선택 시 지운다. 이미 CUSTOM인 기록은 새 alias 추가로 자동 변환하지 않는다.

Flutter의 보호 저장소는 명시적으로 저장한 질환만 보관한다. backend/environment namespace 및 계정/consent epoch 소유권을 확인하며 알레르기·약·메모는 추가 저장하지 않는다. 앱 시작/백그라운드 복귀는 기존 온라인 권한 확인을 요구한다. 유효한 전경 세션에서는 연결이 끊겨도 질환을 기기에 저장할 수 있다. 로그아웃/계정 변경/동의 상실 시 상태와 저장본을 제거한다.

서버 확인 전에는 `기기 저장 · 서버 반영 대기`, 충돌은 `최신 내용 확인 필요`로 구분한다. 연결 복구 시 전경 polling 또는 다시 읽기에서 동기화한다. PUT 응답 유실은 GET으로 결과를 확인하며 version이 달라졌으면 자동 덮어쓰기/병합하지 않는다. 사용자가 최신 내용을 확인하고 명시적으로 다시 편집한다. 기록 선택과 지도 활용 동의는 별개다. 앱 재실행 후 바로 지도로 진입하는 경우에도 보호 저장소의 계정별 pending 상태를 확인하며, 기록 내용을 노출하지 않고 미동기화 상태의 관련 진료과 표시를 차단한다. 동기화 성공 시 응급정보 화면은 최신 서버 snapshot을 다시 읽는다. 열린 editor는 편집 시작 version을 보존하며 중간에 version이 바뀌어도 새 version으로 몰래 저장하지 않는다.

## D047을 향후 추가하는 절차

1. 독립 `catalog.json`의 `diseases`에 사용하지 않은 ID, 검토된 이름, 기존 categoryId, 보수적인 aliases, `active: true`를 추가한다. ID를 재사용하지 않는다.
2. 새 탐색 분류가 필요하면 같은 파일의 `categories`에 ID/한국어 이름/sortOrder를 추가한다. 자주 찾는 질환에 표시하려면 같은 파일의 `quickPickDiseaseIds`를 변경한다.
3. 같은 파일의 `catalogVersion`을 새 버전으로 올린다. 변경 이력에서 기존 ID/이름 보존을 확인한다.
4. `python3 scripts/validate_disease_catalog.py`를 실행한다. 초기 seed 46개를 확인하는 테스트의 예상 총수도 dataset 변경에 맞게 갱신하고 Backend 회귀를 실행한다. 기존 D001–D046 identity 검사와 alias 충돌 검사를 유지한다.
5. 별도 배포 절차에 따라 이 resource를 포함한 Backend를 갱신한다. 현재 배포 방식은 classpath resource이므로 서버 artifact 갱신이 필요하며 관리 API/DB 편집은 만들지 않았다.
6. 앱이 catalog를 재조회하면 새 질환과 카테고리가 표시된다. Flutter application code 변경/재빌드는 필요 없다. 마지막 정상 응답은 공개 정보용 cache에 보관한다.
7. 진료과 mapping이 없어도 선택·저장된다. 병원 자동 매칭에서는 제외한다. 이 추가만으로 immutable v0.5를 수정하거나 의료 관계를 만들지 않는다.

이번 작업의 D047은 테스트 fixture에만 존재한다. 운영 seed는 46개다. 의료전문가 검수/production release가 실제 필요해질 때까지 evidence approval 확장을 재개하지 않는다.
