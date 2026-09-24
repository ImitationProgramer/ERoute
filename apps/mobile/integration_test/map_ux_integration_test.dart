import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:eroute_mobile/core/theme/eroute_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:eroute_mobile/core/map/naver_emergency_map_view.dart';
import 'package:eroute_mobile/core/formatting/provider_time_formatter.dart';
import 'package:eroute_mobile/core/map/map_camera_controller.dart';
import 'package:eroute_mobile/core/map/camera_fit_geometry.dart';
import 'package:eroute_mobile/core/location/heading_service.dart';
import 'package:eroute_mobile/features/emergency_map/domain/hospital_summary.dart';
import 'package:eroute_mobile/features/emergency_map/presentation/emergency_map_controller.dart';
import 'package:eroute_mobile/features/emergency_map/presentation/emergency_map_page.dart';
import 'package:eroute_mobile/features/emergency_call/emergency_dialer.dart';
import 'package:eroute_mobile/core/map/selected_hospital_label.dart';
import 'package:eroute_mobile/core/map/map_scene.dart';
import 'package:eroute_mobile/core/network/api_client.dart';
import 'package:eroute_mobile/app/app.dart';
import 'package:eroute_mobile/features/emergency_map/domain/hospital_repository.dart';
import 'package:eroute_mobile/features/hospital_detail/data/remote_hospital_detail_repository.dart';
import 'package:eroute_mobile/features/hospital_detail/domain/hospital_actions.dart';
import 'package:eroute_mobile/features/hospital_detail/presentation/hospital_detail_state.dart';
import '../test/hospital_detail_test.dart' show RecordingContact, detailJson;
import '../test/emergency_map_test.dart' as fixtures;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var surfaceConverted = false;
  Future<void> captureNative(WidgetTester tester, String name) async {
    if (!surfaceConverted) {
      await binding.convertFlutterSurfaceToImage();
      surfaceConverted = true;
    }
    // Native overlays render asynchronously after the Dart setter updates.
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final bytes = await binding.takeScreenshot(name);
    final file = File('${Directory.systemTemp.path}/eroute-$name.png');
    await file.writeAsBytes(bytes);
    debugPrint('QA_IMAGE ${file.path}');
  }

  var hospitalNativeCalls = 0;
  setUp(() {
    surfaceConverted = false;
    hospitalNativeCalls = 0;
    for (final channel in [
      'plugins.flutter.io/url_launcher',
      'dev.flutter.pigeon.url_launcher_android.UrlLauncherApi.launchUrl',
      'dev.flutter.pigeon.url_launcher_ios.UrlLauncherApi.launchUrl',
    ]) {
      binding.defaultBinaryMessenger.setMockMessageHandler(channel, (_) async {
        hospitalNativeCalls++;
        fail('Native hospital phone handoff is forbidden in integration tests');
      });
    }
  });
  tearDown(() => expect(hospitalNativeCalls, 0));
  testWidgets(
    'native map fitting, exploration, selection, drawer, mock-only 119',
    (tester) async {
      final dialer = MockEmergencyDialer();
      var nativeCalls = 0;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('eroute/emergency_dialer'),
        (_) async {
          nativeCalls++;
          fail(
            'Real emergency platform channel is forbidden in integration tests',
          );
        },
      );
      await initializeNaverMap();
      final repo = fixtures.FakeRepository();
      final container = ProviderContainer(
        overrides: [
          emergencyDialerProvider.overrideWithValue(dialer),
          hospitalRepositoryProvider.overrideWithValue(repo),
          locationServiceProvider.overrideWithValue(
            fixtures.FakeLocation(const GeoPoint(37, 127)),
          ),
          headingServiceProvider.overrideWithValue(fixtures.SilentHeading()),
        ],
      );
      addTearDown(container.dispose);
      MapCameraController? camera;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ERouteTheme.light(),
            debugShowCheckedModeBanner: false,
            home: EmergencyMapPage(
              mapBuilder:
                  ({
                    required scene,
                    required onReady,
                    required onCameraIdle,
                    required onHospitalSelected,
                  }) => NaverEmergencyMapView(
                    scene: scene,
                    onReady: (value) {
                      camera = value;
                      onReady(value);
                    },
                    onCameraIdle: onCameraIdle,
                    onHospitalSelected: onHospitalSelected,
                  ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 100 && camera == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(camera, isNotNull);
      await tester.pump(const Duration(seconds: 2));
      expect(mapAuthenticationError.value, isFalse);
      final controller = container.read(mapControllerProvider);
      expect(controller.snapshot, isNotNull);
      final dynamic nativeState = tester.state(
        find.byType(NaverEmergencyMapView),
      );
      final Map initialMarkers = nativeState.debugHospitalMarkers;
      expect(
        initialMarkers.length,
        controller.snapshot!.result.hospitals.length,
      );
      expect(
        initialMarkers.values.every(
          (dynamic marker) => marker.caption?.text.isNotEmpty != true,
        ),
        isTrue,
      );
      expect(find.text('이 위치에서 검색'), findsNothing);
      final bounds = fitBoundsFor(controller.snapshot!);
      final top = tester.getRect(find.byTooltip('메뉴 열기')).bottom;
      final sheetTop = tester.getRect(find.text('주변 응급의료기관')).top - 28;
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      for (final point in [
        bounds.southWest,
        bounds.northEast,
        controller.snapshot!.center,
        ...controller.snapshot!.result.hospitals.map((h) => h.location),
      ]) {
        final screen = await camera!.project(point);
        expect(screen.dx, inInclusiveRange(0, size.width));
        expect(screen.dy, inInclusiveRange(top, sheetTop));
      }
      controller.moveCamera(const GeoPoint(33.4, 126.5));
      await controller.searchHere();
      await tester.pump(const Duration(seconds: 2));
      expect(controller.snapshot!.source, 'MANUAL');
      expect(find.text('이 위치에서 검색'), findsNothing);
      controller.select(controller.snapshot!.result.hospitals.first.hpid);
      Future<void> waitForSelectedLabel() async {
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          final Map markers = nativeState.debugHospitalMarkers;
          if (markers.values
                      .where((dynamic m) => m.caption?.text.isNotEmpty == true)
                      .length +
                  find.byType(SelectedHospitalLabel).evaluate().length ==
              1) {
            return;
          }
        }
      }

      await waitForSelectedLabel();
      final Map selectedMarkers = nativeState.debugHospitalMarkers;
      final captions = selectedMarkers.values
          .where((dynamic marker) => marker.caption?.text.isNotEmpty == true)
          .length;
      expect(
        captions + find.byType(SelectedHospitalLabel).evaluate().length,
        1,
      );
      final markerBefore = selectedMarkers.values.first;
      final callsBefore = repo.searchCount;
      await tester.tap(find.byTooltip('지도 확대'));
      await tester.pump(const Duration(seconds: 1));
      final beforeSheet = await camera!.project(controller.snapshot!.center);
      await tester.drag(find.text('주변 응급의료기관'), const Offset(0, -120));
      await tester.pump(const Duration(seconds: 1));
      final afterSheet = await camera!.project(controller.snapshot!.center);
      expect((beforeSheet - afterSheet).distance, lessThan(2));
      expect(repo.searchCount, callsBefore);
      expect(
        identical(
          (nativeState.debugHospitalMarkers as Map).values.first,
          markerBefore,
        ),
        isTrue,
      );
      final dense = List.generate(
        40,
        (i) => HospitalSummary.fromJson({
          ...detailJson(hpid: 'DENSE-$i'),
          'location': {
            'latitude': 37 + (i ~/ 8) * .001,
            'longitude': 127 + (i % 8) * .001,
          },
          'distanceFromCenterMeters': 100,
          'distanceFromUserMeters': null,
        }),
      );
      controller.snapshot = SearchPresentationSnapshot(
        center: const GeoPoint(37, 127),
        source: 'GPS',
        revision: controller.snapshot!.revision + 1,
        result: HospitalSearchResult(dense, 10000, false, false, []),
      );
      controller.selectedHpid = null;
      controller.notifyListeners();
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (nativeState.debugClusterPlan.hospitalCount == 40) break;
      }
      await tester.pump(const Duration(seconds: 1));
      final Map denseMarkers = nativeState.debugHospitalMarkers;
      expect(nativeState.debugClusterPlan.hospitalCount, 40);
      expect((nativeState.debugClusterMarkers as Map), isNotEmpty);
      expect(
        denseMarkers.values.every(
          (dynamic marker) => marker.caption?.text.isNotEmpty != true,
        ),
        isTrue,
      );
      await captureNative(tester, 'dense-unselected');
      final centerBeforeSelection = await camera!.project(
        controller.snapshot!.center,
      );
      for (final hpid in ['DENSE-0', 'DENSE-1']) {
        controller.select(hpid);
        await tester.pump();
        await waitForSelectedLabel();
        final Map markers = nativeState.debugHospitalMarkers;
        expect(markers.containsKey(hpid), isTrue);
        expect(nativeState.debugClusterPlan.individualIds, contains(hpid));
        expect(nativeState.debugClusterPlan.hospitalCount, 40);
        expect(
          markers.entries.every(
            (entry) =>
                entry.key == hpid ||
                entry.value.caption?.text.isNotEmpty != true,
          ),
          isTrue,
        );
        expect(
          markers.values
                  .where(
                    (dynamic marker) => marker.caption?.text.isNotEmpty == true,
                  )
                  .length +
              find.byType(SelectedHospitalLabel).evaluate().length,
          1,
        );
        await captureNative(tester, 'dense-selected-$hpid');
        expect(
          markers.entries.every(
            (entry) =>
                !denseMarkers.containsKey(entry.key) ||
                identical(entry.value, denseMarkers[entry.key]),
          ),
          isTrue,
        );
      }
      final centerAfterSelection = await camera!.project(
        controller.snapshot!.center,
      );
      expect(
        (centerBeforeSelection - centerAfterSelection).distance,
        lessThan(2),
      );
      expect(repo.searchCount, callsBefore);
      final insetsBefore = nativeState.debugViewportInsets as EdgeInsets;
      final selectedPosition = await camera!.project(dense[1].location);
      await camera!.updateViewport(
        // Occlude the caption from below while retaining space for its fallback
        // above. A tall development header can leave no room if top is raised.
        insetsBefore.copyWith(
          bottom:
              tester.getSize(find.byType(NaverEmergencyMapView)).height -
              selectedPosition.dy,
        ),
        settled: true,
      );
      for (
        var i = 0;
        i < 30 && find.byType(SelectedHospitalLabel).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(SelectedHospitalLabel), findsOneWidget);
      expect(
        (nativeState.debugHospitalMarkers as Map)['DENSE-1'].caption.text,
        isEmpty,
      );
      await tester.tap(find.byType(SelectedHospitalLabel));
      await tester.pump();
      expect(controller.selectedHpid, 'DENSE-1');
      expect(
        (await camera!.project(dense[1].location) - selectedPosition).distance,
        lessThan(2),
      );
      await camera!.updateViewport(insetsBefore, settled: true);
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if ((nativeState.debugHospitalMarkers as Map)['DENSE-1']
                .caption
                ?.text
                .isNotEmpty ==
            true) {
          break;
        }
      }
      expect(
        (nativeState.debugHospitalMarkers as Map)['DENSE-1'].caption.text,
        dense[1].name,
      );
      expect(find.byType(SelectedHospitalLabel), findsNothing);
      expect(repo.searchCount, callsBefore);
      await tester.tap(find.byTooltip('메뉴 열기'));
      await tester.pumpAndSettle();
      expect(find.text('로그인'), findsOneWidget);
      expect(find.text('로그아웃'), findsNothing);
      await tester.tap(find.byTooltip('메뉴 닫기'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('119 신고'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('119 전화 연결'));
      await tester.pumpAndSettle();
      expect(dialer.requests, ['119']);
      expect(nativeCalls, 0);
      expect(find.text('개발 모드: 실제 전화 연결을 실행하지 않았습니다.'), findsOneWidget);
      await captureNative(tester, 'selected-map');
      await tester.pumpWidget(const SizedBox());
    },
  );

  const smokeHpid = String.fromEnvironment('DETAIL_SMOKE_HPID');
  const smokeHpids = String.fromEnvironment('DETAIL_SMOKE_HPIDS');
  for (final hpid
      in (smokeHpids.isEmpty ? smokeHpid : smokeHpids)
          .split(',')
          .where((hpid) => hpid.isNotEmpty)) {
    testWidgets(
      'stored HTTP detail $hpid reaches Android through Map selection and Back; fake-only contact',
      (tester) async {
        final client = createApiClient();
        addTearDown(client.close);
        final remote = RemoteHospitalDetailRepository(client);
        final stored = await remote.get(hpid);
        expect(stored.address, isNotEmpty);
        expect(
          normalizeHospitalDialNumber(stored.mainPhone!.rawValue),
          isNotNull,
        );
        final contact = RecordingContact();
        final repo = _StoredSearchRepository(stored.realtimeView);
        final container = ProviderContainer(
          overrides: [
            hospitalRepositoryProvider.overrideWithValue(repo),
            locationServiceProvider.overrideWithValue(
              fixtures.FakeLocation(stored.location),
            ),
            headingServiceProvider.overrideWithValue(fixtures.SilentHeading()),
            hospitalDetailRepositoryProvider.overrideWithValue(remote),
            hospitalContactLauncherProvider.overrideWithValue(contact),
            emergencyDialerProvider.overrideWithValue(MockEmergencyDialer()),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const ERouteApp(),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('지도 보기'));
        await tester.pumpAndSettle();
        final map = container.read(mapControllerProvider);
        final snapshot = map.snapshot;
        expect(snapshot!.result.hospitals.single.hpid, hpid);
        await tester.tap(find.text(stored.name).first);
        await tester.pumpAndSettle();
        expect(find.text('병원 상세'), findsOneWidget);
        expect(map.selectedHpid, hpid);
        expect(find.text(stored.address!), findsWidgets);
        final providerTime = formatProviderWallTime(
          stored.realtimeView.parsedSourceTime,
        );
        if (providerTime != null) {
          expect(find.textContaining(providerTime), findsWidgets);
        }
        expect(
          find.textContaining(RegExp(r'(?<!\d)\d{14}(?!\d)')),
          findsNothing,
        );
        await captureNative(tester, 'detail-time-$hpid');
        expect(contact.calls, isEmpty);
        await tester.tap(find.text('전화하기'));
        await tester.pumpAndSettle();
        expect(contact.calls, [stored.mainPhone!.rawValue]);
        await tester.ensureVisible(find.text('진료 정보'));
        await tester.tap(find.text('진료 정보'));
        await tester.pumpAndSettle();
        expect(find.text('병원 진료시간'), findsOneWidget);
        expect(stored.basicInfo.fetchStatus, 'SUCCESS');
        for (final department in stored.basicInfo.departments) {
          expect(find.text(department.name), findsOneWidget);
        }
        await captureNative(tester, 'clinical-departments-$hpid');
        await tester.ensureVisible(find.text('공휴일'));
        await tester.pumpAndSettle();
        expect(find.text('공휴일'), findsOneWidget);
        for (final day in [
          '월요일',
          '화요일',
          '수요일',
          '목요일',
          '금요일',
          '토요일',
          '일요일',
          '공휴일',
        ]) {
          expect(find.text(day), findsOneWidget);
        }
        for (final hours in stored.basicInfo.operatingHours) {
          expect(find.text(hours.display), findsWidgets);
        }
        expect(find.textContaining('정적 정보 수집 연동 후 제공합니다'), findsNothing);
        expect(
          find.textContaining(RegExp(r'(?<!\d)\d{14}(?!\d)')),
          findsNothing,
        );
        await captureNative(tester, 'clinical-hours-$hpid');
        expect(tester.takeException(), isNull);

        await tester.tap(find.byTooltip('뒤로 가기'));
        await tester.pumpAndSettle();
        expect(identical(map.snapshot, snapshot), isTrue);
        expect(map.selectedHpid, hpid);
        expect(repo.searches, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

/// Uses the stored real hospital in a test search; never calls Backend search/NMC.
class _StoredSearchRepository implements HospitalRepository {
  final HospitalSummary hospital;
  int searches = 0;
  _StoredSearchRepository(this.hospital);
  @override
  Future<MapPolicy> policy() async => MapPolicy([10000], 10000, null);
  @override
  Future<HospitalSearchResult> search(
    GeoPoint center,
    String source,
    GeoPoint? user,
    int? radius,
  ) async {
    searches++;
    return HospitalSearchResult([hospital], 10000, false, false, []);
  }
}
