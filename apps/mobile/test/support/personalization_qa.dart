import 'package:eroute_mobile/features/disease_personalization/department_matcher.dart';
import 'package:eroute_mobile/features/disease_personalization/personalization_presentation.dart';
import 'package:eroute_mobile/development/disease_review_preview.dart';

/// Explicit synthetic selection + public hospitals only. Not runtime telemetry.
Map<String, Object?> personalizationQaSummary({
  required List<String> searchHpids,
  required Set<String> selectedDiseaseIds,
  required Iterable<HospitalDiseaseMatchResult> results,
}) {
  final rows = {for (final r in results) r.hospital.hpid: r};
  if (rows.length != searchHpids.length ||
      !rows.keys.toSet().containsAll(searchHpids)) {
    throw StateError('Incomplete QA results');
  }
  final matches = rows.values.where((r) => r.matched).toList();
  return {
    'hospitalCount': searchHpids.length,
    'searchHpidsInDistanceOrder': searchHpids,
    'match': matches.length,
    'unknown': rows.values
        .where((r) => r.status == DepartmentMatchStatus.unknown)
        .length,
    'noMatch': rows.values
        .where((r) => r.status == DepartmentMatchStatus.noMatch)
        .length,
    'matchRatio': searchHpids.isEmpty
        ? null
        : matches.length / searchHpids.length,
    'multipleRelationMatches': matches
        .where((r) => r.matches.map((m) => m.mappingId).toSet().length >= 2)
        .length,
    'allSelectedDiseasesMatched': matches
        .where((r) => r.matchedDiseases.containsAll(selectedDiseaseIds))
        .length,
    'accentCandidates': {
      for (final style in PersonalizationAccent.values)
        style.name: rows.values
            .where(
              (r) =>
                  (r.reviewPreview
                      ? reviewPreviewAccent(r)
                      : approvedAccent(r)) ==
                  style,
            )
            .length,
    },
    'statusRows': [
      for (final id in searchHpids)
        {
          'hpid': id,
          'status': rows[id]!.status.name,
          'unknownReasons': rows[id]!.unknownReasons.toList(),
        },
    ],
    'matches': [
      for (final r in matches)
        {
          'hpid': r.hospital.hpid,
          'matchedDiseases': r.matches
              .map((m) => m.diseaseName)
              .toSet()
              .toList(),
          'matchedDepartments': r.matches
              .map((m) => m.canonicalDepartmentName)
              .toSet()
              .toList(),
          'reasons': [
            for (final m in r.matches)
              {
                'mappingId': m.mappingId,
                'diseaseId': m.diseaseId,
                'candidateCanonical': m.canonicalDepartmentName,
                'hospitalDepartment': m.hospitalDepartmentName,
                'reviewClass': m.reviewClass,
              },
          ],
        },
    ],
  };
}
