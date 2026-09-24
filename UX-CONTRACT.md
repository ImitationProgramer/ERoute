# ERoute UX Contract

## Disease personalization preparation

- Backend versioned disease-department JSON is the only authority. Flutter downloads and verifies the document/hash; it has no manually maintained second catalog.
- v0.1 is DRAFT, public map highlight is disabled. No map toggle, marker/caption, list ordering/count, realtime badge or detail personalization is released. Only dev-debug synthetic comparison may opt into DRAFT matching.
- Member disease choice is optional and separate from the original free text. The editor never infers or preselects disease IDs from prose. Alias search filters choices; checkbox selection and purpose confirmation are both explicit.
- Save returns to the owning emergency-information screen only after the server save and authorized reload. Remove requires the shared confirmation and preserves raw text. Back with edits asks to discard. Failures retain memory-only drafts; reference failure offers retry; conflicts require latest-data review.
- RECORDED raw edits require reconfirmation. NONE/UNSET/profile deletion clear selection. Existing health consent, epoch/version, native privacy leases, ten-minute draft lifetime and logout/account-change/withdrawal cleanup apply to this screen.
- Exact DIRECT matches preserve all disease/department/source reasons. Unknown/missing/stale/broad data never mean care is unavailable. Match does not mean current treatment, emergency acceptance, ranking, visit or transfer recommendation.
- Public department requests contain only HPIDs; no personal disease or member identifier goes to provider requests, map SDK, analytics/logs or public cache keys.

## Navigation

- `/` opens the emergency landing page. `/map` opens the nationwide GPS/manual search. `/hospital/:hpid` loads stored Hospital Master and current observation data by HPID; the current search snapshot supplies distance and immediate fallback presentation.
- Landing to Map to Detail preserves normal back navigation. Returning from Detail preserves the Map controller, camera exploration, search snapshot, selection, and Sheet position.
- Every major page exposes the same Drawer. Opening, closing, or navigating the Drawer does not search the Backend.

## Emergency action

- Landing, Map, and Drawer use one `EmergencyCallCoordinator` and one busy state.
- A request reaches `EmergencyDialer.dial("119")` only after the user confirms in the app-owned dialog.
- Development, tests, CI, simulators, emulators, and device QA use `MockEmergencyDialer`. No automated path opens a phone URI.
- Production still requires all Dart and native release/physical-device/non-automation gates. Android opens `ACTION_DIAL`; iOS hands off to the OS confirmation. Neither automatically calls.

## Search and selection

- Search radii come only from `/api/v1/map-config`. Requested radius and effective response radius remain distinct.
- A successful search fits its center, effective radius, and every returned hospital. A MANUAL fit excludes a remote GPS marker.
- `selectedHpid` is the sole Map selection state shared by marker and list. A list tap selects it and opens Detail.
- Hospitals start icon-only. Only `selectedHpid` has a name: a native caption when it fits the usable viewport, otherwise a single accessible chip inside that viewport. Caption and chip are mutually exclusive; chip tap only reselects the same HPID.
- A successful search retains selection if that HPID remains in the results; otherwise it clears selection. Selection changes update only the old/new markers, never search, open Detail, fit the camera, or reset the Sheet. Marker IDs remain `hospital:{hpid}`.
- Sheet/viewport changes reposition attribution and the selected label without fitting. New successful search revisions own result fitting. Labels never move the camera, and heading only updates the location overlay. Zoom-dependent unselected captions remain future work; clustering follows the marker clustering contract below.
- Sheet, theme, heading, Drawer, and programmatic camera changes never search. A new successful result may fit; Sheet changes after user exploration may not force a zoom.

## Medical data

- Numeric values render only for `KNOWN` values with a numeric payload. A real zero stays zero. Missing, not-provided, unknown-code, and unverified values never become zero or unavailable.
- HVS01 is displayed as `일반 기준값`. It is not a total emergency-bed denominator.
- Stale snapshot, API failure, budget deferral, and not-provided states have distinct Korean labels. Rate deferral says `갱신 대기` with an explanation to refresh the map after a short wait; rolling-budget exhaustion says `조회 한도 도달` and explains the recent 24-hour limit. Render each status once, with a separate cause/recovery sentence. Only an existing snapshot adds `이전 정보`. A region mapping/validation failure says `실시간 정보를 불러오지 못했습니다.` and never exposes the internal error code. Source raw time and fetched time remain distinct.
- Unsupported detail fields use an explicit unavailable state. The UI never supplies fake hospital or medical data.
- Realtime rate-slot admission may wait within the active search deadline, but a returned deferred state has no background resume job or card polling. Guidance must request a later Map refresh and never promise automatic refresh or a midnight quota reset.
- Detail requests are database-only and never trigger an NMC request. `dutyTel1` is `대표전화1`; `dutyTel3` is `대표전화2` and is never relabeled as an emergency-room phone.
- A hospital phone action opens the operating system's number-entry screen only after a user tap. Invalid values and the emergency numbers 119/112 are rejected by this general contact path.
- Detail keeps an immutable HPID-matched Map seed for its screen lifetime and preserves prior successful detail through refresh failures. HPID-keyed requests cannot replace another hospital or resurrect disposed detail state.
- Only pending, previously unknown fields use static skeletons. Successful nulls show `정보 미제공`; failed unknown fields show a request failure with one retry action. Previous values remain readable with a page-level error badge. Existing Map beds never revert to loading because detail is pending.
- `basicInfo.NOT_REQUESTED` denotes no published static collection, not pending detail HTTP. A successful latest `LIVE_NOT_PROVIDED` replaces older bed data; HTTP errors never manufacture this status. Missing secondary contact alone does not make detail partial. Basic collection status stays independent from realtime coverage.
- UI contact labels are `대표전화` and `추가 전화번호`; API source fields and official labels stay intact. Phone availability requires valid normalized mainPhone, an available contact launcher, and no handoff in flight. 119/112 remain blocked even with allowed formatting or a leading plus. Automated contact tests use a fake; no native phone handoff is permitted.

## Session, theme, and accessibility

- Landing renders independently of asynchronous server session restoration. Protected routes use AuthGate and never construct a login from client success. Search and 119 have no auth guard. The existing authentication path is temporarily retained. PASS is excluded from the product direction; password Backend integration follows member UI approval.
- Theme defaults to the operating-system setting. Theme changes do not trigger search or camera fitting.
- Interactive targets are at least 48dp, icon controls have Korean accessible names, drag has a button alternative, and layouts support SafeArea, large text, narrow phones, landscape, and tablets.

## Hospital clinical information

- The clinical tab reads only the published Basic dataset included in the HPID Detail response. Tab switches/rebuilds reuse the same request. Detail refresh/re-entry may read Backend again but never calls NMC.
- `dataStatus` distinguishes not collected, provided records, and explicitly not-provided records. Empty departments alone never mean that a hospital has no departments. Only initial HTTP loading uses skeletons.
- Department names come from verified literal NMC tokens. Unknown strings remain an explicit information-check state. No specialty existence implies current treatment or acceptance.
- Hospital hours render Monday through holiday. Only `KNOWN` complete pairs render a time range. Missing is information not provided; malformed, special, partial and reversed values are information requiring confirmation. Never render open-now, overnight, 24-hour or ER schedules from these values.
- Always explain that published hospital hours can differ by department, are not ER operating hours, and should be confirmed before visiting.
- Failed/budget-deferred collection retains the prior published values with a separate status. An explicitly absent source record preserves a previous snapshot if present; neither absence nor blank departments deletes a hospital.
- Provider wall-clock input is formatted from the Backend parsed local timestamp and labeled when timezone is unverified. It is never converted or used for an age calculation. Raw provider timestamp strings remain Backend data. ERoute fetched timestamps are separate and follow device-local presentation.
- Detail uses an opaque theme surface toolbar and a bottom/side SafeArea around its single body scroller; Scaffold owns the top inset. Hospital names wrap naturally.

## Member authentication and health

- AuthRepository owns server transactions, opaque tokens and secure storage; SessionController is the only Riverpod session writer. AuthGate owns protected navigation. A successful login returns to the requested internal screen.
- Material TextField and DropdownButtonFormField own form behavior. Explicit UNSET/NONE/RECORDED states distinguish omitted health information from a user declaring none. ERoute theme tokens own appearance. Server versions prevent silent overwrites.
- Health consent is separate from signup. Withdrawal confirms the exact data categories and preserves the member account/session. Deletion status is separate from backup destruction; failures have retry, never false success.
- MemberHealthPage and HealthDraft own sensitive screen state. Native recent-app protection and Flutter masking are separate from draft deletion. A memory-only draft expires ten minutes after the last actual edit. Resume revalidates the user, session generation, consent epoch and data version. Network failure keeps the body covered with retry; notification failure is not withdrawal.
- Logout/account change/confirmed withdrawal/nonrenewable expiry clear health state and reject late responses. Foreground consent status polling is every ten seconds and does not count as user activity. There is no offline permanent health copy.
- Material AlertDialog owns cancel/destructive confirmation; SnackBar and inline semantic messages own feedback. Korean labels, light/dark themes, keyboard handling, narrow layouts and large text follow the existing product contract.
- Development account fixtures are explicitly bootstrapped, marked DEVELOPMENT and use real Backend sessions and owner checks. No real PASS, SMS or telephone launcher runs in development or automated QA.

Implementation and operations: `docs/auth/authentication-and-health.md`.

## Member UI phase one

Source: approved member UI direction and explicit preview-first decision (2026-09-15). This supersedes the previous PASS rollout direction; it does not relax current server authorization.

- New member UI uses phone + password. Typing a phone number never proves phone ownership, name or age. No PASS, SMS, account recovery shortcut or invented personal name is introduced.
- General signup consent and health consent are separate. Signup and health copy in preview is explicitly for review; no actual consent evidence or account/session is created. Phone change and password recovery remain visibly unavailable pending policy.
- `MemberUiRepository` is a UI port with no production default binding. Riverpod controllers own screen state; the existing SessionController remains the only session writer. Existing AuthRepository/session/owner checks, native privacy configuration, Backend, HTTP contract and DB migrations are unchanged.
- A `HealthFieldEdit` includes the field, value, baseVersion and consentEpoch. Check authority/epoch/version before applying a single-field edit to its complete original snapshot. Mismatched epoch or version rejects the command, with no merge or retry using a new version. The future PUT adapter must preserve all other fields from that same version; this is not a new HTTP PATCH API.
- Conflicts preserve the draft only while current authority is valid. Latest-state recovery requires explicit draft discard, checks authority, returns to the owning screen, and requires reopening the editor. Session or consent loss purges drafts. A fresh version is never silently adopted for a pending edit.
- Allergy/condition/medication state is UNSET/NONE/RECORDED. The note stays an optional string. Medication registration starts with search → explicit product selection → product confirmation → optional personal note → registration. Manual names remain an alternative after search failure/no results; deleting the last drug produces UNSET. Drug changes also advance the health-profile version.
- Save waits for repository acknowledgement and then returns to the owner screen. Failure retains input. Unsaved back navigation offers continue editing or discard. Memory-only drafts expire ten minutes after actual edit; app lifecycle, polls and retries do not extend expiry. Background UI is covered and resume revalidates authority. A poll connection failure alone is not withdrawal.
- Profile deletion clears allergy/condition/note and preserves medication records and consent. Medication deletion targets one medication. Consent withdrawal covers all health information and leaves the account/session. Service deletion and backup destruction are separate states.
- `main_ui_preview.dart` runs only in debug preview flavor. Preview uses memory repositories, a memory vault, fake privacy presentation and no HTTP; synthetic success is visibly labeled. The native privacy implementation is unchanged for actual screens. Preview app ID is distinct. Profile/release preview and production targeting the preview entrypoint are rejected.
- New canonical owners: forms = Material Form/TextFormField; state selector = wrapping ChoiceChip question/answers; confirmation = memberConfirm/AlertDialog; feedback = MemberNotice + memberFeedback/SnackBar; CRUD state = MemberController + MemberUiRepository; visual values = existing ERoute tokens/themes plus member-scoped category accents. Product search = MedicationSearchController/MedicationProductRepository; product details = MemberProductSummary. No new state framework.

### Fictional medication catalog preview

- The only catalog implementation is `PreviewProductRepository` injected by the explicit preview host. Its source label says fictional/UI review; it is not an MFDS response. No Backend/HTTP/DB changes, online photos, DUR, dosing, photo recognition or prescription history.
- `MedicationProduct` is an assumed UI model: source+id, product name, optional strength/form/manufacturer/description/local image asset. It is not an actual API schema. `MedicationEntry.product` is nullable and distinct from the user-entered name/note, retained from explicit selection only. Never infer a link from names or modify an existing record's link while editing a note.
- Search is submitted with the button or IME search. Text edits and clear invalidate pending results; an older response cannot replace the latest query. Results stay hidden while loading. Clearing returns to the initial state. A failed/no-result search offers retry/rewording and manual entry. Cancel returns without a write.
- Different strengths/forms retain distinct IDs. Missing descriptions, manufacturer and images have explicit empty states. Displaying product details does not create a personal record or provide medication advice.
- Registration returns to the medication list after acknowledgement and removes search/confirmation from the back stack. Conflict recovery also returns to the owner list after explicit draft discard and authorized reload. The original baseVersion/consentEpoch remain attached throughout the flow, never refreshed silently. Withdrawal/session changes clear search queries/results and protect personal note drafts using the existing security scope.


### Member finalization verification contract

Source: `docs/tasks/ERoute_Member_UI_Finalization_Task.md` (2026-09-15).

- Preserve approved member colors, typography and card hierarchy; `없음 · 직접 확인` describes user-declared absence, never identity verification.
- New medication commits use `등록`; existing record edits use `저장`. Product confirmation offers a separate manual-entry transition without transferring the product link. Missing description reads `설명 미제공`.
- Search stays explicit-submit and IME-safe, with no persistent query/URL state because this is a sensitive native mobile workflow. Clear immediately invalidates results and returns input focus.
- After a delayed acknowledgement, success feedback/navigation requires the original access identity and a successful authorized reload. Account/consent changes discard late acknowledgements.
- Preview entrypoint installs an HTTP-client guard in addition to repository injection. The screenshot driver's Flutter surface artifacts describe named test states; driver-side native screenshots after completion cannot represent those states and are not used as evidence.

## Member real integration contract

- Auth form: shared MemberAuthScreen + PasswordPolicy. Korean 010 identifier; NFC Unicode17 codepoints 15..128, no trim/casefold/truncation/required character classes; separate signup consent and age self-declaration. No identity verification assertion.
- API ownership: AuthRepository and SessionController; no anonymous health access. General router uses shared member_ui widgets, never Preview repositories. Internal return destination is preserved.
- Health DTO: atomic health-snapshot; original full snapshot for field PUT; medication baseVersion/consentEpoch mandatory, individual version additionally required for update/delete. Missing=400; stale=409; no automatic latest-value merge.
- Async behavior: server-confirmed feedback only; account/epoch-bound draft and responses; 10-minute memory drafts, no persistent health copy.
- Product capability: unavailable search with manual CRUD; MANUAL source/productCode null; no guessed products.
- Verification: PasswordHttpIntegrationTest, password_member_repository_test.dart, auth_health_integration_test.dart and final standalone general APK QA.

## Freshness polish contract (2026-09-15)

Source: `docs/tasks/ERoute_Freshness_UI_Polish_Task.md`.

- LIVE_AVAILABLE is coverage only: `병상정보 제공`. UNKNOWN source freshness says `원천 갱신시각 확인 필요`; collection expiry remains `이전 정보` with its own reason. Current NMC timezone stays unverified; no source age/threshold is inferred.
- `ERoute 수집` uses freshness.fetchedAt. Detail generatedAt and cache reads never replace it. RealtimeSummary is shared by list/detail; Master catalog age has a separate list explanation.
- Detail displays phone values only in Basic information and retains the existing action/validation/mock boundaries. No native phone launch during QA.
- Health consent entry says `동의 내용 확인하고 시작하기`; grant returns to the owning internal page after server acknowledgement and a confirmed authorized reload. Other management mutations stay on their existing page. Profile-only deletion says `응급 기록 삭제` and preserves medication, consent and account.

## Emergency guide content v1 (2026-09-22)

Source: the user's 2026-09-22 17-guide implementation brief and subsequent ten verbatim ERoute articles. This explicitly supersedes the 2026-09-15/16 guide publication gate; displaying a SOURCE_GROUNDED_DRAFT does not grant medical or production approval. Historical source/review records remain in `docs/content/emergency-guides/`.

| Capability | Canonical owner | Source of truth | Verification |
|---|---|---|---|
| Navigation / read | Existing GuideIndexPage, GuideDetailPage, AssetGuideRepository | Bundled `assets/content/emergency-guides/v1/` | All 17 IDs + seven legacy aliases; offline first load |
| Layout / typography | ERouteScaffold, ERouteCard, ERouteTheme, ERouteTypography | DESIGN.md / runtime Dart tokens | 320dp, 200%, Light/Dark |
| Disclosure / source | Material ExpansionTile / existing HttpsGuideSourceLauncher | Each item's source and latestValidation | Official HTTPS allowlist; failure retains body |
| Emergency action | EmergencyCallCoordinator / EmergencyDialer / busy state | Existing emergency action contract | Mock only; confirm/cancel and semantics |
| Feedback / retry | Existing guide loading/error widgets; SnackBar for URL copy | Local bundle result or source-launch result | Corrupt section isolation; retry; no partial procedure |

- `/emergency-tips`, `/first-aid`, `/guides/article/:id` remain public, with no login, GPS, health consent, session restoration or Backend prerequisite. Old lowercase IDs resolve to the new canonical IDs. Development review routes display the same canonical draft and do not confer approval.
- `AssetGuideRepository` is the sole loader; manifest, four actions and thirteen first-aid articles are common Flutter assets. Legacy `guides/ko` and `guide_review/ko` are historical, unbundled resources and cannot supply app text.
- All items have SOURCE_GROUNDED_DRAFT and null humanReviewedAtUtc. Web source checks are separate from human review. There is no approved status or runtime publication approval gate for these drafts.
- The user-provided sentences are canonical content. Typed WHEN, ACTION_STEPS, WARNING and EMERGENCY sections preserve their meaning and order; optional sections are not filled with invented clinical advice. `scripts/verify_emergency_guides.py` validates metadata, IDs, counts, dates, section types and nonempty steps and generates the Markdown mirror.
- Source organization, title and publication date are visible beneath the body. Latest validation references show final-modified date. Secondary disclosure shows checked date, license and URL host with an explicit full-URL copy action, avoiding long raw query strings in the layout. A broken source URL disables only its external CTA.
- One GuideSafetyNotice reads its exact common copy from the manifest and appears once per first-aid detail. The existing accessible 119 action remains above the procedures.
- KDCA Type 4 material is used for source comparison only. No official diagrams, PDF screenshots, long source paragraphs or new medical instructions enter the bundle. Existing ERoute-generated non-procedural illustrations remain; topics without artwork use a neutral semantic-theme icon.
- Lists preserve requested category order and show canonical summaries. All details have one scroller, wrap text, number action steps with Korean screen-reader labels, and expose heading semantics. Unknown/empty sections never render partially. Source-link failure leaves local text intact.
- Verification distinguishes Pixel 10 emulator checks from physical hardware and actual TalkBack speech. All QA uses MockEmergencyDialer and no automated real phone handoff.

## Disease foundation v1 (supersedes earlier DRAFT-only personalization contract)

- Recording tags and free text are independent. No approved mapping is required to save a tag; pending coverage is an honest normal state. NONE is explicit absence; UNSET is no record. Confirmed whole reset clears tags/text/map use only on Save. Text-only deletion preserves tags and requires map reconfirmation.
- DiseaseSelectionScreen reuses MemberScaffold/MemberGuard/HealthDraft/memberConfirm/memberFeedback. Tag addition never grants map use. Explicit map-use selection is restricted to existing tags; deleting a tag removes only that tag from map use. Failures preserve drafts; conflicts require fresh data; account/consent loss purges them.
- Only APPROVED+DIRECT canonical/approved-alias matches qualify as related information; only explicit EXACT_CANONICAL scope additionally qualifies for a marker accent. No ranking, fuzzy matching, inferred hierarchy, free-text classification, treatment or acceptance guarantee.
- PersonalizationOverlay is Flutter-only public-coordinate projection with private dot paint; SDK/public marker models remain disease-free. Gold augments red emergency/blue selected markers. Card disclosure provides the same meaning without color dependence. Camera motion hides stale dot positions. List order/count and ordinary search stay unchanged.
- Map personalization defaults OFF and production availability remains false. Local health mutation/session changes/navigation/background clear results immediately; cross-device authority has a maximum 10-second display lease, and late responses cannot restore cleared results. SensitiveDisplayScope shares native privacy leases without fetching full health records.

## Development review preview v0.4 (2026-09-18)

- Production policy and public reference remain APPROVED + DIRECT. The debug dev
  local/test capability independently filters DRAFT + DIRECT candidates from an
  authenticated development-auth artifact route. Review classes reuse the existing
  v0.4 worksheet; no evidence or approval is inferred or generated.
- Canonical owners: selection/consent = existing DiseaseSelectionScreen and member
  repositories; toggle = Material SwitchListTile; private async lifetime =
  MapPersonalizationController; exact comparison = compareDepartmentCandidates;
  overlay = PersonalizationOverlay filled/hollow dot variants; reason = Material modal bottom
  sheet reading live preview state. No new disease-selection or cache model.
- Preview and approved toggle modes are exclusive. Both start OFF. Preview OFF has
  no member reads. Session changes, health mutations, background and navigation
  clear private results. The reason sheet follows the same live state and redacts
  immediately on invalidation. Search order/radius/fit/marker/bed semantics stay
  owned by existing public map components.
- Public hospital source is read-only during QA; isolated development accounts and
  a public-data DB copy exercise actual HTTP repositories. No collection, NMC/HIRA
  call, source timestamp change or synthetic hospital substitution is allowed.
- Final emulator retains a normal development build for user inspection, overriding
  the earlier QA APK restoration convention for this explicitly requested task.

## Approval, relation scope and map presentation (2026-09-18)

- Relation approval, mappingScope and visual emphasis are separate. The matcher remains
  exact canonical/approved-alias comparison; BROAD_PARENT never enables hierarchical matching.
  broadDepartmentNames retains only its uncertainty role. DRAFT has no production path.
- Production dots require APPROVED + DIRECT + mappingScope=EXACT_CANONICAL. BROAD_PARENT
  and missing scope are card/reason-only, including when selected. Legacy scope omission
  never means exact. Production remains OFF with no actual approvals or public mappings.
- Dev preview class policy: EXACT_CANONICAL_REVIEW_REQUIRED=filled, REVIEW_REQUIRED=hollow,
  BROAD_PARENT_REVIEW_REQUIRED=none. reviewClass never populates production mappingScope.
  Global DEV stays visible; marker-level DEV and large rings are removed.
- Pure presentation resolver owns style, PersonalizationOverlay owns geometry/paint,
  public MapOverlayGeometry owns current selected label exclusion rectangles. Pending
  label geometry hides accents. All public coordinates are projected; SDK receives no
  personal flags. Existing usable viewport reserves controls and sheet space.
- No ratio threshold, continuous opacity, ranking or filter. Colliding dots are suppressed
  symmetrically, without selecting a better hospital. Counts and card information survive
  suppression. A selected marker has the same 8dp dot size, never a broad-parent exception.
- Multiple relations produce one dot: preview exact then unclassified style, otherwise
  none. This is decoration aggregation only. Badge counts unique departments; reasons
  group by mapping and retain all observed department names.
- Shared PersonalizationBadge/PersonalizationReasons/Material reason sheet own the same
  labels and fields for list and sheet. Card scope text distinguishes exact candidate,
  broad-parent candidate and unclassified; each reason states approved or under review.
  The live provider owns sheet contents and purges them on every existing privacy boundary.
- Preview summary counts the current search, not painted dots: 검색 병원 / 검수 후보 일치 /
  정보 부족. Pending/error states never reuse old counts. UNKNOWN/NO_MATCH imply no care claim.
- Read-only source DB and stored-only isolated QA adapter are required for regional QA.
  Explicit synthetic selections may appear in QA artifacts, never ordinary telemetry.

- SensitiveDisplayScope resolves its shared lease/privacy owners during initialization,
  even when another sensitive route already holds protection. Releasing the last scope
  never reads WidgetRef after disposal; native protection remains active until that release.


## Attached personalization badges (2026-09-18)

- This visual polish preserves matcher/scope/approval policy and every count/card/reason.
  PersonalizationOverlay owns a conservative visibleHospitalMarkers geometry resolver;
  MapOverlayGeometry exposes only public SDK-installed IDs (null while synchronizing).
  SDK models receive no eligibility, disease, member or matching fields.
- A badge requires a rendered marker with its visible circle inside the usable viewport
  and clear of controls/captions. For equal-z overlapping markers, no topmost ordering is
  assumed; both badges are hidden. Existing selected z remains authoritative. Marker
  rendering, z ordering, hitboxes, search order/filter and fitting are unchanged.
- One 8dp badge overlaps the owner's NE circular rim by 2dp; cross and caption remain
  clear. Collision suppression exempts only the owner's marker, never other markers,
  controls, caption/chip or other badges. Camera motion/pending geometry still hides badges.
- Development reason primary copy: 관계 범위: 직접 대응 후보 / 상위 진료과 후보 / 범위 미확정;
  검수 상태: 검수 중. Debug review-only 개발 정보 is initially collapsed and owns all raw
  mappingId/reviewClass text. Approved/production reasons never expose that disclosure.
  Existing live-state privacy redaction and a single scroll owner remain authoritative.
- 200% Light/Dark QA must reach 닫기 with both disclosure states. These are refinements
  to existing shared components; further personalization decoration is out of scope.

The reason sheet body is the sole flexible scroller; its existing 닫기 TextButton stays
in the SafeArea footer, visible at 200% even when development details are expanded.

## Independent record catalog and local condition commits (2026-09-21)

- DiseaseCatalog owns selectable identities, Korean browsing categories, aliases and quick picks;
  DiseaseReference owns clinical relationships. Catalog inclusion never implies a department match.
  Existing v0.4/v0.5, evidence and reviewClass remain immutable. Preview transports explicit scope
  independently of reviewClass; accent policy remains filled 6 / hollow 30 / none 25.
- ConditionCatalogEditor is the record variant of DiseaseSelectionScreen. MemberScaffold,
  MemberGuard, HealthDraft, Material search/ExpansionTile/CheckboxListTile, memberConfirm and
  memberFeedback retain ownership. Existing theme tokens and Korean typography are unchanged.
- STANDARD identity is diseaseId; CUSTOM preserves user text and never enters hospital matching.
  Server categories are browsing metadata only. Legacy migration compares the entire original
  string against a unique normalized canonical/alias key, without splitting prose or fuzzy matching.
- This explicitly approved exception supersedes the earlier no-permanent-health-copy rule ONLY
  for committed condition entries: local-first device-protected secure storage, exclusive account
  and consent-epoch ownership, backend/environment namespace. Other health fields stay unchanged.
  Unsaved edits retain the existing ten-minute memory-only expiry. CUSTOM text is never analytics.
- App restart/background resume still requires online authority validation before showing saved
  conditions. Within an already-authorized foreground session, connection loss permits local saves.
  Local pending and server-confirmed states are distinct. Logout/account/consent loss clears local
  state and deletes its protected copy; late requests cannot restore it.
- Foreground synchronization reads the current server version before PUT. An uncertain PUT is
  reconciled by reading back; changed versions preserve local edits as a conflict, with explicit
  discard-and-reload before editing against fresh data. No automatic merge or silent overwrite.
- Pending condition changes disable related-department personalization, but ordinary hospital
  search remains available. Explicit map-use consent remains separate. Hospital counts, sorting,
  search radius, public markers and matching rules remain unchanged. Production flag stays OFF.

## Condition card grid refinement (2026-09-21)

Source: user UI refinement brief; data/lifecycle contract remains
`docs/operations/disease-catalog-v1.md` and the existing condition API contract.
This supersedes only the earlier record editor's ExpansionTile presentation.

| Capability | Canonical owner | Refinement / verification |
|---|---|---|
| Form / selection | ConditionCatalogEditor + Material TextField, ChoiceChip, FilterChip, CheckboxListTile | Same draft, NONE confirmation and save behavior; row-wide multi-select |
| Category browsing | ConditionCategoryCard / ConditionCategoryGrid | Server categories/counts; 2 columns, accessible 1-column fallback; one inline detail |
| Search | DiseaseCatalog.search + editor-local query | Alias search after IME composition commits; immediate X reset and input focus; selected category retained |
| Selected records | Existing EmergencyCondition identities + editor compact rows | STANDARD/CUSTOM names preserved, explicit removal; no medical inference |
| Scroll / navigation | MemberScaffold + ListView + existing PopScope | One vertical scroller, natural heights, existing unsaved draft guard |
| Toast / confirmation | memberFeedback / memberConfirm | Existing save destination and confirmations |
| CRUD / sync | HealthDraft, ConditionLocalController, existing repositories | No changes; saved pending/conflict state is visible beside Save |

Browsing state is transient and sensitive search is never persisted or placed in a
URL. Only the active category's disease rows are mounted; a committed nonempty
query temporarily replaces browsing with results. Clearing restores the cards and
previous category. Unknown server categories remain browsable without a Flutter
release. Icon associations never define disease membership or counts.

Verification: `test/disease_selection_widget_test.dart`, existing catalog/local
storage/domain suites, and `integration_test/condition_card_grid_integration_test.dart`
under `apps/mobile`. Android UI QA uses a separate preview flavor and test-injected
server catalog, without writing real member health data.

## Health management / ordinary hospital discovery (2026-09-21)

Source: user flow-finishing brief. This supersedes earlier standalone health-main
map-use entries and manual map display switches; it does not change stored consent.
Canonical owners remain ConditionCatalogEditor, DiseaseSelectionScreen (per-disease
map-use variant), HealthDraft, ConditionLocalController, MemberGuard, existing
repositories, MapPersonalizationController, PersonalizationBadge/ReasonSheet,
EmergencyMapPage and its existing HospitalSheet/list tiles.

- NONE hides search, quick picks, categories, selected rows, CUSTOM and hospital-use
  settings. Existing clear confirmation and explicit save remain. UNSET is distinct.
- Health main has only health management cards; the map-use entry and hospital CTA
  move out. Home 가까운 병원 찾기 and 지도 보기 retain the same existing map route.
- Hospital-use settings live below the condition record. Unsaved records are explicitly
  saved before opening the existing per-disease consent screen; pending/conflict prevents
  entry. Fresh authorized server version is required. Returning refreshes the record
  editor's base. These remain two separate commits, not a global consent toggle.
- Existing CONFIRMED consent is restored only when reference, purpose and purposeVersion
  match. Changing selected diseases resets acknowledgement as before. NONE clears map use
  on save through the existing domain. Epoch/session/authority boundaries remain intact.
- Visible foreground hospital route automatically activates the existing controller.
  In debug dev local/test, use only the existing authenticated preview loader; otherwise
  the approved path's availability gate applies. Production stays OFF.
- The authenticated map-selection endpoint confirms health permission/epoch. No reference
  or dev-preview fetch is made for unconfirmed selection. Pending/conflict blocks results;
  public search proceeds unchanged. Responses are still version/session checked twice,
  with the existing ten-second expiry. Background/navigation/privacy/session changes clear
  results; visible route re-entry revalidates before displaying anything.
- Category selection or ordinary search never grants consent. CUSTOM has no disease ID
  in the selection and is never mapped. No supported mapping means no badge. No-login,
  no-consent and failed authorization add no per-hospital empty/login UI.
- Existing result count/order/radius, hospital matcher, red/blue marker semantics,
  mappingScope/reviewClass and filled 6 / hollow 30 / none 25 baseline are unchanged.
  Personalization never filters, sorts, ranks or recommends hospitals.
- Global dev notice and Korean reason labels explain review state. Raw technical enums
  are absent from ordinary reason views. The existing live provider still redacts an
  open reason sheet on invalidation. The fixed close action stays outside its scroller.

Verification: `hospital_personalization_flow_test.dart`,
`condition_catalog_widgets_test.dart`, existing domain/selection suites and
`health_hospital_flow_integration_test.dart`. The optional EmergencyMapBuilder
provider is a host adapter for the same route; default remains the native map.


## Hospital external navigation (2026-09-21)

Source: user request, “ERoute — 병원 상세 길찾기 제거 및 네이버 지도 외부 내비게이션 연결”;
[NAVER official scheme guide](https://guide.ncloud-docs.com/docs/en/maps-url-scheme).

| Capability | Canonical owner | Contract | Verification |
|---|---|---|---|
| External hospital navigation | HospitalNavigationLauncher / SystemHospitalNavigationLauncher | Destination-only nmap navigation; runtime PackageInfo identity | hospital_navigation_test.dart + Android integration test |
| Install prompt / feedback | memberConfirm / memberFeedback | Existing AlertDialog and SnackBar; cancel stays on detail | widget tests + Android integration test |
| CTA layout | HospitalDetailPage + existing Material theme | Outlined buttons, row-to-column at narrow/large text | Light/Dark, 320dp, 200% captures |

- `네이버 지도에서 열기` checks finite destination coordinates in NAVER's documented
  range (latitude 31.43–44.35, longitude 122.37–132.00), then checks scheme availability.
  Missing coordinates never prevent contact/realtime/basic detail rendering. A loaded
  detail with no coordinates must not silently use older search coordinates.
- Installed: open `nmap://navigation` directly. Uninstalled: explain the requirement
  and offer 취소 / 설치하기. Store opens only after 설치하기; failed handoffs use feedback.
- PackageInfo reads the actual installed Android applicationId or iOS bundle ID,
  including flavor suffixes. No new identity string/config/package owner is introduced.
- URL fields are only dlat, dlng, dname and appname. No GPS access, user/health data,
  production URL logs, Directions APIs, routes, polylines, or new SDK keys.
- Busy state blocks duplicate requests; disposed detail never opens a late install
  prompt or reports feedback. Native phone calls remain excluded from automated QA.

## Hospital C context / detail extension (2026-09-22)

Source: explicit user C-plan and hospital-detail brief. Supersedes only earlier
no-ring and detail-without-personalization presentation rules.

| Capability | Canonical owner | Contract / verification |
|---|---|---|
| Applied context | MapPersonalizationController + PersonalizationContextSheet | Reference candidates exposed only after existing double authority check; live expiry/redaction; no filter and no consent X |
| Related hospital ring | personalizationRingEligible → PersonalizationOverlay | At least one EXACT_CANONICAL MATCH under existing controller authority; BROAD_PARENT/null/unknown never ring; independent review-class baseline and selected blue fill; collision/viewport suppression unchanged |
| Card / reason | PersonalizationBadge / PersonalizationReasonSheet | Whole tag tappable, DRAFT visible, one scroller and fixed close; shared by detail |
| Hospital detail | HospitalDetailPage + existing controller | Revalidate via same controller on visible entry/resume; clear on navigation/background/session/consent changes; no detail mapping algorithm |
| Settings entry | MemberEmergencyScreen hospitalUseSettings variant → DiseaseSelectionScreen | Fresh MemberController/MemberGuard authority and same per-disease commit; context sheet cannot mutate consent |
| Clinical layout | HospitalClinicalInformation | Wrap up to 51+ long departments, no fixed height; today uses localPresentationNow, injected in tests; holiday caveat; weekly expansion |
| Freshness | RealtimeSummary detail variant / provider_time_formatter | Recent check means ERoute collection; provider raw/wall-time/zone retained in disclosure; 0 ≠ missing ≠ closed |
| Card interaction surface | ERouteCard Material/Ink | Passive cards support embedded keyboard/touch disclosure without hidden ink |

Search count/order/radii, native position/selection, 119/zoom/sheet, source acquisition,
secure condition storage, consent and navigation launcher remain their existing owners.
Production stays OFF; public mappings/APPROVED remain zero. No disease/ranking/filter data
enters public search or native SDK transport. Detail presentation may consume private
controller results; its domain and data transport remain independent.

The EXACT_CANONICAL-only ring refinement (2026-09-22) preserves BROAD_PARENT context,
card, detail and reason information. Mixed exact+broad matches receive a ring while
both reasons remain available. `reviewClass` cannot substitute for `mappingScope`.

Verification: hospital_c_plan_test.dart, existing controller/privacy/matcher suites,
hospital_personalization_flow_test.dart, detail/navigation tests, and native Pixel 10
QA in docs/qa/hospital-personalization-detail-2026-09-22.

Display authority keeps its existing maximum ten-second lease. Poll renewal starts
every five seconds so successful reads finish before expiry; stalled/failed refreshes
still redact at the original expiry boundary. No stale-authority grace period is added.

## Category recognition across personalization (2026-09-22)

| Capability | Canonical owner | Contract / verification |
|---|---|---|
| Category icon/tone | DiseaseCategoryVisualRegistry | Original 14 associations promoted from condition_catalog_widgets; original grid pixel comparison in both themes/320dp/200% |
| STANDARD visual lookup | DiseaseCatalog.byId → categoryId → registry | No diseaseId/name-specific icon table, no clinical reference edits; inactive metadata can resolve without changing eligibility |
| Shared tag decoration | PersonalizationCategoryButton | Existing context/reason actions, dimensions and labels; same-category aggregation, neutral multi-category/unknown fallbacks |
| Metadata loading | personalizationVisualCatalogProvider → existing DiseaseCatalogRepository | One public metadata future shared by visible buttons; no private IDs in requests/provider keys, no new persistence; loading/error changes only decoration |

The existing controller remains the exclusive authority for whether context/results
exist. CUSTOM/unmapped/invalidated results cannot gain personalization through the
visual lookup. Async public metadata never restores a removed private button.
Consent, lifecycle/redaction, matcher, v0.5, marker ring and production OFF are unchanged.
Verification: disease_category_visual_test.dart, category_grid_visual_test.dart and
existing privacy/matcher/flow suites; docs/qa/personalization-category-visual-2026-09-22.


## Native hospital marker clustering (2026-09-22)

| Capability | Canonical owner | Contract / verification |
|---|---|---|
| Group membership | HospitalMarkerClusterer | 60 logical-pixel seed radius, deterministic HPID order, nine-cell spatial hash; no clinical input, search filtering or ranking |
| Native marker collection | NaverEmergencyMapView | Reconcile native NMarker individual/cluster sets at camera idle or result/selection change; preserve stable objects, invalidate stale projection; all returned HPIDs counted once |
| Selected hospital | Existing selectedHpid + native marker owner | Selected HPID excluded from clustering; retains blue fill, 48dp, z=10 and existing label/card semantics |
| Cluster art / interaction | HospitalClusterPainter / HospitalClusterTarget + MapMarkerIcons.cluster | Neutral surface/navy number only, bounded count-art cache, 48dp minimum pill, same fixed-size count at large text; semantic button: 병원 N개 묶음 / 확대해서 병원 보기; pressed/focus ink |
| Cluster tap | NaverEmergencyMapView._expandCluster | Fit member bounds with existing viewport padding; coincident coordinates use zoom-in; user camera movement only, never select/open a card or execute search |
| Individual ring readiness | MapOverlayGeometry.renderedHospitalIds | Only actual individual native IDs; cluster footprints enter overlayExclusionRects; unchanged personalizationRingEligible remains the sole EXACT/BROAD policy owner |

The installed flutter_naver_map 1.4.4 native clustering primitive was evaluated.
Its Dart API exposes cluster creation/update but no leaf-visibility/removal/completed
membership snapshot. App-side grouping preserves the existing separately projected
ring's exact installation gate without a plugin fork or duplicate inferred native
membership. All visual markers still use the existing native NMarker adapter.

Every result HPID belongs to exactly one individual or cluster, including offscreen
coordinates as in the prior native layer. The **global** cluster-size sum plus
individual count equals the search result count; viewport clipping can reduce the
visible sum. Cluster targets are only exposed fully inside the usable viewport,
below existing Flutter controls. Touch targets yield to selected labels/individual
footprints when they overlap; explicit accessibility tap actions remain available.
No selected-area cluster state exists: selection belongs to the individual marker.

Camera motion retains native overlays and hides stale Flutter cluster targets/rings;
idle recomputes. Layout changes only reposition accessible targets/label geometry.
Search revision changes reconcile away previous groups; pan/cluster tap never query
Backend until the existing search-here action is invoked. Bottom sheet, 10/20/50km,
119/current location/zoom controls and consent/context/card/detail/reason owners stay
unchanged. The EXACT-only helper, immutable reference and Production OFF are baseline.

Verification: hospital_marker_clusterer_test.dart, marker_clustering_integration_test.dart,
existing EXACT ring/flow/search tests, and docs/qa/map-marker-clustering-2026-09-22.

## User-led 119 SMS preparation (2026-09-22)

Authority: the current task brief, existing MemberAccess/RemoteMemberRepository and
HealthService wire contracts, and official platform/service sources recorded in
`docs/operations/emergency-sms-v1.md`.

| Capability | Canonical owner | Observable contract |
|---|---|---|
| Call confirmation | EmergencyCallCoordinator | High-emphasis 119 call is never consent, health, GPS or SMS gated |
| SMS eligibility | emergencySmsAccessProvider | Authenticated same session + GRANTED; access-only read before preview |
| Private preview | MemberSecurityScope / MemberController | Same native privacy lease, lifecycle cover, reload and consent checks as member screens |
| Field selection / body | emergencySmsFields / formatEmergencySms | Explicit preview and selectable saved fields; unset/empty omitted; no inferred departments or internal metadata |
| Location | existing location service / fresh map fix | Permission already granted only; no permission prompt; three-second optional read, never blocks composing |
| Handoff | EmergencySmsLauncher | Android SENDTO / iOS MessageUI, recipient 119; OS user sends; no background send or backend payload |
| Failure | preview inline live region | Generic message, retry, primary call remains reachable; no sensitive error/log content |
| Health edits | MemberFieldEditor / MemberBusyButton / memberFeedback | Existing UNSET/NONE/RECORDED wire; dirty-back confirmation, counter, server-confirmed feedback |

No body logging, analytics, crash attachment, clipboard, shared_preferences,
backend delivery, automatic registration, or health/telephone incident merging.
Composer body exists only as a local formatting/handoff value. Preview drops its
private widgets on background/access loss and disposes after successful handoff.

### Installed-runtime verification and SMS capability refinement (2026-09-22)

Authority: the user's emergency-personalization/iOS QA brief. This supersedes historical
global DEV/per-card review labels and the blanket development SMS-launch restriction
only for explicitly requested native composer QA. Actual calls and SMS transmission
remain prohibited in development/QA.

- The general installed dev app must be updated with the canonical launcher and
  `adb install -r`; preview fixture success never proves actual-account eligibility.
- Ordinary map, radius, list header and hospital card have no persistent DEV/review
  lifecycle text. Context/reason details retain Korean review disclosure at the end;
  no raw enums, approval promotion, or production enablement.
- Confirmation actions are vertically stacked: primary/danger call, eligible SMS,
  cancel. The unchanged access provider checks real same-user/session GRANTED access.
- Native `canCompose` checks SENDTO resolution / MessageUI canSendText. Only preview
  handoff availability depends on it; health access and phone access are independent.
  Unavailable preview explains the limitation and keeps close/call reachable.
- Actual health artifacts contain only sanitized states/counts/booleans. Screenshots
  that display health values use explicit test-only synthetic repositories. Native
  privacy protections are not disabled for actual-account screenshot collection.
