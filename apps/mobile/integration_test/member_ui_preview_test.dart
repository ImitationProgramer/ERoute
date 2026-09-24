import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:eroute_mobile/main_ui_preview.dart' as app;
import 'package:eroute_mobile/preview/member_preview_app.dart';
import 'package:eroute_mobile/preview/member_preview_repository.dart';
import 'package:eroute_mobile/preview/member_product_repository.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('isolated member preview navigation, conflict and theme QA', (
    tester,
  ) async {
    app.main();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('UI 미리보기 · 가상 데이터'), findsOneWidget);
    expect(find.text('내 응급정보'), findsOneWidget);
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('member-health-light');
    if (find.byTooltip('검수 도구 펼치기').evaluate().isNotEmpty) {
      await tester.tap(find.byTooltip('검수 도구 펼치기'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('테마 전환'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('member-health-dark');
    await tester.tap(find.byTooltip('내 정보'));
    await tester.pumpAndSettle();
    expect(find.text('안녕하세요'), findsOneWidget);
    await binding.takeScreenshot('member-account-dark');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('테마 전환'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('알레르기').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '미저장 가상 알레르기 기록');
    await tester.pumpAndSettle();
    await binding.takeScreenshot('member-editor-keyboard');
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('변경사항을 버릴까요?'), findsOneWidget);
    await binding.takeScreenshot('member-unsaved-dialog');
    await tester.tap(find.text('계속 편집'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('저장'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('미저장 가상 알레르기 기록'), findsOneWidget);
    await tester.tap(find.byTooltip('검수 도구 접기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('복용약').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('복용약 추가'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('product-search-initial');
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '가상해봄');
    await tester.pumpAndSettle();
    await binding.takeScreenshot('product-search-keyboard');
    await tester.tap(find.text('검색'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('product-results');
    await tester.tap(find.text('200 mg · 정제'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('product-confirmation-missing');
    await tester.scrollUntilVisible(
      find.text('선택 취소 · 검색으로'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('선택 취소 · 검색으로'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('100 mg · 캡슐'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('복용 메모 · 등록으로'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('복용 메모 · 등록으로'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '개인 복용 메모 검수');
    await tester.pumpAndSettle();
    await binding.takeScreenshot('product-note-keyboard');
    await tester.tap(find.text('등록'));
    await tester.pumpAndSettle();
    expect(find.text('복용약'), findsOneWidget);
    expect(find.text('가상해봄'), findsOneWidget);
    await binding.takeScreenshot('product-registered');
    final preview = tester.widget<MemberPreviewApp>(
      find.byType(MemberPreviewApp),
    );
    await tester.scrollUntilVisible(
      find.text('복용약 추가'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('복용약 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '없는이름');
    await tester.pumpAndSettle();
    await tester.tap(find.text('검색'));
    await tester.pumpAndSettle();
    expect(find.text('검색 결과가 없어요.'), findsOneWidget);
    await binding.takeScreenshot('product-no-results');
    preview.products.scenario = PreviewProductScenario.failure;
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '가상해봄');
    await tester.pumpAndSettle();
    await tester.tap(find.text('검색'));
    await tester.pumpAndSettle();
    expect(find.text('다시 검색'), findsOneWidget);
    await binding.takeScreenshot('product-search-failure');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '가상해봄',
    );
    preview.products.scenario = PreviewProductScenario.standard;
    await tester.tap(find.text('다시 검색'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('100 mg · 정제'), findsOneWidget);
    await tester.tap(find.text('100 mg · 정제'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('선택 대신 직접 입력'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('선택 대신 직접 입력'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('medication-manual-input');
    await tester.enterText(find.byType(TextFormField).first, '직접 입력한 가상 약');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, '검수용 직접 입력 메모');
    await tester.pumpAndSettle();
    preview.repository.scenario = PreviewScenario.saveFailure;
    await tester.tap(find.text('등록'));
    await tester.pumpAndSettle();
    expect(find.text('검수용 직접 입력 메모'), findsOneWidget);
    preview.repository.scenario = PreviewScenario.saved;
    await tester.tap(find.text('등록'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(preview.repository.data.medications.length, 3);
    // Verify an existing manual record can be edited and deleted.
    await tester.tap(find.text('편집').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, '기존 수동 기록 편집 검수');
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제').first);
    await tester.pumpAndSettle();
    await binding.takeScreenshot('medication-delete-confirmation');
    await tester.tap(find.widgetWithText(TextButton, '삭제').last);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(preview.repository.data.medications.length, 2);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('내 정보'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('member-account-light');
    await tester.scrollUntilVisible(
      find.text('건강정보 동의 및 삭제'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('건강정보 동의 및 삭제'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.widgetWithText(OutlinedButton, '응급 기록 삭제'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.widgetWithText(OutlinedButton, '응급 기록 삭제'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('emergency-delete-confirmation');
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.widgetWithText(OutlinedButton, '동의 철회 및 삭제'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.widgetWithText(OutlinedButton, '동의 철회 및 삭제'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('withdrawal-delete-confirmation');
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('검수 도구 펼치기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('미리보기 설정'));
    await tester.pumpAndSettle();
    expect(find.text('UI 미리보기 설정'), findsOneWidget);
    await binding.takeScreenshot('member-preview-controls');
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('글자 크기 전환'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await binding.takeScreenshot('member-health-large-text');
    await tester.pumpWidget(const SizedBox());
  });
}
