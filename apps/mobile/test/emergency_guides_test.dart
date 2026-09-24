import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eroute_mobile/app/router.dart';
import 'package:eroute_mobile/core/theme/eroute_theme.dart';
import 'package:eroute_mobile/features/app_menu/app_session.dart';
import 'package:eroute_mobile/features/emergency_call/emergency_dialer.dart';
import 'package:eroute_mobile/features/emergency_guides/data/asset_guide_repository.dart';
import 'package:eroute_mobile/features/emergency_guides/data/guide_source_launcher.dart';
import 'package:eroute_mobile/features/emergency_guides/domain/guide_article.dart';
import 'package:eroute_mobile/features/emergency_guides/presentation/guide_pages.dart';
import 'package:eroute_mobile/features/emergency_map/presentation/emergency_map_controller.dart';
import 'package:eroute_mobile/features/member_ui/member_contract.dart';

class FilesBundle extends CachingAssetBundle {
  final requests = <String>[];
  final replacements = <String, String>{};
  final missing = <String>{};
  @override
  Future<ByteData> load(String key) async {
    requests.add(key);
    if (missing.contains(key)) throw FlutterError('Missing test asset: $key');
    if (replacements.containsKey(key)) {
      return ByteData.sublistView(
        Uint8List.fromList(utf8.encode(replacements[key]!)),
      );
    }
    if (File(key).existsSync()) {
      return ByteData.sublistView(File(key).readAsBytesSync());
    }
    return rootBundle.load(key);
  }

  // Avoid real async IO in widget tests and exercise repository caching itself.
  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    requests.add(key);
    return replacements[key] ?? File(key).readAsStringSync();
  }
}

class FailingSourceLauncher implements GuideSourceLauncher {
  int calls = 0;
  @override
  Future<bool> open(Uri uri) async {
    calls++;
    return false;
  }
}

class WaitingSession implements SessionSource {
  final Completer<Map<String, dynamic>?> result = Completer();
  @override
  Future<Map<String, dynamic>?> restore() => result.future;
  @override
  Future<bool> signOut() async => false;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FilesBundle bundle;
  late AssetGuideRepository repo;
  late MockEmergencyDialer dialer;
  var nativeCalls = 0;
  const manifestPath = '$guideAssetRoot/manifest.json';
  const aidPath = '$guideAssetRoot/first-aid.json';
  setUp(() {
    PaintingBinding.instance.imageCache.clear();
    SharedPreferences.setMockInitialValues({});
    bundle = FilesBundle();
    repo = AssetGuideRepository(bundle, reviewEnabled: true);
    dialer = MockEmergencyDialer();
    nativeCalls = 0;
    for (final name in [
      'eroute/emergency_dialer',
      'plugins.flutter.io/url_launcher',
      'eroute/privacy',
      'flutter.baseflow.com/geolocator',
      'flutter_naver_map',
    ]) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(name),
        (call) async {
          nativeCalls++;
          fail('Guide must not invoke $name / ${call.method}');
        },
      );
    }
  });
  tearDown(() => expect(nativeCalls, 0));
  Future<void> mount(
    WidgetTester tester,
    Widget page, {
    AppSession session = const AppSession.signedOut(),
    Size size = const Size(430, 932),
    double scale = 1,
    bool dark = false,
    GuideSourceLauncher? launcher,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          guideRepositoryProvider.overrideWithValue(repo),
          sessionProvider.overrideWithValue(session),
          emergencyDialerProvider.overrideWithValue(dialer),
          memberUiRepositoryProvider.overrideWith(
            (ref) => throw StateError('No health read'),
          ),
          hospitalRepositoryProvider.overrideWith(
            (ref) => throw StateError('No hospital call'),
          ),
          locationServiceProvider.overrideWith(
            (ref) => throw StateError('No GPS initialization'),
          ),
          if (launcher != null)
            guideSourceLauncherProvider.overrideWithValue(launcher),
        ],
        child: DefaultAssetBundle(
          bundle: bundle,
          child: MaterialApp(
            theme: dark ? ERouteTheme.dark() : ERouteTheme.light(),
            onGenerateRoute: buildAppRoute,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: page,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test(
    '17 canonical drafts load offline with complete metadata and no approval',
    () async {
      final catalog = await repo.catalog();
      expect(catalog.entries.length, 17);
      expect(
        catalog.entries.where((e) => e.category == 'EMERGENCY_ACTION').length,
        4,
      );
      expect(
        catalog.entries.where((e) => e.category == 'FIRST_AID').length,
        13,
      );
      expect(catalog.articles.length, 17);
      expect(catalog.unavailableIds, isEmpty);
      for (final entry in catalog.entries) {
        final article = (await repo.article(entry.id))!;
        expect(article.contentStatus, guideContentStatus);
        expect(article.humanReviewedAtUtc, isNull);
        expect(article.source.checkedAt, '2026-09-22');
        expect(allowedGuideSource(Uri.parse(article.source.url)), isTrue);
        expect(article.source.publisher, '소방청');
        expect(article.source.title, isNotEmpty);
        expect(
          article.source.publishedAt,
          entry.category == 'FIRST_AID' ? isNotNull : isNull,
        );
        expect(
          article.sections.any((s) => s.type == GuideSectionType.actionSteps),
          isTrue,
        );
        for (final alias in entry.aliases) {
          expect((await repo.article(alias))!.id, entry.id);
        }
      }
      expect(bundle.requests.toSet(), {
        manifestPath,
        '$guideAssetRoot/emergency-actions.json',
        aidPath,
      });
      final count = bundle.requests.length;
      await repo.catalog();
      expect(bundle.requests.length, count);
    },
  );

  test(
    'packaged rootBundle reads every body on first load without repository/network fixtures',
    () async {
      final packaged = AssetGuideRepository(rootBundle);
      final catalog = await packaged.catalog();
      expect(catalog.articles.length, 17);
      expect(
        (await packaged.article(
          'FIRST_AID_CHOKING_INFANT',
        ))!.sections.first.items,
        ['등 두드리기 5회', '가슴 밀어내기 5회', '반복', '의식 소실 시 CPR'],
      );
    },
  );

  test('unsafe IDs and disabled review routes fail before reading', () async {
    for (final id in [
      '../adult-cpr',
      '%2e%2e',
      'https://x',
      'a/b',
      '',
      'adult-cpr?review=true',
    ]) {
      await expectLater(repo.article(id), throwsFormatException);
    }
    await expectLater(
      AssetGuideRepository(
        bundle,
        reviewEnabled: false,
      ).article('adult-cpr', review: true),
      throwsFormatException,
    );
    expect(bundle.requests, isEmpty);
  });

  test(
    'unknown section and empty actions cannot render a partial medical procedure',
    () async {
      final rows = jsonDecode(File(aidPath).readAsStringSync()) as List;
      rows[0]['sections'][0]['type'] = 'UNKNOWN';
      rows[1]['sections'][0]['steps'] = [];
      bundle.replacements[aidPath] = jsonEncode(rows);
      final catalog = await repo.catalog();
      expect(catalog.unavailableIds, {'FIRST_AID_CPR_ADULT', 'FIRST_AID_AED'});
      expect(await repo.article('adult-cpr'), isNull);
      expect(await repo.article('FIRST_AID_BURN'), isNotNull);
      bundle.replacements.remove(aidPath);
      expect(await repo.article('adult-cpr'), isNotNull);
    },
  );

  test('manifest errors retry and malformed metadata is rejected', () async {
    bundle.replacements[manifestPath] = '{}';
    await expectLater(repo.catalog(), throwsFormatException);
    bundle.replacements.remove(manifestPath);
    expect((await repo.catalog()).entries.length, 17);
    final raw =
        (jsonDecode(File(aidPath).readAsStringSync()) as List).first
            as Map<String, dynamic>;
    for (final patch in <Map<String, dynamic>>[
      {'sourceOrganization': ''},
      {'title': ''},
      {'sourceCheckedAt': '2026-02-30'},
      {'contentStatus': 'OTHER'},
      {'humanReviewedAtUtc': '2026-09-22T00:00:00Z'},
      {'publicationDate': null},
      {'license': 'GUESSED'},
    ]) {
      expect(
        () => GuideArticle.fromJson({...raw, ...patch}),
        throwsFormatException,
      );
    }
    expect(
      GuideArticle.fromJson({...raw, 'license': 'UNCONFIRMED'}).source.license,
      'UNCONFIRMED',
    );
  });

  test('source launcher allows only official HTTPS', () async {
    expect(allowedGuideSource(Uri.parse('https://www.nfa.go.kr/nfa/')), isTrue);
    for (final url in [
      'tel:119',
      'sms:119',
      'javascript:alert(1)',
      'http://www.nfa.go.kr',
      'https://www.nfa.go.kr.evil.test',
      'https://evil@www.nfa.go.kr',
      'https://www.nfa.go.kr:8443',
    ]) {
      expect(allowedGuideSource(Uri.parse(url)), isFalse);
      expect(
        await const HttpsGuideSourceLauncher().open(Uri.parse(url)),
        isFalse,
      );
    }
  });

  for (final phase in [
    SessionPhase.signedOut,
    SessionPhase.restoring,
    SessionPhase.temporarilyUnavailable,
    SessionPhase.authenticated,
  ]) {
    testWidgets(
      'lists/details remain public in $phase without health/GPS/Backend',
      (tester) async {
        final session = AppSession(
          phase: phase,
          user: phase == SessionPhase.authenticated
              ? {
                  'userId': 'GUIDE_TEST_ONLY',
                  'phone': 'TEST ONLY',
                  'healthConsent': false,
                }
              : null,
        );
        for (final category in ['actions', 'firstAid']) {
          await mount(
            tester,
            GuideIndexPage(category: category),
            session: session,
          );
          final title = category == 'actions' ? '119에 알려줄 내용' : '성인 심폐소생술';
          await tester.ensureVisible(find.text(title));
          await tester.tap(find.text(title));
          await tester.pumpAndSettle();
          expect(find.text('지금 해야 할 일'), findsOneWidget);
          expect(find.text('본문 준비 중'), findsNothing);
          await tester.tap(find.byTooltip('뒤로 가기'));
          await tester.pumpAndSettle();
          expect(
            find.text(category == 'actions' ? '응급상황 대처요령' : '응급처치 가이드'),
            findsOneWidget,
          );
        }
      },
    );
  }

  testWidgets(
    '119 accessible CTA cancel and confirm use the existing mock once',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await mount(tester, const GuideDetailPage(id: 'FIRST_AID_CPR_ADULT'));
      final call = find.widgetWithText(OutlinedButton, '119 전화 연결');
      expect(find.bySemanticsLabel('119 전화 연결'), findsOneWidget);
      await tester.ensureVisible(call);
      await tester.tap(call);
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(dialer.requests, isEmpty);
      await tester.tap(call);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '119 전화 연결'));
      await tester.pumpAndSettle();
      expect(dialer.requests, ['119']);
      semantics.dispose();
    },
  );

  testWidgets(
    'source failure retains body and disclosure has metadata without long URL',
    (tester) async {
      final launcher = FailingSourceLauncher();
      await mount(
        tester,
        const GuideDetailPage(id: 'FIRST_AID_CPR_ADULT'),
        launcher: launcher,
      );
      final source = find.text('공식 자료 보기').first;
      await tester.ensureVisible(source);
      await tester.tap(source);
      await tester.pumpAndSettle();
      expect(launcher.calls, 1);
      expect(find.textContaining('공식 자료를 열지 못했습니다'), findsOneWidget);
      expect(find.text('반응 확인'), findsOneWidget);
      final disclosure = find.text('출처 상세 정보').first;
      await tester.ensureVisible(disclosure);
      await tester.tap(disclosure);
      await tester.pumpAndSettle();
      expect(find.textContaining('공공누리 제1유형'), findsOneWidget);
      expect(find.textContaining('출처 확인일 2026.09.22'), findsOneWidget);
      expect(find.textContaining('boardId='), findsNothing);
      expect(find.text('출처 URL 복사'), findsOneWidget);
    },
  );

  testWidgets(
    'invalid source URL disables only source CTA and leaves all steps',
    (tester) async {
      final rows = jsonDecode(File(aidPath).readAsStringSync()) as List;
      rows[0]['sourceUrl'] = 'tel:119';
      bundle.replacements[aidPath] = jsonEncode(rows);
      await mount(tester, const GuideDetailPage(id: 'adult-cpr'));
      expect(find.text('반응 확인'), findsOneWidget);
      final disabled = tester.widget<TextButton>(
        find.widgetWithText(TextButton, '공식 자료를 열 수 없습니다'),
      );
      expect(disabled.onPressed, isNull);
      expect(find.text('119 전화 연결'), findsOneWidget);
    },
  );

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'all 17 details and both lists at 320dp scale $scale dark $dark',
        (tester) async {
          final semantics = tester.ensureSemantics();
          final catalog = await repo.catalog();
          for (final entry in catalog.entries) {
            await mount(
              tester,
              GuideDetailPage(key: ValueKey(entry.id), id: entry.id),
              dark: dark,
              scale: scale,
              size: const Size(320, 740),
            );
            expect(find.text(entry.title), findsWidgets);
            expect(find.bySemanticsLabel('119 전화 연결'), findsOneWidget);
            final first = catalog.articles[entry.id]!.sections
                .firstWhere((s) => s.type == GuideSectionType.actionSteps)
                .items
                .first;
            expect(find.bySemanticsLabel('1단계. $first'), findsOneWidget);
            expect(find.text('공식 출처'), findsOneWidget);
            expect(
              find.byType(GuideSafetyNotice),
              entry.category == 'FIRST_AID' ? findsOneWidget : findsNothing,
            );
            await tester.ensureVisible(find.text('출처 상세 정보').first);
            await tester.tap(find.text('출처 상세 정보').first);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.textContaining(entry.source.publisher), findsWidgets);
          }
          for (final category in ['actions', 'firstAid']) {
            await mount(
              tester,
              GuideIndexPage(category: category),
              dark: dark,
              scale: scale,
              size: const Size(320, 740),
            );
            expect(find.text('본문 준비 중'), findsNothing);
            expect(
              find
                  .byType(Image)
                  .evaluate()
                  .every((e) => (e.widget as Image).excludeFromSemantics),
              isTrue,
            );
            expect(tester.takeException(), isNull);
          }
          semantics.dispose();
        },
      );
    }
  }
}
