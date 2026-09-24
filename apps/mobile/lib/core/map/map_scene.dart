import '../location/location_fix.dart';
import '../../features/emergency_map/domain/hospital_summary.dart';

class SearchPresentationSnapshot {
  final GeoPoint center;
  final String source;
  final HospitalSearchResult result;
  final int revision;
  const SearchPresentationSnapshot({
    required this.center,
    required this.source,
    required this.result,
    required this.revision,
  });
}

class MapScene {
  final SearchPresentationSnapshot? search;
  final GeoPoint? initialCenter;
  final CoverageBounds? initialBounds;
  final LocationFix? user;
  final double? heading;
  final String? selectedHpid;
  const MapScene({
    this.search,
    this.initialCenter,
    this.initialBounds,
    this.user,
    this.heading,
    this.selectedHpid,
  });
}
