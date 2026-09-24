import 'package:dio/dio.dart';
import '../domain/hospital_detail.dart';
import '../domain/hospital_detail_repository.dart';

class RemoteHospitalDetailRepository implements HospitalDetailRepository {
  final Dio _client;
  const RemoteHospitalDetailRepository(this._client);
  @override
  Future<HospitalDetail> get(String hpid) async {
    try {
      final response = await _client.get(
        '/api/v1/emergency-hospitals/${Uri.encodeComponent(hpid)}',
      );
      if (response.statusCode != 200 ||
          response.data is! Map<String, dynamic>) {
        throw const HospitalDetailFailure(
          HospitalDetailFailureKind.invalidResponse,
        );
      }
      final detail = HospitalDetail.fromJson(response.data);
      if (detail.hpid != hpid) {
        throw const HospitalDetailFailure(
          HospitalDetailFailureKind.invalidResponse,
        );
      }
      return detail;
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) throw HospitalDetailNotFound(hpid);
      throw HospitalDetailFailure(switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout => HospitalDetailFailureKind.timeout,
        DioExceptionType.badResponse => HospitalDetailFailureKind.unavailable,
        _ =>
          error.error is FormatException
              ? HospitalDetailFailureKind.invalidResponse
              : HospitalDetailFailureKind.network,
      }, statusCode: error.response?.statusCode);
    } on FormatException {
      throw const HospitalDetailFailure(
        HospitalDetailFailureKind.invalidResponse,
      );
    } on TypeError {
      throw const HospitalDetailFailure(
        HospitalDetailFailureKind.invalidResponse,
      );
    }
  }
}
