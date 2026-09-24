import 'package:dio/dio.dart';
import '../domain/hospital_repository.dart';
import '../domain/hospital_summary.dart';

class RemoteHospitalRepository implements HospitalRepository {
  final Dio _client;
  RemoteHospitalRepository(this._client);
  @override
  Future<MapPolicy> policy() async =>
      MapPolicy.fromJson((await _client.get('/api/v1/map-config')).data);
  @override
  Future<HospitalSearchResult> search(
    GeoPoint center,
    String source,
    GeoPoint? user,
    int? radius,
  ) async => HospitalSearchResult.fromJson(
    (await _client.post(
      '/api/v1/emergency-hospitals/search',
      data: {
        'center': center.toJson(),
        'centerSource': source,
        if (user != null) 'userLocation': user.toJson(),
        'radiusMeters': ?radius,
      },
    )).data,
  );
}
