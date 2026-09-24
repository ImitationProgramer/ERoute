import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eroute_mobile/core/formatting/provider_time_formatter.dart';
import 'package:eroute_mobile/core/theme/eroute_theme.dart';
import 'package:eroute_mobile/core/widgets/eroute_skeleton.dart';
import 'package:eroute_mobile/features/hospital_detail/domain/hospital_detail.dart';
import 'package:eroute_mobile/features/hospital_detail/domain/hospital_actions.dart';
import 'package:eroute_mobile/features/hospital_detail/presentation/hospital_clinical_information.dart';
import 'package:eroute_mobile/features/hospital_detail/presentation/hospital_detail_page.dart';
import 'package:eroute_mobile/features/hospital_detail/presentation/hospital_detail_state.dart';
import 'package:eroute_mobile/features/emergency_map/presentation/emergency_map_controller.dart';
import 'hospital_detail_test.dart'
    show detailJson, DeferredDetailRepository, seededMap, RecordingContact;
import 'main_flow_test.dart' show captureQa;

Map<String, dynamic> clinicalJson({
  String dataStatus = 'PROVIDED',
  String fetchStatus = 'SUCCESS',
  String refresh = 'CACHE_HIT',
  bool stale = false,
}) => {
  'fetchStatus': fetchStatus,
  'dataStatus': dataStatus,
  'refreshStatus': refresh,
  'departmentsStatus': dataStatus == 'PROVIDED' ? 'KNOWN' : 'MISSING',
  'departments': dataStatus == 'PROVIDED'
      ? [
          for (final name in ['내과', '외과', '응급의학과'])
            {'name': name, 'source': 'NMC', 'interpretationStatus': 'KNOWN'},
        ]
      : [],
  'operatingHours': [
    for (final day in HospitalClinicalInformation.days.keys)
      {
        'day': day,
        'status': dataStatus == 'PROVIDED' && !['SUN', 'HOLIDAY'].contains(day)
            ? 'KNOWN'
            : 'MISSING',
        'open': '09:00',
        'close': '17:30',
      },
  ],
  'stale': stale,
  'fetchedAt': dataStatus == 'PROVIDED' ? '2026-09-13T06:18:00Z' : null,
};
HospitalDetail data(Map<String, dynamic> basic) =>
    HospitalDetail.fromJson({...detailJson(), 'basicInfo': basic});
HospitalDetailState state(AsyncValue<HospitalDetail> response) =>
    HospitalDetailState(
      hpid: 'TEST_ONLY',
      searchHospital: null,
      searchSource: null,
      tab: HospitalDetailTab.clinical,
      detail: response,
    );

void main() {
  setUpAll(() async {
    await (FontLoader(
      'NotoSansKR',
    )..addFont(rootBundle.load('assets/fonts/NotoSansKR.ttf'))).load();
  });
  test('provider wall clock never acquires a timezone', () {
    expect(formatProviderWallTime('2026-09-13T15:15:33'), '2026.09.13 15:15');
    for (final value in [
      null,
      '20260913151533',
      '2026-02-30T15:15',
      '2026-09-13T25:00',
      '2026-09-13T15:15Z',
      '2026-09-13T15:15+09:00',
    ]) {
      expect(formatProviderWallTime(value), isNull);
    }
  });
  for (final entry in {
    '수집 전': (
      clinicalJson(dataStatus: 'NOT_COLLECTED', fetchStatus: 'NOT_REQUESTED'),
      '병원 진료정보를 아직 수집하지 못했습니다.',
    ),
    '원천 미제공': (clinicalJson(dataStatus: 'NOT_PROVIDED'), '진료과목 정보 미제공'),
    '최초 실패': (
      clinicalJson(
        dataStatus: 'NOT_COLLECTED',
        fetchStatus: 'ERROR',
        refresh: 'ERROR',
      ),
      '병원 진료정보를 수집하지 못했습니다.',
    ),
    '이전 값 유지': (
      clinicalJson(fetchStatus: 'ERROR', refresh: 'ERROR', stale: true),
      '갱신 실패 · 이전 정보',
    ),
    '예산 대기': (
      clinicalJson(refresh: 'BUDGET_DEFERRED', stale: true),
      '갱신 대기 · 이전 정보',
    ),
  }.entries) {
    testWidgets('clinical status ${entry.key}', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HospitalClinicalInformation(
                state: state(AsyncData(data(entry.value.$1))),
              ),
            ),
          ),
        ),
      );
      expect(find.text(entry.value.$2), findsOneWidget);
      expect(find.byType(ERouteSkeleton), findsNothing);
      if (entry.value.$1['dataStatus'] == 'PROVIDED') {
        expect(find.text('내과'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('pending HTTP is distinct from not provided', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HospitalClinicalInformation(state: state(const AsyncLoading())),
        ),
      ),
    );
    expect(find.byType(ERouteSkeleton), findsOneWidget);
    expect(find.text('진료과목 정보 미제공'), findsNothing);
  });
  for (final dark in [false, true]) {
    testWidgets(
      'eight days, uncertain hours, long list and large text: $dark',
      (tester) async {
        tester.view.physicalSize = const Size(430, 932);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final key = GlobalKey();
        final basic = clinicalJson();
        (basic['operatingHours'] as List)[1] = {
          'day': 'TUE',
          'status': 'UNVERIFIED',
          'open': '00:00',
          'close': '23:59',
        };
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? ERouteTheme.dark() : ERouteTheme.light(),
            home: RepaintBoundary(
              key: key,
              child: Scaffold(
                body: SafeArea(
                  child: SingleChildScrollView(
                    child: HospitalClinicalInformation(
                      state: state(AsyncData(data(basic))),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('요일별 보기'));
        await tester.tap(find.text('요일별 보기'));
        await tester.pumpAndSettle();
        expect(find.text('09:00 - 17:30'), findsAtLeastNWidgets(5));
        expect(find.text('정보 확인 필요'), findsAtLeastNWidgets(1));
        expect(find.text('00:00 - 23:59'), findsNothing);
        for (final label in HospitalClinicalInformation.days.values) {
          expect(find.text(label), findsOneWidget);
        }
        await captureQa(tester, key, 'clinical-${dark ? 'dark' : 'light'}');
        final long = clinicalJson();
        long['departments'] = List.generate(
          70,
          (i) => {
            'name': '긴 진료과목 표시 검증 $i',
            'source': 'NMC',
            'interpretationStatus': 'KNOWN',
          },
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? ERouteTheme.dark() : ERouteTheme.light(),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                body: SafeArea(
                  child: SingleChildScrollView(
                    child: HospitalClinicalInformation(
                      state: state(AsyncData(data(long))),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -700),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('tab switches and rebuilds share one backend request', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final repository = DeferredDetailRepository();
    final map = seededMap();
    final container = ProviderContainer(
      overrides: [
        hospitalDetailRepositoryProvider.overrideWithValue(repository),
        mapControllerProvider.overrideWith((ref) => map),
        hospitalContactLauncherProvider.overrideWithValue(RecordingContact()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ERouteTheme.light(),
          home: const HospitalDetailPage(hpid: 'TEST_ONLY'),
        ),
      ),
    );
    repository.requests.single.response.complete(data(clinicalJson()));
    await tester.pumpAndSettle();
    for (var i = 0; i < 6; i++) {
      container.read(hospitalDetailTabProvider('TEST_ONLY').notifier).state =
          i.isEven ? HospitalDetailTab.clinical : HospitalDetailTab.basic;
      await tester.pumpAndSettle();
    }
    expect(repository.requests.length, 1);
    expect(tester.takeException(), isNull);
  });
}
