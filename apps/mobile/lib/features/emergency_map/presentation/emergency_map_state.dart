import '../domain/hospital_summary.dart';
import '../../../core/location/location_fix.dart';
import '../../../core/map/map_scene.dart';

class EmergencyMapState {
  final MapPolicy? policy;
  final LocationFix? userFix;
  final GeoPoint? center, pendingCenter;
  final SearchPresentationSnapshot? snapshot;
  final int? requestedRadiusMeters;
  final String source;
  final String? selectedHpid, message, error;
  final bool loading, locating, userExploring;
  const EmergencyMapState({
    required this.policy,
    required this.userFix,
    required this.center,
    required this.pendingCenter,
    required this.snapshot,
    required this.requestedRadiusMeters,
    required this.source,
    required this.selectedHpid,
    required this.message,
    required this.error,
    required this.loading,
    required this.locating,
    required this.userExploring,
  });
}
