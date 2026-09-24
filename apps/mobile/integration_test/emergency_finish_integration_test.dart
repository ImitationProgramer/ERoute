import 'package:eroute_mobile/features/member_ui/member_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:eroute_mobile/core/theme/eroute_theme.dart';
import 'package:eroute_mobile/features/app_menu/app_session.dart';
import 'package:eroute_mobile/features/emergency_call/emergency_dialer.dart';
import 'package:eroute_mobile/features/emergency_guides/presentation/guide_pages.dart';
import 'package:eroute_mobile/features/emergency_sms/emergency_sms_launcher.dart';
import 'package:eroute_mobile/features/member_ui/member_contract.dart';
import 'package:eroute_mobile/features/member_ui/member_health_screens.dart';
import 'package:eroute_mobile/features/member_ui/member_widgets.dart';
import 'package:eroute_mobile/preview/member_preview_repository.dart';
import '../test/emergency_sms_test.dart' show smsWidgetTests, FakeSms;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var converted = false;
  setUp(() => converted = false);
  Future<void> capture(String name) async {
    if (!converted) {
      await binding.convertFlutterSurfaceToImage();
      converted = true;
    }
    await binding.pump();
    await binding.takeScreenshot(name);
  }

  smsWidgetTests(capture: capture);
  testWidgets('guide/member state visual matrix with fake launchers only', (
    tester,
  ) async {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        await binding.setSurfaceSize(Size(scale == 2 ? 320 : 412, 860));
        for (final scenario in [
          'guide',
          'allergy-unset',
          'allergy-none',
          'allergy-recorded',
          'medication-unset',
          'medication-none',
          'medication-recorded',
          'memo-empty',
          'memo-filled',
          'memo-2000',
          'health',
        ]) {
          final auth = PreviewAuthRepository();
          final repo = PreviewMemberRepository(auth, delay: Duration.zero);
          final status = scenario.endsWith('unset')
              ? EntryStatus.unset
              : scenario.endsWith('none')
              ? EntryStatus.none
              : EntryStatus.recorded;
          repo.data = MemberHealthSnapshot(
            version: 1,
            consentEpoch: repo.epoch,
            allergies: HealthEntry(
              status,
              status == EntryStatus.recorded ? '사용자가 저장한 알레르기 정보' : '',
            ),
            note: scenario == 'memo-empty'
                ? ''
                : scenario == 'memo-2000'
                ? List.filled(2000, '가').join()
                : '구급대원에게 알려야 할 참고사항',
            medicationsStatus: status,
            medications: status == EntryStatus.recorded
                ? repo.data.medications
                : [],
          );
          Widget page;
          if (scenario == 'guide') {
            page = const GuideDetailPage(id: 'FIRST_AID_CPR_ADULT');
          } else if (scenario.startsWith('allergy')) {
            page = MemberFieldEditor(
              field: HealthField.allergies,
              base: repo.data,
            );
          } else if (scenario.startsWith('medication')) {
            page = const MemberMedicationScreen();
          } else if (scenario.startsWith('memo')) {
            page = MemberFieldEditor(field: HealthField.note, base: repo.data);
          } else {
            page = const MemberEmergencyScreen();
          }
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
              emergencyDialerProvider.overrideWithValue(MockEmergencyDialer()),
              emergencySmsLauncherProvider.overrideWithValue(FakeSms()),
            ],
          );
          final lease = container.listen(memberControllerProvider, (_, _) {});
          await container.read(memberControllerProvider.notifier).reload();
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: dark ? ERouteTheme.dark() : ERouteTheme.light(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: MemberSecurityScope(child: page),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (scenario.startsWith('memo')) {
            expect(
              tester.widget<TextField>(find.byType(TextField)).controller!.text,
              repo.data.note,
            );
          }
          if (scenario == 'allergy-recorded') {
            expect(
              tester.widget<TextField>(find.byType(TextField)).controller!.text,
              repo.data.allergies.text,
            );
          }
          await capture(
            '$scenario-${dark ? 'dark' : 'light'}-${scale == 2 ? '320-200' : '412-100'}',
          );
          if (scenario == 'memo-2000') {
            await tester.scrollUntilVisible(
              find.text('2000/2000'),
              220,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            await capture('memo-counter-${dark ? 'dark' : 'light'}-$scale');
          }
          if (scenario == 'guide') {
            await tester.scrollUntilVisible(
              find.text('지금 해야 할 일'),
              180,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            await capture('guide-steps-${dark ? 'dark' : 'light'}-$scale');
            await tester.scrollUntilVisible(
              find.text('출처 상세 정보').first,
              250,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.tap(find.text('출처 상세 정보').first);
            await tester.pumpAndSettle();
            await capture('guide-source-${dark ? 'dark' : 'light'}-$scale');
          }
          expect(
            tester.takeException(),
            isNull,
            reason: '$scenario dark=$dark scale=$scale',
          );
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          lease.close();
          container.dispose();
        }
      }
    }
    await binding.setSurfaceSize(null);
    binding.reportData = {
      ...?binding.reportData,
      'real119Calls': 0,
      'real119Messages': 0,
      'smsLauncher': 'fake',
      'device': 'Android emulator; physical Pixel 10 not connected',
    };
  });
}
