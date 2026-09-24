# 질환→진료과 최소 의료 검수 안내

> **ERoute가 이 질환→진료과 관계를 사용하여 “이 병원에 관련 진료과가 있음”이라고 사용자에게 표시해도 되는가?**

검수 결과는 이 표시의 허용 여부만 결정합니다. 치료 가능 여부, 현재 환자 수용 가능 여부, 병원 추천을 승인하는 검수가 아닙니다. 공식 문서의 진료과 명칭이 일치한다는 사실이나 기존 evidence 검토 완료만으로 의료적 승인이 되지 않습니다.

## 수정할 파일은 하나

- **[review.json](review.json)**: 유일한 수동 편집 원본. 각 relation의 **`clinicalReview` 안만** 사람이 작성합니다.
- [review.md](review.md): 원본으로부터 생성한 검수표. EXACT 36개 다음 BROAD 25개 순서이며 source URL을 클릭할 수 있습니다. 직접 수정하지 않습니다.
- [summary.json](summary.json): 자동 집계. 직접 수정하지 않습니다. `UNASSESSED`는 null의 수입니다.
- [negative-fixtures.json](negative-fixtures.json): validator 테스트용 잘못된 입력 patch입니다. 검수 데이터가 아니며 실제 검수에 복사하지 않습니다.

초기 원본은 61개 전부 PENDING이며 검수자·검수 시각·breadth·risk·reason은 null입니다. 자동 판정, 관리자 UI, DB, 별도 승인 서비스는 없습니다.

`mappingId`, 질환/진료과 ID와 이름, `mappingScope`, `reviewClass`, 출처 URL·원문·`checkedAt`, `parentEvidence`는 v0.5와 기존 review class에서 복사한 읽기 전용 값입니다. ID를 정규화하거나 다시 발급하지 않습니다. 기존 `V04-...`와 `D017-...` 형식을 그대로 유지합니다.

## 사람이 작성하는 판정

| 필드 | 입력 규칙 |
|---|---|
| `reviewer` | 실제 검수자를 식별하는 이름 또는 조직의 reviewer ID. 승인 시 필수 |
| `reviewerRole` | 실제 검수자의 역할·자격. 승인 시 필수 |
| `reviewedAtUtc` | 실제 검토 시각, UTC ISO-8601의 `YYYY-MM-DDTHH:mm:ssZ` 형식. 승인 시 필수 |
| `matchingBreadth` | `NARROW` / `MODERATE` / `VERY_BROAD`; 미판정은 null |
| `userMisinterpretationRisk` | `LOW` / `MEDIUM` / `HIGH`; 미판정은 null |
| `decision` | `PENDING` / `APPROVED` / `HOLD` / `REJECTED` |
| `reason` | 승인·보류·거절의 실제 근거. APPROVED/HOLD/REJECTED에서 필수 |
| `broadApprovalJustification` | BROAD_PARENT를 VERY_BROAD로 판단하고도 승인하려는 경우 별도 명시적 근거. 그 외에는 null 가능 |

공백 문자열은 입력으로 인정하지 않습니다. `checkedAt`은 과거 출처 확인 시각이고 `reviewedAtUtc`는 이번 의료 검수 시각입니다. source의 시각을 복사하거나 generator가 현재 시각을 대신 채우지 않습니다.

| matchingBreadth | 의미 |
|---|---|
| NARROW | 특정 진료과와 비교적 직접적으로 연결 |
| MODERATE | 어느 정도 범위가 넓음 |
| VERY_BROAD | 많은 병원과 매칭되어 정보 가치가 낮거나 오해 가능성이 큼 |

| userMisinterpretationRisk | 의미 |
|---|---|
| LOW | “관련 진료과 있음”으로 이해해도 오해 가능성이 낮음 |
| MEDIUM | 설명이 필요함 |
| HIGH | 치료 가능 또는 적합한 병원으로 오해할 가능성이 큼 |

| decision | 의미와 validator 조건 |
|---|---|
| PENDING | 아직 검수하지 않음. 검수자·시각이 없어도 정상 |
| APPROVED | 공개용 relation 후보. 위의 필수 필드가 모두 필요하고 HIGH risk는 허용하지 않음 |
| HOLD | 추가 검토 필요. reason 필수 |
| REJECTED | 공개하지 않음. reason 필수 |

BROAD_PARENT는 질환 페이지의 세부 진료과 원문과 별도의 상위 구조 근거를 함께 검토합니다. `matchingBreadth == VERY_BROAD`이면 `broadApprovalJustification` 없이 승인할 수 없습니다. justification이 있어도 HIGH risk 승인은 허용되지 않습니다. EXACT도 자동 승인하지 않습니다.

Validator는 입력의 구조와 정책만 검사합니다. 검수자의 신원·자격이나 의료적 타당성을 인증하지 않습니다. 실제 담당자가 출처와 표시 의미를 검토한 후 자신의 판정을 작성하고, 저장소의 사람 리뷰로 변경을 확인합니다.

## 검수 절차와 명령

저장소 root에서 실행합니다. Python 표준 라이브러리만 사용합니다.

1. 검수표의 mapping ID와 질환·진료과를 확인하고 source 링크를 읽습니다. BROAD는 상위 구조 링크도 확인합니다.
2. 위의 표시 허용 질문에 답하고, `review.json`의 해당 `clinicalReview`만 입력합니다. 모르는 항목은 임의로 채우지 않고 PENDING으로 남기거나 이유를 적어 HOLD로 둡니다.
3. validator로 확인한 뒤 generated 검수표와 요약을 갱신합니다.

```sh
python3 scripts/validate_disease_clinical_review.py
python3 scripts/validate_disease_clinical_review.py --write
python3 scripts/validate_disease_clinical_review.py --check-generated
python3 scripts/validate_disease_evidence_v05.py
python3 scripts/test_disease_clinical_review.py
```

최초 전달 상태만 확인하려면 `python3 scripts/validate_disease_clinical_review.py --initial`을 사용합니다. 사람이 판정을 작성한 뒤에는 `--initial`을 사용하지 않습니다.

4. 승인된 관계가 있으면 새 version으로 dry-run합니다. `APPROVED=0`일 때는 version 없이 실행해도 정상 종료하며 파일이나 releases 디렉터리를 만들지 않습니다.

```sh
# 현재 상태: APPROVED=0 / No approved mappings. Nothing generated. / NO OUTPUT GENERATED
python3 scripts/generate_approved_disease_reference.py --dry-run

# 향후 사람이 승인한 뒤에만 실행
python3 scripts/generate_approved_disease_reference.py \
  --version eroute-disease-departments-v0.6 --dry-run
python3 scripts/generate_approved_disease_reference.py \
  --version eroute-disease-departments-v0.6
```

기본 생성 경로는 이 디렉터리의 `releases/v0.6.json`입니다. `--output-dir`로 다른 검토용 디렉터리를 지정할 수 있습니다. 기존 v0.5 이하 버전과 이미 존재하는 버전 파일을 거절하며 덮어쓰기 옵션은 없습니다. 잘못된 결과를 수정할 때는 새 version을 사용합니다. 파일 시스템 권한이나 사람의 직접 파일 수정을 막는 서비스는 아닙니다.

Generator는 61개 row 전체를 검증한 뒤 **APPROVED만** 포함합니다. HOLD/REJECTED/PENDING은 제외합니다. 예를 들어 APPROVED 20, HOLD 30, REJECTED 11이면 20개만 출력합니다. 모든 검수가 끝날 때까지 기다리는 gate는 두지 않습니다.

질환 46개·진료과 51개의 catalog, 기존 evidence와 mappingScope, mapping version은 그대로 보존합니다. 새로운 datasetVersion과 승인된 relation의 `reviewStatus`, 기존 schema의 `approval={reviewer, approvedAt, version}`만 반영합니다. reviewerRole·reason·breadth·risk·justification은 검수 원본에 보관하며 runtime schema에 추가하지 않습니다. `review.json`과 생성 결과를 같은 사람 리뷰/commit으로 남겨 승인 이유를 추적합니다.

출력은 기존 reference schema를 따르는 **승인 relation만의 공개용 projection 후보**입니다. 기존 61개 전체를 보존하는 authoring ledger와는 용도가 다릅니다. 따라서 누락된 mapping을 금지하는 기존 `--previous v0.5.json` transition 검사에는 이 부분집합을 넣지 않습니다. 생성 결과 자체의 기존 도메인 검증은 다음과 같습니다.

```sh
python3 scripts/validate_disease_reference.py \
  docs/review/disease-department-clinical-review-v1/releases/v0.6.json
```

위 도메인 검증 명령은 기존 Java/Maven 환경이 필요합니다. 이번 최소 Python workflow에는 새 의존성을 추가하지 않습니다.

## 공개 경계

생성기는 앱, Backend loader, consent, matcher, 개인화 UI 또는 Production flag를 변경하지 않습니다. 생성 결과의 `publicMapApproved`도 기존 false를 유지합니다. 생성 파일이 생기는 것만으로 production에 공개되지 않습니다. 실제 runtime 전환과 공개 gate 변경은 별도 작업입니다.

이번 전달 상태는 **DRAFT 61 / clinical PENDING 61 / APPROVED 0 / public mappings 0 / Production OFF**입니다. v0.4, v0.5, 원본·reviewed source matrix 및 reviewClass 파일을 SHA-256로 고정하여 변경을 거절합니다. 출처나 관계를 바꿔야 한다면 이 검수 원본에서 고치는 대신 별도 immutable evidence/reference version 작업으로 진행합니다.

실행 결과와 작업 전후 hash는 [VERIFICATION.md](VERIFICATION.md)에 기록합니다.
