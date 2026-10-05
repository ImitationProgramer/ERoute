# README 공개 스크린샷

2026-10-05 README 개편을 위해 기존 2026-09-22 QA 캡처 중 공개 가능한 화면 10장을 선별했다.
실제 앱·에뮬레이터·Preview QA에서 나온 화면이며, 새로 생성한 목업이 아니다.
원본 이미지의 픽셀·비율을 유지하고 GitHub README에서 표시 너비만 지정한다.

## 화면별 범위

| 파일 | 화면과 데이터 |
|---|---|
| [home-android.png](home-android.png) | Android 홈. 계정·건강정보가 표시되지 않는 공통 화면 |
| [hospital-map.png](hospital-map.png) | Android 에뮬레이터의 서울 중심 지도, 개인화 OFF. 공개 병원 정보. 마커 군집화 적용 전 캡처 |
| [guide-list.png](guide-list.png) | Android 응급처치 가이드 목록. 공통 콘텐츠 |
| [hospital-detail.png](hospital-detail.png) | 공개 병원 주소·대표전화·병상 정보 미제공 상태. 개인 건강정보 없음 |
| [hospital-hours.png](hospital-hours.png) | 공개 병원 진료과목·요일별 진료시간·출처. 개인 건강정보 없음 |
| [health-light.png](health-light.png) | Preview 합성 건강정보, 412dp·글자 100%·라이트 |
| [health-dark.png](health-dark.png) | Preview 합성 건강정보, 412dp·글자 100%·다크 |
| [guide-reader.png](guide-reader.png) | Preview 가이드 상세, 412dp·글자 100% |
| [guide-large-dark.png](guide-large-dark.png) | Preview 가이드 상세, 320dp·글자 200%·다크 |
| [home-ios.png](home-ios.png) | iOS Simulator 홈. 계정·건강정보가 표시되지 않는 공통 화면 |

건강정보는 `emergency-finish-2026-09-22`의 합성 fixture다. 실제 계정의 회원 화면,
질환 개인화 화면, 문자 본문, 로그인 화면은 포함하지 않았다. 병원 전화번호·주소는
기관의 공개 정보이며 개인 연락처가 아니다. 지도는 에뮬레이터 QA 화면으로 사용자의
실제 이동 경로를 보여주는 자료가 아니다.

병원 수·거리·병상·진료시간은 촬영 시점의 화면 예시다. 현재 값 또는 현재 수용 가능을
뜻하지 않는다. 가이드 캡처는 UI 소개용이며 최신 의료 지침의 검증 자료가 아니다.
테스트 화면과 iOS Simulator 캡처를 물리 기기·실제 긴급전화·문자 발송 검증으로 해석하지 않는다.

## 공개 검토

- 10장 모두 화면을 직접 열어 계정 식별자, 개인 연락처, 실제 건강정보, 인증정보 노출 여부를 확인했다.
- PNG chunk와 EXIF를 점검했다. EXIF가 있는 3장은 해상도·방향·이미지 크기만 포함하며 GPS 정보가 없다. 텍스트 metadata chunk는 없다.
- 원본은 제외된 `docs/qa/`에 유지한다. 이 폴더의 검토한 사본만 공개하며 QA 원본 폴더의 제외 규칙은 변경하지 않는다.
- [manifest.json](manifest.json)에 원본의 저장소 기준 경로, 촬영일, 설명, SHA-256을 기록했다. 원본 경로는 로컬 추적용이며 clone에 없는 파일로 링크하지 않는다.

새 캡처는 동일하게 화면과 metadata를 확인한 뒤 공개 범위에 명시적으로 추가한다.
[QA 자료 정책](../qa/README.md) · [공개 전 검사](../operations/github-publication.md)
