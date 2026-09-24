import 'package:eroute_mobile/features/disease_personalization/condition_local_store.dart';
import 'package:eroute_mobile/features/disease_personalization/disease_catalog.dart';
import 'package:eroute_mobile/features/disease_personalization/emergency_condition.dart';
import 'support/catalog_fixture.dart';
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
import 'package:eroute_mobile/features/member_ui/member_health_screens.dart';
import 'package:eroute_mobile/preview/member_preview_repository.dart';
import 'package:eroute_mobile/features/disease_personalization/disease_selection_screen.dart';
import 'package:eroute_mobile/features/disease_personalization/disease_reference.dart';
import 'package:eroute_mobile/features/disease_personalization/disease_repository.dart';
import 'package:eroute_mobile/features/disease_personalization/department_matcher.dart';
import 'package:eroute_mobile/features/disease_personalization/map_disease_selection.dart';
import 'support/disease_fixtures.dart';
import 'support/batch2_reference.dart';
import 'support/evidence_v04_reference.dart';

class FixtureDiseaseRepository implements DiseaseDataRepository {
  bool offline = false, disposed = false;
  DiseaseReference? value;
  @override
  Future<DiseaseReference> reference() async {
    if (offline) throw Exception('offline');
    return value ?? backendReference();
  }

  @override
  Future<List<DepartmentSnapshot>> departments(List<String> hpids) async => [];
}

MemberHealthSnapshot replaceSelection(
  MemberHealthSnapshot old,
  MapDiseaseSelection selection, {
  int? version,
}) => MemberHealthSnapshot(
  version: version ?? old.version,
  consentEpoch: old.consentEpoch,
  allergies: old.allergies,
  conditions: old.conditions,
  note: old.note,
  medicationsStatus: old.medicationsStatus,
  medications: old.medications,
  updatedAt: old.updatedAt,
  mapDiseaseSelection: selection,
  standardDiseaseSelection: old.standardDiseaseSelection,
);

class FixtureSelectionRepository implements MapSelectionRepository {
  final PreviewMemberRepository member;
  int writes = 0;
  bool offline = false, consentLost = false;
  FixtureSelectionRepository(this.member);
  @override
  Future<MapSelectionSnapshot> read() async {
    if (consentLost) {
      throw const MemberFailure(MemberFailureKind.consent, "동의 철회");
    }
    return MapSelectionSnapshot(
      member.data.version,
      member.data.consentEpoch,
      member.data.mapDiseaseSelection,
    );
  }

  @override
  Future<MapSelectionSnapshot> save(
    int version,
    int epoch,
    List<String> ids,
    DiseaseReference reference,
  ) async {
    if (offline) {
      throw const MemberFailure(MemberFailureKind.unavailable, '연결 실패');
    }
    writes++;
    member.data = replaceSelection(
      member.data,
      confirmedSelection(reference, ids),
      version: version + 1,
    );
    return read();
  }

  @override
  Future<MapSelectionSnapshot> clear(int version, int epoch) async {
    writes++;
    member.data = replaceSelection(
      member.data,
      const MapDiseaseSelection.none(),
      version: version + 1,
    );
    return read();
  }
}

class FixtureConditionsRepository extends ConditionLocalController {
  final MemoryConditionVault memory;
  int writes = 0;
  FixtureConditionsRepository(PreviewAuthRepository auth, this.memory)
    : super(memory, auth, FixtureCatalogRepository());
  set offline(bool value) => memory.fail = value;
  List<String> get ids =>
      state?.entries
          .where((e) => e.standard)
          .map((e) => e.diseaseId!)
          .toList() ??
      [];
  String? get status => state?.status;
  String get text =>
      state?.entries.where((e) => !e.standard).map((e) => e.name).join('\n') ??
      '';
  @override
  Future<void> save(
    List<EmergencyCondition> entries,
    String status,
    String catalogVersion, {
    int? expectedBaseVersion,
  }) async {
    await super.save(
      entries,
      status,
      catalogVersion,
      expectedBaseVersion: expectedBaseVersion,
    );
    writes++;
  }

  @override
  Future<void> sync() async {}
}

void main() {
  late PreviewMemberRepository member;
  late FixtureSelectionRepository selection;
  late FixtureDiseaseRepository public;
  late ProviderContainer container;
  late FixtureConditionsRepository conditions;
  setUp(() {
    final auth = PreviewAuthRepository();
    member = PreviewMemberRepository(auth, delay: Duration.zero);
    final old = member.data;
    member.data = MemberHealthSnapshot(
      version: old.version,
      consentEpoch: old.consentEpoch,
      allergies: old.allergies,
      conditions: const HealthEntry(EntryStatus.recorded, '천식 없음 · 가상 원문 보존'),
      standardDiseaseSelection: StandardDiseaseSelection(['D001', 'D010']),
      note: old.note,
      medicationsStatus: old.medicationsStatus,
      medications: old.medications,
      updatedAt: old.updatedAt,
    );
    selection = FixtureSelectionRepository(member);
    conditions = FixtureConditionsRepository(auth, MemoryConditionVault());
    public = FixtureDiseaseRepository();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        memberUiRepositoryProvider.overrideWithValue(member),
        memberPrivacyProvider.overrideWithValue(PreviewPrivacy()),
        diseaseDataRepositoryProvider.overrideWith((ref) {
          ref.onDispose(() => public.disposed = true);
          return public;
        }),
        mapSelectionRepositoryProvider.overrideWithValue(selection),
        conditionLocalProvider.overrideWith((ref) => conditions),
        diseaseCatalogRepositoryProvider.overrideWithValue(
          FixtureCatalogRepository(),
        ),
      ],
    );
  });
  tearDown(() => container.dispose());
  Future<void> mount(
    WidgetTester tester, {
    bool dark = false,
    double scale = 1,
    bool record = false,
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
          home: const MemberEmergencyScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (record) {
      final entry = find.text('기저질환');
      await tester.ensureVisible(entry);
      await tester.tap(entry);
    } else {
      openMemberPage(
        tester.element(find.byType(MemberEmergencyScreen)),
        DiseaseSelectionScreen(base: member.data),
      );
    }
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, String label) async {
    final f = find.text(label);
    final scrolling = find
        .descendant(
          of: find.byType(ListView).last,
          matching: find.byType(Scrollable),
        )
        .first;
    tester.state<ScrollableState>(scrolling).position.jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(
      f,
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await Scrollable.ensureVisible(tester.element(f.last), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(f.last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'record tags without approved mappings; deleting text keeps tags and no map consent',
    (tester) async {
      await mount(tester, record: true, dark: true, scale: 2);

      await tester.scrollUntilVisible(
        find.byTooltip('천식 없음 · 가상 원문 보존 제거'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.byTooltip('천식 없음 · 가상 원문 보존 제거')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('천식 없음 · 가상 원문 보존 제거'));
      await tester.pumpAndSettle();
      conditions.offline = true;
      await tapVisible(tester, '기저질환 저장');
      expect(conditions.writes, 0);
      expect(find.byType(DiseaseSelectionScreen), findsOneWidget);
      conditions.offline = false;
      await tapVisible(tester, '기저질환 저장');
      expect(conditions.ids, ['D001', 'D010']);
      expect(conditions.text, '');
      expect(conditions.status, 'RECORDED');
      expect(selection.writes, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'NONE clears everything only after explicit confirmation and save',
    (tester) async {
      await mount(tester, record: true);
      await tapVisible(tester, '기저질환 없음');
      expect(conditions.writes, 0);
      await tester.tap(find.widgetWithText(TextButton, '기록 지우기'));
      await tester.pumpAndSettle();
      expect(conditions.writes, 0);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('카테고리로 찾기'), findsNothing);
      expect(find.text('병원 탐색에 활용'), findsNothing);
      expect(find.text('등록된 기저질환이 없습니다.'), findsOneWidget);
      await tapVisible(tester, '기저질환 있음');
      expect(find.text('카테고리로 찾기'), findsOneWidget);
      await tapVisible(tester, '기저질환 없음');
      await tapVisible(tester, '기저질환 저장');
      expect(conditions.status, 'NONE');
      expect(conditions.ids, isEmpty);
      expect(conditions.text, '');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'tag removal is an unsaved draft; back can retain it and session loss purges',
    (tester) async {
      await mount(tester, record: true);
      await tester.scrollUntilVisible(
        find.byTooltip('천식 제거'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.byTooltip('천식 제거')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('천식 제거'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('변경사항을 버릴까요?'), findsOneWidget);
      await tester.tap(find.text('계속 편집'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('뇌전증 제거'), findsOneWidget);
      expect(conditions.writes, 0);
      container.read(memberControllerProvider.notifier).cover(clear: true);
      await tester.pumpAndSettle();
      expect(find.byTooltip('뇌전증 제거'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Batch 2 catalog search selects exact tag IDs without automatically enabling map use',
    (tester) async {
      public.value = batch2Reference();
      await mount(tester, record: true);
      const queries = {
        '당뇨병': '당뇨병',
        '루푸스': '전신성 홍반성 루푸스',
        'IPF': '특발성 폐섬유화증',
        '우울증': '우울증',
        '녹내장': '녹내장',
        '자궁내막증': '자궁내막증',
        '건선': '건선',
        '허리디스크': '요추 추간판 탈출증',
      };
      for (final entry in queries.entries) {
        final query = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '질환 검색',
        );
        tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: find.byType(ListView).last,
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position
            .jumpTo(0);
        await tester.pumpAndSettle();
        await tester.ensureVisible(query);
        await tester.enterText(query, entry.key);
        await tester.pumpAndSettle();
        final candidate = find.widgetWithText(CheckboxListTile, entry.value);
        await tester.ensureVisible(candidate);
        await tester.tap(candidate);
        await tester.pumpAndSettle();
      }
      await tapVisible(tester, '기저질환 저장');
      expect(conditions.ids.toSet(), {
        'D001',
        'D010',
        'D017',
        'D025',
        'D023',
        'D032',
        'D039',
        'D041',
        'D045',
        'D044',
      });
      expect(conditions.text, '천식 없음 · 가상 원문 보존');
      expect(selection.writes, 0);
      expect(member.data.mapDiseaseSelection.state, 'NOT_SELECTED');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('v0.4 tags preserve free text and require separate map use', (
    tester,
  ) async {
    public.value = evidenceV04Reference();
    await mount(tester, record: true);
    for (final name in ['고혈압', '당뇨병']) {
      final query = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '질환 검색',
      );
      tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(ListView).last,
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await tester.ensureVisible(query);
      await tester.enterText(query, name);
      await tester.pumpAndSettle();
      final candidate = find.widgetWithText(CheckboxListTile, name);
      await tester.ensureVisible(candidate);
      await tester.tap(candidate);
      await tester.pumpAndSettle();
    }
    await tapVisible(tester, '기저질환 저장');
    expect(conditions.ids.toSet(), {'D001', 'D003', 'D010', 'D017'});
    expect(conditions.text, '천식 없음 · 가상 원문 보존');
    expect(selection.writes, 0);
    expect(member.data.mapDiseaseSelection.state, 'NOT_SELECTED');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'D047 server fixture category, alias search, selection and local save without mapping',
    (tester) async {
      final j = catalogJson();
      (j['categories'] as List).add({
        'id': 'CAT_FUTURE',
        'name': '미래 분류',
        'sortOrder': 999,
      });
      (j['diseases'] as List).add({
        'id': 'D047',
        'canonicalName': '테스트질환',
        'categoryId': 'CAT_FUTURE',
        'aliases': ['future047'],
        'active': true,
      });
      (container.read(diseaseCatalogRepositoryProvider)
                  as FixtureCatalogRepository)
              .json =
          j;
      await mount(tester, record: true);
      await tapVisible(tester, '미래 분류');
      await tapVisible(tester, '테스트질환');
      tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(ListView).last,
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      final query = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '질환 검색',
      );
      await tester.enterText(query, 'FUTURE047');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('condition-D047')),
            )
            .value,
        true,
      );
      await tapVisible(tester, '기저질환 저장');
      expect(conditions.ids, contains('D047'));
      expect(selection.writes, 0);
      expect(public.value?.supports('D047') ?? false, false);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'card grid quick picks, one detail, IME clear, custom and pending re-entry',
    (tester) async {
      await mount(tester, record: true);
      final scroll = find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first;
      Future<void> top() async {
        tester.state<ScrollableState>(scroll).position.jumpTo(0);
        await tester.pumpAndSettle();
      }

      final quick = find.widgetWithText(FilterChip, '고혈압');
      await tester.tap(quick);
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(quick).selected, isTrue);
      await tester.tap(quick);
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(quick).selected, isFalse);
      await tapVisible(tester, '심혈관');
      expect(find.byKey(const ValueKey('condition-D003')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('condition-D003')));
      await tester.tap(find.byKey(const ValueKey('condition-D003')));
      await tester.pumpAndSettle();
      await top();
      await tapVisible(tester, '호흡기');
      expect(find.byKey(const ValueKey('condition-D003')), findsNothing);
      expect(find.byKey(const ValueKey('condition-D001')), findsOneWidget);
      await top();
      final query = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '질환 검색',
      );
      await tester.showKeyboard(query);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '고지혈증',
          composing: TextRange(start: 0, end: 4),
          selection: TextSelection.collapsed(offset: 4),
        ),
      );
      await tester.pump();
      expect(find.text('카테고리로 찾기'), findsOneWidget);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '고지혈증',
          selection: TextSelection.collapsed(offset: 4),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('condition-D018')), findsOneWidget);
      await tapVisible(tester, '이상지질혈증');
      await tester.tap(find.byTooltip('검색어 지우기'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(query).focusNode!.hasFocus, isTrue);
      expect(find.text('카테고리로 찾기'), findsOneWidget);
      expect(find.byKey(const ValueKey('condition-D001')), findsOneWidget);
      await tapVisible(tester, '목록에 없는 질환 직접 입력');
      final custom = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '직접 입력한 질환',
      );
      await tester.ensureVisible(custom);
      await tester.enterText(custom, '테스트 직접 입력 질환');
      await tapVisible(tester, '직접 입력 질환 추가');
      await tapVisible(tester, '기저질환 저장');
      expect(conditions.ids, containsAll(['D001', 'D003', 'D018']));
      expect(conditions.text, contains('테스트 직접 입력 질환'));
      expect(selection.writes, 0);
      await tester.ensureVisible(find.text('기저질환'));
      await tester.tap(find.text('기저질환'));
      await tester.pumpAndSettle();
      await tapVisible(tester, '목록에 없는 질환 직접 입력');
      final pending = find.byWidgetPredicate(
        (w) => w is MemberCopy && w.text == '기기에 저장됨 · 서버 동기화 대기 중',
      );
      await tester.scrollUntilVisible(pending, 250, scrollable: scroll);
      expect(pending, findsOneWidget);
      final remove = find.byTooltip('테스트 직접 입력 질환 제거');
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(remove, findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'narrow 320dp 200% grid, long custom and full scroll dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await mount(tester, record: true, dark: dark, scale: 2);
        await tapVisible(tester, '류마티스·자가면역');
        await tapVisible(tester, '전신성 홍반성 루푸스');
        await tapVisible(tester, '목록에 없는 질환 직접 입력');
        final custom = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '직접 입력한 질환',
        );
        await tester.ensureVisible(custom);
        await tester.enterText(custom, '긴 직접 입력 질환 이름 ' * 15);
        await tapVisible(tester, '직접 입력 질환 추가');
        await tapVisible(tester, '기저질환 저장');
        expect(conditions.ids, contains('D025'));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'explicit choice only; original remains; save and disable return to owner',
    (tester) async {
      await mount(tester);
      expect(selection.writes, 0);
      expect(public.disposed, isFalse);
      await tester.scrollUntilVisible(
        find.text('천식'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, '천식'),
            )
            .value,
        false,
      );
      await tapVisible(tester, '천식');
      await tapVisible(tester, '선택한 질환의 지도 활용 목적과 한계를 확인했습니다.');
      await tapVisible(tester, '선택한 질환 확인하고 저장');
      expect(selection.writes, 1);
      expect(member.data.mapDiseaseSelection.diseaseIds, ['D001']);
      expect(member.data.conditions.text, '천식 없음 · 가상 원문 보존');
      expect(find.byType(DiseaseSelectionScreen), findsNothing);
      openMemberPage(
        tester.element(find.byType(MemberEmergencyScreen)),
        DiseaseSelectionScreen(base: member.data),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, '지도 활용 해제');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextButton, '지도 활용 해제'),
        ),
      );
      await tester.pumpAndSettle();
      expect(member.data.mapDiseaseSelection.diseaseIds, isEmpty);
      expect(member.data.conditions.text, '천식 없음 · 가상 원문 보존');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('search clear, failure draft and session loss', (tester) async {
    await mount(tester);
    final query = find.byType(TextField);
    await tester.scrollUntilVisible(
      query,
      250,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.enterText(query, 'asthma');
    await tester.pumpAndSettle();
    await tapVisible(tester, '천식');
    await tester.tap(find.byTooltip('검색어 지우기'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(query).controller!.text, isEmpty);
    await tapVisible(tester, '선택한 질환의 지도 활용 목적과 한계를 확인했습니다.');
    selection.offline = true;
    await tapVisible(tester, '선택한 질환 확인하고 저장');
    expect(selection.writes, 0);
    expect(find.byType(DiseaseSelectionScreen), findsOneWidget);
    container.read(memberControllerProvider.notifier).cover(clear: true);
    await tester.pumpAndSettle();
    expect(find.text('천식 없음 · 가상 원문 보존'), findsNothing);
    expect(selection.writes, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('selection polling revocation purges sensitive screen', (
    tester,
  ) async {
    await mount(tester);
    await tapVisible(tester, '천식');
    selection.consentLost = true;
    member.granted = false;
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('천식 없음 · 가상 원문 보존'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(selection.writes, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'reference unavailable retries and dark large text stays usable',
    (tester) async {
      public.offline = true;
      await mount(tester, dark: true, scale: 1.5);
      expect(find.text('다시 시도'), findsOneWidget);
      public.offline = false;
      await tapVisible(tester, '다시 시도');
      expect(tester.takeException(), isNull);
      await tapVisible(tester, '천식');
      await tapVisible(tester, '선택한 질환의 지도 활용 목적과 한계를 확인했습니다.');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('synthetic light and dark selection visual evidence', (
    tester,
  ) async {
    final font = FontLoader('NotoSansKR')
      ..addFont(rootBundle.load('assets/fonts/NotoSansKR.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final mode in [
      (false, false),
      (true, false),
      (false, true),
      (true, true),
    ]) {
      final (dark, record) = mode;
      await mount(tester, dark: dark, scale: dark ? 2 : 1, record: record);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).first,
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(
          'build/qa/disease-foundation/${record ? 'record' : 'selection'}-${dark ? 'dark-large' : 'light'}.png',
        );
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });
}
