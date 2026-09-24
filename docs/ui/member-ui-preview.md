# 회원 UI 미리보기

## 적용 범위

`eroute-member-ui-v1.png`를 기준으로 만든 실제 Flutter 회원 위젯이다. 승인 후 같은 위젯을 일반 앱의 실제 Repository에 연결했다. 현재 일반 앱의 가입·저장·지도 검수는 [회원 실제 연동 보고](../qa/member-real-integration-2026-09-15/README.md)를 참조한다. 아래는 가상 데이터로 동작하는 Preview의 사용법과 이력이다. PASS·SMS는 이번 연동 범위에 없다.

새 화면은 `apps/mobile/lib/features/member_ui/`에 있고, `lib/preview/`는 가상 데이터와 검수 도구만 소유한다. 별도의 데모 화면 복제본이 없다. 기존 Riverpod/Repository 패턴과 SessionController를 재사용한다.

## 실행과 식별

저장소 루트에서:

```sh
cd apps/mobile
flutter run -d emulator-5554 --debug --flavor preview \
  -t lib/main_ui_preview.dart --dart-define=EROUTE_AUTOMATION=true
```

- 대상: `emulator-5554`, sdk gphone16k arm64, Android 17 / API 37.
- 앱 이름: **ERoute UI Preview**.
- Application ID: `com.eroute.eroute_mobile.preview`.
- 버전: `0.1.0-ui-preview`, versionCode `1`.
- 일반 dev ID: `com.eroute.eroute_mobile`. Preview와 별도로 설치된다.
- 화면 상단: **UI 미리보기 · 가상 데이터**. 펼치기 버튼으로 검수 도구를 열고 접는다. 달/해 버튼은 테마, `Tt`는 글씨 1/2배, 조절 버튼은 화면·상태 선택이다.
- 테스트 로그인: `010-1234-5678` / `preview-password-only`. 다른 비밀번호는 실패를 재현한다. 이 정보는 preview 도구에만 표시된다.
- 저장·가입·삭제는 메모리에서만 처리하고 “미리보기에서 반영됨”으로 표시한다. 앱 재시작 또는 시나리오 변경 시 초기화된다.
- 시나리오 변경은 검수 전용 리셋이다. 현재 초안을 초기화한다는 설명을 설정 창에 표시한다.

## 검수할 흐름

| 화면/상태 | 조작과 기대 결과 |
|---|---|
| 내 응급정보 | 저장된 원문과 상태를 카드로 확인하고 해당 편집 화면으로 이동 |
| 빈 상태 | 4개 항목의 미입력 표시. 알레르기·기저질환·복용약만 명시적 없음 선택 가능 |
| 항목 편집 | 질문형 선택(있어요/없어요/아직 입력 안 함)/자유 입력, 저장 중 중복 제출 방지, 실패 시 입력 유지 |
| 버전 충돌 | 설정에서 “저장 시 버전 충돌”, 편집 후 저장. 현재 초안을 자동 반영하지 않음 |
| 동의 충돌 | “저장 시 동의 변경”, 편집 후 저장. 초안 제거와 현재 권한 재확인, 건강정보 숨김 |
| 충돌 복구 | “최신 내용 확인”에서 초안 버리기를 명시적으로 확인. 권한 확인 후 원래 화면에서 항목을 다시 열어 편집 |
| 미저장 변경사항 | 설정에서 상태 선택 시 알레르기 초안 진입. 뒤로가기에서 계속 편집/버리기 |
| 복용약 | 목록 → 약 검색 → 제품 선택·확인 → 선택 메모 → 등록. 검색 실패/결과 없음에서 직접 입력 가능. 마지막 약 삭제 후 미입력 |
| 내 정보 | 중립적인 인사, 계정/보안/건강정보 그룹. 번호 변경·복구는 정책 미확정 안내 |
| 동의 필요 | 가입 동의와 별도로 건강정보 동의 확인. 실제 동의 증거 저장 없음 |
| 삭제/철회 | 응급정보 삭제는 약 유지, 약 삭제는 해당 약만, 철회는 모든 건강정보 삭제·계정 유지 |
| 삭제 실패/완료 | 서비스 삭제와 백업 파기 분리. 실패 시 재시도, 완료라도 백업 완료를 추정하지 않음 |

가입 동의 문구는 검토용이며 실제 운영 문안과 비밀번호 정책은 2차 단계에서 확정한다. UI의 전화번호 형식 확인은 검토용 한국 휴대폰 형식 검사이며 번호 소유·실명·연령 확인이 아니다. 응급 메모는 선택 문자열로 유지한다.

## 항목 저장 계약

`MemberUiRepository`는 UI용 경계다. 아직 일반 실행에 연결하지 않았으며, 미주입 상태에서는 실패한다. 새로운 HTTP API를 정의하거나 서버가 PATCH를 지원한다고 가정하지 않는다.

```text
HealthFieldEdit(field, baseVersion, consentEpoch,
                entry | note | medicationsStatus)
```

1. 현재 세션·동의가 유효해야 한다.
2. `consentEpoch`와 `baseVersion`을 원본의 현재 값과 비교한다.
3. 하나라도 다르면 거부하고 데이터는 변경하지 않는다. 최신 버전으로 자동 재제출하지 않는다.
4. 일치하면 선택한 항목만 교체한다. 나머지 원문·상태·복용약은 그대로 보존한다.
5. 성공 시 새 스냅샷·버전·저장시각을 반환한다.

`applyHealthFieldEdit`는 이 규칙을 순수 함수로 구현한다. 향후 기존 전체 PUT에 연결할 때 동일 버전 원본 스냅샷을 유지하고 해당 항목만 교체해야 한다. 최신 스냅샷에 오래된 편집 내용을 자동 병합하거나 누락 값을 빈 문자열로 채우지 않는다. 약 변경도 프로필 버전을 증가시키므로 열린 다른 편집기에 충돌을 발생시킨다.

초안은 기존 HealthDraft를 사용해 실제 편집부터 10분 동안 메모리에만 둔다. 사용자·세션 generation·consent epoch에 묶이며, 버전 충돌 시 자동 복원하지 않는다. 앱 전환/조회/동의 polling은 초안 기한을 연장하지 않는다. 세션·동의 상실 시 민감한 내용과 초안을 제거한다.

## 격리와 보안

- 새 일반 위젯에는 가상 계정·가짜 성공 조건이 없다. Preview 전용 ProviderScope에서만 메모리 구현을 주입한다.
- Preview AuthRepository는 HTTP를 모두 거부하고 실제 토큰/secure storage를 쓰지 않는다. 로그인 성공도 미리 정한 테스트 조건에 따라 결정한다.
- 정상 `main.dart`/`main_production.dart`의 import 그래프에는 preview가 없다.
- Android Gradle은 preview profile/release, 정상 flavor의 preview 진입점 빌드를 거부한다. 진입점도 assert가 아닌 runtime debug/flavor 검사로 보호한다.
- 기존 네이티브 민감 화면 보호 설정은 변경하지 않았다. 캡처용 privacy 구현은 가상 데이터만 있는 preview에 주입한다.
- 실제 인증/건강정보 테스트 서버를 실행하거나 계정/건강정보를 변경하지 않는다. 실제 PASS·SMS·전화 launcher도 실행하지 않는다.

## 재현 가능한 검증

```sh
# apps/mobile에서 실행
flutter analyze
flutter test --dart-define=EROUTE_AUTOMATION=true
flutter drive -d emulator-5554 --debug --flavor preview \
  -t integration_test/member_ui_preview_test.dart \
  --driver test_driver/member_preview_driver.dart \
  --dart-define=EROUTE_AUTOMATION=true
flutter test integration_test/member_dev_smoke_test.dart -d emulator-5554 \
  --flavor dev --dart-define=EROUTE_AUTOMATION=true
flutter build apk --release --flavor production -t lib/main_production.dart \
  --dart-define=EROUTE_AUTOMATION=true

# 아래 두 명령은 실패해야 정상이다.
flutter build apk --release --flavor production -t lib/main_ui_preview.dart
flutter build apk --release --flavor preview -t lib/main_ui_preview.dart
```

Flutter 통합 테스트와 release 빌드는 생성되는 plugin registrant를 공유하므로 순차 실행한다. `ANDROID_ADB` 환경변수에 adb 실행 파일 경로를 지정하면 드라이버에서 추가 OS 캡처를 시도한다. 최종 상태바·키보드 캡처는 실제 설치된 standalone preview에서도 따로 확인했다.

저장소 루트에서 production APK의 가상 데이터 제외도 검사한다:

```sh
python3 scripts/verify_member_preview.py \
  --apk apps/mobile/build/app/outputs/flutter-apk/app-production-release.apk
```

최종 실행 결과·캡처·빌드 해시는 `docs/qa/member-ui-preview-2026-09-15/`에 기록한다. 위젯 캡처와 에뮬레이터 캡처를 구분한다. 위젯 검수는 320/430/720dp, 밝음/어두움, 글씨 1/2배, 키보드 inset을 포함한다.

## 검색 기반 복용약 등록 보완

가상 제품 상태는 접을 수 있는 검수 도구의 설정에서 선택한다. 검색어 **가상해봄**은 같은 이름의 100 mg 정제, 200 mg 정제, 100 mg 캡슐을 반환한다. 모두 허구의 제품이며 실제 식약처 조회 결과가 아니다. 제품 ID도 preview 전용이다.

| 검수 상태 | 동작 |
|---|---|
| 함량·제형이 다른 제품 | 결과의 함량·제형을 확인하고 선택, 제품 확인 후 개인 메모 입력 |
| 결과 없음 | 검색어 수정 또는 약 이름 직접 입력 |
| 검색 실패 | 다시 검색 또는 약 이름 직접 입력 |
| 설명 없음 | 200 mg 정제 선택 → 설명 없음 문구 |
| 이미지 없음 | 사진 대신 이미지 없음 표시; 네트워크 이미지 요청 없음 |
| 선택 취소 | 검색 결과로 돌아가며 기록은 생성하지 않음 |
| 제품 선택 후 저장 실패·충돌·철회 | 기존 시나리오와 조합 가능, 메모 보존/권한 상실 제거 규칙 동일 |

### 화면용 데이터 계약 — 실제 API 필드는 미확정

가정한 `MedicationProduct` 필드는 `source`, `sourceLabel`, `id`, `name`, 선택적인 `strength`, `form`, `manufacturer`, `description`, `imageAsset`이다. `imageAsset`은 로컬 화면용 자리이며 실제 API의 이미지 필드가 아니다. 서버의 실제 필드·페이징·검색 규칙·제품정보 갱신 정책은 확정하지 않았다. 이번 검색은 소규모 메모리 목록에서만 수행한다.

사용자 기록 `MedicationEntry`는 기존 ID·버전·이름·메모·시각을 유지하며, **명시적으로 선택했을 때만** 별도의 nullable `product` 스냅샷을 갖는다. 같은 제품명을 입력한 수동 기록은 연결하지 않는다. 제품을 선택한 기록의 편집은 개인 메모만 바꾼다. 제품 설명을 개인 메모에 복사하거나 제품정보를 복용 판단으로 해석하지 않는다.

`saveMedication(original?, product?, name, note, baseVersion, consentEpoch)`는 UI/메모리 Repository 경계의 확장이다. 실제 Backend, HTTP 계약, DB는 변경하지 않았다. 전체 건강정보 버전·동의 epoch와 개별 약 버전을 기존 방식으로 검사하며, 다른 항목과 제품 연결을 보존한다.

이번 비교 캡처·검수 결과는 `docs/qa/member-ui-refinement-2026-09-15/`에 별도 기록한다.


## 회원 UI 마감 (2026-09-15)

- **UI Preview 완료 여부와 실제 인증·식약처 연동 여부를 별도로 검수한다.** 최종 결과·실행 명령·APK 해시·캡처는 [이번 검수 보고](../qa/member-ui-finalization-2026-09-15/README.md)에 기록한다.
- 기존 검색/선택 위젯과 Repository를 재사용한다. `없음 · 직접 확인`은 사용자가 건강정보를 직접 확인했다는 뜻이며 번호 소유·실명 확인이 아니다.
- 복용약 신규 기록은 `검색 → 제품 선택 → 제품 확인 → 복용 메모 · 등록으로 → 선택 메모 → 등록 → 목록`이다. 기존 기록의 수정은 `저장`이다. 선택·화면 이동만으로 등록되지 않는다.
- 검색 실패와 0건은 별도 상태다. 이때 직접 입력을 선택하거나, 제품 확인에서 `선택 대신 직접 입력`으로 전환할 수 있다. 이 전환은 제품 연결을 넘기지 않는다.
- 제품 설명이 없으면 `설명 미제공`, 사진이 없으면 일반 약 아이콘과 `제품 이미지 없음`을 표시한다. 긴 제품명은 검수 설정의 `긴 제품명`에서 검색어 `가상해봄`으로 확인한다.
- 새 HTTP 클라이언트도 Preview 진입점의 `PreviewNetworkGuard`가 차단한다. 일반 앱의 네트워크 설정·라우팅·민감 화면 보호는 그대로다.
- 등록 응답 이후에도 현재 userId/sessionGeneration/consentEpoch 및 접근 상태를 확인한다. 오래된 계정·철회 응답은 성공 안내나 목록 이동을 만들지 않는다.
- 응급정보 삭제는 알레르기·기저질환·응급 메모만 대상으로 하고 복용약·동의·계정을 유지한다. 전체 건강정보 삭제/철회는 약을 포함하되 계정·로그인을 유지하며 백업 파기 상태를 별도로 표시한다.
