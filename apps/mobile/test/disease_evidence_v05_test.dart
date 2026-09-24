import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eroute_mobile/development/disease_review_preview.dart';
import 'package:eroute_mobile/features/disease_personalization/disease_reference.dart';
import 'package:eroute_mobile/features/disease_personalization/disease_repository.dart';
import 'package:eroute_mobile/features/disease_personalization/department_matcher.dart';
import 'package:eroute_mobile/features/disease_personalization/personalization_presentation.dart';
import 'support/disease_fixtures.dart';
import 'support/evidence_v04_reference.dart';
import 'support/synthetic_personalization.dart';

class _LiveHttpOverrides extends HttpOverrides {}

void main() {
  const runtimeUrl = String.fromEnvironment('EROUTE_RUNTIME_SMOKE_URL');
  final data =
      jsonDecode(
            File(
              '../../services/backend/src/main/resources/reference/disease-departments/v0.5.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final raw = DiseaseReference.decode(referenceEnvelope(jsonEncode(data)));
  final publicData = Map<String, dynamic>.from(data)..['mappings'] = [];
  final catalog = DiseaseReference.decode(
    referenceEnvelope(jsonEncode(publicData)),
  );
  final old = evidenceV04Reference();
  final oldRaw = evidenceV04Reference(published: false);
  Map<String, dynamic> projection(
    DiseaseReference reference,
    DiseaseReference candidates,
  ) {
    final classes =
        jsonDecode(
              File(
                '../../services/backend/src/development/resources/reference/review-classes-${reference.version.endsWith('v0.5') ? 'v0.5' : 'v0.4'}.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    return {
      'documentType': 'DEVELOPMENT_REVIEW_PREVIEW',
      'referenceVersion': reference.version,
      'mappings': [
        for (final m in candidates.mappings)
          {
            'id': m.id,
            'diseaseId': m.diseaseId,
            'departmentId': m.departmentId,
            'relationType': m.relation,
            'reviewStatus': m.reviewStatus,
            'reviewClass': (classes['mappings'] as List).singleWhere(
              (r) => r['mappingId'] == m.id,
            )['reviewClass'],
          },
      ],
    };
  }

  final preview = ReviewPreviewCandidates.decode(
    projection(catalog, raw),
    catalog,
  );
  final prior = ReviewPreviewCandidates.decode(projection(old, oldRaw), old);
  final now = DateTime.now();

  if (runtimeUrl.isNotEmpty) {
    test(
      'live development API through RemoteDiseaseDataRepository is v05',
      () async {
        await HttpOverrides.runWithHttpOverrides(() async {
          final dio = Dio(BaseOptions(baseUrl: runtimeUrl));
          try {
            final active = await RemoteDiseaseDataRepository(dio).reference();
            expect(active.version, catalog.version);
            expect(active.diseases.length, 46);
            expect(active.departments.length, 51);
            expect(active.mappings, isEmpty);
            for (final disease in catalog.diseases) {
              expect(
                active.search(disease.name).map((d) => d.id),
                catalog.search(disease.name).map((d) => d.id),
              );
            }
          } finally {
            dio.close(force: true);
          }
        }, _LiveHttpOverrides());
      },
    );
  }

  test('v05 parses 36 exact and 25 broad scopes while all 61 stay DRAFT', () {
    expect(raw.version, 'eroute-disease-departments-v0.5');
    expect(raw.mappings.length, 61);
    expect(
      raw.mappings
          .where((m) => m.mappingScope == MappingScope.exactCanonical)
          .length,
      36,
    );
    expect(
      raw.mappings
          .where((m) => m.mappingScope == MappingScope.broadParent)
          .length,
      25,
    );
    expect(raw.mappings.every((m) => m.reviewStatus == 'DRAFT'), isTrue);
    expect(catalog.mappings, isEmpty);
    expect(publicDiseaseMapEnabled, isFalse);
    final result = matchDepartments(
      reference: raw,
      selection: confirmedSelection(
        raw,
        raw.diseases.map((d) => d.id).toList(),
      ),
      hospital: syntheticDepartmentSnapshot(
        names: raw.departments.values.toList(),
        now: now,
      ),
      now: now,
      enabled: true,
      allowDraft: true,
    )!;
    expect(result.matched, isFalse);
    expect(result.matchCount, 0);
    expect(approvedAccent(result), PersonalizationAccent.none);
  });

  test('every disease name and alias retains identical search results', () {
    expect(catalog.diseases.length, 46);
    expect(catalog.departments, old.departments);
    for (final disease in old.diseases) {
      for (final term in [disease.name, ...disease.aliases]) {
        expect(
          catalog.search(term).map((d) => d.id),
          old.search(term).map((d) => d.id),
          reason: term,
        );
      }
    }
  });

  test('all 61 relation presentations remain filled 6 hollow 30 none 25', () {
    final counts = <PersonalizationAccent, int>{};
    for (final mapping in raw.mappings) {
      final hospital = syntheticDepartmentSnapshot(
        names: [catalog.departments[mapping.departmentId]!],
        now: now,
      );
      final result = preview.match(
        catalog,
        confirmedSelection(catalog, [mapping.diseaseId]),
        hospital,
        now,
      )!;
      final before = prior.match(
        old,
        confirmedSelection(old, [mapping.diseaseId]),
        hospital,
        now,
      )!;
      expect(result.matched, isTrue, reason: mapping.id);
      expect(result.matchedDiseases, before.matchedDiseases);
      expect(result.matchedDepartments, before.matchedDepartments);
      expect(result.matchCount, before.matchCount);
      final accent = reviewPreviewAccent(result);
      expect(accent, reviewPreviewAccent(before), reason: mapping.id);
      expect(approvedAccent(result), PersonalizationAccent.none);
      counts.update(accent, (n) => n + 1, ifAbsent: () => 1);
    }
    expect(counts, {
      PersonalizationAccent.filled: 6,
      PersonalizationAccent.hollow: 30,
      PersonalizationAccent.none: 25,
    });
  });

  test(
    '46 diseases across 51 canonical departments retain preview matching',
    () {
      for (final disease in catalog.diseases) {
        for (final department in catalog.departments.values) {
          final hospital = syntheticDepartmentSnapshot(
            names: [department],
            now: now,
          );
          final result = preview.match(
            catalog,
            confirmedSelection(catalog, [disease.id]),
            hospital,
            now,
          )!;
          final before = prior.match(
            old,
            confirmedSelection(old, [disease.id]),
            hospital,
            now,
          )!;
          expect(
            result.matched,
            before.matched,
            reason: '${disease.id}/$department',
          );
          expect(result.matchCount, before.matchCount);
          expect(reviewPreviewAccent(result), reviewPreviewAccent(before));
        }
      }
    },
  );

  test(
    'extra evidence scope in preview payload cannot promote reviewClass',
    () {
      final payload = projection(catalog, raw);
      for (final row in payload['mappings'] as List) {
        row['mappingScope'] = (data['mappings'] as List).singleWhere(
          (m) => m['id'] == row['id'],
        )['mappingScope'];
      }
      final decoded = ReviewPreviewCandidates.decode(payload, catalog);
      expect(decoded.mappings.every((m) => m.mappingScope != null), isTrue);
      expect(
        decoded.mappings
            .where((m) => m.reviewClass == 'REVIEW_REQUIRED')
            .length,
        30,
      );
      final stale = projection(catalog, raw)
        ..['referenceVersion'] = old.version;
      expect(
        () => ReviewPreviewCandidates.decode(stale, catalog),
        throwsFormatException,
      );
    },
  );
}
