import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'core/config/app_config.dart';
import 'features/emergency_call/emergency_dialer.dart';
import 'features/emergency_call/system_emergency_dialer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AppConfig.developmentAuth ||
      !['disabled', 'production'].contains(AppConfig.authEnvironment)) {
    throw StateError('Production authentication configuration conflict.');
  }
  if (AppConfig.authEnvironment == 'production' &&
      Uri.tryParse(AppConfig.apiBaseUrl)?.scheme != 'https') {
    throw StateError('Production password authentication requires HTTPS.');
  }
  // Production is deliberately opt-in; this entrypoint must never be used by QA.
  final dialer = await SystemEmergencyDialer.forProduction();
  runApp(
    ProviderScope(
      overrides: [emergencyDialerProvider.overrideWithValue(dialer)],
      child: const ERouteApp(),
    ),
  );
}
