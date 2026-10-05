# QA 자료의 Git 공개 범위

이 폴더의 기기 캡처, UI dump, 로그인 검증 응답, HTTP 기록, 로그는 기본적으로
Git에서 제외한다. 실제 계정·건강정보·위치·세션이 포함될 수 있으므로 로컬 원본을
유지하고 공개 저장소, GitHub Issue, Actions artifact에 그대로 첨부하지 않는다.
기존 문서의 QA 링크 일부는 이러한 로컬 자료를 가리키며 clone에는 포함되지 않는다.

아래 네 파일만 공개 원천에 기반한 질환→진료과 검증 입력으로 포함한다.
사용자의 건강기록이 아니며, 기존 validator와 테스트가 해당 경로·해시를 사용한다.

- `disease-evidence-v04-2026-09-18/review-inputs.json`
- `disease-catalog-batch2-2026-09-18/review-inputs.json`
- `disease-evidence-v05-2026-09-19/source-matrix/eroute-disease-source-matrix-v05.json`
- `disease-evidence-v05-2026-09-19/source-matrix/eroute-disease-source-matrix-v05-reviewed.json`

새 QA 이미지를 공유해야 한다면 별도의 synthetic 계정으로 재현하고 이미지와
metadata를 직접 검토한 뒤 공개 범위에 명시적으로 추가한다. 비밀정보 스캐너는
이미지 속 개인정보를 판단하지 못한다. `git add -f`로 제외 정책을 우회하지 않는다.

2026-10-05 README 소개용으로 공통 화면·공개 병원 정보·합성 건강정보 캡처 10장을
검토해 [공개 스크린샷 폴더](../screenshots/README.md)에 사본으로 추가했다.
화면별 출처와 해시는 해당 폴더에 기록하며, 이 QA 원본 폴더의 제외 범위는 유지한다.
