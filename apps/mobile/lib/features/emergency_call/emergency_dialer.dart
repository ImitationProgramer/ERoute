import 'package:flutter_riverpod/flutter_riverpod.dart';

enum DialResult { simulated, handedToSystem, unavailable }

abstract interface class EmergencyDialer {
  Future<DialResult> dial(String number);
}

class MockEmergencyDialer implements EmergencyDialer {
  final List<String> _requests = [];
  List<String> get requests => List.unmodifiable(_requests);
  @override
  Future<DialResult> dial(String number) async {
    if (number != '119') return DialResult.unavailable;
    _requests.add(number);
    return DialResult.simulated;
  }
}

/// Default composition is safe even in release or when a test forgets overrides.
final emergencyDialerProvider = Provider<EmergencyDialer>(
  (ref) => MockEmergencyDialer(),
);

class EmergencyDialerPolicy {
  final bool production, release, enabled, physicalDevice, automation;
  const EmergencyDialerPolicy({
    this.production = false,
    this.release = false,
    this.enabled = false,
    this.physicalDevice = false,
    this.automation = true,
  });
  bool get allowsSystem =>
      production && release && enabled && physicalDevice && !automation;
}
