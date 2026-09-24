import '../../core/privacy_changes.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../app_menu/app_session.dart';
import '../auth/auth_repository.dart';
import '../member_ui/member_contract.dart';
import 'disease_reference.dart';
import 'map_disease_selection.dart';
import 'department_matcher.dart';

abstract interface class DiseaseDataRepository {
  Future<DiseaseReference> reference();
  Future<List<DepartmentSnapshot>> departments(List<String> hpids);
}

final diseaseDataRepositoryProvider =
    Provider.autoDispose<DiseaseDataRepository>((ref) {
      final dio = createApiClient();
      ref.onDispose(() => dio.close(force: true));
      return RemoteDiseaseDataRepository(dio);
    });

class RemoteDiseaseDataRepository implements DiseaseDataRepository {
  final Dio dio;
  RemoteDiseaseDataRepository(this.dio);
  @override
  Future<DiseaseReference> reference() async {
    final r = await dio.get('/api/v1/reference/disease-departments');
    return DiseaseReference.decode(Map<String, dynamic>.from(r.data as Map));
  }

  @override
  Future<List<DepartmentSnapshot>> departments(List<String> hpids) async {
    final ids = hpids.toSet().toList();
    if (ids.isEmpty) return [];
    // One retry if publication changes between chunks; never combine versions.
    for (var attempt = 0; attempt < 2; attempt++) {
      final result = <DepartmentSnapshot>[];
      String? version;
      var first = true, mixed = false;
      for (var offset = 0; offset < ids.length; offset += 100) {
        final chunk = ids.skip(offset).take(100).toList();
        final r = await dio.post(
          '/api/v1/emergency-hospitals/departments/query',
          data: {'hpids': chunk},
        );
        final j = Map<String, dynamic>.from(r.data as Map);
        if (!first && version != j['datasetVersion']) {
          mixed = true;
          break;
        }
        version = j['datasetVersion'];
        first = false;
        final batch = (j['hospitals'] as List)
            .map(
              (h) => DepartmentSnapshot.fromJson(Map<String, dynamic>.from(h)),
            )
            .toList();
        if (batch.length != chunk.length ||
            batch.map((h) => h.hpid).toSet().length != chunk.length ||
            batch.any(
              (h) => !chunk.contains(h.hpid) || h.datasetVersion != version,
            )) {
          throw const FormatException('병원 진료과 응답을 확인하지 못했습니다.');
        }
        result.addAll(batch);
      }
      if (!mixed) return result;
    }
    throw const FormatException('진료과 자료가 변경되었습니다. 다시 조회해주세요.');
  }
}

abstract interface class MapSelectionRepository {
  Future<MapSelectionSnapshot> read();
  Future<MapSelectionSnapshot> save(
    int version,
    int epoch,
    List<String> ids,
    DiseaseReference reference,
  );
  Future<MapSelectionSnapshot> clear(int version, int epoch);
}

final mapSelectionRepositoryProvider =
    Provider.autoDispose<MapSelectionRepository>(
      (ref) => RemoteMapSelectionRepository(
        ref.watch(authRepositoryProvider),
        onChange: () => ref.read(privacyChangeProvider.notifier).state++,
      ),
    );

class RemoteMapSelectionRepository implements MapSelectionRepository {
  final AuthRepository auth;
  final void Function()? onChange;
  RemoteMapSelectionRepository(this.auth, {this.onChange});
  Future<MapSelectionSnapshot> _request(
    String method, [
    Map<String, Object>? data,
    String path = '/api/v1/me/map-disease-selection',
  ]) async {
    if (method != 'GET') onChange?.call();
    try {
      final r = await auth.request(method, path, data: data);
      return MapSelectionSnapshot.fromJson(
        Map<String, dynamic>.from(r.data as Map),
      );
    } on AuthFailure {
      throw const MemberFailure(
        MemberFailureKind.session,
        '로그인 상태가 변경되었습니다. 다시 확인해주세요.',
      );
    } on DioException catch (e) {
      final code = e.response?.data is Map ? e.response?.data['code'] : null;
      if (code == 'HEALTH_CONSENT_REQUIRED' ||
          code == 'CONSENT_GENERATION_CHANGED') {
        throw const MemberFailure(
          MemberFailureKind.consent,
          '건강정보 동의 상태가 변경되었습니다.',
        );
      }
      if (e.response?.statusCode == 401) {
        throw const MemberFailure(
          MemberFailureKind.session,
          '로그인 상태를 다시 확인해주세요.',
        );
      }
      if (e.response?.statusCode == 409) {
        throw const MemberFailure(
          MemberFailureKind.conflict,
          '정보가 변경되었습니다. 최신 내용을 확인하고 다시 선택해주세요.',
        );
      }
      throw const MemberFailure(
        MemberFailureKind.unavailable,
        '선택 정보를 처리하지 못했습니다. 다시 시도해주세요.',
      );
    }
  }

  @override
  Future<MapSelectionSnapshot> read() => _request('GET');
  @override
  Future<MapSelectionSnapshot> save(
    int version,
    int epoch,
    List<String> ids,
    DiseaseReference reference,
  ) => _request('PUT', {
    'version': version,
    'consentEpoch': epoch,
    'diseaseIds': ids,
    'purpose': reference.purpose,
    'purposeVersion': reference.purposeVersion,
    'referenceVersion': reference.version,
    'confirmed': true,
  });
  @override
  Future<MapSelectionSnapshot> clear(int version, int epoch) =>
      _request('DELETE', {'version': version, 'consentEpoch': epoch});
}

abstract interface class ConditionsRepository {
  Future<void> save(
    int version,
    int epoch,
    String status,
    String text,
    List<String> ids,
    String catalogVersion,
  );
}

final conditionsRepositoryProvider = Provider.autoDispose<ConditionsRepository>(
  (ref) => RemoteConditionsRepository(
    ref.watch(authRepositoryProvider),
    () => ref.read(privacyChangeProvider.notifier).state++,
  ),
);

class RemoteConditionsRepository implements ConditionsRepository {
  final AuthRepository auth;
  final void Function()? onChange;
  RemoteConditionsRepository(this.auth, [this.onChange]);
  @override
  Future<void> save(
    int version,
    int epoch,
    String status,
    String text,
    List<String> ids,
    String catalogVersion,
  ) async {
    await RemoteMapSelectionRepository(
      auth,
      onChange: onChange,
    )._request('PUT', {
      'version': version,
      'consentEpoch': epoch,
      'status': status,
      'freeText': text,
      'diseaseIds': ids,
      'catalogVersion': catalogVersion,
    }, '/api/v1/me/conditions');
  }
}
