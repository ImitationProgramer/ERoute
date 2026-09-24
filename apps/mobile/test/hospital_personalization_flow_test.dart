import 'package:eroute_mobile/features/disease_personalization/personalization_overlay.dart';
import 'package:eroute_mobile/features/hospital_detail/presentation/hospital_detail_page.dart';
import 'package:eroute_mobile/features/emergency_map/presentation/emergency_map_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eroute_mobile/features/disease_personalization/condition_catalog_widgets.dart';
import 'package:eroute_mobile/features/disease_personalization/condition_local_store.dart';
import 'package:eroute_mobile/features/disease_personalization/emergency_condition.dart';
import 'package:eroute_mobile/features/disease_personalization/map_personalization_controller.dart';
import 'package:eroute_mobile/features/app_menu/app_session.dart';
import 'support/disease_fixtures.dart';
import 'package:eroute_mobile/features/disease_personalization/personalization_badge.dart';
import 'package:eroute_mobile/features/emergency_map/presentation/emergency_map_controller.dart';
import 'package:eroute_mobile/features/member_ui/member_health_screens.dart';
import 'support/hospital_personalization_flow_fixture.dart';

Future<void> exerciseHospitalFlow(
  WidgetTester tester, {
  bool dark = false,
  double scale = 1,
  Future<void> Function(String)? capture,
}) async {
  final f = FlowFixture(signedIn: false, dark: dark);
  await tester.pumpWidget(f.app(scale: scale));
  await tester.pumpAndSettle();
  Future<void> shot(String name) async {
    if (capture != null) {
      await capture('${dark ? 'dark' : 'light'}-${scale.toInt()}x-$name');
    }
  }

  Future<void> reveal(Finder target) async {
    // Let the existing transient save feedback finish before a following action.
    // At 200% it occupies more of the bottom viewport on a real Android device.
    if (find.byType(SnackBar).evaluate().isNotEmpty) {
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    }
    final list = find.byType(ListView);
    final custom = find.byType(CustomScrollView);
    final scroll = list.evaluate().isNotEmpty
        ? find
              .descendant(of: list.last, matching: find.byType(Scrollable))
              .first
        : custom.evaluate().isNotEmpty
        ? find
              .descendant(of: custom.last, matching: find.byType(Scrollable))
              .first
        : find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      target,
      180,
      scrollable: scroll,
      maxScrolls: 100,
    );
    await Scrollable.ensureVisible(tester.element(target.last), alignment: .5);
    await tester.pumpAndSettle();
  }

  Future<void> tap(Finder target) async {
    await reveal(target);
    await tester.tap(target.last);
    await tester.pumpAndSettle();
  }

  Future<void> home() async {
    Navigator.of(
      tester.element(find.byType(Scaffold).last),
    ).popUntil((route) => route.isFirst);
    await tester.pumpAndSettle();
  }

  Future<void> hospitals({required bool matched}) async {
    await tap(
      find.byWidgetPredicate(
        (w) => w is Text && w.semanticsLabel == '가까운 병원 찾기',
      ),
    );
    await tester.pumpAndSettle();
    final c = f.container.read(mapControllerProvider);
    expect(c.result!.hospitals.map((h) => h.hpid), ['QA_A', 'QA_B', 'QA_C']);
    expect(c.result!.totalCount, 3);
    expect(c.requestedRadiusMeters, 10000);
    if (matched) {
      expect(
        f.personal.state.results.entries
            .where((e) => e.value.matched)
            .map((e) => e.key),
        ['QA_A', 'QA_C'],
      );
    } else {
      expect(f.personal.state.results.values.where((r) => r.matched), isEmpty);
      expect(find.byType(PersonalizationBadge), findsNothing);
    }
    await tester.tap(find.byTooltip('병원 목록 펼치기'));
    await tester.pumpAndSettle();
  }

  await hospitals(matched: false);
  expect(f.selection.reads, 0);
  expect(f.data.reads, 0);
  await shot('ordinary-hospital');
  await home();
  await tap(
    find.byWidgetPredicate((w) => w is Text && w.semanticsLabel == '내 응급정보'),
  );
  final phone = find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == '휴대폰 번호',
  );
  final password = find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == '비밀번호',
  );
  await tester.enterText(phone, '01012345678');
  await tester.enterText(password, 'preview-password-only');
  await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  await tester.pumpAndSettle();
  await tap(find.widgetWithText(FilledButton, '로그인'));
  expect(find.byType(MemberEmergencyScreen), findsOneWidget);
  expect(find.text('관련 진료과 병원 보기'), findsNothing);
  expect(find.text('지도에서 활용할 질환 선택'), findsNothing);
  expect(find.byType(HealthSummaryCard), findsNWidgets(4));
  await shot('health-main');
  await tap(find.text('기저질환'));
  expect(find.text('아직 입력하지 않았어요'), findsWidgets);
  await tap(find.text('기저질환 없음'));
  expect(find.byType(TextField), findsNothing);
  expect(find.byType(ConditionCategoryGrid), findsNothing);
  expect(find.text('병원 탐색에 활용'), findsNothing);
  await shot('none');
  await tap(find.text('기저질환 있음'));
  await shot('grid');
  await tap(find.byKey(const ValueKey('category-CAT_RESPIRATORY')));
  await tap(find.byKey(const ValueKey('condition-D001')));
  await shot('category-detail');
  await tap(find.text('기저질환 저장'));
  // Signed in and recorded, but not opted in: ordinary results remain unchanged.
  await home();
  await hospitals(matched: false);
  await home();
  await tap(
    find.byWidgetPredicate((w) => w is Text && w.semanticsLabel == '내 응급정보'),
  );
  await tap(find.text('기저질환'));
  await tap(find.text('병원 탐색 활용 설정'));
  final agreement = find.widgetWithText(
    CheckboxListTile,
    '선택한 질환의 지도 활용 목적과 한계를 확인했습니다.',
  );
  await tap(find.widgetWithText(CheckboxListTile, '천식'));
  expect(f.selection.writes, 0);
  await shot('consent-first');
  await tap(agreement);
  await tap(find.text('선택한 질환 확인하고 저장'));
  expect(f.selection.writes, 1);
  await tap(find.text('병원 탐색 활용 설정'));
  await reveal(find.widgetWithText(CheckboxListTile, '천식'));
  expect(
    tester
        .widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, '천식'))
        .value,
    isTrue,
  );
  await reveal(agreement);
  expect(tester.widget<CheckboxListTile>(agreement).value, isTrue);
  await shot('consent-restored');
  await tester.pageBack();
  await tester.pumpAndSettle();
  await shot('utilization-section');
  await home();
  await hospitals(matched: true);
  await tap(find.byKey(const ValueKey('personalization-context')));
  expect(find.text('병원 탐색에 활용 중'), findsOneWidget);
  expect(find.text('→ 내과'), findsOneWidget);
  await tap(find.text('병원 탐색 활용 설정'));
  await reveal(agreement);
  expect(tester.widget<CheckboxListTile>(agreement).value, isTrue);
  expect(f.selection.writes, 1);
  await tester.pageBack();
  await tester.pumpAndSettle();
  expect(find.byType(EmergencyMapPage), findsOneWidget);
  expect(
    tester
        .widget<PersonalizationOverlay>(find.byType(PersonalizationOverlay))
        .ringIds,
    isEmpty,
  );
  // A and C get informational badges; B stays visible and in the same position.
  final badge = find.byType(PersonalizationBadge).first;
  await reveal(badge);
  await shot('personalized-hospital');
  await tap(find.descendant(of: badge, matching: find.byType(TextButton)));
  expect(find.byType(PersonalizationReasonSheet), findsOneWidget);
  expect(find.text('관계 범위: 상위 진료과 후보'), findsOneWidget);
  expect(find.textContaining('REVIEW_REQUIRED'), findsNothing);
  expect(find.textContaining('DRAFT'), findsNothing);
  await shot('reason');
  await tester.tap(find.text('닫기'));
  await tester.pumpAndSettle();
  await tap(find.text('가상 A 응급의료기관'));
  expect(find.byType(HospitalDetailPage), findsOneWidget);
  await tap(find.text('진료 정보'));
  expect(find.byType(PersonalizationBadge), findsWidgets);
  await tester.tap(find.byTooltip('뒤로 가기'));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('personalization-context')), findsOneWidget);
  expect(f.personal.state.results.values.where((r) => r.matched).length, 2);
  await home();
  await tap(
    find.byWidgetPredicate((w) => w is Text && w.semanticsLabel == '내 응급정보'),
  );
  await tap(find.text('기저질환'));
  await tap(find.text('목록에 없는 질환 직접 입력'));
  final custom = find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == '직접 입력한 질환',
  );
  await reveal(custom);
  await tester.enterText(custom, '가상 직접 입력 질환');
  await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  await tester.pumpAndSettle();
  await tap(find.text('직접 입력 질환 추가'));
  f.conditions.offline = true;
  await tap(find.text('기저질환 저장'));
  expect(f.container.read(conditionLocalProvider)!.pending, isTrue);
  await home();
  await hospitals(matched: false);
  f.conditions.conflict();
  await tester.pumpAndSettle();
  expect(f.personal.state.results, isEmpty);
  expect(f.container.read(mapControllerProvider).result!.hospitals.length, 3);
  expect(f.hospitals.requestedRadii.toSet(), {10000});
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
  f.container.dispose();
}

void main() {
  test(
    'CUSTOM and an unmapped STANDARD remain recorded without department queries',
    () async {
      final f = FlowFixture();
      await f.container.read(sessionControllerProvider.future);
      final local = LocalConditions(
        userId: f.member.user['userId'],
        epoch: f.member.epoch,
        baseVersion: 1,
        catalogVersion: 'fixture',
        status: 'RECORDED',
        entries: [
          EmergencyCondition.custom('가상 직접 입력 질환'),
          EmergencyCondition.standard('D001', '천식'),
        ],
      );
      f.member.data = flowHealth(f.member.data, local: local);
      final c = MapPersonalizationController(
        f.data,
        f.selection,
        () => f.container.read(sessionProvider),
        available: true,
        // Public catalog has zero approved mappings; no inferred/custom mapping.
      );
      await c.enable();
      expect(c.state.results, isEmpty);
      expect(f.data.reads, 0); // no map consent
      f.member.data = flowHealth(
        f.member.data,
        selection: confirmedSelection(f.data.referenceValue, ['D001']),
      );
      await c.enable();
      expect(f.member.data.conditionEntries, hasLength(2));
      expect(c.state.results, isEmpty);
      expect(f.data.departmentReads, 0);
      f.member.granted = false;
      await c.enable();
      expect(c.state.results, isEmpty);
      c.dispose();
      f.container.dispose();
    },
  );

  testWidgets(
    '320dp 200% NONE hides editing without changing UNSET semantics',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = FlowFixture(dark: true);
      await f.container.read(sessionControllerProvider.future);
      await tester.pumpWidget(f.app(scale: 2));
      await tester.pumpAndSettle();
      final home = find.byWidgetPredicate(
        (w) => w is Text && w.semanticsLabel == '내 응급정보',
      );
      await tester.ensureVisible(home);
      await tester.tap(home);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('기저질환'));
      await tester.tap(find.text('기저질환'));
      await tester.pumpAndSettle();
      expect(f.container.read(conditionLocalProvider)!.status, 'UNSET');
      await tester.tap(find.text('기저질환 없음'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(ConditionCategoryGrid), findsNothing);
      expect(
        f.container.read(conditionLocalProvider)!.status,
        'UNSET',
      ); // unsaved explicit NONE
      await tester.tap(find.text('기저질환 있음'));
      await tester.pumpAndSettle();
      expect(find.byType(ConditionCategoryGrid), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      f.container.dispose();
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'health to ordinary hospital flow with opt-in only dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await exerciseHospitalFlow(tester, dark: dark);
      },
    );
  }
}
