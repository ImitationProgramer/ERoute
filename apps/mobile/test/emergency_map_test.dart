import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eroute_mobile/core/location/location_service.dart';
import 'package:eroute_mobile/core/location/location_fix.dart';
import 'package:eroute_mobile/core/location/heading_service.dart';
import 'package:eroute_mobile/features/emergency_call/emergency_dialer.dart';
import 'package:eroute_mobile/features/emergency_map/domain/hospital_repository.dart';
import 'package:eroute_mobile/features/emergency_map/domain/hospital_summary.dart';
import 'package:eroute_mobile/features/emergency_map/presentation/emergency_map_controller.dart';
import 'package:eroute_mobile/features/emergency_map/presentation/emergency_map_page.dart';
import 'package:eroute_mobile/features/emergency_map/presentation/widgets/hospital_list_tile.dart';

class FakeLocation implements LocationService {
  GeoPoint? value;
  FakeLocation(this.value);
  @override
  Future<LocationFix?> current() async =>
      value == null ? null : LocationFix(value!, measuredAt: DateTime.now());
}

class SilentHeading implements HeadingService {
  @override
  Stream<HeadingReading> watch() => const Stream.empty();
}

class FakeRepository implements HospitalRepository {
  int searchCount = 0;
  int totalCount = 1;
  final List<int?> requestedRadii = [];
  final List<Completer<HospitalSearchResult>> requests = [];
  bool deferred = false;
  @override
  Future<MapPolicy> policy() async => MapPolicy(
    [10000, 20000, 50000],
    10000,
    CoverageBounds(const GeoPoint(33, 124), const GeoPoint(39, 132)),
  );
  @override
  Future<HospitalSearchResult> search(
    GeoPoint center,
    String source,
    GeoPoint? user,
    int? radius,
  ) {
    searchCount++;
    requestedRadii.add(radius);
    if (deferred) {
      final c = Completer<HospitalSearchResult>();
      requests.add(c);
      return c.future;
    }
    return Future.value(
      HospitalSearchResult(
        [hospital()],
        radius ?? 10000,
        false,
        false,
        [],
        totalCount: totalCount,
      ),
    );
  }
}

HospitalSummary hospital({
  String beds = '14',
  String status = 'KNOWN',
  String coverage = 'LIVE_AVAILABLE',
  bool stale = false,
  String refresh = 'UPDATED',
  String? error,
  bool hasSnapshot = true,
}) => HospitalSummary(
  hpid: 'TEST_ONLY',
  name: '테스트 응급의료기관',
  classification: '지역응급의료센터',
  location: const GeoPoint(37, 127),
  centerDistance: 1400,
  userDistance: null,
  coverage: coverage,
  refresh: refresh,
  beds: ResourceValue(status, int.tryParse(beds), beds),
  reference: ResourceValue('KNOWN', 17, '17'),
  stale: stale,
  rawSourceTime: '20260908210000',
  fetchedAt: hasSnapshot ? DateTime.parse('2026-09-08T12:00:00Z') : null,
  error: error,
);
void main() {
  setUpAll(() async {
    final loader = FontLoader('NotoSansKR')
      ..addFont(rootBundle.load('assets/fonts/NotoSansKR.ttf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'no GPS still supports manual search without invented user location',
    () async {
      final c = EmergencyMapController(FakeRepository(), FakeLocation(null));
      await c.initialize();
      expect(c.center, isNull);
      expect(c.userLocation, isNull);
      c.moveCamera(const GeoPoint(37, 127));
      await c.searchHere();
      expect(c.source, 'MANUAL');
      expect(c.result!.hospitals.length, 1);
      expect(c.userLocation, isNull);
      c.dispose();
    },
  );
  test('late response cannot overwrite a newer search', () async {
    final repo = FakeRepository()..deferred = true;
    final c = EmergencyMapController(repo, FakeLocation(null));
    c.center = const GeoPoint(37, 127);
    final first = c.search();
    await Future<void>.delayed(Duration.zero);
    final second = c.search();
    await Future<void>.delayed(Duration.zero);
    repo.requests[1].complete(HospitalSearchResult([], 20000, true, false, []));
    await second;
    repo.requests[0].complete(
      HospitalSearchResult([hospital()], 10000, false, false, []),
    );
    await first;
    expect(c.result!.radius, 20000);
    expect(c.result!.hospitals, isEmpty);
    c.dispose();
  });
  test('unknown or missing numeric data never becomes zero', () {
    expect(ResourceValue('MISSING', null, null).display, '정보 미제공');
    expect(ResourceValue('KNOWN', 0, '0').display, '0');
    expect(ResourceValue('UNVERIFIED', -1, '-1').display, '확인 중');
  });
  testWidgets(
    'mapping, budget, absence and real failures have independent card labels',
    (tester) async {
      final cases = <(HospitalSummary, String)>[
        (
          hospital(
            coverage: 'LIVE_UNKNOWN',
            refresh: 'NOT_REQUESTED',
            error: 'REGION_MAPPING_ERROR',
            hasSnapshot: false,
            beds: '',
            status: 'MISSING',
          ),
          '실시간 정보를 불러오지 못했습니다.',
        ),
        (
          hospital(
            coverage: 'LIVE_UNKNOWN',
            refresh: 'BUDGET_DEFERRED',
            hasSnapshot: false,
            beds: '',
            status: 'MISSING',
          ),
          '갱신 대기',
        ),
        (
          hospital(
            coverage: 'LIVE_UNKNOWN',
            refresh: 'NOT_REQUESTED',
            hasSnapshot: false,
            beds: '',
            status: 'MISSING',
          ),
          '실시간 정보 확인 대기',
        ),
        (
          hospital(coverage: 'LIVE_NOT_PROVIDED', beds: '', status: 'MISSING'),
          '실시간 병상정보 미제공',
        ),
        (
          hospital(
            coverage: 'LIVE_ERROR',
            refresh: 'ERROR',
            hasSnapshot: false,
            beds: '',
            status: 'MISSING',
          ),
          '갱신 실패',
        ),
        (
          hospital(coverage: 'LIVE_ERROR', refresh: 'ERROR', stale: true),
          '갱신 실패 · 이전 정보',
        ),
        (hospital(beds: '0'), '병상정보 제공'),
      ];
      for (final (value, label) in cases) {
        expect(value.statusLabel, label);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HospitalListTile(
                hospital: value,
                manual: false,
                selected: false,
                onTap: () {},
              ),
            ),
          ),
        );
        expect(find.text(label), findsOneWidget);
        expect(find.textContaining('REGION_MAPPING_ERROR'), findsNothing);
        if (!label.contains('이전 정보')) {
          expect(find.textContaining('이전 정보'), findsNothing);
        }
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets('deferral explains its cause once and requires manual refresh', (
    tester,
  ) async {
    for (final reason in ['CALL_RATE_LIMIT', 'CALL_BUDGET_LIMIT']) {
      for (final previous in [false, true]) {
        final value = hospital(
          coverage: previous ? 'LIVE_AVAILABLE' : 'LIVE_UNKNOWN',
          refresh: 'BUDGET_DEFERRED',
          error: reason,
          hasSnapshot: previous,
          stale: true,
          beds: previous ? '14' : '',
          status: previous ? 'KNOWN' : 'MISSING',
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HospitalListTile(
                hospital: value,
                manual: true,
                selected: false,
                onTap: () {},
              ),
            ),
          ),
        );
        expect(find.text(value.statusLabel), findsOneWidget);
        expect(find.text(value.refreshGuidance!), findsOneWidget);
        expect(find.textContaining('지도에서 새로고침'), findsOneWidget);
        expect(find.textContaining('자동'), findsNothing);
        expect(find.textContaining('CALL_'), findsNothing);
        expect(value.statusLabel.contains('이전 정보'), previous);
        if (reason == 'CALL_BUDGET_LIMIT') {
          expect(find.textContaining('최근 24시간 조회 한도'), findsOneWidget);
        } else {
          expect(find.textContaining('요청이 몰려'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      }
    }
  });
  test('budget and API errors remain distinct', () {
    expect(
      hospital(stale: true, refresh: 'BUDGET_DEFERRED').statusLabel,
      '갱신 대기 · 이전 정보',
    );
    expect(
      hospital(stale: true, coverage: 'LIVE_ERROR').statusLabel,
      '갱신 실패 · 이전 정보',
    );
    expect(hospital(coverage: 'LIVE_NOT_PROVIDED').statusLabel, '실시간 병상정보 미제공');
  });
  testWidgets(
    'manual search labels HVS01 as a reference value and shows raw source time',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HospitalListTile(
              hospital: hospital(),
              manual: true,
              selected: false,
              onTap: () {},
            ),
          ),
        ),
      );
      expect(find.text('일반 병상 기준'), findsOneWidget);
      expect(find.text('검색 중심에서 직선거리'), findsOneWidget);
      expect(find.textContaining('제공기관 입력시각 확인 불가'), findsOneWidget);
      expect(find.textContaining('총병상'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('map screen renders same hospital result without native SDK', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hospitalRepositoryProvider.overrideWithValue(FakeRepository()),
          headingServiceProvider.overrideWithValue(SilentHeading()),
          emergencyDialerProvider.overrideWithValue(MockEmergencyDialer()),
          locationServiceProvider.overrideWithValue(
            FakeLocation(const GeoPoint(37, 127)),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'NotoSansKR',
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff16776e),
            ),
          ),
          home: RepaintBoundary(
            key: key,
            child: EmergencyMapPage(
              mapBuilder:
                  ({
                    required scene,
                    required onReady,
                    required onCameraIdle,
                    required onHospitalSelected,
                  }) => const ColoredBox(
                    color: Color(0xffe5ede7),
                    child: Center(
                      child: Icon(
                        Icons.local_hospital,
                        size: 42,
                        color: Color(0xff16776e),
                      ),
                    ),
                  ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('주변 응급의료기관'), findsOneWidget);
    expect(find.text('테스트 응급의료기관'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/qa/emergency-map.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
    });
  });
}
