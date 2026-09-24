import 'package:flutter_test/flutter_test.dart';
import 'package:eroute_mobile/features/disease_personalization/department_matcher.dart';
import 'package:eroute_mobile/features/disease_personalization/map_personalization_controller.dart';
import 'package:eroute_mobile/features/disease_personalization/map_disease_selection.dart';
import 'package:eroute_mobile/features/app_menu/app_session.dart';
import 'support/evidence_v04_reference.dart';
import 'support/disease_fixtures.dart';
import 'support/synthetic_personalization.dart';
import 'personalization_foundation_test.dart'
    show SyntheticPublicRepository, SyntheticSelectionRepository;

void main() {
  test(
    '46 active catalog entries decode with exact provided search aliases',
    () {
      final reference = evidenceV04Reference();
      expect(reference.diseases.where((d) => d.active).length, 46);
      expect(reference.mappings, isEmpty);
      const queries = {
        '당뇨병': 'D017',
        '당뇨': 'D017',
        '루푸스': 'D025',
        'SLE': 'D025',
        'IPF': 'D023',
        'MS': 'D028',
        '알츠하이머': 'D029',
        '전립선비대증': 'D035',
        'BPH': 'D035',
        'PCOS': 'D042',
        '우울증': 'D032',
        '녹내장': 'D039',
        '자궁내막증': 'D041',
        '건선': 'D045',
        '허리디스크': 'D044',
      };
      for (final entry in queries.entries) {
        expect(reference.search(entry.key).map((d) => d.id).toList(), [
          entry.value,
        ], reason: entry.key);
      }
    },
  );
  test(
    'all 61 actual candidate relations remain excluded even with a draft override',
    () {
      final reference = evidenceV04Reference(published: false);
      expect(reference.mappings.length, 61);
      final ids = reference.diseases.map((d) => d.id).toList();
      final result = matchDepartments(
        reference: reference,
        selection: confirmedSelection(reference, ids),
        hospital: syntheticDepartmentSnapshot(
          names: reference.departments.values.toList(),
        ),
        now: DateTime.now(),
        enabled: true,
        allowDraft: true,
      )!;
      expect(result.matched, isFalse);
      expect(result.matchCount, 0);
      expect(result.matchedDiseases, isEmpty);
      expect(result.unknownReasons, contains('NO_APPROVED_MAPPING'));
      expect(reference.diseases.any((d) => reference.supports(d.id)), isFalse);
    },
  );
  test(
    'recorded and separately confirmed staging tags yields prepared state and no hospital fetch or gold results',
    () async {
      final data = SyntheticPublicRepository()..value = evidenceV04Reference();
      final selections = SyntheticSelectionRepository()
        ..value = MapSelectionSnapshot(
          2,
          1,
          confirmedSelection(data.value, ['D001', 'D003', 'D010', 'D017']),
        );
      final controller = MapPersonalizationController(
        data,
        selections,
        () => const AppSession(
          phase: SessionPhase.authenticated,
          user: {'userId': 'V04_TEST_USER'},
          generation: 1,
        ),
        available: true,
      );
      addTearDown(controller.dispose);
      await controller.enable();
      expect(controller.state.message, '관련 진료과 정보 준비 중');
      expect(controller.state.results, isEmpty);
      expect(data.departmentReads, 0);
    },
  );
}
