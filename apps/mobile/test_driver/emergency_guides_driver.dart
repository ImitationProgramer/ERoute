import 'dart:io';
import 'dart:convert';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  const directory = '../../docs/qa/emergency-guide-content-v1-2026-09-22';
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      final file = File('$directory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      return true;
    },
    responseDataCallback: (data) async {
      final summary = Map<String, dynamic>.from(data ?? {})
        ..remove('screenshots');
      await File(
        '$directory/android-results.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(summary));
    },
  );
}
