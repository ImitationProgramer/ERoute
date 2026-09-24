import 'package:eroute_mobile/features/member_ui/member_product.dart';
import 'package:eroute_mobile/features/member_ui/member_product_screens.dart';
import 'package:eroute_mobile/preview/member_product_repository.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eroute_mobile/core/theme/eroute_theme.dart';
import 'package:eroute_mobile/features/app_menu/app_session.dart';
import 'package:eroute_mobile/features/member_ui/member_contract.dart';
import 'package:eroute_mobile/features/member_ui/member_controller.dart';
import 'package:eroute_mobile/features/member_ui/member_widgets.dart';
import 'package:eroute_mobile/features/member_ui/member_auth_screen.dart';
import 'package:eroute_mobile/features/member_ui/member_health_screens.dart';
import 'package:eroute_mobile/features/member_ui/member_profile_screen.dart';
import 'package:eroute_mobile/preview/member_preview_repository.dart';

void main() {
  late PreviewMemberRepository repo;
  late PreviewProductRepository catalog;
  late ProviderContainer container;
  setUp(() {
    final auth = PreviewAuthRepository();
    repo = PreviewMemberRepository(auth, delay: Duration.zero);
    catalog = PreviewProductRepository(delay: Duration.zero);
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        memberUiRepositoryProvider.overrideWithValue(repo),
        medicationProductRepositoryProvider.overrideWithValue(catalog),
        memberPrivacyProvider.overrideWithValue(PreviewPrivacy()),
        memberResultLabelProvider.overrideWithValue('미리보기에서 반영됨'),
      ],
    );
  });
  tearDown(() => container.dispose());
  Future<void> pump(
    WidgetTester tester,
    Widget page, {
    bool dark = false,
    double scale = 1,
  }) async {
    await container.read(sessionControllerProvider.future);
    await container.read(memberControllerProvider.notifier).reload();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dark ? ERouteTheme.dark() : ERouteTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: MemberSecurityScope(child: page),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('main cards navigate to focused editor; saves only one field', (
    tester,
  ) async {
    await pump(tester, const MemberEmergencyScreen());
    expect(find.byType(TextFormField), findsNothing);
    await tester.tap(find.text('알레르기').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField),
      '한 줄의 긴 알레르기 기록, 그대로 보존',
    );
    await tester.ensureVisible(find.text('저장').last);
    await tester.tap(find.text('저장').last);
    await tester.pumpAndSettle();
    expect(repo.data.allergies.text, '한 줄의 긴 알레르기 기록, 그대로 보존');
    expect(repo.data.conditions.status, EntryStatus.none);
    expect(repo.data.note, '응급 상황에서는 보호자에게 연락해주세요.');
    expect(find.text('내 응급정보'), findsOneWidget);
  });
  testWidgets(
    'save failure preserves input and retry; version conflict requires latest',
    (tester) async {
      repo.reset(PreviewScenario.saveFailure);
      await pump(
        tester,
        MemberFieldEditor(field: HealthField.note, base: repo.data),
      );
      await tester.enterText(find.byType(TextFormField), '보존할 초안');
      await tester.ensureVisible(find.text('저장').last);
      await tester.tap(find.text('저장').last);
      await tester.pumpAndSettle();
      expect(find.text('보존할 초안'), findsOneWidget);
      repo.scenario = PreviewScenario.versionConflict;
      await tester.ensureVisible(find.text('저장').last);
      await tester.tap(find.text('저장').last);
      await tester.pumpAndSettle();
      expect(find.text('보존할 초안'), findsOneWidget);
      expect(find.text('최신 내용 확인'), findsOneWidget);
      expect(repo.data.note, '다른 기기에서 변경한 가상 메모입니다.');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('health consent returns to its owner only after confirmation', (
    tester,
  ) async {
    repo.reset(PreviewScenario.consentRequired);
    await pump(tester, const MemberEmergencyScreen());
    await tester.tap(find.text('동의 내용 확인하고 시작하기'));
    await tester.pumpAndSettle();
    expect(find.text('건강정보 관리'), findsOneWidget);
    expect(find.text('내 응급정보'), findsNothing);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('동의하고 시작'));
    repo.delay = const Duration(milliseconds: 500);
    await tester.tap(find.text('동의하고 시작'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('건강정보 관리'), findsOneWidget);
    expect(container.read(memberControllerProvider).access?.granted, isFalse);
    await tester.pumpAndSettle();
    expect(find.text('내 응급정보'), findsOneWidget);
    expect(container.read(memberControllerProvider).access?.granted, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('dirty exit asks and keep editing retains draft', (tester) async {
    await pump(tester, const MemberEmergencyScreen());
    await tester.tap(find.text('알레르기').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '미저장 초안');
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('변경사항을 버릴까요?'), findsOneWidget);
    await tester.tap(find.text('계속 편집'));
    await tester.pumpAndSettle();
    expect(find.text('미저장 초안'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('resume offline stays covered; epoch change purges input', (
    tester,
  ) async {
    await pump(
      tester,
      MemberFieldEditor(field: HealthField.note, base: repo.data),
    );
    await tester.enterText(find.byType(TextFormField), '민감한 초안');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('민감한 초안'), findsNothing);
    repo.scenario = PreviewScenario.readFailure;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('민감한 초안'), findsNothing);
    repo.scenario = PreviewScenario.saved;
    await container.read(memberControllerProvider.notifier).reload();
    await tester.pumpAndSettle();
    expect(find.text('민감한 초안'), findsOneWidget);
    repo.epoch++;
    await container.read(memberControllerProvider.notifier).reload();
    await tester.pumpAndSettle();
    expect(find.text('민감한 초안'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('auth masks passwords, rejects mismatch and has no PASS', (
    tester,
  ) async {
    await pump(tester, const MemberAuthScreen(signup: true));
    expect(find.textContaining('PASS'), findsNothing);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '01012345678');
    await tester.enterText(fields.at(1), 'preview-password-only');
    await tester.enterText(fields.at(2), 'different-password-only');
    await tester.scrollUntilVisible(
      find.text('동의하고 가입'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('동의하고 가입'));
    await tester.pumpAndSettle();
    expect(find.text('비밀번호가 일치하지 않습니다.'), findsOneWidget);
  });
  testWidgets('screen matrix: themes, widths, 200% text and keyboard', (
    tester,
  ) async {
    final font = FontLoader('NotoSansKR')
      ..addFont(rootBundle.load('assets/fonts/NotoSansKR.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    final pages = <String, Widget Function()>{
      'health': () => const MemberEmergencyScreen(),
      'account': () => const MemberAccountScreen(),
      'login': () => const MemberAuthScreen(),
      'signup': () => const MemberAuthScreen(signup: true),
      'allergy': () =>
          MemberFieldEditor(field: HealthField.allergies, base: repo.data),
      'condition': () =>
          MemberFieldEditor(field: HealthField.conditions, base: repo.data),
      'note': () => MemberFieldEditor(field: HealthField.note, base: repo.data),
      'medications': () => const MemberMedicationScreen(),
      'medication-form': () => MemberFieldEditor(base: repo.data),
      'consent': () => const MemberConsentScreen(),
      'product-results': () => MemberMedicationSearchScreen(base: repo.data),
      'product-no-results': () => MemberMedicationSearchScreen(base: repo.data),
      'product-failure': () => MemberMedicationSearchScreen(base: repo.data),
      'product-no-description': () => MemberProductConfirmationScreen(
        base: repo.data,
        product: PreviewProductRepository.products[1],
      ),
      'product-long-name': () => MemberProductConfirmationScreen(
        base: repo.data,
        product: PreviewProductRepository.longProduct,
      ),
      'product-long-results': () =>
          MemberMedicationSearchScreen(base: repo.data),
      'product-search': () => MemberMedicationSearchScreen(base: repo.data),
      'product-confirmation': () => MemberProductConfirmationScreen(
        base: repo.data,
        product: PreviewProductRepository.products.first,
      ),
      'product-note': () => MemberFieldEditor(
        base: repo.data,
        selectedProduct: PreviewProductRepository.products.first,
      ),
    };
    for (final dark in [false, true]) {
      for (final width in [320.0, 430.0, 720.0]) {
        for (final scale in [1.0, 2.0]) {
          tester.view.physicalSize = Size(width, 932);
          for (final entry in pages.entries) {
            await tester.pumpWidget(const SizedBox());
            catalog.scenario = entry.key == 'product-no-results'
                ? PreviewProductScenario.noResults
                : entry.key == 'product-failure'
                ? PreviewProductScenario.failure
                : entry.key == 'product-long-results'
                ? PreviewProductScenario.longName
                : PreviewProductScenario.standard;
            final key = GlobalKey();
            await pump(
              tester,
              RepaintBoundary(key: key, child: entry.value()),
              dark: dark,
              scale: scale,
            );
            if ([
              'product-results',
              'product-long-results',
              'product-no-results',
              'product-failure',
            ].contains(entry.key)) {
              await tester.enterText(find.byType(TextField), '가상해봄');
              await tester.scrollUntilVisible(
                find.text('검색'),
                120,
                scrollable: find.byType(Scrollable).first,
              );
              await tester.tap(find.text('검색'));
              await tester.pumpAndSettle();
            }
            expect(
              tester.takeException(),
              isNull,
              reason: '${entry.key}: dark=$dark width=$width scale=$scale',
            );
            if (width == 430 && scale == 1 ||
                width == 320 &&
                    scale == 2 &&
                    [
                      'health',
                      'account',
                      'product-long-name',
                      'product-long-results',
                      'product-note',
                    ].contains(entry.key)) {
              await tester.runAsync(() async {
                final image =
                    await (key.currentContext!.findRenderObject()
                            as RenderRepaintBoundary)
                        .toImage();
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final f = File(
                  'build/qa/member-ui/${entry.key}-${dark ? 'dark' : 'light'}${width == 320 ? '-320dp-2x' : ''}.png',
                );
                await f.parent.create(recursive: true);
                await f.writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
            final input = find.byType(TextField);
            if (input.evaluate().isNotEmpty) {
              tester.view.viewInsets = const FakeViewPadding(bottom: 320);
              await tester.pumpAndSettle();
              expect(
                tester.takeException(),
                isNull,
                reason: 'keyboard ${entry.key}',
              );
              tester.view.resetViewInsets();
            }
          }
        }
      }
    }
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('empty, consent and failure states are explicit and captured', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final scenario in [
      PreviewScenario.empty,
      PreviewScenario.consentRequired,
      PreviewScenario.readFailure,
      PreviewScenario.deletionFailed,
      PreviewScenario.deletionComplete,
    ]) {
      await tester.pumpWidget(const SizedBox());
      repo.reset(scenario);
      await container
          .read(sessionControllerProvider.notifier)
          .accept(repo.user);
      final key = GlobalKey();
      final page =
          [
            PreviewScenario.deletionFailed,
            PreviewScenario.deletionComplete,
            PreviewScenario.consentRequired,
          ].contains(scenario)
          ? const MemberConsentScreen()
          : const MemberEmergencyScreen();
      await pump(tester, RepaintBoundary(key: key, child: page));
      expect(tester.takeException(), isNull);
      if (scenario == PreviewScenario.empty) {
        expect(find.text('미입력'), findsNWidgets(4));
      }
      if (scenario == PreviewScenario.consentRequired) {
        expect(find.text('건강정보 처리에 별도로 동의합니다'), findsOneWidget);
      }
      if (scenario == PreviewScenario.deletionFailed) {
        expect(find.text('삭제 재시도'), findsOneWidget);
      }
      if (scenario == PreviewScenario.deletionComplete) {
        expect(find.text('백업 파기는 별도 확인 중입니다.'), findsOneWidget);
      }
      if (scenario == PreviewScenario.readFailure) {
        expect(find.text('다시 확인'), findsOneWidget);
      }
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final f = File('build/qa/member-ui/state-${scenario.name}.png');
        await f.parent.create(recursive: true);
        await f.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'pending request shows loader and late result cannot reveal disposed screen',
    (tester) async {
      await container.read(sessionControllerProvider.future);
      repo.delay = const Duration(seconds: 15);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ERouteTheme.light(),
            home: const MemberEmergencyScreen(),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      container.read(memberControllerProvider.notifier).cover(clear: true);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 15));
      expect(tester.takeException(), isNull);
    },
  );
}
