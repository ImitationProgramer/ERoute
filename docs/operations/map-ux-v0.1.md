# Emergency Map UX v0.1

## Search and camera

SearchPresentationSnapshot binds the completed request center/source to the effective radius, hospitals and revision. Manual camera bounds contain only that center, its complete spherical radius bounding box and all returned hospitals. A remote user GPS marker is never an input to fitting. GPS searches naturally include the user because it is the search center.

The adapter alone imports Naver types. Camera events distinguish fitting, current-location movement, layout, user gesture and user zoom. The manual-search candidate is the geographic point at the unobscured viewport center, rather than the physical screen center behind the Sheet. Search is offered only after user movement of at least 100m (or initial manual selection). Zoom controls pivot on this unobscured center.

Camera fitting uses measured top content, current Sheet height, control lanes and marker margins. Native contentPadding stays zero: the entire occlusion padding is passed once to fitBounds so changing insets cannot silently move an explored camera. Naver attribution is repositioned separately. Sheet settlement refits only before user exploration; a new result always refits. Circle/markers use the same completed snapshot and HPID selection state.

Sheet sizes are 18% / 30% / 72%, constrained further to leave space for controls. All hospital metrics and NMC interpretation behavior are unchanged. No marker, heading, menu, Sheet or zoom event searches the backend.

## Location and heading

LocationFix preserves reported accuracy and measurement time; absent accuracy does not become an invented radius. Heading uses a separate compass stream. Android medium/high quality and iOS reported error at most 30 degrees are accepted; unknown/low quality falls back to a blue dot. Android quality is a categorical approximation, not a measured degree guarantee. UI updates are capped at 10Hz and stale heading expires after 10 seconds. Route/app backgrounding cancels the subscription. No background location or always-location permission is added.

Android/iOS physical-device validation of compass reference, rotation and permissions remains required. Emulator sensor data is not acceptance evidence for heading accuracy.

## Drawer and sessions

The Drawer uses a translucent surface, scrim and shadow. There is no map capture or blur implementation. Signed-out menus are login, profile, emergency information, settings and app information. Protected placeholders explicitly require login. Production defaults to a signed-out SessionSource; it never creates fake identities. Authenticated UI receives a real summary and sign-out boundary from a future adapter. Search and emergency UI have no authentication guard.

## Emergency dialing: development and QA

Default main.dart, run_mobile.py, dev flavor, debug/profile, all tests and CI use MockEmergencyDialer. It records a request in memory and returns simulated; it has no platform dependency. The confirmation UI reports that no phone connection was executed. No URI runs on startup, build, render, resume, navigation, retry or failure. There is no alternate emergency-number fallback.

SystemEmergencyDialer creation in FLUTTER_TEST, CI or EROUTE_TEST_HARNESS throws. Test harnesses explicitly override the dialer and install a fail-fast native-channel interceptor. Policy tests exercise every combination of production/release/enabled/physical/automation gates without invoking a launcher. Integration uses a fixed safe entrypoint and mandatory EROUTE_AUTOMATION=true / EROUTE_TEST_HARNESS=true. Never use the production entrypoint or an enabled production artifact for UI automation or smoke tests.

Actual 119/112 test calls, including physical-device QA, are prohibited. QA validates confirmation plus mock recording only. Native platform code is inspected and built; automated tests never invoke its emergency handoff method.

## Actual distribution boundary (not a QA procedure)

Only lib/main_production.dart may request SystemEmergencyDialer. It requires production flavor, release, ENABLE_SYSTEM_EMERGENCY_DIALER=true and EROUTE_AUTOMATION=false. Unknown/default configuration returns mock. Native code independently checks build settings and supported device status; Android rejects common emulator signatures and iOS excludes simulator/test-host builds. Device heuristics are defense in depth, not a substitute for separate test composition and distribution controls.

Android uses ACTION_DIAL only; CALL_PHONE permission is absent. iOS opens tel:119 only after ERoute user confirmation, then iOS supplies the final call confirmation. Neither result is treated as a completed call or accepted incident.

Android production uses the production flavor's release artifact; release signing must be configured for distribution (the existing development signing setup is not a deployment). iOS production scheme uses Release-production. Its additional native opt-in comes from an untracked ios/Flutter/EmergencyProduction.local.xcconfig with EROUTE_DISTRIBUTION_EMERGENCY_ENABLED=true and EROUTE_DISTRIBUTION_AUTOMATION=false. The file is intentionally not created for development. Dart opt-in flags are still independently required. A plain release build is insufficient on both platforms.

## Verification

Run flutter test and flutter analyze from apps/mobile. Build development APK with flutter build apk --debug --flavor dev. Run native map tests from repository root with scripts/test_mobile_integration.py and FLUTTER_BIN set. The native map test uses fixture hospitals, position and heading plus a MockEmergencyDialer and a rejecting native channel; it checks projection against the unobscured viewport and camera preservation after Sheet movement.

Full iOS compilation and physical-device sensor QA require Xcode and devices. No production telephone handoff is executed during these checks.

Validation completed on 2026-09-12 (Asia/Seoul): 28 unit/widget tests passed and flutter analyze reported no issues after the Landing, Map, Detail, Drawer, theme, and routing redesign. Pixel 10 native Naver-map integration from the previous map-UX gate passed, including projected bounds visibility and preservation of an explored camera after Sheet movement. Re-run that device gate after installing the new APK; it always uses fixture data and MockEmergencyDialer. No production emergency handoff was executed.
