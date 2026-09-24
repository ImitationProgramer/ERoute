// Synthetic hospitals and immutable v0.5 relation fixtures. Separate preview APK;
// never reads or changes the signed-in development user's profile.
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:eroute_mobile/core/map/naver_emergency_map_view.dart';
import 'package:eroute_mobile/core/map/map_camera_controller.dart';
import 'package:eroute_mobile/core/map/map_scene.dart';
import 'package:eroute_mobile/core/map/hospital_cluster_marker.dart';
import 'package:eroute_mobile/core/theme/eroute_theme.dart';
import 'package:eroute_mobile/features/emergency_map/domain/hospital_summary.dart';
import 'package:eroute_mobile/features/disease_personalization/disease_reference.dart';
import 'package:eroute_mobile/features/disease_personalization/personalization_overlay.dart';
import 'package:eroute_mobile/features/disease_personalization/personalization_presentation.dart';
import '../test/support/hospital_personalization_flow_fixture.dart';
import '../test/support/disease_fixtures.dart';
import '../test/support/synthetic_personalization.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native grouping, count, tap fit, selected exclusion, EXACT/BROAD and stale replacement',
    (tester) async {
      await initializeNaverMap();
      final data = FlowData();
      final exact = data.preview.mappings.firstWhere(
        (m) => m.mappingScope == MappingScope.exactCanonical,
      );
      final exactResult = data.preview.match(
        data.referenceValue,
        confirmedSelection(data.referenceValue, [exact.diseaseId]),
        syntheticDepartmentSnapshot(
          names: [data.referenceValue.departments[exact.departmentId]!],
        ),
        DateTime.now(),
      )!;
      final broadResult = data.preview.match(
        data.referenceValue,
        confirmedSelection(data.referenceValue, ['D001']),
        syntheticDepartmentSnapshot(names: ['내과']),
        DateTime.now(),
      )!;
      expect(
        personalizationRingEligible(broadResult, previewAllowed: true),
        false,
      );
      expect(
        personalizationRingEligible(exactResult, previewAllowed: true),
        true,
      );
      final rows = [
        for (var i = 0; i < 3; i++)
          HospitalSummary(
            hpid: 'SYNTH_$i',
            name: 'SYNTHETIC $i',
            classification: 'TEST',
            location: GeoPoint(37.5665, 126.978 + (i - 1) * .002),
            centerDistance: 100,
            userDistance: null,
            coverage: 'LIVE_NOT_PROVIDED',
            refresh: 'UNCHANGED',
            beds: ResourceValue('MISSING', null, null),
            reference: ResourceValue('MISSING', null, null),
            stale: false,
            rawSourceTime: null,
            fetchedAt: null,
            error: null,
          ),
      ];
      var revision = 1;
      String? selected;
      var dark = false;
      var showPersonal = true;
      var currentRows = rows;
      SearchPresentationSnapshot search() => SearchPresentationSnapshot(
        center: const GeoPoint(37.5665, 126.978),
        source: 'SYNTHETIC',
        revision: revision,
        result: HospitalSearchResult(
          currentRows,
          10000,
          false,
          false,
          [],
          totalCount: currentRows.length,
        ),
      );
      MapCameraController? camera;
      late StateSetter update;
      var selectionCalls = 0;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return MaterialApp(
              theme: dark ? ERouteTheme.dark() : ERouteTheme.light(),
              home: Scaffold(
                body: Stack(
                  children: [
                    NaverEmergencyMapView(
                      scene: MapScene(search: search(), selectedHpid: selected),
                      onReady: (c) {
                        camera = c;
                        setState(() {});
                      },
                      onCameraIdle: (_) {},
                      onHospitalSelected: (id) {
                        selectionCalls++;
                        setState(() => selected = id);
                      },
                    ),
                    Positioned.fill(
                      child: PersonalizationOverlay(
                        controller: camera,
                        search: search(),
                        accents: const {},
                        selectedHpid: selected,
                        insets: const EdgeInsets.only(top: 80),
                        ringIds: {
                          if (showPersonal &&
                              personalizationRingEligible(
                                exactResult,
                                previewAllowed: true,
                              ))
                            'SYNTH_0',
                          if (showPersonal &&
                              personalizationRingEligible(
                                broadResult,
                                previewAllowed: true,
                              ))
                            'SYNTH_1',
                        },
                      ),
                    ),
                    const Positioned(
                      top: 30,
                      left: 16,
                      child: Text('SYNTHETIC · EXACT/BROAD cluster QA'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
      Future<void> settle(bool Function() ready) async {
        for (var i = 0; i < 250; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (ready()) {
            await tester.pump(const Duration(milliseconds: 500));
            return;
          }
        }
        fail('Native state did not settle');
      }

      await settle(() => camera != null);
      final dynamic native = tester.state(find.byType(NaverEmergencyMapView));
      await camera!.updateViewport(
        const EdgeInsets.only(top: 80),
        settled: true,
      );
      await settle(
        () =>
            native.debugClusterPlan.clusters.length == 1 &&
            native.renderedHospitalIds.value != null,
      );
      expect(native.debugClusterPlan.clusters.single.count, 3);
      expect(native.debugHospitalMarkers, isEmpty);
      expect(
        find.byKey(const ValueKey('personalization-ring:SYNTH_0')),
        findsNothing,
      );
      await settle(
        () => find.byType(HospitalClusterTarget).evaluate().length == 1,
      );
      await tester.tap(find.byType(HospitalClusterTarget));
      await settle(
        () =>
            native.debugHospitalMarkers.length == 3 &&
            native.renderedHospitalIds.value?.length == 3,
      );
      expect(selectionCalls, 0);
      expect(selected, isNull);
      expect(native.debugClusterMarkers, isEmpty);
      await settle(
        () => find
            .byKey(const ValueKey('personalization-ring:SYNTH_0'))
            .evaluate()
            .isNotEmpty,
      );
      expect(
        find.byKey(const ValueKey('personalization-ring:SYNTH_1')),
        findsNothing,
      );
      await binding.convertFlutterSurfaceToImage();
      Future<void> capture(String name) async {
        for (var i = 0; i < 15; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final bytes = await binding.takeScreenshot(name);
        await File(
          '${Directory.systemTemp.path}/$name.png',
        ).writeAsBytes(bytes);
      }

      await capture('exact-ring-fixture');
      update(() => selected = 'SYNTH_0');
      await settle(
        () => native.debugHospitalMarkers['SYNTH_0']?.size.width == 48,
      );
      await settle(
        () => find
            .byKey(const ValueKey('personalization-ring:SYNTH_0'))
            .evaluate()
            .isNotEmpty,
      );
      await capture('selected-exact-fixture');
      update(() => selected = 'SYNTH_1');
      await camera!.zoomBy(-5);
      await settle(
        () =>
            native.debugClusterPlan.clusters.length == 1 &&
            native.debugClusterPlan.clusters.single.count == 2,
      );
      expect(native.debugHospitalMarkers.keys.toList(), ['SYNTH_1']);
      expect(native.debugHospitalMarkers['SYNTH_1'].size.width, 48);
      expect(native.debugHospitalMarkers['SYNTH_1'].zIndex, 10);
      expect(native.debugClusterPlan.hospitalCount, 3);
      expect(
        find.byKey(const ValueKey('personalization-ring:SYNTH_1')),
        findsNothing,
      );
      update(() => showPersonal = false);
      expect(native.debugClusterPlan.hospitalCount, 3);
      update(() => dark = true);
      await tester.pump(const Duration(seconds: 2));
      await capture('native-dark-fixture');
      final oldClusterIds = (native.debugClusterMarkers as Map).keys.toSet();
      update(() {
        currentRows = [rows.last];
        revision++;
        selected = null;
      });
      await settle(
        () =>
            native.debugClusterPlan.hospitalCount == 1 &&
            native.debugClusterMarkers.isEmpty,
      );
      expect(native.debugHospitalMarkers.keys.toList(), ['SYNTH_2']);
      expect(
        (native.debugClusterMarkers as Map).keys.toSet().intersection(
          oldClusterIds,
        ),
        isEmpty,
      );
      // Late camera callbacks / rapid result replacement cannot restore old groups.
      update(() {
        currentRows = [];
        revision++;
      });
      await camera!.zoomBy(1);
      await settle(
        () =>
            native.debugClusterPlan.hospitalCount == 0 &&
            native.debugHospitalMarkers.isEmpty,
      );
      await File(
        '${Directory.systemTemp.path}/clustering-native-result.json',
      ).writeAsString(
        jsonEncode({
          'nearbyCount': 3,
          'tapSplitIndividuals': 3,
          'tapSelectionCalls': selectionCalls,
          'selectedExcludedCount': 2,
          'exactIndividualRing': true,
          'broadRing': false,
          'clusterRing': false,
          'replacementAndEmpty': 'PASS',
          'native': 'PASS',
        }),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
