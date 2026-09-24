import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../test/hospital_personalization_flow_test.dart'
    show exerciseHospitalFlow;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android home, login, health, per-disease consent and unchanged hospital results',
    (tester) async {
      await binding.convertFlutterSurfaceToImage();
      for (final dark in [false, true]) {
        for (final scale in [1.0, 2.0]) {
          await exerciseHospitalFlow(
            tester,
            dark: dark,
            scale: scale,
            capture: (name) async {
              await binding.takeScreenshot('health-hospital-$name');
            },
          );
        }
      }
    },
  );
}
