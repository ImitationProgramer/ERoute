# 일반 앱 연결 복구 — 2026-09-21

설치 APK의 API 주소는 꺼진 QA 서버 `http://10.0.2.2:18089`였다. 일반 백엔드 `18081`은 살아 있었지만 인증 설정 누락으로 로그인에 `503 AUTH_UNAVAILABLE`을 반환했다.

## 조치

- 기존 로컬 `.env`에 일반 API 주소, `local/password` 인증 및 기존 `.runtime/auth-local/keys.json` 경로를 저장했다. 개발 인증은 꺼짐이다.
- 최신 소스의 일반 Backend를 `./mvnw -q clean package -DskipTests`로 빌드했다. QA 클래스 미포함을 확인하고 일반 서버를 재시작했다. 스키마 변경은 없었다.
- `python3 scripts/run_mobile.py --build-apk --debug`로 `lib/main.dart`, `devDebug` APK를 빌드해 같은 앱 ID에 `adb install -r`로 설치했다. 앱 삭제/초기화 없음, 최초 설치시각 유지.
- 로컬 Android Studio `main.dart` 실행 설정에 dev flavor와 공개 모바일 설정 파일 `.runtime/general-app-recovery/mobile-defines.json`을 지정했다. 백엔드 비밀 키는 모바일 설정에 넣지 않았다.
- Quick Boot 저장 → 정상 종료 → Android Studio Running Devices에서 Pixel 10 실행 → 재설치 없이 APK 해시 일치와 지도 표시를 확인했다.

## 검증

- Backend health UP, 병원 Master 532건, 계정 7건 및 인증 키 등록 5건 유지.
- 에뮬레이터에서 실제 병원 46곳, 지도 타일/마커, 강북삼성병원 상세와 병상정보 표시 확인.
- 기존 가상 검수 계정으로 실제 앱 로그인 → 내 응급정보 진입 → 로그아웃 성공. 기존 건강정보 동의 상태를 변경하지 않았다.
- 최신 질환 catalog API의 질환 46개/분류 14개 확인.
- 최신 APK/Backend 빌드 및 실제 앱 동작을 검증했다. 애플리케이션 소스 변경은 없으며 전체 자동 테스트는 재실행하지 않았다.
- 일반 dev 앱의 미승인 매핑 미리보기 표시/공개 승인 정책, 모의 긴급전화 정책은 기존대로다. 원천 병원 목록의 이전 자료 안내도 유지된다.

APK SHA-256: `650efa26ed9cffe9956db8a736911b1e46ec6009df627af0d16d07bc25c1e978`

Backend SHA-256: `399c8ea718f4d5754ab2f978cc5ed2d8c2af5072ba88df9b130ae74bcd306101`

비공개 실행 기록: `.runtime/general-app-recovery/verification.json`, `backend.log`, `mobile-build.log`, `map-after-restart.png`.

## 다음 실행

기존 DB(55432)를 실행하고 프로젝트 루트에서 `python3 scripts/run_backend.py`를 실행한 뒤 Android Studio의 Pixel 10에서 **ERoute**를 연다. ERoute Preview는 별도 앱이다. 일반 API는 `18081`이며 APK에 주소가 고정되므로 다른 주소를 사용하려면 재빌드한다. `run_backend.py`는 자동 빌드하지 않으므로 Backend 코드 수정 후에는 Maven 빌드와 재시작이 필요하다.
