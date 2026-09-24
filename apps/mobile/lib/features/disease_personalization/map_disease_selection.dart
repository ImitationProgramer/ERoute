class StandardDiseaseSelection {
  final List<String> diseaseIds;
  final String? catalogVersion;
  final DateTime? confirmedAt;
  const StandardDiseaseSelection.empty()
    : diseaseIds = const [],
      catalogVersion = null,
      confirmedAt = null;
  StandardDiseaseSelection(
    Iterable<String> ids, {
    this.catalogVersion,
    this.confirmedAt,
  }) : diseaseIds = List.unmodifiable(ids);
  factory StandardDiseaseSelection.fromJson(Object? value) {
    if (value == null) return const StandardDiseaseSelection.empty();
    final j = value as Map;
    return StandardDiseaseSelection(
      (j['diseaseIds'] as List).cast<String>(),
      catalogVersion: j['catalogVersion'],
      confirmedAt: DateTime.tryParse(j['confirmedAt'] ?? ''),
    );
  }
  @override
  String toString() => 'StandardDiseaseSelection[redacted]';
}

class MapDiseaseSelection {
  final String state;
  final List<String> diseaseIds;
  final String? purpose, purposeVersion, referenceVersion;
  final DateTime? confirmedAt;
  const MapDiseaseSelection.none()
    : state = 'NOT_SELECTED',
      diseaseIds = const [],
      purpose = null,
      purposeVersion = null,
      referenceVersion = null,
      confirmedAt = null;
  MapDiseaseSelection({
    required this.state,
    required Iterable<String> diseaseIds,
    this.purpose,
    this.purposeVersion,
    this.referenceVersion,
    this.confirmedAt,
  }) : diseaseIds = List.unmodifiable(diseaseIds);
  factory MapDiseaseSelection.fromJson(Object? value) {
    if (value == null) return const MapDiseaseSelection.none();
    final j = value as Map;
    final state = j['state'] as String;
    if (!{'NOT_SELECTED', 'CONFIRMED', 'RECONFIRM_REQUIRED'}.contains(state)) {
      throw const FormatException('선택 상태를 확인하지 못했습니다.');
    }
    return MapDiseaseSelection(
      state: state,
      diseaseIds: (j['diseaseIds'] as List).cast<String>(),
      purpose: j['purpose'],
      purposeVersion: j['purposeVersion'],
      referenceVersion: j['referenceVersion'],
      confirmedAt: DateTime.tryParse(j['confirmedAt'] ?? ''),
    );
  }
  MapDiseaseSelection reconfirm() => state == 'NOT_SELECTED'
      ? this
      : MapDiseaseSelection(
          state: 'RECONFIRM_REQUIRED',
          diseaseIds: diseaseIds,
          purpose: purpose,
          purposeVersion: purposeVersion,
          referenceVersion: referenceVersion,
          confirmedAt: confirmedAt,
        );
  @override
  String toString() => 'MapDiseaseSelection[redacted]';
}

class MapSelectionSnapshot {
  final int version, consentEpoch;
  final MapDiseaseSelection selection;
  const MapSelectionSnapshot(this.version, this.consentEpoch, this.selection);
  factory MapSelectionSnapshot.fromJson(Map<String, dynamic> j) =>
      MapSelectionSnapshot(
        j['version'] as int,
        j['consentEpoch'] as int,
        MapDiseaseSelection.fromJson(j['mapDiseaseSelection']),
      );
  @override
  String toString() => 'MapSelectionSnapshot[redacted]';
}
