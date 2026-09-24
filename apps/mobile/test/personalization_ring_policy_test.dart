// Immutable v0.5 relations + synthetic hospitals. No member/data writes.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eroute_mobile/core/map/map_camera_controller.dart';
import 'package:eroute_mobile/core/theme/eroute_theme.dart';
import 'package:eroute_mobile/features/disease_personalization/department_matcher.dart';
import 'package:eroute_mobile/features/disease_personalization/disease_reference.dart';
import 'package:eroute_mobile/features/disease_personalization/personalization_badge.dart';
import 'package:eroute_mobile/features/disease_personalization/personalization_overlay.dart';
import 'package:eroute_mobile/features/disease_personalization/personalization_presentation.dart';
import 'main_flow_test.dart' show captureQa;
import 'personalization_overlay_test.dart'
    show ProjectionFixture, syntheticSearch;
import 'support/category_visual_fixture.dart';
import 'support/disease_fixtures.dart';
import 'support/hospital_personalization_flow_fixture.dart';
import 'support/synthetic_personalization.dart';

void main() {
  final data = FlowData();
  final exact = data.preview.mappings.firstWhere(
    (m) => m.mappingScope == MappingScope.exactCanonical,
  );
  final department = data.referenceValue.departments[exact.departmentId]!;
  HospitalDiseaseMatchResult match(
    List<String> ids,
    List<String> departments,
  ) => data.preview.match(
    data.referenceValue,
    confirmedSelection(data.referenceValue, ids),
    syntheticDepartmentSnapshot(names: departments),
    DateTime.now(),
  )!;
  final broad = match(['D001'], ['내과']);
  final direct = match([exact.diseaseId], [department]);
  final mixed = match(['D001', exact.diseaseId], ['내과', department]);
  final noMatch = match(['D001'], ['구강내과']);
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader(
      'NotoSansKR',
    )..addFont(rootBundle.load('assets/fonts/NotoSansKR.ttf'))).load();
  });
  test('A-D: broad, immutable exact, mixed, no match', () {
    expect(broad.matched, isTrue);
    expect(broad.matches.single.mappingScope, MappingScope.broadParent);
    expect(broad.matches.single.reviewClass, 'BROAD_PARENT_REVIEW_REQUIRED');
    expect(personalizationRingEligible(broad, previewAllowed: true), isFalse);
    expect(direct.matched, isTrue);
    expect(personalizationRingEligible(direct, previewAllowed: true), isTrue);
    expect(mixed.matchedDiseases, {'D001', exact.diseaseId});
    expect(personalizationRingEligible(mixed, previewAllowed: true), isTrue);
    expect(noMatch.status, DepartmentMatchStatus.noMatch);
    expect(personalizationRingEligible(noMatch, previewAllowed: true), isFalse);
    expect(personalizationRingEligible(direct, previewAllowed: false), isFalse);
    final unmatchedExact = match(['D001', exact.diseaseId], ['내과']);
    expect(unmatchedExact.matched, isTrue);
    expect(
      personalizationRingEligible(unmatchedExact, previewAllowed: true),
      isFalse,
    );
  });
  test('scope is fail-closed and never inferred from reviewClass', () {
    expect(() => decodeMappingScope('UNKNOWN'), throwsFormatException);
    for (final preview in [false, true]) {
      for (final rawScope in [null, 'BROAD_PARENT', 'EXACT_CANONICAL']) {
        for (final reviewClass in [
          null,
          'EXACT_CANONICAL_REVIEW_REQUIRED',
          'BROAD_PARENT_REVIEW_REQUIRED',
          'REVIEW_REQUIRED',
        ]) {
          final reason = DepartmentMatchReason(
            diseaseId: 'fixture',
            diseaseName: 'fixture',
            mappingId: 'fixture',
            canonicalDepartmentId: 'fixture',
            canonicalDepartmentName: 'fixture',
            hospitalDepartmentName: 'fixture',
            hospitalDepartmentRaw: 'fixture',
            hospitalSource: 'TEST',
            mappingScope: decodeMappingScope(rawScope),
            reviewClass: reviewClass,
            reviewStatus: preview ? 'DRAFT' : 'APPROVED',
          );
          final result = HospitalDiseaseMatchResult(
            syntheticDepartmentSnapshot(),
            'test',
            [
              DiseaseMatch('fixture', DepartmentMatchStatus.match, [
                reason,
              ], []),
            ],
            reviewPreview: preview,
          );
          expect(
            personalizationRingEligible(result, previewAllowed: true),
            rawScope == 'EXACT_CANONICAL',
          );
        }
      }
    }
  });
  for (final scenario in [
    ('broad-fixture', broad, false, false),
    ('exact-ring', direct, false, true),
    ('mixed-ring', mixed, false, true),
    ('no-match', noMatch, false, false),
    ('selected-broad-fixture', broad, true, false),
    ('selected-exact', direct, true, true),
  ]) {
    testWidgets('${scenario.$1}: overlay and independent selected geometry', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final camera = ProjectionFixture();
      addTearDown(camera.dispose);
      final key = GlobalKey(), selected = scenario.$3;
      final diameter = HospitalMarkerGeometry.visibleRadius(selected) * 2;
      await tester.pumpWidget(
        withVisualCatalog(
          MaterialApp(
            theme: ERouteTheme.light(),
            home: RepaintBoundary(
              key: key,
              child: Scaffold(
                body: Stack(
                  children: [
                    const Positioned(
                      top: 28,
                      left: 20,
                      child: Text('SYNTHETIC FIXTURE · v0.5 relation'),
                    ),
                    Positioned(top: 64, left: 20, child: Text(scenario.$1)),
                    // Test-only stand-in. Native selected fill is separately checked on Android.
                    Positioned(
                      left: camera.point.dx - diameter / 2,
                      top: camera.point.dy - diameter / 2,
                      child: Container(
                        key: const ValueKey('fixture-marker'),
                        width: diameter,
                        height: diameter,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected
                              ? const Color(0xff244e86)
                              : const Color(0xffc93645),
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                        child: const Icon(
                          Icons.add,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                    PersonalizationOverlay(
                      controller: camera,
                      search: syntheticSearch(),
                      accents: const {},
                      selectedHpid: selected ? 'TEST_ONLY' : null,
                      ringIds: {
                        if (personalizationRingEligible(
                          scenario.$2,
                          previewAllowed: true,
                        ))
                          'TEST_ONLY',
                      },
                      insets: EdgeInsets.zero,
                    ),
                    Positioned(
                      top: 330,
                      left: 20,
                      right: 20,
                      child: PersonalizationBadge(result: scenario.$2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final ring = find.byKey(const ValueKey('personalization-ring:TEST_ONLY'));
      expect(ring, scenario.$4 ? findsOneWidget : findsNothing);
      final marker = tester.widget<Container>(
        find.byKey(const ValueKey('fixture-marker')),
      );
      expect(
        (marker.decoration! as BoxDecoration).color,
        selected ? const Color(0xff244e86) : const Color(0xffc93645),
      );
      if (scenario.$4) {
        expect(tester.getSize(ring).width, diameter + 10);
        camera.cameraMoving.value = true;
        await tester.pump();
        expect(ring, findsNothing);
        camera.cameraMoving.value = false;
        camera.projectionRevision.value++;
        await tester.pumpAndSettle();
        expect(ring, findsOneWidget);
        camera.overlayExclusionRects.value = [
          const Rect.fromLTWH(150, 180, 80, 80),
        ];
        await tester.pump();
        expect(ring, findsNothing);
        camera.overlayExclusionRects.value = [];
        await tester.pumpAndSettle();
      }
      await captureQa(tester, key, scenario.$1);
      if (scenario.$2.matched) {
        await tester.tap(find.byType(TextButton));
        await tester.pumpAndSettle();
        expect(find.byType(PersonalizationReasonSheet), findsOneWidget);
        for (final r in scenario.$2.matches) {
          expect(
            find.text('등록한 질환: ${r.diseaseName}'),
            findsNWidgets(
              scenario.$2.matches
                  .where((m) => m.diseaseName == r.diseaseName)
                  .length,
            ),
          );
          expect(
            find.text('관련 후보 진료과: ${r.canonicalDepartmentName}'),
            findsNWidgets(
              scenario.$2.matches
                  .where(
                    (m) =>
                        m.canonicalDepartmentName == r.canonicalDepartmentName,
                  )
                  .length,
            ),
          );
        }
      } else {
        expect(find.byType(TextButton), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
