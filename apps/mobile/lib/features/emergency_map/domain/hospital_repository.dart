import 'hospital_summary.dart';

abstract interface class HospitalRepository {
  Future<MapPolicy> policy();
  Future<HospitalSearchResult> search(
    GeoPoint center,
    String source,
    GeoPoint? user,
    int? radius,
  );
}
