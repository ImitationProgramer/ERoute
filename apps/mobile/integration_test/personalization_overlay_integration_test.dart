import 'dart:io';
import 'package:flutter/material.dart';
import 'package:eroute_mobile/core/theme/eroute_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:eroute_mobile/core/map/naver_emergency_map_view.dart';
import 'package:eroute_mobile/core/map/map_camera_controller.dart';
import 'package:eroute_mobile/core/location/heading_service.dart';
import 'package:eroute_mobile/core/privacy_changes.dart';
import 'package:eroute_mobile/features/app_menu/app_session.dart';
import 'package:eroute_mobile/features/emergency_map/domain/hospital_summary.dart';
import 'package:eroute_mobile/features/emergency_map/presentation/emergency_map_controller.dart';
import 'package:eroute_mobile/features/emergency_map/presentation/emergency_map_page.dart';
import 'package:eroute_mobile/features/disease_personalization/disease_reference.dart';
import 'package:eroute_mobile/features/disease_personalization/disease_repository.dart';
import 'package:eroute_mobile/features/disease_personalization/department_matcher.dart';
import 'package:eroute_mobile/features/disease_personalization/map_personalization_controller.dart';
import '../test/emergency_map_test.dart' as fixtures;
import '../test/personalization_foundation_test.dart'
    show SyntheticSelectionRepository;
import '../test/support/synthetic_personalization.dart';

class NativeSyntheticPublic implements DiseaseDataRepository {
  @override
  Future<DiseaseReference> reference() async => syntheticReference();
  @override
  Future<List<DepartmentSnapshot>> departments(List<String> hpids) async => [
    for (final h in hpids) syntheticDepartmentSnapshot(hpid: h),
  ];
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native map keeps public marker, aligns separate gold dot, clears on privacy and lifecycle',
    (tester) async {
      await initializeNaverMap();
      await binding.convertFlutterSurfaceToImage();
      final repo = fixtures.FakeRepository();
      final container = ProviderContainer(
        overrides: [
          hospitalRepositoryProvider.overrideWithValue(repo),
          locationServiceProvider.overrideWithValue(
            fixtures.FakeLocation(const GeoPoint(37, 127)),
          ),
          headingServiceProvider.overrideWithValue(fixtures.SilentHeading()),
          sessionProvider.overrideWithValue(
            const AppSession(
              phase: SessionPhase.authenticated,
              user: {'userId': 'TEST_USER'},
              generation: 1,
            ),
          ),
          diseaseDataRepositoryProvider.overrideWithValue(
            NativeSyntheticPublic(),
          ),
          mapSelectionRepositoryProvider.overrideWithValue(
            SyntheticSelectionRepository(),
          ),
          mapPersonalizationAvailableProvider.overrideWithValue(true),
        ],
      );
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
                    onReady: (v) {
                      camera = v;
                      onReady(v);
                    },
                    onCameraIdle: onCameraIdle,
                    onHospitalSelected: onHospitalSelected,
                  ),
            ),
          ),
        ),
      );
      Future<void> waitFor(bool Function() ready) async {
        for (var i = 0; i < 150 && !ready(); i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(ready(), isTrue);
      }

      await waitFor(
        () =>
            camera != null &&
            container.read(mapControllerProvider).snapshot != null,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(mapAuthenticationError.value, isFalse);
      final dynamic native = tester.state(find.byType(NaverEmergencyMapView));
      final Map before = Map.of(native.debugHospitalMarkers as Map);
      final searches = repo.searchCount;
      await container.read(mapPersonalizationProvider.notifier).enable();
      final dot = find.byKey(const ValueKey('personalization-dot:TEST_ONLY'));
      await waitFor(() => dot.evaluate().isNotEmpty);
      final location = await camera!.project(const GeoPoint(37, 127));
      expect(
        (tester.getCenter(dot) - location - const Offset(13.170, -13.170))
            .distance,
        lessThan(3),
      );
      expect((native.debugHospitalMarkers as Map).keys, before.keys);
      expect(repo.searchCount, searches);
      expect(find.text('내 질환 관련 진료과'), findsWidgets);
      container.read(mapControllerProvider).select('TEST_ONLY');
      await tester.pumpAndSettle();
      await waitFor(() => dot.evaluate().isNotEmpty);
      expect(tester.getSize(dot), const Size(8, 8));
      expect(
        (tester.getCenter(dot) - location - const Offset(16.2635, -16.2635))
            .distance,
        lessThan(3),
      );
      expect(repo.searchCount, searches);
      await waitFor(
        () =>
            (native.debugHospitalMarkers as Map)['TEST_ONLY'].size.width == 48,
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)),
      );
      // Pump multiple frames so the native texture reflects the SDK setters.
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final image = await binding.takeScreenshot('approved-selected-dot');
      final artifact = File(
        '${Directory.systemTemp.path}/eroute-review-approved-selected-dot.png',
      );
      await artifact.writeAsBytes(image);
      debugPrint('QA_IMAGE ${artifact.path}');
      debugPrint('SYNTHETIC_OVERLAY_NATIVE_PRIVACY_READY');
      await tester.pump(const Duration(seconds: 2));
      container.read(privacyChangeProvider.notifier).state++;
      await tester.pumpAndSettle();
      expect(dot, findsNothing);
      expect(container.read(mapPersonalizationProvider).enabled, isFalse);
      await container.read(mapPersonalizationProvider.notifier).enable();
      await waitFor(() => dot.evaluate().isNotEmpty);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(dot, findsNothing);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(container.read(mapPersonalizationProvider).enabled, isFalse);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    },
  );
}
