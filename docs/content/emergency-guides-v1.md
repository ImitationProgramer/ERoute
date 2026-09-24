# ERoute 응급 가이드 v1

<!-- GENERATED: python3 scripts/verify_emergency_guides.py --write-markdown -->

Canonical: `apps/mobile/assets/content/emergency-guides/v1/`. 이 문서는 생성 결과이며 직접 편집하지 않습니다.

상태: SOURCE_GROUNDED_DRAFT · humanReviewedAtUtc: null · production 의료승인 없음.

최신 기준 확인은 출처 대조 기록이며 의료전문가 승인이나 모든 절차의 완전성 보증이 아닙니다.

공통 안내: 앱은 일반 응급처치 안내입니다. 실제 긴급 상황에서는 119 안내를 우선 따르세요. 상태가 심각하거나 판단이 어려우면 119에 도움을 요청하세요.

| ID | 제목 | 게시일 | 확인일 | 이용조건 |
|---|---|---|---|---|
| EMERGENCY_CALL_INFO | 119에 알려줄 내용 | 미표시 (null) | 2026-09-22 | UNCONFIRMED |
| EMERGENCY_LOCATION_HELP | 주소를 모를 때 위치 설명 | 미표시 (null) | 2026-09-22 | UNCONFIRMED |
| EMERGENCY_BEFORE_AMBULANCE | 구급차가 오기 전 | 미표시 (null) | 2026-09-22 | UNCONFIRMED |
| EMERGENCY_HANDOFF_INFO | 구급대원에게 알려줄 정보 | 미표시 (null) | 2026-09-22 | UNCONFIRMED |
| FIRST_AID_CPR_ADULT | 성인 심폐소생술 | 2022-11-03 | 2026-09-22 | KOGL_TYPE_1 |
| FIRST_AID_AED | 자동심장충격기(AED) | 2022-11-03 | 2026-09-22 | KOGL_TYPE_1 |
| FIRST_AID_CHOKING_ADULT_CHILD | 성인·소아 기도폐쇄 | 2022-11-09 | 2026-09-22 | KOGL_TYPE_1 |
| FIRST_AID_CHOKING_INFANT | 영아 기도폐쇄 | 2024-10-25 | 2026-09-22 | KOGL_TYPE_1 |
| FIRST_AID_BLEEDING | 외부 출혈·지혈 | 2022-11-10 | 2026-09-22 | KOGL_TYPE_1 |
| FIRST_AID_BURN | 화상 | 2022-11-10 | 2026-09-22 | KOGL_TYPE_1 |
| FIRST_AID_AMPUTATION | 절단상 | 2022-11-09 | 2026-09-22 | KOGL_TYPE_1 |
| FIRST_AID_BEE_STING | 벌 쏘임 | 2022-11-10 | 2026-09-22 | KOGL_TYPE_1 |
| FIRST_AID_SNAKE_BITE | 뱀 물림 | 2022-11-10 | 2026-09-22 | KOGL_TYPE_1 |
| FIRST_AID_NOSEBLEED | 코피 | 2022-11-10 | 2026-09-22 | KOGL_TYPE_1 |
| FIRST_AID_HEAT_INJURY | 열손상 | 2024-08-20 | 2026-09-22 | KOGL_TYPE_1 |
| FIRST_AID_COLD_INJURY | 한랭손상 | 2024-08-20 | 2026-09-22 | KOGL_TYPE_1 |
| FIRST_AID_SEIZURE | 경련 발작 | 2024-10-25 | 2026-09-22 | KOGL_TYPE_1 |

## 119에 알려줄 내용

`EMERGENCY_CALL_INFO` · EMERGENCY_ACTION

상황과 증상을 설명할 때 필요한 정보

### 지금 해야 할 일

1. 환자가 있다는 사실
2. 정확한 위치
3. 증상과 의식·호흡 상태
4. 알고 있는 나이·지병·복용약
5. 신고자의 연락 가능한 번호
6. 먼저 전화를 끊지 않고 119 안내 따르기

출처: [소방청 · 119 구급신고 요령](https://www.nfa.go.kr/nfa/safetyinfo/emergencyservice/119emergencydeclaration/)

게시일: null · 확인일: 2026-09-22 · 이용조건: UNCONFIRMED


## 주소를 모를 때 위치 설명

`EMERGENCY_LOCATION_HELP` · EMERGENCY_ACTION

주변 건물과 표지로 장소를 알리는 방법

### 지금 해야 할 일

사용할 수 있는 위치 단서

1. 큰 건물명/상호
2. 건물 전화번호
3. 엘리베이터 고유번호
4. 국가지점번호
5. 고속도로 이정좌표
6. 전봇대 번호
7. 도로명/주변 표지판
8. 스마트폰 GPS 활성화

출처: [소방청 · 119 구급신고 요령](https://www.nfa.go.kr/nfa/safetyinfo/emergencyservice/119emergencydeclaration/)

게시일: null · 확인일: 2026-09-22 · 이용조건: UNCONFIRMED


## 구급차가 오기 전

`EMERGENCY_BEFORE_AMBULANCE` · EMERGENCY_ACTION

현장 안내와 준비에 관한 내용

### 지금 해야 할 일

1. 119 의료지도에 따라 응급처치
2. 다른 사람이 있으면 구급차가 들어오는 길 안내
3. 평소 복용약 등 필요한 물품 준비
4. 환자 상태 지속 관찰

### 주의하세요

- 119 실시간 안내가 앱 일반 안내보다 우선

출처: [소방청 · 119 구급차 도착 전 준비](https://www.nfa.go.kr/nfa/safetyinfo/emergencyservice/emergencydeclarationbefore/)

게시일: null · 확인일: 2026-09-22 · 이용조건: UNCONFIRMED


## 구급대원에게 알려줄 정보

`EMERGENCY_HANDOFF_INFO` · EMERGENCY_ACTION

상태 변화와 이미 시행한 응급처치, 지병·병원·복용약

### 지금 해야 할 일

1. 증상/사고가 시작된 과정
2. 도착 전 상태 변화
3. 이미 시행한 응급처치
4. 알고 있는 지병
5. 다니는 병원
6. 복용 중인 약

출처: [소방청 · 119 구급차 도착 전 준비](https://www.nfa.go.kr/nfa/safetyinfo/emergencyservice/emergencydeclarationbefore/)

게시일: null · 확인일: 2026-09-22 · 이용조건: UNCONFIRMED


## 성인 심폐소생술

`FIRST_AID_CPR_ADULT` · FIRST_AID

반응·호흡 확인과 기본소생술 순서

### 지금 해야 할 일

1. 반응 확인
2. 119 신고 및 AED 요청
3. 정상 호흡 여부 확인
4. 가슴압박: 분당 100~120회, 성인 약 5cm
5. 교육받고 시행 가능한 경우 30:2
6. AED 음성안내
7. 구급대 도착 또는 정상 반응까지 지속

출처: [소방청 · 심폐소생술 (CPR)](https://www.nfa.go.kr/nfa/safetyinfo/lifesafety/0001/?boardId=bbs_0000000000002462&cntId=3&mode=view)

게시일: 2022-11-03 · 확인일: 2026-09-22 · 이용조건: KOGL_TYPE_1

최신 기준 확인: [질병관리청 · 2025년 한국 심폐소생술 가이드라인](https://www.kdca.go.kr/bbs/kdca/49/309908/artclView.do)

작성: 2026-01-29 · 최종수정: 2026-02-09 · 확인일: 2026-09-22 · KOGL_TYPE_4


## 자동심장충격기(AED)

`FIRST_AID_AED` · FIRST_AID

AED 음성 안내와 사용 시 주의

### 지금 해야 할 일

1. 전원 켜기
2. 맨 가슴에 패드 부착
3. 분석 중 환자 접촉 금지
4. 충격 지시 시 모두 떨어진 것 확인
5. 충격 후 즉시 CPR 재개
6. 계속 음성 안내 따르기

출처: [소방청 · 자동 심장충격기 (AED)](https://www.nfa.go.kr/nfa/safetyinfo/lifesafety/0001/?boardId=bbs_0000000000002462&cntId=4&mode=view)

게시일: 2022-11-03 · 확인일: 2026-09-22 · 이용조건: KOGL_TYPE_1

최신 기준 확인: [질병관리청 · 2025년 한국 심폐소생술 가이드라인](https://www.kdca.go.kr/bbs/kdca/49/309908/artclView.do)

작성: 2026-01-29 · 최종수정: 2026-02-09 · 확인일: 2026-09-22 · KOGL_TYPE_4


## 성인·소아 기도폐쇄

`FIRST_AID_CHOKING_ADULT_CHILD` · FIRST_AID

말하거나 숨쉬기 어려운 기도폐쇄 상황에서 시행할 기본 응급처치입니다.

### 이럴 때 확인하세요

환자가 기침하고 말할 수 있다면

- 스스로 강하게 기침하도록 격려합니다.

### 지금 해야 할 일

심하게 막힌 것으로 보이면

1. 말을 못 하거나 숨을 못 쉬고, 소리 나는 기침을 못 하는 경우 빠른 처치가 필요합니다.
2. 등 두드리기를 시행합니다.
3. 필요하면 복부 밀어내기를 시행합니다.
4. 이물이 나오거나 의식을 잃을 때까지 처치를 이어갑니다.
5. 의식을 잃으면 심폐소생술을 시작합니다.

### 주의하세요

- 보이지 않는 이물을 손가락으로 무작정 훑어내지 않습니다.

출처: [소방청 · 기도폐쇄](https://www.nfa.go.kr/nfa/safetyinfo/lifesafety/0001/?boardId=bbs_0000000000002462&cntId=6&mode=view)

게시일: 2022-11-09 · 확인일: 2026-09-22 · 이용조건: KOGL_TYPE_1

최신 기준 확인: [질병관리청 · 2025년 한국 심폐소생술 가이드라인](https://www.kdca.go.kr/bbs/kdca/49/309908/artclView.do)

작성: 2026-01-29 · 최종수정: 2026-02-09 · 확인일: 2026-09-22 · KOGL_TYPE_4


## 영아 기도폐쇄

`FIRST_AID_CHOKING_INFANT` · FIRST_AID

등 두드리기 5회·가슴 밀어내기 5회와 주의사항

### 지금 해야 할 일

1. 등 두드리기 5회
2. 가슴 밀어내기 5회
3. 반복
4. 의식 소실 시 CPR

### 주의하세요

- 보이지 않는 이물의 blind finger sweep 금지

출처: [소방청 · 영아 기도폐쇄 처치](https://www.nfa.go.kr/nfa/safetyinfo/lifesafety/0001/?boardId=bbs_0000000000002462&cntId=20&mode=view)

게시일: 2024-10-25 · 확인일: 2026-09-22 · 이용조건: KOGL_TYPE_1

최신 기준 확인: [질병관리청 · 2025년 한국 심폐소생술 가이드라인](https://www.kdca.go.kr/bbs/kdca/49/309908/artclView.do)

작성: 2026-01-29 · 최종수정: 2026-02-09 · 확인일: 2026-09-22 · KOGL_TYPE_4


## 외부 출혈·지혈

`FIRST_AID_BLEEDING` · FIRST_AID

외부 출혈이 있을 때 직접 압박으로 출혈을 줄이는 방법입니다.

### 지금 해야 할 일

1. 가능하면 장갑 등으로 직접적인 혈액 접촉을 피합니다.
2. 거즈나 깨끗한 천으로 출혈 부위를 직접 압박합니다.
3. 붕대로 고정한 뒤에도 압박을 유지합니다.
4. 출혈이 심하거나 멈추지 않으면 119에 도움을 요청합니다.

### 주의하세요

- 골절이 의심되는 부위나 물체가 박힌 관통상은 무리하게 직접 압박하지 않습니다.

출처: [소방청 · 지혈 처치](https://www.nfa.go.kr/nfa/safetyinfo/lifesafety/0001/?boardId=bbs_0000000000002462&cntId=11&mode=view)

게시일: 2022-11-10 · 확인일: 2026-09-22 · 이용조건: KOGL_TYPE_1


## 화상

`FIRST_AID_BURN` · FIRST_AID

화상 부위를 식히고 추가 손상을 줄이는 기본 응급처치입니다.

### 지금 해야 할 일

1. 안전하게 제거할 수 있는 옷·반지 등 장신구를 제거합니다.
2. 피부에 달라붙은 것은 억지로 떼지 않습니다.
3. 화상 부위를 차가운 물로 식힙니다.
4. 물집은 터뜨리지 않고 보호합니다.
5. 넓거나 깊은 화상, 얼굴·기도 주변 화상 등 심한 화상은 119 또는 의료기관의 도움을 받습니다.

출처: [소방청 · 화상 처치](https://www.nfa.go.kr/nfa/safetyinfo/lifesafety/0001/?boardId=bbs_0000000000002462&cntId=12&mode=view)

게시일: 2022-11-10 · 확인일: 2026-09-22 · 이용조건: KOGL_TYPE_1


## 절단상

`FIRST_AID_AMPUTATION` · FIRST_AID

절단된 신체 부위를 적절히 보관하고 신속한 이송을 준비하는 방법입니다.

### 지금 해야 할 일

1. 눈에 보이는 오염물을 생리식염수 등으로 조심스럽게 씻어냅니다.
2. 생리식염수에 적셨다가 짠 거즈로 감쌉니다.
3. 물이 들어가지 않도록 비닐봉지 등에 밀봉합니다.
4. 차갑게 보관합니다.
5. 환자와 절단 부위를 함께 신속하게 의료기관으로 이송할 수 있도록 119의 안내를 받습니다.

### 주의하세요

- 절단 부위가 얼음과 직접 닿지 않도록 합니다.

출처: [소방청 · 절단상 처치](https://www.nfa.go.kr/nfa/safetyinfo/lifesafety/0001/?boardId=bbs_0000000000002462&cntId=7&mode=view)

게시일: 2022-11-09 · 확인일: 2026-09-22 · 이용조건: KOGL_TYPE_1


## 벌 쏘임

`FIRST_AID_BEE_STING` · FIRST_AID

벌에 쏘였을 때 침을 제거하고 전신 알레르기 반응을 확인하는 방법입니다.

### 지금 해야 할 일

1. 침이 남아 있다면 카드처럼 평평한 물체의 모서리로 밀어 제거합니다.
2. 쏘인 부위를 씻습니다.
3. 냉찜질로 통증과 부기를 줄입니다.
4. 호흡곤란·청색증 등 전신반응이 나타나는지 관찰합니다.

### 119 도움이 필요할 때

- 호흡곤란 등 아나필락시스가 의심되면 즉시 119에 신고합니다.
- 처방받은 에피네프린 자가주사기를 가진 환자가 도움을 요청하는 경우 사용을 도울 수 있습니다.

출처: [소방청 · 벌 쏘임](https://www.nfa.go.kr/nfa/safetyinfo/lifesafety/0001/?boardId=bbs_0000000000002462&cntId=8&mode=view)

게시일: 2022-11-10 · 확인일: 2026-09-22 · 이용조건: KOGL_TYPE_1

최신 기준 확인: [질병관리청 · 2025년 한국 심폐소생술 가이드라인](https://www.kdca.go.kr/bbs/kdca/49/309908/artclView.do)

작성: 2026-01-29 · 최종수정: 2026-02-09 · 확인일: 2026-09-22 · KOGL_TYPE_4


## 뱀 물림

`FIRST_AID_SNAKE_BITE` · FIRST_AID

뱀에 물렸을 때 움직임을 줄이고 신속하게 도움을 요청하는 방법입니다.

### 지금 해야 할 일

1. 물린 자국과 환자의 상태를 확인합니다.
2. 환자를 앉히거나 눕혀 안정시킵니다.
3. 움직임을 최소화합니다.
4. 119의 안내를 받습니다.

### 주의하세요

- 독을 입으로 빨아내지 않습니다.
- 임의로 강하게 묶지 않습니다.
- 상처를 절개하지 않습니다.

출처: [소방청 · 뱀 물림](https://www.nfa.go.kr/nfa/safetyinfo/lifesafety/0001/?boardId=bbs_0000000000002462&cntId=9&mode=view)

게시일: 2022-11-10 · 확인일: 2026-09-22 · 이용조건: KOGL_TYPE_1


## 코피

`FIRST_AID_NOSEBLEED` · FIRST_AID

코피가 날 때 올바른 자세와 압박으로 지혈하는 방법입니다.

### 지금 해야 할 일

1. 앉은 상태에서 고개를 앞으로 숙입니다.
2. 코의 부드러운 부분을 눌러 지혈합니다.
3. 입으로 숨을 쉽니다.
4. 피를 삼키지 말고 입으로 뱉습니다.
5. 출혈이 계속되거나 심하면 의료 도움을 받습니다.

출처: [소방청 · 코피 처치](https://www.nfa.go.kr/nfa/safetyinfo/lifesafety/0001/?boardId=bbs_0000000000002462&cntId=10&mode=view)

게시일: 2022-11-10 · 확인일: 2026-09-22 · 이용조건: KOGL_TYPE_1


## 열손상

`FIRST_AID_HEAT_INJURY` · FIRST_AID

고온 환경에서 발생한 열손상 환자의 체온을 낮추는 기본 응급처치입니다.

### 지금 해야 할 일

1. 시원하거나 그늘지고 바람이 통하는 곳으로 이동합니다.
2. 더운 옷·모자 등 불필요한 복장을 벗깁니다.
3. 선풍기·부채·얼음팩 등을 이용해 체온을 낮춥니다.
4. 체온이 높거나 의식 상태가 좋지 않으면 즉시 119에 신고합니다.

### 주의하세요

- 중증 열손상이 의심되면 음료를 억지로 먹이지 않습니다.

출처: [소방청 · 열손상](https://www.nfa.go.kr/nfa/safetyinfo/lifesafety/0001/?boardId=bbs_0000000000002462&cntId=16&mode=view)

게시일: 2024-08-20 · 확인일: 2026-09-22 · 이용조건: KOGL_TYPE_1


## 한랭손상

`FIRST_AID_COLD_INJURY` · FIRST_AID

추위에 노출된 환자를 따뜻한 곳으로 옮기고 추가 손상을 막는 방법입니다.

### 지금 해야 할 일

1. 실내 등 따뜻하고 바람을 피할 수 있는 곳으로 이동합니다.
2. 젖거나 몸을 조이는 옷을 제거합니다.
3. 담요 등으로 몸을 감싸 보온합니다.
4. 반지·시계 등 조이는 물건을 제거합니다.

### 주의하세요

- 손상된 부위를 문지르거나 마사지하지 않습니다.
- 술과 카페인은 피합니다.

출처: [소방청 · 한랭손상](https://www.nfa.go.kr/nfa/safetyinfo/lifesafety/0001/?boardId=bbs_0000000000002462&cntId=17&mode=view)

게시일: 2024-08-20 · 확인일: 2026-09-22 · 이용조건: KOGL_TYPE_1


## 경련 발작

`FIRST_AID_SEIZURE` · FIRST_AID

경련 중 환자가 다치지 않도록 보호하고 발작 과정을 관찰하는 방법입니다.

### 지금 해야 할 일

1. 환자 곁에 머뭅니다.
2. 주변의 위험한 물건을 치워 다치지 않게 합니다.
3. 발작이 시작된 시간과 진행 과정을 관찰합니다.
4. 발작이 끝난 뒤에도 상태가 회복되는지 관찰합니다.
5. 필요한 경우 119의 도움을 받습니다.

### 주의하세요

- 몸을 억지로 붙잡거나 움직임을 강제로 막지 않습니다.
- 입에 물건을 억지로 넣지 않습니다.

출처: [소방청 · 경련처치](https://www.nfa.go.kr/nfa/safetyinfo/lifesafety/0001/?boardId=bbs_0000000000002462&cntId=19&mode=view)

게시일: 2024-10-25 · 확인일: 2026-09-22 · 이용조건: KOGL_TYPE_1

최신 기준 확인: [질병관리청 · 2025년 한국 심폐소생술 가이드라인](https://www.kdca.go.kr/bbs/kdca/49/309908/artclView.do)

작성: 2026-01-29 · 최종수정: 2026-02-09 · 확인일: 2026-09-22 · KOGL_TYPE_4
