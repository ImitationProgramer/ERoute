// Existing synthetic QA credentials, real local Backend and product repositories.
// Read-only health/access QA. Never grants consent or changes health records.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:eroute_mobile/main.dart' as app;
import 'package:eroute_mobile/app/app.dart';
import 'package:eroute_mobile/features/app_menu/app_session.dart';
import 'package:eroute_mobile/features/member_ui/member_auth_screen.dart';
import 'package:eroute_mobile/features/member_ui/member_controller.dart';
import 'package:eroute_mobile/features/emergency_sms/emergency_sms_launcher.dart';
import 'package:eroute_mobile/features/emergency_sms/emergency_sms_preview.dart';
import 'package:eroute_mobile/features/emergency_call/emergency_dialer.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'iOS general app real Backend login and native unavailable boundary',
    (tester) async {
      expect(Platform.isIOS, isTrue);
      final account =
          jsonDecode(const String.fromEnvironment('MEMBER_TEST_ACCOUNT'))
              as Map;
      await app.main();
      await tester.pumpAndSettle();
      final c = ProviderScope.containerOf(
        tester.element(find.byType(ERouteApp)),
      );
      Future<void> waitFor(bool Function() ready) async {
        for (var i = 0; i < 150 && !ready(); i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          ready(),
          isTrue,
          reason:
              'Expected server-confirmed state within 15 seconds (credentials redacted)',
        );
        await tester.pumpAndSettle();
      }

      await waitFor(
        () => c.read(sessionProvider).phase != SessionPhase.restoring,
      );
      if (c.read(sessionProvider).authenticated) {
        await c.read(sessionControllerProvider.notifier).signOut();
        await tester.pumpAndSettle();
      }
      expect(c.read(emergencyDialerProvider), isA<MockEmergencyDialer>());
      await tester.tap(find.byTooltip('메뉴 열기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('로그인').first);
      await tester.pumpAndSettle();
      expect(find.byType(MemberAuthScreen), findsOneWidget);
      await binding.takeScreenshot('ios-login-empty');
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), account['phone'] as String);
      await tester.enterText(fields.at(1), account['password'] as String);
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await tester.pumpAndSettle();
      final submit = find.widgetWithText(FilledButton, '로그인');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await waitFor(() => c.read(sessionProvider).authenticated);
      await waitFor(() => c.read(memberControllerProvider).access != null);
      final access = c.read(memberControllerProvider).access!;
      expect(await const NativeEmergencySmsLauncher().canCompose(), isFalse);
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.popUntil((route) => route.isFirst);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('119 신고').first);
      await tester.tap(find.text('119 신고').first);
      await tester.pumpAndSettle();
      await waitFor(() => !c.read(emergencySmsAccessProvider).isLoading);
      expect(
        find.text('응급정보 문자 준비'),
        access.granted ? findsOneWidget : findsNothing,
      );
      expect(find.widgetWithText(FilledButton, '119 전화 연결'), findsOneWidget);
      await binding.takeScreenshot('ios-119-real-login');
      int? healthVersion;
      if (access.granted) {
        await tester.tap(find.text('응급정보 문자 준비'));
        await tester.pumpAndSettle();
        await waitFor(() => c.read(memberControllerProvider).health != null);
        healthVersion = c.read(memberControllerProvider).health!.version;
        expect(
          find.text('이 기기에서는 문자 작성 기능을 사용할 수 없습니다. 긴급 상황에서는 119에 전화하세요.'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, '문자 앱에서 확인하고 보내기'),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.text('닫기'));
      } else {
        expect(c.read(memberControllerProvider).health, isNull);
        await tester.tap(find.text('취소'));
      }
      await tester.pumpAndSettle();
      binding.reportData = {
        ...?binding.reportData,
        'realRepository': true,
        'syntheticQaAccount': true,
        'login': 'PASS',
        'access': access.consentState,
        'healthRead': access.granted ? 'PASS' : 'BLOCKED by unchanged consent',
        'smsOption': access.granted ? 'visible' : 'hidden',
        'consentEpoch': access.consentEpoch,
        'healthVersion': healthVersion,
        'healthValuesLoggedOrCaptured': false,
        'nativeCapability': false,
        'actualCall': 0,
        'actualSend': 0,
      };
      await c.read(sessionControllerProvider.notifier).signOut();
      await tester.pumpAndSettle();
      expect(c.read(sessionProvider).authenticated, isFalse);
      expect(
        (c.read(emergencyDialerProvider) as MockEmergencyDialer).requests,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
