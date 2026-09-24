import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eroute_mobile/preview/member_preview_app.dart';
import 'package:eroute_mobile/preview/member_preview_repository.dart';
import 'package:eroute_mobile/features/member_ui/member_widgets.dart';

void main() {
  testWidgets(
    'preview restores session, owns toolbar overlay and applies scenario',
    (tester) async {
      await tester.pumpWidget(const MemberPreviewHost());
      await tester.pumpAndSettle();
      expect(find.text('내 응급정보'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('검수 도구 펼치기'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('미리보기 설정'));
      await tester.pumpAndSettle();
      expect(find.text('UI 미리보기 설정'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<PreviewPage>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('로그인').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('상태 적용'));
      await tester.pumpAndSettle();
      expect(find.text('다시 만나 반가워요'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is MemberCopy && w.text == 'UI 미리보기 · 가상 데이터',
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('미리보기 설정'), findsOneWidget);
      expect(find.bySemanticsLabel('UI 미리보기 · 가상 데이터'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('미리보기 설정'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<PreviewPage>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('알레르기 편집').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<PreviewScenario>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('저장 시 버전 충돌').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('상태 적용'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '충돌 검사 초안');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('저장'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('최신 내용 확인'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('최신 내용 확인'), findsOneWidget);
      await tester.ensureVisible(find.text('최신 내용 확인'));
      await tester.tap(find.text('최신 내용 확인'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('최신 내용 확인').last);
      await tester.pumpAndSettle();
      expect(find.text('내 응급정보'), findsOneWidget);
      await tester.tap(find.byTooltip('글자 크기 전환'));
      await tester.pumpAndSettle();
      expect(
        MediaQuery.textScalerOf(
          tester.element(find.bySemanticsLabel('저장한 건강정보를 확인하고 수정하세요.')),
        ).scale(10),
        20,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
