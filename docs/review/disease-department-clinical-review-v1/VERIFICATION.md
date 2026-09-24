# 최소 의료 검수 체계 검증 결과

2026-09-22. 의료 판정은 수행하지 않았다. 검수 원본에는 임의 reviewer, reviewedAtUtc, breadth, risk를 입력하지 않았다.

| 항목 | 결과 |
|---|---|
| review rows | 61 |
| EXACT_CANONICAL | 36 |
| BROAD_PARENT | 25 |
| PENDING / APPROVED / HOLD / REJECTED | 61 / 0 / 0 / 0 |
| breadth / risk | 각각 UNASSESSED 61 |
| clinical validator | PASS, --initial 및 --check-generated 포함 |
| 기존 v0.5 evidence validator | PASS, evidence complete 61/61, DRAFT 61 / APPROVED 0 |
| negative fixtures | 15개 모두 예상 FAIL을 확인한 테스트 PASS |
| Python tests | 11 tests PASS |
| generator dry-run | APPROVED=0, NO OUTPUT GENERATED |
| generator 기본 실행 | APPROVED=0, NO OUTPUT GENERATED |
| 향후 승인 generator 테스트 | 임시 디렉터리에서만 합성 승인 입력 사용: 승인된 관계만 추출, 나머지 제외, catalog/evidence 보존, 재실행 덮어쓰기·v0.5 대상 거절 |
| 기존 Java 도메인 검증 | 임시 합성 출력 PASS, 46 diseases / 51 departments / public draft 0 |
| 공개용 dataset 생성 | 없음, releases 디렉터리와 v0.6 파일 모두 없음 |
| 기존 보호 파일 | 468개 byte hash 동일 |
| 앱 / Backend / contracts 코드 변경 | 0 |
| Production flag | OFF, public mappings 0 |

테스트의 APPROVED 입력과 reviewer/time 문자열은 **TEST_ONLY**로 표시한 메모리/임시 파일에만 사용했다. 실제 review.json이나 runtime reference에 반영하지 않았다. Java 검증은 기존 컴파일된 ReferenceTool을 사용했고 Backend source를 변경하지 않았다. 앱 변경이 없어 Flutter/iOS/Android 빌드는 실행하지 않았다.

## 실행 명령

```sh
python3 scripts/validate_disease_clinical_review.py --initial --check-generated
python3 scripts/test_disease_clinical_review.py
python3 scripts/validate_disease_evidence_v05.py
python3 scripts/generate_approved_disease_reference.py --dry-run
python3 scripts/generate_approved_disease_reference.py
python3 scripts/verify_disease_release.py
```

Generator 두 실행의 출력:

```text
APPROVED=0
No approved mappings. Nothing generated.
NO OUTPUT GENERATED
```

## 불변 파일 SHA-256

| 파일 | Before | After | 결과 |
|---|---|---|---|
| v0.4 | `32a5f98da61178b882a940ea061a55e981febb0900d995ec88356d31b8dadd84` | `32a5f98da61178b882a940ea061a55e981febb0900d995ec88356d31b8dadd84` | 동일 |
| v0.5 | `bd5014127bf2db7bb315efd50411811ca2ce172c2fb9148dfe4884d7d158cf12` | `bd5014127bf2db7bb315efd50411811ca2ce172c2fb9148dfe4884d7d158cf12` | 동일 |
| source matrix 원본 | `309eacdbb321c63883ee88ef589a35e78fdd80454c87ff3f66874ed41a874eee` | `309eacdbb321c63883ee88ef589a35e78fdd80454c87ff3f66874ed41a874eee` | 동일 |
| source matrix reviewed | `2418fcfccdb2bd3d462463f769eb3a782aa997b07b984226dc141f2a8b41fee4` | `2418fcfccdb2bd3d462463f769eb3a782aa997b07b984226dc141f2a8b41fee4` | 동일 |
| reviewClass | `90d3bcb043e22471a850b68d355681894cd510480c099ce1debb78211c4e946f` | `90d3bcb043e22471a850b68d355681894cd510480c099ce1debb78211c4e946f` | 동일 |

수동 검수 owner는 [review.json](review.json), 검수표는 [review.md](review.md), 절차·명령은 [GUIDE.md](GUIDE.md), 집계는 [summary.json](summary.json)이다. generated 파일에는 의료 판단을 따로 입력하지 않는다.
