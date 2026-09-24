// Synthetic visual QA only. Actual-account runtime evidence is recorded separately.
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:eroute_mobile/app/app.dart';
import 'package:eroute_mobile/core/location/location_fix.dart';
import 'package:eroute_mobile/core/theme/theme_controller.dart';
import 'package:eroute_mobile/features/app_menu/app_session.dart';
import 'package:eroute_mobile/features/disease_personalization/condition_local_store.dart';
import 'package:eroute_mobile/features/disease_personalization/emergency_condition.dart';
import 'package:eroute_mobile/features/disease_personalization/personalization_badge.dart';
import 'package:eroute_mobile/features/emergency_call/emergency_dialer.dart';
import 'package:eroute_mobile/features/emergency_map/domain/hospital_summary.dart';
import 'package:eroute_mobile/features/emergency_sms/emergency_sms_formatter.dart';
import 'package:eroute_mobile/features/emergency_sms/emergency_sms_launcher.dart';
import 'package:eroute_mobile/features/emergency_sms/emergency_sms_preview.dart';
import 'package:eroute_mobile/features/member_ui/member_contract.dart';
import 'package:eroute_mobile/features/member_ui/member_health_screens.dart';
import 'package:eroute_mobile/features/member_ui/member_widgets.dart';
import 'package:eroute_mobile/preview/member_preview_repository.dart';
import '../test/support/catalog_fixture.dart';
import '../test/support/disease_fixtures.dart';
import '../test/support/hospital_personalization_flow_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var converted = false;
  Future<void> capture(
    String name, [
    Map<String, Object?> args = const {},
  ]) async {
    if (Platform.isIOS && !name.startsWith('ios-')) name = 'ios-$name';
    if (Platform.isAndroid && !converted) {
      await binding.convertFlutterSurfaceToImage();
      converted = true;
    }
    await binding.pump();
    if (args.containsKey('expectedBody')) {
      binding.reportData ??= {};
      final hashes =
          binding.reportData!.putIfAbsent(
                'canonicalHashes',
                () => <String, String>{},
              )
              as Map<String, String>;
      hashes[name] = sha256
          .convert(utf8.encode(args['expectedBody'] as String))
          .toString();
    }
    await binding.takeScreenshot(name);
  }

  setUp(() => converted = false);

  testWidgets('synthetic map card and reason preserve review boundary', (
    tester,
  ) async {
    await binding.setSurfaceSize(const Size(412, 860));
    final f = FlowFixture();
    await f.container.read(sessionControllerProvider.future);
    final catalog = await FixtureCatalogRepository().catalog();
    const ids = ['D001', 'D003', 'D017'];
    f.member.data = flowHealth(
      f.member.data,
      local: LocalConditions(
        userId: f.member.user['userId'],
        epoch: f.member.epoch,
        baseVersion: 1,
        catalogVersion: catalog.version,
        status: 'RECORDED',
        entries: [
          for (final id in ids)
            EmergencyCondition.standard(id, catalog.byId(id)!.name),
        ],
      ),
      selection: confirmedSelection(f.data.referenceValue, ids),
    );
    await tester.pumpWidget(f.app());
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is Text && w.semanticsLabel == '가까운 병원 찾기',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('DEV ·'), findsNothing);
    expect(find.textContaining('검수 중'), findsNothing);
    expect(
      find.byKey(const ValueKey('personalization-context')),
      findsOneWidget,
    );
    await capture('map-no-dev-banner');
    await capture('hospital-card-no-review');
    await tester.tap(
      find.descendant(
        of: find.byType(PersonalizationBadge).first,
        matching: find.byType(TextButton),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('개발 미리보기 · 검수 중'));
    await tester.pumpAndSettle();
    expect(find.textContaining('BROAD_PARENT'), findsNothing);
    expect(find.textContaining('EXACT_CANONICAL'), findsNothing);
    await capture('personalization-reason-dev-review');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    f.container.dispose();
  });

  for (final dark in [false, true]) {
    testWidgets('synthetic product SMS/native capability dark=$dark', (
      tester,
    ) async {
      await binding.setSurfaceSize(Size(dark ? 320 : 412, 860));
      final auth = PreviewAuthRepository();
      final repo = PreviewMemberRepository(auth, delay: Duration.zero);
      repo.data = MemberHealthSnapshot(
        version: 1,
        consentEpoch: repo.epoch,
        conditions: const HealthEntry(EntryStatus.recorded, ''),
        conditionEntries: const [
          EmergencyCondition.standard('QA_STANDARD', '합성 표준 질환'),
          EmergencyCondition.custom('합성 직접 입력 질환'),
        ],
        allergies: const HealthEntry(EntryStatus.none, ''),
        medicationsStatus: EntryStatus.recorded,
        medications: [
          MedicationEntry(
            id: 'qa',
            name: '합성 복용약',
            note: '합성 복용 메모',
            version: 1,
            updatedAt: DateTime(2026, 9, 22),
          ),
        ],
        note: 'QA 합성 메모 — 선택 해제 검증',
      );
      final location = dark
          ? null
          : LocationFix(const GeoPoint(37, 127), measuredAt: DateTime.now());
      final dialer = MockEmergencyDialer();
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          sessionProvider.overrideWithValue(
            AppSession(
              phase: SessionPhase.authenticated,
              user: repo.user,
              generation: auth.generation,
            ),
          ),
          memberUiRepositoryProvider.overrideWithValue(repo),
          memberPrivacyProvider.overrideWithValue(PreviewPrivacy()),
          emergencyDialerProvider.overrideWithValue(dialer),
          themeModeProvider.overrideWith(
            (ref) => dark ? ThemeMode.dark : ThemeMode.light,
          ),
          emergencySmsLocationProvider.overrideWith((ref) async => location),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const ERouteApp(),
        ),
      );
      // ERouteApp inherits the platform text scale; apply the test scale through the view.
      tester.platformDispatcher.textScaleFactorTestValue = dark ? 2 : 1;
      await tester.pumpAndSettle();
      final prefix = Platform.isIOS ? 'ios' : 'android';
      await capture('$prefix-home${dark ? '-dark-200' : ''}');
      await tester.ensureVisible(find.text('119 신고').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('119 신고').first);
      await tester.pumpAndSettle();
      expect(find.text('응급정보 문자 준비'), findsOneWidget);
      final call = find.widgetWithText(FilledButton, '119 전화 연결');
      final sms = find.text('응급정보 문자 준비');
      expect(tester.getTopLeft(call).dy, lessThan(tester.getTopLeft(sms).dy));
      await capture('$prefix-119-dialog${dark ? '-dark-200' : ''}');
      await tester.tap(sms);
      await tester.pumpAndSettle();
      expect(find.byType(EmergencySmsPreview), findsOneWidget);
      await capture(dark ? '$prefix-sms-preview-dark-200' : 'sms-preview');
      final note = find.widgetWithText(CheckboxListTile, '응급 메모');
      await tester.scrollUntilVisible(
        note,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(note);
      await tester.pumpAndSettle();
      final fields = emergencySmsFields(repo.data, location)..remove('응급 메모');
      final body = formatEmergencySms(fields);
      expect(body, isNot(contains(repo.data.note)));
      await capture(
        dark ? '$prefix-sms-selected-dark-200' : 'sms-preview-selected-fields',
      );
      final handoff = find.widgetWithText(OutlinedButton, '문자 앱에서 확인하고 보내기');
      await tester.scrollUntilVisible(
        handoff,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      final available = await const NativeEmergencySmsLauncher().canCompose();
      if (Platform.isIOS) {
        expect(
          available,
          isFalse,
          reason:
              'Simulator capability is expected unavailable; physical testing is separate',
        );
        expect(tester.widget<OutlinedButton>(handoff).onPressed, isNull);
        expect(
          find.textContaining('이 기기에서는 문자 작성 기능을 사용할 수 없습니다.'),
          findsOneWidget,
        );
        await capture('ios-sms-unavailable${dark ? '-dark-200' : ''}');
        await tester.tap(find.text('닫기'));
        await tester.pumpAndSettle();
      } else {
        expect(available, isTrue);
        await tester.tap(handoff);
        await tester.pumpAndSettle();
        // The host watcher captures Messages, clears the synthetic draft and
        // presses Back. Native UI cannot be captured by a Flutter surface.
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(seconds: 2));
          for (
            var i = 0;
            i < 120 && binding.lifecycleState != AppLifecycleState.resumed;
            i++
          ) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
        });
        await tester.pumpAndSettle();
        expect(binding.lifecycleState, AppLifecycleState.resumed);
        await capture(
          dark ? 'android-sms-composer-no-location' : 'android-sms-composer',
          {'expectedBody': body},
        );
        await tester.pumpAndSettle();
      }
      expect(dialer.requests, isEmpty);
      if (!dark) {
        // Real product routes, synthetic repository. No authentication claim.
        final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
        nav.pushNamed('/first-aid');
        await tester.pumpAndSettle();
        await capture('$prefix-guide');
        nav.pop();
        nav.pushNamed('/emergency-profile');
        await tester.pumpAndSettle();
        expect(find.byType(MemberEmergencyScreen), findsOneWidget);
        await capture('$prefix-member-health');
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      container.dispose();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
  }
}
