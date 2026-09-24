import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eroute_mobile/core/theme/eroute_theme.dart';
import 'package:eroute_mobile/features/emergency_map/presentation/emergency_map_controller.dart';
import 'package:eroute_mobile/features/hospital_detail/domain/hospital_actions.dart';
import 'package:eroute_mobile/features/hospital_detail/domain/hospital_detail.dart';
import 'package:eroute_mobile/features/hospital_detail/domain/hospital_detail_repository.dart';
import 'package:eroute_mobile/features/hospital_detail/presentation/hospital_detail_page.dart';
import 'package:eroute_mobile/features/hospital_detail/presentation/hospital_detail_state.dart';
import 'hospital_detail_test.dart' show detailJson, seededMap, RecordingContact;
import 'main_flow_test.dart' show captureQa;

class NavigationDetailRepository implements HospitalDetailRepository {
  final Map<String, dynamic> json;
  NavigationDetailRepository(this.json);
  @override
  Future<HospitalDetail> get(String hpid) async =>
      HospitalDetail.fromJson(json);
}

class RecordingNavigation implements HospitalNavigationLauncher {
  final calls = <(double?, double?, String)>[];
  HospitalNavigationResult result = HospitalNavigationResult.opened;
  Completer<HospitalNavigationResult>? pending;
  bool storeResult = true;
  bool throws = false;
  int stores = 0;
  @override
  HospitalActionAvailability get availability =>
      HospitalActionAvailability.available;
  @override
  Future<HospitalNavigationResult> openNavigation(
    double? lat,
    double? lng,
    String name,
  ) async {
    calls.add((lat, lng, name));
    if (throws) throw StateError('test');
    return pending != null ? pending!.future : result;
  }

  @override
  Future<bool> openStore() async {
    stores++;
    return storeResult;
  }
}

Future<void> showNavigationDetail(
  WidgetTester tester, {
  HospitalNavigationLauncher launcher =
      const SystemHospitalNavigationLauncher(),
  Map<String, dynamic>? json,
  RecordingContact? contact,
  bool dark = false,
  double scale = 1,
  GlobalKey? captureKey,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mapControllerProvider.overrideWith((_) => seededMap()),
        hospitalDetailRepositoryProvider.overrideWithValue(
          NavigationDetailRepository(json ?? detailJson()),
        ),
        hospitalContactLauncherProvider.overrideWithValue(
          contact ?? RecordingContact(),
        ),
        hospitalNavigationLauncherProvider.overrideWithValue(launcher),
      ],
      child: RepaintBoundary(
        key: captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? ERouteTheme.dark() : ERouteTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const HospitalDetailPage(hpid: 'TEST_ONLY'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const system = SystemHospitalNavigationLauncher();
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final native = <MethodCall>[];
  bool installed = true, succeeds = true, nativeThrows = false;
  setUpAll(() async {
    await (FontLoader(
      'NotoSansKR',
    )..addFont(rootBundle.load('assets/fonts/NotoSansKR.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() {
    installed = succeeds = true;
    nativeThrows = false;
    native.clear();
    PackageInfo.setMockInitialValues(
      appName: 'ERoute',
      packageName: 'com.eroute.eroute_mobile.preview',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          native.add(call);
          if (nativeThrows) throw PlatformException(code: 'test');
          return call.method == 'canLaunch' ? installed : succeeds;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test(
    'navigation encodes Korean, space and reserved characters with only destination and identity',
    () {
      const name = '서울 병원 & 응급센터+#?/%';
      final uri = hospitalNavigationUri(
        latitude: 37.5,
        longitude: 127,
        hospitalName: name,
        appIdentifier: 'com.eroute.eroute_mobile',
      )!;
      expect(uri.scheme, 'nmap');
      expect(uri.host, 'navigation');
      expect(uri.queryParameters, {
        'dlat': '37.5',
        'dlng': '127.0',
        'dname': name,
        'appname': 'com.eroute.eroute_mobile',
      });
      expect(uri.toString(), contains('dname=${Uri.encodeComponent(name)}'));
      expect(uri.toString(), isNot(contains('+')));
      expect(
        hospitalNavigationUri(
          latitude: 37,
          longitude: 127,
          hospitalName: name,
          appIdentifier: '',
        ),
        isNull,
      );
    },
  );
  for (final point in <(double?, double?)>[
    (null, 127),
    (37, null),
    (double.nan, 127),
    (37, double.infinity),
    (0, 0),
    (31.42, 127),
    (44.36, 127),
    (37, 122.36),
    (37, 132.01),
  ]) {
    test('invalid $point never checks installation or launches', () async {
      expect(
        hospitalNavigationUri(
          latitude: point.$1,
          longitude: point.$2,
          hospitalName: '병원',
          appIdentifier: 'com.eroute.eroute_mobile',
        ),
        isNull,
      );
      expect(
        await system.openNavigation(point.$1, point.$2, '병원'),
        HospitalNavigationResult.invalidLocation,
      );
      expect(native, isEmpty);
    });
  }
  test('documented coordinate boundaries are accepted', () {
    expect(validHospitalNavigationLocation(31.43, 122.37), isTrue);
    expect(validHospitalNavigationLocation(44.35, 132), isTrue);
  });
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      '$platform checks scheme before launch and uses runtime identity',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        final identity = platform == TargetPlatform.android
            ? 'com.eroute.eroute_mobile.preview'
            : 'com.eroute.erouteMobile';
        PackageInfo.setMockInitialValues(
          appName: 'ERoute',
          packageName: identity,
          version: '1',
          buildNumber: '1',
          buildSignature: '',
        );
        expect(
          await system.openNavigation(37, 127, '서울 병원'),
          HospitalNavigationResult.opened,
        );
        expect(native.map((c) => c.method), ['canLaunch', 'launch']);
        expect(
          Uri.parse(native.last.arguments['url']).queryParameters['appname'],
          identity,
        );
        expect(native.last.arguments['useWebView'], false);
        expect(native.last.arguments['useSafariVC'], false);
      },
    );
    test('$platform official store fallback', () async {
      debugDefaultTargetPlatformOverride = platform;
      expect(await system.openStore(), isTrue);
      expect(
        native.single.arguments['url'],
        platform == TargetPlatform.android
            ? 'https://play.google.com/store/apps/details?id=com.nhn.android.nmap'
            : 'https://apps.apple.com/kr/app/id311867728',
      );
    });
  }
  test(
    'missing app does not launch; native failures remain failures',
    () async {
      installed = false;
      expect(
        await system.openNavigation(37, 127, '병원'),
        HospitalNavigationResult.notInstalled,
      );
      expect(native.single.method, 'canLaunch');
      installed = true;
      succeeds = false;
      expect(
        await system.openNavigation(37, 127, '병원'),
        HospitalNavigationResult.failed,
      );
      expect(await system.openStore(), false);
      nativeThrows = true;
      expect(
        await system.openNavigation(37, 127, '병원'),
        HospitalNavigationResult.failed,
      );
      expect(await system.openStore(), false);
    },
  );
  for (final location in [
    null,
    <String, dynamic>{},
    {'latitude': 37},
    {'latitude': 'bad', 'longitude': 127},
    {'latitude': 0, 'longitude': 0},
    {'latitude': double.nan, 'longitude': 127},
  ]) {
    testWidgets(
      'missing/invalid location preserves detail and phone: $location',
      (tester) async {
        final launcher = RecordingNavigation();
        final contact = RecordingContact();
        await showNavigationDetail(
          tester,
          launcher: launcher,
          contact: contact,
          json: detailJson()..['location'] = location,
        );
        expect(find.text('상세 병원 TEST_ONLY'), findsOneWidget);
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, '네이버 지도에서 열기'),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.text('네이버 지도에서 열기'));
        expect(launcher.calls, isEmpty);
        await tester.tap(find.text('전화하기'));
        expect(contact.calls, ['02-111-1111']);
      },
    );
  }
  testWidgets(
    'installed opens once, no confirmation, busy disables duplicates',
    (tester) async {
      final launcher = RecordingNavigation()..pending = Completer();
      await showNavigationDetail(tester, launcher: launcher);
      await tester.tap(find.text('네이버 지도에서 열기'));
      await tester.pump();
      await tester.tap(find.text('네이버 지도에서 열기'));
      expect(launcher.calls, [(37.0, 127.0, '상세 병원 TEST_ONLY')]);
      expect(find.byType(AlertDialog), findsNothing);
      launcher.pending!.complete(HospitalNavigationResult.opened);
      await tester.pumpAndSettle();
    },
  );
  for (final install in [false, true]) {
    testWidgets(
      'missing app ${install ? 'install' : 'cancel'} preserves detail',
      (tester) async {
        final launcher = RecordingNavigation()
          ..result = HospitalNavigationResult.notInstalled;
        await showNavigationDetail(tester, launcher: launcher);
        await tester.tap(find.text('네이버 지도에서 열기'));
        await tester.pumpAndSettle();
        expect(find.text('네이버 지도가 필요합니다'), findsOneWidget);
        expect(find.text('길 안내를 보려면 네이버 지도 앱이 필요합니다.'), findsOneWidget);
        await tester.tap(find.text(install ? '설치하기' : '취소'));
        await tester.pumpAndSettle();
        expect(launcher.stores, install ? 1 : 0);
        expect(find.byType(HospitalDetailPage), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
      },
    );
  }
  for (final failure in ['launch', 'throw', 'store']) {
    testWidgets('$failure shows feedback and releases busy state', (
      tester,
    ) async {
      final launcher = RecordingNavigation()
        ..result = failure == 'store'
            ? HospitalNavigationResult.notInstalled
            : HospitalNavigationResult.failed
        ..throws = failure == 'throw'
        ..storeResult = false;
      await showNavigationDetail(tester, launcher: launcher);
      await tester.tap(find.text('네이버 지도에서 열기'));
      await tester.pumpAndSettle();
      if (failure == 'store') {
        await tester.tap(find.text('설치하기'));
        await tester.pumpAndSettle();
      }
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, '네이버 지도에서 열기'),
            )
            .onPressed,
        isNotNull,
      );
    });
  }
  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'narrow 320 ${dark ? 'dark' : 'light'} ${scale}x CTA and dialog',
        (tester) async {
          tester.view.physicalSize = const Size(320, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final key = GlobalKey();
          await showNavigationDetail(
            tester,
            launcher: RecordingNavigation()
              ..result = HospitalNavigationResult.notInstalled,
            dark: dark,
            scale: scale,
            captureKey: key,
          );
          await tester.ensureVisible(find.text('네이버 지도에서 열기'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await captureQa(
            tester,
            key,
            'navigation-${dark ? 'dark' : 'light'}-${scale}x',
          );
          await tester.tap(find.text('네이버 지도에서 열기'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await captureQa(
            tester,
            key,
            'navigation-dialog-${dark ? 'dark' : 'light'}-${scale}x',
          );
          await tester.tap(find.text('취소'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
        },
      );
    }
  }
}
