import 'disease_reference.dart';
import 'map_disease_selection.dart';

enum DepartmentMatchStatus { match, unknown, noMatch }

class DepartmentToken {
  final String? name, raw;
  final String source, status;
  const DepartmentToken(this.name, this.raw, this.source, this.status);
  factory DepartmentToken.fromJson(Map<String, dynamic> j) => DepartmentToken(
    j['name'],
    j['rawValue'],
    j['source'] as String,
    j['interpretationStatus'] as String,
  );
}

class DepartmentSnapshot {
  final String hpid, recordStatus, departmentsStatus;
  final String? datasetVersion, normalizerVersion;
  final int? snapshotId;
  final DateTime? fetchedAt, validUntil;
  final bool stale;
  final List<String> staleReasons;
  final List<DepartmentToken> departments;
  DepartmentSnapshot({
    required this.hpid,
    required this.recordStatus,
    required this.departmentsStatus,
    this.datasetVersion,
    this.normalizerVersion,
    this.snapshotId,
    this.fetchedAt,
    this.validUntil,
    this.stale = false,
    Iterable<String> staleReasons = const [],
    Iterable<DepartmentToken> departments = const [],
  }) : departments = List.unmodifiable(departments),
       staleReasons = List.unmodifiable(staleReasons);
  factory DepartmentSnapshot.fromJson(Map<String, dynamic> j) =>
      DepartmentSnapshot(
        hpid: j['hpid'],
        recordStatus: j['recordStatus'],
        departmentsStatus: j['departmentsStatus'],
        datasetVersion: j['datasetVersion'],
        normalizerVersion: j['normalizerVersion'],
        snapshotId: j['snapshotId'],
        fetchedAt: DateTime.tryParse(j['fetchedAt'] ?? ''),
        validUntil: DateTime.tryParse(j['validUntil'] ?? ''),
        stale: j['stale'] == true,
        staleReasons: (j['staleReasons'] as List).cast<String>(),
        departments: (j['departments'] as List).map(
          (d) => DepartmentToken.fromJson(Map<String, dynamic>.from(d)),
        ),
      );
}

class DepartmentMatchReason {
  final String diseaseId,
      diseaseName,
      mappingId,
      canonicalDepartmentId,
      canonicalDepartmentName;
  final String hospitalDepartmentName, hospitalDepartmentRaw, hospitalSource;
  final int? snapshotId;
  final String? reviewClass;
  final MappingScope? mappingScope;
  final String reviewStatus;
  final String relationType;
  const DepartmentMatchReason({
    required this.diseaseId,
    required this.diseaseName,
    required this.mappingId,
    required this.canonicalDepartmentId,
    required this.canonicalDepartmentName,
    required this.hospitalDepartmentName,
    required this.hospitalDepartmentRaw,
    required this.hospitalSource,
    this.snapshotId,
    this.reviewClass,
    this.mappingScope,
    this.reviewStatus = 'DRAFT',
    this.relationType = 'DIRECT',
  });
  @override
  String toString() => 'DepartmentMatchReason[redacted]';
}

class DiseaseMatch {
  final String diseaseId;
  final DepartmentMatchStatus status;
  final List<DepartmentMatchReason> matches;
  final Set<String> unknownReasons;
  DiseaseMatch(
    this.diseaseId,
    this.status,
    Iterable<DepartmentMatchReason> matches,
    Iterable<String> reasons,
  ) : matches = List.unmodifiable(matches),
      unknownReasons = Set.unmodifiable(reasons);
  @override
  String toString() => 'DiseaseMatch[redacted]';
}

class HospitalDiseaseMatchResult {
  final DepartmentSnapshot hospital;
  final bool reviewPreview;
  final String referenceVersion;
  final List<DiseaseMatch> perDiseaseResults;
  final DepartmentMatchStatus status;
  bool get matched => status == DepartmentMatchStatus.match;
  Set<String> get matchedDiseases => matches.map((m) => m.diseaseId).toSet();
  Set<String> get matchedDepartments =>
      matches.map((m) => m.canonicalDepartmentId).toSet();
  int get matchCount => matchedDepartments.length;
  String get mappingVersion => referenceVersion;
  List<DepartmentMatchReason> get matches =>
      List.unmodifiable(perDiseaseResults.expand((d) => d.matches));
  Set<String> get unknownReasons =>
      Set.unmodifiable(perDiseaseResults.expand((d) => d.unknownReasons));
  HospitalDiseaseMatchResult(
    this.hospital,
    this.referenceVersion,
    Iterable<DiseaseMatch> results, {
    this.reviewPreview = false,
  }) : perDiseaseResults = List.unmodifiable(results),
       status = results.any((d) => d.status == DepartmentMatchStatus.match)
           ? DepartmentMatchStatus.match
           : results.any((d) => d.status == DepartmentMatchStatus.unknown)
           ? DepartmentMatchStatus.unknown
           : DepartmentMatchStatus.noMatch;
  @override
  String toString() => 'HospitalDiseaseMatchResult[redacted]';
}

/// Pure comparison. DRAFT must be opted into by a development/test caller.
HospitalDiseaseMatchResult? matchDepartments({
  required DiseaseReference reference,
  required MapDiseaseSelection selection,
  required DepartmentSnapshot hospital,
  required DateTime now,
  bool enabled = false,
  bool allowDraft = false,
}) {
  return compareDepartmentCandidates(
    reference: reference,
    selection: selection,
    hospital: hospital,
    now: now,
    enabled: enabled,
    allowLegacyDraft: allowDraft,
    candidates: reference.mappings
        .where(
          (m) =>
              m.relation == 'DIRECT' &&
              (m.reviewStatus == 'APPROVED' ||
                  (allowDraft &&
                      reference.schemaVersion == 1 &&
                      m.reviewStatus == 'DRAFT')),
        )
        .toList(),
  );
}

/// Shared exact-canonical primitive. Callers supply their independently filtered policy.
HospitalDiseaseMatchResult? compareDepartmentCandidates({
  required DiseaseReference reference,
  required MapDiseaseSelection selection,
  required DepartmentSnapshot hospital,
  required DateTime now,
  required List<DiseaseMapping> candidates,
  bool enabled = false,
  bool allowLegacyDraft = false,
  bool reviewPreview = false,
}) {
  if (!enabled ||
      selection.state != 'CONFIRMED' ||
      selection.diseaseIds.isEmpty ||
      selection.referenceVersion != reference.version ||
      selection.purposeVersion != reference.purposeVersion ||
      selection.purpose != reference.purpose ||
      selection.confirmedAt == null ||
      (reference.status == 'DRAFT' && !allowLegacyDraft)) {
    return null;
  }
  final diseases = {
    for (final d in reference.diseases)
      if (d.active) d.id: d,
  };
  if (selection.diseaseIds.any((id) => !diseases.containsKey(id))) return null;
  final results = <DiseaseMatch>[];
  for (final id in selection.diseaseIds.toSet()) {
    final reasons = <String>{};
    final matches = <DepartmentMatchReason>[];
    final mappings = candidates.where((m) => m.diseaseId == id).toList();
    if (mappings.isEmpty) {
      reasons.add(reviewPreview ? 'NO_DRAFT_CANDIDATE' : 'NO_APPROVED_MAPPING');
    }
    if (hospital.recordStatus != 'PROVIDED') reasons.add(hospital.recordStatus);
    if (hospital.stale ||
        hospital.validUntil == null ||
        !hospital.validUntil!.isAfter(now)) {
      reasons.addAll(['STALE_OR_UNDATED', ...hospital.staleReasons]);
    }
    if (hospital.snapshotId == null || hospital.fetchedAt == null) {
      reasons.add('NO_SNAPSHOT');
    }
    final usable = reasons.isEmpty;
    if (hospital.departments.isEmpty) reasons.add('MISSING_DEPARTMENTS');
    if (hospital.departmentsStatus != 'KNOWN') {
      reasons.add('UNCERTAIN_DEPARTMENTS');
    }
    for (final token in hospital.departments) {
      if (token.status != 'KNOWN' ||
          token.name == null ||
          token.name!.isEmpty) {
        reasons.add('UNVERIFIED_TOKEN');
        continue;
      }
      final name = canonicalKey(token.name!);
      final canonical = reference.departmentAliases[name] ?? name;
      if (reference.broadNames.contains(canonical)) {
        reasons.add('BROAD_DEPARTMENT');
      }
      if (!usable) continue;
      for (final m in mappings) {
        if (canonical != canonicalKey(reference.departments[m.departmentId]!)) {
          continue;
        }
        if (matches.any(
          (r) => r.mappingId == m.id && r.hospitalDepartmentName == token.name,
        )) {
          continue;
        }
        matches.add(
          DepartmentMatchReason(
            diseaseId: id,
            diseaseName: diseases[id]!.name,
            mappingId: m.id,
            canonicalDepartmentId: m.departmentId,
            canonicalDepartmentName: reference.departments[m.departmentId]!,
            hospitalDepartmentName: token.name!,
            hospitalDepartmentRaw: token.raw ?? token.name!,
            hospitalSource: token.source,
            snapshotId: hospital.snapshotId,
            reviewClass: m.reviewClass,
            mappingScope: m.mappingScope,
            reviewStatus: m.reviewStatus,
            relationType: m.relation,
          ),
        );
      }
    }
    results.add(
      DiseaseMatch(
        id,
        matches.isNotEmpty
            ? DepartmentMatchStatus.match
            : reasons.isNotEmpty
            ? DepartmentMatchStatus.unknown
            : DepartmentMatchStatus.noMatch,
        matches,
        reasons,
      ),
    );
  }
  return HospitalDiseaseMatchResult(
    hospital,
    reference.version,
    results,
    reviewPreview: reviewPreview,
  );
}

/// Request scope is private memory, never a public hospital cache key.
class MatchRequestIdentity {
  final String userId, referenceVersion;
  final int sessionGeneration, consentEpoch, profileVersion, searchRevision;
  const MatchRequestIdentity(
    this.userId,
    this.sessionGeneration,
    this.consentEpoch,
    this.profileVersion,
    this.referenceVersion,
    this.searchRevision,
  );
  @override
  bool operator ==(Object other) =>
      other is MatchRequestIdentity &&
      userId == other.userId &&
      sessionGeneration == other.sessionGeneration &&
      consentEpoch == other.consentEpoch &&
      profileVersion == other.profileVersion &&
      referenceVersion == other.referenceVersion &&
      searchRevision == other.searchRevision;
  @override
  int get hashCode => Object.hash(
    userId,
    sessionGeneration,
    consentEpoch,
    profileVersion,
    referenceVersion,
    searchRevision,
  );
  @override
  String toString() => 'MatchRequestIdentity[redacted]';
}

class MatchSession {
  int _generation = 0;
  List<HospitalDiseaseMatchResult> results = const [];
  MatchRequestIdentity? identity;
  void clear() {
    _generation++;
    identity = null;
    results = const [];
  }

  Future<void> evaluate(
    MatchRequestIdentity owner,
    Future<List<HospitalDiseaseMatchResult>> Function() operation,
  ) async {
    clear();
    identity = owner;
    final generation = _generation;
    final result = await operation();
    if (generation == _generation && identity == owner) {
      results = List.unmodifiable(result);
    }
  }
}
