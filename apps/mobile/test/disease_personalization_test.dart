import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eroute_mobile/features/disease_personalization/disease_reference.dart';
import 'package:eroute_mobile/features/disease_personalization/department_matcher.dart';
import 'package:eroute_mobile/features/disease_personalization/disease_repository.dart';
import 'package:eroute_mobile/features/disease_personalization/map_disease_selection.dart';
import 'package:eroute_mobile/features/member_ui/member_contract.dart';
import 'support/disease_fixtures.dart';

void main() {
  final ref = backendReference();
  final now = DateTime.utc(2026, 9, 17);
  DepartmentSnapshot hospital(
    List<String> names, {
    bool stale = false,
    String status = 'KNOWN',
  }) => DepartmentSnapshot(
    hpid: 'SYNTHETIC',
    recordStatus: 'PROVIDED',
    departmentsStatus: 'KNOWN',
    datasetVersion: 'test',
    normalizerVersion: 'test',
    snapshotId: 1,
    fetchedAt: now,
    validUntil: now.add(const Duration(days: 7)),
    stale: stale,
    departments: names.map((n) => DepartmentToken(n, n, 'SYNTHETIC', status)),
  );
  HospitalDiseaseMatchResult evaluate(
    List<String> ids,
    List<String> names, {
    bool stale = false,
    String status = 'KNOWN',
  }) => matchDepartments(
    reference: ref,
    selection: confirmedSelection(ref, ids),
    hospital: hospital(names, stale: stale, status: status),
    now: now,
    enabled: true,
    allowDraft: true,
  )!;
  test(
    'one Backend draft reference, aliases suggest but never confirm prose',
    () {
      expect(ref.diseases.length, 16);
      expect(ref.mappings.where((m) => m.relation == 'DIRECT').length, 24);
      expect(ref.mappings.where((m) => m.relation == 'CONTEXTUAL').length, 5);
      expect(
        ref.mappings.where((m) => m.relation == 'REVIEW_REQUIRED').length,
        1,
      );
      expect(ref.search(' COPD ').single.id, 'D002');
      expect(ref.search('기관지천식').single.id, 'D001');
      for (final sentence in [
        '천식이 있습니다',
        '천식 의심',
        '천식 없음',
        '가족이 천식',
        '어릴 때 천식',
      ]) {
        expect(ref.search(sentence), isEmpty);
      }
      expect(publicDiseaseMapEnabled, isFalse);
      final bad = referenceEnvelope();
      bad['sha256'] = 'invalid';
      expect(() => DiseaseReference.decode(bad), throwsFormatException);
      final parsed =
          jsonDecode(backendReferenceDocument()) as Map<String, dynamic>;
      parsed['mappings'][0]['departmentId'] = 'missing';
      expect(
        () => DiseaseReference.decode(referenceEnvelope(jsonEncode(parsed))),
        throwsFormatException,
      );
    },
  );
  test('exact match, broad and missing UNKNOWN, unrelated NO_MATCH', () {
    expect(evaluate(['D001'], ['호흡기내과']).status, DepartmentMatchStatus.match);
    expect(evaluate(['D001'], ['내과']).status, DepartmentMatchStatus.unknown);
    expect(evaluate(['D001'], ['정형외과']).status, DepartmentMatchStatus.noMatch);
    expect(evaluate(['D001'], []).status, DepartmentMatchStatus.unknown);
    expect(
      evaluate(['D001'], ['호흡기 알레르기내과'], status: 'UNVERIFIED').status,
      DepartmentMatchStatus.unknown,
    );
    expect(
      evaluate(['D001'], ['호흡기내과'], stale: true).status,
      DepartmentMatchStatus.unknown,
    );
    expect(
      evaluate(['D001'], ['호흡기내과'], status: 'UNVERIFIED').matches,
      isEmpty,
    );
    expect(evaluate(['D005'], ['심장외과']).matches, isEmpty);
    expect(evaluate(['D009'], ['소아청소년심장과', '신·췌장이식외과']).matches, isEmpty);
  });
  test(
    'multiple disease/direct/hospital reasons and original token survive',
    () {
      final result = evaluate(
        ['D001', 'D002', 'D010'],
        ['호흡기내과', '알레르기내과', '신경과', '신경외과'],
      );
      expect(result.matches.length, 6);
      expect(result.perDiseaseResults.length, 3);
      expect(
        result.matches.every(
          (m) =>
              m.relationType == 'DIRECT' &&
              m.hospitalSource == 'SYNTHETIC' &&
              m.snapshotId == 1 &&
              m.hospitalDepartmentRaw.isNotEmpty,
        ),
        isTrue,
      );
      expect(result.toString(), isNot(contains('D001')));
    },
  );
  test('OFF, DRAFT default, reconfirm, version mismatch do not evaluate', () {
    final selection = confirmedSelection(ref, ['D001']);
    expect(
      matchDepartments(
        reference: ref,
        selection: selection,
        hospital: hospital(['호흡기내과']),
        now: now,
      ),
      isNull,
    );
    expect(
      matchDepartments(
        reference: ref,
        selection: selection,
        hospital: hospital(['호흡기내과']),
        now: now,
        enabled: true,
      ),
      isNull,
    );
    expect(
      matchDepartments(
        reference: ref,
        selection: selection.reconfirm(),
        hospital: hospital(['호흡기내과']),
        now: now,
        enabled: true,
        allowDraft: true,
      ),
      isNull,
    );
    final old = MapDiseaseSelection(
      state: 'CONFIRMED',
      diseaseIds: ['D001'],
      purpose: ref.purpose,
      purposeVersion: ref.purposeVersion,
      referenceVersion: 'old',
      confirmedAt: now,
    );
    expect(
      matchDepartments(
        reference: ref,
        selection: old,
        hospital: hospital(['호흡기내과']),
        now: now,
        enabled: true,
        allowDraft: true,
      ),
      isNull,
    );
  });
  test(
    'raw edit invalidates, NONE clears, unrelated field preserves selection',
    () {
      final base = MemberHealthSnapshot(
        version: 4,
        consentEpoch: 2,
        conditions: const HealthEntry(EntryStatus.recorded, '천식'),
        mapDiseaseSelection: confirmedSelection(ref, ['D001']),
      );
      final edit = applyHealthFieldEdit(
        base,
        const HealthFieldEdit(
          field: HealthField.conditions,
          baseVersion: 4,
          consentEpoch: 2,
          entry: HealthEntry(EntryStatus.recorded, '천식 의심'),
        ),
        now,
      );
      expect(edit.conditions.text, '천식 의심');
      expect(edit.mapDiseaseSelection.state, 'RECONFIRM_REQUIRED');
      expect(
        applyHealthFieldEdit(
          base,
          const HealthFieldEdit(
            field: HealthField.conditions,
            baseVersion: 4,
            consentEpoch: 2,
            entry: HealthEntry(EntryStatus.none),
          ),
          now,
        ).mapDiseaseSelection.diseaseIds,
        isEmpty,
      );
      expect(
        applyHealthFieldEdit(
          base,
          const HealthFieldEdit(
            field: HealthField.note,
            baseVersion: 4,
            consentEpoch: 2,
            note: '가상',
          ),
          now,
        ).mapDiseaseSelection.state,
        'CONFIRMED',
      );
    },
  );
  test('all published DB hospitals reproduce 6 of 16 coverage without API', () {
    final data =
        jsonDecode(
              File(
                '../../contracts/fixtures/department-coverage-2026-09-17.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(data['summary']['masterCount'], 532);
    expect(data['summary']['distinctNormalizedCount'], 51);
    expect(data['referenceSha256'], ref.sha256Hash);
    final counts = {for (final d in ref.diseases) d.id: 0};
    final evaluated = <String>[];
    for (final h in data['hospitals'] as List) {
      if (h['active'] != true) continue;
      final j = Map<String, dynamic>.from(h);
      j['recordStatus'] ??= 'NOT_COLLECTED';
      j['departmentsStatus'] ??= 'MISSING';
      j['datasetVersion'] = data['datasetVersion'];
      j['staleReasons'] = <String>[];
      j['validUntil'] = j['fetchedAt'] == null
          ? null
          : DateTime.parse(
              j['fetchedAt'],
            ).add(const Duration(days: 7)).toIso8601String();
      final result = matchDepartments(
        reference: ref,
        selection: confirmedSelection(ref, counts.keys.toList()),
        hospital: DepartmentSnapshot.fromJson(j),
        now: DateTime.parse(data['observedAt']),
        enabled: true,
        allowDraft: true,
      )!;
      evaluated.add(result.hospital.hpid);
      for (final d in result.perDiseaseResults) {
        if (d.status == DepartmentMatchStatus.match) {
          counts[d.diseaseId] = counts[d.diseaseId]! + 1;
        }
      }
    }
    expect(
      counts,
      Map<String, dynamic>.from(data['summary']['diseaseCoverage']),
    );
    expect(counts.values.where((v) => v > 0).length, 6);
    expect(
      evaluated,
      (data['hospitals'] as List)
          .where((h) => h['active'] == true)
          .map((h) => h['hpid'])
          .toList(),
    );
  });
  test(
    'logout/account/epoch/version/revision clear rejects every late result',
    () async {
      final session = MatchSession();
      final late = Completer<List<HospitalDiseaseMatchResult>>();
      final a = MatchRequestIdentity('A', 1, 2, 3, ref.version, 1);
      final b = MatchRequestIdentity('B', 2, 4, 5, ref.version, 2);
      final pending = session.evaluate(a, () => late.future);
      session.clear();
      await session.evaluate(b, () async => []);
      late.complete([
        evaluate(['D001'], ['호흡기내과']),
      ]);
      await pending;
      expect(session.results, isEmpty);
      expect(session.identity, b);
      session.clear();
      expect(session.identity, isNull);
    },
  );
  test(
    'public repository sends HPIDs only and discards mixed generations',
    () async {
      final dio = Dio();
      var calls = 0;
      final payloads = <Object?>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) {
            payloads.add(r.data);
            expect(r.headers.containsKey('Authorization'), isFalse);
            calls++;
            final version = calls == 1 ? 'one' : 'two';
            final ids = (r.data['hpids'] as List).cast<String>();
            h.resolve(
              Response(
                requestOptions: r,
                data: {
                  'datasetVersion': version,
                  'hospitals': ids
                      .map(
                        (id) => {
                          'hpid': id,
                          'recordStatus': 'NOT_COLLECTED',
                          'departmentsStatus': 'MISSING',
                          'datasetVersion': version,
                          'departments': [],
                          'staleReasons': [],
                        },
                      )
                      .toList(),
                },
              ),
            );
          },
        ),
      );
      final result = await RemoteDiseaseDataRepository(
        dio,
      ).departments(List.generate(101, (i) => 'S$i'));
      expect(calls, 4);
      expect(result.length, 101);
      expect(result.every((h) => h.datasetVersion == 'two'), isTrue);
      expect(payloads.every((p) => (p as Map).keys.single == 'hpids'), isTrue);
      dio.close();
    },
  );
  test(
    'SDK and public search transport have no dependency on member matching',
    () {
      for (final path in [
        'lib/core/map',
        'lib/features/emergency_map/data',
        'lib/features/emergency_map/domain',
        'lib/features/hospital_detail/data',
        'lib/features/hospital_detail/domain',
      ]) {
        for (final file
            in Directory(path)
                .listSync(recursive: true)
                .whereType<File>()
                .where((f) => f.path.endsWith('.dart'))) {
          final source = file.readAsStringSync();
          expect(
            source.contains('disease_personalization'),
            isFalse,
            reason: file.path,
          );
          expect(
            source.contains('mapDiseaseSelection'),
            isFalse,
            reason: file.path,
          );
        }
      }
    },
  );
}
