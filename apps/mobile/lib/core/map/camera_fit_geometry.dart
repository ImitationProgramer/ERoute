import 'dart:math' as math;
import '../../features/emergency_map/domain/hospital_summary.dart';
import 'map_scene.dart';

const _earthRadius = 6371008.8;
double _rad(double degrees) => degrees * math.pi / 180;
double _deg(double radians) => radians * 180 / math.pi;
double distanceMeters(GeoPoint a, GeoPoint b) {
  final lat = _rad(b.latitude - a.latitude);
  final lon = _rad(b.longitude - a.longitude);
  final h =
      math.pow(math.sin(lat / 2), 2) +
      math.cos(_rad(a.latitude)) *
          math.cos(_rad(b.latitude)) *
          math.pow(math.sin(lon / 2), 2);
  return 2 * _earthRadius * math.asin(math.sqrt(h.clamp(0, 1)));
}

/// User GPS is deliberately not an input: only the completed search is fitted.
CoverageBounds fitBoundsFor(SearchPresentationSnapshot snapshot) {
  final center = snapshot.center;
  final angular = snapshot.result.radius / _earthRadius;
  final latitude = _rad(center.latitude);
  final south = (latitude - angular).clamp(-math.pi / 2, math.pi / 2);
  final north = (latitude + angular).clamp(-math.pi / 2, math.pi / 2);
  final lonDelta = south <= -math.pi / 2 || north >= math.pi / 2
      ? math.pi
      : math.asin((math.sin(angular) / math.cos(latitude)).clamp(-1, 1));
  var minLat = _deg(south), maxLat = _deg(north);
  var minLon = (center.longitude - _deg(lonDelta)).clamp(-180.0, 180.0);
  var maxLon = (center.longitude + _deg(lonDelta)).clamp(-180.0, 180.0);
  if (center.longitude - _deg(lonDelta) < -180 ||
      center.longitude + _deg(lonDelta) > 180) {
    minLon = -180;
    maxLon = 180;
  }
  for (final hospital in snapshot.result.hospitals) {
    minLat = math.min(minLat, hospital.location.latitude);
    maxLat = math.max(maxLat, hospital.location.latitude);
    minLon = math.min(minLon, hospital.location.longitude);
    maxLon = math.max(maxLon, hospital.location.longitude);
  }
  return CoverageBounds(GeoPoint(minLat, minLon), GeoPoint(maxLat, maxLon));
}
