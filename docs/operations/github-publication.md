# GitHub 업로드 준비

확인일: 2026-09-23. 로컬 저장소의 업로드 후보를 정리한 기록이다.
GitHub 저장소 생성, remote 등록, push, 앱 배포는 수행하지 않았다.
프로젝트 파일은 Git index에 준비했으며 프로젝트 커밋은 아직 만들지 않았다.

> 위 내용과 아래 초기 검증 결과는 2026-09-23 준비 시점의 기록이다.
> 2026-10-05 README 개편에서는 공통 UI·공개 병원 정보·합성 건강정보 캡처 10장을
> 직접 검토해 `docs/screenshots/`의 공개 사본으로 추가했다.
> [화면별 출처·metadata 검토 범위](../screenshots/README.md)를 따르며,
> 실제 계정 QA 원본의 제외 정책은 유지한다.

## 포함·제외 범위

- 포함: 앱·서버 소스, 계약, synthetic 테스트, 의존성 lockfile, 공개 원천 자료,
  임상 검수표, 앱 아이콘·가이드 일러스트, 실행 문서.
- 제외: `.env`와 환경별 파일, `.runtime`, `.tools`, 인증키·credential 파일,
  Android/iOS 서명키·프로비저닝 파일, 로컬 DB·덤프, 빌드 결과, 로그,
  `output`, `tmp`, 실제 계정 QA 캡처·UI dump·HTTP 기록.
- `docs/qa`는 기본 제외한다. [공개 원천 입력 네 파일](../qa/README.md)과
  안내 문서만 예외이며, 기존 테스트 경로와 source matrix 해시를 유지한다.
- `docs/ui/references`의 원본 첨부 자료는 제외한다. 앱에서 사용하는 검증된
  아이콘·일러스트와 재생성에 필요한 후보 원본은 포함한다.
- `.env.example`은 비밀 값이 비어 있는 템플릿으로 포함한다.
- 문서·생성 기록의 개인 홈 디렉터리 경로는 일반화했다.
- Backend Docker context도 허용된 빌드 입력만 전송하도록 제한했다.

제외된 원본 파일은 삭제하지 않았다. 기존 문서의 일부 QA 링크는 로컬에서만
열린다. `.env`나 인증키를 clone에서 자동 복구하지 않으며 각 실행 환경에 별도로
설정한다. 현재 개발 DB의 암호화 키를 재생성하거나 교체하지 않는다.

## 업로드 전 검사

macOS에서는 `brew install gitleaks`로 설치한다. 이번 검증 버전은 8.30.1이다.
CI는 같은 버전의 Linux 배포본과 SHA-256을 고정한다.

새 clone마다 로컬 hook 설정이 필요하다. Git 설정은 clone으로 전달되지 않는다.

```sh
git config --local core.hooksPath .githooks
git add .
python3 scripts/check_publication.py --history
python3 scripts/test_publication.py
git diff --cached --stat
```

`check_publication.py`는 변경분만이 아니라 **전체 index의 실제 파일 내용**을
검사한다. 작업 디렉터리에서 값을 지웠어도 index에 남아 있으면 차단한다.
검사 중 만들어지는 복사본·보고서는 접근이 제한된 임시 폴더에만 두고 종료 시
제거한다. 값 자체는 검사 출력에 표시하지 않는다.

검사 내용:

- index에 강제로 추가된 ignore 대상 파일, symlink/submodule, 충돌 상태 거절.
- 파일당 50 MiB 초과 거절.
- Gitleaks 기본 규칙 및 NMC URL/config key, 직렬화된 인증키 규칙 검사.
- 로컬 `.env`의 API 키·DB 비밀번호·지도 Client ID와 `.runtime/auth-*`의
  인증키·credential 실제 값을 메모리에서 대조. 지도 Client ID도 로컬 설정으로 유지.
- `--history`에서는 로컬 Git refs의 과거 내용까지 비밀정보 검사.

로컬 pre-commit hook은 index 검사를 실행한다. Gitleaks가 없거나 검사가 실패하면
커밋을 중단한다. 강제 추가나 hook 우회 대신 원인을 해결하고 다시 stage한다.
CI에도 검사와 회귀 테스트를 추가했다. Actions 권한은 `contents: read`이며
checkout credential은 남기지 않는다. QA 자료를 Actions artifact로 올리지 않는다.

## 검증 결과

공개 후보만 별도 폴더에 복원하여, 기존 `.env`·DB·QA 원본 없이 확인했다.

| 검사 | 결과 |
|---|---|
| index 비밀정보·비공개 경로 검사 | PASS, 탐지 0건 |
| 기존 Git history 검사 | PASS; 작업 전부터 비어 있는 초기 커밋 1개 |
| 보안 검사 회귀 테스트 | 8 tests PASS; 강제 추가·오래된 index·history 탐지 포함 |
| Flutter 의존성 복원 | offline pub get PASS |
| flutter analyze | PASS, No issues found |
| flutter test | 334 PASS / 1 기존 skip |
| Backend 원천·질환 검증 테스트 | 9 PASS / 0 failure / 0 error |
| clinical review validator 및 테스트 | PASS, 11 tests PASS |
| v0.5 evidence validator / 공식 원천 확인 | PASS |
| approval generator dry-run | APPROVED=0, output 없음 |
| 앱·서버 런타임 소스 | 이번 보안 정리에서 변경 없음 |
| GitHub Actions 실제 실행 | NOT RUN, 업로드하지 않음 |
| 전체 Backend 통합 테스트 / Android·iOS 재빌드 | 이번 정리에서는 NOT RUN |

보안 회귀 테스트는 임시 저장소에서 임의 생성한 가짜 비밀값만 사용한다.
실제 사용자 데이터로 로그인하거나 SMS·전화를 실행하지 않았다.

v0.4·v0.5·review classes와 source matrix 원문은 작업 전후 해시가 동일하다.

| 불변 입력 | SHA-256 (before = after) |
|---|---|
| v0.4 | `32a5f98da61178b882a940ea061a55e981febb0900d995ec88356d31b8dadd84` |
| v0.5 | `bd5014127bf2db7bb315efd50411811ca2ce172c2fb9148dfe4884d7d158cf12` |
| source matrix | `309eacdbb321c63883ee88ef589a35e78fdd80454c87ff3f66874ed41a874eee` |
| reviewed source matrix | `2418fcfccdb2bd3d462463f769eb3a782aa997b07b984226dc141f2a8b41fee4` |

DRAFT 61 / APPROVED 0 / public mappings 0 / clinical PENDING 61을 유지한다.
Production flag를 변경하지 않았다.

## 이후 실제 업로드할 때

1. 위 검사와 `git diff --cached --stat`로 커밋 대상을 다시 확인한다.
2. 공개될 Git 작성자 이름·이메일을 확인한 뒤 로컬 커밋을 만든다.
3. 별도로 정한 GitHub 저장소와 공개 범위를 확인한 뒤 remote를 등록하고 push한다.
4. 업로드 후 Actions 결과를 확인한다. 원격 실행 결과를 로컬 검사로 대신하지 않는다.

현재 문서는 2~4단계의 실행 기록이 아니다. 실제 업로드는 아직 하지 않았다.
`.env`, 키, 원본 QA 폴더를 웹의 파일 업로드 기능으로 직접 올리는 방식은 이 로컬
hook의 보호를 받지 않는다.

검사 통과는 비밀정보·개인정보의 절대 부재나 앱 전체의 보안 인증을 의미하지 않는다.
이미지·PDF 속 개인정보는 자동 판별하지 않으므로 새 자료는 별도 확인한다.
향후 키가 외부에 노출됐다면 파일 삭제만으로 해결되지 않으며 발급처에서 폐기·교체하고
이력도 정리해야 한다. 이번 로컬 조사에서는 키 노출을 확인하지 않아 키를 교체하지 않았다.

Oracle 운영 서버의 TLS·비밀정보 관리·백업, Play Store 출시 설정과 개인정보 처리방침,
외부 자료의 재배포 권한 검토는 이 Git 업로드 준비와 별도로 다룬다.
