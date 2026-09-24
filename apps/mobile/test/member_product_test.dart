import 'dart:async';
import 'dart:io';
import 'package:eroute_mobile/preview/preview_network_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eroute_mobile/core/theme/eroute_theme.dart';
import 'package:eroute_mobile/features/app_menu/app_session.dart';
import 'package:eroute_mobile/features/member_ui/member_contract.dart';
import 'package:eroute_mobile/features/member_ui/member_controller.dart';
import 'package:eroute_mobile/features/member_ui/member_health_screens.dart';
import 'package:eroute_mobile/features/member_ui/member_product.dart';
import 'package:eroute_mobile/features/member_ui/member_product_screens.dart';
import 'package:eroute_mobile/features/member_ui/member_widgets.dart';
import 'package:eroute_mobile/preview/member_preview_repository.dart';
import 'package:eroute_mobile/preview/member_product_repository.dart';

class DelayedCatalog implements MedicationProductRepository {
  @override
  bool get available => true;
  final requests = <String, Completer<List<MedicationProduct>>>{};
  @override
  String get sourceLabel => 'Test';
  @override
  Future<List<MedicationProduct>> search(String query) =>
      (requests[query] = Completer<List<MedicationProduct>>()).future;
}

class HeldAcknowledgementRepository extends PreviewMemberRepository {
  HeldAcknowledgementRepository(super.auth) : super(delay: Duration.zero);
  Completer<void>? acknowledgement;
  @override
  Future<void> saveMedication({
    MedicationEntry? original,
    MedicationProduct? product,
    required String name,
    required String note,
    required int baseVersion,
    required int consentEpoch,
  }) async {
    await super.saveMedication(
      original: original,
      product: product,
      name: name,
      note: note,
      baseVersion: baseVersion,
      consentEpoch: consentEpoch,
    );
    await acknowledgement?.future;
  }
}

void main() {
  test(
    'late search, clear and disposal cannot restore obsolete results',
    () async {
      final repo = DelayedCatalog();
      final controller = MedicationSearchController(repo);
      final first = controller.search('old');
      final second = controller.search('new');
      repo.requests['new']!.complete([PreviewProductRepository.products[1]]);
      await second;
      repo.requests['old']!.complete([PreviewProductRepository.products[0]]);
      await first;
      expect(controller.state.products.single.id, 'preview-product-200-tablet');
      final clear = controller.search('clear');
      controller.clear();
      repo.requests['clear']!.complete(PreviewProductRepository.products);
      await clear;
      expect(controller.state.products, isEmpty);
      expect(controller.state.attempted, isFalse);
      final disposed = controller.search('disposed');
      controller.dispose();
      repo.requests['disposed']!.complete(PreviewProductRepository.products);
      await disposed;
    },
  );
  test(
    'catalog variants, missing fields and failures are explicit fictional fixtures',
    () async {
      final repo = PreviewProductRepository(delay: Duration.zero);
      final products = await repo.search('가상해봄');
      expect(products.map((p) => p.id).toSet().length, 3);
      expect(products.map((p) => p.name).toSet().length, 1);
      expect(products.map((p) => p.variant).toSet().length, 3);
      expect(products.every((p) => p.source == 'UI_PREVIEW_PRODUCTS'), isTrue);
      expect(products.every((p) => p.imageAsset == null), isTrue);
      expect(await repo.search('없는이름'), isEmpty);
      repo.scenario = PreviewProductScenario.noDescription;
      expect((await repo.search('가상해봄')).single.description, isNull);
      repo.scenario = PreviewProductScenario.failure;
      await expectLater(repo.search('가상해봄'), throwsStateError);
    },
  );
  test(
    'explicit product link survives edits; matching manual names stay unlinked; stale writes fail',
    () async {
      final repo = PreviewMemberRepository(
        PreviewAuthRepository(),
        delay: Duration.zero,
      );
      final product = PreviewProductRepository.products.first;
      final originalAllergies = repo.data.allergies;
      Future<void> add({
        MedicationProduct? selected,
        MedicationEntry? original,
        String note = '',
        int? version,
        int? epoch,
      }) => repo.saveMedication(
        original: original,
        product: selected,
        name: product.name,
        note: note,
        baseVersion: version ?? repo.data.version,
        consentEpoch: epoch ?? repo.epoch,
      );
      await add();
      final manual = repo.data.medications.last;
      expect(manual.product, isNull);
      await add(selected: product);
      final linked = repo.data.medications.last;
      expect(linked.product?.id, product.id);
      expect(identical(repo.data.allergies, originalAllergies), isTrue);
      await add(original: linked, selected: product, note: '개인 메모');
      expect(repo.data.medications.last.product, same(product));
      expect(repo.data.medications.last.note, '개인 메모');
      expect(
        repo.data.medications.firstWhere((p) => p.id == manual.id).product,
        isNull,
      );
      await expectLater(
        add(original: manual, selected: product),
        throwsA(isA<MemberFailure>()),
      );
      final version = repo.data.version;
      await expectLater(
        add(selected: product, version: version - 1),
        throwsA(
          isA<MemberFailure>().having(
            (e) => e.kind,
            'kind',
            MemberFailureKind.conflict,
          ),
        ),
      );
      await expectLater(
        add(selected: product, epoch: repo.epoch - 1),
        throwsA(
          isA<MemberFailure>().having(
            (e) => e.kind,
            'kind',
            MemberFailureKind.consent,
          ),
        ),
      );
      expect(repo.data.version, version);
    },
  );

  test('unexpected HTTP is blocked at the Preview entrypoint boundary', () {
    HttpOverrides.runWithHttpOverrides(() {
      expect(() => HttpClient(), throwsStateError);
    }, PreviewNetworkGuard());
  });

  test(
    'pending product writes reject account switch and consent withdrawal',
    () async {
      for (final withdraw in [false, true]) {
        final repo = PreviewMemberRepository(
          PreviewAuthRepository(),
          delay: Duration.zero,
        );
        final base = repo.data;
        repo.delay = const Duration(milliseconds: 20);
        final pending = repo.saveMedication(
          product: PreviewProductRepository.products.first,
          name: PreviewProductRepository.products.first.name,
          note: '늦은 저장',
          baseVersion: base.version,
          consentEpoch: base.consentEpoch,
        );
        final rejected = expectLater(pending, throwsA(isA<MemberFailure>()));
        repo.delay = Duration.zero;
        if (withdraw) {
          await repo.withdrawConsent(repo.epoch, 'pending-product');
        } else {
          repo.auth.generation++;
          repo.auth.user = {...repo.user, 'userId': 'ui-preview-other'};
        }
        final current = repo.data;
        await rejected;
        expect(repo.data, same(current));
        expect(repo.data.medications.any((m) => m.note == '늦은 저장'), isFalse);
      }
    },
  );

  late HeldAcknowledgementRepository health;
  late PreviewProductRepository products;
  late ProviderContainer container;
  setUp(() {
    final auth = PreviewAuthRepository();
    health = HeldAcknowledgementRepository(auth);
    products = PreviewProductRepository(delay: Duration.zero);
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        memberUiRepositoryProvider.overrideWithValue(health),
        medicationProductRepositoryProvider.overrideWithValue(products),
        memberPrivacyProvider.overrideWithValue(PreviewPrivacy()),
      ],
    );
  });
  tearDown(() => container.dispose());
  Future<void> pump(WidgetTester tester, Widget page) async {
    await container.read(sessionControllerProvider.future);
    await container.read(memberControllerProvider.notifier).reload();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ERouteTheme.light(),
          home: MemberSecurityScope(child: page),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.scrollUntilVisible(
      (text == '복용약 추가' ? find.textContaining(text) : find.text(text)).last,
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(
      (text == '복용약 추가' ? find.textContaining(text) : find.text(text)).last,
    );
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), '가상해봄');
    await tap(tester, '검색');
  }

  testWidgets(
    'list to search to product confirmation, cancellation, personal note and registration',
    (tester) async {
      await pump(tester, const MemberMedicationScreen());
      await tap(tester, '복용약 추가');
      expect(find.text('약 검색'), findsOneWidget);
      await search(tester);
      expect(find.text('100 mg · 정제'), findsOneWidget);
      expect(find.text('200 mg · 정제'), findsOneWidget);
      expect(find.text('100 mg · 캡슐'), findsOneWidget);
      await tap(tester, '200 mg · 정제');
      expect(find.text('제품 확인'), findsOneWidget);
      expect(find.text('제품 이미지 없음'), findsOneWidget);
      await tap(tester, '선택 취소 · 검색으로');
      expect(health.data.medications.length, 1);
      expect(find.text('약 검색'), findsOneWidget);
      await tap(tester, '100 mg · 캡슐');
      await tap(tester, '복용 메모 · 등록으로');
      expect(find.byType(TextFormField), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '사용자가 남긴 가상 메모');
      await tester.pump();
      await tap(tester, '등록');
      expect(find.text('복용약'), findsOneWidget);
      expect(
        health.data.medications.last.product?.id,
        'preview-product-100-capsule',
      );
      expect(health.data.medications.last.note, '사용자가 남긴 가상 메모');
      expect(health.data.medications.first.product, isNull);
      expect(find.text('약 검색'), findsNothing);
    },
  );
  testWidgets(
    'search failure and empty result expose manual fallback; clear invalidates results',
    (tester) async {
      products.scenario = PreviewProductScenario.failure;
      await pump(tester, MemberMedicationSearchScreen(base: health.data));
      await search(tester);
      expect(find.text('다시 검색'), findsOneWidget);
      await tap(tester, '약 이름 직접 입력');
      expect(find.byType(TextFormField), findsNWidgets(2));
      await tester.pageBack();
      await tester.pumpAndSettle();
      products.scenario = PreviewProductScenario.noResults;
      await search(tester);
      expect(find.text('검색 결과가 없어요.'), findsOneWidget);
      products.scenario = PreviewProductScenario.standard;
      await search(tester);
      await tester.ensureVisible(find.byTooltip('검색어 지우기'));
      await tester.tap(find.byTooltip('검색어 지우기'));
      await tester.pumpAndSettle();
      expect(find.text('100 mg · 정제'), findsNothing);
      expect(find.text('약 이름 직접 입력'), findsNothing);
    },
  );
  testWidgets(
    'product save failure keeps note, conflict does not merge, withdrawal purges draft',
    (tester) async {
      health.scenario = PreviewScenario.saveFailure;
      await pump(
        tester,
        MemberFieldEditor(
          base: health.data,
          selectedProduct: PreviewProductRepository.products.first,
        ),
      );
      await tester.enterText(find.byType(TextFormField), '보존할 개인 복용 메모');
      await tap(tester, '등록');
      expect(find.text('보존할 개인 복용 메모'), findsOneWidget);
      health.scenario = PreviewScenario.versionConflict;
      await tap(tester, '등록');
      await tester.scrollUntilVisible(
        find.text('최신 내용 확인'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('최신 내용 확인'), findsOneWidget);
      expect(health.data.medications.length, 1);
      await health.withdrawConsent(health.epoch, 'product-test-withdrawal');
      await container.read(memberControllerProvider.notifier).reload();
      await tester.pumpAndSettle();
      expect(find.text('보존할 개인 복용 메모'), findsNothing);
      expect(health.data.medications, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'withdrawal during search clears query and pending response cannot reappear',
    (tester) async {
      products.delay = const Duration(seconds: 5);
      await pump(tester, MemberMedicationSearchScreen(base: health.data));
      await tester.enterText(find.byType(TextField), '가상해봄');
      await tester.tap(find.text('검색'));
      await tester.pump();
      expect(find.text('제품을 검색하고 있어요.'), findsOneWidget);
      await health.withdrawConsent(health.epoch, 'search-test-withdrawal');
      await container.read(memberControllerProvider.notifier).reload();
      await tester.pump(const Duration(seconds: 6));
      expect(find.text('가상해봄'), findsNothing);
      expect(container.read(medicationSearchProvider).products, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'initial/loading, missing description, optional note and duplicate register',
    (tester) async {
      health.reset(PreviewScenario.empty);
      await pump(tester, const MemberMedicationScreen());
      await tap(tester, '복용약 추가');
      expect(container.read(medicationSearchProvider).attempted, isFalse);
      expect(health.data.medicationsStatus, EntryStatus.unset);
      products.delay = const Duration(seconds: 1);
      await tester.enterText(find.byType(TextField), '가상해봄');
      await tester.tap(find.text('검색'));
      await tester.pump();
      expect(find.text('제품을 검색하고 있어요.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      await tap(tester, '200 mg · 정제');
      expect(find.bySemanticsLabel('설명 미제공'), findsOneWidget);
      expect(health.data.medications, isEmpty);
      await tap(tester, '복용 메모 · 등록으로');
      health.delay = const Duration(seconds: 1);
      await tester.tap(find.text('등록'));
      await tester.tap(find.text('등록'));
      await tester.pump();
      expect(health.data.medications, isEmpty);
      expect(health.data.medicationsStatus, EntryStatus.unset);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(health.data.medications.length, 1);
      expect(health.data.medications.single.note, isEmpty);
      expect(health.data.medicationsStatus, EntryStatus.recorded);
      expect(find.text('복용약'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'selection can switch to manual; manual registration edit delete preserves explicit state',
    (tester) async {
      health.reset(PreviewScenario.empty);
      await pump(tester, const MemberMedicationScreen());
      await tap(tester, '복용약 추가');
      await search(tester);
      await tap(tester, '100 mg · 정제');
      await tap(tester, '선택 대신 직접 입력');
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(health.data.medications, isEmpty);
      await tester.enterText(find.byType(TextFormField).first, '직접 적은 가상 약');
      await tester.enterText(find.byType(TextFormField).last, '수동 기록 메모');
      await tap(tester, '등록');
      expect(health.data.medications.single.product, isNull);
      await tap(tester, '편집');
      await tester.enterText(find.byType(TextFormField).first, '수정한 가상 약');
      await tap(tester, '저장');
      expect(health.data.medications.single.name, '수정한 가상 약');
      expect(health.data.medications.single.product, isNull);
      await tap(tester, '삭제');
      await tester.tap(find.widgetWithText(TextButton, '삭제').last);
      await tester.pumpAndSettle();
      expect(health.data.medications, isEmpty);
      expect(health.data.medicationsStatus, EntryStatus.unset);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'failed registration preserves NONE and cancel does not register',
    (tester) async {
      health.reset(PreviewScenario.empty);
      await health.saveField(
        HealthFieldEdit(
          field: HealthField.medicationsStatus,
          baseVersion: health.data.version,
          consentEpoch: health.epoch,
          medicationsStatus: EntryStatus.none,
        ),
      );
      health.scenario = PreviewScenario.saveFailure;
      await pump(tester, const MemberMedicationScreen());
      await tap(tester, '복용약 추가');
      await search(tester);
      await tap(tester, '100 mg · 정제');
      await tap(tester, '복용 메모 · 등록으로');
      await tester.enterText(find.byType(TextFormField), '실패해도 보존할 메모');
      await tap(tester, '등록');
      expect(health.data.medicationsStatus, EntryStatus.none);
      expect(health.data.medications, isEmpty);
      expect(find.text('실패해도 보존할 메모'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('변경사항 버리기'));
      await tester.pumpAndSettle();
      expect(health.data.medicationsStatus, EntryStatus.none);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final withdrawal in [false, true]) {
    testWidgets(
      'late successful acknowledgement is discarded after ${withdrawal ? "withdrawal" : "account switch"}',
      (tester) async {
        await pump(
          tester,
          MemberFieldEditor(
            base: health.data,
            selectedProduct: PreviewProductRepository.products.first,
          ),
        );
        health.acknowledgement = Completer<void>();
        await tester.enterText(find.byType(TextFormField), '이전 계정 메모');
        await tester.tap(find.text('등록'));
        await tester.pump();
        if (withdrawal) {
          await health.withdrawConsent(health.epoch, 'late-ack');
        } else {
          health.reset(PreviewScenario.empty, userId: 'ui-preview-other');
        }
        await container.read(memberControllerProvider.notifier).reload();
        await tester.pump();
        final current = health.data;
        health.acknowledgement!.complete();
        await tester.pumpAndSettle();
        expect(health.data, same(current));
        expect(find.text('이전 계정 메모'), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(find.text('복용약'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('IME composition does not submit and clear returns focus', (
    tester,
  ) async {
    await pump(tester, MemberMedicationSearchScreen(base: health.data));
    final input = tester.widget<TextField>(find.byType(TextField));
    input.controller!.value = const TextEditingValue(
      text: '가상',
      composing: TextRange(start: 0, end: 2),
    );
    await tester.tap(find.text('검색'));
    await tester.pump();
    expect(container.read(medicationSearchProvider).attempted, isFalse);
    input.controller!.value = const TextEditingValue(text: '가상해봄');
    await tester.tap(find.text('검색'));
    await tester.pumpAndSettle();
    expect(container.read(medicationSearchProvider).products.length, 3);
    await tester.tap(find.byTooltip('검색어 지우기'));
    await tester.pumpAndSettle();
    expect(input.controller!.text, isEmpty);
    expect(input.focusNode!.hasFocus, isTrue);
    expect(container.read(medicationSearchProvider).products, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
