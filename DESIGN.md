---
version: alpha
colors:
  background-light: "#FAFBFC"
  surface-light: "#FFFFFF"
  background-dark: "#101B2D"
  surface-dark: "#1A2940"
  primary: "#244E86"
  primary-dark: "#9BC2FF"
  emergency-light: "#C93645"
  emergency-dark: "#FF7A85"
typography:
  korean:
    fontFamily: "NotoSansKR"
rounded:
  control: "12px"
  card: "16px"
  sheet: "24px"
spacing:
  xxs: "4px"
  xs: "8px"
  sm: "12px"
  md: "16px"
  lg: "24px"
  xl: "32px"
components:
  app-shell:
    backgroundColor: "{colors.background-light}"
    textColor: "{colors.primary}"
  dark-app-shell:
    backgroundColor: "{colors.background-dark}"
    textColor: "{colors.primary-dark}"
  emergency-button:
    backgroundColor: "{colors.emergency-light}"
    textColor: "#FFFFFF"
    rounded: "999px"
    size: "208px"
  card:
    backgroundColor: "{colors.surface-light}"
    rounded: "{rounded.card}"
  dark-card:
    backgroundColor: "{colors.surface-dark}"
    rounded: "{rounded.card}"
  dark-emergency-button:
    backgroundColor: "{colors.emergency-dark}"
    rounded: "999px"
---

# ERoute Design

## Approved app icon (2026-09-15)

The user approved the E variant from `docs/ui/icon-review-v1`: the winding ivory
road, layered hills, luminous horizon and central navy E stay consistent between
Light and Dark. The approved high-resolution PNGs and hashes in `generation.json`
are the artwork source; they are raster originals, not editable vectors.
`scripts/generate_app_icons.py` owns deterministic platform exports. Android uses
the Light landscape with a separate E foreground and a transparent monochrome
E/road silhouette; it does not switch two landscapes on device theme changes.
Preview adds the same geometric P badge on the right hillside, clear of the E and
road, in actual color and monochrome resources. iOS uses the existing AppIcon
catalog with any/dark/tinted appearances. App ThemeMode and launcher appearance
remain independent. No public/member/map UI token or layout changes are included.

## Overview

ERoute is a Korean emergency-care product used under stress. The interface should feel like a calm, legible medical instrument. Its memorable element is the large circular 119 action on the landing screen. Every other surface stays quiet so that action remains unmistakable.

The primary reference is `docs/ui/references/eroute-main-flow-v1.png`. It informs hierarchy and flow, while all hospital content comes from the actual Backend. Reference-image places, hospitals, numbers, photos, and medical claims are never product data.

The Dart tokens in `apps/mobile/lib/core/theme/eroute_tokens.dart` own runtime values. This document mirrors and explains them; `colors.primary` maps to `ERouteColors.primaryLight`, while the remaining color names map directly by role. `ThemeData`, shared components, and the map adapter consume the Dart owners.

## Colors

Deep navy and blue carry navigation, selection, and trust. Coral is reserved for 119 and hospital identification. Warm white and muted blue-gray make data readable without suggesting a medical status. Color is always paired with a label or icon.

## Typography

Noto Sans KR is bundled and used for every role. Weight and scale create hierarchy: 28px landing hero, 22px page titles, 18px hospital names, 16px body, and 13px supporting information. Numeric bed values use tabular figures where supported.

## Layout

The base rhythm is 4, 8, 12, 16, 24, and 32dp. Phone content uses 16dp horizontal margins. Landing and detail content center at a maximum width of 720dp. The map owns the full viewport and reports overlay and Sheet occlusion to its camera adapter.

## Elevation & Depth

Most content is flat. Subtle shadow is reserved for the map top bar, draggable Sheet, Drawer, the 119 action halo, and the member reference cards described below.

## Shapes

Controls use 12dp corners, cards 16dp, and the map Sheet 24dp top corners. The emergency action is circular. Pill shapes are reserved for compact selectors and status badges.

## Components

Shared ERoute components own buttons, cards, top bars, feedback, section titles, and status badges. Every interactive target is at least 48dp. Loading, error, unavailable, stale, and selected states keep stable geometry.

Detail uses `ERouteSkeleton` only for pending fields without prior values: static muted bars following the existing field geometry, without shimmer. Completed missing fields and request errors use distinct text. Map names appear only for the selected hospital; an occluded native caption becomes one small `SelectedHospitalLabel` within the usable viewport, with a single-line ellipsis and the full accessible name. Both consume the existing semantic theme and spacing; this is a state/legibility refinement, not a palette or typography change.

The Landing decoration is a transparent, pointer-inert illustration layer behind the real layout. Light and dark themes own separate assets; neither asset contains copy, controls, logos, a real hospital, or identifiable geography. The layer disappears on landscape, short/narrow screens, and large text so it can never displace the 119 action or quick actions.

## Do's and Don'ts

- Keep 119 available without login, GPS, map, or Backend state.
- Preserve raw and interpreted medical data separately and label stale or missing values.
- Use actual HPID-backed results; never invent a hospital, user, capability, address, phone, or operating hour.
- Do not show occupancy percentages, acceptance claims, or severe-disease capability from bed counts.
- Do not use coral as general decoration or success color.
- Do not capture the native map to simulate Drawer blur.

## Clinical information extension

The existing Detail card and Noto Sans KR roles own the clinical tab. Departments use simple text rows; hospital hours use two flexible columns in Monday-to-holiday order. Large text wraps without fixed row heights. Explicit missing/uncertain/previous-data labels use existing neutral text rather than availability colors. The medical-hours explanation remains visible below the data. Detail's toolbar uses an opaque theme surface to establish the scroll boundary; the palette and type scale are unchanged.

## Member authentication and sensitive forms

Auth and health forms reuse ERouteScaffold, Material form controls and shared theme tokens. Keep the existing quiet navy/Noto Sans KR language and 48dp targets. A privacy cover replaces only the sensitive body; public navigation and emergency entry remain reachable. Consent and destructive confirmation use app-owned dialogs, persistent inline errors and server-confirmed feedback. Manual health fields distinguish not entered from explicitly none. No clinical status colors are introduced. The member-specific category accents below identify field types only.

## Member UI preview (2026-09)

The member reference is `docs/ui/references/eroute-member-ui-v1.png`: upper A+C for saved-health cards, upper D for focused editing, lower B+C for the account summary and grouped menus. The original map reference remains authoritative only for the public map flow. These are real Flutter widgets, never a full-screen raster.

Member UI keeps the existing navy/blue semantic theme, Noto Sans KR, 16dp card radius and 16dp phone gutters. The account summary uses a restrained primary-to-secondary gradient, with neutral greeting and phone shown once. Two functional shortcut cards lead to emergency information and medications; compact grouped rows hold consent and security actions. Health cards pair an icon, field label, textual entry state and saved summary. Source text is preserved and never split to infer medical counts. The optional emergency note has no explicit-none state.

`features/member_ui/member_widgets.dart` owns the new member page shell, feedback, panels and busy button, consuming existing ERoute themes/tokens. Material form fields, AlertDialog and SnackBar retain their interaction roles. The new shell uses an opaque theme surface and explicit status-bar brightness. Authored Korean explanatory copy wraps at spaces; stored health text is unchanged. Timestamps use device-local minute precision.

The shared member widgets are currently mounted only in the isolated preview. The preview toolbar, scenario controls and synthetic results are in `lib/preview`; they are not product components. Existing general dev/production routes remain in place until the same new widgets are connected to actual repositories in phase two.

## Member reference refinement and product search (2026-09-15)

The explicit reference-fidelity request adds member-only pastel categories: coral allergy, violet condition, warm orange medication, teal note. `MemberTone` / `memberToneColors` in `features/member_ui/member_widgets.dart` own paired light/dark background and foreground values. These are category decoration with text labels, never clinical severity, verification or success signals. Public map/emergency tokens remain unchanged.

`memberCardShape` owns a weak outline, 16dp radius; member panels and shortcuts use low elevation with a faint shadow. The main has one bold navigation title, compact supporting copy and saved timestamp above the four information cards. A single small provenance line replaces repeated notice boxes. The editor uses a focused pastel context strip, a question, wrapping 48dp ChoiceChip targets and a navigation save action. No new allergy types or medical fields are copied from the reference.

Product search uses the same shell/cards, an explicit search submit action, differentiated product name/strength/form, and a calm image-absent placeholder. Product confirmation separates catalog information from the optional personal note editor. Product source stays visible. The preview marker stays visible while its tools collapse; tools never occupy ordinary product content. Default-size representative reference comparisons were captured before extending the product flow.

## Approved member UI: real integration

The approved member colors, type, cards and shared widgets are unchanged. General dev/production now route through the same member_ui widgets with RemoteMemberRepository. Signup/login/reauth use password authentication. Added only required age self-declaration, password policy copy and server-backed states. Preview remains an isolated repository/product/privacy override. General medication search capability is unavailable, with a working manual input action. Member route privacy leases share the native owner; the last member route releases screen protection. No icon or MFDS integration in this phase.

## Freshness and small-screen polish (2026-09-15)

The approved structure and tokens remain unchanged. Landing quick-action labels keep Korean words together and switch to the existing single-column mode at narrow/intermediate large text sizes. ERouteTheme owns explicit AppBar status-icon brightness; ERouteApp supplies the same theme fallback for screens without an AppBar. MemberScaffold retains its scoped overlay style. RealtimeSummary remains the shared list/detail owner and distinguishes collection age from an unverified provider clock. Detail contact numbers appear in Basic information; the action row retains its explanatory line.

## Emergency guide content v1 (2026-09-22)

The two existing guide lists and detail reader retain ERouteScaffold, ERouteCard, bundled Noto Sans KR, navy semantic colors, soft pastel artwork, 16dp gutters and a 720dp reading width. Runtime theme tokens remain unchanged. The detail hierarchy is title/category, summary, the existing 119 action, one shared safety notice for first aid, structured sections, and visible official sources. The brief's supplied procedure text owns all clinical wording; empty sections are omitted instead of invented.

Cards use canonical summaries and existing ERoute-generated topic illustrations tracked in `docs/ui/guide-thumbnails-v1/manifest.json`. No official images are bundled. A neutral article icon reserves the same geometry for topics with no existing illustration. Images are decorative. Below 300dp card content width or at 150% text scaling, the 112dp image moves above text (maximum 240dp); neither titles nor body text are shrunk or ellipsized.

Numbered steps communicate action order, with one Korean semantic label per step. Warnings remain neutral, readable text; the emergency tone stays reserved for 119. Source organization/title/date is visible, and Material ExpansionTile contains secondary metadata. Long URLs are represented by their host and an explicit full-URL copy action. Source failures keep body content on screen. The 17 items remain source-grounded drafts, without medical approval labels.

## Disease selection preparation (2026-09-17)

Explicit map-use disease selection reuses MemberScaffold, MemberGuard, MemberNotice, memberConfirm/memberFeedback, Material TextField and CheckboxListTile, and the existing theme. It preserves raw health text and shows a persistent map-publication hold. No new palette or yellow hospital style is released. The single-column form wraps at large text sizes and keeps natural ListView scrolling. Reference, purpose and conflict states use neutral explanations, never clinical availability colors. The dev-only synthetic matcher uses the existing public scaffold, carries a development label, and cannot access saved member selections.

## Extensible condition recording and private map layer (2026-09-18)

The condition editor keeps MemberScaffold, condition tone, shared confirmations/feedback and draft guards. InputChip tags and free text have separate roles; no mapping is required for a tag. DiseaseSelectionScreen owns both recording and the separately confirmed map-use variant. Gold is a restrained supplementary accent owned by ERouteColors.personalizationGoldLight (#946600) / personalizationGoldDark (#ffd36e), never a replacement emergency or selection color. PersonalizationOverlay owns Flutter paint and PersonalizationBadge owns the expandable reason. Red native emergency markers and blue selection remain unchanged. Dots are decorative; cards carry accessible explanatory text. Production exposure stays OFF; native positive QA uses synthetic test fixtures only.

## Development disease review preview (2026-09-18)

Dev debug local/test builds add an explicit, initially OFF `검수 중 매핑 미리보기 · DEV`
switch on the existing map. Existing navy, Noto Sans KR, card, sheet and gold tokens
remain authoritative. An 8dp badge attached to the marker rim is the preview signature: filled for exact review
candidates, hollow for unclassified candidates, absent for broad-parent candidates.
DEV appears only in the global preview state. Dots never replace red/blue semantics. Live result counts explain the current search
without sorting or filtering. The shared card badge opens the existing Material
bottom-sheet pattern; each disease keeps its candidate/observed-department pair and
review class. Korean uncertainty copy is from the task brief, not a clinical claim.

## Disease visual policy (2026-09-18)

Emergency map first, personalization second. Preserve hospital position/red emergency
markers first, blue selection and its caption second, and personal information third.
PersonalizationOverlay paints one 8dp dot with a 1.5dp inside border, overlapping the
visible circular rim by 2dp at its upper-right diagonal. Transparent icon padding is excluded. Selection does not enlarge the dot. Existing
personalizationGoldLight/Dark and theme surface own filled/hollow colors; no new
palette, icon family, animation, score or design system is introduced. HospitalMarkerGeometry
owns the unchanged 38/48dp native marker dimensions.

The production presentation gate is APPROVED + DIRECT + explicit EXACT_CANONICAL.
BROAD_PARENT and unclassified approved mappings retain card information without a dot.
Development-only REVIEW_REQUIRED uses hollow; exact review candidates use filled;
broad-parent uses no dot. Fill describes preview classification, never approval.
The mutually exclusive mode's global DEV label and per-card/reason state explain it.

Actual geometry, not match percentages, controls clutter: hide dots overlapping any
hospital marker, selected caption/chip, existing control insets, another dot or the
usable viewport boundary. Pending geometry and camera motion hide dots. Never move
or replace an emergency marker to accommodate an accent. Cards and the summary keep
all matches even when no dot can be painted. Scope and review state use Korean text;
no meaning depends on color, dot fill or an overlay accessibility focus target alone.

Large text keeps the full 119 label and drops only its decorative phone icon above
150% scaling. The SDK 1.4.4 fixed-height scale bar is omitted above that scale to avoid
overflow; radius and hospital distances remain accessible, fully scaled app text.


## Marker association and review wording polish (2026-09-18)

The badge is attached to a hospital, never a separate map location. HospitalMarkerGeometry
shares the vector icon's 21/48 outer radius with the Flutter geometry resolver. The
badge center is radius+2dp from the marker center at NE, leaving a 2dp rim overlap
with its 4dp radius, clear of the medical cross. Normal and selected markers use the
same relative rule. Keep the 8dp size, gold tokens and filled/hollow meanings.

Only installed, fully in-viewport and unoccluded marker geometry admits a badge.
Equal-z overlapping hospital circles are ambiguous, so their badges are suppressed;
the selected marker's existing higher z is known. Other marker, control, caption and
badge collisions still suppress decoration. No hospital marker or match is suppressed.

Review reasons lead with 직접 대응 후보 / 상위 진료과 후보 / 범위 미확정 and 검수 상태: 검수 중.
Debug preview alone offers a collapsed Material ExpansionTile named 개발 정보 for raw
mappingId/reviewClass. The sheet keeps one natural scroller and a reachable 닫기 button
at 200% text. No further marker decoration, palette, symbol, halo or animation is added.

The reason sheet body is the sole flexible scroller; its existing 닫기 TextButton stays
in the SafeArea footer, visible at 200% even when development details are expanded.

## Condition catalog card browsing (2026-09-21)

Only candidate 2 in `docs/ui/references/disease-category-card-grid-v1.png` informs
this refinement. The existing MemberScaffold, Noto Sans KR, navy text, white/themed
surface, thin outlines and member pastel icon circles remain canonical. No fonts,
colors, packages, catalog records or clinical illustrations are added.

`condition_catalog_widgets.dart` owns reusable ConditionCategoryCard and
ConditionCategoryGrid. Category IDs select decorative Material icons and existing
MemberTone accents only; unknown IDs receive a neutral medical icon. Server names,
order and active-disease counts remain authoritative. Cards have natural heights,
two equal-width columns and 12dp gaps. Below 300dp content width or at 150% text
scaling, one column preserves long Korean labels; no text is shrunk or clipped.

A card opens one detail panel directly below its row. The shared member card shape,
softBlue selection background, navy outline and check icon keep selection distinct
from decorative category colors. Search has an outlined, filled field and explicit
clear; results use the same whole-row CheckboxListTile as category details. Selected
records use compact wrapping rows, named remove controls and a secondary 직접 입력
label. Storage and synchronization semantics stay in their existing owners.

## Health management and hospital discovery finishing (2026-09-21)

The card-grid reference remains candidate 2. Category cards retain natural height
and the 2-column/1-column responsive rules. Vertical padding drops from 16 to 8dp,
and icon-to-name spacing from 12 to 4dp (~126 to ~102dp for a one-line label at
100%). The chevron sits beside the wrapping name and points up while open; the
whole card retains selected/expanded semantics and the blue outline/background.

Explicit NONE shows only absence copy and save/reset controls. UNSET remains
unselected, never inferred as NONE. MemberEmergencyScreen returns to its four
health summary cards. ConditionCatalogEditor owns the hospital-use settings entry
below recording/save, with the existing per-disease consent screen as its detail.

Hospital discovery keeps the existing home actions and map route. Existing
PersonalizationBadge uses a softBlue health-outline action, not a star, while the
existing gold marker geometry and scope/classification presentation stay unchanged.
The live reason sheet shows Korean scope/review labels without raw diagnostic codes.
No new palette, typography, mapping, marker meaning or medical claims are introduced.


## Hospital external navigation (2026-09-21)

Hospital detail keeps its outlined Material CTAs and existing navy/Noto Sans KR
style. `네이버 지도에서 열기` uses the existing directions icon. The CTA row gives
the longer navigation action two shares of width, then uses the landing flow's
full-width column treatment below 360dp content width or 125% text scaling.
Text never shrinks. Invalid/missing coordinates disable only this action with a
muted explanation. Existing memberConfirm/AlertDialog and memberFeedback/SnackBar
own the install prompt and launch failures; there is no pre-handoff confirmation.

## Hospital personalization C and clinical detail (2026-09-22)

Source: right-hand C only in `docs/ui/references/hospital-personalization-c-v1.png`.
This explicit user refinement supersedes the earlier dot-only/no-halo presentation
rule, not its review classification or clinical matching policy. Keep Noto Sans KR,
navy #244E86 / dark #9BC2FF, white #FFFFFF / dark surface #1A2940 and emergency
#C93645 / #FF7A85 under the existing theme owner. No new palette/font or medical icon.
The signature is a thin blue outline 5dp outside the native hospital circle, plus
an applied-context chip below the radius controls and a compact card tag next to
the hospital identity. Emergency fill and selected marker size/z/caption stay intact.
No red/pink personalization halo, filter, ranking, or consent-removal X is adopted.
The unchanged review baseline remains filled 6 / hollow 30 / none 25; C rings are an
independent presentation requiring at least one matched EXACT_CANONICAL relation.
DRAFT exact relations require the existing development capability. BROAD_PARENT and
null/unknown scope never receive a ring, regardless of reviewClass, but retain the
context chip, card tag, detail and reason. `personalizationRingEligible` owns this
policy; selected blue fill remains independent. Crowded/occluded rings are suppressed.

Detail reuses RealtimeSummary's explicit detail variant, PersonalizationBadge/reason
sheet, HospitalClinicalInformation and Material ExpansionTile. Departments use natural
height wrapping tags, with related meaning in a separate labeled section. Today's
hours use the device-local presentation clock and explicitly say weekday-based;
weekly/holiday rows remain expandable and missing never means closed. Source details
preserve provider wall time without assigning a timezone. `HVS01` stays a reference
value (`일반 병상 기준`), never relabeled ordinary inpatient beds. ERouteCard now owns
Material/Ink for passive cards too, so embedded disclosures have visible ink/focus.

## Shared DiseaseCatalog category visuals (2026-09-22)

The existing fourteen condition-card icon/tone associations now belong to
`DiseaseCategoryVisualRegistry` in `disease_category_visual.dart`. Category cards,
map context and hospital card/detail tags resolve through this one owner. The
memberToneColors and ERoute softBlue/primary theme tokens retain their values;
category cards retain their exact geometry and known-category appearance.
PersonalizationCategoryButton uses the same category colors in its existing compact
18dp icon / 48dp target. Category recognition is separate from clinical certainty.
Multiple diseases with one category share that visual. Multiple categories use the
existing generic personalization icon with neutral surfaceContainerHighest /
onSurfaceVariant; missing catalog/identity or an unknown category uses the neutral
medical icon. Never infer category from disease IDs/names or department mappings.
The C-plan blue marker ring, emergency/selected marker semantics and all review
copy are unchanged; category icons never enter the native marker.


## Hospital marker clustering (2026-09-22)

Dense public map results use neutral number pills, never the hospital cross or red/
selected-blue fill. HospitalClusterPainter consumes the existing surfaceLight/Dark
and primaryLight/Dark tokens: #FFFFFF/#1A2940 surfaces, #244E86/#9BC2FF counts and
1.5dp border. NotoSansKR bold 17dp tabular numerals occupy a 48dp high pill (minimum
48dp width; grows for three or more digits). Count art is independent of text scale;
the accessible label always states the full hospital count. HospitalClusterTarget
owns the transparent native-icon companion's focus and pressed Material ink.

HospitalClusterGeometry owns the 60dp grouping distance, chosen against existing
38dp hospital / 48dp selected geometry and a 48dp cluster target. No zoom-number or
geographic-km threshold controls membership. No selected-area cluster variant: the
selected hospital remains a separate native symbol. Dark art changes with the theme.
Existing controls, typography, card geometry, review copy and EXACT-only ring are
unchanged. Cluster symbols never receive personalization rings. This explicitly
adds clustering to the established map without restyling individual hospital markers.

## Emergency finish and user-led SMS (2026-09-22)

The existing navy, Noto Sans KR, member category tones and 16dp gutters remain the
runtime owners. Guide step numbers use small primary-container badges and 1.65
line height; the shared safety notice uses secondary body text, without a card.
Source publisher/title/date stay compact; checked date, license and KDCA validation
live inside disclosure. Canonical guide assets and clinical wording are unchanged.

Health summaries share 미입력 / 없음 / 등록됨 badges. A pending condition sync remains
separate supporting text. Allergy choices reuse the existing editor. Medication
unset/none have distinct copy; only unset offers the explicit-none action. The
free-text note keeps the shared dirty-navigation, counter and save-feedback owners;
empty and never-entered notes are indistinguishable in the existing wire model.

Ordinary map surfaces have no persistent DEV banner. Compact hospital buttons omit
review copy; context/reason sheets end with 개발 미리보기 · 검수 중 and explain
that the unpublished disease-department relation is under review. No production mapping or presentation flag is enabled.

EmergencyCallCoordinator owns call confirmation in every entry point. Its filled
coral call action stays immediately available while an access-only SMS eligibility
check runs. SMS preview reuses MemberSecurityScope, app-owned Material sheet,
checkboxes, disclosure and an outlined handoff action. Long values have five-line
summaries and a full-body disclosure; nothing is silently truncated in the composer.
Telephone and SMS are independent. OS composition owns final transmission.

The 119 dialog stacks the filled call action first, optional SMS preparation second,
and cancel last, including at 320dp/200%. Native SMS capability is checked in the
preview without affecting call access. Unavailable devices retain the preview and
a readable explanation with a disabled composer action. Android package visibility
permits only a SENDTO/smsto handler query; no SMS permission is added.
