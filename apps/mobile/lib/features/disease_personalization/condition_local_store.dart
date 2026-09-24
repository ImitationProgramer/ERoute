import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/config/app_config.dart';
import '../../core/privacy_changes.dart';
import '../app_menu/app_session.dart';
import '../auth/auth_repository.dart';
import '../member_ui/member_contract.dart';
import 'disease_catalog.dart';
import 'emergency_condition.dart';

abstract interface class ConditionVault {
  Future<String?> read();
  Future<void> write(String? value);
}

class SecureConditionVault implements ConditionVault {
  final FlutterSecureStorage storage;
  SecureConditionVault({
    this.storage = const FlutterSecureStorage(
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.unlocked_this_device,
      ),
    ),
  });
  String get key =>
      'eroute.conditions.${AppConfig.authEnvironment}.${sha256.convert(utf8.encode(AppConfig.apiBaseUrl))}';
  @override
  Future<String?> read() => storage.read(key: key);
  @override
  Future<void> write(String? value) => value == null
      ? storage.delete(key: key)
      : storage.write(key: key, value: value);
}

class LocalConditions {
  final String userId, catalogVersion, status;
  final int epoch, baseVersion;
  final List<EmergencyCondition> entries;
  final bool pending, conflict;
  const LocalConditions({
    required this.userId,
    required this.epoch,
    required this.baseVersion,
    required this.catalogVersion,
    required this.status,
    required this.entries,
    this.pending = false,
    this.conflict = false,
  });
  factory LocalConditions.fromJson(Map j) => LocalConditions(
    userId: j['userId'],
    epoch: j['epoch'],
    baseVersion: j['baseVersion'],
    catalogVersion: j['catalogVersion'],
    status: j['status'],
    entries: (j['entries'] as List)
        .map((e) => EmergencyCondition.fromJson(e as Map))
        .toList(),
    pending: j['pending'] == true,
    conflict: j['conflict'] == true,
  );
  Map<String, Object> toJson() => {
    'userId': userId,
    'epoch': epoch,
    'baseVersion': baseVersion,
    'catalogVersion': catalogVersion,
    'status': status,
    'entries': entries.map((e) => e.toJson()).toList(),
    'pending': pending,
    'conflict': conflict,
  };
  LocalConditions changed({
    int? version,
    String? catalogVersion,
    bool? pending,
    bool? conflict,
  }) => LocalConditions(
    userId: userId,
    epoch: epoch,
    baseVersion: version ?? baseVersion,
    catalogVersion: catalogVersion ?? this.catalogVersion,
    status: status,
    entries: entries,
    pending: pending ?? this.pending,
    conflict: conflict ?? this.conflict,
  );
}

final conditionLocalProvider =
    StateNotifierProvider<ConditionLocalController, LocalConditions?>((ref) {
      final c = ConditionLocalController(
        SecureConditionVault(),
        ref.watch(authRepositoryProvider),
        ref.watch(diseaseCatalogRepositoryProvider),
        onChange: () => ref.read(privacyChangeProvider.notifier).state++,
      );
      ref.listen(sessionProvider, (old, next) {
        if (next.phase == SessionPhase.signedOut ||
            (old?.userId != null && old!.userId != next.userId) ||
            (old?.authenticated == true &&
                old?.generation != next.generation)) {
          unawaited(c.purge().catchError((Object _) {}));
        } else if (!next.authenticated) {
          c.suspend();
        }
      });
      return c;
    });

/// Only explicitly saved conditions reach this device-protected vault. No other health fields.
class ConditionLocalController extends StateNotifier<LocalConditions?> {
  final ConditionVault vault;
  final AuthRepository auth;
  final DiseaseCatalogRepository catalog;
  final void Function()? onChange;
  MemberAccess? _access;
  int _generation = 0;
  late Future<void> _storage = Future.value();
  Future<void>? _sync;
  LocalConditions? _server;
  ConditionLocalController(this.vault, this.auth, this.catalog, {this.onChange})
    : super(null);
  Future<void> _persist(LocalConditions? value, int ticket) {
    return _storage = _storage.catchError((_) {}).then((_) async {
      if (ticket != _generation) return;
      await vault.write(value == null ? null : jsonEncode(value.toJson()));
    });
  }

  void suspend() {
    _generation++;
    _access = null;
    if (state != null) state = null;
    _server = null;
  }

  Future<void> purge() async {
    suspend();
    await _persist(null, _generation);
  }

  bool get authorized => _access?.granted == true;

  /// Check only pending ownership on a direct map entry after restart. Never
  /// expose persisted names or authorize record display from this lightweight gate.
  Future<bool> mapReady(AppSession session) async {
    if (!session.authenticated) return false;
    if (state?.userId == session.userId) return state?.pending != true;
    try {
      await _storage.catchError((_) {});
      final raw = await vault.read();
      if (raw == null) return true;
      final saved = LocalConditions.fromJson(jsonDecode(raw) as Map);
      final consent = session.user?['healthConsent'];
      if (saved.userId != session.userId) return true;
      if (consent is! Map || consent['state'] != 'GRANTED') return false;
      return saved.epoch != consent['epoch'] || !saved.pending;
    } catch (_) {
      return false;
    }
  }

  Future<void> attach(MemberAccess access, MemberHealthSnapshot health) async {
    if (!access.granted) {
      await purge();
      return;
    }
    final ticket = ++_generation;
    if (state?.userId != access.userId || state?.epoch != access.consentEpoch) {
      state = null;
      _server = null;
    }
    _access = access;
    DiseaseCatalog? c;
    try {
      c = await catalog.catalog();
    } catch (_) {
      /* Legacy text stays intact until catalog is available. */
    }
    final raw = await vault.read();
    if (ticket != _generation || !mounted) return;
    LocalConditions? saved;
    try {
      if (raw != null) saved = LocalConditions.fromJson(jsonDecode(raw) as Map);
    } catch (_) {
      saved = null;
    }
    final entries =
        health.conditionEntries ??
        migrateConditions(
          health.standardDiseaseSelection.diseaseIds,
          health.conditions.text,
          c,
        );
    final server = LocalConditions(
      userId: access.userId,
      epoch: access.consentEpoch,
      baseVersion: health.version,
      catalogVersion: c?.version ?? '',
      status: entries.isNotEmpty
          ? 'RECORDED'
          : health.conditions.status.name.toUpperCase(),
      entries: entries,
    );
    _server = server;
    if (saved?.userId == access.userId &&
        saved?.epoch == access.consentEpoch &&
        saved?.pending == true) {
      state = _same(saved!, server)
          ? server
          : saved.changed(conflict: saved.baseVersion != health.version);
    } else {
      state = server;
    }
    await _persist(state, ticket);
  }

  bool _same(LocalConditions a, LocalConditions b) =>
      a.status == b.status &&
      jsonEncode(a.entries.map((e) => e.toJson()).toList()) ==
          jsonEncode(b.entries.map((e) => e.toJson()).toList());
  Future<void> save(
    List<EmergencyCondition> entries,
    String status,
    String catalogVersion, {
    int? expectedBaseVersion,
  }) async {
    final base = state;
    if (!authorized || base == null) {
      throw const MemberFailure(MemberFailureKind.session, '로그인 상태를 확인해주세요.');
    }
    if (expectedBaseVersion != null &&
        expectedBaseVersion != base.baseVersion) {
      throw const MemberFailure(
        MemberFailureKind.conflict,
        '편집 중 서버 기록이 변경되었습니다. 최신 내용을 확인해주세요.',
      );
    }
    if (base.conflict) {
      throw const MemberFailure(
        MemberFailureKind.conflict,
        '최신 내용을 확인한 뒤 다시 편집해주세요.',
      );
    }
    final unique = uniqueConditions(entries);
    if (unique.length > 100 ||
        unique.any((e) => e.name.trim().isEmpty) ||
        unique.where((e) => !e.standard).map((e) => e.name).join('\n').length >
            2000 ||
        (status == 'RECORDED') != unique.isNotEmpty) {
      throw const MemberFailure(
        MemberFailureKind.validation,
        '질환 이름과 입력 상태를 확인해주세요. 최대 100개, 직접 입력은 전체 2,000자까지 저장합니다.',
      );
    }
    final value = LocalConditions(
      userId: base.userId,
      epoch: base.epoch,
      baseVersion: base.baseVersion,
      catalogVersion: catalogVersion,
      status: status,
      entries: unique,
      pending: true,
    );
    final ticket = ++_generation;
    try {
      await _persist(value, ticket);
    } catch (_) {
      throw const MemberFailure(
        MemberFailureKind.unavailable,
        '기기에 저장하지 못했습니다. 입력을 유지했으니 다시 시도해주세요.',
      );
    }
    if (ticket != _generation || !authorized) return;
    state = value;
    onChange?.call();
  }

  Future<void> useServer() async {
    if (!authorized || _server == null) return;
    final ticket = ++_generation;
    await _persist(_server, ticket);
    if (ticket == _generation) state = _server;
  }

  Future<void> sync() => _sync ??= _syncNow().whenComplete(() => _sync = null);
  Future<void> _syncNow() async {
    final value = state;
    final ticket = _generation;
    if (value == null || !authorized || !value.pending || value.conflict) {
      return;
    }
    try {
      // Read before every retry: resolves an uncertain PUT without blind replay.
      final r = await auth.request('GET', '/api/v1/me/conditions');
      if (ticket != _generation || !authorized) return;
      final current = r.data as Map;
      if (current['consentEpoch'] != value.epoch) {
        await purge();
        return;
      }
      final entries = (current['conditionEntries'] as List?)
          ?.map((e) => EmergencyCondition.fromJson(e as Map))
          .toList();
      final server = entries == null
          ? null
          : LocalConditions(
              userId: value.userId,
              epoch: value.epoch,
              baseVersion: current['version'] as int,
              catalogVersion:
                  current['catalogVersion'] as String? ?? value.catalogVersion,
              status: current['status'] as String,
              entries: entries,
            );
      _server = server ?? _server;
      if (server != null && _same(value, server)) {
        await _commit(server, ticket);
        return;
      }
      if (current['version'] != value.baseVersion) {
        await _commit(value.changed(conflict: true), ticket);
        return;
      }
      final version = value.catalogVersion.isEmpty
          ? (await catalog.catalog()).version
          : value.catalogVersion;
      if (ticket != _generation || !authorized) return;
      final written = await auth.request(
        'PUT',
        '/api/v1/me/conditions',
        data: {
          'version': value.baseVersion,
          'consentEpoch': value.epoch,
          'status': value.status,
          'catalogVersion': version,
          'conditionEntries': value.entries.map((e) => e.toJson()).toList(),
        },
      );
      if (ticket != _generation || !authorized) return;
      final j = written.data as Map;
      final confirmed = LocalConditions(
        userId: value.userId,
        epoch: value.epoch,
        baseVersion: j['version'] as int,
        catalogVersion: j['catalogVersion'] as String? ?? version,
        status: j['status'] as String,
        entries: (j['conditionEntries'] as List)
            .map((e) => EmergencyCondition.fromJson(e as Map))
            .toList(),
      );
      _server = confirmed;
      await _commit(confirmed, ticket);
    } on AuthFailure {
      if (ticket == _generation) await purge();
    } on DioException catch (e) {
      final code = e.response?.data is Map ? e.response?.data['code'] : null;
      if (ticket != _generation) return;
      if (e.response?.statusCode == 401 ||
          code == 'HEALTH_CONSENT_REQUIRED' ||
          code == 'CONSENT_GENERATION_CHANGED') {
        await purge();
      } else if (e.response?.statusCode == 409 ||
          e.response?.statusCode == 400) {
        await _commit(value.changed(conflict: true), ticket);
      }
      // Connection failures leave the explicitly saved local record pending.
    }
  }

  Future<void> _commit(LocalConditions value, int ticket) async {
    await _persist(value, ticket);
    if (ticket == _generation && authorized && mounted) {
      state = value;
      onChange?.call();
    }
  }
}
