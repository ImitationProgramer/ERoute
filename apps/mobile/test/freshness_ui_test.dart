import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eroute_mobile/core/theme/eroute_theme.dart';
import 'package:eroute_mobile/core/widgets/eroute_scaffold.dart';
import 'package:eroute_mobile/features/hospital_detail/domain/hospital_detail.dart';
import 'package:eroute_mobile/features/emergency_map/presentation/widgets/realtime_summary.dart';
import 'hospital_detail_test.dart' show detailJson;

void main() {
  for (final source in ['TIMEZONE_UNVERIFIED', 'MISSING', 'UNPARSEABLE']) {
    testWidgets(
      'recent collection with $source never asserts source freshness',
      (tester) async {
        final json = detailJson();
        final f = json['realtime']['freshness'];
        f['sourceFreshness'] = 'UNKNOWN';
        f['lastAttemptAt'] = '2026-09-08T11:59:59Z';
        f['source'] = {
          'sourceRawTimestamp': source == 'MISSING' ? null : '20260908125855',
          'parsedSourceTimestamp': source == 'TIMEZONE_UNVERIFIED'
              ? '2026-09-08T12:58:55'
              : null,
          'sourceTimestampStatus': source,
        };
        final h = HospitalDetail.fromJson(json).realtimeView;
        await tester.pumpWidget(
          MaterialApp(
            theme: ERouteTheme.light(),
            home: Scaffold(body: RealtimeSummary(hospital: h)),
          ),
        );
        expect(find.text('병상정보 제공'), findsOneWidget);
        expect(find.text('원천 갱신시각 확인 필요'), findsOneWidget);
        expect(find.text('0'), findsOneWidget);
        expect(find.textContaining('ERoute 수집'), findsOneWidget);
        expect(h.lastAttemptAt, DateTime.utc(2026, 9, 8, 11, 59, 59));
        expect(h.stale, isFalse);
        expect(
          find.textContaining(
            source == 'TIMEZONE_UNVERIFIED' ? '시간대 미확인' : '입력시각 확인 불가',
          ),
          findsOneWidget,
        );
      },
    );
  }
  testWidgets(
    'verified stale source remains previous despite recent collection',
    (tester) async {
      // Presentation contract fixture only: current NMC normalizer never verifies a zone.
      final json = detailJson();
      final f = json['realtime']['freshness'];
      f['sourceFreshness'] = 'STALE';
      f['source'] = {
        'sourceTimestampStatus': 'VERIFIED',
        'parsedSourceTimestamp': '2026-09-07T12:00:00',
      };
      final h = HospitalDetail.fromJson(json).realtimeView;
      await tester.pumpWidget(
        MaterialApp(
          theme: ERouteTheme.light(),
          home: Scaffold(body: RealtimeSummary(hospital: h)),
        ),
      );
      expect(find.text('이전 정보'), findsOneWidget);
      expect(find.text('제공기관 갱신이 지연된 병상정보입니다.'), findsOneWidget);
      expect(find.text('병상정보 제공'), findsNothing);
    },
  );
  testWidgets('cache expiry reason is separate from unknown provider time', (
    tester,
  ) async {
    final json = detailJson(stale: true);
    json['realtime']['freshness']['staleReasons'] = ['CACHE_EXPIRED'];
    final h = HospitalDetail.fromJson(json).realtimeView;
    await tester.pumpWidget(
      MaterialApp(
        theme: ERouteTheme.light(),
        home: Scaffold(body: RealtimeSummary(hospital: h)),
      ),
    );
    expect(find.text('이전 정보'), findsOneWidget);
    expect(find.textContaining('수집 후 시간이 지나 이전 병상정보'), findsOneWidget);
    expect(find.textContaining('원천 갱신시각 확인 필요'), findsOneWidget);
  });
  testWidgets(
    'transparent public toolbar restores status icon contrast across themes',
    (tester) async {
      for (final dark in [false, true, false]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? ERouteTheme.dark() : ERouteTheme.light(),
            home: const Scaffold(appBar: ERouteTopBar(), body: Text('검증')),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          SystemChrome.latestStyle?.statusBarIconBrightness,
          dark ? Brightness.light : Brightness.dark,
        );
        expect(
          SystemChrome.latestStyle?.statusBarBrightness,
          dark ? Brightness.dark : Brightness.light,
        );
      }
    },
  );
}
