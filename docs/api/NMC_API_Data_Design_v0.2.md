# 국립중앙의료원 전국 응급의료정보조회 API 데이터 설계서 v0.2

작성 기준: 2026-09-08  
실측 범위: 경기도 파주시  
실측 횟수: 3회  
실측 시각(run): 20:46:59 / 21:06:16 / 21:45:48 전후  
기준 문서: 국립중앙의료원 OpenAPI 활용가이드 V13

---

## 1. 핵심 결론

파주시 `응급의료기관 목록정보 조회`에서는 4개 기관이 반환되었다.

| HPID | 기관명 | 분류코드 | 분류명 | 실시간 병상 응답 | 중증질환 응답 |
|---|---|---|---|---|---|
| A2100035 | 경기도의료원파주병원 | G006 | 지역응급의료센터 | 있음 | 있음 |
| A2100131 | 메디인병원 | G007 | 지역응급의료기관 | 있음 | 있음 |
| A2100083 | 무척조은병원 | G009 | 응급실운영신고기관 | 없음 | 없음 |
| A2100130 | 문산중앙병원 | G009 | 응급실운영신고기관 | 없음 | 없음 |

따라서 `병원 목록에 존재한다 = 실시간 병상 데이터가 존재한다`는 가정은 사용할 수 없다.

앱에서는 최소한 다음 3개 상태를 분리해야 한다.

- `LIVE_AVAILABLE`: 실시간 병상 API에 현재 row가 존재함
- `LIVE_NOT_PROVIDED`: 병원은 존재하지만 실시간 병상 row가 없음
- `LIVE_ERROR`: API 호출 자체가 실패함

`LIVE_NOT_PROVIDED`를 병상 0으로 표시해서는 안 된다.

---

## 2. 파주시 병원 Master

### A2100035 경기도의료원파주병원

- 분류: G006 / 지역응급의료센터
- 주소: 경기도 파주시 중앙로 207, 경기도립의료원파주병원 (금촌동)
- 대표전화: 031-940-9100
- 목록 API의 `dutyTel3`: 031-940-9119
- 위도: 37.7548802103
- 경도: 126.779637936

### A2100131 메디인병원

- 분류: G007 / 지역응급의료기관
- 주소: 경기도 파주시 금릉역로 190(금촌동)
- 대표전화: 0319431191
- 목록 API의 `dutyTel3`: 031-570-7912
- 위도: 37.75804616829998
- 경도: 126.7748532614

### A2100083 무척조은병원

- 분류: G009 / 응급실운영신고기관
- 주소: 경기도 파주시 문산읍 방촌로 1675-20
- 대표전화: 031-954-1400
- 목록 API의 `dutyTel3`: 031-953-0119
- 위도: 37.86396621605936
- 경도: 126.78097787974224

### A2100130 문산중앙병원

- 분류: G009 / 응급실운영신고기관
- 주소: 경기도 파주시 문산읍 문향로39번길 53, 문산중앙병원
- 대표전화: 031-950-9000
- 목록 API의 `dutyTel3`: 031-950-9099
- 위도: 37.85424810677575
- 경도: 126.78322857702757

---

## 3. 실시간 병상 실측

### 경기도의료원파주병원

| 필드 | 의미 | 20:45 | 21:03 | 21:45 | 기준(HVS) |
|---|---|---:|---:|---:|---:|
| hvec | 일반응급실 일반병상 가용 | 12 | 13 | 14 | HVS01=17 |
| hvgc | 일반 입원실 가용 | 62 | 61 | 60 | HVS38=189 |
| hvicc | 일반 중환자실 가용 | 3 | 3 | 3 | HVS17=8 |
| hvoc | 수술실 가용 | 3 | 3 | 3 | HVS22=3 |
| hv29 | 응급실 음압격리병상 | 1 | 1 | 1 | HVS03=1 |
| hv30 | 응급실 일반격리병상 | 2 | 2 | 2 | HVS04=2 |
| hv31 | 응급전용 중환자실 | 1 | 1 | 1 | HVS05=2 |
| hv36 | 응급전용 입원실 | 1 | 1 | 0 | HVS19=3 |
| hv42 | 분만실 | Y | Y | Y | HVS26=1 |

변화:
- 응급실 가용병상: 12 → 13 → 14
- 일반 입원실: 62 → 61 → 60
- 응급전용 입원실: 1 → 1 → 0

### 메디인병원

| 필드 | 의미 | 20:45 | 21:05 | 21:45 | 기준(HVS) |
|---|---|---:|---:|---:|---:|
| hvec | 일반응급실 일반병상 가용 | 8 | 10 | 11 | HVS01=12 |
| hvgc | 일반 입원실 가용 | 52 | 51 | 51 | HVS38=206 |
| hvoc | 수술실 가용 | 4 | 4 | 4 | HVS22=4 |
| hv30 | 응급실 일반격리병상 | 2 | 2 | 2 | HVS04=2 |

변화:
- 응급실 가용병상: 8 → 10 → 11
- 일반 입원실: 52 → 51 → 51

### 무척조은병원 / 문산중앙병원

`응급의료기관 목록정보 조회`와 `기본정보 조회`에는 존재하지만, 세 번 모두 `실시간 가용병상정보 조회` 결과에는 row가 없었다.

따라서 UI:

> 실시간 병상정보 미제공

처럼 표시해야 한다.

절대:

> 가용병상 0

으로 표시하면 안 된다.

---

## 4. 실시간 데이터 freshness

6개 실시간 병상 snapshot(2개 병원 × 3회)에서 `hvidate`와 실제 API 호출 시각의 차이는:

- 최소 약 17초
- 최대 약 195초
- 평균 약 83초

이었다.

이 실측 구간에서는 `hvidate`가 비교적 최근이었으므로 실시간 병상 데이터가 실제로 갱신되고 있음을 확인했다.

다만 3회 표본만으로 갱신 주기를 확정할 수는 없다.

권장 저장 필드:

```text
sourceUpdatedAt  <- hvidate
fetchedAt        <- 우리 서버 호출시각
freshnessSeconds <- fetchedAt - sourceUpdatedAt
```

---

## 5. Basic API의 hv*를 실시간 병상으로 사용하면 안 됨

`getEgytBassInfoInqire`에서도 `hvec`, `hvgc`, `hvoc` 등이 반환되지만 세 번의 호출에서 값이 고정돼 있었으며 실시간 API와 불일치했다.

### 파주병원

기본정보 API:

- hvec=20
- hvgc=81
- hvicc=2
- hvoc=3

21:45 실시간 API:

- hvec=14
- hvgc=60
- hvicc=3
- hvoc=3

### 메디인병원

기본정보 API:

- hvec=10
- hvgc=23
- hvoc=0

21:45 실시간 API:

- hvec=11
- hvgc=51
- hvoc=4

### 문산중앙병원

기본정보 API에는:

- hvec=10
- hvgc=52
- hvoc=2

가 존재했지만, 실시간 병상 API에는 기관 자체가 반환되지 않았다.

따라서 앱의 live 상태 계산 규칙:

```text
실시간 병상 표시
= 오직 getEmrrmRltmUsefulSckbdInfoInqire 결과 사용

getEgytBassInfoInqire의 hv*
= 실시간 판단에 사용 금지
```

---

## 6. 중증질환 수용가능정보 실측

실시간 중증질환 API는 파주시에서 2개 기관만 반환했다.

- 경기도의료원파주병원
- 메디인병원

두 기관 모두 3회 동일:

```text
MKioskTy28 = Y
MKioskTy1~27 = 정보미제공
```

즉:

- 응급실 Gate Keeper 값은 Y
- 질환별 상세 수용능력은 전부 `정보미제공`

이다.

따라서 다음 표현은 금지한다.

```text
MKioskTy28=Y
→ 모든 중증질환 수용 가능
```

권장 UI:

```text
응급실 운영 정보: 제공됨
중증질환별 수용정보: 미제공
```

---

## 7. MKioskTy는 반드시 endpoint별 코드북을 사용해야 함

V13 자체에서 동일한 `MKioskTyN` 이름이 API별로 다른 의미로 사용된다.

예를 들어 중증질환 전용 API에서는:

- MKioskTy1 = 심근경색 재관류중재술
- MKioskTy2 = 뇌경색 재관류중재술
- ...
- MKioskTy28 = 응급실 Gate Keeper

반면 기본정보 API의 legacy 필드는 다른 매핑을 사용한다.

따라서 다음 함수 구조는 위험하다.

```text
field_label("MKioskTy7")
```

반드시:

```text
field_label(endpoint, "MKioskTy7")
```

이어야 한다.

DB에서도:

```text
endpoint + fieldName
```

을 복합 식별자로 사용한다.

---

## 8. 실제 응답 타입과 V13 선언 타입이 다를 수 있음

파주병원의 최신 실시간 응답:

```text
hv42 = Y
HVS26 = 1
```

V13에서 `hv42`는 분만실 자원 필드지만, 실제 값은 정수가 아니라 `Y`였다.

따라서:

```text
모든 hv* = Integer
```

같은 스키마는 사용할 수 없다.

권장 원본 저장:

```text
rawValue: string
```

그 후 필드별 파서:

```text
NUMERIC
BOOLEAN_CODE
ENUM_CODE
UNKNOWN
```

로 해석한다.

파싱 실패 시 원본값을 버리지 않는다.

---

## 9. 장비 가용 코드 `N1`

실제 데이터에서 다음처럼 `N1` 코드가 반복됐다.

파주병원:

- hvangioayn=N1
- hvcrrtayn=N1
- hvecmoayn=N1
- hvhypoayn=N1
- hvincuayn=N1
- hvoxyayn=N1
- hvventisoayn=N1

메디인병원에서도 일부 장비 필드가 `N1`.

V13 예제에도 `N1` 값은 등장하지만 이 실측과 문서만으로 `N1`의 정확한 코드 의미를 확정하기 어렵다.

따라서 v0.2 정책:

```text
Y  -> AVAILABLE
N  -> UNAVAILABLE (공식 명세가 Y/N이라고 명시한 필드에 한함)
N1 -> UNKNOWN_CODE_N1
```

`N1`을 임의로 `false`로 변환하지 않는다.

---

## 10. 병원 메시지 API

4개 HPID에 대해 3회 모두:

```text
totalCount = 0
```

이었다.

이는 해당 실측 시점에 메시지가 없었다는 뜻이지, 메시지 기능이 불필요하다는 뜻은 아니다.

DB 구조는 유지한다.

```text
hospital_message
- hpid
- symBlkMsg
- symBlkMsgTyp
- symTypCod
- symTypCodMag
- symBlkSttDtm
- symBlkEndDtm
- symOutDspYon
- symOutDspMth
```

---

## 11. API별 데이터 소유권

### hospital_list

앱의 병원 Master 기본 소스.

사용:

- hpid
- 기관명
- 응급의료기관 분류
- 주소
- 좌표
- 연락처

### hospital_basic

정적/상세 Master 보강.

사용:

- 진료과목
- 진료시간
- 기관설명
- 병상 총수 관련 정적 정보

사용 금지:

- live 병상 판단용 hv*

### beds

실시간 병상/장비의 유일한 live 소스.

### severe

질환별 수용정보의 유일한 live 소스.

### messages

현재 차단/수용제한 메시지 소스.

---

## 12. 권장 DB v0.2

### hospital

```text
hpid PK
name
emergency_class_code
emergency_class_name
address
latitude
longitude
main_phone
secondary_phone
created_at
updated_at
```

### hospital_realtime_snapshot

```text
id PK
hpid FK
source_updated_at
fetched_at
raw_json JSONB
freshness_seconds
coverage_status
```

`coverage_status`:

```text
AVAILABLE
NOT_PROVIDED
API_ERROR
STALE
```

### hospital_resource_value

```text
snapshot_id FK
field_name
raw_value
parsed_type
numeric_value nullable
boolean_value nullable
reference_field nullable
```

### severe_capability_snapshot

```text
id
hpid
fetched_at
gatekeeper_raw
raw_json
```

### severe_capability_value

```text
snapshot_id
capability_code
raw_value
normalized_status
detail_message
```

`normalized_status`:

```text
AVAILABLE
UNAVAILABLE
NOT_PROVIDED
UNKNOWN
```

### hospital_message

기존 설계 유지.

---

## 13. UI 규칙 v0.2

### 파주병원 / 메디인병원

```text
응급실 가용병상 14
기준병상 17

데이터 갱신
약 1분 전
```

단 `14/17`을 자동으로 "82% 여유"나 "점유율 18%"로 계산하지 않는다.
HVS는 공식 명칭이 '기준' 자원이므로 실제 점유율 계산식으로 쓸 수 있는지 별도 검증이 필요하다.

### 무척조은병원 / 문산중앙병원

```text
응급실 운영기관
실시간 병상정보 미제공
```

### 중증질환

파주병원 / 메디인병원:

```text
중증질환별 수용정보
정보 미제공
```

`MKioskTy28=Y`만으로 추천 점수를 높이지 않는다.

---

## 14. 테스트 프로그램 수정 필요사항

1. Python 최소 버전을 명확히 `>=3.10`으로 고정하거나 Python 3.9 호환 타입 힌트 사용.
2. `analyze.py`의 `정보미제공`을 `OTHER`가 아니라 `NOT_PROVIDED`로 분류.
3. `N1`을 별도 코드로 분류.
4. `postCdn1`, `postCdn2`는 V13에 존재하므로 known field에 추가.
5. `field_label()`을 endpoint-aware 구조로 변경.
6. basic endpoint의 `hv*`와 realtime endpoint의 `hv*`를 논리적으로 분리.
7. `hv*` 값을 전부 Integer라고 가정하지 않기.
8. 실시간 API에 row가 없는 병원을 `NOT_PROVIDED`로 명시적으로 기록.

---

## 15. v0.2에서 확정된 사항

- 파주시 API 목록 기관: 4개
- 실시간 병상 제공 기관: 2개
- 중증질환 API 제공 기관: 2개
- 파주병원 HPID: A2100035
- 메디인병원 HPID: A2100131
- 무척조은병원 HPID: A2100083
- 문산중앙병원 HPID: A2100130
- `hpid`가 API 간 JOIN key로 정상 작동
- 실시간 `hvidate`가 실제로 시간에 따라 변함
- `hv*`의 실시간 값이 실제로 변함
- `hvs*`는 3회 실측에서 안정적으로 유지
- basic API의 `hv*`는 live 정보로 사용하기 부적절
- 실시간 병상 API에서 기관이 아예 누락될 수 있음
- severe API에서 `정보미제공`이 실제 운영값으로 반환됨
- `MKioskTy` 필드 의미는 endpoint별로 분리해야 함
- `hv42=Y`처럼 필드 타입이 명세의 직관적 예상과 다를 수 있음
- `N1` 코드 의미는 추가 확인 필요
- 실측 시점에는 4개 기관 모두 활성 메시지 0건
- 음수 병상은 이번 3회 실측에서는 관찰되지 않음

---

## 16. 다음 검증 과제

1. 파주시 24시간 수집으로 실제 갱신주기 측정
2. `N1` 코드의 공식 의미 확인
3. 다른 지역(서울/고양/의정부 등) 실측으로 필드 다양성 확보
4. 음수 병상 실제 사례 수집
5. 메시지 API의 활성 차단 사례 수집
6. 위치 API의 거리/정렬 동작 실측
7. 외상센터 3개 API 실측
8. HVS를 이용한 점유율/혼잡도 계산이 타당한지 공식 의미 추가 확인

---

## 최종 데이터 원칙

```text
기관 존재
≠ 실시간 데이터 제공

실시간 병상 없음
≠ 병상 0

정보미제공
≠ 불가능

MKioskTy28=Y
≠ 모든 질환 수용 가능

Basic API의 hv*
≠ 실시간 병상

HVS 기준값
≠ 허가병상/총병상이라고 임의 해석

N1
≠ N이라고 임의 변환
```

이 원칙을 앱/서버 공통 도메인 규칙으로 고정한다.