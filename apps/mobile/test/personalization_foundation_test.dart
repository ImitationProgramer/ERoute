import 'package:eroute_mobile/features/disease_personalization/condition_local_store.dart';
import 'package:eroute_mobile/features/auth/auth_repository.dart';
import 'support/catalog_fixture.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:eroute_mobile/core/privacy_changes.dart';
import 'personalization_overlay_test.dart' show syntheticSearch;
import 'package:eroute_mobile/features/disease_personalization/disease_reference.dart';
import 'package:eroute_mobile/features/disease_personalization/department_matcher.dart';
import 'package:eroute_mobile/features/disease_personalization/disease_repository.dart';
import 'package:eroute_mobile/features/disease_personalization/map_disease_selection.dart';
import 'package:eroute_mobile/features/disease_personalization/map_personalization_controller.dart';
import 'package:eroute_mobile/features/app_menu/app_session.dart';
import 'support/disease_fixtures.dart';
import 'support/synthetic_personalization.dart';

class SyntheticPublicRepository implements DiseaseDataRepository {
  DiseaseReference value = syntheticReference();
  int reads = 0, departmentReads = 0;
  Completer<List<DepartmentSnapshot>>? pending;
  @override
  Future<DiseaseReference> reference() async {
    reads++;
    return value;
  }

  @override
  Future<List<DepartmentSnapshot>> departments(List<String> hpids) async {
    departmentReads++;
    return pending == null ? [syntheticDepartmentSnapshot()] : pending!.future;
  }
}

class SyntheticSelectionRepository implements MapSelectionRepository {
  late MapSelectionSnapshot value = MapSelectionSnapshot(
    1,
    1,
    confirmedSelection(syntheticReference(), ['TEST_DISEASE']),
  );
  int reads = 0;
  bool fail = false;
  @override
  Future<MapSelectionSnapshot> read() async {
    reads++;
    if (fail) throw Exception('synthetic offline');
    return value;
  }

  @override
  Future<MapSelectionSnapshot> save(
    int v,
    int e,
    List<String> ids,
    DiseaseReference r,
  ) async => value = MapSelectionSnapshot(v + 1, e, confirmedSelection(r, ids));
  @override
  Future<MapSelectionSnapshot> clear(int v, int e) async =>
      value = MapSelectionSnapshot(v + 1, e, const MapDiseaseSelection.none());
}

void main() {
  final time = DateTime.utc(2026, 9, 18);
  HospitalDiseaseMatchResult? match(
    DiseaseReference r,
    List<String> ids,
    List<String> names, {
    bool stale = false,
    bool allowDraft = false,
  }) => matchDepartments(
    reference: r,
    selection: confirmedSelection(r, ids),
    hospital: syntheticDepartmentSnapshot(
      names: names,
      now: time,
      stale: stale,
    ),
    now: time,
    enabled: true,
    allowDraft: allowDraft,
  );
  test(
    'real seed has 16 diseases, 51 literal departments, zero approved relationships',
    () {
      final raw = File(
        '../../services/backend/src/main/resources/reference/disease-departments/v0.2.json',
      ).readAsStringSync();
      final r = DiseaseReference.decode(referenceEnvelope(raw));
      expect(r.diseases.length, 16);
      expect(r.departments.length, 51);
      expect(r.mappings, isEmpty);
      expect(r.publicMapApproved, isFalse);
      expect(r.diseases.any((d) => r.supports(d.id)), isFalse);
    },
  );
  test(
    'empty and draft mapping sets are normal and cannot highlight, even with draft override',
    () {
      final r = syntheticReference(approved: false);
      expect(match(r, [], ['TEST_DEPARTMENT']), isNull);
      final result = match(
        r,
        ['TEST_DISEASE'],
        ['TEST_DEPARTMENT'],
        allowDraft: true,
      )!;
      expect(result.matched, isFalse);
      expect(result.unknownReasons, contains('NO_APPROVED_MAPPING'));
      final data = syntheticReferenceData()..['mappings'] = [];
      expect(
        match(
          DiseaseReference.decode(referenceEnvelope(jsonEncode(data))),
          ['TEST_DISEASE'],
          ['TEST_DEPARTMENT'],
        )!.matched,
        isFalse,
      );
    },
  );
  test(
    'one-to-many and shared departments count unique departments and retain all disease reasons',
    () {
      final r = syntheticReference();
      final result = match(
        r,
        ['TEST_DISEASE', 'TEST_DISEASE_2', 'TEST_DRAFT_DISEASE'],
        ['TEST_DEPARTMENT', 'TEST_DEPARTMENT_2', 'TEST_DEPARTMENT'],
      )!;
      expect(result.matchedDiseases, {'TEST_DISEASE', 'TEST_DISEASE_2'});
      expect(result.matchCount, 2);
      expect(result.matches.length, 3);
      expect(result.mappingVersion, r.version);
      expect(result.toString(), isNot(contains('TEST_DISEASE')));
    },
  );
  test(
    'approved broad direct relation and explicit alias work; substrings, stale and missing do not',
    () {
      final r = syntheticReference();
      expect(match(r, ['TEST_DISEASE'], ['TEST_ALIAS'])!.matched, isTrue);
      expect(
        match(r, ['TEST_DISEASE'], ['TEST_DEPARTMENT_EXTRA'])!.matched,
        isFalse,
      );
      expect(
        match(r, ['TEST_DISEASE'], [])!.status,
        DepartmentMatchStatus.unknown,
      );
      expect(
        match(r, ['TEST_DISEASE'], ['TEST_DEPARTMENT'], stale: true)!.status,
        DepartmentMatchStatus.unknown,
      );
    },
  );
  test(
    'approval metadata, alias ambiguity, hash and priority are validated',
    () {
      for (final field in ['sourceUrl', 'checkedAt']) {
        final d = syntheticReferenceData();
        ((d['mappings'] as List).first['evidence'] as List).first[field] = null;
        expect(
          () => DiseaseReference.decode(referenceEnvelope(jsonEncode(d))),
          throwsFormatException,
        );
      }
      final d = syntheticReferenceData();
      d['mappings'][0]['priority'] = 'PRIMARY';
      expect(
        () => DiseaseReference.decode(referenceEnvelope(jsonEncode(d))),
        throwsFormatException,
      );
      final alias = syntheticReferenceData();
      alias['departmentAliases'][0]['alias'] = 'TEST_DEPARTMENT';
      expect(
        () => DiseaseReference.decode(referenceEnvelope(jsonEncode(alias))),
        throwsFormatException,
      );
    },
  );
  test(
    'controller OFF does no reads; zero approvals is prepared state; late results cannot resurrect',
    () async {
      final data = SyntheticPublicRepository(),
          selections = SyntheticSelectionRepository();
      var session = const AppSession(
        phase: SessionPhase.authenticated,
        user: {'userId': 'SYNTHETIC_USER'},
        generation: 1,
      );
      final c = MapPersonalizationController(
        data,
        selections,
        () => session,
        available: true,
      );
      addTearDown(c.dispose);
      expect(selections.reads, 0);
      expect(data.reads, 0);
      data.value = syntheticReference(approved: false);
      await c.enable();
      expect(c.state.enabled, isTrue);
      expect(c.state.results, isEmpty);
      expect(c.state.message, '관련 진료과 정보 준비 중');
      expect(data.departmentReads, 0);
      c.disable();
      data.value = syntheticReference();
      data.pending = Completer();
      final pending = c.enable();
      await Future<void>.delayed(Duration.zero);
      c.disable();
      session = const AppSession.signedOut();
      data.pending!.complete([syntheticDepartmentSnapshot()]);
      await pending;
      expect(c.state.enabled, isFalse);
      expect(c.state.results, isEmpty);
    },
  );
  test(
    'production gate OFF and failed authority never allow results',
    () async {
      final data = SyntheticPublicRepository(),
          s = SyntheticSelectionRepository();
      const user = AppSession(
        phase: SessionPhase.authenticated,
        user: {'userId': 'SYNTHETIC_USER'},
        generation: 1,
      );
      final off = MapPersonalizationController(
        data,
        s,
        () => user,
        available: false,
      );
      await off.enable();
      expect(s.reads, 0);
      off.dispose();
      final c = MapPersonalizationController(
        data,
        s,
        () => user,
        available: true,
      );
      s.fail = true;
      await c.enable();
      expect(c.state.results, isEmpty);
      c.dispose();
    },
  );
  testWidgets(
    'map TTL expires during hanging authority request and stale consent cannot resurrect results',
    (tester) async {
      final data = SyntheticPublicRepository(),
          selections = SyntheticSelectionRepository();
      const user = AppSession(
        phase: SessionPhase.authenticated,
        user: {'userId': 'TEST_USER'},
        generation: 1,
      );
      final c = MapPersonalizationController(
        data,
        selections,
        () => user,
        available: true,
      );
      c.setSearch(syntheticSearch());
      await c.enable();
      expect(c.state.results.values.single.matched, isTrue);
      data.pending = Completer();
      await tester.pump(const Duration(seconds: 11));
      expect(c.state.results, isEmpty);
      selections.value = const MapSelectionSnapshot(
        2,
        2,
        MapDiseaseSelection.none(),
      );
      data.pending!.complete([syntheticDepartmentSnapshot()]);
      await tester.pump();
      expect(c.state.results, isEmpty);
      c.dispose();
    },
  );
  test(
    'account generation and local privacy mutations immediately clear provider state',
    () async {
      final session = StateProvider(
        (ref) => const AppSession(
          phase: SessionPhase.authenticated,
          user: {'userId': 'TEST_USER'},
          generation: 1,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith((ref) => ref.watch(session)),
          diseaseDataRepositoryProvider.overrideWithValue(
            SyntheticPublicRepository(),
          ),
          mapSelectionRepositoryProvider.overrideWithValue(
            SyntheticSelectionRepository(),
          ),
          mapPersonalizationAvailableProvider.overrideWithValue(true),
          conditionLocalProvider.overrideWith((ref) => ConditionLocalController(MemoryConditionVault(),AuthRepository(),FixtureCatalogRepository())),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(mapPersonalizationProvider, (_, next) {});
      final c = container.read(mapPersonalizationProvider.notifier);
      c.setSearch(syntheticSearch());
      await c.enable();
      expect(c.state.results, isNotEmpty);
      container.read(session.notifier).state = const AppSession(
        phase: SessionPhase.authenticated,
        user: {'userId': 'TEST_OTHER'},
        generation: 2,
      );
      await container.pump();
      expect(c.state.enabled, isFalse);
      expect(c.state.results, isEmpty);
      await c.enable();
      container.read(privacyChangeProvider.notifier).state++;
      await container.pump();
      expect(c.state.enabled, isFalse);
      sub.close();
    },
  );
}
