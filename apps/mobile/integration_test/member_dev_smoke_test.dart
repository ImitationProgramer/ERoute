import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:eroute_mobile/main.dart' as app;
import 'package:eroute_mobile/features/member_ui/member_auth_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('normal dev launches password routes without preview', (
    tester,
  ) async {
    await app.main();
    await tester.pumpAndSettle();
    expect(find.text('UI 미리보기 · 가상 데이터'), findsNothing);
    await tester.tap(find.byTooltip('메뉴 열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('로그인').first);
    await tester.pumpAndSettle();
    expect(find.byType(MemberAuthScreen), findsOneWidget);
    expect(find.text('UI 미리보기 · 가상 데이터'), findsNothing);
    expect(find.text('다시 만나 반가워요'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
