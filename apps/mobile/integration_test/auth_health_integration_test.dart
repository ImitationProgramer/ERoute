import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:eroute_mobile/main.dart' as app;
import 'package:eroute_mobile/app/app.dart';
import 'package:eroute_mobile/app/router.dart';
import 'package:eroute_mobile/features/app_menu/app_session.dart';
import 'package:eroute_mobile/features/member_ui/member_auth_screen.dart';
import 'package:eroute_mobile/features/member_ui/member_controller.dart';
import 'package:eroute_mobile/features/member_ui/member_health_screens.dart';
import 'package:eroute_mobile/features/member_ui/member_profile_screen.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('general app new signup and real password health lifecycle', (
    tester,
  ) async {
    final account =
        jsonDecode(const String.fromEnvironment('MEMBER_TEST_ACCOUNT')) as Map;
    await app.main();
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ERouteApp)),
    );
    final auth = container.read(authRepositoryProvider);
    auth.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          if (o.path.startsWith('/api/v1/auth/')) {
            debugPrint('Member QA request: ${o.method} ${o.path}');
          }
          h.next(o);
        },
        onResponse: (r, h) {
          if (r.requestOptions.path.startsWith('/api/v1/auth/')) {
            debugPrint(
              'Member QA response: ${r.statusCode} ${r.requestOptions.path}',
            );
          }
          h.next(r);
        },
      ),
    );
    if (container.read(sessionProvider).authenticated) {
      await container.read(sessionControllerProvider.notifier).signOut();
      await tester.pumpAndSettle();
    }
    Future<void> settle() async {
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
    }

    Future<void> waitFor(bool Function() ready) async {
      for (var i = 0; i < 150 && !ready(); i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        ready(),
        true,
        reason: 'Expected server-confirmed state within 15 seconds',
      );
      await settle();
    }

    Future<void> tapText(String text) async {
      final f = find.text(text).last;
      await tester.ensureVisible(f);
      await tester.tap(f);
      await settle();
    }

    Future<void> route(String name) async {
      final context = tester.element(find.byType(Scaffold).first);
      pushAppRoute(context, name);
      await settle();
    }

    Future<void> enterAuth(bool signup) async {
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), account['phone'] as String);
      await tester.enterText(fields.at(1), account['password'] as String);
      if (signup) {
        await tester.enterText(fields.at(2), account['password'] as String);
        await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        await settle();
        await tapText('만 14세 이상입니다 (자기확인)');
        await tapText('가입 약관 및 개인정보 처리에 동의합니다 (필수)');
      } else {
        await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        await settle();
      }
      expect(
        tester.widget<TextFormField>(fields.at(0)).controller!.text ==
            account['phone'],
        true,
      );
      expect(
        tester.widget<TextFormField>(fields.at(1)).controller!.text ==
            account['password'],
        true,
      );
      final submit = find.widgetWithText(
        FilledButton,
        signup ? '동의하고 가입' : '로그인',
      );
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await settle();
      await waitFor(() => container.read(sessionProvider).authenticated);
    }

    await route(AppRoutes.login);
    await tapText('회원가입');
    expect(find.byType(MemberAuthScreen), findsOneWidget);
    expect(find.textContaining('본인확인 서비스 준비'), findsNothing);
    await enterAuth(true);
    final firstUser = container.read(sessionProvider).userId;
    expect(firstUser, isNotNull);
    await waitFor(
      () => container.read(memberControllerProvider).access != null,
    );
    expect(container.read(memberControllerProvider).access!.granted, false);
    await tapText('건강정보 동의 확인');
    await waitFor(() => find.text('건강정보 처리에 별도로 동의합니다').evaluate().isNotEmpty);
    await tapText('건강정보 처리에 별도로 동의합니다');
    await tapText('동의하고 시작');
    await waitFor(
      () => container.read(memberControllerProvider).access?.granted == true,
    );
    await route(AppRoutes.emergencyProfile);
    await waitFor(() => find.text('알레르기').evaluate().isNotEmpty);
    await tapText('알레르기');
    final recorded = find.text('있어요');
    if (recorded.evaluate().isNotEmpty) {
      await tester.ensureVisible(recorded);
      await tester.tap(recorded);
      await settle();
    }
    await tester.enterText(
      find.byType(TextFormField).first,
      '가상 알레르기 · 일반 앱 저장',
    );
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await settle();
    await tapText('저장');
    await waitFor(() => find.byType(MemberFieldEditor).evaluate().isEmpty);
    await tapText('응급 메모');
    await tester.enterText(
      find.byType(TextFormField).first,
      '가상 응급 메모 · 실제 저장',
    );
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await waitFor(() => !container.read(memberControllerProvider).covered);
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await settle();
    await tapText('저장');
    await waitFor(() => find.byType(MemberFieldEditor).evaluate().isEmpty);
    await tapText('복용약');
    await tapText('복용약 추가');
    await waitFor(() => find.text('직접 입력').evaluate().isNotEmpty);
    expect(find.bySemanticsLabel(RegExp('약 검색 준비')), findsWidgets);
    await tapText('직접 입력');
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '가상 수동 복용약');
    await tester.enterText(fields.at(1), '가상 복용 메모');
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await settle();
    await tapText('등록');
    await waitFor(() => find.byType(MemberFieldEditor).evaluate().isEmpty);
    final stored = await auth.request('GET', '/api/v1/me/health-snapshot');
    expect(stored.data['note'] == '가상 응급 메모 · 실제 저장', true);
    expect((stored.data['medications'] as List).length, 1);
    expect(stored.data['allergies']['text'] == '가상 알레르기 · 일반 앱 저장', true);
    await route(AppRoutes.profile);
    await waitFor(() => find.byType(MemberAccountScreen).evaluate().isNotEmpty);
    await tapText('로그아웃');
    await waitFor(() => !container.read(sessionProvider).authenticated);
    await route(AppRoutes.login);
    await enterAuth(false);
    expect(container.read(sessionProvider).userId == firstUser, true);
    final persisted = await auth.request('GET', '/api/v1/me/health-snapshot');
    expect(persisted.data['note'] == stored.data['note'], true);
    expect((persisted.data['medications'] as List).length, 1);
    await route(AppRoutes.profile);
    await tapText('건강정보 동의 및 삭제');
    await tapText('동의 철회 및 삭제');
    await tapText('동의 철회 및 삭제');
    await waitFor(
      () =>
          container.read(memberControllerProvider).access?.consentState ==
          'REVOKED',
    );
    expect(container.read(sessionProvider).authenticated, true);
    expect(
      (await auth.request('GET', '/api/v1/me/health-consent')).data['state'],
      'REVOKED',
    );
    await route(AppRoutes.profile);
    await tapText('로그아웃');
    await waitFor(() => !container.read(sessionProvider).authenticated);
    await tester.pumpWidget(const SizedBox());
  });
}
