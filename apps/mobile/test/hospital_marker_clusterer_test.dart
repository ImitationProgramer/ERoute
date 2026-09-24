import 'dart:ui' show SemanticsAction, SemanticsActionEvent;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eroute_mobile/core/map/hospital_marker_clusterer.dart';
import 'package:eroute_mobile/core/map/hospital_cluster_marker.dart';
import 'package:eroute_mobile/core/theme/eroute_theme.dart';
import 'main_flow_test.dart' show captureQa;

void main() {
  const clusterer = HospitalMarkerClusterer();
  const nearby = {
    'A': Offset(100, 100),
    'B': Offset(120, 100),
    'C': Offset(140, 110),
  };
  const distant = {
    'A': Offset(100, 100),
    'B': Offset(300, 100),
    'C': Offset(500, 100),
  };
  test(
    'nearby groups 3; zoom-in screen projection splits; no private inputs',
    () {
      final grouped = clusterer.group(nearby);
      expect(grouped.clusters.single.count, 3);
      expect(grouped.individualIds, isEmpty);
      expect(grouped.hospitalCount, 3);
      final split = clusterer.group(distant);
      expect(split.clusters, isEmpty);
      expect(split.individualIds, {'A', 'B', 'C'});
    },
  );
  test('selected is always individual and excluded from counts', () {
    final plan = clusterer.group(nearby, selectedHpid: 'B');
    expect(plan.individualIds, {'B'});
    expect(plan.clusters.single.hospitalIds, ['A', 'C']);
    expect(plan.hospitalCount, 3);
    expect(clusterer.group(nearby, selectedHpid: 'missing').hospitalCount, 3);
  });
  test(
    'deterministic, exact boundary, offscreen, coincident, replacement/empty',
    () {
      expect(
        clusterer
            .group(Map.fromEntries(nearby.entries.toList().reversed))
            .clusters
            .single
            .id,
        clusterer.group(nearby).clusters.single.id,
      );
      expect(
        clusterer
            .group({'A': Offset.zero, 'B': const Offset(60, 0)})
            .clusters
            .single
            .count,
        2,
      );
      expect(
        clusterer
            .group({'A': Offset.zero, 'B': const Offset(60.01, 0)})
            .individualIds
            .length,
        2,
      );
      expect(
        clusterer
            .group({
              'A': const Offset(-1000, -1000),
              'B': const Offset(-1000, -1000),
            })
            .clusters
            .single
            .count,
        2,
      );
      expect(clusterer.group({'NEW': const Offset(1, 1)}).individualIds, {
        'NEW',
      });
      expect(clusterer.group({}).hospitalCount, 0);
      expect(
        clusterer.group({'bad': const Offset(double.nan, 0)}).individualIds,
        {'bad'},
      );
    },
  );
  test(
    '500 hospitals: unique membership, grid boundary grouping and performance',
    () {
      final timings = <String, Object>{};
      for (final count in [100, 500]) {
        for (final spacing in [4.0, 80.0]) {
          final points = {
            for (var i = 0; i < count; i++)
              '$i': Offset((i % 25) * spacing, (i ~/ 25) * spacing),
          };
          final sw = Stopwatch()..start();
          late HospitalClusterPlan plan;
          for (var i = 0; i < 100; i++) {
            plan = clusterer.group(points, selectedHpid: '0');
          }
          sw.stop();
          final ids = [
            ...plan.individualIds,
            for (final c in plan.clusters) ...c.hospitalIds,
          ];
          expect(ids.length, count);
          expect(ids.toSet(), points.keys.toSet());
          expect(plan.individualIds, contains('0'));
          expect(plan.hospitalCount, count);
          if (spacing == 80) expect(plan.clusters, isEmpty);
          timings['$count/$spacing'] = {
            'averageMicroseconds': sw.elapsedMicroseconds / 100,
            'clusters': plan.clusters.length,
            'individual': plan.individualIds.length,
          };
        }
      }
      File('build/qa/cluster-performance.json')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(jsonEncode(timings));
    },
  );
  testWidgets(
    'occluded cluster retains accessible tap without stealing touch',
    (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: HospitalClusterTarget(
              count: 12,
              pointerEnabled: false,
              onTap: () => tapped++,
            ),
          ),
        ),
      );
      final target = find.byType(HospitalClusterTarget);
      final node = tester.getSemantics(target);
      expect(node.getSemanticsData().label, '병원 12개 묶음');
      tester.binding.performSemanticsAction(
        SemanticsActionEvent(
          type: SemanticsAction.tap,
          nodeId: node.id,
          viewId: tester.view.viewId,
        ),
      );
      expect(tapped, 1);
      await tester.tap(target, warnIfMissed: false);
      expect(tapped, 1);
    },
  );
  setUpAll(() async {
    await (FontLoader(
      'NotoSansKR',
    )..addFont(rootBundle.load('assets/fonts/NotoSansKR.ttf'))).load();
  });
  for (final dark in [false, true]) {
    testWidgets(
      'count visuals 9/12/105/500 and semantics at 320dp/200% dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(320, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var tapped = 0;
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? ERouteTheme.dark() : ERouteTheme.light(),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: RepaintBoundary(
                key: key,
                child: Scaffold(
                  body: Column(
                    children: [
                      const SizedBox(height: 24),
                      const Text('SYNTHETIC', textScaler: TextScaler.noScaling),
                      for (final count in [9, 12, 105, 500])
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: CustomPaint(
                            painter: HospitalClusterPainter(count, dark: dark),
                            child: HospitalClusterTarget(
                              count: count,
                              onTap: () => tapped++,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        final target = find.byType(HospitalClusterTarget).at(2);
        expect(tester.getSize(target), HospitalClusterGeometry.size(105));
        final semantics = tester.getSemantics(target).getSemanticsData();
        expect(semantics.label, '병원 105개 묶음');
        expect(semantics.hint, '확대해서 병원 보기');
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(tapped, 1);
        await captureQa(
          tester,
          key,
          'cluster-counts-${dark ? 'dark' : 'light'}',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
