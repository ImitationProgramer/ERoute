import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'emergency_dialer.dart';

/// Only the production composition may create this implementation.
/// Native code independently rechecks build and device constraints.
class SystemEmergencyDialer implements EmergencyDialer {
  static const _channel = MethodChannel('eroute/emergency_dialer');
  final EmergencyDialerPolicy _policy;
  SystemEmergencyDialer._(this._policy);

  static void _rejectTestEnvironment() {
    if (Platform.environment.containsKey('FLUTTER_TEST') ||
        Platform.environment.containsKey('CI') ||
        const bool.fromEnvironment('EROUTE_TEST_HARNESS')) {
      throw StateError(
        'SystemEmergencyDialer is forbidden in tests/automation',
      );
    }
  }

  static Future<EmergencyDialer> forProduction() async {
    _rejectTestEnvironment();
    if (const bool.fromEnvironment('EROUTE_AUTOMATION', defaultValue: true) ||
        !kReleaseMode ||
        appFlavor != 'production' ||
        !const bool.fromEnvironment('ENABLE_SYSTEM_EMERGENCY_DIALER')) {
      return MockEmergencyDialer();
    }
    try {
      final allowed =
          await _channel.invokeMethod<bool>('isSystemDialerAllowed') ?? false;
      final policy = EmergencyDialerPolicy(
        production: true,
        release: true,
        enabled: true,
        physicalDevice: allowed,
        automation: false,
      );
      return policy.allowsSystem
          ? SystemEmergencyDialer._(policy)
          : MockEmergencyDialer();
    } catch (_) {
      return MockEmergencyDialer();
    }
  }

  @override
  Future<DialResult> dial(String number) async {
    _rejectTestEnvironment();
    if (!_policy.allowsSystem || number != '119') return DialResult.unavailable;
    try {
      return await _channel.invokeMethod<bool>('openEmergencyDialScreen') ==
              true
          ? DialResult.handedToSystem
          : DialResult.unavailable;
    } catch (_) {
      return DialResult.unavailable;
    }
  }
}
