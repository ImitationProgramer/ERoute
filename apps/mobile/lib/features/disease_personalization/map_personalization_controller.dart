import 'personalization_presentation.dart';
import 'condition_local_store.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/map/map_scene.dart';
import '../../core/privacy_changes.dart';
import '../app_menu/app_session.dart';
import 'disease_reference.dart';
import 'map_disease_selection.dart';
import 'disease_repository.dart';
import 'department_matcher.dart';

/// Production cannot be opted in by a Dart define in this release.
final mapPersonalizationAvailableProvider = Provider<bool>(
  (ref) => appFlavor == 'dev' && kDebugMode || publicDiseaseMapEnabled,
);

class MapPersonalizationState {
  final bool enabled, loading;
  final List<String> selectedDiseaseNames;
  final List<PersonalizationContextRelation> contextRelations;
  final int currentHospitalCount;
  final String? message;
  final Map<String, HospitalDiseaseMatchResult> results;
  const MapPersonalizationState({
    this.selectedDiseaseNames = const [],
    this.contextRelations = const [],
    this.currentHospitalCount = 0,
    this.enabled = false,
    this.loading = false,
    this.message,
    this.results = const {},
  });
  @override
  String toString() => 'MapPersonalizationState[redacted]';
}

final mapPersonalizationProvider =
    StateNotifierProvider.autoDispose<
      MapPersonalizationController,
      MapPersonalizationState
    >((ref) {
      final c = MapPersonalizationController(
        ref.watch(diseaseDataRepositoryProvider),
        ref.watch(mapSelectionRepositoryProvider),
        () => ref.read(sessionProvider),
        available: ref.watch(mapPersonalizationAvailableProvider),
        authorizeRecords: () => ref
            .read(conditionLocalProvider.notifier)
            .mapReady(ref.read(sessionProvider)),
        recordsReady: () =>
            ref.read(conditionLocalProvider)?.pending != true &&
            ref.read(conditionLocalProvider)?.conflict != true,
      );
      ref.listen(sessionProvider, (old, next) {
        if (old?.userId != next.userId ||
            old?.generation != next.generation ||
            !next.authenticated) {
          c.disable();
        }
      });
      ref.listen(privacyChangeProvider, (_, next) => c.disable());
      ref.listen(conditionLocalProvider, (_, next) {
        if (next?.pending == true || next?.conflict == true) c.disable();
      });
      return c;
    });

/// Fetches only the map selection. Public searches and health snapshots are never invoked.
class MapPersonalizationController
    extends StateNotifier<MapPersonalizationState> {
  final DiseaseDataRepository data;
  final MapSelectionRepository selections;
  final AppSession Function() session;
  final bool available;
  final bool Function()? recordsReady;
  final Future<bool> Function()? authorizeRecords;
  final DateTime Function() now;
  final Future<DiseaseReference> Function()? loadReference;
  final bool Function(DiseaseReference, String)? supports;
  final Iterable<DiseaseMapping> Function(DiseaseReference)? contextMappings;
  final HospitalDiseaseMatchResult? Function(
    DiseaseReference,
    MapDiseaseSelection,
    DepartmentSnapshot,
    DateTime,
  )?
  match;
  SearchPresentationSnapshot? _search;
  Timer? _poll, _expiry;
  int _generation = 0;
  bool _refreshing = false;
  MapPersonalizationController(
    this.data,
    this.selections,
    this.session, {
    required this.available,
    this.recordsReady,
    this.authorizeRecords,
    this.loadReference,
    this.supports,
    this.contextMappings,
    this.match,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now,
       super(const MapPersonalizationState());
  void disable() {
    _generation++;
    _poll?.cancel();
    _expiry?.cancel();
    _poll = null;
    _expiry = null;
    if (mounted) state = const MapPersonalizationState();
  }

  Future<void> enable() async {
    if (!available) return;
    if (recordsReady?.call() == false) {
      state = const MapPersonalizationState(
        message: '기저질환을 서버에 반영한 뒤 관련 진료과 표시를 켜주세요.',
      );
      return;
    }
    if (!session().authenticated) {
      state = const MapPersonalizationState(
        message: '로그인 후 내 응급정보에서 지도 활용을 확인해주세요.',
      );
      return;
    }
    final owner = session(), activation = _generation;
    final ready = authorizeRecords == null || await authorizeRecords!();
    if (!mounted ||
        activation != _generation ||
        !session().authenticated ||
        session().userId != owner.userId ||
        session().generation != owner.generation) {
      return;
    }
    if (!ready) {
      state = const MapPersonalizationState(
        message: '기저질환의 서버 반영 상태를 먼저 확인해주세요.',
      );
      return;
    }
    disable();
    state = const MapPersonalizationState(enabled: true, loading: true);
    // Renew before the ten-second display lease expires. A stalled/failed
    // request still loses its display at the existing expiry boundary.
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => refresh());
    await refresh();
  }

  void setSearch(SearchPresentationSnapshot? search) {
    if (_search?.revision == search?.revision) return;
    _search = search;
    _generation++;
    if (state.enabled) {
      state = const MapPersonalizationState(enabled: true, loading: true);
      unawaited(refresh());
    }
  }

  Future<void> refresh() async {
    if (!mounted || !state.enabled || _refreshing) return;
    _refreshing = true;
    final ticket = _generation, owner = session(), search = _search;
    bool valid() =>
        mounted &&
        state.enabled &&
        recordsReady?.call() != false &&
        ticket == _generation &&
        session().authenticated &&
        session().userId == owner.userId &&
        session().generation == owner.generation;
    try {
      final selection = await selections.read();
      if (!valid()) return;
      // No reference/preview fetch without an existing opt-in. The authenticated
      // selection endpoint remains the authority for health consent and epoch.
      if (selection.selection.state != 'CONFIRMED') {
        state = const MapPersonalizationState(enabled: true);
        return;
      }
      final reference = await (loadReference?.call() ?? data.reference());
      if (!valid()) return;
      final s = selection.selection;
      if (s.state != 'CONFIRMED' ||
          s.referenceVersion != reference.version ||
          s.purposeVersion != reference.purposeVersion ||
          s.purpose != reference.purpose) {
        state = const MapPersonalizationState(
          enabled: true,
          message: '내 응급정보에서 지도 활용 질환을 확인해주세요.',
        );
        return;
      }
      final supported = s.diseaseIds
          .where(
            (id) => supports?.call(reference, id) ?? reference.supports(id),
          )
          .toSet();
      if (supported.isEmpty) {
        state = const MapPersonalizationState(
          enabled: true,
          message: '관련 진료과 정보 준비 중',
        );
        return;
      }
      final hpids =
          search?.result.hospitals.map((h) => h.hpid).toList() ?? <String>[];
      final hospitals = await data.departments(hpids);
      if (!valid()) return;
      // Recheck authority/profile after the public request before exposing results.
      final current = await selections.read();
      if (!valid()) return;
      if (current.version != selection.version ||
          current.consentEpoch != selection.consentEpoch ||
          current.selection.state != 'CONFIRMED') {
        state = const MapPersonalizationState(
          enabled: true,
          message: '정보가 변경되었습니다. 지도 활용을 다시 확인해주세요.',
        );
        return;
      }
      final results = <String, HospitalDiseaseMatchResult>{};
      for (final h in hospitals) {
        final result = match != null
            ? match!(reference, s, h, now())
            : matchDepartments(
                reference: reference,
                selection: s,
                hospital: h,
                now: now(),
                enabled: true,
              );
        if (result != null) results[h.hpid] = result;
      }
      state = MapPersonalizationState(
        enabled: true,
        results: Map.unmodifiable(results),
        selectedDiseaseNames: List.unmodifiable(
          reference.diseases
              .where((d) => s.diseaseIds.contains(d.id))
              .map((d) => d.name),
        ),
        contextRelations: List.unmodifiable([
          for (final mapping
              in contextMappings?.call(reference) ??
                  reference.mappings.where(
                    (m) =>
                        m.reviewStatus == 'APPROVED' && m.relation == 'DIRECT',
                  ))
            if (supported.contains(mapping.diseaseId))
              PersonalizationContextRelation(
                reference.diseases
                    .firstWhere((d) => d.id == mapping.diseaseId)
                    .name,
                reference.departments[mapping.departmentId]!,
                mapping,
              ),
        ]),
        currentHospitalCount: hpids.length,
        message: supported.length < s.diseaseIds.length
            ? '일부 질환의 관련 진료과 정보 준비 중'
            : null,
      );
      _expiry?.cancel();
      // Consent freshness is bounded even if a request hangs; clinical data may expire sooner.
      var duration = const Duration(seconds: 10);
      for (final h in hospitals) {
        if (results[h.hpid]?.matched == true && h.validUntil != null) {
          final remaining = h.validUntil!.difference(now());
          if (remaining < duration) duration = remaining;
        }
      }
      _expiry = Timer(duration.isNegative ? Duration.zero : duration, () {
        if (valid()) {
          state = const MapPersonalizationState(
            enabled: true,
            message: '개인화 정보를 확인 중입니다.',
          );
        }
      });
    } catch (_) {
      if (valid()) {
        state = const MapPersonalizationState(
          enabled: true,
          message: '개인화 정보를 확인하지 못했습니다. 다시 켜서 확인해주세요.',
        );
      }
    } finally {
      _refreshing = false;
      if (mounted && state.enabled && ticket != _generation) {
        unawaited(refresh());
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _poll?.cancel();
    _expiry?.cancel();
    super.dispose();
  }
}
