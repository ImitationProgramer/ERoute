import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eroute_mobile/core/map/camera_fit_geometry.dart';
import 'package:eroute_mobile/core/map/map_scene.dart';
import 'package:eroute_mobile/core/map/map_camera_controller.dart';
import 'package:eroute_mobile/core/location/heading_service.dart';
import 'package:eroute_mobile/core/location/location_fix.dart';
import 'package:eroute_mobile/features/emergency_map/domain/hospital_summary.dart';
import 'package:eroute_mobile/features/emergency_map/presentation/emergency_map_controller.dart';
import 'package:eroute_mobile/features/emergency_map/presentation/emergency_map_page.dart';
import 'package:eroute_mobile/features/app_menu/app_session.dart';
import 'package:eroute_mobile/features/app_menu/emergency_drawer.dart';
import 'package:eroute_mobile/features/emergency_call/emergency_dialer.dart';
import 'emergency_map_test.dart' as fixtures;

class RecordingCamera implements MapCameraController {
  final fits = <SearchPresentationSnapshot>[];
  final viewports = <EdgeInsets>[];
  double zoom = 0;
  @override
  Future<Offset> project(GeoPoint point) async => Offset.zero;
  @override
  Future<void> fit(SearchPresentationSnapshot snapshot) async =>
      fits.add(snapshot);
  @override
  Future<void> moveToCurrentLocation(GeoPoint point) async {}
  @override
  Future<void> zoomBy(double delta) async {
    zoom += delta;
  }

  @override
  Future<void> updateViewport(
    EdgeInsets insets, {
    required bool settled,
  }) async => viewports.add(insets);
}

class TestHeading implements HeadingService {
  final events = StreamController<HeadingReading>.broadcast();
  @override
  Stream<HeadingReading> watch() => events.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'every effective radius fits the entire search and not remote user GPS',
    () {
      for (final center in [
        const GeoPoint(33.4, 126.5),
        const GeoPoint(38.2, 128.5),
      ]) {
        for (final radius in [10000, 20000, 50000]) {
          final snapshot = SearchPresentationSnapshot(
            center: center,
            source: 'MANUAL',
            revision: 1,
            result: HospitalSearchResult([], radius, true, false, []),
          );
          final scene = MapScene(
            search: snapshot,
            user: LocationFix(const GeoPoint(0, 0), measuredAt: DateTime(2026)),
          );
          final bounds = fitBoundsFor(scene.search!);
          expect(bounds.southWest.latitude, lessThan(center.latitude));
          expect(bounds.northEast.latitude, greaterThan(center.latitude));
          expect(
            distanceMeters(
              center,
              GeoPoint(bounds.northEast.latitude, center.longitude),
            ),
            closeTo(radius, .01),
          );
          expect(bounds.southWest.latitude, greaterThan(30));
          expect(bounds.southWest.longitude, greaterThan(120));
        }
      }
    },
  );
  test(
    'all returned hospital coordinates participate even outside the circle',
    () {
      final snapshot = SearchPresentationSnapshot(
        center: const GeoPoint(33, 126),
        source: 'GPS',
        revision: 1,
        result: HospitalSearchResult(
          [fixtures.hospital()],
          10000,
          false,
          false,
          [],
        ),
      );
      final bounds = fitBoundsFor(snapshot);
      expect(bounds.northEast.latitude, greaterThanOrEqualTo(37));
      expect(bounds.northEast.longitude, greaterThanOrEqualTo(127));
    },
  );
  test(
    'programmatic camera events do not create manual search; user movement requires 100m',
    () {
      final controller = EmergencyMapController(
        fixtures.FakeRepository(),
        fixtures.FakeLocation(null),
      );
      controller.center = const GeoPoint(37, 127);
      for (final origin in [
        CameraMoveOrigin.programmaticFit,
        CameraMoveOrigin.programmaticLayout,
        CameraMoveOrigin.programmaticCurrentLocation,
      ]) {
        controller.cameraMoved(MapCameraEvent(const GeoPoint(38, 128), origin));
        expect(controller.pendingCenter, isNull);
        expect(controller.userExploring, isFalse);
      }
      controller.cameraMoved(
        const MapCameraEvent(
          GeoPoint(37.00001, 127),
          CameraMoveOrigin.userZoomControl,
        ),
      );
      expect(controller.pendingCenter, isNull);
      controller.cameraMoved(
        const MapCameraEvent(
          GeoPoint(37.01, 127),
          CameraMoveOrigin.userGesture,
        ),
      );
      expect(controller.pendingCenter, isNotNull);
      controller.dispose();
    },
  );
  test(
    'invalid or poor heading falls back; trustworthy north zero is valid',
    () {
      expect(const HeadingReading(0, 15).usableDegrees, 0);
      expect(const HeadingReading(120, 45).usableDegrees, isNull);
      expect(const HeadingReading(120, null).usableDegrees, isNull);
      expect(const HeadingReading(double.nan, 15).usableDegrees, isNull);
      expect(const HeadingReading(null, 15).usableDegrees, isNull);
    },
  );

  for (final size in [
    const Size(430, 932),
    const Size(360, 640),
    const Size(800, 400),
  ]) {
    testWidgets(
      'map controls, drawer and sheet fit $size with no extra search',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = fixtures.FakeRepository();
        final camera = RecordingCamera();
        final heading = TestHeading();
        addTearDown(heading.events.close);
        bool ready = false;
        MapScene? observedScene;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              hospitalRepositoryProvider.overrideWithValue(repo),
              locationServiceProvider.overrideWithValue(
                fixtures.FakeLocation(const GeoPoint(37, 127)),
              ),
              headingServiceProvider.overrideWithValue(heading),
              emergencyDialerProvider.overrideWithValue(MockEmergencyDialer()),
            ],
            child: MaterialApp(
              home: EmergencyMapPage(
                mapBuilder:
                    ({
                      required scene,
                      required onReady,
                      required onCameraIdle,
                      required onHospitalSelected,
                    }) {
                      observedScene = scene;
                      if (!ready) {
                        ready = true;
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => onReady(camera),
                        );
                      }
                      return const ColoredBox(color: Color(0xffe5ede7));
                    },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(observedScene!.search!.result.radius, 10000);
        expect(camera.fits, hasLength(1));
        expect(repo.searchCount, 1);
        expect(find.byTooltip('119 신고'), findsOneWidget);
        expect(
          tester.getRect(find.byTooltip('119 신고')).bottom,
          lessThan(size.height),
        );
        await tester.tap(find.byTooltip('지도 확대'));
        await tester.pumpAndSettle();
        expect(camera.zoom, 1);
        heading.events.add(const HeadingReading(90, 15));
        await tester.pump(const Duration(milliseconds: 150));
        expect(observedScene!.heading, 90);
        expect(camera.fits, hasLength(1));
        await tester.drag(find.text('주변 응급의료기관'), const Offset(0, -120));
        await tester.pumpAndSettle();
        expect(camera.viewports.last.bottom, greaterThan(0));
        await tester.tap(find.byTooltip('메뉴 열기'));
        await tester.pumpAndSettle();
        expect(find.text('로그인'), findsOneWidget);
        expect(find.text('로그아웃'), findsNothing);
        if (find.text('내 응급정보').evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            find.text('내 응급정보'),
            80,
            scrollable: find.byType(Scrollable).last,
          );
        }
        await tester.tap(find.text('내 응급정보'));
        await tester.pumpAndSettle();
        expect(find.text('다시 만나 반가워요'), findsOneWidget);
        expect(repo.searchCount, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  test('production session starts signed out, no fabricated identity', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(sessionProvider).authenticated, isFalse);
    expect(container.read(sessionProvider).userSummary, isNull);
  });
  testWidgets(
    'authenticated menu uses provided identity and actual sign-out boundary',
    (tester) async {
      final session = TestSessionSource();
      final container = ProviderContainer(
        overrides: [sessionSourceProvider.overrideWithValue(session)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: EmergencyDrawer())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('테스트 전용 사용자'), findsOneWidget);
      expect(find.text('로그아웃'), findsOneWidget);
      expect(find.text('로그인'), findsNothing);
      await tester.tap(find.text('로그아웃'));
      await tester.pumpAndSettle();
      expect(session.signOutCount, 1);
      expect(container.read(sessionProvider).authenticated, isFalse);
    },
  );
}

class TestSessionSource implements SessionSource {
  int signOutCount = 0;
  @override
  Future<Map<String, dynamic>?> restore() async => {
    'userId': 'fixture-user',
    'phone': '테스트 전용 사용자',
    'role': 'MEMBER',
  };
  @override
  Future<bool> signOut() async {
    signOutCount++;
    return true;
  }
}
