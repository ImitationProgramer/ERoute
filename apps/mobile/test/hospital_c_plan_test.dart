import 'support/category_visual_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:eroute_mobile/core/theme/eroute_theme.dart';
import 'package:eroute_mobile/core/map/map_camera_controller.dart';
import 'package:eroute_mobile/features/disease_personalization/personalization_presentation.dart';
import 'package:eroute_mobile/features/disease_personalization/personalization_overlay.dart';
import 'package:eroute_mobile/features/disease_personalization/personalization_badge.dart';
import 'package:eroute_mobile/features/hospital_detail/presentation/hospital_clinical_information.dart';
import 'package:eroute_mobile/features/emergency_map/presentation/widgets/realtime_summary.dart';
import 'support/hospital_personalization_flow_fixture.dart';
import 'support/disease_fixtures.dart';
import 'support/synthetic_personalization.dart';
import 'hospital_clinical_information_test.dart' show clinicalJson, data, state;
import 'emergency_map_test.dart' show hospital;
import 'main_flow_test.dart' show captureQa;

void main() {
  final reference = FlowData();
  final match = reference.preview.match(
    reference.referenceValue,
    confirmedSelection(reference.referenceValue, ['D001']),
    syntheticDepartmentSnapshot(names: ['내과']),
    DateTime.now(),
  )!;
  setUpAll(() async {
    await (FontLoader(
      'NotoSansKR',
    )..addFont(rootBundle.load('assets/fonts/NotoSansKR.ttf'))).load();
  });
  test('BROAD D001 keeps its hospital match but cannot receive a C ring', () {
    expect(match.matched, isTrue);
    expect(personalizationRingEligible(match, previewAllowed: true), isFalse);
    expect(personalizationRingEligible(match, previewAllowed: false), isFalse);
    final unmatched = reference.preview.match(
      reference.referenceValue,
      confirmedSelection(reference.referenceValue, ['D001']),
      syntheticDepartmentSnapshot(names: ['구강내과']),
      DateTime.now(),
    )!;
    expect(
      personalizationRingEligible(unmatched, previewAllowed: true),
      isFalse,
    );
  });
  test(
    'selected and unselected rings surround native circle; collisions hide only decoration',
    () {
      const points = {'a': Offset(100, 100), 'b': Offset(250, 100)};
      for (final selected in [null, 'a']) {
        final rings = layoutPersonalizationRings(
          points: points,
          eligible: {'a'},
          selectedHpid: selected,
          viewport: const Rect.fromLTWH(0, 0, 400, 400),
        );
        expect(rings.keys, ['a']);
        expect(rings['a']!.center, points['a']);
        expect(
          rings['a']!.width / 2,
          HospitalMarkerGeometry.visibleRadius(selected == 'a') + 5,
        );
      }
      expect(
        layoutPersonalizationRings(
          points: points,
          eligible: {'a'},
          selectedHpid: null,
          viewport: const Rect.fromLTWH(0, 0, 400, 400),
          obstacles: [const Rect.fromLTWH(80, 80, 50, 50)],
        ),
        isEmpty,
      );
      expect(
        layoutPersonalizationRings(
          points: points,
          eligible: {'a'},
          selectedHpid: null,
          viewport: const Rect.fromLTWH(0, 0, 400, 400),
          renderedIds: {'b'},
        ),
        isEmpty,
      );
      // A directly related marker still yields to another hospital footprint.
      expect(
        layoutPersonalizationRings(
          points: const {'a': Offset(100, 100), 'b': Offset(125, 100)},
          eligible: {'a'},
          selectedHpid: 'a',
          viewport: const Rect.fromLTWH(0, 0, 400, 400),
        ),
        isEmpty,
      );
      // Separate marker circles with colliding outer rings suppress both rings.
      expect(
        layoutPersonalizationRings(
          points: const {'a': Offset(100, 100), 'b': Offset(142, 100)},
          eligible: {'a', 'b'},
          selectedHpid: null,
          viewport: const Rect.fromLTWH(0, 0, 400, 400),
        ),
        isEmpty,
      );
    },
  );
  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'C clinical 320dp $dark ${scale}x: 51 wrapping names, today/missing, reason semantics',
        (tester) async {
          tester.view.physicalSize = const Size(320, 850);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final key = GlobalKey();
          final basic = clinicalJson();
          basic['departments'] = [
            {'name': '내과', 'source': 'NMC', 'interpretationStatus': 'KNOWN'},
            for (var i = 1; i < 51; i++)
              {
                'name': '긴 한국어 진료과목 검증용 $i',
                'source': 'NMC',
                'interpretationStatus': 'KNOWN',
              },
          ];
          await tester.pumpWidget(
            withVisualCatalog(
              MaterialApp(
                theme: dark ? ERouteTheme.dark() : ERouteTheme.light(),
                home: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: RepaintBoundary(
                    key: key,
                    child: Scaffold(
                      body: SingleChildScrollView(
                        child: HospitalClinicalInformation(
                          state: state(AsyncData(data(basic))),
                          personalization: match,
                          now: () => DateTime(2026, 9, 27),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('진료과목 51개'), findsOneWidget);
          expect(find.text('오늘 · 일요일'), findsOneWidget);
          expect(find.text('휴진'), findsNothing);
          expect(find.byType(Wrap), findsWidgets);
          await captureQa(
            tester,
            key,
            'c-detail-${dark ? 'dark' : 'light'}-${scale}x',
          );
          final button = find.widgetWithText(TextButton, '천식 · 내과');
          expect(
            tester.getSemantics(button),
            matchesSemantics(
              isButton: true,
              hasEnabledState: true,
              isEnabled: true,
              isFocusable: true,
              hasTapAction: true,
              hasFocusAction: true,
              label: '천식 · 내과',
            ),
          );
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(find.byType(PersonalizationReasonSheet), findsOneWidget);
          expect(find.text('관계 범위: 상위 진료과 후보'), findsOneWidget);
          expect(find.text('닫기').hitTestable(), findsOneWidget);
          await captureQa(
            tester,
            key,
            'c-reason-${dark ? 'dark' : 'light'}-${scale}x',
          );
          await tester.tap(find.text('닫기'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('요일별 보기'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('요일별 보기'));
          await tester.pumpAndSettle();
          expect(find.text('일요일'), findsOneWidget);
          expect(find.text('정보 미제공'), findsNWidgets(3));
          await tester.ensureVisible(find.text('오늘 · 일요일'));
          await tester.pumpAndSettle();
          await captureQa(
            tester,
            key,
            'c-hours-${dark ? 'dark' : 'light'}-${scale}x',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('compact reason tag is keyboard operable', (tester) async {
    await tester.pumpWidget(
      withVisualCatalog(
        MaterialApp(
          home: Scaffold(body: PersonalizationBadge(result: match)),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(PersonalizationReasonSheet), findsOneWidget);
    expect(find.text('닫기').hitTestable(), findsOneWidget);
  });
  testWidgets(
    'missing beds are not zero and source details preserve provider clock',
    (tester) async {
      await tester.pumpWidget(
        withVisualCatalog(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RealtimeSummary(
                  hospital: hospital(
                    coverage: 'LIVE_NOT_PROVIDED',
                    beds: '',
                    status: 'MISSING',
                  ),
                  detail: true,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('실시간 병상정보 미제공'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      await tester.tap(find.text('출처·갱신 상세 정보'));
      await tester.pumpAndSettle();
      expect(find.textContaining('HVS01 (일반_기준)'), findsOneWidget);
    },
  );
}
