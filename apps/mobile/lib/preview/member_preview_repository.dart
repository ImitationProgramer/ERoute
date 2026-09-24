import '../features/member_ui/member_product.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import '../features/auth/auth_repository.dart';
import '../features/member_ui/member_contract.dart';
import '../features/member_ui/member_widgets.dart';

enum PreviewScenario {
  saved,
  empty,
  loading,
  readFailure,
  saveFailure,
  consentRequired,
  versionConflict,
  consentConflict,
  unsaved,
  deletionFailed,
  deletionComplete,
}

class PreviewVault implements TokenVault {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String? value) async {}
}

class PreviewPrivacy implements MemberPrivacy {
  @override
  Future<void> sensitive(bool value) async {}
  @override
  Future<void> allowDisplay() async {}
}

/// No sockets, secure storage, real tokens, or real AuthRepository transactions.
class PreviewAuthRepository extends AuthRepository {
  Map<String, dynamic>? user;
  PreviewAuthRepository()
    : super(
        dio: Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) => handler.reject(
                DioException(
                  requestOptions: options,
                  error: 'UI preview forbids all HTTP',
                ),
              ),
            ),
          ),
        vault: PreviewVault(),
      );
  @override
  Future<Map<String, dynamic>?> restore() async => user;
  @override
  Future<Map<String, dynamic>> me() async =>
      user ??
      (throw const MemberFailure(MemberFailureKind.session, '로그인이 필요합니다.'));
  @override
  Future<bool> signOut() async {
    generation++;
    user = null;
    return true;
  }

  @override
  Future<bool> retryLogout() async => true;
  @override
  Future<Response<dynamic>> request(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? headers,
  }) async => throw StateError('Preview cannot call HTTP: $method $path');
}

class PreviewMemberRepository implements MemberUiRepository {
  final PreviewAuthRepository auth;
  final DateTime Function() now;
  Duration delay;
  PreviewScenario scenario = PreviewScenario.saved;
  bool granted = true;
  String fixtureUserId = 'ui-preview-member';
  int epoch = 1, sequence = 0;
  List<DeletionProgress> jobs = [];
  late MemberHealthSnapshot data;
  PreviewMemberRepository(
    this.auth, {
    DateTime Function()? now,
    this.delay = const Duration(milliseconds: 450),
  }) : now = now ?? DateTime.now {
    reset(PreviewScenario.saved);
  }
  Map<String, dynamic> get user => {
    'userId': fixtureUserId,
    'phone': '010-****-5678',
    'role': 'MEMBER',
    'source': 'UI_PREVIEW',
    'healthConsent': {'epoch': epoch, 'state': granted ? 'GRANTED' : 'REVOKED'},
  };
  void reset(PreviewScenario value, {String userId = 'ui-preview-member'}) {
    fixtureUserId = userId;
    scenario = value;
    epoch++;
    auth.generation++;
    granted = ![
      PreviewScenario.consentRequired,
      PreviewScenario.deletionFailed,
      PreviewScenario.deletionComplete,
    ].contains(value);
    jobs = value == PreviewScenario.deletionFailed
        ? [const DeletionProgress('FAILED')]
        : value == PreviewScenario.deletionComplete
        ? [const DeletionProgress('COMPLETE')]
        : [];
    auth.user = user;
    data = MemberHealthSnapshot(
      version: 1,
      consentEpoch: epoch,
      allergies: value == PreviewScenario.empty
          ? const HealthEntry(EntryStatus.unset)
          : const HealthEntry(EntryStatus.recorded, '페니실린 계열 약에 알레르기가 있어요.'),
      conditions: value == PreviewScenario.empty
          ? const HealthEntry(EntryStatus.unset)
          : const HealthEntry(EntryStatus.none),
      note: value == PreviewScenario.empty ? '' : '응급 상황에서는 보호자에게 연락해주세요.',
      medicationsStatus: value == PreviewScenario.empty
          ? EntryStatus.unset
          : EntryStatus.recorded,
      medications: value == PreviewScenario.empty
          ? []
          : [
              MedicationEntry(
                id: 'preview-med-1',
                name: '가상 복용약',
                note: '식사 후 복용한다고 직접 기록했어요.',
                version: 1,
                updatedAt: now(),
              ),
            ],
      updatedAt: value == PreviewScenario.empty ? null : now(),
    );
  }

  Future<void> wait() async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
  }

  void authorized([int? expectedEpoch]) {
    if (auth.user == null) {
      throw const MemberFailure(MemberFailureKind.session, '로그인이 필요합니다.');
    }
    if (!granted || expectedEpoch != null && expectedEpoch != epoch) {
      throw const MemberFailure(
        MemberFailureKind.consent,
        '건강정보 동의 상태가 변경되었습니다. 현재 권한을 다시 확인해주세요.',
      );
    }
  }

  @override
  Future<MemberAccess> access() async {
    await wait();
    if (auth.user == null) {
      throw const MemberFailure(MemberFailureKind.session, '로그인이 필요합니다.');
    }
    if (scenario == PreviewScenario.readFailure) {
      throw const MemberFailure(
        MemberFailureKind.unavailable,
        '정보를 불러오지 못했습니다. 연결 상태를 확인한 뒤 다시 시도해주세요.',
      );
    }
    return MemberAccess(
      userId: user['userId'] as String,
      phone: user['phone'] as String,
      sessionGeneration: auth.generation,
      consentEpoch: epoch,
      consentState: granted
          ? 'GRANTED'
          : jobs.any((j) => j.state != 'COMPLETE')
          ? 'REVOKING'
          : 'REVOKED',
      deletions: List.unmodifiable(jobs),
    );
  }

  @override
  Future<Map<String, dynamic>> authenticate(
    String phone,
    String password, {
    required bool signup,
    required bool terms,
    bool age14OrOlder = false,
  }) async {
    await wait();
    final digits = phone.replaceAll(RegExp(r'[\s-]'), '');
    if (!RegExp(r'^010\d{8}$').hasMatch(digits) ||
        password.isEmpty ||
        signup && !terms) {
      throw const MemberFailure(
        MemberFailureKind.validation,
        '번호·비밀번호와 가입 동의를 확인해주세요.',
      );
    }
    if (scenario == PreviewScenario.saveFailure) {
      throw const MemberFailure(
        MemberFailureKind.unavailable,
        '요청을 처리하지 못했습니다. 다시 시도해주세요.',
      );
    }
    if (!signup &&
        (digits != '01012345678' || password != 'preview-password-only')) {
      throw const MemberFailure(
        MemberFailureKind.validation,
        '휴대폰 번호 또는 비밀번호를 확인해주세요.',
      );
    }
    if (signup) {
      reset(PreviewScenario.empty);
      granted = false;
    }
    auth.generation++;
    auth.user = user;
    return auth.user!;
  }

  @override
  Future<MemberHealthSnapshot> readHealth() async {
    final generation = auth.generation;
    final owner = auth.user?['userId'];
    await wait();
    authorized();
    if (generation != auth.generation || owner != auth.user?['userId']) {
      throw const MemberFailure(MemberFailureKind.session, '계정이 변경되었습니다.');
    }
    if (scenario == PreviewScenario.loading) {
      await Future<void>.delayed(const Duration(seconds: 30));
    }
    authorized();
    if (generation != auth.generation || owner != auth.user?['userId']) {
      throw const MemberFailure(MemberFailureKind.session, '계정이 변경되었습니다.');
    }
    if (data.consentEpoch != epoch) {
      throw const MemberFailure(
        MemberFailureKind.consent,
        '건강정보 동의 상태가 변경되었습니다.',
      );
    }
    return data;
  }

  Future<void> beforeWrite(int version, int expectedEpoch) async {
    final generation = auth.generation;
    final owner = auth.user?['userId'];
    await wait();
    if (generation != auth.generation || owner != auth.user?['userId']) {
      throw const MemberFailure(MemberFailureKind.session, '계정이 변경되었습니다.');
    }
    if (scenario == PreviewScenario.saveFailure) {
      throw const MemberFailure(
        MemberFailureKind.unavailable,
        '저장하지 못했습니다. 입력한 내용은 유지됩니다. 다시 시도해주세요.',
      );
    }
    if (scenario == PreviewScenario.versionConflict) {
      scenario = PreviewScenario.saved;
      data = applyHealthFieldEdit(
        data,
        HealthFieldEdit(
          field: HealthField.note,
          baseVersion: data.version,
          consentEpoch: epoch,
          note: '다른 기기에서 변경한 가상 메모입니다.',
        ),
        now(),
      );
    }
    if (scenario == PreviewScenario.consentConflict) {
      scenario = PreviewScenario.saved;
      epoch++;
      granted = false;
      auth.user = user;
    }
    authorized(expectedEpoch);
    if (version != data.version) {
      throw const MemberFailure(
        MemberFailureKind.conflict,
        '다른 곳에서 정보가 변경되었습니다. 최신 내용을 확인한 뒤 다시 편집해주세요.',
      );
    }
  }

  @override
  Future<MemberHealthSnapshot> saveField(HealthFieldEdit edit) async {
    await beforeWrite(edit.baseVersion, edit.consentEpoch);
    data = applyHealthFieldEdit(data, edit, now());
    return data;
  }

  void replaceMedications(List<MedicationEntry> meds) {
    data = MemberHealthSnapshot(
      version: data.version + 1,
      consentEpoch: epoch,
      allergies: data.allergies,
      conditions: data.conditions,
      note: data.note,
      medications: meds,
      medicationsStatus: meds.isEmpty
          ? EntryStatus.unset
          : EntryStatus.recorded,
      updatedAt: now(),
    );
  }

  @override
  Future<void> saveMedication({
    MedicationEntry? original,
    MedicationProduct? product,
    required String name,
    required String note,
    required int baseVersion,
    required int consentEpoch,
  }) async {
    await beforeWrite(baseVersion, consentEpoch);
    if (name.trim().isEmpty || name.length > 200 || note.length > 2000) {
      throw const MemberFailure(
        MemberFailureKind.validation,
        '약 이름은 200자, 메모는 2,000자 이내로 입력해주세요.',
      );
    }
    if ((product != null && name != product.name) ||
        (original != null &&
            ((original.product == null) != (product == null) ||
                original.product != null &&
                    !original.product!.sameProduct(product!)))) {
      throw const MemberFailure(
        MemberFailureKind.validation,
        '기존 기록의 제품 연결은 변경할 수 없습니다.',
      );
    }
    final meds = [...data.medications];
    if (original == null) {
      if (meds.length >= 100) {
        throw const MemberFailure(
          MemberFailureKind.validation,
          '복용약은 최대 100개까지 등록할 수 있습니다.',
        );
      }
      meds.add(
        MedicationEntry(
          id: 'preview-new-${++sequence}',
          name: name,
          product: product,
          note: note,
          version: 1,
          updatedAt: now(),
        ),
      );
    } else {
      final i = meds.indexWhere(
        (m) => m.id == original.id && m.version == original.version,
      );
      if (i < 0) {
        throw const MemberFailure(
          MemberFailureKind.conflict,
          '복용약이 변경되었습니다. 최신 목록을 확인해주세요.',
        );
      }
      meds[i] = MedicationEntry(
        id: original.id,
        name: name,
        product: product,
        note: note,
        version: original.version + 1,
        updatedAt: now(),
      );
    }
    replaceMedications(meds);
  }

  @override
  Future<void> deleteMedication(
    MedicationEntry entry,
    int baseVersion,
    int epoch,
  ) async {
    await beforeWrite(baseVersion, epoch);
    if (!data.medications.any(
      (m) => m.id == entry.id && m.version == entry.version,
    )) {
      throw const MemberFailure(
        MemberFailureKind.conflict,
        '복용약이 변경되었습니다. 최신 목록을 확인해주세요.',
      );
    }
    replaceMedications(
      data.medications.where((m) => m.id != entry.id).toList(),
    );
  }

  @override
  Future<void> deleteProfile(int baseVersion, int epoch) async {
    await beforeWrite(baseVersion, epoch);
    data = MemberHealthSnapshot(
      version: data.version + 1,
      consentEpoch: epoch,
      medicationsStatus: data.medicationsStatus,
      medications: data.medications,
      updatedAt: now(),
    );
  }

  @override
  Future<void> grantConsent(int expectedEpoch) async {
    await wait();
    if (auth.user == null ||
        expectedEpoch != epoch ||
        jobs.any((j) => j.state != 'COMPLETE')) {
      throw const MemberFailure(
        MemberFailureKind.consent,
        '동의 또는 삭제 처리 상태를 다시 확인해주세요.',
      );
    }
    granted = true;
    epoch++;
    data = MemberHealthSnapshot(version: 0, consentEpoch: epoch);
    auth.user = user;
  }

  final Set<String> withdrawalKeys = {};
  @override
  Future<void> withdrawConsent(int expectedEpoch, String requestKey) async {
    await wait();
    if (withdrawalKeys.contains(requestKey)) return;
    authorized(expectedEpoch);
    withdrawalKeys.add(requestKey);
    granted = false;
    epoch++;
    data = MemberHealthSnapshot(version: 0, consentEpoch: epoch);
    jobs = [const DeletionProgress('COMPLETE')];
    auth.user = user;
  }

  @override
  Future<void> retryDeletion() async {
    await wait();
    if (auth.user == null) {
      throw const MemberFailure(MemberFailureKind.session, '로그인이 필요합니다.');
    }
    jobs = [const DeletionProgress('COMPLETE')];
  }

  @override
  Future<void> logoutAll() async {
    await auth.signOut();
  }
}
