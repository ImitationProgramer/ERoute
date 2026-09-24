import '../test/support/category_visual_fixture.dart';
import 'package:eroute_mobile/features/disease_personalization/condition_local_store.dart';
import 'package:eroute_mobile/features/disease_personalization/disease_catalog.dart';
import 'package:eroute_mobile/core/map/naver_emergency_map_view.dart';
import 'package:eroute_mobile/core/location/heading_service.dart';
import 'package:eroute_mobile/features/emergency_map/domain/hospital_summary.dart';
import 'package:eroute_mobile/features/emergency_map/presentation/emergency_map_controller.dart';
import 'package:eroute_mobile/features/emergency_map/presentation/emergency_map_page.dart';
import '../test/emergency_map_test.dart' as hospitals;
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
import 'package:eroute_mobile/features/disease_personalization/disease_repository.dart';
import 'package:eroute_mobile/features/disease_personalization/map_personalization_controller.dart';
import 'package:eroute_mobile/development/disease_review_preview.dart';
import 'package:eroute_mobile/features/disease_personalization/personalization_badge.dart';
import 'package:eroute_mobile/features/disease_personalization/personalization_presentation.dart';
import '../test/support/disease_fixtures.dart';
import '../test/support/synthetic_personalization.dart';
import 'disease_personalization_integration_test.dart' show TestMemoryVault;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'v0.5 real Android tags and live preview preserve draft presentation',
    (tester) async {
      debugPrint('CATALOG_QA map init');
      await initializeNaverMap();
      final auth = AuthRepository(vault: TestMemoryVault());
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          hospitalRepositoryProvider.overrideWithValue(
            hospitals.FakeRepository(),
          ),
          locationServiceProvider.overrideWithValue(
            hospitals.FakeLocation(const GeoPoint(37, 127)),
          ),
          headingServiceProvider.overrideWithValue(hospitals.SilentHeading()),
        ],
      );
      addTearDown(() async {
        debugPrint('CATALOG_QA mount');
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        auth.dio.close();
      });
      final publicSubscription = container.listen(
        diseaseDataRepositoryProvider,
        (_, next) {},
      );
      addTearDown(publicSubscription.close);
      debugPrint('CATALOG_QA session restore');
      await container.read(sessionControllerProvider.future);
      debugPrint('CATALOG_QA signup');
      final user = await auth.passwordLogin(
        '010${Random.secure().nextInt(100000000).toString().padLeft(8, '0')}',
        'QA ${authNonce()} batch-two',
        signup: true,
        termsAccepted: true,
        age14OrOlder: true,
      );
      await container.read(sessionControllerProvider.notifier).accept(user);
      debugPrint('CATALOG_QA consent');
      var consent = (await auth.request(
        'GET',
        '/api/v1/me/health-consent',
      )).data;
      consent = (await auth.request(
        'POST',
        '/api/v1/me/health-consent',
        data: {'epoch': consent['epoch'], 'documentVersion': 'health-v1'},
      )).data;
      debugPrint('CATALOG_QA reference');
      final reference = await container
          .read(diseaseDataRepositoryProvider)
          .reference();
      expect(reference.version, 'eroute-disease-departments-v0.5');
      expect(reference.diseases.length, 46);
      expect(reference.mappings, isEmpty);
      final previewResponse = await auth.request(
        'GET',
        '/api/v1/dev/reference/disease-departments-review-preview',
      );
      final preview = ReviewPreviewCandidates.decode(
        Map<String, dynamic>.from(previewResponse.data as Map),
        reference,
      );
      expect(preview.version, reference.version);
      expect(preview.mappings.length, 61);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const ERouteApp(),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> waitFor(bool Function() ready) async {
        for (var i = 0; i < 150 && !ready(); i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(ready(), isTrue);
        await tester.pumpAndSettle();
      }

      Future<void> tap(String label) async {
        final checkbox = find.widgetWithText(CheckboxListTile, label);
        final target = checkbox.evaluate().isNotEmpty
            ? checkbox
            : find.text(label);
        final scroll = find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first;
        tester.state<ScrollableState>(scroll).position.jumpTo(0);
        await tester.pump();
        await tester.scrollUntilVisible(target, 250, scrollable: scroll);
        await Scrollable.ensureVisible(
          tester.element(target.last),
          alignment: .5,
        );
        await tester.pumpAndSettle();
        await tester.tap(target.last);
        await tester.pumpAndSettle();
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
      debugPrint('CATALOG_QA condition editor');
      await tap('기저질환');
      await waitFor(() => find.text('질환 검색').evaluate().isNotEmpty);
      expect(
        (await container.read(diseaseCatalogRepositoryProvider).catalog())
            .diseases
            .length,
        46,
      );
      await tap('호흡기');
      final asthma = find.byKey(const ValueKey('condition-D001'));
      await tester.scrollUntilVisible(
        asthma,
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(asthma);
      await tester.pumpAndSettle();

      for (final entry in {
        '고지혈증': '이상지질혈증',
        '고혈압': '고혈압',
        '뇌전증': '뇌전증',
        '당뇨': '당뇨병',
        'IPF': '특발성 폐섬유화증',
        '메니에르병': '메니에르병',
      }.entries) {
        final query = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '질환 검색',
        );
        final scroll = find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first;
        tester.state<ScrollableState>(scroll).position.jumpTo(0);
        await tester.pump();
        await tester.ensureVisible(query);
        await tester.enterText(query, entry.key);
        await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        await tester.pumpAndSettle();
        await tap(entry.value);
      }
      debugPrint('CATALOG_QA save conditions');
      await tap('기저질환 저장');
      await waitFor(
        () => find.byType(DiseaseSelectionScreen).evaluate().isEmpty,
      );
      await container.read(conditionLocalProvider.notifier).sync();
      await container.read(memberControllerProvider.notifier).reload();
      await tester.pumpAndSettle();
      await tap('기저질환');
      await waitFor(() => find.text('질환 검색').evaluate().isNotEmpty);
      await tap('목록에 없는 질환 직접 입력');
      final custom = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '직접 입력한 질환',
      );
      await tester.ensureVisible(custom);
      await tester.enterText(custom, 'QA 미등록 질환');
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await tester.pumpAndSettle();
      await tap('직접 입력 질환 추가');
      await tap('기저질환 저장');
      await waitFor(
        () => find.byType(DiseaseSelectionScreen).evaluate().isEmpty,
      );
      await container.read(conditionLocalProvider.notifier).sync();
      final saved = (await auth.request(
        'GET',
        '/api/v1/me/health-snapshot',
      )).data;
      expect(
        (saved['standardDiseaseSelection']['diseaseIds'] as List).toSet(),
        {'D001', 'D003', 'D010', 'D017', 'D018', 'D023', 'D046'},
      );
      expect(saved['mapDiseaseSelection']['state'], 'NOT_SELECTED');
      expect(saved['conditions']['text'], 'QA 미등록 질환');
      expect(
        (saved['conditionEntries'] as List)
            .where((e) => e['type'] == 'CUSTOM')
            .length,
        1,
      );
      await container.read(mapSelectionRepositoryProvider).save(
        saved['version'],
        consent['epoch'],
        ['D001', 'D003', 'D010', 'D017'],
        reference,
      );
      final sub = container.listen(mapPersonalizationProvider, (_, next) {});
      final controller = container.read(mapPersonalizationProvider.notifier);
      await controller.enable();
      expect(controller.state.message, '관련 진료과 정보 준비 중');
      expect(controller.state.results, isEmpty);
      controller.disable();
      Navigator.of(
        tester.element(find.byType(Scaffold).last),
      ).popUntil((r) => r.isFirst);
      await tester.pumpAndSettle();
      final nearby = find.byWidgetPredicate(
        (w) => w is Text && w.semanticsLabel == '가까운 병원 찾기',
      );
      await tester.ensureVisible(nearby);
      await tester.tap(nearby);
      await tester.pumpAndSettle();
      await waitFor(() => find.byType(EmergencyMapPage).evaluate().isNotEmpty);
      await waitFor(
        () =>
            container
                .read(mapControllerProvider)
                .result
                ?.hospitals
                .isNotEmpty ==
            true,
      );

      sub.close();
      await container.read(sessionControllerProvider.notifier).signOut();
      // Native rendering of live development candidates, with test-only hospital snapshots.
      for (final scenario in [
        ('D010', '신경과', PersonalizationAccent.filled),
        ('D045', '피부과', PersonalizationAccent.hollow),
        ('D001', '내과', PersonalizationAccent.none),
      ]) {
        final now = DateTime.now();
        final result = preview.match(
          reference,
          confirmedSelection(reference, [scenario.$1]),
          syntheticDepartmentSnapshot(names: [scenario.$2], now: now),
          now,
        )!;
        expect(result.matched, isTrue);
        expect(reviewPreviewAccent(result), scenario.$3);
        await tester.pumpWidget(
          withVisualCatalog(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: PersonalizationBadge(
                    key: ValueKey(scenario.$1),
                    result: result,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(compactPersonalizationLabel(result)),
          findsOneWidget,
        );
        await tester.tap(
          find.text(compactPersonalizationLabel(result)),
        );
        await tester.pumpAndSettle();
        expect(find.text('검수 상태: 개발 검수 중'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );
}
