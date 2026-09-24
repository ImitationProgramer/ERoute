> 경로 표기: `${EROUTE_ROOT}`는 현재 저장소 위치, `${HOME}`은 사용자 홈입니다.
> 저장소 안에서 시작해 각 터미널에서 `export EROUTE_ROOT="$(git rev-parse --show-toplevel)"`를 먼저 실행하세요.

# ERoute 실행·종료 가이드

2026-09-21 개정 | 기존 Mac 개발환경을 다시 켜고 끄는 가이드입니다. 새 Mac의 최초 설치 절차는 포함하지 않습니다.

## 매일 시작

DB → Backend → Android Studio의 Pixel 10 → ERoute

Android Studio Terminal을 두 개 사용합니다. 터미널 1은 Backend용으로 켜두고, 터미널 2는 상태 확인과 앱 작업에 사용합니다. 이미 정상 실행 중인 항목은 재사용합니다.

## 매일 종료

입력 저장 → Flutter 종료 → Quick Boot 저장 → 에뮬레이터 종료 → Backend 종료 → DB 종료

| 구분 | 현재 기준 |
| 프로젝트 | ${EROUTE_ROOT} |
| DB | PostgreSQL 16 / 127.0.0.1:55432 / eroute<br/>데이터 폴더: .runtime/postgres |
| Backend | Java 21 / Mac: http://127.0.0.1:18081<br/>인증: local / password / 개발 인증 허용 false |
| 일반 앱 | ERoute / com.eroute.eroute_mobile<br/>dev flavor / lib/main.dart / 119는 Mock |
| 에뮬레이터 | Android Studio의 Pixel 10 API 37.1<br/>AVD: Pixel_10 / 기존 Android 사용자 0 |
| 도구 | Flutter 3.47.2: ~/development/flutter<br/>Android SDK: ~/Library/Android/sdk |

## 이번에 바뀐 내용

- 꺼진 QA 서버 18089를 바라보던 앱을 일반 서버 18081에 연결한 최신 앱으로 교체했습니다.
- .env에 API 주소와 비밀번호 인증 설정을 저장했습니다. 이제 Backend는 기본 실행 명령만으로 켤 수 있습니다.
- 실제 앱의 병원 조회·상세·로그인과 Quick Boot 재실행 후 최신 APK 유지를 확인했습니다.
- Android Studio 실행 설정, QA 설치본 복구와 백그라운드 서버 종료 절차를 보완했습니다.

> 읽는 순서: 실행은 2~3페이지, 코드 반영은 4페이지, 종료는 5페이지, 문제 해결은 6페이지입니다. 설정과 검증 근거는 7~8페이지에 있습니다.

<!-- page -->

# 1. DB와 Backend 켜기

터미널 1에서 실행합니다. 코드 블록은 위에서 아래로 복사하고, 줄 끝의 역슬래시(\) 뒤에는 공백을 붙이지 않습니다.

## 1-1. 프로젝트로 이동하고 DB 확인

```sh
cd ${EROUTE_ROOT}
/opt/homebrew/opt/postgresql@16/bin/pg_ctl \
  -D "$PWD/.runtime/postgres" status
```

server is running이면 아래 start를 건너뜁니다. no server running일 때만 시작합니다.

```sh
/opt/homebrew/opt/postgresql@16/bin/pg_ctl \
  -D "$PWD/.runtime/postgres" \
  -l "$PWD/.runtime/postgres/server.log" \
  -o "-h 127.0.0.1 -p 55432" start
/opt/homebrew/opt/postgresql@16/bin/pg_isready \
  -h 127.0.0.1 -p 55432
```

accepting connections이면 정상입니다. DB는 백그라운드에서 실행됩니다.

## 1-2. Backend가 이미 켜져 있는지 확인

```sh
curl --max-time 5 -fsS http://127.0.0.1:18081/actuator/health
lsof -nP -iTCP:18081 -sTCP:LISTEN
```

기존 ERoute 서버이고 status가 UP이면 재사용합니다. health가 UP이어도 로그인 설정까지 정상이라는 뜻은 아닙니다. 로그인 실패는 6페이지를 확인합니다.

## 1-3. 서버가 꺼져 있을 때 실행

포트 점유가 없을 때 프로젝트 루트에서 실행합니다. 현재 .env에는 7페이지의 인증 설정이 저장되어 있습니다.

```sh
python3 scripts/run_backend.py
```

Started ERouteApplication이 나오면 터미널을 켜둡니다. 터미널 2에서 health의 UP을 확인합니다. run_backend.py는 .env를 읽고 기존 JAR를 실행하며, 자동으로 빌드하지는 않습니다. JAR가 없거나 Backend 코드를 바꿨다면 4페이지를 먼저 따릅니다.

> 이 환경은 기존 .runtime/postgres를 사용합니다. Docker Compose의 5432/8080과 섞지 않습니다. 기존 .env와 인증 키 파일을 다시 만들 필요가 없습니다.

<!-- page -->

# 2. Pixel 10과 일반 앱 열기

DB와 Backend가 켜져 있으면 이미 설치된 ERoute를 열면 됩니다. 매일 빌드하거나 재설치할 필요는 없습니다.

## 2-1. Android Studio에서 에뮬레이터 실행

Tools → Device Manager → Pixel 10의 실행 버튼을 누릅니다. 또는 Running Devices → Add Device → Pixel 10 API 37.1을 선택합니다. 이미 켜져 있으면 그대로 사용합니다.

Android 홈에서 **ERoute**를 엽니다. ERoute Preview는 별도 검수 앱입니다. 단, 일반 ERoute와 같은 앱 ID에도 과거 QA 빌드가 설치될 수 있으므로 아이콘 이름만으로 연결 서버를 판정하지 않습니다.

## 2-2. 터미널 2에서 기기 확인

```sh
cd ${EROUTE_ROOT}
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
export PATH="$HOME/development/flutter/bin:$PATH"
adb devices -l
adb -s emulator-5554 shell am get-current-user
```

상태는 device, 기존 Android 사용자는 0입니다. 이 문서의 emulator-5554는 예시이므로 실제 목록에 표시된 ID로 바꿉니다.

## 2-3. 설치된 앱만 열기

```sh
adb -s emulator-5554 shell am start \
  -n com.eroute.eroute_mobile/.MainActivity
```

가까운 병원 찾기에서 지도와 병원 목록을, 로그인 후 내 응급정보에서 회원 기능을 확인합니다. 건강정보 등록은 별도 동의가 필요합니다. 위치와 반경에 따라 병원 수는 달라집니다.

## 2-4. 코드를 수정하며 Flutter 실행

```sh
python3 scripts/run_mobile.py -d emulator-5554
```

현재 .env의 API·지도·인증 설정을 읽어 dev flavor의 lib/main.dart를 실행합니다. r은 Hot Reload, R은 Hot Restart, q는 Flutter 종료입니다. Hot Restart 시 저장하지 않은 화면 입력은 사라질 수 있습니다.

> API_BASE_URL은 빌드 시 APK에 고정됩니다. Mac에서 서버가 정상이어도 APK가 18089 등 QA 주소를 바라보면 연결되지 않습니다. 주소를 고쳤다면 4페이지대로 일반 APK를 다시 빌드합니다. Android Studio의 Run 버튼 설정은 7페이지를 확인합니다.

<!-- page -->

# 3. 수정한 코드·서버 주소 반영하기

코드나 APK의 연결 설정이 바뀐 경우에 수행합니다. 서버만 다시 켜는 것으로 설치 앱의 코드나 API 주소가 바뀌지는 않습니다.

## 3-1. Backend 코드 또는 의존성 변경

현재 Backend를 종료합니다. 터미널에서 실행했다면 Control + C, 백그라운드 서버라면 5페이지 절차를 따릅니다. 그다음 프로젝트 루트에서 빌드합니다.

```sh
cd ${EROUTE_ROOT}
JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home \
./services/backend/mvnw -f services/backend/pom.xml \
  clean package -DskipTests
```

BUILD SUCCESS 후 python3 scripts/run_backend.py로 다시 켭니다. 일반 비밀번호 인증은 기본 빌드에 포함되므로 development-auth 프로필을 추가하지 않습니다. -DskipTests는 테스트 통과를 의미하지 않습니다. DB migration이 바뀌는 작업은 적용 전에 별도 백업을 준비합니다.

### 질환 DRAFT 개인화의 실제 개발 경로를 확인할 때

위 기본 빌드에는 DRAFT preview endpoint와 개발 reference loader가 포함되지 않습니다. 앱이 debug/dev이고 `AUTH_ENVIRONMENT=local`이어도 기본 JAR에 연결하면 개발 preview를 사용할 수 없습니다. 비밀번호 로그인 성공은 preview endpoint 포함 여부를 보장하지 않습니다.

개발 DRAFT 검증에는 기존 서버를 정상 종료한 뒤 다음 artifact를 빌드하고, 같은 `.env`와 DB·인증 키로 다시 실행합니다.

```sh
./services/backend/mvnw -f services/backend/pom.xml \
  -Pdevelopment-auth clean package -DskipTests
python3 scripts/run_backend.py
```

이때 `EROUTE_AUTH_ENVIRONMENT=local`, `EROUTE_AUTH_PROVIDER=password`, `EROUTE_ALLOW_DEVELOPMENT_AUTH=false`를 유지합니다. Maven 프로필은 개발 reference/preview 코드를 포함하는 용도이며 로그인 방식이나 건강정보 권한을 우회하지 않습니다. 앱은 `python3 scripts/run_mobile.py -d emulator-5554`로 실행하는 debug/dev 구성을 사용합니다.

서버 응답으로 active reference를 확인하고(`GET /api/v1/reference/disease-departments`의 `document.datasetVersion`), 기존 지도 선택의 reference가 바뀌었다면 앱의 **병원 탐색에 활용**에서 목적·한계를 다시 확인하여 저장합니다. 버전을 코드나 저장 요청에 고정하지 않습니다. 현재 개발 loader는 v0.5, 기본 production loader는 v0.4이며 public mappings 0 / APPROVED 0 / production flag OFF를 유지합니다. 개발 JAR은 production에서 실행하지 않습니다.

실제 로그인 계정과 native 지도에서 확인한 원인 및 결과는 [runtime 진단 기록](../qa/personalization-runtime-2026-09-21/README.md)에 남깁니다.

## 3-2. 일반 APK 빌드 후 데이터 유지 설치

터미널 2에서 실행합니다. PATH와 기기 ID는 3페이지 기준입니다. pubspec 의존성을 바꿨다면 apps/mobile에서 flutter pub get을 실행한 뒤 프로젝트 루트로 돌아옵니다.

```sh
python3 scripts/run_mobile.py --build-apk --debug && \
adb -s emulator-5554 install -r \
  apps/mobile/build/app/outputs/flutter-apk/app-dev-debug.apk
```

빌드 성공 후에만 설치됩니다. Success가 나오면 입력 중인 내용을 저장한 뒤 앱을 다시 엽니다. install -r은 같은 ID·서명의 앱을 업데이트하며 저장 데이터를 유지합니다.

```sh
adb -s emulator-5554 shell am force-stop com.eroute.eroute_mobile
adb -s emulator-5554 shell am start \
  -n com.eroute.eroute_mobile/.MainActivity
```

## 3-3. 업데이트 완료 확인

- 일반 앱의 변경 화면과 병원 조회·로그인을 확인합니다.
- 5페이지대로 Quick Boot를 저장하고 에뮬레이터를 정상 종료합니다.
- Android Studio에서 같은 Pixel 10을 다시 켜고 재설치 없이 변경 화면이 유지되는지 확인합니다.
- 버전 표시 0.1.0(1)은 이전 빌드와 같을 수 있습니다. 필요하면 설치 APK와 빌드 APK의 SHA-256을 비교합니다.

> 서명 불일치(INSTALL_FAILED_UPDATE_INCOMPATIBLE)는 기존 서명 키를 확인할 문제입니다. uninstall, Wipe Data, 앱 데이터 삭제로 해결하지 않습니다. integration_test용 APK는 최종 일반 앱으로 남겨두지 않습니다.

<!-- page -->

# 4. 작업을 끝내는 순서

입력 내용을 먼저 저장합니다. 같은 Backend나 DB를 사용하는 다른 작업이 끝났는지도 확인합니다.

## 4-1. Flutter 종료와 Quick Boot 저장

flutter run 터미널이 있으면 q로 종료합니다. 설치 앱만 열었다면 q 단계만 건너뜁니다. 기기가 device 상태일 때 최신 스냅샷을 저장합니다.

```sh
adb -s emulator-5554 emu avd snapshot save default_boot
```

OK를 확인합니다. Snapshots → Settings → Auto-save current state to Quickboot는 Yes로 둡니다. 이전 스냅샷을 Load하는 동작과 다릅니다. [1]

## 4-2. Pixel 10 정상 종료

Device Manager의 Stop을 사용하거나 아래 명령으로 종료합니다. 종료가 끝난 후 adb devices에서 해당 ID가 사라졌는지 확인합니다.

```sh
adb -s emulator-5554 emu kill
adb devices -l
```

창 숨기기는 종료가 아닐 수 있습니다. Shift+닫기, 강제 종료, -no-snapshot-save, -read-only 등 저장을 생략하는 실행 경로는 일상 업데이트에 사용하지 않습니다. [1][2]

## 4-3. Backend 종료

터미널 1에서 실행했다면 Control + C로 종료합니다. 백그라운드 서버 또는 터미널을 잃어버린 경우에는 다음으로 현재 PID를 확인합니다.

```sh
lsof -nP -iTCP:18081 -sTCP:LISTEN
```

예를 들어 실제 표시된 PID가 12345일 때만 아래 숫자를 사용합니다. 다른 PID이면 반드시 바꿉니다. 명령 경로가 ERoute의 .runtime/backend-artifacts/...jar인지 확인한 뒤 종료합니다.

```sh
ps -p 12345 -o pid=,comm=,args=
kill -TERM 12345
```

lsof에서 18081 점유가 없어야 종료된 것입니다. 과거 PID를 그대로 복사하거나 Java 프로세스 전체를 종료하지 않습니다.

## 4-4. 마지막으로 DB 종료

```sh
cd ${EROUTE_ROOT}
/opt/homebrew/opt/postgresql@16/bin/pg_ctl \
  -D "$PWD/.runtime/postgres" -m fast stop
/opt/homebrew/opt/postgresql@16/bin/pg_ctl \
  -D "$PWD/.runtime/postgres" status
```

server stopped / no server running이면 완료입니다. fast는 연결을 닫고 진행 중 트랜잭션을 롤백하지만 저장된 DB를 삭제하지 않습니다. [3] 환경 종료를 위해 로그아웃하거나 건강정보 동의를 철회할 필요는 없습니다.

<!-- page -->

# 5. 막혔을 때 확인할 곳

이번 연결 장애는 QA 주소가 고정된 APK와 인증이 꺼진 Backend가 함께 원인이었습니다. 아래 순서로 해당 항목을 확인합니다.

## 병원 정보를 불러오지 못할 때

1. Mac의 http://127.0.0.1:18081/actuator/health가 UP인지 확인합니다.
2. 일반 앱의 API_BASE_URL이 http://10.0.2.2:18081이어야 합니다. 에뮬레이터 내부 localhost는 Mac 서버 주소가 아닙니다.
3. QA용 18089나 다른 임시 포트로 만든 APK라면 4페이지의 일반 빌드·설치 절차를 수행합니다. .env만 바꾸고 앱을 그대로 두면 해결되지 않습니다.
4. 정상 종료·Android Studio 재실행 후에도 같은 최신 앱이 유지되는지 확인합니다.

## 로그인에 실패할 때

503 AUTH_UNAVAILABLE이면 Backend의 EROUTE_AUTH_ENVIRONMENT=local, EROUTE_AUTH_PROVIDER=password와 기존 키 파일 경로를 확인하고 서버를 재시작합니다. health UP만으로 인증 활성화를 확인할 수는 없습니다.

앱 연결 자체가 안 되면 위의 API 주소부터 확인합니다. 서버 연결과 인증 설정이 정상인데 자격정보 오류가 나면 실제 가입 계정의 번호·비밀번호를 확인합니다. 기존 QA 서버의 계정과 일반 DB의 계정은 같다고 가정하지 않습니다.

| 증상 | 확인·조치 |
| DB 55432 연결 거부 | 2페이지의 pg_ctl status / pg_isready 확인. 로그: .runtime/postgres/server.log |
| 18081 이미 사용 중 | lsof로 현재 프로세스 확인. 기존 서버가 정상이라면 재사용하고, 바꿔야 한다면 5페이지대로 해당 PID만 종료 |
| JAR 없음·코드 미반영 | run_backend.py는 자동 빌드하지 않음. 4페이지의 Maven 빌드 후 서버 재시작 |
| 병원 목록은 보이고 갱신 대기 | 앱 연결 실패와 구분. 각 병원의 갱신 안내·기준시각을 확인하고 잠시 후 새로고침 |
| 병원 기본 목록이 이전 자료 | 저장된 Master의 최신성 안내. 앱 설치 실패를 뜻하지 않으며 일상 실행 때 전국 재수집을 반복하지 않음 |
| 다시 켜니 옛 앱으로 복귀 | 일반 앱·사용자 0 확인 → 일반 APK 업데이트 → Quick Boot 저장 → 정상 종료 → Studio에서 재실행 |

## 에뮬레이터가 스냅샷에서 부팅되지 않을 때

Device Manager → Pixel 10 메뉴 → Cold Boot를 사용합니다. 앱·데이터를 삭제하는 Wipe Data와 다릅니다. 현재 그래픽은 Software(swiftshader)이며 스냅샷 신뢰성에 제약이 있으므로 저장 응답과 재실행을 확인합니다. 일상 실행마다 그래픽 설정을 바꾸지는 않습니다. [1]

<!-- page -->

# 6. 로컬 설정과 Android Studio Run

2026-09-21 복구 때 아래 값이 기존 .env에 저장되었습니다. 현재 환경에서는 매 실행마다 다시 입력할 필요가 없습니다.

## .env에서 확인할 공개 설정

```text
PORT=18081
API_BASE_URL=http://10.0.2.2:18081
EROUTE_AUTH_ENVIRONMENT=local
EROUTE_AUTH_PROVIDER=password
EROUTE_ALLOW_DEVELOPMENT_AUTH=false
```

EROUTE_AUTH_KEY_FILE은 다음 기존 파일의 절대 경로입니다. .env에는 한 줄로 저장합니다.

```text
${EROUTE_ROOT}/.runtime/auth-local/keys.json
```

DB_URL은 기존 127.0.0.1:55432/eroute를 사용합니다. DB 비밀번호·NMC 키·지도 설정·인증 키 내용은 기존 값을 유지합니다. 쉘에서 별도로 지정한 환경변수는 .env보다 우선하므로 다른 프로젝트에서 export한 설정이 있으면 함께 확인합니다.

## 일반 앱 실행 설정

run_mobile.py는 API_BASE_URL·NAVER_MAP_CLIENT_ID 등 필요한 모바일 설정만 전달합니다. NMC·DB·인증 서버의 비밀 키는 APK에 넣지 않습니다. API 설정을 바꾸면 새로 빌드해야 합니다.

Android Studio의 현재 main.dart 실행 설정에는 dev flavor와 설정 JSON을 지정했습니다. 실행 대상은 lib/main.dart입니다. 앱 프로젝트(apps/mobile)를 기준으로 같은 파일을 상대 경로로 지정하면 아래와 같습니다.

```text
--flavor dev
--dart-define-from-file=../../.runtime/general-app-recovery/mobile-defines.json
```

위 두 옵션은 Additional run args에서 공백으로 연결합니다. 긴 파일 경로를 중간에 끊어 넣지 않습니다. 해당 JSON은 9월 21일 설정을 저장한 파일이므로 .env를 수정해도 자동 갱신되지 않습니다.

> 설정을 바꾼 뒤에는 python3 scripts/run_mobile.py -d emulator-5554를 사용하면 현재 .env로 빌드할 수 있습니다. JSON 파일이 없거나 Run 설정이 불확실할 때도 이 명령을 사용합니다. 이번 실제 빌드 검증은 run_mobile.py로 수행했습니다.

## 일상 실행과 별개인 작업

discovery, --sync-catalog, --sync-basic, 회원 bootstrap은 매번 실행하지 않습니다. BASIC_INFO_SCHEDULER_ENABLED=true 등 기존 수집 정책은 유지되어 서버 작업과 지도 검색에서 NMC 호출이 발생할 수 있습니다.

Backend 통합 테스트는 별도 _test DB를 사용합니다. 앱·DB 초기화나 키 재생성은 실행·종료 절차에 포함되지 않습니다. 미승인 본문·매핑의 공개 정책과 개발 앱의 모의 긴급전화 동작은 그대로입니다.

<!-- page -->

# 7. 검증 결과와 참고 자료

2026-09-21 실제 일반 앱 복구 결과를 반영했습니다. 이번 PDF 개정에서는 실행 설정과 health를 다시 확인했으며, 문서 편집을 위해 서비스를 추가로 재시작하지 않았습니다.

## 실제 복구에서 확인한 내용

| 항목 | 결과 |
| Backend | 일반 코드로 clean package 후 재시작. health UP. 비밀번호 인증 활성화. 추가 DB migration 없음 |
| 앱 | lib/main.dart / devDebug 빌드 후 install -r. 최초 설치시각 유지, 앱 삭제·데이터 초기화 없음 |
| 병원 | 기존 DB의 병원 532건 유지. 당시 위치·반경에서 46곳, 지도·마커·상세·병상정보 표시 확인 |
| 로그인 | 기존 가상 검수 계정의 실제 앱 로그인 → 내 응급정보 진입 → 로그아웃 성공. 건강정보 동의 상태 유지 |
| 질환 목록 | 최신 서버 catalog 응답의 질환 46개·분류 14개 확인 |
| 재실행 | Quick Boot 저장 → 정상 종료 → Android Studio에서 Pixel 10 실행 후 APK 해시 일치와 지도 표시 확인 |

병원 수와 원천 데이터는 위치·시점에 따라 달라질 수 있습니다. 위 숫자는 검증 당시의 결과이며 매 실행의 고정 기대값은 아닙니다. 전체 자동 테스트는 이번 복구에서 재실행하지 않았습니다.

## 9월 21일 설치본 식별값

APK SHA-256:

```text
650efa26ed9cffe9956db8a736911b1e46ec6009df627af0d16d07bc25c1e978
```

Backend JAR SHA-256:

```text
399c8ea718f4d5754ab2f978cc5ed2d8c2af5072ba88df9b130ae74bcd306101
```

이후 코드를 바꿔 다시 빌드하면 해시는 달라집니다. 버전명만으로 최신 설치본을 판단하지 않습니다.

## 프로젝트 내 근거

- scripts/run_backend.py / scripts/run_mobile.py
- docs/operations/general-app-recovery-2026-09-21.md
- .runtime/general-app-recovery/verification.json
- docs/qa/disease-catalog-2026-09-21/README.md
- docs/qa/emergency-guides-v1-2026-09-15/recovery/README.md

## 공식 참고 문서 · 2026-09-21 확인

[1] [Android Developers: Snapshots](https://developer.android.com/studio/run/emulator-snapshots) - Quick Boot, Cold Boot, Software 제약

[2] [Android Developers: Emulator command line](https://developer.android.com/studio/run/emulator-commandline) - 실행 옵션과 종료

[3] [PostgreSQL 16: pg_ctl](https://www.postgresql.org/docs/16/app-pg-ctl.html) - DB 시작·상태·정상 종료
