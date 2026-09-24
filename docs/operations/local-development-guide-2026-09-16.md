> 경로 표기: `${EROUTE_ROOT}`는 현재 저장소 위치, `${HOME}`은 사용자 홈입니다.
> 저장소 안에서 시작해 각 터미널에서 `export EROUTE_ROOT="$(git rev-parse --show-toplevel)"`를 먼저 실행하세요.

2026-09-16 현재 설정과 실행 스크립트를 확인한 개정판입니다. 기존 개발환경을 다시 켜고 끄는 용도이며, 새 Mac에 처음 설치하는 절차는 아닙니다.


# ERoute 실행·종료 가이드

2026-09-16 현재 설정과 실행 스크립트를 확인한 개정판입니다. 기존 개발환경을 다시 켜고 끄는 용도이며, 새 Mac에 처음 설치하는 절차는 아닙니다.

매일 시작: DB → Backend → Pixel 10 → ERoute

Android Studio의 Terminal을 두 개 사용하세요. 터미널 1은 Backend를 실행한 채 유지하고, 터미널 2는 상태 확인과 Flutter 작업에 씁니다. 이미 정상 실행 중인 항목은 그대로 사용합니다.

매일 종료: 작업 저장 → Flutter → 에뮬레이터 → Backend → DB

에뮬레이터는 최신 상태를 저장한 뒤 정상 종료합니다. DB와 앱 데이터, 키 파일은 다음 실행에서도 그대로 재사용합니다.

프로젝트 | ${EROUTE_ROOT}

DB | PostgreSQL 16 · 127.0.0.1:55432 · DB eroute
데이터: .runtime/postgres

Backend | Java 21 · Mac 주소 http://127.0.0.1:18081
인증: local / password / development-auth 허용 false

일반 앱 | ERoute · com.eroute.eroute_mobile
dev flavor · lib/main.dart · 119 Mock

에뮬레이터 | 기존 Pixel 10 (AVD: Pixel_10), Android 37.1 이미지
일반 Android 사용자 0 · adb ID는 실행마다 확인

도구 | Flutter 3.47.2: ${HOME}/development/flutter
Android SDK: ${HOME}/Library/Android/sdk

이번 개정에서 달라진 점

① 기존 키를 쓰는 비밀번호 회원 인증을 실행 명령에 명시합니다.<br/>② 설치된 앱을 여는 일과 코드 수정 후 APK를 업데이트하는 일을 구분합니다.<br/>③ Quick Boot 저장·재실행 확인을 추가하고, 저장을 막는 실행 옵션을 제외합니다.<br/>④ 과거 문서의 고정 PID 대신 현재 포트를 점유한 프로세스를 확인합니다.

이 환경의 기준
Docker Compose가 아닌 기존 .runtime/postgres를 사용합니다. Compose의 5432/8080과 현재 로컬의 55432/18081을 섞지 마세요. .env와 .runtime/auth-local/keys.json을 다시 만들지 않습니다.

터미널 1에서 실행합니다. 각 코드 블록은 위에서 아래로 복사하세요. 줄 끝의 \ 뒤에는 공백을 붙이지 않습니다.


# 1. DB와 Backend 켜기

터미널 1에서 실행합니다. 각 코드 블록은 위에서 아래로 복사하세요. 줄 끝의 \ 뒤에는 공백을 붙이지 않습니다.

1-1. 프로젝트로 이동하고 DB 상태 확인

```sh
cd ${EROUTE_ROOT}
/opt/homebrew/opt/postgresql@16/bin/pg_ctl \
  -D "$PWD/.runtime/postgres" status
```

server is running이면 시작 명령을 건너뜁니다. no server running일 때만 아래를 실행합니다.

```sh
/opt/homebrew/opt/postgresql@16/bin/pg_ctl \
  -D "$PWD/.runtime/postgres" \
  -l "$PWD/.runtime/postgres/server.log" \
  -o "-h 127.0.0.1 -p 55432" start
/opt/homebrew/opt/postgresql@16/bin/pg_isready \
  -h 127.0.0.1 -p 55432
```

정상: server started / accepting connections. DB는 백그라운드로 실행되므로 터미널 입력 표시가 돌아옵니다.

1-2. Backend가 이미 켜져 있는지 확인

```sh
curl --max-time 5 -fsS http://127.0.0.1:18081/actuator/health
lsof -nP -iTCP:18081 -sTCP:LISTEN
```

status가 UP이고 기존 ERoute 서버이면 재사용합니다. 연결 실패이며 포트 점유도 없을 때 다음을 실행합니다.

1-3. 현재 회원 인증 설정으로 Backend 실행

```sh
EROUTE_AUTH_ENVIRONMENT=local \
EROUTE_AUTH_PROVIDER=password \
EROUTE_ALLOW_DEVELOPMENT_AUTH=false \
EROUTE_AUTH_KEY_FILE="$PWD/.runtime/auth-local/keys.json" \
PORT=18081 SERVER_PORT=18081 \
python3 scripts/run_backend.py
```

Started ERouteApplication 로그가 나오면 터미널 1을 켜둡니다. 새 터미널에서 health의 UP을 다시 확인하세요. 스크립트는 .env를 읽고 공식 자료를 검사한 뒤, 미리 빌드된 JAR의 해시별 복사본을 실행합니다. 자동 빌드는 하지 않습니다.

인증 설정을 생략하지 않기
2026-09-21 복구 시 기존 로컬 .env에 위 인증 항목과 API_BASE_URL=http://10.0.2.2:18081을 저장했습니다. 이 설정이 있는 환경에서는 python3 scripts/run_backend.py만 실행해도 비밀번호 로그인이 활성화됩니다. 새 환경에서 인증 항목을 생략하면 기본 disabled가 적용됩니다. 키 누락 시 새 키 생성·계정 bootstrap 대신 기존 키 위치를 확인하세요. JAR가 없거나 코드를 바꿨으면 4페이지를 따릅니다.

DB와 Backend가 정상이면 Android Studio에서 기존 에뮬레이터를 실행합니다. APK를 매일 다시 설치할 필요는 없습니다.


# 2. Pixel 10과 일반 앱 열기

DB와 Backend가 정상이면 Android Studio에서 기존 에뮬레이터를 실행합니다. APK를 매일 다시 설치할 필요는 없습니다.

2-1. Android Studio에서 기존 Pixel 10 실행

Tools → Device Manager → Pixel 10의 실행 버튼을 누릅니다. 또는 Running Devices → Add Device → Pixel 10 API 37.1을 선택합니다. 이미 켜져 있으면 그대로 사용하고 Android 홈 화면까지 기다리세요.

ERoute 일반 앱을 엽니다. ERoute Preview는 별도 검수 앱이며 이번 실행 대상이 아닙니다. Android 사용자도 기존 사용자 0을 사용합니다.

2-2. 터미널 2에 도구 경로 설정 후 기기 확인

```sh
cd ${EROUTE_ROOT}
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
export PATH="$HOME/development/flutter/bin:$PATH"
adb devices -l
adb -s emulator-5554 shell am get-current-user
```

목록의 상태가 device인지 확인합니다. 아래 명령의 emulator-5554는 실제 표시된 ID로 바꾸세요. 사용자 결과는 0이어야 합니다. 다른 사용자라면 저장 중 작업을 마친 뒤 Android 사용자 메뉴에서 소유자로 전환하세요.

2-3. 이미 설치된 최신 앱을 그냥 사용할 때

```sh
adb -s emulator-5554 shell am start \
  -n com.eroute.eroute_mobile/.MainActivity
```

앱 아이콘을 직접 눌러도 같습니다. 현재 일반 앱은 회원 로그인·수동 복용약 저장과 7개 그림의 가이드 목록을 포함합니다. 가이드의 미승인 항목은 “본문 준비 중”이 정상입니다.

2-4. 화면 코드를 수정하면서 실행할 때

```sh
EROUTE_AUTH_ENVIRONMENT=local \
EROUTE_ALLOW_DEVELOPMENT_AUTH=false \
API_BASE_URL=http://10.0.2.2:18081 \
python3 scripts/run_mobile.py -d emulator-5554
```

이 명령은 현재 소스로 빌드·설치하고 Flutter 디버깅을 연결합니다. r은 Hot Reload, R은 Dart 실행 상태를 다시 만드는 Hot Restart, q는 Flutter 실행 종료입니다. Hot Restart는 앱 저장 데이터를 지우는 명령은 아니지만 입력 중 메모리 상태는 잃을 수 있습니다.

주소와 지도 설정
10.0.2.2는 Android 에뮬레이터에서 Mac에 접속하는 주소입니다. API_BASE_URL은 빌드 때 고정되므로 주소를 바꾸면 APK도 다시 빌드합니다. 지도 Client ID는 기존 .env에서 읽습니다. 가이드만 볼 때 GPS·지도 검색은 필요하지 않습니다.

소스가 바뀌었을 때만 수행합니다. 실행 중인 앱 입력을 저장하고, 일반 APK의 ID·서명·데이터를 유지합니다.


# 3. 수정한 코드를 반영하기

소스가 바뀌었을 때만 수행합니다. 실행 중인 앱 입력을 저장하고, 일반 APK의 ID·서명·데이터를 유지합니다.

3-1. Backend Java 코드나 의존성이 바뀐 경우

터미널 1의 Backend를 Control + C로 종료하고, 프로젝트 루트에서 다음을 실행합니다. 현재 비밀번호 인증은 기본 빌드에 포함되므로 과거 development-auth 프로필을 추가하지 않습니다.

```sh
cd ${EROUTE_ROOT}
JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home \
./services/backend/mvnw -f services/backend/pom.xml \
  clean package -DskipTests
```

BUILD SUCCESS 뒤에 2페이지의 인증 설정 포함 Backend 명령으로 다시 켭니다. -DskipTests는 빌드용이며 테스트 통과를 뜻하지 않습니다. Flyway가 시작 시 migration을 적용하므로 DB 스키마 변경 전에는 별도 백업이 필요합니다.

3-2. 최종 일반 APK를 빌드하고 업데이트 설치

터미널 2에서 실행합니다. PATH와 기기 ID는 3페이지 기준입니다. 의존성/pubspec 변경 시 먼저 cd apps/mobile에서 flutter pub get 후 루트로 돌아옵니다.

```sh
EROUTE_AUTH_ENVIRONMENT=local \
EROUTE_ALLOW_DEVELOPMENT_AUTH=false \
API_BASE_URL=http://10.0.2.2:18081 \
python3 scripts/run_mobile.py --build-apk --debug && \
adb -s emulator-5554 install -r \
  apps/mobile/build/app/outputs/flutter-apk/app-dev-debug.apk
```

빌드 성공 후에만 설치합니다. Success가 나오면 저장 중 편집이 없는지 확인한 뒤 앱을 다시 엽니다. 이 재시작은 저장 데이터를 삭제하지 않습니다.

```sh
adb -s emulator-5554 shell am force-stop com.eroute.eroute_mobile
adb -s emulator-5554 shell am start \
  -n com.eroute.eroute_mobile/.MainActivity
```

3-3. 업데이트 완료 확인

① 일반 ERoute에서 변경 화면과 기존 로그인 상태를 확인합니다.<br/>② 5페이지대로 최신 Quick Boot를 저장하고 에뮬레이터를 정상 종료합니다.<br/>③ Android Studio에서 같은 Pixel 10을 다시 켭니다.<br/>④ 재설치 없이 변경 화면이 유지되는지 확인합니다. 버전 문자열 0.1.0(1)은 같을 수 있으므로 그것만으로 최신 여부를 판정하지 않습니다.

설치 실패 시
서명 불일치(INSTALL_FAILED_UPDATE_INCOMPATIBLE)는 기존 인증서·서명 키를 대조할 문제입니다. uninstall, Wipe Data, 앱 데이터 삭제로 우회하지 마세요. 일반 APK를 Preview·production APK로 바꿔 설치하지 않습니다.

저장하지 않은 입력부터 마무리합니다. 실행 중인 서버·DB를 사용하는 다른 작업이 없는지도 확인하세요.


# 4. 작업을 끝내는 순서

저장하지 않은 입력부터 마무리합니다. 실행 중인 서버·DB를 사용하는 다른 작업이 없는지도 확인하세요.

4-1. Flutter 종료 후 최신 에뮬레이터 상태 저장

flutter run 터미널이 있으면 q로 종료합니다. 설치 앱만 열어 썼다면 이 단계는 건너뜁니다. 에뮬레이터가 아직 device 상태일 때 아래를 실행합니다.

```sh
adb -s emulator-5554 emu avd snapshot save default_boot
```

성공/OK 응답을 확인합니다. Android Studio의 Snapshots → Settings → Auto-save current state to Quickboot도 Yes로 둡니다. 이전 스냅샷을 Load하는 동작과 혼동하지 마세요.

4-2. Pixel 10 정상 종료

Device Manager에서 Pixel 10의 Stop을 사용합니다. 종료와 저장이 끝날 때까지 기다립니다. 창만 숨긴 것은 기기 종료가 아닐 수 있으므로 확인합니다.

```sh
adb devices -l
```

해당 emulator ID가 목록에서 사라지면 종료된 것입니다. 저장을 건너뛰는 Shift+닫기, 강제 종료, -no-snapshot / -no-snapshot-save / -read-only 실행은 일상 경로에 사용하지 않습니다.

4-3. Backend 종료

터미널 1에서 Control + C를 누르고 종료를 기다립니다. Command + C가 아닙니다. 창을 잃어버렸다면 6페이지의 현재 PID 확인 절차를 사용합니다.

```sh
lsof -nP -iTCP:18081 -sTCP:LISTEN
curl --max-time 5 http://127.0.0.1:18081/actuator/health
```

포트 점유 출력이 없고 연결 실패이면 종료 상태입니다. 여전히 UP이면 다른 프로세스를 확인하세요.

4-4. 마지막으로 PostgreSQL 종료

```sh
cd ${EROUTE_ROOT}
/opt/homebrew/opt/postgresql@16/bin/pg_ctl \
  -D "$PWD/.runtime/postgres" -m fast stop
/opt/homebrew/opt/postgresql@16/bin/pg_ctl \
  -D "$PWD/.runtime/postgres" status
```

server stopped 다음 no server running이면 완료입니다. fast 종료는 연결을 닫고 진행 중 트랜잭션을 롤백하며, 저장된 DB를 삭제하지 않습니다. 다음 시작은 다시 2페이지 순서입니다.

종료와 로그아웃은 다릅니다
환경 종료를 위해 로그아웃하거나 건강정보 동의를 철회할 필요는 없습니다. 앱·DB·기존 키가 보존되어도 세션 만료나 명시적 로그아웃으로 재로그인이 필요할 수 있습니다. 이는 데이터 초기화와 다릅니다.

원인을 확인한 뒤 해당 항목만 고칩니다. 기존 데이터 초기화나 다른 서버 전체 종료를 복구 수단으로 사용하지 않습니다.


# 5. 막혔을 때 확인할 곳

원인을 확인한 뒤 해당 항목만 고칩니다. 기존 데이터 초기화나 다른 서버 전체 종료를 복구 수단으로 사용하지 않습니다.

DB 또는 Backend에 연결되지 않을 때

55432 연결 거부 | 2페이지의 pg_ctl status와 pg_isready부터 확인. 로그는 .runtime/postgres/server.log. initdb나 .runtime/postgres 삭제 금지.

18081 이미 사용 중 | lsof로 현재 PID 확인. health가 UP이면 기존 서버 재사용. 다른 프로세스이면 명령 경로를 확인한 후 담당 작업과 조율.

JAR 없음 / 변경 미반영 | run_backend.py는 자동 빌드하지 않음. 4페이지의 Maven 빌드 성공 후 재시작. 실행 중 JAR는 .runtime/backend-artifacts의 해시별 복사본.

로그인 unavailable | Backend local/password/기존 키, 앱 local 빌드 여부를 함께 확인. 예전 auth=disabled APK라면 현재 설정으로 업데이트.

앱만 연결 실패 | Mac health가 UP인지 확인 후, APK의 API_BASE_URL이 10.0.2.2:18081인지 확인. localhost나 후보 서버 18082로 빌드된 앱과 구분.

Backend 터미널을 잃어버렸을 때

```sh
lsof -nP -iTCP:18081 -sTCP:LISTEN
```

여기서 표시된 PID를 확인한 뒤, 예를 들어 실제 PID가 12345라면 ps -p 12345 -o pid=,comm=,args= 로 ERoute의 .runtime/backend-artifacts/...jar인지 확인합니다. 그 프로세스를 종료할 때만 kill -TERM 12345를 사용하세요. 과거 문서의 PID 2281을 고정 명령으로 복사하지 않습니다.

에뮬레이터 화면 멈춤·옛 앱 복귀

현재 Pixel_10의 Graphics는 swiftshader(Software), Quick Boot 설정은 켜짐입니다. 기존 설정을 일상 실행마다 바꾸지 않습니다. 업데이트 후 옛 화면이면 일반 앱/사용자 0/설치본을 확인하고, 최신 APK 업데이트 → 스냅샷 저장 → 정상 종료 → Studio 재실행을 확인합니다.

스냅샷에서 부팅하지 못할 때만 Device Manager → Pixel 10 메뉴 → Cold Boot를 사용합니다. Cold Boot는 저장 실행 상태를 건너뛰며 Wipe Data와 다릅니다. Wipe Data는 앱과 데이터를 삭제하므로 선택하지 않습니다.

Software 그래픽과 스냅샷
Android 공식 문서는 Software 렌더링에서 스냅샷이 불안정할 수 있음을 알립니다. 이 환경에서는 이전 저장·재실행 성공 기록도 있습니다. 따라서 성공을 가정하지 말고 저장 응답과 재실행 화면을 확인하세요. 그래픽 변경이 필요하면 정상 종료 후 한 설정씩 변경·재검증합니다. [1]

이번 개정은 실행 설정·파일·현재 프로세스를 읽고 기존 health를 확인한 문서 작업입니다. 문서 검증을 위해 DB·Backend·에뮬레이터를 재시작하지 않았습니다.


# 6. 정상 상태와 확인 근거

이번 개정은 실행 설정·파일·현재 프로세스를 읽고 기존 health를 확인한 문서 작업입니다. 문서 검증을 위해 DB·Backend·에뮬레이터를 재시작하지 않았습니다.

빠르게 확인하는 정상 상태

DB | 127.0.0.1:55432 accepting connections. 기존 eroute DB 사용.

Backend | 18081 health UP. local / password / allow-development=false. 기존 auth-local/keys.json 사용.

앱·세션 | 일반 ERoute가 열리고 기존 계정 데이터 유지. 서버 중단·만료·로그아웃에 따른 재로그인은 별개.

가이드 v1.1 | 대처요령 3개 + 응급처치 4개 그림 카드. 카드 탭은 내부 상세. 승인 없는 본문은 준비 중. 개발 검토본은 기존 앱 정보 경로.

119·외부 호출 | 개발 일반 앱 119는 Mock. 가이드 확인을 위해 실제 PASS·SMS·전화 앱을 실행하지 않음. 지도 검색은 NMC 호출이 생길 수 있음.

설정 보존 | 지도 Client ID, DB/NMC 설정과 키 파일 유지. 비밀키·비밀번호·토큰을 PDF나 Dart 설정에 복사하지 않음.

일상 실행에 포함하지 않는 작업

매번 discovery, --sync-catalog, --sync-basic, 회원 bootstrap을 수행하지 않습니다. 현재 .env의 BASIC_INFO_SCHEDULER_ENABLED=true 등 기존 수집 정책은 유지합니다. 서버의 예정 수집이나 지도 사용으로 외부 호출이 발생할 수 있으므로 “서버를 켜기만 하면 항상 0회”라고 보장하지 않습니다.

Backend 통합 테스트는 데이터를 변경하므로 별도 _test DB에서 수행합니다. adb uninstall, pm clear, Wipe Data, DB 재생성, 키 재생성은 이 실행·종료 가이드에 포함하지 않습니다.

설정과 절차의 근거

로컬 확인일: 2026-09-16 KST. .env의 공개 설정 항목, 실제 Backend 프로세스의 필요한 환경 항목, AVD config.ini, DB 상태, health 응답, 일반 설치 패키지와 Android 사용자 0을 대조했습니다. 키 내용·계정·건강정보는 문서에 수록하지 않았습니다.

프로젝트 루트 기준:<br/>• scripts/run_backend.py, scripts/run_mobile.py<br/>• services/backend/src/main/resources/application.yml<br/>• docs/qa/member-real-integration-2026-09-15/commands.md<br/>• docs/qa/emergency-guides-v1-2026-09-15/recovery/README.md<br/>• docs/qa/guide-reader-v1_1-2026-09-16/README.md

[1] <link href="https://developer.android.com/studio/run/emulator-snapshots" color="#2D5885">Android Developers: Snapshots</link> · 저장, Cold Boot, Software 제약<br/>[2] <link href="https://developer.android.com/studio/run/emulator-commandline" color="#2D5885">Android Developers: Emulator command line</link> · 실행 옵션과 종료<br/>[3] <link href="https://www.postgresql.org/docs/16/app-pg-ctl.html" color="#2D5885">PostgreSQL 16: pg_ctl</link> · 시작·상태·정상 종료
