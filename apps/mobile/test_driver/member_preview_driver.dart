import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      final file = File('build/qa/member-ui/device/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      // Driver callbacks receive screenshots after the test. A native screencap
      // here would repeatedly capture the final screen, not this named state.
      return true;
    },
  );
}
