import 'package:eroute_mobile/features/disease_personalization/condition_catalog_editor.dart';
import 'dart:convert';
import 'package:eroute_mobile/features/emergency_map/domain/hospital_summary.dart';
import '../test/support/personalization_qa.dart';
import 'package:eroute_mobile/features/disease_personalization/personalization_badge.dart';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:eroute_mobile/app/app.dart';
import 'package:eroute_mobile/app/router.dart';
import 'package:eroute_mobile/core/theme/theme_controller.dart';
import 'package:eroute_mobile/core/map/naver_emergency_map_view.dart';
import 'package:eroute_mobile/core/map/map_camera_controller.dart';
import 'package:eroute_mobile/features/app_menu/app_session.dart';
import 'package:eroute_mobile/features/auth/auth_repository.dart';
import 'package:eroute_mobile/features/member_ui/member_controller.dart';
import 'package:eroute_mobile/features/member_ui/member_contract.dart';
import 'package:eroute_mobile/features/member_ui/member_health_screens.dart';
import 'package:eroute_mobile/features/disease_personalization/disease_selection_screen.dart';
import 'package:eroute_mobile/features/disease_personalization/disease_repository.dart';
import 'package:eroute_mobile/features/disease_personalization/map_personalization_controller.dart';
import 'package:eroute_mobile/features/emergency_map/presentation/emergency_map_controller.dart';
import 'package:eroute_mobile/development/disease_review_preview.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'actual v0.4 candidates, stored hospital search, native Flutter map and private lifecycle',
    (tester) async {
      expect(reviewPreviewBuild, isTrue);
      // Real secure vault retains the isolated QA login for the final normal dev APK.
      final auth = AuthRepository();
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(auth)],
      );
      final publicSubscription = container.listen(
        diseaseDataRepositoryProvider,
        (_, next) {},
      );
      addTearDown(publicSubscription.close);
      container.read(themeModeProvider.notifier).state = ThemeMode.light;
      await container.read(sessionControllerProvider.future);
      final phone =
          '010${Random.secure().nextInt(100000000).toString().padLeft(8, '0')}';
      final password = 'QA ${authNonce()} review-preview';
      final user = await auth.passwordLogin(
        phone,
        password,
        signup: true,
        termsAccepted: true,
        age14OrOlder: true,
      );
      await container.read(sessionControllerProvider.notifier).accept(user);
      // Private recovery data is never included in QA screenshots or results.
      await File(
        '${Directory.systemTemp.path}/review-preview-account.json',
      ).writeAsString(jsonEncode({'phone': phone, 'password': password}));
      var consent = (await auth.request(
        'GET',
        '/api/v1/me/health-consent',
      )).data;
      consent = (await auth.request(
        'POST',
        '/api/v1/me/health-consent',
        data: {'epoch': consent['epoch'], 'documentVersion': 'health-v1'},
      )).data;
      final reference = await container
          .read(diseaseDataRepositoryProvider)
          .reference();
      expect(reference.mappings, isEmpty);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const ERouteApp(),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> waitFor(bool Function() ready) async {
        for (var i = 0; i < 250 && !ready(); i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(ready(), isTrue);
        await tester.pumpAndSettle();
      }

      Future<void> tap(String label) async {
        if (label == '지도에서 활용할 질환 선택') {
          if (find.byType(ConditionCatalogEditor).evaluate().isEmpty) {
            await tap('기저질환');
          }
          await tap('병원 탐색 활용 설정');
          return;
        }
        final target = find.text(label);
        final scroll = find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first;
        tester.state<ScrollableState>(scroll).position.jumpTo(0);
        await tester.pump();
        for (var i = 0; i < 35 && target.evaluate().isEmpty; i++) {
          await tester.drag(scroll, const Offset(0, -220));
          await tester.pumpAndSettle();
        }
        await Scrollable.ensureVisible(
          tester.element(target.last),
          alignment: .5,
        );
        await tester.pumpAndSettle();
        await tester.tap(target.last);
        await tester.pumpAndSettle();
      }

      var converted = false;
      Future<void> capture(String name) async {
        if (name.contains('reason')) {
          // Renew through the real authority check, never bypass the privacy lease.
          // Otherwise a screenshot can catch the intentional 10s redaction window.
          final previous = container.read(reviewPreviewProvider);
          await container.read(reviewPreviewProvider.notifier).refresh();
          await waitFor(
            () =>
                !identical(container.read(reviewPreviewProvider), previous) &&
                container.read(reviewPreviewProvider).results.isNotEmpty,
          );
          expect(
            tester
                .widget<PersonalizationReasonSheet>(
                  find.byType(PersonalizationReasonSheet),
                )
                .result
                ?.matched,
            isTrue,
          );
          expect(find.textContaining('reviewClass:'), findsNothing);
          if (name.contains('close')) {
            await tester.ensureVisible(find.text('닫기'));
            await tester.pumpAndSettle();
          }
        }
        if (!converted) {
          await binding.convertFlutterSurfaceToImage();
          converted = true;
        }
        for (
          var frame = 0;
          frame < (name.contains('reason') ? 2 : 20);
          frame++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        // Validate every painted badge against its actual installed SDK marker.
        final mapView = find.byType(NaverEmergencyMapView);
        if (mapView.evaluate().isNotEmpty && !name.contains('reason')) {
          final dynamic native = tester.state(mapView);
          final dots = find.byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key as ValueKey<String>).value.startsWith(
                  'personalization-dot:',
                ),
          );
          for (final element in dots.evaluate()) {
            final id = (element.widget.key as ValueKey<String>).value
                .split(':')
                .last;
            final dynamic marker = (native.debugHospitalMarkers as Map)[id];
            expect(marker, isNotNull);
            final Offset point = await native.project(
              GeoPoint(marker.position.latitude, marker.position.longitude),
            );
            final relative =
                tester.getCenter(find.byKey(element.widget.key!)) -
                tester.getTopLeft(mapView) -
                point;
            final radius =
                marker.size.width *
                HospitalMarkerGeometry.iconRadius /
                HospitalMarkerGeometry.iconCanvasSize;
            expect(relative.dx, greaterThan(0));
            expect(relative.dx, closeTo(-relative.dy, .8));
            expect(relative.distance - 4 - radius, closeTo(-2, .8));
          }
        }
        if (name.contains('reason')) {
          expect(
            tester
                .widget<PersonalizationReasonSheet>(
                  find.byType(PersonalizationReasonSheet),
                )
                .result
                ?.matched,
            isTrue,
          );
        }
        final bytes = await binding.takeScreenshot(name);
        final f = File('${Directory.systemTemp.path}/eroute-review-$name.png');
        await f.writeAsBytes(bytes);
        debugPrint('QA_IMAGE ${f.path}');
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
      await tap('기저질환');
      await waitFor(() => find.text('질환 추가').evaluate().isNotEmpty);
      await tap('질환 추가');
      const scenarios = {
        '천식': 'asthma',
        '뇌전증': 'epilepsy',
        '건선': 'psoriasis',
        '메니에르병': 'meniere',
        '녹내장': 'glaucoma',
        '요로결석': 'stone',
        '자궁내막증': 'endometriosis',
      };
      for (final name in scenarios.keys) {
        final query = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '질환 검색',
        );
        await tester.ensureVisible(query);
        await tester.enterText(query, name);
        await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        await tester.pumpAndSettle();
        await tap(name);
      }
      await capture('01-tags-light');
      await tap('기저질환 저장');
      await waitFor(
        () => find.byType(DiseaseSelectionScreen).evaluate().isEmpty,
      );
      await tap('지도에서 활용할 질환 선택');
      await waitFor(
        () =>
            find.byType(DiseaseSelectionScreen).evaluate().isNotEmpty &&
            find.text('천식').evaluate().isNotEmpty,
      );
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
      pushAppRoute(tester.element(find.byType(Scaffold).first), AppRoutes.map);
      await waitFor(
        () =>
            find.byType(NaverEmergencyMapView).evaluate().isNotEmpty &&
            container.read(mapControllerProvider).snapshot != null &&
            !container.read(mapControllerProvider).loading,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(mapAuthenticationError.value, isFalse);
      final map = container.read(mapControllerProvider);
      var order = map.snapshot!.result.hospitals.map((h) => h.hpid).toList();
      expect(order, isNotEmpty);
      container.read(reviewPreviewProvider.notifier).disable();
      await tester.pumpAndSettle();
      await capture('02-off-light');
      final report = <String, dynamic>{
        'referenceVersion': reference.version,
        'publicMappings': reference.mappings.length,
        'center': {
          'latitude': map.center!.latitude,
          'longitude': map.center!.longitude,
        },
        'radiusMeters': map.snapshot!.result.radius,
        'searchHpidsInDistanceOrder': order,
        'scenarios': [],
      };
      Future<void> on() async {
        await container.read(reviewPreviewProvider.notifier).enable();
        await tester.pump();
        await waitFor(
          () =>
              container.read(reviewPreviewProvider).results.length ==
              order.length,
        );
        expect(
          map.snapshot!.result.hospitals.map((h) => h.hpid).toList(),
          order,
        );
        expect(container.read(mapPersonalizationProvider).results, isEmpty);
      }

      Future<void> select(List<String> names) async {
        final snapshot = await container
            .read(mapSelectionRepositoryProvider)
            .read();
        await container
            .read(mapSelectionRepositoryProvider)
            .save(
              snapshot.version,
              snapshot.consentEpoch,
              names
                  .map(
                    (n) =>
                        reference.diseases.singleWhere((d) => d.name == n).id,
                  )
                  .toList(),
              reference,
            );
        await tester.pumpAndSettle();
      }

      void record(List<String> names) {
        final state = container.read(reviewPreviewProvider);
        (report['scenarios'] as List).add({
          'diseases': names,
          ...personalizationQaSummary(
            searchHpids: order,
            selectedDiseaseIds: reference.diseases
                .where((d) => names.contains(d.name))
                .map((d) => d.id)
                .toSet(),
            results: state.results.values,
          ),
          'paintedDots': find
              .byWidgetPredicate(
                (w) =>
                    w.key is ValueKey<String> &&
                    (w.key as ValueKey<String>).value.startsWith(
                      'personalization-dot:',
                    ),
              )
              .evaluate()
              .length,
        });
      }

      var i = 3;
      for (final entry in scenarios.entries) {
        if (entry.key != '천식') await select([entry.key]);
        await on();
        record([entry.key]);
        await capture('${i++}-${entry.value}-light');
      }
      await select(['천식', '건선']);
      await on();
      record(['천식', '건선']);
      await capture('10-multiple-light');
      container.read(themeModeProvider.notifier).state = ThemeMode.dark;
      await tester.pumpAndSettle();
      await capture('10-multiple-dark');
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      await tester.pumpAndSettle();
      await capture('10-multiple-dark-large');
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue();
      container.read(themeModeProvider.notifier).state = ThemeMode.light;
      await tester.pumpAndSettle();
      final state = container.read(reviewPreviewProvider);
      final both = state.results.values
          .where((r) => r.matchedDiseases.length == 2)
          .toList();
      expect(both, isNotEmpty);
      // Open a real current-search hospital's card reason with both paired relations.
      final target = both.first.hospital.hpid;
      final scroll = find
          .descendant(
            of: find.byType(DraggableScrollableSheet),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('hospital:$target')),
        200,
        scrollable: scroll,
      );
      final badge = find.descendant(
        of: find.byKey(ValueKey('hospital:$target')),
        matching: find.text('내 질환 관련 진료과 · 검수 중 · 관련 진료과 2개'),
      );
      await tester.ensureVisible(badge);
      await tester.pumpAndSettle();
      await tester.tap(badge);
      await tester.pumpAndSettle();
      expect(find.byType(PersonalizationReasonSheet), findsOneWidget);
      expect(find.text('등록한 질환: 천식'), findsOneWidget);
      expect(find.text('등록한 질환: 건선'), findsOneWidget);
      expect(find.textContaining('REVIEW_REQUIRED'), findsNothing);
      expect(find.text('검수 상태: 개발 검수 중'), findsNWidgets(2));
      await capture('11-reason-light');
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      await tester.pumpAndSettle();
      await capture('11-reason-light-large');
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.pumpAndSettle();
      container.read(themeModeProvider.notifier).state = ThemeMode.dark;
      await tester.pumpAndSettle();
      await capture('12-reason-dark');
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      await tester.pumpAndSettle();
      await capture('12-reason-dark-large');
      expect(find.textContaining('reviewClass:'), findsNothing);
      await capture('13-reason-developer-dark-large');
      await tester.ensureVisible(find.text('닫기'));
      await tester.pumpAndSettle();
      expect(find.text('닫기').hitTestable(), findsOneWidget);
      await capture('14-reason-close-dark-large');
      await tester.tap(find.text('닫기'));
      await tester.pumpAndSettle();
      expect(find.byType(PersonalizationReasonSheet), findsNothing);
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.pumpAndSettle();
      await tester.ensureVisible(badge);
      await tester.tap(badge);
      await tester.pumpAndSettle();
      expect(find.textContaining('REVIEW_REQUIRED'), findsNothing);
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.pumpAndSettle();
      // A lifecycle boundary must redact the open sheet as well as all overlays.
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(container.read(reviewPreviewProvider).enabled, isFalse);
      expect(find.text('등록한 질환: 천식'), findsNothing);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      Navigator.pop(tester.element(find.byType(PersonalizationReasonSheet)));
      await tester.pumpAndSettle();
      container.read(themeModeProvider.notifier).state = ThemeMode.light;
      await waitFor(() => !map.loading);
      await on();
      final signingOut = container
          .read(sessionControllerProvider.notifier)
          .signOut();
      await tester.pump();
      expect(container.read(reviewPreviewProvider).enabled, isFalse);
      expect(container.read(reviewPreviewProvider).results, isEmpty);
      await signingOut;
      final other = await auth.passwordLogin(
        '010${Random.secure().nextInt(100000000).toString().padLeft(8, '0')}',
        'QA ${authNonce()} isolated-other',
        signup: true,
        termsAccepted: true,
        age14OrOlder: true,
      );
      await container.read(sessionControllerProvider.notifier).accept(other);
      await tester.pump();
      expect(container.read(reviewPreviewProvider).results, isEmpty);
      await container.read(sessionControllerProvider.notifier).signOut();
      final restored = await auth.passwordLogin(phone, password);
      await container.read(sessionControllerProvider.notifier).accept(restored);
      await tester.pump();
      await on();
      final currentConsent = (await auth.request(
        'GET',
        '/api/v1/me/health-consent',
      )).data;
      await container
          .read(memberUiRepositoryProvider)
          .withdrawConsent(currentConsent['epoch'], authNonce());
      await tester.pump();
      expect(container.read(reviewPreviewProvider).enabled, isFalse);
      expect(container.read(reviewPreviewProvider).results, isEmpty);
      // Restore only this isolated QA account's tags/consent for direct user inspection.
      final revoked = (await auth.request(
        'GET',
        '/api/v1/me/health-consent',
      )).data;
      final renewed = (await auth.request(
        'POST',
        '/api/v1/me/health-consent',
        data: {'epoch': revoked['epoch'], 'documentVersion': 'health-v1'},
      )).data;
      final empty = (await auth.request(
        'GET',
        '/api/v1/me/health-snapshot',
      )).data;
      await container
          .read(conditionsRepositoryProvider)
          .save(
            empty['version'],
            renewed['epoch'],
            'RECORDED',
            '',
            scenarios.keys
                .map(
                  (n) => reference.diseases.singleWhere((d) => d.name == n).id,
                )
                .toList(),
            reference.catalogVersion,
          );
      await select(['천식', '건선']);
      report['regions'] = [];
      for (final region in {
        'busan': const GeoPoint(35.1796, 129.0756),
        'yeongwol': const GeoPoint(37.1836, 128.4618),
      }.entries) {
        container.read(reviewPreviewProvider.notifier).disable();
        map.moveCamera(region.value);
        await map.searchHere();
        await tester.pumpAndSettle();
        order = map.snapshot!.result.hospitals.map((h) => h.hpid).toList();
        await on();
        await capture('region-${region.key}');
        if (region.key == 'yeongwol') {
          map.select(order.single);
          await tester.pumpAndSettle();
          await capture('region-yeongwol-selected');
          container.read(themeModeProvider.notifier).state = ThemeMode.dark;
          await tester.pumpAndSettle();
          await capture('region-yeongwol-selected-dark');
          container.read(themeModeProvider.notifier).state = ThemeMode.light;
          await tester.pumpAndSettle();
          await tester.pumpAndSettle();
        }
        final regional = container.read(reviewPreviewProvider);
        (report['regions'] as List).add({
          'name': region.key,
          'center': region.value.toJson(),
          'radiusMeters': map.snapshot!.result.radius,
          ...personalizationQaSummary(
            searchHpids: order,
            selectedDiseaseIds: {'D001', 'D045'},
            results: regional.results.values,
          ),
          'paintedDots': find
              .byWidgetPredicate(
                (w) =>
                    w.key is ValueKey<String> &&
                    (w.key as ValueKey<String>).value.startsWith(
                      'personalization-dot:',
                    ),
              )
              .evaluate()
              .length,
        });
      }
      container.read(reviewPreviewProvider.notifier).disable();
      report['privacy'] = {
        'backgroundClearsOpenReason': true,
        'logoutClears': true,
        'accountSwitchClears': true,
        'consentWithdrawalClears': true,
        'offDefault': true,
        'noReorder': true,
        'publicGoldResults': 0,
      };
      final file = File(
        '${Directory.systemTemp.path}/eroute-review-results.json',
      );
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
      );
      debugPrint('QA_ARTIFACT ${file.path}');
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      auth.dio.close();
      expect(tester.takeException(), isNull);
    },
  );
}
