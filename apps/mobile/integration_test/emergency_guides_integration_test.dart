import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:eroute_mobile/app/router.dart';
import 'package:eroute_mobile/core/theme/eroute_theme.dart';
import 'package:eroute_mobile/core/location/heading_service.dart';
import 'package:eroute_mobile/features/app_menu/app_session.dart';
import 'package:eroute_mobile/features/emergency_call/emergency_dialer.dart';
import 'package:eroute_mobile/features/emergency_guides/data/asset_guide_repository.dart';
import 'package:eroute_mobile/features/emergency_guides/data/guide_source_launcher.dart';
import 'package:eroute_mobile/features/emergency_guides/presentation/guide_pages.dart';
import 'package:eroute_mobile/features/emergency_landing/presentation/emergency_landing_page.dart';
import 'package:eroute_mobile/features/emergency_map/presentation/emergency_map_controller.dart';
import 'package:eroute_mobile/features/emergency_map/domain/hospital_summary.dart';
import 'package:eroute_mobile/features/member_ui/member_contract.dart';
import 'package:eroute_mobile/features/member_ui/member_widgets.dart';
import 'package:eroute_mobile/preview/member_preview_repository.dart';
import '../test/emergency_map_test.dart'
    show FakeRepository, FakeLocation, SilentHeading;

class ObservedSourceLauncher implements GuideSourceLauncher {
  final requests = <Uri>[];
  @override
  Future<bool> open(Uri uri) async {
    requests.add(uri);
    return false; // Offline failure preserves the bundled body.
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Pixel 10 offline guides, routes, source, mock119 and accessibility layouts',
    (tester) async {
      final dialer = MockEmergencyDialer();
      final launcher = ObservedSourceLauncher();
      final hospitals = FakeRepository();
      final auth = PreviewAuthRepository();
      final container = ProviderContainer(
        overrides: [
          emergencyDialerProvider.overrideWithValue(dialer),
          guideSourceLauncherProvider.overrideWithValue(launcher),
          sessionProvider.overrideWithValue(const AppSession.signedOut()),
          memberPrivacyProvider.overrideWithValue(PreviewPrivacy()),
          memberUiRepositoryProvider.overrideWithValue(
            PreviewMemberRepository(auth, delay: Duration.zero),
          ),
          hospitalRepositoryProvider.overrideWithValue(hospitals),
          locationServiceProvider.overrideWithValue(
            FakeLocation(const GeoPoint(37, 127)),
          ),
          headingServiceProvider.overrideWithValue(SilentHeading()),
        ],
      );
      addTearDown(container.dispose);
      Future<void> mount({
        Widget home = const EmergencyLandingPage(),
        bool dark = false,
        double scale = 1,
      }) async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              key: UniqueKey(),
              debugShowCheckedModeBanner: false,
              theme: dark ? ERouteTheme.dark() : ERouteTheme.light(),
              onGenerateRoute: buildAppRoute,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: home,
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> screenshot(String name) async {
        await tester.pumpAndSettle();
        await binding.takeScreenshot(name);
        expect(tester.takeException(), isNull);
      }

      Finder quick(String label) => find
          .byWidgetPredicate(
            (w) => w is Text && (w.semanticsLabel == label || w.data == label),
          )
          .first;
      Future<void> tap(Finder target) async {
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      Future<void> back() => tap(find.byTooltip('뒤로 가기'));

      await mount();
      await binding.convertFlutterSurfaceToImage();
      await screenshot('home');
      expect(hospitals.searchCount, 0);
      await tap(find.text('119 신고'));
      await tap(find.text('취소'));
      expect(dialer.requests, isEmpty);
      await tap(quick('응급상황 대처요령'));
      await screenshot('emergency-actions-list');
      await tap(find.text('119에 알려줄 내용'));
      await screenshot('emergency-call-info');
      expect(find.text('환자가 있다는 사실'), findsOneWidget);
      await back();
      await tap(find.text('구급차가 오기 전'));
      await screenshot('ambulance-before-arrival');
      await tap(find.text('출처 상세 정보'));
      await tester.ensureVisible(find.text('출처 URL 복사'));
      await screenshot('source-disclosure');
      await tap(find.text('공식 자료 보기'));
      expect(launcher.requests.single.host, 'www.nfa.go.kr');
      expect(find.textContaining('공식 자료를 열지 못했습니다'), findsOneWidget);
      expect(find.text('119 의료지도에 따라 응급처치'), findsOneWidget);
      await back();
      await back();
      await tap(quick('응급처치 가이드'));
      await screenshot('first-aid-list');
      for (final item in [
        ('성인 심폐소생술', 'cpr'),
        ('자동심장충격기(AED)', 'aed'),
        ('영아 기도폐쇄', 'infant-choking'),
        ('외부 출혈·지혈', 'bleeding'),
        ('화상', 'burn'),
        ('열손상', 'heat'),
        ('한랭손상', 'cold'),
        ('경련 발작', 'seizure'),
      ]) {
        await tap(find.text(item.$1));
        await screenshot(item.$2);
        expect(find.text('지금 해야 할 일'), findsOneWidget);
        if (item.$2 == 'cpr') {
          await tap(find.widgetWithText(OutlinedButton, '119 전화 연결'));
          await tap(find.widgetWithText(FilledButton, '119 전화 연결'));
          expect(dialer.requests, ['119']);
          await tester.pump(const Duration(seconds: 5));
          await tester.pumpAndSettle();
        }
        await back();
      }
      // Every actual bundled article is also constructed and rendered offline.
      final catalog = await AssetGuideRepository(rootBundle).catalog();
      expect(catalog.articles.length, 17);
      for (final entry in catalog.entries) {
        await mount(home: GuideDetailPage(id: entry.id));
        expect(find.text('지금 해야 할 일'), findsOneWidget);
        expect(find.textContaining(entry.source.title), findsWidgets);
        expect(tester.takeException(), isNull);
      }
      expect(hospitals.searchCount, 0);
      await mount(
        home: const GuideDetailPage(id: 'FIRST_AID_CPR_ADULT'),
        dark: true,
      );
      await screenshot('dark');
      await binding.setSurfaceSize(const Size(320, 740));
      await mount(
        home: const GuideDetailPage(id: 'FIRST_AID_CPR_ADULT'),
        scale: 2,
      );
      await screenshot('320dp-200');
      await tap(find.text('출처 상세 정보').last);
      await screenshot('320dp-200-source');
      await binding.setSurfaceSize(null);

      // Existing home entry points and signed-out health gate; synthetic hospital data only.
      await mount();
      await tap(quick('가까운 병원 찾기'));
      expect(hospitals.searchCount, 1);
      await screenshot('nearby-hospitals-regression');
      await back();
      await tap(quick('내 응급정보'));
      expect(find.text('로그인'), findsWidgets);
      await screenshot('emergency-info-regression');

      // Real Android URL launcher handoff, no phone URI; offline browser is expected.
      final uri = Uri.parse(catalog.entries.first.source.url);
      expect(await const HttpsGuideSourceLauncher().open(uri), isTrue);
      binding.reportData = {
        ...?binding.reportData,
        'guideCount': 17,
        'hospitalRequests': hospitals.searchCount,
        'mock119Requests': dialer.requests,
        'real119Requests': 0,
        'officialHttpsHandoff': true,
        'networkMode': 'host disabled Wi-Fi and mobile data before launch',
      };
    },
  );
}
