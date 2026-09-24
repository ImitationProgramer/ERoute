import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eroute_mobile/core/location/location_fix.dart';
import 'package:eroute_mobile/core/theme/eroute_theme.dart';
import 'package:eroute_mobile/features/app_menu/app_session.dart';
import 'package:eroute_mobile/features/disease_personalization/emergency_condition.dart';
import 'package:eroute_mobile/features/emergency_call/emergency_call_coordinator.dart';
import 'package:eroute_mobile/features/emergency_call/emergency_dialer.dart';
import 'package:eroute_mobile/features/emergency_map/domain/hospital_summary.dart';
import 'package:eroute_mobile/features/emergency_sms/emergency_sms_formatter.dart';
import 'package:eroute_mobile/features/emergency_sms/emergency_sms_launcher.dart';
import 'package:eroute_mobile/features/emergency_sms/emergency_sms_preview.dart';
import 'package:eroute_mobile/features/member_ui/member_contract.dart';
import 'package:eroute_mobile/features/member_ui/member_controller.dart';
import 'package:eroute_mobile/features/member_ui/member_widgets.dart';
import 'package:eroute_mobile/preview/member_preview_repository.dart';

class FakeSms implements EmergencySmsLauncher {
  bool available = true;
  @override
  Future<bool> canCompose() async => available;
  final bodies = <String>[];
  bool success = false;
  @override
  Future<bool> compose(String body) async {
    bodies.add(body);
    return success;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'canonical fields preserve STANDARD/CUSTOM, explicit none and omissions',
    () {
      final h = MemberHealthSnapshot(
        version: 999,
        consentEpoch: 888,
        conditionEntries: const [
          EmergencyCondition.standard('secret-id', '천식'),
          EmergencyCondition.custom('사용자 원문 & + #\n참고'),
        ],
        allergies: const HealthEntry(EntryStatus.none),
      );
      final body = formatEmergencySms(
        emergencySmsFields(
          h,
          LocationFix(
            const GeoPoint(37.1234567, 127.7654321),
            measuredAt: DateTime.now(),
          ),
        ),
      );
      expect(body, contains('기저질환: 천식, 사용자 원문 & + #\n참고'));
      expect(body, contains('알레르기: 없음'));
      expect(body, contains('37.123457, 127.765432'));
      for (final absent in [
        '복용약:',
        '응급 메모:',
        '미입력',
        'secret-id',
        '999',
        '888',
        '내과',
        'userId',
        'consentEpoch',
      ]) {
        expect(body, isNot(contains(absent)));
      }
      expect(
        formatEmergencySms(emergencySmsFields(h, null)),
        isNot(contains('현재 위치:')),
      );
    },
  );
  test(
    'native channel percent encodes once and catches failure; no actual platform action',
    () async {
      const launcher = NativeEmergencySmsLauncher();
      const body = '한글 & + #\n천식';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeEmergencySmsLauncher.channel, (
            call,
          ) async {
            expect(call.method, 'compose');
            expect(
              Uri.decodeComponent((call.arguments as Map)['encodedBody']),
              body,
            );
            return true;
          });
      expect(await launcher.compose(body), isTrue);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            NativeEmergencySmsLauncher.channel,
            (_) async => throw PlatformException(code: 'unavailable'),
          );
      expect(await launcher.compose(body), isFalse);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeEmergencySmsLauncher.channel, null);
    },
  );
  test('native handoff contains no direct send or SEND_SMS permission', () {
    final android = File(
      'android/app/src/main/kotlin/com/eroute/eroute_mobile/MainActivity.kt',
    ).readAsStringSync();
    final ios = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(android, contains('Intent.ACTION_SENDTO'));
    expect(android, contains('smsto:119'));
    expect(android, isNot(contains('SmsManager')));
    expect(ios, contains('MFMessageComposeViewController'));
    expect(ios, contains('composer.recipients = ["119"]'));
    for (final file
        in Directory('android/app/src')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('AndroidManifest.xml'))) {
      expect(
        file.readAsStringSync(),
        isNot(contains('android.permission.SEND_SMS')),
      );
    }
  });
  test('native capability is read-only and fails closed', () async {
    const launcher = NativeEmergencySmsLauncher();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final available in [true, false]) {
      messenger.setMockMethodCallHandler(NativeEmergencySmsLauncher.channel, (
        call,
      ) async {
        expect(call.method, 'canCompose');
        expect(call.arguments, isNull);
        return available;
      });
      expect(await launcher.canCompose(), available);
    }
    messenger.setMockMethodCallHandler(NativeEmergencySmsLauncher.channel, (
      _,
    ) async {
      throw PlatformException(code: 'unavailable');
    });
    expect(await launcher.canCompose(), isFalse);
    messenger.setMockMethodCallHandler(
      NativeEmergencySmsLauncher.channel,
      null,
    );
  });
  smsWidgetTests();
}

void smsWidgetTests({Future<void> Function(String)? capture}) {
  for (final loggedIn in [false, true]) {
    for (final granted in [false, true]) {
      testWidgets(
        'SMS option login=$loggedIn consent=$granted; call remains primary',
        (tester) async {
          final auth = PreviewAuthRepository();
          final repo = PreviewMemberRepository(auth, delay: Duration.zero)
            ..granted = granted;
          final dialer = MockEmergencyDialer();
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                sessionProvider.overrideWithValue(
                  loggedIn
                      ? AppSession(
                          phase: SessionPhase.authenticated,
                          user: repo.user,
                          generation: auth.generation,
                        )
                      : const AppSession.signedOut(),
                ),
                memberUiRepositoryProvider.overrideWithValue(repo),
                emergencyDialerProvider.overrideWithValue(dialer),
              ],
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ERouteTheme.light(),
                home: Scaffold(
                  body: Consumer(
                    builder: (context, ref, _) => TextButton(
                      onPressed: () =>
                          ref.read(emergencyCallProvider).confirm(context),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          expect(
            find.text('응급정보 문자 준비'),
            loggedIn && granted ? findsOneWidget : findsNothing,
          );
          if (capture != null) await capture('dialog-$loggedIn-$granted');
          await tester.tap(find.widgetWithText(FilledButton, '119 전화 연결'));
          await tester.pumpAndSettle();
          expect(dialer.requests, ['119']);
        },
      );
    }
  }
  for (final scenario in [
    'empty-success',
    'location-only',
    'account-switch',
    'background',
    'dismissed',
    'unavailable',
  ]) {
    testWidgets('SMS handoff lifetime: $scenario', (tester) async {
      final auth = PreviewAuthRepository();
      final repo = PreviewMemberRepository(auth, delay: Duration.zero);
      repo.data = MemberHealthSnapshot(version: 1, consentEpoch: repo.epoch);
      final sms = FakeSms()..success = true;
      sms.available = scenario != 'unavailable';
      final sessionState = StateProvider(
        (ref) => AppSession(
          phase: SessionPhase.authenticated,
          user: repo.user,
          generation: auth.generation,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith((ref) => ref.watch(sessionState)),
          memberUiRepositoryProvider.overrideWithValue(repo),
          memberPrivacyProvider.overrideWithValue(PreviewPrivacy()),
          emergencySmsLauncherProvider.overrideWithValue(sms),
          emergencySmsLocationProvider.overrideWith(
            (ref) async => scenario == 'location-only'
                ? LocationFix(
                    const GeoPoint(37, 127),
                    measuredAt: DateTime.now(),
                  )
                : null,
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ERouteTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showEmergencySmsPreview(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final send = find.widgetWithText(OutlinedButton, '문자 앱에서 확인하고 보내기');
      await tester.scrollUntilVisible(
        send,
        150,
        scrollable: find.byType(Scrollable).last,
      );
      if (scenario == 'unavailable') {
        expect(
          find.textContaining('이 기기에서는 문자 작성 기능을 사용할 수 없습니다.'),
          findsOneWidget,
        );
        expect(tester.widget<OutlinedButton>(send).onPressed, isNull);
        expect(sms.bodies, isEmpty);
        if (capture != null) await capture('sms-unavailable');
        await tester.tap(find.text('닫기'));
        await tester.pumpAndSettle();
        expect(find.byType(EmergencySmsPreview), findsNothing);
        return;
      }
      repo.delay = const Duration(milliseconds: 300);
      await tester.tap(send);
      await tester.pump();
      if (scenario == 'account-switch') {
        container.read(sessionState.notifier).state =
            const AppSession.signedOut();
      } else if (scenario == 'background') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
      } else if (scenario == 'dismissed') {
        await tester.tap(find.text('닫기'));
      }
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      final success =
          scenario == 'empty-success' || scenario == 'location-only';
      expect(sms.bodies.length, success ? 1 : 0);
      if (success) {
        expect(find.byType(EmergencySmsPreview), findsNothing);
        expect(
          sms.bodies.single.contains('현재 위치:'),
          scenario == 'location-only',
        );
      }
      await tester.pumpWidget(const SizedBox());
      if (scenario == 'background') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
    });
  }
  for (final dark in [false, true]) {
    for (final hasLocation in [false, true]) {
      testWidgets('SMS selected preview 320dp 200% dark=$dark location=$hasLocation', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(320, 740));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final auth = PreviewAuthRepository();
        final repo = PreviewMemberRepository(auth, delay: Duration.zero);
        repo.data = MemberHealthSnapshot(
          version: 1,
          consentEpoch: repo.epoch,
          conditionEntries: const [
            EmergencyCondition.standard('ASTHMA', '천식'),
            EmergencyCondition.custom('직접 저장한 질환'),
          ],
          allergies: const HealthEntry(EntryStatus.none),
          note: List.filled(100, '참고할 정보입니다. ').join(),
        );
        final sms = FakeSms();
        final dialer = MockEmergencyDialer();
        final container = ProviderContainer(
          overrides: [
            sessionProvider.overrideWithValue(
              AppSession(
                phase: SessionPhase.authenticated,
                user: repo.user,
                generation: auth.generation,
              ),
            ),
            memberUiRepositoryProvider.overrideWithValue(repo),
            memberPrivacyProvider.overrideWithValue(PreviewPrivacy()),
            emergencySmsLauncherProvider.overrideWithValue(sms),
            emergencyDialerProvider.overrideWithValue(dialer),
            emergencySmsLocationProvider.overrideWith(
              (ref) async => hasLocation
                  ? LocationFix(
                      const GeoPoint(37, 127),
                      measuredAt: DateTime.now(),
                    )
                  : null,
            ),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: dark ? ERouteTheme.dark() : ERouteTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(2)),
                child: child!,
              ),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showEmergencySmsPreview(context),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        if (capture != null) {
          await capture(
            'sms-top-${dark ? 'dark' : 'light'}-${hasLocation ? 'location' : 'no-location'}-320-200',
          );
        }
        await tester.scrollUntilVisible(
          find.text('천식, 직접 저장한 질환'),
          160,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text('천식, 직접 저장한 질환'), findsOneWidget);
        expect(
          emergencySmsFields(repo.data, null).containsKey('현재 위치'),
          isFalse,
        );
        expect(sms.bodies, isEmpty);
        if (capture != null) {
          await capture(
            'sms-${dark ? 'dark' : 'light'}-${hasLocation ? 'location' : 'no-location'}-320-200',
          );
        }
        // Exclude long note; actual composer must receive exactly the selected fields.
        final note = find.text('응급 메모');
        await tester.scrollUntilVisible(
          note,
          160,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        await tester.tap(note);
        await tester.pumpAndSettle();
        final send = find.widgetWithText(OutlinedButton, '문자 앱에서 확인하고 보내기');
        await tester.scrollUntilVisible(
          send,
          160,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        await tester.tap(send);
        await tester.pumpAndSettle();
        expect(sms.bodies.length, 1);
        expect(sms.bodies.single, isNot(contains('응급 메모:')));
        expect(sms.bodies.single, contains('알레르기: 없음'));
        expect(find.textContaining('문자 작성 화면을 열지 못했습니다.'), findsOneWidget);
        if (capture != null) {
          await capture(
            'sms-failure-${dark ? 'dark' : 'light'}-${hasLocation ? 'location' : 'no-location'}',
          );
        }
        expect(tester.takeException(), isNull);
        // Revocation between preview and handoff fails closed.
        repo.granted = false;
        await tester.scrollUntilVisible(
          send,
          160,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        await tester.tap(send);
        await tester.pumpAndSettle();
        expect(sms.bodies.length, 1);
        expect(container.read(memberControllerProvider).covered, isTrue);
        // Emergency call remains reachable even after losing health access.
        final call = find.widgetWithText(FilledButton, '119 전화 연결');
        await tester.scrollUntilVisible(
          call,
          -200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(call);
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
