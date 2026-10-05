# ERoute 개발 · 실행 가이드

[프로젝트 소개로 돌아가기](../README.md)

명령은 별도 안내가 없으면 저장소 루트에서 실행합니다.

Flutter(Android/iOS) → Spring Boot(Java 21) → NMC OpenAPI. PostgreSQL에 전국 기관 Master와 마지막 정상 응답을 저장하며 GPS 또는 수동 검색 중심으로 주변 기관을 조회합니다.

## GitHub 업로드 전 확인

[공개 준비 및 비밀정보 관리](operations/github-publication.md)를 먼저 확인합니다.
`.env`, 인증키, 서명키, 로컬 DB, 실제 계정 QA 자료는 Git에 포함하지 않습니다.
개인정보가 들어갈 수 있는 QA 원본은 로컬에 보존하며, clone에는 공개 원천 검증에
필요한 [일부 입력 파일](qa/README.md)만 포함합니다.

```sh
brew install gitleaks  # macOS, 다른 환경은 문서의 고정 버전 사용
git config --local core.hooksPath .githooks
git add .
python3 scripts/check_publication.py --history
```

이 검사는 저장소 업로드 준비 확인이며 Play Store 출시나 Oracle 운영 배포 승인이 아닙니다.

## 먼저 확인할 자료

- 공식 필드 의미: `docs/references/`의 NMC V13 PDF
- 실측 근거: `docs/api/NMC_API_Data_Design_v0.2.md`
- 런타임 코드북: `services/backend/src/main/resources/nmc/codebooks/v13/codebook.json`
- 실제 전국 조회 검증: `docs/api/nmc-discovery-report.md`
- REST 계약: `contracts/openapi/emergency-map-v1.yaml` (JSON 표현의 유효한 OpenAPI/YAML)

원문 PDF는 Git 포함 여부와 무관하게 구현 환경에서 읽을 수 있어야 합니다. 다른 위치에 있다면 `NMC_V13_PDF`로 지정합니다. 해시가 다른 자료를 임의로 같은 버전으로 취급하지 않습니다.

```sh
python3 scripts/verify_sources.py
```

## 로컬 실행

필요 도구: Java 21, Flutter 3.47.2, PostgreSQL 16, Python 3.9 이상. Docker Compose는 선택입니다.

1. `.env.example`을 `.env`로 복사하고 NMC 키를 설정합니다. `.env`는 Git에서 제외됩니다.
2. 인코딩된 키는 `NMC_SERVICE_KEY_ENCODING=encoded`, 디코딩된 키는 `decoded`를 사용합니다. 키를 두 번 인코딩하지 않습니다.
3. `DB_URL`, `DB_USERNAME`, `DB_PASSWORD`를 설정합니다. 처음 기동하면 Flyway가 schema를 생성합니다.

기존 로컬 DB에서 회원 기능도 사용할 때는 `.env`에 `EROUTE_AUTH_ENVIRONMENT=local`, `EROUTE_AUTH_PROVIDER=password`, `EROUTE_ALLOW_DEVELOPMENT_AUTH=false`, `EROUTE_AUTH_KEY_FILE=<기존 .runtime/auth-local/keys.json의 절대 경로>`를 지정합니다. 인증 설정을 생략하면 기본값은 `disabled`이며 로그인은 503을 반환합니다. 기존 DB의 인증 키는 새로 생성하거나 교체하지 않습니다.

```sh
cd services/backend
./mvnw -DskipTests package
cd ../..
python3 scripts/run_backend.py
```

현재 작업 환경에는 `.runtime/postgres`의 개발용 PostgreSQL이 `127.0.0.1:55432`에 준비돼 있습니다. 시스템 서비스로 등록하지 않았습니다. 서버 실행 설정은 로컬 `.env`를 확인하세요.

Docker를 사용할 경우 비어 있지 않은 `DB_PASSWORD`를 설정하고 실행합니다.

```sh
docker compose --env-file .env -f infra/compose.yaml up --build
```

## 최초 수집: discovery gate 필수

다음 스크립트도 서버와 동일한 PostgreSQL endpoint 호출 예산을 사용합니다. 일반 테스트와 CI는 실제 NMC를 호출하지 않습니다.

```sh
python3 -m venv .tools/python
.tools/python/bin/pip install -r scripts/requirements.txt
.tools/python/bin/python scripts/discover_nmc.py
.tools/python/bin/python scripts/import_regions.py
# 기존 서버를 종료한 뒤, 검증된 수집 계획으로 Master를 갱신하며 기동
python3 scripts/run_backend.py --sync-catalog
```

Discovery가 통과하지 않으면 Master 동기화는 실행되지 않습니다. 인증/통신 실패를 무필터 조회 미지원으로 판단하지 않습니다. 무필터 pagination이 실패한 경우 행정구역을 적재한 뒤 `scripts/discover_nmc.py --regional`로 지역별 gate를 검증합니다. 지역별 수집은 전체 지역 discovery 근거가 있어야 하며, 검증된 일부 지역만으로 전국 Master를 대체하지 않습니다.

전국 행정구역 참조자료는 공식 자료에서 적재합니다. NMC 지역 필터의 호환성은 해당 지역 첫 요청에서 실제 Master HPID 집합과 대조합니다. 미검증 지역도 병원 목록에서 제거하지 않습니다.

## 앱 실행

로컬 Flutter SDK는 `~/development/flutter`에 설치합니다. 현재 프로젝트 버전은 `apps/mobile/.flutter-version`에 기록되어 있습니다. `run_mobile.py`는 `FLUTTER_BIN`, 터미널 PATH, `~/development/flutter/bin/flutter` 순서로 SDK를 찾습니다. `/tmp`의 임시 SDK 경로는 사용하지 않습니다. Android Studio의 Flutter SDK path도 같은 영구 경로로 설정합니다.

`NAVER_MAP_CLIENT_ID`는 네이버 Maps Application의 Client ID(키 ID)입니다. Dynamic Map을 선택하고 Android 패키지는 `com.eroute.eroute_mobile`, iOS Bundle ID는 `com.eroute.erouteMobile`로 등록합니다. 모바일 전용이므로 Web 서비스 URL은 비워둡니다. NMC 키는 앱으로 전달하지 않습니다.

```sh
cd apps/mobile
flutter pub get
cd ../..
API_BASE_URL=http://10.0.2.2:18081 python3 scripts/run_mobile.py
```

위 주소는 Android 에뮬레이터에서 호스트 서버에 접근하는 개발 예시입니다. 실제 기기에서는 접근 가능한 서버 URL을 사용합니다. 운영 빌드는 HTTPS를 사용하며 고정 Backend URL을 소스에 넣지 않습니다. HTTP 예외는 Android debug manifest에만 있습니다.

Android 에뮬레이터용 로컬 `.env`에는 `API_BASE_URL=http://10.0.2.2:18081`을 저장할 수 있습니다. 이 주소는 APK 빌드 때 고정되므로 QA 서버용 APK를 설치했다면 서버만 켜서는 복구되지 않습니다. `python3 scripts/run_mobile.py --build-apk --debug`로 일반 앱을 빌드하고 `adb install -r apps/mobile/build/app/outputs/flutter-apk/app-dev-debug.apk`로 데이터를 유지하며 업데이트합니다. 설치 후 아래의 일반 에뮬레이터 업데이트 완료 기준을 따릅니다.

지도 Client ID가 없거나 인증이 실패하면 목록은 이용할 수 있지만 네이버 지도 렌더링은 검증할 수 없습니다. iOS 빌드는 전체 Xcode와 CocoaPods가 필요합니다.

## 테스트

```sh
python3 scripts/verify_sources.py
cd services/backend
./mvnw verify
cd ../../apps/mobile
flutter analyze
flutter test
flutter build apk --debug --flavor dev
```

Backend 통합 테스트는 기본적으로 Testcontainers PostgreSQL을 사용합니다. Docker가 없으면 이름이 `_test`로 끝나는 별도 DB를 만들고 다음처럼 지정합니다. 운영 DB에서는 파괴적 테스트 실행을 거부합니다.

```sh
EROUTE_TEST_JDBC_URL=jdbc:postgresql://127.0.0.1:55432/eroute_test \
EROUTE_TEST_DB_USER=eroute ./mvnw verify
```

`flutter test`의 지도 화면 QA는 native 지도 대신 test double을 사용합니다. 실제 지도·위치 권한 검증과 동일하지 않습니다.

지도 UX 개선 버전은 실제 검색 반경 Circle, 전체 결과 camera fitting, 동적 Sheet, 현재 위치/병원/수동 중심 마커, 확대·축소, 메뉴를 제공합니다. MANUAL fitting에는 멀리 떨어진 사용자 GPS를 포함하지 않습니다.

개발 실행은 항상 `dev` flavor와 `MockEmergencyDialer`를 사용합니다. 119 확인 버튼을 눌러도 OS 전화 앱을 열지 않고 개발 모드 안내만 표시합니다. 개발·QA·자동 테스트에서 실제 긴급번호로 전화 연결을 시험하지 않습니다.

네이티브 지도 integration 테스트는 실행 중인 에뮬레이터와 `.env`의 지도 Client ID를 사용합니다. 병원/위치/heading/119는 테스트 구현으로 주입하며 NMC를 호출하지 않습니다.

```sh
python3 scripts/test_mobile_integration.py emulator-5554
```

구조와 배포용 전화 기능의 구분은 `docs/operations/map-ux-v0.1.md`를 참조하세요.

## 데이터 원칙

- 병원 Master 기준 LEFT JOIN. JOIN key는 `hpid`입니다.
- 병상 live source는 `getEmrrmRltmUsefulSckbdInfoInqire`뿐입니다.
- 0 / row 없음 / 필드 없음 / API 오류 / 예산 보류를 구별합니다.
- HVS01의 공식 명칭은 `일반_기준`, UI는 `일반 기준값`입니다. 총병상·점유율 분모로 사용하지 않습니다.
- hvidate 원문·지역시각 파싱값·서버 수집시각을 분리합니다. 시간대가 미확정이면 UTC 변환과 원천 경과시간 계산을 하지 않습니다.
- 충돌·미확정 의미는 `UNVERIFIED`, 미지 코드는 `UNKNOWN_CODE`입니다.
- 300초 공유 캐시와 on-demand 갱신을 사용합니다. 활성 화면 자동 polling과 전국 실시간 polling은 없습니다.
- 예산은 endpoint별 최근 24시간 자동 호출 900회로 제한합니다. 현재 계정의 일일 1,000회 중 여유를 남깁니다.

상세 정책과 운영 점검은 `docs/architecture/emergency-map-v0.1.md`, `docs/operations/runbook.md`를 참조하세요.

## 병원 진료정보 정적 캐시

NMC Basic Info의 진료과목과 병원 진료시간은 PostgreSQL에 별도 저장하고 `진료 정보` 탭에 표시합니다. Detail 조회·탭 전환·새로고침은 NMC를 호출하지 않습니다. 수집 전, 원천 미제공, 확인 필요, 갱신 실패·이전 정보를 구분합니다. 병원 진료시간은 응급실·진료과별 운영시간이나 현재 수용 가능을 뜻하지 않습니다.

최초 실행은 `--discover-basic` → `--sync-basic` 순서입니다. 실제 검증 결과와 예산은 `docs/api/nmc-basic-discovery-report.md`, 재개·scheduler 설정은 `docs/operations/runbook.md`를 참조하세요. 정상 게시 후 `BASIC_INFO_SCHEDULER_ENABLED=true`로 7일 갱신을 활성화할 수 있습니다. HIRA 연동은 포함하지 않습니다.

## 회원가입·로그인 및 내 응급정보

일반 앱의 승인된 회원 UI에 휴대폰 번호·비밀번호 가입/로그인, 실제 DB 세션, 별도 건강정보 동의, 본인 소유 응급정보·수동 복용약 CRUD와 동의 철회를 연결했습니다. `EROUTE_AUTH_PROVIDER=password`와 명시적 환경·기존 키를 사용하며 PASS/SMS를 선행조건으로 요구하지 않습니다. 번호 소유·실명·연령 검증은 수행하지 않습니다. 식약처 검색은 준비 상태이며 직접 입력 저장을 지원합니다.

현재 설치 일반 APK, 실제 가입·저장·지도 검수와 실행/종료 방법은 로컬 QA 기록 `docs/qa/member-real-integration-2026-09-15/README.md` (clone에는 미포함), 계약·키 교체·백업 복원은 [인증·건강정보 운영 문서](auth/authentication-and-health.md)를 따릅니다.


### 일반 에뮬레이터 업데이트의 완료 기준

공유하는 `Pixel_10`은 Android Studio의 일반 실행을 사용한다. 앱 업데이트는 같은 ID·서명의 `adb install -r`로 수행하며 앱 삭제/Wipe Data로 해결하지 않는다. 설치 후 최신 Quick Boot 상태를 저장하고, 정상 종료 → Android Studio 재실행 → 설치 APK 해시와 기능 화면 유지까지 확인한다. `-no-snapshot-save`/`-read-only` 실행 세션에서 설치 확인만 한 상태를 사용자에게 완료로 넘기지 않는다. 로컬 QA 기록 `docs/qa/emergency-guides-v1-2026-09-15/recovery/README.md` (clone에는 미포함).
