import '../main_flow_test.dart' show FakeDetailRepository;
import 'package:eroute_mobile/features/hospital_detail/presentation/hospital_detail_state.dart';
// Test-only UI repositories. Server v0.5 is read unchanged; hospital rows are synthetic.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:eroute_mobile/app/router.dart';
import 'package:eroute_mobile/core/theme/eroute_theme.dart';
import 'package:eroute_mobile/core/privacy_changes.dart';
import 'package:eroute_mobile/core/theme/theme_controller.dart';
import 'package:eroute_mobile/features/app_menu/app_session.dart';
import 'package:eroute_mobile/features/disease_personalization/condition_local_store.dart';
import 'package:eroute_mobile/features/disease_personalization/disease_catalog.dart';
import 'package:eroute_mobile/features/disease_personalization/disease_reference.dart';
import 'package:eroute_mobile/features/disease_personalization/disease_repository.dart';
import 'package:eroute_mobile/features/disease_personalization/map_disease_selection.dart';
import 'package:eroute_mobile/features/disease_personalization/map_personalization_controller.dart';
import 'package:eroute_mobile/features/disease_personalization/department_matcher.dart';
import 'package:eroute_mobile/development/disease_review_preview.dart';
import 'package:eroute_mobile/features/member_ui/member_contract.dart';
import 'package:eroute_mobile/features/member_ui/member_widgets.dart';
import 'package:eroute_mobile/features/emergency_map/domain/hospital_summary.dart';
import 'package:eroute_mobile/features/emergency_map/presentation/emergency_map_controller.dart';
import 'package:eroute_mobile/features/emergency_map/presentation/emergency_map_page.dart';
import 'package:eroute_mobile/core/location/heading_service.dart';
import 'package:eroute_mobile/preview/member_preview_repository.dart';
import '../emergency_map_test.dart'
    show FakeRepository, FakeLocation, SilentHeading;
import 'catalog_fixture.dart';
import 'disease_fixtures.dart';
import 'synthetic_personalization.dart';

String _document(String define, String path) =>
    define.isEmpty ? File(path).readAsStringSync() : define;

class FlowData implements DiseaseDataRepository {
  late final DiseaseReference referenceValue;
  late final ReviewPreviewCandidates preview;
  int reads = 0, departmentReads = 0;
  FlowData() {
    final json =
        jsonDecode(
              _document(
                const String.fromEnvironment('FLOW_REFERENCE'),
                '../../services/backend/src/main/resources/reference/disease-departments/v0.5.json',
              ),
            )
            as Map<String, dynamic>;
    final raw = DiseaseReference.decode(referenceEnvelope(jsonEncode(json)));
    final classes = jsonDecode(
      _document(
        const String.fromEnvironment('FLOW_CLASSES'),
        '../../services/backend/src/development/resources/reference/review-classes-v0.5.json',
      ),
    );
    referenceValue = DiseaseReference.decode(
      referenceEnvelope(jsonEncode({...json, 'mappings': []})),
    );
    preview = ReviewPreviewCandidates.decode({
      'documentType': 'DEVELOPMENT_REVIEW_PREVIEW',
      'referenceVersion': raw.version,
      'mappings': [
        for (final m in raw.mappings)
          {
            'id': m.id,
            'diseaseId': m.diseaseId,
            'departmentId': m.departmentId,
            'relationType': m.relation,
            'reviewStatus': m.reviewStatus,
            'mappingScope': m.mappingScope == MappingScope.broadParent
                ? 'BROAD_PARENT'
                : m.mappingScope == MappingScope.exactCanonical
                ? 'EXACT_CANONICAL'
                : null,
            'reviewClass': (classes['mappings'] as List).singleWhere(
              (r) => r['mappingId'] == m.id,
            )['reviewClass'],
          },
      ],
    }, referenceValue);
  }
  @override
  Future<DiseaseReference> reference() async {
    reads++;
    return referenceValue;
  }

  @override
  Future<List<DepartmentSnapshot>> departments(List<String> hpids) async {
    departmentReads++;
    return [
      for (final id in hpids)
        syntheticDepartmentSnapshot(
          hpid: id,
          names: id == 'QA_B' ? ['정형외과'] : ['내과', '신경과'],
        ),
    ];
  }
}

class FlowHospitals extends FakeRepository {
  final rows = [
    for (final item in [
      ('QA_A', '가상 A 응급의료기관', 500),
      ('QA_B', '가상 B 응급의료기관', 700),
      ('QA_C', '가상 C 응급의료기관', 1100),
    ])
      HospitalSummary(
        hpid: item.$1,
        name: item.$2,
        classification: '지역응급의료센터',
        location: const GeoPoint(37, 127),
        centerDistance: item.$3,
        userDistance: item.$3,
        coverage: 'LIVE_AVAILABLE',
        refresh: 'UPDATED',
        beds: ResourceValue('KNOWN', 4, '4'),
        reference: ResourceValue('KNOWN', 5, '5'),
        stale: false,
        rawSourceTime: null,
        fetchedAt: DateTime.now(),
        error: null,
      ),
  ];
  @override
  Future<HospitalSearchResult> search(
    GeoPoint center,
    String source,
    GeoPoint? user,
    int? radius,
  ) async {
    searchCount++;
    requestedRadii.add(radius);
    return HospitalSearchResult(
      rows,
      radius ?? 10000,
      false,
      false,
      [],
      totalCount: rows.length,
    );
  }
}

MemberHealthSnapshot flowHealth(
  MemberHealthSnapshot old, {
  LocalConditions? local,
  MapDiseaseSelection? selection,
  int? version,
}) => MemberHealthSnapshot(
  version: version ?? old.version,
  consentEpoch: old.consentEpoch,
  allergies: old.allergies,
  medications: old.medications,
  medicationsStatus: old.medicationsStatus,
  note: old.note,
  updatedAt: DateTime.now(),
  conditionEntries: local?.entries ?? old.conditionEntries,
  conditions: local == null
      ? old.conditions
      : HealthEntry(
          EntryStatus.values.byName(local.status.toLowerCase()),
          local.entries.where((e) => !e.standard).map((e) => e.name).join('\n'),
        ),
  standardDiseaseSelection: local == null
      ? old.standardDiseaseSelection
      : StandardDiseaseSelection(
          local.entries.where((e) => e.standard).map((e) => e.diseaseId!),
        ),
  mapDiseaseSelection: selection ?? old.mapDiseaseSelection,
);

class FlowConditions extends ConditionLocalController {
  final PreviewMemberRepository member;
  final VoidCallback changed;
  bool offline = false;
  FlowConditions(PreviewAuthRepository auth, this.member, this.changed)
    : super(MemoryConditionVault(), auth, FixtureCatalogRepository());
  @override
  Future<void> sync() async {
    if (offline || state?.pending != true || state?.conflict == true) {
      return;
    }
    final next = state!.changed(
      version: member.data.version + 1,
      pending: false,
    );
    member.data = flowHealth(
      member.data,
      local: next,
      version: next.baseVersion,
      selection: next.status == 'NONE'
          ? const MapDiseaseSelection.none()
          : member.data.mapDiseaseSelection,
    );
    state = next;
    changed();
  }

  void conflict() {
    state = state!.changed(pending: true, conflict: true);
    changed();
  }
}

class FlowSelection implements MapSelectionRepository {
  final PreviewMemberRepository member;
  final VoidCallback changed;
  int reads = 0, writes = 0;
  FlowSelection(this.member, this.changed);
  @override
  Future<MapSelectionSnapshot> read() async {
    reads++;
    await member.access();
    if (!member.granted) {
      throw const MemberFailure(MemberFailureKind.consent, '동의 확인 필요');
    }
    return MapSelectionSnapshot(
      member.data.version,
      member.data.consentEpoch,
      member.data.mapDiseaseSelection,
    );
  }

  @override
  Future<MapSelectionSnapshot> save(
    int v,
    int e,
    List<String> ids,
    DiseaseReference r,
  ) async {
    if (v != member.data.version ||
        e != member.epoch ||
        ids.any(
          (id) => !member.data.standardDiseaseSelection.diseaseIds.contains(id),
        )) {
      throw const MemberFailure(MemberFailureKind.conflict, '기록을 확인해주세요.');
    }
    writes++;
    member.data = flowHealth(
      member.data,
      version: v + 1,
      selection: confirmedSelection(r, ids),
    );
    changed();
    return read();
  }

  @override
  Future<MapSelectionSnapshot> clear(int v, int e) async {
    writes++;
    member.data = flowHealth(
      member.data,
      version: v + 1,
      selection: const MapDiseaseSelection.none(),
    );
    changed();
    return read();
  }
}

class FlowFixture {
  final auth = PreviewAuthRepository();
  late final member = PreviewMemberRepository(auth, delay: Duration.zero);
  final data = FlowData();
  final hospitals = FlowHospitals();
  late final conditions = FlowConditions(auth, member, changed);
  late final selection = FlowSelection(member, changed);
  late final ProviderContainer container;
  MapPersonalizationController get personal => reviewPreviewBuild
      ? container.read(reviewPreviewProvider.notifier)
      : container.read(mapPersonalizationProvider.notifier);
  void changed() => container.read(privacyChangeProvider.notifier).state++;
  FlowFixture({bool signedIn = true, bool dark = false}) {
    member.data = MemberHealthSnapshot(version: 1, consentEpoch: member.epoch);
    if (!signedIn) auth.user = null;
    MapPersonalizationController controller() => MapPersonalizationController(
      data,
      selection,
      () => container.read(sessionProvider),
      available: true,
      authorizeRecords: () =>
          conditions.mapReady(container.read(sessionProvider)),
      recordsReady: () =>
          container.read(conditionLocalProvider)?.pending != true &&
          container.read(conditionLocalProvider)?.conflict != true,
      loadReference: data.reference,
      supports: (r, id) => data.preview.mappings.any((m) => m.diseaseId == id),
      contextMappings: (_) => data.preview.mappings,
      match: data.preview.match,
    );
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        memberUiRepositoryProvider.overrideWithValue(member),
        memberPrivacyProvider.overrideWithValue(PreviewPrivacy()),
        conditionLocalProvider.overrideWith((ref) => conditions),
        diseaseCatalogRepositoryProvider.overrideWithValue(
          FixtureCatalogRepository(),
        ),
        diseaseDataRepositoryProvider.overrideWithValue(data),
        mapSelectionRepositoryProvider.overrideWithValue(selection),
        themeModeProvider.overrideWith(
          (ref) => dark ? ThemeMode.dark : ThemeMode.light,
        ),
        hospitalRepositoryProvider.overrideWithValue(hospitals),
        hospitalDetailRepositoryProvider.overrideWithValue(
          FakeDetailRepository(),
        ),
        locationServiceProvider.overrideWithValue(
          FakeLocation(const GeoPoint(37, 127)),
        ),
        headingServiceProvider.overrideWithValue(SilentHeading()),
        emergencyMapBuilderProvider.overrideWithValue(
          ({
            required scene,
            required onReady,
            required onCameraIdle,
            required onHospitalSelected,
          }) => const Center(child: Text('테스트 지도 · 실제 지도 아님')),
        ),
        mapPersonalizationProvider.overrideWith((ref) {
          final c = controller();
          ref.listen(sessionProvider, (_, next) => c.disable());
          ref.listen(privacyChangeProvider, (_, next) => c.disable());
          return c;
        }),
        reviewPreviewProvider.overrideWith((ref) {
          final c = controller();
          ref.listen(sessionProvider, (_, next) => c.disable());
          ref.listen(privacyChangeProvider, (_, next) => c.disable());
          return c;
        }),
      ],
    );
  }
  Widget app({double scale = 1}) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: ERouteTheme.light(),
      darkTheme: ERouteTheme.dark(),
      themeMode: container.read(themeModeProvider),
      navigatorObservers: [appRouteObserver],
      initialRoute: AppRoutes.landing,
      onGenerateRoute: buildAppRoute,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
    ),
  );
}
