import 'department_matcher.dart';
import 'disease_reference.dart';

/// Private presentation only. Never used by search, ranking or the matcher.
enum PersonalizationAccent { none, filled, hollow }

PersonalizationAccent approvedAccent(HospitalDiseaseMatchResult result) =>
    !result.reviewPreview &&
        result.matched &&
        result.matches.any(
          (r) =>
              r.reviewStatus == 'APPROVED' &&
              r.relationType == 'DIRECT' &&
              r.mappingScope == MappingScope.exactCanonical,
        )
    ? PersonalizationAccent.filled
    : PersonalizationAccent.none;

String relationScopeLabel(
  DepartmentMatchReason reason, {
  required bool preview,
}) {
  if (preview) {
    return switch (reason.reviewClass) {
      'EXACT_CANONICAL_REVIEW_REQUIRED' => '직접 대응 후보',
      'BROAD_PARENT_REVIEW_REQUIRED' => '상위 진료과 후보',
      _ => '범위 미확정',
    };
  }
  return switch (reason.mappingScope) {
    MappingScope.exactCanonical => '정확 대응',
    MappingScope.broadParent => '상위 진료과',
    null => '범위 미확정',
  };
}

String personalizationBadgeLabel(HospitalDiseaseMatchResult result) {
  if (!result.reviewPreview) return '내 질환 관련 진료과';
  final departments = result.matches
      .map((r) => r.canonicalDepartmentName)
      .toSet();
  return '내 질환 관련 진료과 · 검수 중 · ${departments.length == 1 ? departments.single : '관련 진료과 ${departments.length}개'}';
}

/// Context is reference metadata only, never a hospital filter or a new match.
class PersonalizationContextRelation {
  final String diseaseName, departmentName;
  final DiseaseMapping mapping;
  const PersonalizationContextRelation(
    this.diseaseName,
    this.departmentName,
    this.mapping,
  );
  String get scopeLabel => mapping.mappingScope == MappingScope.broadParent
      ? (mapping.reviewStatus == 'DRAFT' ? '상위 진료과 후보' : '상위 진료과')
      : mapping.mappingScope == MappingScope.exactCanonical
      ? (mapping.reviewStatus == 'DRAFT' ? '직접 대응 후보' : '정확 대응')
      : '범위 미확정';
  @override
  String toString() => 'PersonalizationContextRelation[redacted]';
}

String personalizationContextLabel(
  List<PersonalizationContextRelation> relations,
) {
  final diseases = relations.map((r) => r.diseaseName).toSet();
  final departments = relations.map((r) => r.departmentName).toSet();
  if (diseases.length == 1 && departments.length == 1) {
    return '${diseases.single} · ${departments.single}';
  }
  return '내 질환 ${diseases.length}개 · 관련 진료과 ${departments.length}개';
}

String compactPersonalizationLabel(HospitalDiseaseMatchResult result) {
  final diseases = result.matches.map((r) => r.diseaseName).toSet();
  final departments = result.matches
      .map((r) => r.canonicalDepartmentName)
      .toSet();
  if (diseases.length == 1 && departments.length == 1) {
    return '${diseases.single} · ${departments.single}';
  }
  return '내 질환 관련 · 진료과 ${departments.length}개';
}

/// C-plan ring is independent of the unchanged review-class dot baseline.
/// Canonical ring policy: require an EXACT_CANONICAL matched relation, never
/// infer scope from reviewClass or an exact hospital department token alone.
/// Caller supplies only live results authorized by the controller's capability,
/// STANDARD selection, CONFIRMED consent and sync/freshness gates.
bool personalizationRingEligible(
  HospitalDiseaseMatchResult result, {
  required bool previewAllowed,
}) =>
    result.matched &&
    (result.reviewPreview
        ? previewAllowed &&
              result.matches.any(
                (r) =>
                    r.reviewStatus == 'DRAFT' &&
                    r.relationType == 'DIRECT' &&
                    r.mappingScope == MappingScope.exactCanonical,
              )
        : approvedAccent(result) != PersonalizationAccent.none);
