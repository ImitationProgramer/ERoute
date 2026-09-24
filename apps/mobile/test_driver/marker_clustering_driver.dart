import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final file = File(
      '../../docs/qa/map-marker-clustering-2026-09-22/after/$name.png',
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    return true;
  },
);
