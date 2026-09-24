import 'hospital_detail.dart';

class HospitalDetailNotFound implements Exception {
  final String hpid;
  const HospitalDetailNotFound(this.hpid);
}

enum HospitalDetailFailureKind {
  network,
  timeout,
  unavailable,
  invalidResponse,
}

class HospitalDetailFailure implements Exception {
  final HospitalDetailFailureKind kind;
  final int? statusCode;
  const HospitalDetailFailure(this.kind, {this.statusCode});
}

abstract interface class HospitalDetailRepository {
  Future<HospitalDetail> get(String hpid);
}
