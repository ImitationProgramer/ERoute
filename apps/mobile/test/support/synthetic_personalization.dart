// Test-only medical-free reference. Never imported by lib/ or shipped as an asset.
import 'dart:convert';
import 'disease_fixtures.dart';
import 'package:eroute_mobile/features/disease_personalization/disease_reference.dart';
import 'package:eroute_mobile/features/disease_personalization/department_matcher.dart';

Map<String, dynamic> syntheticReferenceData({bool approved = true}) {
  final evidence = <String, dynamic>{
    'sourceName': 'Synthetic fixture only',
    'sourceUrl': 'https://example.invalid/synthetic',
    'checkedAt': '2026-09-17T00:00:00Z',
    'rawDepartmentText': 'TEST_DEPARTMENT',
    'notes': 'Not clinical evidence',
  };
  final approval = {
    'reviewer': 'Synthetic test reviewer',
    'approvedAt': '2026-09-17T01:00:00Z',
    'version': 1,
  };
  Map<String, Object?> mapping(
    String id,
    String disease,
    String department, {
    bool draft = false,
  }) => {
    'id': id,
    'diseaseId': disease,
    'departmentId': department,
    'relationType': 'DIRECT',
    'mappingScope': 'EXACT_CANONICAL',
    'reviewStatus': approved && !draft ? 'APPROVED' : 'DRAFT',
    'version': 1,
    'evidence': [evidence],
    'approval': approved && !draft ? approval : null,
  };
  return {
    'schemaVersion': 2,
    'datasetVersion': 'synthetic-v1',
    'catalogVersion': 'synthetic-catalog-v1',
    'vocabularyVersion': 'synthetic-vocabulary-v1',
    'purpose': 'TEST_PURPOSE',
    'purposeVersion': 'synthetic-purpose-v1',
    'status': 'READY',
    'publicMapApproved': false,
    'diseases': [
      for (final id in ['TEST_DISEASE', 'TEST_DISEASE_2', 'TEST_DRAFT_DISEASE'])
        {
          'id': id,
          'displayName': id,
          'aliases': <String>[],
          'category': 'synthetic',
          'active': true,
          'lifecycleStatus': 'ACTIVE',
          'version': 1,
        },
    ],
    'departments': [
      for (final id in ['TEST_DEPARTMENT', 'TEST_DEPARTMENT_2'])
        {'id': id, 'canonicalName': id, 'active': true, 'version': 1},
    ],
    'mappings': [
      mapping('M1', 'TEST_DISEASE', 'TEST_DEPARTMENT'),
      mapping('M2', 'TEST_DISEASE', 'TEST_DEPARTMENT_2'),
      mapping('M3', 'TEST_DISEASE_2', 'TEST_DEPARTMENT'),
      mapping('M4', 'TEST_DRAFT_DISEASE', 'TEST_DEPARTMENT', draft: true),
    ],
    'departmentAliases': [
      {
        'alias': 'TEST_ALIAS',
        'departmentId': 'TEST_DEPARTMENT',
        'reviewStatus': approved ? 'APPROVED' : 'DRAFT',
        'version': 1,
        'evidence': evidence,
        'approval': approved ? approval : null,
      },
    ],
    'broadDepartmentNames': ['TEST_DEPARTMENT'],
  };
}

DiseaseReference syntheticReference({bool approved = true}) =>
    DiseaseReference.decode(
      referenceEnvelope(jsonEncode(syntheticReferenceData(approved: approved))),
    );
DepartmentSnapshot syntheticDepartmentSnapshot({
  List<String> names = const ['TEST_DEPARTMENT'],
  String hpid = 'SYNTHETIC_HOSPITAL',
  DateTime? now,
  bool stale = false,
}) {
  final time = now ?? DateTime.now();
  return DepartmentSnapshot(
    hpid: hpid,
    recordStatus: 'PROVIDED',
    departmentsStatus: 'KNOWN',
    snapshotId: 1,
    datasetVersion: 'synthetic-public-v1',
    normalizerVersion: 'synthetic',
    fetchedAt: time,
    validUntil: time.add(const Duration(days: 7)),
    stale: stale,
    departments: names.map((n) => DepartmentToken(n, n, 'SYNTHETIC', 'KNOWN')),
  );
}
