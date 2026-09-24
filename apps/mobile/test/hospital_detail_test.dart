import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eroute_mobile/core/map/map_scene.dart';
import 'package:eroute_mobile/core/widgets/eroute_skeleton.dart';
import 'package:eroute_mobile/core/theme/eroute_theme.dart';
import 'package:eroute_mobile/features/emergency_map/domain/hospital_summary.dart';
import 'package:eroute_mobile/features/emergency_map/presentation/emergency_map_controller.dart';
import 'package:eroute_mobile/features/hospital_detail/data/remote_hospital_detail_repository.dart';
import 'package:eroute_mobile/features/hospital_detail/domain/hospital_actions.dart';
import 'package:eroute_mobile/features/hospital_detail/domain/hospital_detail.dart';
import 'package:eroute_mobile/features/hospital_detail/domain/hospital_detail_repository.dart';
import 'package:eroute_mobile/features/hospital_detail/presentation/hospital_detail_state.dart';
import 'package:eroute_mobile/features/hospital_detail/presentation/hospital_detail_page.dart';
import 'emergency_map_test.dart' as fixtures;
import 'main_flow_test.dart' show captureQa;

Map<String, dynamic> detailJson({
  String hpid = 'TEST_ONLY',
  String? address = '검증 주소',
  String? phone = '02-111-1111',
  String? secondary = '02-222-2222',
  String coverage = 'LIVE_AVAILABLE',
  bool stale = false,
}) => {
  'hpid': hpid,
  'name': '상세 병원 $hpid',
  'emergencyClass': {'code': 'A', 'name': '지역응급의료센터'},
  'address': address,
  'location': {'latitude': 37, 'longitude': 127},
  'mainPhone': phone == null
      ? null
      : {
          'sourceField': 'dutyTel1',
          'officialLabel': '대표전화1',
          'rawValue': phone,
        },
  'secondaryPhone': secondary == null
      ? null
      : {
          'sourceField': 'dutyTel3',
          'officialLabel': '대표전화2',
          'rawValue': secondary,
        },
  'masterUpdatedAt': '2026-09-08T12:00:00Z',
  'catalogVersion': 'test',
  'catalogFetchedAt': '2026-09-08T12:00:00Z',
  'catalogStale': false,
  'generatedAt': '2026-09-08T12:00:00Z',
  'basicInfo': {'fetchStatus': 'NOT_REQUESTED'},
  'realtime': {
    'coverageStatus': coverage,
    'refreshStatus': coverage == 'LIVE_ERROR' ? 'ERROR' : 'CACHE_HIT',
    'availableBeds': {
      'endpoint': 'getEmrrmRltmUsefulSckbdInfoInqire',
      'sourceField': 'hvec',
      'officialLabel': '일반',
      'interpretationStatus': coverage == 'LIVE_NOT_PROVIDED'
          ? 'NOT_PROVIDED'
          : 'KNOWN',
      'numericValue': coverage == 'LIVE_NOT_PROVIDED' ? null : 0,
      'rawValue': coverage == 'LIVE_NOT_PROVIDED' ? null : '0',
    },
    'referenceResources': [],
    'freshness': {
      'stale': stale,
      'source': {'sourceRawTimestamp': null},
      'fetchedAt': '2026-09-08T12:00:00Z',
    },
    'error': coverage == 'LIVE_ERROR' ? 'NMC_TIMEOUT' : null,
  },
};

class DetailAdapter implements HttpClientAdapter {
  final FutureOr<ResponseBody> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  DetailAdapter(this.respond);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return await respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(Object? json, [int status = 200]) =>
    ResponseBody.fromString(
      jsonEncode(json),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );

class DeferredDetailRepository implements HospitalDetailRepository {
  final requests = <({String hpid, Completer<HospitalDetail> response})>[];
  @override
  Future<HospitalDetail> get(String hpid) {
    final response = Completer<HospitalDetail>();
    requests.add((hpid: hpid, response: response));
    return response.future;
  }
}

class RecordingContact implements HospitalContactLauncher {
  final calls = <String>[];
  Completer<bool>? pending;
  bool available = true;
  @override
  HospitalActionAvailability get availability => available
      ? HospitalActionAvailability.available
      : HospitalActionAvailability.unavailable;
  @override
  Future<bool> openDialScreen(String phoneNumber) {
    calls.add(phoneNumber);
    return pending?.future ?? Future.value(true);
  }
}

EmergencyMapController seededMap() {
  final map = EmergencyMapController(
    fixtures.FakeRepository(),
    fixtures.FakeLocation(null),
  );
  map.snapshot = SearchPresentationSnapshot(
    center: const GeoPoint(37, 127),
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
  return map;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'NotoSansKR',
    )..addFont(rootBundle.load('assets/fonts/NotoSansKR.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  var nativeCalls = 0;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    nativeCalls = 0;
    for (final name in [
      'plugins.flutter.io/url_launcher',
      'eroute/emergency_dialer',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), (_) async {
            nativeCalls++;
            fail('Native phone launch is forbidden in tests');
          });
    }
  });
  tearDown(() => expect(nativeCalls, 0));
  test(
    'real repository deserializes HTTP JSON and uses exactly the requested HPID',
    () async {
      final adapter = DetailAdapter(
        (_) => jsonResponse(detailJson(hpid: 'A / B')),
      );
      final dio = Dio(BaseOptions(baseUrl: 'https://backend.invalid'))
        ..httpClientAdapter = adapter;
      final detail = await RemoteHospitalDetailRepository(dio).get('A / B');
      expect(adapter.requests.single.uri.pathSegments.last, 'A / B');
      expect(detail.address, '검증 주소');
      expect(detail.mainPhone!.rawValue, '02-111-1111');
      expect(detail.secondaryPhone!.sourceField, 'dutyTel3');
      expect(detail.classification, '지역응급의료센터');
      expect(detail.realtimeView.beds.numericValue, 0);
      expect(detail.basicInfo.fetchStatus, 'NOT_REQUESTED');
    },
  );

  for (final status in [404, 503]) {
    test('HTTP $status has an explicit failure', () async {
      final dio = Dio()
        ..httpClientAdapter = DetailAdapter((_) => jsonResponse({}, status));
      await expectLater(
        RemoteHospitalDetailRepository(dio).get('A'),
        throwsA(
          status == 404
              ? isA<HospitalDetailNotFound>()
              : isA<HospitalDetailFailure>().having(
                  (e) => e.kind,
                  'kind',
                  HospitalDetailFailureKind.unavailable,
                ),
        ),
      );
    });
  }
  for (final type in [
    DioExceptionType.connectionError,
    DioExceptionType.receiveTimeout,
  ]) {
    test('$type is finite and classified', () async {
      final dio = Dio()
        ..httpClientAdapter = DetailAdapter(
          (r) => throw DioException(requestOptions: r, type: type),
        );
      await expectLater(
        RemoteHospitalDetailRepository(dio).get('A'),
        throwsA(
          isA<HospitalDetailFailure>().having(
            (e) => e.kind,
            'kind',
            type == DioExceptionType.connectionError
                ? HospitalDetailFailureKind.network
                : HospitalDetailFailureKind.timeout,
          ),
        ),
      );
    });
  }
  for (final malformed in [
    null,
    [],
    {'hpid': 'TEST_ONLY'},
    detailJson()..['mainPhone'] = 'wrong shape',
    detailJson()..['generatedAt'] = 'bad date',
    detailJson(hpid: 'WRONG'),
  ]) {
    test(
      'malformed or mismatched response never becomes missing data: $malformed',
      () async {
        final dio = Dio()
          ..httpClientAdapter = DetailAdapter((_) => jsonResponse(malformed));
        await expectLater(
          RemoteHospitalDetailRepository(dio).get('TEST_ONLY'),
          throwsA(
            isA<HospitalDetailFailure>().having(
              (e) => e.kind,
              'kind',
              HospitalDetailFailureKind.invalidResponse,
            ),
          ),
        );
      },
    );
  }

  test('refresh error keeps previous data and immutable Map seed', () async {
    final repo = DeferredDetailRepository();
    final map = seededMap();
    final container = ProviderContainer(
      overrides: [
        mapControllerProvider.overrideWith((_) => map),
        hospitalDetailRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      hospitalDetailProvider('TEST_ONLY'),
      (_, _) {},
    );
    addTearDown(subscription.close);
    expect(
      container
          .read(hospitalDetailProvider('TEST_ONLY'))
          .realtime!
          .beds
          .numericValue,
      14,
    );
    repo.requests.single.response.complete(
      HospitalDetail.fromJson(detailJson()),
    );
    await container.read(hospitalDetailRequestProvider('TEST_ONLY').future);
    map.snapshot = null;
    map.notifyListeners();
    container.invalidate(hospitalDetailRequestProvider('TEST_ONLY'));
    final refreshed = container.read(
      hospitalDetailRequestProvider('TEST_ONLY').future,
    );
    repo.requests.last.response.completeError(
      const HospitalDetailFailure(HospitalDetailFailureKind.network),
    );
    await expectLater(refreshed, throwsA(isA<HospitalDetailFailure>()));
    final state = container.read(hospitalDetailProvider('TEST_ONLY'));
    expect(state.phase, HospitalDetailPhase.error);
    expect(state.loaded!.address, '검증 주소');
    expect(state.searchHospital!.centerDistance, 1400);
    expect(
      state.fieldStatus(state.loaded!.address),
      DetailFieldStatus.available,
    );
    expect(state.realtime!.beds.numericValue, 0);
  });

  test(
    'A/B response reversal and disposed A cannot replace B or resurrect A',
    () async {
      final repo = DeferredDetailRepository();
      final container = ProviderContainer(
        overrides: [hospitalDetailRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      final a = container.listen(hospitalDetailRequestProvider('A'), (_, _) {});
      final b = container.listen(hospitalDetailRequestProvider('B'), (_, _) {});
      addTearDown(b.close);
      a.close();
      await container.pump();
      repo.requests[1].response.complete(
        HospitalDetail.fromJson(detailJson(hpid: 'B')),
      );
      await container.read(hospitalDetailRequestProvider('B').future);
      repo.requests[0].response.complete(
        HospitalDetail.fromJson(detailJson(hpid: 'A')),
      );
      await container.pump();
      expect(
        container.read(hospitalDetailRequestProvider('B')).value!.hpid,
        'B',
      );
      final reopened = container.listen(
        hospitalDetailRequestProvider('A'),
        (_, _) {},
      );
      addTearDown(reopened.close);
      expect(repo.requests.length, 3);
      expect(
        container.read(hospitalDetailRequestProvider('A')).isLoading,
        isTrue,
      );
    },
  );

  Future<void> show(
    WidgetTester tester,
    HospitalDetailRepository repo,
    RecordingContact contact, {
    bool seed = true,
    GlobalKey? qaKey,
    Size size = const Size(430, 1100),
    double textScale = 1,
    bool dark = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final map = seededMap();
    if (!seed) map.snapshot = null;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mapControllerProvider.overrideWith((_) => map),
          hospitalDetailRepositoryProvider.overrideWithValue(repo),
          hospitalContactLauncherProvider.overrideWithValue(contact),
        ],
        child: RepaintBoundary(
          key: qaKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? ERouteTheme.dark() : ERouteTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: const HospitalDetailPage(hpid: 'TEST_ONLY'),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'HTTP 200 traverses repository, provider and screen without a DTO override',
    (tester) async {
      final adapter = DetailAdapter((_) => jsonResponse(detailJson()));
      final dio = Dio()..httpClientAdapter = adapter;
      await show(
        tester,
        RemoteHospitalDetailRepository(dio),
        RecordingContact(),
      );
      await tester.pumpAndSettle();
      expect(
        adapter.requests.single.path,
        '/api/v1/emergency-hospitals/TEST_ONLY',
      );
      expect(find.text('검증 주소'), findsWidgets);
      expect(find.text('02-111-1111'), findsWidgets);
      expect(find.text('02-222-2222'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '전화하기'))
            .onPressed,
        isNotNull,
      );
    },
  );

  for (final secondary in ['02-111-1111', '02-222-2222', null]) {
    testWidgets(
      'phone only appears in basic information, secondary=$secondary',
      (tester) async {
        final repo = DeferredDetailRepository();
        final contact = RecordingContact();
        await show(tester, repo, contact);
        repo.requests.single.response.complete(
          HospitalDetail.fromJson(detailJson(secondary: secondary)),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('02-111-1111'),
          secondary == '02-111-1111' ? findsNWidgets(2) : findsOneWidget,
        );
        final button = find.widgetWithText(OutlinedButton, '전화하기');
        final help = find.text('전화하기를 누르면 전화 앱의 번호 입력 화면을 엽니다.');
        expect(
          tester.getTopLeft(help).dy - tester.getBottomLeft(button).dy,
          lessThanOrEqualTo(9),
        );
        expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
        expect(find.text('대표전화'), findsOneWidget);
        expect(
          find.text('추가 전화번호'),
          secondary == null ? findsNothing : findsOneWidget,
        );
        expect(contact.calls, isEmpty);
      },
    );
  }

  testWidgets('visual state matrix never leaves a skeleton after completion', (
    tester,
  ) async {
    final repo = DeferredDetailRepository();
    final key = GlobalKey();
    await show(
      tester,
      repo,
      RecordingContact(),
      qaKey: key,
      size: const Size(430, 932),
    );
    await captureQa(tester, key, 'detail-loading');
    repo.requests.last.response.completeError(
      const HospitalDetailFailure(HospitalDetailFailureKind.network),
    );
    await tester.pumpAndSettle();
    await captureQa(tester, key, 'detail-error');
    await tester.tap(find.text('다시 시도'));
    await tester.pump();
    repo.requests.last.response.complete(
      HospitalDetail.fromJson(
        detailJson(address: null, phone: null, secondary: null),
      ),
    );
    await tester.pumpAndSettle();
    await captureQa(tester, key, 'detail-empty');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HospitalDetailPage)),
    );
    container.invalidate(hospitalDetailRequestProvider('TEST_ONLY'));
    container.read(hospitalDetailRequestProvider('TEST_ONLY'));
    await tester.pump();
    repo.requests.last.response.complete(HospitalDetail.fromJson(detailJson()));
    await tester.pumpAndSettle();
    await captureQa(tester, key, 'detail-success');
    container.invalidate(hospitalDetailRequestProvider('TEST_ONLY'));
    container.read(hospitalDetailRequestProvider('TEST_ONLY'));
    await tester.pump();
    repo.requests.last.response.completeError(
      const HospitalDetailFailure(HospitalDetailFailureKind.network),
    );
    await tester.pumpAndSettle();
    expect(find.text('검증 주소'), findsWidgets);
    expect(find.byType(ERouteSkeleton), findsNothing);
    await captureQa(tester, key, 'detail-refresh-error');
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('narrow large-text detail remains scrollable, dark=$dark', (
      tester,
    ) async {
      final repo = DeferredDetailRepository();
      final key = GlobalKey();
      await show(
        tester,
        repo,
        RecordingContact(),
        qaKey: key,
        size: const Size(360, 640),
        textScale: 1.8,
        dark: dark,
      );
      repo.requests.last.response.complete(
        HospitalDetail.fromJson(
          detailJson(address: '검증용 긴 주소입니다. '.padRight(180, '가')),
        ),
      );
      await tester.pumpAndSettle();
      await captureQa(
        tester,
        key,
        dark ? 'detail-dark-large-text' : 'detail-large-text',
      );
      await tester.scrollUntilVisible(
        find.text('추가 전화번호'),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('02-222-2222'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'loading retains Map beds; null completes as unavailable and hides secondary',
    (tester) async {
      final repo = DeferredDetailRepository();
      final contact = RecordingContact();
      await show(tester, repo, contact);
      expect(find.byType(ERouteSkeleton), findsWidgets);
      expect(find.text('14'), findsOneWidget);
      expect(find.text('테스트 응급의료기관'), findsOneWidget);
      expect(contact.calls, isEmpty);
      repo.requests.single.response.complete(
        HospitalDetail.fromJson(
          detailJson(address: null, phone: null, secondary: null),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ERouteSkeleton), findsNothing);
      expect(find.text('정보 미제공'), findsWidgets);
      expect(find.text('추가 전화번호'), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '전화하기'))
            .onPressed,
        isNull,
      );
      expect(find.text('0'), findsOneWidget);
    },
  );

  for (final failure in [
    const HospitalDetailNotFound('TEST_ONLY'),
    const HospitalDetailFailure(
      HospitalDetailFailureKind.unavailable,
      statusCode: 503,
    ),
    const HospitalDetailFailure(HospitalDetailFailureKind.network),
    const HospitalDetailFailure(HospitalDetailFailureKind.invalidResponse),
  ]) {
    testWidgets('failure ends skeleton and retry preserves summary: $failure', (
      tester,
    ) async {
      final repo = DeferredDetailRepository();
      await show(tester, repo, RecordingContact());
      repo.requests.single.response.completeError(failure);
      await tester.pumpAndSettle();
      expect(find.byType(ERouteSkeleton), findsNothing);
      expect(find.text('테스트 응급의료기관'), findsOneWidget);
      expect(find.text('14'), findsOneWidget);
      expect(find.text('정보를 불러오지 못했습니다'), findsWidgets);
      await tester.tap(find.text('다시 시도'));
      await tester.pump();
      expect(repo.requests.length, 2);
      expect(find.byType(ERouteSkeleton), findsWidgets);
    });
  }

  testWidgets('deep-link 404 has a finite empty state', (tester) async {
    final repo = DeferredDetailRepository();
    await show(tester, repo, RecordingContact(), seed: false);
    repo.requests.single.response.completeError(
      const HospitalDetailNotFound('TEST_ONLY'),
    );
    await tester.pumpAndSettle();
    expect(find.text('병원 정보를 찾을 수 없습니다'), findsOneWidget);
    expect(find.text('지도에서 찾기'), findsOneWidget);
    expect(find.byType(ERouteSkeleton), findsNothing);
  });

  for (final number in [
    '119',
    '112',
    '+119',
    '+1-1-2',
    '(119)',
    '02-CALL',
    '',
  ]) {
    testWidgets(
      'invalid hospital number cannot reach even a fake launcher: $number',
      (tester) async {
        final repo = DeferredDetailRepository();
        final contact = RecordingContact();
        await show(tester, repo, contact);
        repo.requests.single.response.complete(
          HospitalDetail.fromJson(detailJson(phone: number)),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, '전화하기'),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.text('전화하기'));
        expect(contact.calls, isEmpty);
      },
    );
  }

  testWidgets(
    'valid number reaches fake only after tap, busy blocks duplicates and failure recovers',
    (tester) async {
      final repo = DeferredDetailRepository();
      final contact = RecordingContact()..pending = Completer<bool>();
      await show(tester, repo, contact);
      repo.requests.single.response.complete(
        HospitalDetail.fromJson(detailJson()),
      );
      await tester.pumpAndSettle();
      expect(contact.calls, isEmpty);
      expect(find.text('검증 주소'), findsWidgets);
      expect(find.text('추가 전화번호'), findsOneWidget);
      await tester.tap(find.text('전화하기'));
      await tester.pump();
      await tester.tap(find.text('전화하기'));
      expect(contact.calls, ['02-111-1111']);
      contact.pending!.complete(false);
      await tester.pumpAndSettle();
      expect(find.text('전화 앱을 열 수 없습니다. 번호를 직접 입력해주세요.'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '전화하기'))
            .onPressed,
        isNotNull,
      );
    },
  );

  for (final coverage in [
    'LIVE_AVAILABLE',
    'LIVE_NOT_PROVIDED',
    'LIVE_ERROR',
  ]) {
    test('realtime meaning survives detail state: $coverage', () {
      final data = HospitalDetail.fromJson(
        detailJson(coverage: coverage, stale: coverage == 'LIVE_ERROR'),
      );
      final state = HospitalDetailState(
        hpid: data.hpid,
        searchHospital: fixtures.hospital(),
        searchSource: 'GPS',
        tab: HospitalDetailTab.basic,
        detail: AsyncData(data),
      );
      expect(state.realtime!.coverage, coverage);
      expect(
        state.realtime!.beds.numericValue,
        coverage == 'LIVE_NOT_PROVIDED' ? null : 0,
      );
      expect(
        state.phase,
        coverage == 'LIVE_AVAILABLE'
            ? HospitalDetailPhase.dataAvailable
            : HospitalDetailPhase.partialData,
      );
    });
  }
}
