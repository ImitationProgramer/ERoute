import 'support/category_visual_fixture.dart';
import 'dart:async';
import 'package:eroute_mobile/features/disease_personalization/personalization_presentation.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eroute_mobile/core/map/map_camera_controller.dart';
import 'package:eroute_mobile/core/map/map_scene.dart';
import 'package:eroute_mobile/core/theme/eroute_theme.dart';
import 'package:eroute_mobile/features/emergency_map/domain/hospital_summary.dart';
import 'package:eroute_mobile/features/disease_personalization/personalization_overlay.dart';
import 'package:eroute_mobile/features/disease_personalization/personalization_badge.dart';
import 'package:eroute_mobile/features/disease_personalization/department_matcher.dart';
import 'support/synthetic_personalization.dart';
import 'support/disease_fixtures.dart';
import 'emergency_map_test.dart' show hospital;

class ProjectionFixture
    implements MapCameraController, MapProjectionEvents, MapOverlayGeometry {
  @override
  final ValueNotifier<List<Rect>?> overlayExclusionRects = ValueNotifier(
    const [],
  );
  @override
  final ValueNotifier<Set<String>?> renderedHospitalIds = ValueNotifier(const {
    'TEST_ONLY',
  });
  @override
  final ValueNotifier<int> projectionRevision = ValueNotifier<int>(0);
  @override
  final ValueNotifier<bool> cameraMoving = ValueNotifier<bool>(false);
  Offset point = const Offset(190, 220);
  Completer<Offset>? pending;
  int projections = 0;
  @override
  Future<Offset> project(GeoPoint p) async {
    projections++;
    return pending == null ? point : pending!.future;
  }

  @override
  Future<void> fit(SearchPresentationSnapshot s) async {}
  @override
  Future<void> moveToCurrentLocation(GeoPoint p) async {}
  @override
  Future<void> zoomBy(double d) async {}
  @override
  Future<void> updateViewport(EdgeInsets e, {required bool settled}) async {}
  void dispose() {
    overlayExclusionRects.dispose();
    renderedHospitalIds.dispose();
    projectionRevision.dispose();
    cameraMoving.dispose();
  }
}

SearchPresentationSnapshot syntheticSearch([int revision = 1]) =>
    SearchPresentationSnapshot(
      center: const GeoPoint(37, 127),
      source: 'SYNTHETIC',
      result: HospitalSearchResult(
        [hospital()],
        10000,
        false,
        false,
        [],
        totalCount: 1,
      ),
      revision: revision,
    );

void main() {
  testWidgets(
    'small gold dot: selected anchor, camera movement, edge clipping, OFF and late projection',
    (tester) async {
      final camera = ProjectionFixture();
      addTearDown(camera.dispose);
      Future<void> show({
        Set<String> ids = const {'TEST_ONLY'},
        String? selected,
        int revision = 1,
      }) async {
        await tester.pumpWidget(
          withVisualCatalog(
            MaterialApp(
              home: PersonalizationOverlay(
                controller: camera,
                search: syntheticSearch(revision),
                accents: {
                  for (final id in ids) id: PersonalizationAccent.filled,
                },
                selectedHpid: selected,
                insets: const EdgeInsets.only(top: 100, bottom: 100),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      final ring = find.byKey(const ValueKey('personalization-dot:TEST_ONLY'));
      await show();
      expect(ring, findsOneWidget);
      camera.renderedHospitalIds.value = null;
      await tester.pump();
      expect(ring, findsNothing);
      camera.renderedHospitalIds.value = {};
      await tester.pump();
      expect(ring, findsNothing);
      camera.renderedHospitalIds.value = {'TEST_ONLY'};
      await tester.pump();
      expect(ring, findsOneWidget);
      expect(tester.getSize(ring).width, 8);
      await show(selected: 'TEST_ONLY');
      expect(tester.getSize(ring).width, 8);
      camera.cameraMoving.value = true;
      await tester.pump();
      expect(ring, findsNothing);
      camera.point = const Offset(230, 250);
      camera.cameraMoving.value = false;
      camera.projectionRevision.value++;
      await tester.pumpAndSettle();
      expect(ring, findsOneWidget);
      expect(
        (tester.getCenter(ring) -
                camera.point -
                const Offset(16.2635, -16.2635))
            .distance,
        lessThan(.001),
      );
      camera.point = const Offset(5, 5);
      camera.projectionRevision.value++;
      await tester.pumpAndSettle();
      expect(ring, findsNothing);
      camera.point = const Offset(190, 220);
      await show(ids: {}, revision: 2);
      expect(ring, findsNothing);
      expect(camera.projections, greaterThan(2));
      camera.pending = Completer();
      await show(revision: 3);
      await tester.pumpWidget(const SizedBox());
      camera.pending!.complete(const Offset(190, 220));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('synthetic badge discloses reasons at 200% text in both themes', (
    tester,
  ) async {
    final font = FontLoader('NotoSansKR')
      ..addFont(rootBundle.load('assets/fonts/NotoSansKR.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final r = syntheticReference();
    final result = matchDepartments(
      reference: r,
      selection: confirmedSelection(r, ['TEST_DISEASE']),
      hospital: syntheticDepartmentSnapshot(),
      now: DateTime.now(),
      enabled: true,
    )!;
    for (final dark in [false, true]) {
      await tester.pumpWidget(
        withVisualCatalog(
          MaterialApp(
            theme: dark ? ERouteTheme.dark() : ERouteTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(dark ? 2 : 1)),
              child: child!,
            ),
            home: Scaffold(
              body: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text('테스트 응급의료기관 · 가상 자료'),
                    PersonalizationBadge(result: result),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextButton).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('등록한 질환: TEST_DISEASE'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).first,
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(
          'build/qa/disease-foundation/badge-${dark ? 'dark-large' : 'light'}.png',
        );
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });
}
