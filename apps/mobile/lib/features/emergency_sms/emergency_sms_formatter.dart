import '../disease_personalization/emergency_condition.dart';
import '../../core/location/location_fix.dart';
import '../member_ui/member_contract.dart';

/// Only these user-visible fields can cross the SMS handoff boundary.
/// No identity, phone, consent/version, catalog IDs or inferred departments.
Map<String, String> emergencySmsFields(
  MemberHealthSnapshot health,
  LocationFix? location, {
  List<EmergencyCondition>? conditions,
  EntryStatus? conditionsStatus,
}) {
  final fields = <String, String>{};
  if (location != null) {
    fields['현재 위치'] =
        '좌표: ${location.point.latitude.toStringAsFixed(6)}, ${location.point.longitude.toStringAsFixed(6)}';
  }
  conditions ??= health.conditionEntries;
  conditionsStatus ??= health.conditions.status;
  if (conditions != null && conditions.isNotEmpty) {
    fields['기저질환'] = conditions
        .where((e) => e.name != e.diseaseId)
        .map((e) => e.name)
        .join(', ');
  } else if (conditionsStatus == EntryStatus.none) {
    fields['기저질환'] = '없음';
  } else if (conditionsStatus == EntryStatus.recorded &&
      health.conditions.text.trim().isNotEmpty) {
    fields['기저질환'] = health.conditions.text;
  }
  if (health.allergies.status == EntryStatus.none) {
    fields['알레르기'] = '없음';
  } else if (health.allergies.status == EntryStatus.recorded) {
    fields['알레르기'] = health.allergies.text;
  }
  if (health.medicationsStatus == EntryStatus.none) {
    fields['복용약'] = '없음';
  } else if (health.medicationsStatus == EntryStatus.recorded &&
      health.medications.isNotEmpty) {
    fields['복용약'] = health.medications
        .map(
          (m) =>
              m.note.trim().isEmpty ? m.name : '${m.name} (복용 메모: ${m.note})',
        )
        .join('\n');
  }
  if (health.note.trim().isNotEmpty) fields['응급 메모'] = health.note;
  fields.removeWhere((_, value) => value.trim().isEmpty);
  return fields;
}

/// Single canonical body for both the exact preview and native composer.
String formatEmergencySms(Map<String, String> selectedFields) => [
  '[ERoute 응급정보]',
  for (final name in ['현재 위치', '기저질환', '알레르기', '복용약', '응급 메모'])
    if (selectedFields[name]?.trim().isNotEmpty == true)
      '$name: ${selectedFields[name]}',
  '',
  '※ 사용자가 ERoute에 직접 입력한 건강정보와 확인한 위치를 전송하기로 선택한 내용입니다.',
  '※ 긴급 상황에서는 119 통화 안내를 우선 따르세요.',
].join('\n');
