import '../features/disease_personalization/condition_local_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config/app_config.dart';
import '../core/privacy_changes.dart';
import '../features/app_menu/app_session.dart';
import '../features/disease_personalization/disease_reference.dart';
import '../features/disease_personalization/disease_repository.dart';
import '../features/disease_personalization/department_matcher.dart';
import '../features/disease_personalization/map_disease_selection.dart';
import '../features/disease_personalization/personalization_presentation.dart';
import '../features/disease_personalization/map_personalization_controller.dart';

const reviewPreviewBuild =
    kDebugMode &&
    appFlavor == 'dev' &&
    (AppConfig.authEnvironment == 'local' ||
        AppConfig.authEnvironment == 'test');

/// Only this development module knows DRAFT input policy. Public reference stays unchanged.
class ReviewPreviewCandidates {
  final String version;
  final List<DiseaseMapping> mappings;
  ReviewPreviewCandidates.decode(
    Map<String, dynamic> j,
    DiseaseReference catalog,
  ) : version = j['referenceVersion'] as String,
      mappings = List.unmodifiable(
        (j['mappings'] as List).map((row) {
          if (row['relationType'] != 'DIRECT' ||
              row['reviewStatus'] != 'DRAFT' ||
              !catalog.diseases.any((d) => d.id == row['diseaseId']) ||
              !catalog.departments.containsKey(row['departmentId']) ||
              !{
                'BROAD_PARENT_REVIEW_REQUIRED',
                'EXACT_CANONICAL_REVIEW_REQUIRED',
                'REVIEW_REQUIRED',
              }.contains(row['reviewClass'])) {
            throw const FormatException('검수 후보를 확인하지 못했습니다.');
          }
          return DiseaseMapping(
            row['id'],
            row['diseaseId'],
            row['departmentId'],
            row['relationType'],
            row['reviewStatus'],
            reviewClass: row['reviewClass'],
            mappingScope: decodeMappingScope(row['mappingScope']),
          );
        }),
      ) {
    if (j['documentType'] != 'DEVELOPMENT_REVIEW_PREVIEW' ||
        version != catalog.version ||
        mappings.map((m) => m.id).toSet().length != mappings.length) {
      throw const FormatException('검수 후보 버전이 다릅니다.');
    }
  }
  HospitalDiseaseMatchResult? match(
    DiseaseReference reference,
    MapDiseaseSelection selection,
    DepartmentSnapshot hospital,
    DateTime now,
  ) => compareDepartmentCandidates(
    reference: reference,
    selection: selection,
    hospital: hospital,
    now: now,
    candidates: mappings
        .where((m) => m.reviewStatus == 'DRAFT' && m.relation == 'DIRECT')
        .toList(),
    enabled: version == reference.version,
    reviewPreview: true,
  );
}

final reviewPreviewProvider =
    StateNotifierProvider.autoDispose<
      MapPersonalizationController,
      MapPersonalizationState
    >((ref) {
      final data = ref.watch(diseaseDataRepositoryProvider);
      ReviewPreviewCandidates? candidates;
      final c = MapPersonalizationController(
        data,
        ref.watch(mapSelectionRepositoryProvider),
        () => ref.read(sessionProvider),
        available: reviewPreviewBuild,
        authorizeRecords: () => ref
            .read(conditionLocalProvider.notifier)
            .mapReady(ref.read(sessionProvider)),
        recordsReady: () =>
            ref.read(conditionLocalProvider)?.pending != true &&
            ref.read(conditionLocalProvider)?.conflict != true,
        loadReference: () async {
          final catalog = await data.reference();
          final response = await ref
              .read(authRepositoryProvider)
              .request(
                'GET',
                '/api/v1/dev/reference/disease-departments-review-preview',
              );
          candidates = ReviewPreviewCandidates.decode(
            Map<String, dynamic>.from(response.data as Map),
            catalog,
          );
          return catalog;
        },
        supports: (r, id) =>
            r.diseases.any((d) => d.id == id && d.active) &&
            (candidates?.mappings.any((m) => m.diseaseId == id) ?? false),
        contextMappings: (_) => candidates?.mappings ?? const [],
        match: (r, s, h, now) => candidates?.match(r, s, h, now),
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

/// Preview classification never becomes production mappingScope.
PersonalizationAccent reviewPreviewAccent(HospitalDiseaseMatchResult result) {
  if (!result.reviewPreview || !result.matched) {
    return PersonalizationAccent.none;
  }
  final reasons = result.matches.where(
    (r) => r.reviewStatus == 'DRAFT' && r.relationType == 'DIRECT',
  );
  if (reasons.any((r) => r.reviewClass == 'EXACT_CANONICAL_REVIEW_REQUIRED')) {
    return PersonalizationAccent.filled;
  }
  if (reasons.any((r) => r.reviewClass == 'REVIEW_REQUIRED')) {
    return PersonalizationAccent.hollow;
  }
  return PersonalizationAccent.none;
}
