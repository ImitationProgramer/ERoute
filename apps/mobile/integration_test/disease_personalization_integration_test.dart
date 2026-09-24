import 'package:eroute_mobile/features/disease_personalization/condition_catalog_editor.dart';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:eroute_mobile/app/app.dart';
import 'package:eroute_mobile/app/router.dart';
import 'package:eroute_mobile/features/app_menu/app_session.dart';
import 'package:eroute_mobile/features/auth/auth_repository.dart';
import 'package:eroute_mobile/features/member_ui/member_controller.dart';
import 'package:eroute_mobile/features/member_ui/member_health_screens.dart';
import 'package:eroute_mobile/features/disease_personalization/disease_selection_screen.dart';
import 'package:eroute_mobile/features/disease_personalization/disease_reference.dart';
import 'package:eroute_mobile/features/disease_personalization/disease_repository.dart';
import 'package:eroute_mobile/features/disease_personalization/department_matcher.dart';

class TestMemoryVault implements TokenVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String? next) async {
    value = next;
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real Android selection/reconfirmation/removal/session boundaries with native protection',
    (tester) async {
      final auth = AuthRepository(vault: TestMemoryVault());
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(auth)],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        container.dispose();
      });
      String phone() =>
          '010${Random.secure().nextInt(100000000).toString().padLeft(8, '0')}';
      Future<void> signup() async {
        final user = await auth.passwordLogin(
          phone(),
          'QA ${authNonce()} test-only',
          signup: true,
          termsAccepted: true,
          age14OrOlder: true,
        );
        await container.read(sessionControllerProvider.notifier).accept(user);
      }

      final publicSubscription = container.listen(
        diseaseDataRepositoryProvider,
        (_, next) {},
      );
      addTearDown(publicSubscription.close);
      await container.read(sessionControllerProvider.future);
      await signup();
      var consent = (await auth.request(
        'GET',
        '/api/v1/me/health-consent',
      )).data;
      consent = (await auth.request(
        'POST',
        '/api/v1/me/health-consent',
        data: {'epoch': consent['epoch'], 'documentVersion': 'health-v1'},
      )).data;
      final epoch = consent['epoch'];
      Map<String, Object> profile(int version, String text) => {
        'version': version,
        'consentEpoch': epoch,
        'allergies': {'status': 'UNSET', 'text': ''},
        'conditions': {'status': 'RECORDED', 'text': text},
        'note': '',
        'medicationsStatus': 'UNSET',
      };
      await auth.request(
        'PUT',
        '/api/v1/me/conditions',
        data: {
          'version': 0,
          'consentEpoch': epoch,
          'status': 'RECORDED',
          'freeText': '천식 의심 · 가상 QA 원문',
          'diseaseIds': ['D001'],
          'catalogVersion':
              (await container.read(diseaseDataRepositoryProvider).reference())
                  .catalogVersion,
        },
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const ERouteApp(),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> settle() async {
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 200));
      }

      Future<void> waitFor(bool Function() ready) async {
        for (var i = 0; i < 150 && !ready(); i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(ready(), isTrue);
        await settle();
      }

      Future<void> selectionReady() async {
        await waitFor(
          () =>
              find.byType(DiseaseSelectionScreen).evaluate().isNotEmpty &&
              !container.read(memberControllerProvider).covered,
        );
        for (
          var i = 0;
          i < 30 && find.byType(TextField).evaluate().isEmpty;
          i++
        ) {
          await tester.drag(find.byType(ListView).last, const Offset(0, -180));
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(find.byType(TextField), findsOneWidget);
        await settle();
      }

      Future<void> tap(String text) async {
        if (text == '지도에서 활용할 질환 선택') {
          if (find.byType(ConditionCatalogEditor).evaluate().isEmpty) {
            await tap('기저질환');
          }
          await tap('병원 탐색 활용 설정');
          return;
        }
        final f = find.text(text);
        final scrolling = find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first;
        tester.state<ScrollableState>(scrolling).position.jumpTo(0);
        await tester.pump();
        await tester.scrollUntilVisible(
          f,
          250,
          scrollable: find
              .descendant(
                of: find.byType(ListView).last,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await Scrollable.ensureVisible(tester.element(f.last), alignment: 0.5);
        await tester.pumpAndSettle();
        await tester.tap(f.last);
        await settle();
      }

      pushAppRoute(
        tester.element(find.byType(Scaffold).first),
        AppRoutes.emergencyProfile,
      );
      await waitFor(
        () =>
            find.byType(MemberEmergencyScreen).evaluate().isNotEmpty &&
            !container.read(memberControllerProvider).covered,
      );
      await tap('지도에서 활용할 질환 선택');
      await selectionReady();
      debugPrint('DISEASE_QA_NATIVE_PRIVACY_READY');
      await tester.pump(const Duration(seconds: 2));
      final search = find.byType(TextField);
      await tester.scrollUntilVisible(
        search,
        250,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.enterText(search, 'asthma');
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await settle();
      await tap('천식');
      await tap('선택한 질환의 지도 활용 목적과 한계를 확인했습니다.');
      await tap('선택한 질환 확인하고 저장');
      await waitFor(
        () => find
            .byWidgetPredicate(
              (w) => w is DiseaseSelectionScreen && !w.recordMode,
            )
            .evaluate()
            .isEmpty,
      );
      var snapshot = (await auth.request(
        'GET',
        '/api/v1/me/health-snapshot',
      )).data;
      expect(snapshot['mapDiseaseSelection']['state'], 'CONFIRMED');
      expect(snapshot['conditions']['text'] == '천식 의심 · 가상 QA 원문', isTrue);
      await auth.request(
        'PUT',
        '/api/v1/me/emergency-profile',
        data: profile(snapshot['version'], '천식 없음 · 가상 QA 수정'),
      );
      await container.read(memberControllerProvider.notifier).reload();
      await settle();
      expect(
        container
            .read(memberControllerProvider)
            .health!
            .mapDiseaseSelection
            .state,
        'RECONFIRM_REQUIRED',
      );
      await tap('지도에서 활용할 질환 선택');
      await selectionReady();
      await tap('선택한 질환의 지도 활용 목적과 한계를 확인했습니다.');
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(container.read(memberControllerProvider).covered, isTrue);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await waitFor(() => !container.read(memberControllerProvider).covered);
      await tap('선택한 질환 확인하고 저장');
      await waitFor(
        () => find
            .byWidgetPredicate(
              (w) => w is DiseaseSelectionScreen && !w.recordMode,
            )
            .evaluate()
            .isEmpty,
      );
      await tap('지도에서 활용할 질환 선택');
      await selectionReady();
      await tap('지도 활용 해제');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextButton, '지도 활용 해제'),
        ),
      );
      await waitFor(
        () => find
            .byWidgetPredicate(
              (w) => w is DiseaseSelectionScreen && !w.recordMode,
            )
            .evaluate()
            .isEmpty,
      );
      snapshot = (await auth.request('GET', '/api/v1/me/health-snapshot')).data;
      expect(snapshot['mapDiseaseSelection']['state'], 'NOT_SELECTED');
      expect(snapshot['conditions']['text'] == '천식 없음 · 가상 QA 수정', isTrue);
      // Native production repository still uses only the Backend reference.
      final reference = await container
          .read(diseaseDataRepositoryProvider)
          .reference();
      expect(reference.status, 'READY');
      expect(reference.mappings, isEmpty);
      expect(reference.departments.length, 51);
      expect(publicDiseaseMapEnabled, isFalse);
      final rows = await container
          .read(diseaseDataRepositoryProvider)
          .departments(['synthetic-not-present']);
      expect(rows.single.recordStatus, 'NOT_FOUND');
      // Save again, then exercise withdrawal while the editor is open.
      await container.read(mapSelectionRepositoryProvider).save(
        snapshot['version'],
        epoch,
        ['D001'],
        reference,
      );
      await container.read(memberControllerProvider.notifier).reload();
      await settle();
      await tap('지도에서 활용할 질환 선택');
      await selectionReady();
      await auth.request(
        'POST',
        '/api/v1/me/health-consent/withdrawals',
        data: {'epoch': epoch},
        headers: {'Idempotency-Key': authNonce()},
      );
      await container.read(memberControllerProvider.notifier).reload();
      await settle();
      expect(container.read(memberControllerProvider).health, isNull);
      expect(find.byType(TextField), findsNothing);
      await container.read(sessionControllerProvider.notifier).signOut();
      await settle();
      expect(container.read(memberControllerProvider).health, isNull);
      await signup();
      await container.read(memberControllerProvider.notifier).reload();
      await settle();
      expect(container.read(memberControllerProvider).health, isNull);
      final session = MatchSession();
      session.clear();
      expect(session.results, isEmpty);
      await container.read(sessionControllerProvider.notifier).signOut();
      await tester.pumpWidget(const SizedBox());
      auth.dio.close();
      expect(tester.takeException(), isNull);
      debugPrint('DISEASE_QA_LIFECYCLE_COMPLETE');
    },
  );
}
