import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:eroute_mobile/features/hospital_detail/domain/hospital_actions.dart';
import '../test/hospital_navigation_test.dart' show showNavigationDetail;

// Real package_info and url_launcher plugins; only hospital data/phone are fixtures.
class ObservedSystemNavigation implements HospitalNavigationLauncher {
  final system = const SystemHospitalNavigationLauncher();
  HospitalNavigationResult? result;
  bool? storeOpened;
  @override
  HospitalActionAvailability get availability => system.availability;
  @override
  Future<HospitalNavigationResult> openNavigation(
    double? lat,
    double? lng,
    String name,
  ) async => result = await system.openNavigation(lat, lng, name);
  @override
  Future<bool> openStore() async => storeOpened = await system.openStore();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android real missing-app detection, cancellation and official store handoff',
    (tester) async {
      final identity = await PackageInfo.fromPlatform();
      expect(identity.packageName, 'com.eroute.eroute_mobile.preview');
      final launcher = ObservedSystemNavigation();
      await showNavigationDetail(tester, launcher: launcher);
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await binding.takeScreenshot('navigation-android-detail');
      await tester.tap(find.text('네이버 지도에서 열기'));
      await tester.pumpAndSettle();
      expect(launcher.result, HospitalNavigationResult.notInstalled);
      expect(find.text('네이버 지도가 필요합니다'), findsOneWidget);
      await binding.takeScreenshot('navigation-android-not-installed');
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(launcher.storeOpened, isNull);
      expect(find.text('상세 병원 TEST_ONLY'), findsOneWidget);
      await tester.tap(find.text('네이버 지도에서 열기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('설치하기'));
      // Permit native store handoff to complete without assuming the store is loaded.
      await tester.pumpAndSettle();
      for (var i = 0; i < 30 && launcher.storeOpened == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(launcher.storeOpened, true);
    },
  );
}
