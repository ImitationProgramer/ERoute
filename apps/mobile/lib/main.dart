import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'core/config/app_config.dart';
import 'package:flutter/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AppConfig.developmentAuth &&
      (!['local', 'test'].contains(AppConfig.authEnvironment) ||
          appFlavor != 'dev')) {
    throw StateError(
      'Development authentication requires an explicit dev flavor and local/test environment.',
    );
  }
  runApp(const ProviderScope(child: ERouteApp()));
}
