# 119 응급정보 문자 준비 v1 — 2026-09-22

사용자 확인 → 항목 선택 → OS 문자 작성 화면(수신자 119, 본문 입력) → 사용자가 최종 전송.
전화 연결과 문자는 독립된 신고 수단이다. 자동 첨부/사건 병합이나 접수를 보장하지 않는다.
실제 긴급 상황에서는 119 통화 안내가 우선이다.

## 기존 모델과 포함 범위

- Backend HealthService와 Dart EntryStatus의 wire는 `UNSET/NONE/RECORDED`다.
  요청에서 NOT_SET이라고 부른 상태는 기존 `UNSET`에 대응한다. schema 변경 없음.
- 기저질환: 구조화 STANDARD displayName / CUSTOM customName. 기존 same-user,
  same-consent local condition owner가 있으면 기기 저장 기록도 미리보기로 확인한다.
  Legacy 표준 선택은 기존 local migration이 확인한 이름을 사용한다. 이름 대신 ID만
  남은 항목은 SMS에 ID를 넣지 않는다. 질환→진료과 추론은 포함하지 않는다.
- 알레르기: RECORDED 원문, NONE은 없음, UNSET은 생략.
- 복용약: 저장된 이름과 사용자가 입력한 복용 메모. NONE은 없음, UNSET은 생략.
- 응급 메모: 기존 free text. 빈 값/공백은 생략. 최대 2000자. 모델에는 note status나
  최초 입력 이력이 없어 빈 값과 한 번도 입력하지 않은 값을 별도로 영속 구분하지 않는다.
- 위치: 기존 location owner의 최근(1분 이내) fix 또는 이미 허용된 현재 위치 조회.
  주소/geocoder owner가 없어 좌표만 표시한다. 새 권한이나 역지오코딩 요청 없음.
  위치 조회는 최대 3초이며 조회 중/실패에도 위치 없이 작성 가능하다.
- 이름/나이/보호자 연락처는 canonical health snapshot에 없어 제외했다.
  로그인 전화번호, userId, token, consentEpoch, version, diseaseId 등 내부 metadata 제외.

`lib/features/emergency_sms/emergency_sms_formatter.dart`의 `emergencySmsFields`가
허용 필드를 고르고 `formatEmergencySms` 하나가 미리보기 전체 본문과 composer 본문을 만든다.
항목별 체크를 해제할 수 있다. 긴 정보의 요약은 5줄이며 전체 본문 disclosure에서 원문을 확인한다.
전송 직전에 동일 계정/session/consentEpoch와 현재 권한, health version, 활성 route를 재확인한다.
동의 철회, 계정 변경, background는 기존 MemberSecurityScope/MemberController 보호를 적용한다.

## Native 구현과 개인정보

기존 url_launcher는 공식 HTTPS 링크에 재사용한다. Apple의 공식 sms URL 규격은 본문을
허용하지 않으므로 비공식 `sms:&body=`에 의존하지 않는다. 추가 package 없이 별도
`eroute/emergency_sms` MethodChannel로 percent-encoded 본문만 전달하고 native에서 한 번 decode한다.
Android는 `ACTION_SENDTO`, `smsto:119`, `sms_body`; iOS는 MessageUI의
`MFMessageComposeViewController.recipients/body`, 사용자 완료/취소 시 dismiss를 사용한다.
AppDelegate는 현재 foreground scene의 key window에서 composer를 표시한다.
`canCompose`는 Android의 SENDTO handler와 iOS의 `canSendText()`를 읽는다.
지원하지 않는 기기에서는 preview에 제한 안내를 표시하고 문자 앱 열기만 비활성화한다.
전화 및 닫기는 유지한다. Android의 `queries`는 smsto handler 조회용이며 새 권한이 아니다.
MessageUI는 활성 scene/presenter와 중복 presentation을 확인하고, channel 응답은
presentation 완료 시 한 번만 돌려준다. delegate는 본문을 비우고 dismiss만 담당한다.

OS가 최종 Send 버튼을 소유한다. SEND_SMS 권한, SmsManager, background send, backend
전송, 공식 시스템 API 연동 없음. ERoute는 body/URL을 기록·저장·복사하지 않는다.
OS 문자 앱이 작성 내용을 보관할 수 있으며 그 시점부터 작성 화면은 OS/문자 앱 소유다.
119 안심콜 링크는 공식 안내 페이지를 연다. 데이터 등록/sync는 하지 않는다.

## 공식 근거 (확인일 2026-09-22)

- 소방청 [119 비긴급 신고 자제, 다매체신고 적극 활용](https://www.nfa.go.kr/nfa/news/pressrelease/press/?cntId=1902&mode=view&pageIdx=1&searchCondition=all):
  119 문자 신고와 사진·동영상 첨부를 안내한다.
- 정부 정책브리핑 [알아야 산다! 119를 만나는 다양한 방법](https://www.korea.kr/news/policyNewsView.do?newsId=148929801):
  문자/사진/영상 신고 및 **공식 119신고 앱**의 GPS 위치 전달을 설명한다.
  이 앱의 기능을 ERoute 연동 근거로 해석하지 않는다.
- 소방청 [119 안심콜서비스](https://www.nfa.go.kr/nfa/safetyinfo/emergencyservice/),
  [안심콜 FAQ](https://www.nfa.go.kr/nfa/communication/0018/0006/):
  병력 등 사전 등록 정보를 신고 시 출동대가 활용하는 공식 서비스다.
  소방청 사이트 일부 직접 요청에는 방문자 확인 페이지가 표시될 수 있다.
- Android Developers [Common intents — Messaging](https://developer.android.com/guide/components/intents-common#Messaging):
  ACTION_SENDTO/smsto, sms_body로 작성 화면을 연다.
- Apple [SMS Links](https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/SMSLinks/SMSLinks.html):
  sms URL에는 본문을 포함하지 않는 공식 규격.
- Apple [MFMessageComposeViewController](https://developer.apple.com/documentation/messageui/mfmessagecomposeviewcontroller):
  OS 표준 메시지 작성 화면으로 recipient/body를 제공하고 최종 전송은 사용자에게 맡긴다.

## 변경하지 않은 경계

DiseaseCatalog, matcher, EXACT ring/clustering/search count/order/radius, v0.5,
consent wire, 119 전화 dialer owner 및 production gate, emergency guide canonical
text는 변경하지 않는다. DRAFT 61 / APPROVED 0 / public mappings 0 유지.

## 검증

[최종 Android/iOS QA](../qa/emergency-personalization-ios-2026-09-22/README.md)에
실제 로그인 계정, Android Messages composer, iOS Simulator build/불가 처리와
physical iPhone NOT RUN을 구분해 기록한다. 전화는 Mock 정책을 유지한다.
단위 테스트는 fake SMS launcher를 사용하고, 별도 native QA는 실제 OS composer를
열어 recipient/body를 확인한 뒤 작성 중인 본문을 지우고 돌아온다. Send는 누르지 않는다.
실제 계정의 건강정보 본문은 로그나 QA screenshot에 보관하지 않는다.
