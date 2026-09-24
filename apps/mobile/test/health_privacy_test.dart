import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:eroute_mobile/core/theme/eroute_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:eroute_mobile/features/member_health/health_draft.dart';
import 'package:eroute_mobile/features/member_health/member_health_page.dart';
import 'package:eroute_mobile/features/app_menu/app_session.dart';
import 'package:eroute_mobile/features/auth/auth_repository.dart';
import 'package:eroute_mobile/features/auth/auth_page.dart';

class MemoryVault implements TokenVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String? next) async {
    value = next;
  }
}

class PrivacyRepository extends AuthRepository {
  bool offline = false, withdrawn = false;
  PrivacyRepository() : super(vault: MemoryVault());
  Map<String, dynamic> get user => {
    'userId': 'A',
    'phone': 'dev:member-a',
    'role': 'MEMBER',
    'source': 'DEVELOPMENT',
    'healthConsent': {
      'state': withdrawn ? 'REVOKED' : 'GRANTED',
      'epoch': withdrawn ? 2 : 1,
    },
  };
  @override
  Future<Map<String, dynamic>?> restore() async => user;
  @override
  Future<Map<String, dynamic>> me() async {
    if (offline) throw const AuthFailure('NETWORK', '확인하지 못했습니다.');
    return user;
  }

  @override
  Future<Response<dynamic>> request(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? headers,
  }) async {
    if (offline) throw const AuthFailure('NETWORK', '확인하지 못했습니다.');
    dynamic body;
    if (path.endsWith('emergency-profile')) {
      body = {
        'consentEpoch': 1,
        'version': 1,
        'allergies': {'status': 'UNSET', 'text': ''},
        'conditions': {'status': 'UNSET', 'text': ''},
        'note': '',
        'medicationsStatus': 'UNSET',
        'updatedAt': null,
      };
    } else if (path.endsWith('health-consent')) {
      body = user['healthConsent'];
    } else {
      body = <dynamic>[];
    }
    return Response(
      requestOptions: RequestOptions(path: path),
      data: body,
      statusCode: 200,
    );
  }
}

void main() {
  test('memory draft TTL is not extended by revalidation or app switches', () {
    var elapsed = Duration.zero;
    final draft = HealthDraft(elapsed: () => elapsed);
    draft.edit(
      user: 'A',
      session: 1,
      epoch: 2,
      version: 3,
      data: {'note': '가상 초안'},
    );
    elapsed = const Duration(minutes: 9);
    expect(draft.restore('A', 1, 2, 3)?['note'], '가상 초안');
    elapsed = const Duration(minutes: 10);
    expect(draft.restore('A', 1, 2, 3), isNull);
    expect(draft.values, isNull);
  });
  test(
    'another user, session, consent or data version cannot restore draft',
    () {
      for (final input in [
        ('B', 1, 2, 3),
        ('A', 2, 2, 3),
        ('A', 1, 3, 3),
        ('A', 1, 2, 4),
      ]) {
        final draft = HealthDraft(elapsed: () => Duration.zero);
        draft.edit(
          user: 'A',
          session: 1,
          epoch: 2,
          version: 3,
          data: {'note': '가상 초안'},
        );
        expect(draft.restore(input.$1, input.$2, input.$3, input.$4), isNull);
      }
    },
  );
  testWidgets(
    'another app then failed verification: covered retry preserves draft',
    (tester) async {
      final repo = PrivacyRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authRepositoryProvider.overrideWithValue(repo)],
          child: const MaterialApp(home: AuthGate(child: MemberHealthPage())),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '응급 메모 (선택)'),
        '약 정보 확인 중인 가상 초안',
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('약 정보 확인 중인 가상 초안'), findsNothing);
      repo.offline = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('약 정보 확인 중인 가상 초안'), findsNothing);
      expect(find.text('다시 확인'), findsOneWidget);
      repo.offline = false;
      await tester.tap(find.text('다시 확인'));
      await tester.pumpAndSettle();
      expect(find.text('약 정보 확인 중인 가상 초안'), findsOneWidget);
      repo.offline = true;
      await tester.pump(const Duration(seconds: 10));
      expect(find.text('약 정보 확인 중인 가상 초안'), findsOneWidget);
      repo.offline = false;
      repo.withdrawn = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('약 정보 확인 중인 가상 초안'), findsNothing);
      expect(find.text('건강정보 처리 동의'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('health form narrow layout visual QA', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final font = FontLoader('NotoSansKR')
      ..addFont(rootBundle.load('assets/fonts/NotoSansKR.ttf'));
    await font.load();
    final iconFont = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconFont.load();
    final key = GlobalKey();
    final repo = PrivacyRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(
            theme: ERouteTheme.light(),
            home: const AuthGate(child: MemberHealthPage()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/qa/member-health.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox());
  });
}
