import 'location_fix.dart';

abstract interface class LocationService {
  Future<LocationFix?> current();
}
