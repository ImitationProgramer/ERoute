import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eroute_mobile/app/app.dart';
import 'package:eroute_mobile/core/location/heading_service.dart';
import 'package:eroute_mobile/core/theme/theme_controller.dart';
import 'package:eroute_mobile/features/emergency_call/emergency_dialer.dart';
import 'package:eroute_mobile/features/emergency_map/domain/hospital_summary.dart';
import 'package:eroute_mobile/features/emergency_map/presentation/emergency_map_controller.dart';
import 'package:eroute_mobile/features/emergency_landing/presentation/widgets/landing_illustration.dart';
import 'package:eroute_mobile/features/hospital_detail/domain/hospital_actions.dart';
import 'package:eroute_mobile/features/hospital_detail/domain/hospital_detail.dart';
import 'package:eroute_mobile/features/hospital_detail/domain/hospital_detail_repository.dart';
import 'package:eroute_mobile/features/hospital_detail/presentation/hospital_detail_state.dart';
import 'emergency_map_test.dart' as fixtures;

class FakeDetailRepository implements HospitalDetailRepository {
  int requestCount = 0;
  @override
  Future<HospitalDetail> get(String hpid) async {
    requestCount++;
    return HospitalDetail(
      hpid: hpid,
      name: '테스트 응급의료기관',
      classification: '지역응급의료센터',
      address: '검증용 주소',
      location: const GeoPoint(37, 127),
      mainPhone: const HospitalContactNumber(
        sourceField: 'dutyTel1',
        officialLabel: '대표전화1',
        rawValue: '02-111-1111',
      ),
      secondaryPhone: const HospitalContactNumber(
        sourceField: 'dutyTel3',
        officialLabel: '대표전화2',
        rawValue: '02-222-2222',
      ),
      masterUpdatedAt: DateTime.parse('2026-09-08T12:00:00Z'),
      catalogFetchedAt: DateTime.parse('2026-09-08T12:00:00Z'),
      generatedAt: DateTime.parse('2026-09-08T12:00:00Z'),
      catalogVersion: 'test',
      catalogStale: false,
      realtimeView: fixtures.hospital(),
      basicInfo: const HospitalBasicInfo(fetchStatus: 'NOT_REQUESTED'),
    );
  }
}

class FakeContactLauncher implements HospitalContactLauncher {
  final List<String> requests = [];
  @override
  HospitalActionAvailability get availability =>
      HospitalActionAvailability.available;
  @override
  Future<bool> openDialScreen(String phoneNumber) async {
    requests.add(phoneNumber);
    return true;
  }
}

Future<void> captureQa(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/qa/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
  });
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('NotoSansKR')
      ..addFont(rootBundle.load('assets/fonts/NotoSansKR.ttf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('landing is inert until the user opens the map', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = fixtures.FakeRepository()..totalCount = 8;
    final detailRepo = FakeDetailRepository();
    final contactLauncher = FakeContactLauncher();
    final qaKey = GlobalKey();
    final mock = MockEmergencyDialer();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hospitalRepositoryProvider.overrideWithValue(repo),
          locationServiceProvider.overrideWithValue(
            fixtures.FakeLocation(const GeoPoint(37, 127)),
          ),
          headingServiceProvider.overrideWithValue(fixtures.SilentHeading()),
          emergencyDialerProvider.overrideWithValue(mock),
          hospitalDetailRepositoryProvider.overrideWithValue(detailRepo),
          hospitalContactLauncherProvider.overrideWithValue(contactLauncher),
        ],
        child: RepaintBoundary(key: qaKey, child: const ERouteApp()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('지금,\n도움이 필요하신가요?'), findsOneWidget);
    expect(find.text('119 신고'), findsOneWidget);
    expect(repo.searchCount, 0);
    expect(mock.requests, isEmpty);
    await tester.runAsync(
      () => precacheImage(
        const AssetImage(LandingIllustrationAssets.light),
        tester.element(find.text('119 신고')),
      ),
    );
    await tester.pumpAndSettle();
    await captureQa(tester, qaKey, 'emergency-landing');

    await tester.tap(find.text('지도 보기'));
    await tester.pumpAndSettle();
    expect(find.text('주변 응급의료기관'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(repo.searchCount, 1);
    expect(repo.requestedRadii, [10000]);

    await tester.tap(find.text('20km'));
    await tester.pumpAndSettle();
    expect(repo.searchCount, 2);
    expect(repo.requestedRadii, [10000, 20000]);

    await tester.tap(find.text('테스트 응급의료기관'));
    await tester.pumpAndSettle();
    expect(find.text('병원 상세'), findsOneWidget);
    expect(find.text('검증용 주소'), findsWidgets);
    await tester.tap(find.text('전화하기'));
    await tester.pumpAndSettle();
    expect(contactLauncher.requests, ['02-111-1111']);

    await tester.scrollUntilVisible(
      find.text('대표전화'),
      220,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('대표전화'), findsOneWidget);
    expect(find.text('추가 전화번호'), findsOneWidget);
    expect(find.text('02-222-2222'), findsOneWidget);
    expect(find.text('응급실 전화'), findsNothing);
    expect(find.text('14'), findsOneWidget);
    expect(find.text('17'), findsOneWidget);
    expect(find.textContaining('중증응급환자'), findsNothing);
    expect(find.textContaining('24시간'), findsNothing);
    expect(repo.searchCount, 2);
    expect(detailRepo.requestCount, 1);
    await captureQa(tester, qaKey, 'hospital-detail');

    await tester.tap(find.byTooltip('뒤로 가기'));
    await tester.pumpAndSettle();
    expect(find.text('주변 응급의료기관'), findsOneWidget);
    expect(repo.searchCount, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'landing 119 uses the shared mock and never opens native channel',
    (tester) async {
      var nativeCalls = 0;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('eroute/emergency_dialer'),
        (_) async {
          nativeCalls++;
          fail('native emergency channel is forbidden in widget tests');
        },
      );
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('eroute/emergency_dialer'),
          null,
        ),
      );
      final repo = fixtures.FakeRepository();
      final mock = MockEmergencyDialer();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hospitalRepositoryProvider.overrideWithValue(repo),
            emergencyDialerProvider.overrideWithValue(mock),
          ],
          child: const ERouteApp(),
        ),
      );
      await tester.tap(find.text('119 신고'));
      await tester.pumpAndSettle();
      expect(mock.requests, isEmpty);
      await tester.tap(find.text('119 전화 연결'));
      await tester.pumpAndSettle();
      expect(mock.requests, ['119']);
      expect(nativeCalls, 0);
      expect(repo.searchCount, 0);
    },
  );

  testWidgets('drawer emergency shortcut uses the same mock coordinator', (
    tester,
  ) async {
    final repo = fixtures.FakeRepository();
    final mock = MockEmergencyDialer();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hospitalRepositoryProvider.overrideWithValue(repo),
          emergencyDialerProvider.overrideWithValue(mock),
        ],
        child: const ERouteApp(),
      ),
    );
    await tester.tap(find.byTooltip('메뉴 열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('긴급 상황 시\n119 전화 연결'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AlertDialog, '119 신고'), findsOneWidget);
    await tester.tap(find.text('119 전화 연결'));
    await tester.pumpAndSettle();
    expect(mock.requests, ['119']);
    expect(repo.searchCount, 0);
  });

  testWidgets('system theme boundary changes theme without searching', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = fixtures.FakeRepository();
    final container = ProviderContainer(
      overrides: [hospitalRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const ERouteApp()),
    );
    await tester.pumpAndSettle();
    container.read(themeModeProvider.notifier).state = ThemeMode.dark;
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('119 신고'))).brightness,
      Brightness.dark,
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      LandingIllustrationAssets.dark,
    );
    expect(repo.searchCount, 0);
  });

  testWidgets('landing remains reachable on a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(const ProviderScope(child: ERouteApp()));
    await tester.pumpAndSettle();
    expect(find.text('119 신고'), findsOneWidget);
    expect(find.bySemanticsLabel('가까운 병원 찾기'), findsOneWidget);
    expect(find.byKey(const ValueKey('landing-illustration')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'landing illustration is a separate non-interactive theme asset',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const ProviderScope(child: ERouteApp()));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('landing-illustration')),
        findsOneWidget,
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect(
        (image.image as AssetImage).assetName,
        LandingIllustrationAssets.light,
      );
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('landing-illustration')))
            .label,
        isEmpty,
      );
    },
  );

  test(
    'hospital dial normalization rejects emergency and malformed numbers',
    () {
      expect(normalizeHospitalDialNumber('02-111-1111'), '021111111');
      expect(normalizeHospitalDialNumber('119'), isNull);
      expect(normalizeHospitalDialNumber('112'), isNull);
      expect(normalizeHospitalDialNumber('02-CALL'), isNull);
    },
  );

  test('detail contract preserves master contacts and realtime meanings', () {
    final detail = HospitalDetail.fromJson({
      'hpid': 'TEST',
      'name': '테스트 병원',
      'emergencyClass': {'code': 'A', 'name': '분류'},
      'address': '검증 주소',
      'location': {'latitude': 37, 'longitude': 127},
      'mainPhone': {
        'sourceField': 'dutyTel1',
        'officialLabel': '대표전화1',
        'rawValue': '02-111-1111',
      },
      'secondaryPhone': {
        'sourceField': 'dutyTel3',
        'officialLabel': '대표전화2',
        'rawValue': '02-222-2222',
      },
      'masterUpdatedAt': '2026-09-08T12:00:00Z',
      'catalogVersion': 'v1',
      'catalogFetchedAt': '2026-09-08T12:00:00Z',
      'catalogStale': false,
      'realtime': {
        'coverageStatus': 'LIVE_AVAILABLE',
        'refreshStatus': 'CACHE_HIT',
        'availableBeds': {
          'endpoint': 'getEmrrmRltmUsefulSckbdInfoInqire',
          'sourceField': 'hvec',
          'officialLabel': '일반',
          'rawValue': '0',
          'numericValue': 0,
          'interpretationStatus': 'KNOWN',
        },
        'referenceResources': [
          {
            'endpoint': 'getEmrrmRltmUsefulSckbdInfoInqire',
            'sourceField': 'HVS01',
            'officialLabel': '일반_기준',
            'rawValue': null,
            'numericValue': null,
            'interpretationStatus': 'NOT_PROVIDED',
          },
        ],
        'freshness': {
          'source': {'sourceRawTimestamp': null},
          'fetchedAt': '2026-09-08T12:00:00Z',
          'stale': false,
        },
        'error': null,
      },
      'basicInfo': {
        'fetchStatus': 'NOT_REQUESTED',
        'departmentsRaw': null,
        'sourceRawTimestamp': null,
        'parsedSourceTimestamp': null,
        'fetchedAt': null,
        'lastAttemptAt': null,
        'error': null,
      },
      'generatedAt': '2026-09-08T12:00:00Z',
    });
    expect(detail.secondaryPhone!.officialLabel, '대표전화2');
    expect(detail.secondaryPhone!.sourceField, 'dutyTel3');
    expect(detail.realtimeView.beds.numericValue, 0);
    expect(detail.realtimeView.reference.numericValue, isNull);
    expect(detail.basicInfo.fetchStatus, 'NOT_REQUESTED');
  });

  test('HVS01 is selected by source field and totalCount is preserved', () {
    final json = <String, dynamic>{
      'hpid': 'TEST',
      'name': '테스트',
      'emergencyClass': {'code': 'A', 'name': '분류'},
      'location': {'latitude': 37, 'longitude': 127},
      'distanceFromCenterMeters': 1,
      'distanceFromUserMeters': null,
      'realtime': {
        'coverageStatus': 'LIVE_AVAILABLE',
        'refreshStatus': 'UPDATED',
        'availableBeds': {
          'interpretationStatus': 'KNOWN',
          'numericValue': 2,
          'rawValue': '2',
          'sourceField': 'hvec',
        },
        'referenceResources': [
          {
            'interpretationStatus': 'KNOWN',
            'numericValue': 99,
            'rawValue': '99',
            'sourceField': 'OTHER',
          },
          {
            'interpretationStatus': 'KNOWN',
            'numericValue': 7,
            'rawValue': '7',
            'sourceField': 'HVS01',
            'officialLabel': '일반_기준',
          },
        ],
        'freshness': {
          'stale': false,
          'source': {'sourceRawTimestamp': null},
          'fetchedAt': null,
        },
        'error': null,
      },
    };
    final hospital = HospitalSummary.fromJson(json);
    expect(hospital.reference.numericValue, 7);
    expect(hospital.reference.officialLabel, '일반_기준');
    final result = HospitalSearchResult(
      [hospital],
      10000,
      false,
      false,
      const [],
      totalCount: 8,
    );
    expect(result.totalCount, 8);
  });
}
