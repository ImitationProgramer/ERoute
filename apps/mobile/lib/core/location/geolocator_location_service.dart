import 'package:geolocator/geolocator.dart';
import 'location_service.dart';
import 'location_fix.dart';
import '../../features/emergency_map/domain/hospital_summary.dart';

class GeolocatorLocationService implements LocationService {
  @override
  Future<LocationFix?> current() => _current(requestPermission: true);

  /// SMS never requests permission or waits on a permission dialog.
  Future<LocationFix?> currentIfPermitted() =>
      _current(requestPermission: false);

  Future<LocationFix?> _current({required bool requestPermission}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && requestPermission) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return LocationFix(
        GeoPoint(p.latitude, p.longitude),
        accuracyMeters: p.accuracy.isFinite && p.accuracy >= 0
            ? p.accuracy
            : null,
        measuredAt: p.timestamp,
      );
    } catch (_) {
      return null;
    }
  }
}
