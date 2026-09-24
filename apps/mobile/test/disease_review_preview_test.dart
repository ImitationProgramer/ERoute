import 'support/category_visual_fixture.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eroute_mobile/development/disease_review_preview.dart';
import 'package:eroute_mobile/features/disease_personalization/department_matcher.dart';
import 'package:eroute_mobile/features/disease_personalization/personalization_badge.dart';
import 'package:eroute_mobile/features/disease_personalization/map_disease_selection.dart';
import 'package:eroute_mobile/features/disease_personalization/map_personalization_controller.dart';
import 'package:eroute_mobile/features/app_menu/app_session.dart';
import 'support/evidence_v04_reference.dart';
import 'support/disease_fixtures.dart';
import 'support/synthetic_personalization.dart';
import 'personalization_foundation_test.dart'
    show SyntheticPublicRepository, SyntheticSelectionRepository;
import 'personalization_overlay_test.dart' show syntheticSearch;

void main() {
  final catalog = evidenceV04Reference();
  final raw = evidenceV04Reference(published: false);
  final worksheet = jsonDecode(
    File(
      '../../docs/qa/disease-evidence-v04-2026-09-18/review-inputs.json',
    ).readAsStringSync(),
  );
  Map<String, dynamic> projection() => {
    'documentType': 'DEVELOPMENT_REVIEW_PREVIEW',
    'referenceVersion': catalog.version,
    'mappings': [
      for (final m in raw.mappings)
        {
          'id': m.id,
          'diseaseId': m.diseaseId,
          'departmentId': m.departmentId,
          'relationType': m.relation,
          'reviewStatus': m.reviewStatus,
          'reviewClass': (worksheet['mappings'] as List).firstWhere(
            (r) => r['mappingId'] == m.id,
          )['reviewClass'],
        },
    ],
  };
  final candidates = ReviewPreviewCandidates.decode(projection(), catalog);
  final now = DateTime.now();
  HospitalDiseaseMatchResult evaluate(
    List<String> names,
    List<String> departments, {
    bool stale = false,
  }) => candidates.match(
    catalog,
    confirmedSelection(
      catalog,
      names
          .map((n) => catalog.diseases.singleWhere((d) => d.name == n).id)
          .toList(),
    ),
    syntheticDepartmentSnapshot(names: departments, now: now, stale: stale),
    now,
  )!;
  test(
    'actual v0.4 seven canonical candidates without promotion or inferred hierarchy',
    () {
      for (final entry in {
        '천식': '내과',
        '뇌전증': '신경과',
        '건선': '피부과',
        '메니에르병': '이비인후과',
        '녹내장': '안과',
        '요로결석': '비뇨의학과',
        '자궁내막증': '산부인과',
      }.entries) {
        final r = evaluate([entry.key], [entry.value]);
        expect(r.matched, isTrue);
        expect(r.reviewPreview, isTrue);
        expect(r.matches.single.canonicalDepartmentName, entry.value);
        expect(r.matches.single.reviewClass, isNotNull);
      }
      expect(
        evaluate(['천식'], ['내과']).matches.single.reviewClass,
        'BROAD_PARENT_REVIEW_REQUIRED',
      );
      for (final name in ['호흡기내과', '심장내과', '소화기내과', '내과의원']) {
        expect(evaluate(['천식'], [name]).matched, isFalse);
      }
      expect(catalog.mappings, isEmpty);
      expect(
        matchDepartments(
          reference: raw,
          selection: confirmedSelection(raw, ['D001']),
          hospital: syntheticDepartmentSnapshot(names: ['내과']),
          now: now,
          enabled: true,
        )!.matched,
        isFalse,
      );
    },
  );
  test(
    'multiple diseases retain paired reasons and one result with unique departments',
    () {
      final r = evaluate(['천식', '건선'], ['내과', '피부과']);
      expect(r.matchedDiseases, {'D001', 'D045'});
      expect(r.matchCount, 2);
      expect(r.matches.map((m) => m.diseaseName), ['천식', '건선']);
    },
  );
  test('stale, missing and invalid projection fail closed', () {
    expect(
      evaluate(['천식'], ['내과'], stale: true).status,
      DepartmentMatchStatus.unknown,
    );
    expect(evaluate(['천식'], []).status, DepartmentMatchStatus.unknown);
    expect(evaluate(['건선'], ['신경과']).status, DepartmentMatchStatus.noMatch);
    final p = projection();
    p['referenceVersion'] = 'other';
    expect(
      () => ReviewPreviewCandidates.decode(p, catalog),
      throwsFormatException,
    );
    final approved = projection();
    approved['mappings'][0]['reviewStatus'] = 'APPROVED';
    expect(
      () => ReviewPreviewCandidates.decode(approved, catalog),
      throwsFormatException,
    );
  });
  test(
    'preview defaults off, no reads, pending response discarded on disable',
    () async {
      final data = SyntheticPublicRepository()..value = catalog;
      final selection = SyntheticSelectionRepository()
        ..value = MapSelectionSnapshot(
          1,
          1,
          confirmedSelection(catalog, ['D001']),
        );
      final c = MapPersonalizationController(
        data,
        selection,
        () => const AppSession(
          phase: SessionPhase.authenticated,
          user: {'userId': 'isolated-qa'},
        ),
        available: true,
        supports: (r, id) => candidates.mappings.any((m) => m.diseaseId == id),
        match: candidates.match,
      );
      expect(c.state.enabled, isFalse);
      c.setSearch(syntheticSearch());
      expect(selection.reads, 0);
      expect(data.reads, 0);
      data.pending = Completer<List<DepartmentSnapshot>>();
      final pending = c.enable();
      await Future<void>.delayed(Duration.zero);
      expect(c.state.loading, isTrue);
      c.disable();
      data.pending!.complete([
        syntheticDepartmentSnapshot(names: ['내과']),
      ]);
      await pending;
      expect(c.state.results, isEmpty);
      expect(c.state.enabled, isFalse);
      c.dispose();
    },
  );
  testWidgets(
    'preview badge is distinct and shows exact paired reason and limits',
    (tester) async {
      await tester.pumpWidget(
        withVisualCatalog(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: PersonalizationBadge(
                  result: evaluate(['천식', '건선'], ['내과', '피부과']),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('등록한 질환과 관련된 진료과 확인'), findsNothing);
      await tester.tap(find.text('내 질환 관련 · 진료과 2개'));
      await tester.pumpAndSettle();
      expect(find.textContaining('등록한 질환: 천식'), findsOneWidget);
      expect(find.textContaining('등록한 질환: 건선'), findsOneWidget);
      expect(find.textContaining('BROAD_PARENT_REVIEW_REQUIRED'), findsNothing);
      expect(find.text('관계 범위: 상위 진료과 후보'), findsOneWidget);
      expect(find.text('검수 상태: 개발 검수 중'), findsNWidgets(2));
      expect(
        find.textContaining('현재 환자 수용 가능 여부를 의미하지 않습니다.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
