import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  const directory = '../../docs/qa/emergency-personalization-ios-2026-09-22';
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      final file = File('$directory/$name.png');
      await file.parent.create(recursive: true);
      if (name.startsWith('android-sms-composer')) {
        return file.exists(); // Actual native capture from the host watcher.
      }
      await file.writeAsBytes(bytes);
      return true;
    },
    responseDataCallback: (data) async {
      for (final entry in ((data?['canonicalHashes'] ?? {}) as Map).entries) {
        final nativeFile = File('$directory/${entry.key}.json');
        final native =
            jsonDecode(await nativeFile.readAsString()) as Map<String, dynamic>;
        native['bodyExactCanonicalMatch'] =
            native.remove('bodySha256') == entry.value;
        if (native['bodyExactCanonicalMatch'] != true) {
          throw StateError(
            'Native canonical body mismatch (synthetic values redacted)',
          );
        }
        await nativeFile.writeAsString(
          const JsonEncoder.withIndent('  ').convert(native),
        );
      }
      final summary = Map<String, dynamic>.from(data ?? {})
        ..remove('screenshots');
      await File(
        '$directory/${Platform.environment['EROUTE_QA_PLATFORM'] ?? 'android'}-integration-results.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(summary));
    },
  );
}
