import '../disease_personalization/emergency_condition.dart';
import '../disease_personalization/map_disease_selection.dart';
import 'package:dio/dio.dart';
import '../auth/auth_repository.dart';
import 'member_contract.dart';
import 'member_product.dart';

/// The snapshot is a single server transaction, never composed from two GETs.
MemberHealthSnapshot decodeHealth(Map<String, dynamic> value) {
  EntryStatus status(Object? raw) =>
      EntryStatus.values.byName((raw as String).toLowerCase());
  HealthEntry entry(String name) {
    final field = value[name] as Map;
    return HealthEntry(status(field['status']), field['text'] as String);
  }

  return MemberHealthSnapshot(
    conditionEntries: (value['conditionEntries'] as List?)
        ?.map((e) => EmergencyCondition.fromJson(e as Map))
        .toList(),
    version: value['version'] as int,
    consentEpoch: value['consentEpoch'] as int,
    allergies: entry('allergies'),
    conditions: entry('conditions'),
    standardDiseaseSelection: StandardDiseaseSelection.fromJson(
      value['standardDiseaseSelection'],
    ),
    mapDiseaseSelection: MapDiseaseSelection.fromJson(
      value['mapDiseaseSelection'],
    ),
    note: value['note'] as String,
    medicationsStatus: status(value['medicationsStatus']),
    updatedAt: DateTime.tryParse(value['updatedAt'] as String? ?? ''),
    medications: (value['medications'] as List).map((raw) {
      final m = raw as Map;
      if (m['consentEpoch'] != value['consentEpoch'] ||
          m['source'] != 'MANUAL' ||
          m['productCode'] != null) {
        throw const MemberFailure(
          MemberFailureKind.validation,
          '서버 기록 형식을 확인하지 못했습니다.',
        );
      }
      return MedicationEntry(
        id: m['id'] as String,
        name: m['name'] as String,
        note: m['note'] as String,
        version: m['version'] as int,
        updatedAt: DateTime.parse(m['updatedAt'] as String),
      );
    }).toList(),
  );
}

class MedicationWrite {
  final int baseVersion, consentEpoch;
  final int? version;
  final String name, note;
  const MedicationWrite({
    required this.baseVersion,
    required this.consentEpoch,
    this.version,
    required this.name,
    required this.note,
  });
  Map<String, Object> toJson() => {
    'baseVersion': baseVersion,
    'consentEpoch': consentEpoch,
    'version': ?version,
    'name': name,
    'note': note,
  };
}

class RemoteMemberRepository implements MemberUiRepository {
  final AuthRepository auth;
  String? _identity;
  final Map<int, MemberHealthSnapshot> _bases = {};
  final void Function()? onChange;
  final Future<void> Function()? onConditionsCleared;
  RemoteMemberRepository(this.auth, {this.onChange, this.onConditionsCleared});
  void clear() {
    _identity = null;
    _bases.clear();
  }

  Future<T> _run<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on AuthFailure catch (e) {
      clear();
      throw MemberFailure(MemberFailureKind.session, e.message);
    } on DioException catch (e) {
      final code = (e.response?.data is Map ? e.response?.data['code'] : null);
      if (code == 'DATA_VERSION_CONFLICT') {
        throw const MemberFailure(
          MemberFailureKind.conflict,
          '다른 곳에서 정보가 변경되었습니다. 최신 내용을 확인한 뒤 다시 편집해주세요.',
        );
      }
      if (code == 'CONSENT_GENERATION_CHANGED' ||
          code == 'HEALTH_CONSENT_REQUIRED') {
        clear();
        throw const MemberFailure(
          MemberFailureKind.consent,
          '건강정보 동의 상태가 변경되었습니다. 다시 확인해주세요.',
        );
      }
      if (e.response?.statusCode == 401) {
        clear();
        throw MemberFailure(MemberFailureKind.session, authError(e));
      }
      throw MemberFailure(MemberFailureKind.validation, authError(e));
    }
  }

  @override
  Future<MemberAccess> access() => _run(() async {
    final user = await auth.me();
    // Operators may manage their session, but never receive medical privileges.
    final consent = user['healthConsent'] as Map;
    final jobs = user['role'] == 'MEMBER'
        ? (await auth.request(
                'GET',
                '/api/v1/me/health-consent/withdrawals',
              )).data
              as List
        : const [];
    final a = MemberAccess(
      userId: user['userId'] as String,
      phone: user['phone'] as String,
      sessionGeneration: auth.generation,
      consentEpoch: consent['epoch'] as int,
      consentState: user['role'] == 'MEMBER'
          ? consent['state'] as String
          : 'FORBIDDEN',
      deletions: jobs
          .map(
            (j) => DeletionProgress(
              j['state'] as String,
              backupComplete: j['backupComplete'] == true,
            ),
          )
          .toList(),
    );
    if (_identity != a.identity || !a.granted) _bases.clear();
    _identity = a.identity;
    return a;
  });
  @override
  Future<Map<String, dynamic>> authenticate(
    String phone,
    String password, {
    required bool signup,
    required bool terms,
    bool age14OrOlder = false,
  }) async {
    clear();
    return _run(
      () => auth.passwordLogin(
        phone,
        password,
        signup: signup,
        termsAccepted: terms,
        age14OrOlder: age14OrOlder,
      ),
    );
  }

  @override
  Future<MemberHealthSnapshot> readHealth() => _run(() async {
    final identity = _identity;
    final r = await auth.request('GET', '/api/v1/me/health-snapshot');
    final snapshot = decodeHealth(Map<String, dynamic>.from(r.data as Map));
    if (identity != _identity) {
      throw const MemberFailure(
        MemberFailureKind.session,
        '이전 계정의 요청이 취소되었습니다.',
      );
    }
    _bases[snapshot.version] = snapshot;
    if (_bases.length > 16) _bases.remove(_bases.keys.first);
    return snapshot;
  });
  @override
  Future<MemberHealthSnapshot> saveField(
    HealthFieldEdit edit,
  ) => _run(() async {
    onChange?.call();
    final base = _bases[edit.baseVersion];
    if (base == null) {
      throw const MemberFailure(
        MemberFailureKind.conflict,
        '편집 원본이 만료되었습니다. 최신 내용을 확인해주세요.',
      );
    }
    final changed = applyHealthFieldEdit(base, edit, DateTime.now());
    Map<String, Object> entry(HealthEntry e) => {
      'status': e.status.name.toUpperCase(),
      'text': e.text,
    };
    final r = await auth.request(
      'PUT',
      '/api/v1/me/emergency-profile',
      data: {
        'version': base.version,
        'consentEpoch': edit.consentEpoch,
        'allergies': entry(changed.allergies),
        'conditions': entry(changed.conditions),
        'note': changed.note,
        'medicationsStatus': changed.medicationsStatus.name.toUpperCase(),
      },
    );
    final value = Map<String, dynamic>.from(r.data as Map);
    // PUT confirms only the profile; preserve this exact-version medication list.
    final result = MemberHealthSnapshot(
      conditionEntries: (value['conditionEntries'] as List?)
          ?.map((e) => EmergencyCondition.fromJson(e as Map))
          .toList(),
      version: value['version'] as int,
      consentEpoch: value['consentEpoch'] as int,
      allergies: changed.allergies,
      conditions: changed.conditions,
      standardDiseaseSelection: StandardDiseaseSelection.fromJson(
        value['standardDiseaseSelection'],
      ),
      mapDiseaseSelection: MapDiseaseSelection.fromJson(
        value['mapDiseaseSelection'],
      ),
      note: changed.note,
      medicationsStatus: changed.medicationsStatus,
      medications: base.medications,
      updatedAt: DateTime.parse(value['updatedAt'] as String),
    );
    _bases[result.version] = result;
    return result;
  });
  @override
  Future<void> saveMedication({
    MedicationEntry? original,
    MedicationProduct? product,
    required String name,
    required String note,
    required int baseVersion,
    required int consentEpoch,
  }) => _run(() async {
    onChange?.call();
    if (product != null || original?.product != null) {
      throw const MemberFailure(
        MemberFailureKind.validation,
        '제품 검색 연결은 준비 중입니다. 직접 입력해주세요.',
      );
    }
    await auth.request(
      original == null ? 'POST' : 'PUT',
      '/api/v1/me/medications${original == null ? '' : '/${original.id}'}',
      data: MedicationWrite(
        baseVersion: baseVersion,
        consentEpoch: consentEpoch,
        version: original?.version,
        name: name,
        note: note,
      ).toJson(),
    );
  });
  @override
  Future<void> deleteMedication(
    MedicationEntry entry,
    int baseVersion,
    int epoch,
  ) => _run(() async {
    onChange?.call();
    await auth.request(
      'DELETE',
      '/api/v1/me/medications/${entry.id}?baseVersion=$baseVersion&consentEpoch=$epoch&version=${entry.version}',
    );
  });
  @override
  Future<void> deleteProfile(int baseVersion, int epoch) => _run(() async {
    onChange?.call();
    await auth.request(
      'DELETE',
      '/api/v1/me/emergency-profile',
      data: {'version': baseVersion, 'consentEpoch': epoch},
    );
    await onConditionsCleared?.call();
    _bases.clear();
  });
  @override
  Future<void> grantConsent(int epoch) => _run(() async {
    await auth.request(
      'POST',
      '/api/v1/me/health-consent',
      data: {'epoch': epoch, 'documentVersion': 'health-v1'},
    );
    clear();
  });
  @override
  Future<void> withdrawConsent(int epoch, String requestKey) => _run(() async {
    onChange?.call();
    clear();
    await auth.request(
      'POST',
      '/api/v1/me/health-consent/withdrawals',
      data: {'epoch': epoch},
      headers: {'Idempotency-Key': requestKey},
    );
    await onConditionsCleared?.call();
  });
  @override
  Future<void> retryDeletion() => _run(() async {
    final jobs =
        (await auth.request(
              'GET',
              '/api/v1/me/health-consent/withdrawals',
            )).data
            as List;
    for (final job in jobs.where((j) => j['state'] == 'FAILED')) {
      await auth.request(
        'POST',
        '/api/v1/me/health-consent/withdrawals/${job['id']}/retry',
      );
    }
  });
  @override
  Future<void> logoutAll() => _run(() async {
    clear();
    await auth.request('POST', '/api/v1/auth/logout-all');
  });
}
