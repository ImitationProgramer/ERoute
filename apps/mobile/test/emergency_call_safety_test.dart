import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eroute_mobile/features/emergency_call/emergency_dialer.dart';
import 'package:eroute_mobile/features/emergency_call/system_emergency_dialer.dart';
import 'package:eroute_mobile/features/emergency_call/emergency_call_coordinator.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  var nativeCalls = 0;
  setUp(() {
    nativeCalls = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('eroute/emergency_dialer'),
      (_) async {
        nativeCalls++;
        fail('OS emergency launcher must NEVER run in tests');
      },
    );
  });
  tearDown(() {
    expect(nativeCalls, 0);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('eroute/emergency_dialer'),
      null,
    );
  });
  test('default composition is mock', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(emergencyDialerProvider), isA<MockEmergencyDialer>());
  });
  test(
    'production dialer construction in tests fails before touching platform',
    () async {
      await expectLater(
        SystemEmergencyDialer.forProduction(),
        throwsStateError,
      );
    },
  );
  test(
    'every missing gate fails closed, including production release automation',
    () {
      for (var mask = 0; mask < 32; mask++) {
        final policy = EmergencyDialerPolicy(
          production: mask & 1 != 0,
          release: mask & 2 != 0,
          enabled: mask & 4 != 0,
          physicalDevice: mask & 8 != 0,
          automation: mask & 16 != 0,
        );
        expect(policy.allowsSystem, mask == 15);
      }
      expect(const EmergencyDialerPolicy().allowsSystem, isFalse);
    },
  );
  test(
    'mock records only intended request and never substitutes another number',
    () async {
      final mock = MockEmergencyDialer();
      expect(await mock.dial('119'), DialResult.simulated);
      expect(await mock.dial('112'), DialResult.unavailable);
      expect(mock.requests, ['119']);
    },
  );
  testWidgets(
    'start/render/resume/cancel are inert; explicit confirmation records once',
    (tester) async {
      final mock = MockEmergencyDialer();
      final coordinator = EmergencyCallCoordinator(mock);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  coordinator.confirm(context);
                  coordinator.confirm(context);
                },
                child: const Text('119 신고'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(mock.requests, isEmpty);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(mock.requests, isEmpty);
      await tester.tap(find.text('119 신고'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(mock.requests, isEmpty);
      await tester.tap(find.text('119 신고'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('119 전화 연결'));
      await tester.pumpAndSettle();
      expect(mock.requests, ['119']);
      expect(find.text('개발 모드: 실제 전화 연결을 실행하지 않았습니다.'), findsOneWidget);
      expect(find.textContaining('신고 완료'), findsNothing);
    },
  );
  test(
    'native sources contain only guarded handoff; no direct-call intent or permission',
    () {
      final android = File(
        'android/app/src/main/kotlin/com/eroute/eroute_mobile/MainActivity.kt',
      ).readAsStringSync();
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final ios = File('ios/Runner/AppDelegate.swift').readAsStringSync();
      expect(android, contains('Intent.ACTION_DIAL'));
      expect(android, isNot(contains('Intent.ACTION_CALL')));
      expect(manifest, isNot(contains('android.permission.CALL_PHONE')));
      expect(android, contains('if (!allowed())'));
      expect(ios, contains('guard self.systemDialerAllowed()'));
      expect(ios, contains('targetEnvironment(simulator)'));
    },
  );
  testWidgets('launcher failure never retries or changes emergency number', (
    tester,
  ) async {
    final dialer = FailingDialer();
    final coordinator = EmergencyCallCoordinator(dialer);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => coordinator.confirm(context),
              child: const Text('119 신고'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('119 신고'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('119 전화 연결'));
    await tester.pumpAndSettle();
    expect(dialer.requests, ['119']);
    expect(find.textContaining('전화 기능을 열 수 없습니다'), findsOneWidget);
  });
}

class FailingDialer implements EmergencyDialer {
  final requests = <String>[];
  @override
  Future<DialResult> dial(String number) async {
    requests.add(number);
    throw StateError('test failure');
  }
}
