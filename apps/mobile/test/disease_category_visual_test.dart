import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eroute_mobile/core/theme/eroute_theme.dart';
import 'package:eroute_mobile/features/app_menu/app_session.dart';
import 'package:eroute_mobile/features/disease_personalization/disease_catalog.dart';
import 'package:eroute_mobile/features/disease_personalization/disease_category_visual.dart';
import 'package:eroute_mobile/features/disease_personalization/personalization_category_button.dart';
import 'package:eroute_mobile/features/disease_personalization/personalization_badge.dart';
import 'package:eroute_mobile/features/disease_personalization/condition_local_store.dart';
import 'package:eroute_mobile/features/disease_personalization/emergency_condition.dart';
import 'package:eroute_mobile/features/disease_personalization/department_matcher.dart';
import 'package:eroute_mobile/features/emergency_map/presentation/emergency_map_controller.dart';
import 'package:eroute_mobile/features/emergency_map/presentation/widgets/hospital_list_tile.dart';
import 'package:eroute_mobile/features/hospital_detail/presentation/hospital_clinical_information.dart';
import 'package:eroute_mobile/features/member_ui/member_widgets.dart';
import 'support/catalog_fixture.dart';
import 'support/category_visual_fixture.dart';
import 'support/hospital_personalization_flow_fixture.dart';
import 'support/disease_fixtures.dart';
import 'support/synthetic_personalization.dart';
import 'hospital_clinical_information_test.dart' show state, data, clinicalJson;
import 'emergency_map_test.dart' show hospital;
import 'main_flow_test.dart' show captureQa;

void main() {
  final catalog = DiseaseCatalog.fromJson(catalogJson());
  final expected = <String, (IconData, MemberTone?)>{
    'CAT_CARDIOVASCULAR': (Icons.favorite_border, MemberTone.allergy),
    'CAT_RESPIRATORY': (Icons.air, null),
    'CAT_ENDOCRINE_METABOLIC': (Icons.science_outlined, MemberTone.medication),
    'CAT_RENAL': (Icons.water_drop_outlined, MemberTone.note),
    'CAT_GI_LIVER': (Icons.restaurant_outlined, MemberTone.medication),
    'CAT_RHEUM_IMMUNE': (Icons.shield_outlined, MemberTone.condition),
    'CAT_NEURO': (Icons.psychology_outlined, MemberTone.condition),
    'CAT_MENTAL': (Icons.self_improvement, MemberTone.note),
    'CAT_DERM_ALLERGY': (Icons.healing_outlined, MemberTone.allergy),
    'CAT_ENT': (Icons.hearing_outlined, null),
    'CAT_OPHTHALMOLOGY': (Icons.visibility_outlined, null),
    'CAT_UROLOGY': (Icons.medical_services_outlined, MemberTone.note),
    'CAT_OBGYN': (Icons.female, MemberTone.allergy),
    'CAT_MSK_REHAB': (Icons.accessibility_new, MemberTone.medication),
  };
  test('all 14 original category icon/tone pairs preserved', () {
    expect(catalog.categories.map((c) => c.id).toSet(), expected.keys.toSet());
    for (final entry in expected.entries) {
      final visual = DiseaseCategoryVisualRegistry.forCategory(entry.key);
      expect((visual.icon, visual.tone), entry.value);
      expect(visual.neutral, isFalse);
    }
  });
  for (final sample in {
    'D001': 'CAT_RESPIRATORY',
    'D003': 'CAT_CARDIOVASCULAR',
    'D017': 'CAT_ENDOCRINE_METABOLIC',
    'D009': 'CAT_RENAL',
    'D032': 'CAT_MENTAL',
  }.entries) {
    test('${sample.key} resolves through catalog ${sample.value}', () {
      expect(catalog.byId(sample.key)!.category, sample.value);
      final visual = DiseaseCategoryVisualRegistry.forDiseases(catalog, [
        sample.key,
      ]);
      expect((visual.icon, visual.tone), expected[sample.value]);
    });
  }
  test('same category aggregates, mixed categories never pick first', () {
    expect(
      DiseaseCategoryVisualRegistry.forDiseases(catalog, [
        'D001',
        'D002',
        'D001',
      ]).icon,
      Icons.air,
    );
    for (final ids in [
      ['D001', 'D003'],
      ['D003', 'D001'],
    ]) {
      expect(
        DiseaseCategoryVisualRegistry.forDiseases(catalog, ids),
        same(DiseaseCategoryVisualRegistry.multiple),
      );
    }
  });
  test(
    'catalog membership owns visuals including inactive and unknown categories',
    () {
      final json = catalogJson();
      final disease = (json['diseases'] as List).firstWhere(
        (d) => d['id'] == 'D001',
      );
      disease['active'] = false;
      (json['quickPickDiseaseIds'] as List).remove('D001');
      disease['categoryId'] = 'CAT_RENAL';
      expect(
        DiseaseCategoryVisualRegistry.forDiseases(
          DiseaseCatalog.fromJson(json),
          ['D001'],
        ).icon,
        Icons.water_drop_outlined,
      );
      (json['categories'] as List).add({
        'id': 'FUTURE_CATEGORY',
        'name': '미래 분류',
        'sortOrder': 100,
      });
      disease['categoryId'] = 'FUTURE_CATEGORY';
      expect(
        DiseaseCategoryVisualRegistry.forDiseases(
          DiseaseCatalog.fromJson(json),
          ['D001'],
        ),
        same(DiseaseCategoryVisualRegistry.unknown),
      );
      for (final ids in [
        <String>[],
        ['CUSTOM'],
        ['D001', 'MISSING'],
      ]) {
        expect(
          DiseaseCategoryVisualRegistry.forDiseases(catalog, ids),
          same(DiseaseCategoryVisualRegistry.unknown),
        );
      }
      expect(DiseaseCategoryVisualRegistry.unknown.neutral, isTrue);
      expect(
        DiseaseCategoryVisualRegistry.forDiseases(null, ['D001']),
        same(DiseaseCategoryVisualRegistry.unknown),
      );
    },
  );
  setUpAll(() async {
    await (FontLoader(
      'NotoSansKR',
    )..addFont(rootBundle.load('assets/fonts/NotoSansKR.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  final source = FlowData();
  HospitalDiseaseMatchResult match(List<String> ids) => source.preview.match(
    source.referenceValue,
    confirmedSelection(source.referenceValue, ids),
    syntheticDepartmentSnapshot(names: ['내과']),
    DateTime.now(),
  )!;
  final scenarios = <String, List<String>>{
    'single': ['D001'],
    'same': ['D001', 'D002'],
    'mixed': ['D001', 'D003'],
  };
  for (final dark in [false, true]) {
    for (final scenario in scenarios.entries) {
      testWidgets(
        'actual map context ${scenario.key} dark=$dark and search unchanged',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final f = FlowFixture(dark: dark);
          await f.container.read(sessionControllerProvider.future);
          f.member.data = flowHealth(
            f.member.data,
            local: LocalConditions(
              userId: f.member.user['userId'],
              epoch: f.member.epoch,
              baseVersion: 1,
              catalogVersion: catalog.version,
              status: 'RECORDED',
              entries: [
                for (final id in scenario.value)
                  EmergencyCondition.standard(id, catalog.byId(id)!.name),
              ],
            ),
            selection: confirmedSelection(
              f.data.referenceValue,
              scenario.value,
            ),
          );
          final key = GlobalKey();
          await tester.pumpWidget(RepaintBoundary(key: key, child: f.app()));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byWidgetPredicate(
              (w) => w is Text && w.semanticsLabel == '가까운 병원 찾기',
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('DEV · 질환 개인화 미리보기'), findsNothing);
          final button = find.byKey(const ValueKey('personalization-context'));
          final icon = scenario.key == 'mixed'
              ? Icons.health_and_safety_outlined
              : Icons.air;
          expect(
            find.descendant(of: button, matching: find.byIcon(icon)),
            findsOneWidget,
          );
          final contextButton = tester.widget<TextButton>(
            find.descendant(of: button, matching: find.byType(TextButton)),
          );
          final cardButton = tester.widget<TextButton>(
            find.descendant(
              of: find.byType(PersonalizationBadge).first,
              matching: find.byType(TextButton),
            ),
          );
          expect(
            contextButton.style!.foregroundColor!.resolve({}),
            cardButton.style!.foregroundColor!.resolve({}),
          );
          expect(
            contextButton.style!.backgroundColor!.resolve({}),
            cardButton.style!.backgroundColor!.resolve({}),
          );
          final results = f.container.read(mapControllerProvider).result!;
          expect(results.hospitals.map((h) => h.hpid), [
            'QA_A',
            'QA_B',
            'QA_C',
          ]);
          expect(results.radius, 10000);
          await captureQa(
            tester,
            key,
            'category-visual/map-${scenario.key}-${dark ? 'dark' : 'light'}',
          );
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(find.text('개발 미리보기 · 검수 중'), findsOneWidget);
          await captureQa(
            tester,
            key,
            'category-visual/context-${scenario.key}-${dark ? 'dark' : 'light'}',
          );

          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          f.container.dispose();
          expect(tester.takeException(), isNull);
        },
      );
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'card and detail ${scenario.key} 320dp dark=$dark scale=$scale',
          (tester) async {
            tester.view.physicalSize = const Size(320, 850);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final key = GlobalKey();
            final result = match(scenario.value);
            await tester.pumpWidget(
              withVisualCatalog(
                MaterialApp(
                  theme: dark ? ERouteTheme.dark() : ERouteTheme.light(),
                  home: MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                    child: Scaffold(
                      body: SingleChildScrollView(
                        child: RepaintBoundary(
                          key: key,
                          child: Column(
                            children: [
                              HospitalListTile(
                                hospital: hospital(),
                                personalization: result,
                                manual: false,
                                selected: false,
                                onTap: () {},
                              ),
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: HospitalClinicalInformation(
                                  state: state(AsyncData(data(clinicalJson()))),
                                  personalization: result,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final icon = scenario.key == 'mixed'
                ? Icons.health_and_safety_outlined
                : Icons.air;
            expect(
              find.descendant(
                of: find.byType(PersonalizationBadge),
                matching: find.byIcon(icon),
              ),
              findsNWidgets(2),
            );
            final buttons = tester
                .widgetList<TextButton>(
                  find.descendant(
                    of: find.byType(PersonalizationBadge),
                    matching: find.byType(TextButton),
                  ),
                )
                .toList();
            expect(
              buttons[0].style!.foregroundColor!.resolve({}),
              buttons[1].style!.foregroundColor!.resolve({}),
            );
            expect(
              find.text('실제 진료 가능 여부 또는 현재 수용 가능을 의미하지 않습니다.'),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
            await captureQa(
              tester,
              key,
              'category-visual/card-detail-${scenario.key}-${dark ? 'dark' : 'light'}-${scale}x',
            );
          },
        );
      }
    }
  }
  for (final dark in [false, true]) {
    testWidgets('long disease and department 320dp 200% dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const reason = DepartmentMatchReason(
        diseaseId: 'D001',
        diseaseName: '아주 긴 한국어 질환 표시명을 위한 합성 테스트 질환',
        mappingId: 'SYNTHETIC',
        canonicalDepartmentId: 'TEST',
        canonicalDepartmentName: '아주 긴 한국어 진료과 표시명 합성 테스트',
        hospitalDepartmentName: '합성 테스트',
        hospitalDepartmentRaw: '합성 테스트',
        hospitalSource: 'TEST',
        reviewClass: 'BROAD_PARENT_REVIEW_REQUIRED',
      );
      final result = HospitalDiseaseMatchResult(
        syntheticDepartmentSnapshot(),
        'TEST',
        [
          DiseaseMatch('D001', DepartmentMatchStatus.match, [reason], {}),
        ],
        reviewPreview: true,
      );
      final key = GlobalKey();
      await tester.pumpWidget(
        withVisualCatalog(
          MaterialApp(
            theme: dark ? ERouteTheme.dark() : ERouteTheme.light(),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: RepaintBoundary(
                    key: key,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: HospitalClinicalInformation(
                        state: state(AsyncData(data(clinicalJson()))),
                        personalization: result,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.air), findsOneWidget);
      expect(find.textContaining(reason.diseaseName), findsOneWidget);
      expect(tester.takeException(), isNull);
      await captureQa(
        tester,
        key,
        'category-visual/long-detail-${dark ? 'dark' : 'light'}-2.0x',
      );
    });
  }
  testWidgets(
    'catalog loading/error is neutral; late public metadata cannot resurrect removed private button',
    (tester) async {
      final pending = Completer<DiseaseCatalog>();
      final container = ProviderContainer(
        overrides: [
          personalizationVisualCatalogProvider.overrideWith(
            (ref) => pending.future,
          ),
        ],
      );
      Widget host(Widget child) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: child)),
      );
      await tester.pumpWidget(
        host(
          PersonalizationCategoryButton(
            diseaseIds: const ['D001'],
            label: '테스트',
            onPressed: () {},
          ),
        ),
      );
      expect(find.byIcon(Icons.medical_services_outlined), findsOneWidget);
      await tester.pumpWidget(host(const SizedBox()));
      pending.complete(catalog);
      await tester.pumpAndSettle();
      expect(find.byType(PersonalizationCategoryButton), findsNothing);
      container.dispose();
      final repository = FixtureCatalogRepository()..offline = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            diseaseCatalogRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            home: Scaffold(body: PersonalizationBadge(result: match(['D001']))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.medical_services_outlined), findsOneWidget);
      expect(find.text('천식 · 내과'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
