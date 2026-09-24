# 응급 가이드 v1 구현·출처 대조 기록 (2026-09-22)

현재 canonical은 `apps/mobile/assets/content/emergency-guides/v1/`의 JSON이다.
`emergency-guides-v1.md`는 `python3 scripts/verify_emergency_guides.py --write-markdown`으로 생성한다.
이전 `emergency-guides/drafts/` 및 unbundled `assets/guide_review/ko/`, `assets/guides/ko/`는 과거 조사·부분 원고이며 앱 입력이 아니다.

## 조사 및 소유권

- 홈 진입: EmergencyLandingState의 기존 `/emergency-tips`, `/first-aid`.
- 목록/카드/상세: GuideIndexPage, _GuideTopicCard, GuideDetailPage, _GuideReader 확장. ERouteScaffold, ERouteCard, 기존 테마·NotoSansKR 유지.
- repository: AssetGuideRepository 유지. 기존 publication 승인 manifest 의존을 이번 사용자 지시의 SOURCE_GROUNDED_DRAFT bundle 정책으로 교체. 원격 API 없음.
- JSON: 기존 assets convention 안에 content/emergency-guides/v1/ 사용. manifest + emergency-actions.json + first-aid.json 3개만 공통 번들.
- 119: EmergencyCallCoordinator 및 기존 확인 dialog, shared busy state, MockEmergencyDialer 유지. 새 전화 helper 없음.
- 출처: HttpsGuideSourceLauncher 재사용. 공식 HTTPS allowlist, 외부 앱 연결, 실패 시 본문 유지. 웹뷰 없음.
- 그림: 기존 직접 생성된 ERoute topic assets의 generation.json/manifest.json 확인 후 재사용. 새 공식 이미지 다운로드 및 PDF 그림 번들 없음. 기존 이미지 없는 항목에는 테마 article 아이콘.
- 일괄 placeholder 검색 결과 가이드 모듈의 ‘본문 준비 중’, ‘준비 중’ 제거. 약 검색/병원 즐겨찾기 등 다른 기능 문구 유지.

## 문안 입력과 과거 원고 차이

2026-09-22 사용자 최초 요청의 119 4개·CPR·AED·영아 기도폐쇄 핵심 문안과 후속 메시지의 10개 완성 문안을 입력했다.
후속 10개 본문·summary는 원문 그대로 구조화했다. 단어/순서/임상 조건을 새로 보충하지 않았다. WHEN과 section intro를 분리하고 벌 쏘임의 EMERGENCY type을 명시적으로 지원했다.

‘기존 7개 + 새 10개’를 단순 append하지 않았다. 기존 지혈·화상은 후속 문안과 겹치므로 대체하고, 새 인계 항목·영아·성인소아 기도폐쇄 등 고정 ID 기준으로 4+13을 구성했다. 일곱 lowercase 경로는 alias로 유지한다.

| 과거 부분 원고 | 차이 / 처리 |
|---|---|
| 신고·위치·도착 전 | 과거 S12 정책브리핑 부분 원고 대신 이번에 지정된 소방청 119 자료와 사용자 입력 사용. 인계를 별도 항목으로 분리. 과거 표현을 병합하지 않음. |
| CPR | 과거 원고의 ‘시작·중단 조건 미확정’ 메모는 의료절차가 아님. 이번 사용자 핵심 문안만 사용. 이전 미확정 메모를 승인 완료로 바꾸지 않음. |
| AED | 과거의 기기별 버튼/5주기 검토 메모를 가져오지 않음. 사용자가 지정한 음성안내와 6단계만 사용. |
| 외부 출혈·상처 → 외부 출혈·지혈 | 과거는 골절·관통상을 일괄 제외했으며 새 문안은 ‘골절이 의심되는 부위나 물체가 박힌 관통상’에 대한 무리한 압박 금지. 범위 차이를 임의로 통합하지 않고 새 입력을 독립적으로 사용. |
| 열에 의한 화상 → 화상 | 과거는 열화상 한정 및 진료 전환 미기재. 새 입력은 ‘화상’ 제목과 진료 도움 문장을 포함. 과거의 범위 제한/미완성 설명을 새 문안에 병합하지 않음. |

이는 사용자 입력 반영이며 의료전문가 승인이나 이전 검토 질문의 임상 해결을 선언하지 않는다.

## 출처·이용조건 확인

- [소방청 응급처치 안전교육 목록](https://www.nfa.go.kr/nfa/safetyinfo/lifesafety/0001/)에서 전체 13개, 제목·게시일을 확인했다.
- 개별 cntId: CPR 3 / AED 4 / 기도폐쇄 6 / 절단상 7 / 벌 8 / 뱀 9 / 코피 10 / 지혈 11 / 화상 12 / 열손상 16 / 한랭손상 17 / 경련 19 / 영아 20.
- 13개 게시물 각각의 ‘제 1유형’ 표시를 HTML에서 확인했다. 증거: `docs/qa/emergency-guide-content-v1-2026-09-22/source-checks.json`.
- [119 구급신고 요령](https://www.nfa.go.kr/nfa/safetyinfo/emergencyservice/119emergencydeclaration/)과 [119 구급차 도착 전 준비](https://www.nfa.go.kr/nfa/safetyinfo/emergencyservice/emergencydeclarationbefore/)는 본문 이미지의 HTML 대체 텍스트로 전달 내용·위치 단서·동행인 역할·인계를 확인했다. 게시일 미표시 null, 개별 license 미확인 UNCONFIRMED. 해당 4개 ID 모두 이 정책을 사용한다.
- 일부 web 요청은 방문자 확인/검색오류 페이지였다. 동일 공식 URL의 직접 HTTPS HTML 읽기로 게시물 제목·날짜·이용조건을 재확인했다. 사이트 전체 정책으로 license를 추정하지 않았다.

## KDCA 최신 기준 비교 범위

[2025년 한국 심폐소생술 가이드라인](https://www.kdca.go.kr/bbs/kdca/49/309908/artclView.do): 작성 2026-01-29, 최종수정 2026-02-09, 공공누리 제4유형(출처표시·상업적 이용금지·변경금지).

첨부 260209 PDF 531쪽을 임시 폴더에서 텍스트로 읽어 대조했다. PDF SHA256: `62e84596a95eb57146b36861afa104c8a3687c8f1c966d646182dbe60cb12d2c`. PDF/그림/캡처/긴 원문은 앱과 저장소 산출물에 추가하지 않았다. 이번 본문은 사용자 입력이며 KDCA 문단의 변형·장문 복제가 아니다.

- CPR: 인쇄쪽 57–70의 반응·정상 호흡 확인, 신고, 압박 속도/깊이, 30:2와 대조.
- AED: 81–84의 음성안내, 맨 가슴 패드, 분석·충격 중 접촉 금지, 즉시 CPR 재개와 대조.
- 성인·소아 기도폐쇄: 86–88, 297–298의 기침/심한 폐쇄 구분, 등 두드리기/복부 밀어내기, 의식 소실 시 CPR, 보이지 않는 이물 훑기 금지와 대조. 사용자 입력에 없는 횟수·예외를 추가하지 않음.
- 영아 기도폐쇄: 298쪽의 5회·5회 교대와 반응 소실 시 CPR, 보이지 않는 이물 제거 금지를 대조. 최신 문헌의 손 기법 세부사항은 제공 문안에 없어 추가하지 않음. 입력 문안에 과거 두 손가락 기법은 없으므로 해당 기법과의 충돌 문장을 앱에 가져오지 않음.
- 벌 쏘임: 497–499쪽 아나필락시스의 신고/도움 요청에 따른 자가주사기 도움과 대조. 약물 용량·재투여·처방·진단 절차 추가 없음.
- 경련: 499–500쪽의 보호·관찰·억제/입안 물건 금지와 대조. 사용자 입력에 없는 시간 기준/추가 절차를 생성하지 않음.
- 나머지 항목에 KDCA 최신성 검증을 일괄 부여하지 않았다. latestValidation은 위 6개에만 존재한다.

sourceCheckedAt은 위 기술적 자료 확인일이다. 모든 humanReviewedAtUtc는 null이며 상태는 SOURCE_GROUNDED_DRAFT다. 최신 기준 출처 표시는 완전한 임상 검증/production 의료승인을 뜻하지 않는다.
