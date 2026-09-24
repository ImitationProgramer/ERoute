import 'package:eroute_mobile/features/disease_personalization/personalization_presentation.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:eroute_mobile/development/disease_review_preview.dart';
import 'package:eroute_mobile/features/disease_personalization/disease_reference.dart';
import 'package:eroute_mobile/features/disease_personalization/department_matcher.dart';
import 'package:eroute_mobile/features/disease_personalization/map_disease_selection.dart';
import 'support/personalization_qa.dart';

void main() {
  const input = String.fromEnvironment('QA_BUNDLE_PATH');
  const output = String.fromEnvironment('QA_REPORT_PATH');
  test(
    'replay stored public data with the real matcher and explicit QA selection',
    () {
      final bundle =
          jsonDecode(File(input).readAsStringSync()) as Map<String, dynamic>;
      final reference = DiseaseReference.decode(bundle['reference']);
      final preview = ReviewPreviewCandidates.decode(
        bundle['preview'],
        reference,
      );
      final now = DateTime.parse(bundle['evaluatedAt']);
      final ids = (bundle['selectedDiseaseIds'] as List).cast<String>();
      final selection = MapDiseaseSelection(
        state: 'CONFIRMED',
        diseaseIds: ids,
        purpose: reference.purpose,
        purposeVersion: reference.purposeVersion,
        referenceVersion: reference.version,
        confirmedAt: now,
      );
      final hpids = (bundle['search']['hospitals'] as List)
          .map((h) => h['hpid'] as String)
          .toList();
      final results = (bundle['departments'] as List).map(
        (h) => preview.match(
          reference,
          selection,
          DepartmentSnapshot.fromJson(h),
          now,
        )!,
      );
      final report = {
        'referenceVersion': reference.version,
        'referenceSha256': reference.sha256Hash,
        'evaluatedAt': bundle['evaluatedAt'],
        'center': bundle['center'],
        'requestedRadius': bundle['requestedRadius'],
        'searchMeta': bundle['search']['meta'],
        'selectedDiseaseIds': ids,
        'ringEligibleHpids': [
          for (final r in results)
            if (personalizationRingEligible(r, previewAllowed: true))
              r.hospital.hpid,
        ],
        'matchedScopes': {
          for (final r in results)
            if (r.matched)
              r.hospital.hpid: [
                for (final m in r.matches) m.mappingScope?.name,
              ],
        },
        ...personalizationQaSummary(
          searchHpids: hpids,
          selectedDiseaseIds: ids.toSet(),
          results: results,
        ),
      };
      expect(
        report['hospitalCount'],
        (report['match'] as int) +
            (report['unknown'] as int) +
            (report['noMatch'] as int),
      );
      File(output).writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
    },
    skip: input.isEmpty || output.isEmpty
        ? 'Explicit stored QA bundle only'
        : false,
  );
}
