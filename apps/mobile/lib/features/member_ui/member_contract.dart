import '../disease_personalization/condition_local_store.dart';
import '../disease_personalization/emergency_condition.dart';
import '../../core/privacy_changes.dart';
import '../disease_personalization/map_disease_selection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'member_product.dart';
import '../app_menu/app_session.dart';
import 'remote_member_repository.dart';

enum EntryStatus { unset, none, recorded }

enum HealthField { allergies, conditions, note, medicationsStatus }

enum MemberFailureKind { validation, unavailable, conflict, consent, session }

class MemberFailure implements Exception {
  final MemberFailureKind kind;
  final String message;
  const MemberFailure(this.kind, this.message);
  @override
  String toString() => message;
}

class HealthEntry {
  final EntryStatus status;
  final String text;
  const HealthEntry(this.status, [this.text = '']);
  String get summary => switch (status) {
    EntryStatus.unset => '아직 입력하지 않았어요',
    EntryStatus.none => '없음 · 직접 확인',
    EntryStatus.recorded => text,
  };
}

class MedicationEntry {
  final String id, name, note;
  final MedicationProduct? product;
  final int version;
  final DateTime updatedAt;
  const MedicationEntry({
    required this.id,
    required this.name,
    this.note = '',
    this.product,
    required this.version,
    required this.updatedAt,
  });
}

class MemberHealthSnapshot {
  final List<EmergencyCondition>? conditionEntries;
  final int version, consentEpoch;
  final HealthEntry allergies, conditions;
  final MapDiseaseSelection mapDiseaseSelection;
  final StandardDiseaseSelection standardDiseaseSelection;
  final String note;
  final EntryStatus medicationsStatus;
  final List<MedicationEntry> medications;
  final DateTime? updatedAt;
  MemberHealthSnapshot({
    required this.version,
    required this.consentEpoch,
    this.conditionEntries,
    this.allergies = const HealthEntry(EntryStatus.unset),
    this.conditions = const HealthEntry(EntryStatus.unset),
    this.note = '',
    this.mapDiseaseSelection = const MapDiseaseSelection.none(),
    this.standardDiseaseSelection = const StandardDiseaseSelection.empty(),
    this.medicationsStatus = EntryStatus.unset,
    List<MedicationEntry> medications = const [],
    this.updatedAt,
  }) : medications = List.unmodifiable(medications);
}

/// UI command, not an HTTP PATCH contract. Version and epoch are mandatory.
class HealthFieldEdit {
  final HealthField field;
  final int baseVersion, consentEpoch;
  final HealthEntry? entry;
  final String? note;
  final EntryStatus? medicationsStatus;
  const HealthFieldEdit({
    required this.field,
    required this.baseVersion,
    required this.consentEpoch,
    this.entry,
    this.note,
    this.medicationsStatus,
  });
}

/// Fail before merging. A future HTTP adapter must send the original complete
/// snapshot plus this one edit using the same version, never a fresh version.
MemberHealthSnapshot applyHealthFieldEdit(
  MemberHealthSnapshot base,
  HealthFieldEdit edit,
  DateTime now,
) {
  if (base.consentEpoch != edit.consentEpoch) {
    throw const MemberFailure(
      MemberFailureKind.consent,
      '건강정보 동의 상태가 변경되었습니다. 현재 권한을 다시 확인해주세요.',
    );
  }
  if (base.version != edit.baseVersion) {
    throw const MemberFailure(
      MemberFailureKind.conflict,
      '다른 곳에서 정보가 변경되었습니다. 최신 내용을 확인한 뒤 다시 편집해주세요.',
    );
  }
  if (edit.field == HealthField.allergies ||
      edit.field == HealthField.conditions) {
    final e = edit.entry;
    if (e == null ||
        e.text.length > 2000 ||
        (e.status == EntryStatus.recorded) != e.text.trim().isNotEmpty) {
      throw const MemberFailure(
        MemberFailureKind.validation,
        '등록할 내용을 입력해주세요.',
      );
    }
  }
  if (edit.field == HealthField.note &&
      (edit.note == null || edit.note!.length > 2000)) {
    throw const MemberFailure(
      MemberFailureKind.validation,
      '메모는 2,000자 이내로 입력해주세요.',
    );
  }
  if (edit.field == HealthField.medicationsStatus &&
      (edit.medicationsStatus == null ||
          (base.medications.isNotEmpty !=
              (edit.medicationsStatus == EntryStatus.recorded)))) {
    throw const MemberFailure(
      MemberFailureKind.validation,
      '복용약 목록과 입력 상태를 확인해주세요.',
    );
  }
  return MemberHealthSnapshot(
    conditionEntries: base.conditionEntries,
    version: base.version + 1,
    consentEpoch: base.consentEpoch,
    allergies: edit.field == HealthField.allergies
        ? edit.entry!
        : base.allergies,
    conditions: edit.field == HealthField.conditions
        ? edit.entry!
        : base.conditions,
    note: edit.field == HealthField.note ? edit.note! : base.note,
    medicationsStatus: edit.field == HealthField.medicationsStatus
        ? edit.medicationsStatus!
        : base.medicationsStatus,
    medications: base.medications,
    standardDiseaseSelection:
        edit.field == HealthField.conditions &&
            edit.entry!.status == EntryStatus.none
        ? const StandardDiseaseSelection.empty()
        : base.standardDiseaseSelection,
    mapDiseaseSelection: edit.field != HealthField.conditions
        ? base.mapDiseaseSelection
        : edit.entry!.status == EntryStatus.none
        ? const MapDiseaseSelection.none()
        : edit.entry!.text.trim() != base.conditions.text
        ? base.mapDiseaseSelection.reconfirm()
        : base.mapDiseaseSelection,
    updatedAt: now,
  );
}

class DeletionProgress {
  final String state;
  final bool backupComplete;
  const DeletionProgress(this.state, {this.backupComplete = false});
}

class MemberAccess {
  final String userId, phone, consentState;
  final int sessionGeneration, consentEpoch;
  final List<DeletionProgress> deletions;
  const MemberAccess({
    required this.userId,
    required this.phone,
    required this.sessionGeneration,
    required this.consentEpoch,
    required this.consentState,
    this.deletions = const [],
  });
  bool get granted => consentState == 'GRANTED';
  String get identity => '$userId:$sessionGeneration:$consentEpoch';
}

/// Production binding intentionally absent in phase one. Implementations use
/// existing AuthRepository for transport and SessionController for session writes.
abstract interface class MemberUiRepository {
  Future<MemberAccess> access();
  Future<Map<String, dynamic>> authenticate(
    String phone,
    String password, {
    required bool signup,
    required bool terms,
    bool age14OrOlder = false,
  });
  Future<MemberHealthSnapshot> readHealth();
  Future<MemberHealthSnapshot> saveField(HealthFieldEdit edit);
  Future<void> saveMedication({
    MedicationEntry? original,
    MedicationProduct? product,
    required String name,
    required String note,
    required int baseVersion,
    required int consentEpoch,
  });
  Future<void> deleteMedication(
    MedicationEntry entry,
    int baseVersion,
    int epoch,
  );
  Future<void> deleteProfile(int baseVersion, int epoch);
  Future<void> grantConsent(int epoch);
  Future<void> withdrawConsent(int epoch, String requestKey);
  Future<void> retryDeletion();
  Future<void> logoutAll();
}

final memberUiRepositoryProvider = Provider.autoDispose<MemberUiRepository>((
  ref,
) {
  final repository = RemoteMemberRepository(
    ref.watch(authRepositoryProvider),
    onChange: () => ref.read(privacyChangeProvider.notifier).state++,
    onConditionsCleared: () => ref.read(conditionLocalProvider.notifier).purge(),
  );
  ref.listen(sessionProvider, (old, next) {
    if (old?.userId != next.userId ||
        old?.generation != next.generation ||
        !next.authenticated) {
      repository.clear();
    }
  });
  ref.onDispose(repository.clear);
  return repository;
});

String memberError(Object e) =>
    e is MemberFailure ? e.message : '상태를 확인하지 못했습니다. 다시 시도해주세요.';

String memberTime(DateTime? value) {
  if (value == null) return '아직 저장한 정보가 없어요';
  final d = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}.${two(d.month)}.${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}
