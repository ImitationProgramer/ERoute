import '../../features/emergency_map/domain/hospital_summary.dart';

class LocationFix {
  final GeoPoint point;
  final double? accuracyMeters;
  final DateTime measuredAt;
  const LocationFix(
    this.point, {
    this.accuracyMeters,
    required this.measuredAt,
  });
}
