import 'package:unorm_dart/unorm_dart.dart' as unicode;
import 'disease_catalog.dart';

class EmergencyCondition {
  final String? diseaseId;
  final String name;
  bool get standard => diseaseId != null;
  const EmergencyCondition.standard(String id, this.name) : diseaseId = id;
  const EmergencyCondition.custom(this.name) : diseaseId = null;
  factory EmergencyCondition.fromJson(Map j) => switch (j['type']) {
    'STANDARD' => EmergencyCondition.standard(
      j['diseaseId'] as String,
      j['displayName'] as String? ?? j['diseaseId'] as String,
    ),
    'CUSTOM' => EmergencyCondition.custom(j['customName'] as String),
    _ => throw const FormatException('질환 기록 형식을 확인해주세요.'),
  };
  Map<String, Object> toJson() => standard
      ? {'type': 'STANDARD', 'diseaseId': diseaseId!, 'displayName': name}
      : {'type': 'CUSTOM', 'customName': name};
  String get identity =>
      standard ? 'S:$diseaseId' : 'C:${customConditionKey(name)}';
}

String customConditionKey(String text) =>
    unicode.nfc(text).trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
List<EmergencyCondition> uniqueConditions(
  Iterable<EmergencyCondition> entries,
) {
  final seen = <String>{};
  return entries.where((e) => seen.add(e.identity)).toList();
}

List<EmergencyCondition> migrateConditions(
  List<String> ids,
  String raw,
  DiseaseCatalog? catalog,
) {
  final result = ids
      .map(
        (id) => EmergencyCondition.standard(id, catalog?.byId(id)?.name ?? id),
      )
      .toList();
  if (raw.trim().isNotEmpty) {
    final id = catalog?.exact(raw);
    result.add(
      id == null
          ? EmergencyCondition.custom(raw)
          : EmergencyCondition.standard(id, catalog!.byId(id)!.name),
    );
  }
  return uniqueConditions(result);
}
