import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

enum HospitalActionAvailability { available, unavailable }

abstract interface class HospitalContactLauncher {
  HospitalActionAvailability get availability;
  Future<bool> openDialScreen(String phoneNumber);
}

abstract interface class HospitalNavigationLauncher {
  HospitalActionAvailability get availability;
  Future<HospitalNavigationResult> openNavigation(
    double? latitude,
    double? longitude,
    String hospitalName,
  );
  Future<bool> openStore();
}

enum HospitalNavigationResult { opened, notInstalled, invalidLocation, failed }

// NAVER's documented coordinate coverage for navigation destinations.
bool validHospitalNavigationLocation(double? latitude, double? longitude) =>
    latitude != null &&
    longitude != null &&
    latitude.isFinite &&
    longitude.isFinite &&
    latitude >= 31.43 &&
    latitude <= 44.35 &&
    longitude >= 122.37 &&
    longitude <= 132.0;

Uri? hospitalNavigationUri({
  required double? latitude,
  required double? longitude,
  required String hospitalName,
  required String appIdentifier,
}) {
  if (!validHospitalNavigationLocation(latitude, longitude) ||
      appIdentifier.trim().isEmpty) {
    return null;
  }
  final parameters = {
    'dlat': latitude.toString(),
    'dlng': longitude.toString(),
    'dname': hospitalName,
    'appname': appIdentifier,
  };
  // Non-HTTP schemes require percent-encoded spaces, not form-encoded '+'.
  return Uri(
    scheme: 'nmap',
    host: 'navigation',
    query: parameters.entries
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
        )
        .join('&'),
  );
}

class SystemHospitalNavigationLauncher implements HospitalNavigationLauncher {
  const SystemHospitalNavigationLauncher();

  @override
  HospitalActionAvailability get availability =>
      !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)
      ? HospitalActionAvailability.available
      : HospitalActionAvailability.unavailable;

  @override
  Future<HospitalNavigationResult> openNavigation(
    double? latitude,
    double? longitude,
    String hospitalName,
  ) async {
    if (!validHospitalNavigationLocation(latitude, longitude)) {
      return HospitalNavigationResult.invalidLocation;
    }
    if (availability != HospitalActionAvailability.available) {
      return HospitalNavigationResult.failed;
    }
    try {
      final identity = await PackageInfo.fromPlatform();
      final uri = hospitalNavigationUri(
        latitude: latitude,
        longitude: longitude,
        hospitalName: hospitalName,
        appIdentifier: identity.packageName,
      );
      if (uri == null) return HospitalNavigationResult.failed;
      if (!await canLaunchUrl(uri)) {
        return HospitalNavigationResult.notInstalled;
      }
      return await launchUrl(uri, mode: LaunchMode.externalApplication)
          ? HospitalNavigationResult.opened
          : HospitalNavigationResult.failed;
    } catch (_) {
      return HospitalNavigationResult.failed;
    }
  }

  @override
  Future<bool> openStore() async {
    if (availability != HospitalActionAvailability.available) return false;
    final uri = defaultTargetPlatform == TargetPlatform.android
        ? Uri.https('play.google.com', '/store/apps/details', {
            'id': 'com.nhn.android.nmap',
          })
        : Uri.https('apps.apple.com', '/kr/app/id311867728');
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}

final hospitalNavigationLauncherProvider = Provider<HospitalNavigationLauncher>(
  (ref) => const SystemHospitalNavigationLauncher(),
);

class UnavailableHospitalContactLauncher implements HospitalContactLauncher {
  const UnavailableHospitalContactLauncher();
  @override
  HospitalActionAvailability get availability =>
      HospitalActionAvailability.unavailable;
  @override
  Future<bool> openDialScreen(String phoneNumber) async => false;
}

class UnavailableHospitalNavigationLauncher
    implements HospitalNavigationLauncher {
  const UnavailableHospitalNavigationLauncher();
  @override
  HospitalActionAvailability get availability =>
      HospitalActionAvailability.unavailable;
  @override
  Future<HospitalNavigationResult> openNavigation(
    double? latitude,
    double? longitude,
    String hospitalName,
  ) async => HospitalNavigationResult.failed;
  @override
  Future<bool> openStore() async => false;
}

String? normalizeHospitalDialNumber(String rawValue) {
  final raw = rawValue.trim();
  if (raw.isEmpty || !RegExp(r'^[0-9+()\-\s]+$').hasMatch(raw)) return null;
  final normalized = raw.replaceAll(RegExp(r'[()\-\s]'), '');
  if (!RegExp(r'^\+?[0-9]{3,}$').hasMatch(normalized)) return null;
  final digits = normalized.replaceFirst(RegExp(r'^\+'), '');
  if (digits == '119' || digits == '112') return null;
  return normalized;
}

class SystemHospitalContactLauncher implements HospitalContactLauncher {
  const SystemHospitalContactLauncher();
  @override
  HospitalActionAvailability get availability =>
      HospitalActionAvailability.available;
  @override
  Future<bool> openDialScreen(String phoneNumber) async {
    final normalized = normalizeHospitalDialNumber(phoneNumber);
    if (normalized == null) return false;
    try {
      return await launchUrl(
        Uri(scheme: 'tel', path: normalized),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }
}

final hospitalContactLauncherProvider = Provider<HospitalContactLauncher>(
  (ref) => const SystemHospitalContactLauncher(),
);
