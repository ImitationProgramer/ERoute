import 'package:eroute_mobile/core/theme/eroute_theme.dart';
import 'package:eroute_mobile/features/app_menu/app_session.dart';
import 'package:eroute_mobile/features/disease_personalization/condition_catalog_widgets.dart';
import 'package:eroute_mobile/features/disease_personalization/condition_local_store.dart';
import 'package:eroute_mobile/features/disease_personalization/disease_catalog.dart';
import 'package:eroute_mobile/features/member_ui/member_controller.dart';
import 'package:eroute_mobile/features/member_ui/member_contract.dart';
import 'package:eroute_mobile/features/member_ui/member_health_screens.dart';
import 'package:eroute_mobile/features/member_ui/member_widgets.dart';
import 'package:eroute_mobile/preview/member_preview_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../test/disease_selection_widget_test.dart'
    show FixtureConditionsRepository;
import '../test/support/catalog_fixture.dart';

// Test-only repositories; this entry point never contacts a health Backend.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android card browsing, selection, search, custom, pending and themes',
    (tester) async {
      await binding.convertFlutterSurfaceToImage();
      for (final dark in [false, true]) {
        for (final scale in [1.0, 2.0]) {
          final auth = PreviewAuthRepository();
          final repository = PreviewMemberRepository(
            auth,
            delay: Duration.zero,
          );
          final local = FixtureConditionsRepository(
            auth,
            MemoryConditionVault(),
          );
          final container = ProviderContainer(
            overrides: [
              authRepositoryProvider.overrideWithValue(auth),
              memberUiRepositoryProvider.overrideWithValue(repository),
              memberPrivacyProvider.overrideWithValue(PreviewPrivacy()),
              conditionLocalProvider.overrideWith((ref) => local),
              diseaseCatalogRepositoryProvider.overrideWithValue(
                FixtureCatalogRepository(),
              ),
            ],
          );
          await container.read(sessionControllerProvider.future);
          await container.read(memberControllerProvider.notifier).reload();
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: dark ? ERouteTheme.dark() : ERouteTheme.light(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: const MemberEmergencyScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          Future<void> reveal(Finder target) async {
            final scroll = find
                .descendant(
                  of: find.byType(ListView).last,
                  matching: find.byType(Scrollable),
                )
                .first;
            await tester.scrollUntilVisible(
              target,
              220,
              scrollable: scroll,
              maxScrolls: 80,
            );
            await Scrollable.ensureVisible(
              tester.element(target.last),
              alignment: .5,
            );
            await tester.pumpAndSettle();
          }

          Future<void> tap(Finder target) async {
            await reveal(target);
            await tester.tap(target.last);
            await tester.pumpAndSettle();
          }

          Future<void> top() async {
            tester
                .state<ScrollableState>(
                  find
                      .descendant(
                        of: find.byType(ListView).last,
                        matching: find.byType(Scrollable),
                      )
                      .first,
                )
                .position
                .jumpTo(0);
            await tester.pumpAndSettle();
          }

          Future<void> capture(String state) async {
            await binding.takeScreenshot(
              'condition-grid-${dark ? 'dark' : 'light'}-${scale.toInt()}x-$state',
            );
          }

          await tap(find.text('기저질환'));
          await capture('none');
          await tap(find.text('기저질환 있음'));
          await capture('browse');
          final quick = find.widgetWithText(FilterChip, '고혈압');
          await tap(quick);
          expect(tester.widget<FilterChip>(quick).selected, isTrue);
          await tap(quick);
          expect(tester.widget<FilterChip>(quick).selected, isFalse);
          await tap(find.byKey(const ValueKey('category-CAT_CARDIOVASCULAR')));
          expect(
            tester
                .widget<ConditionCategoryCard>(
                  find.byKey(const ValueKey('category-CAT_CARDIOVASCULAR')),
                )
                .selected,
            isTrue,
          );
          await tap(find.byKey(const ValueKey('condition-D003')));
          await top();
          await tap(find.byKey(const ValueKey('category-CAT_RESPIRATORY')));
          expect(find.byKey(const ValueKey('condition-D003')), findsNothing);
          await tap(find.byKey(const ValueKey('condition-D001')));
          await capture('detail');
          await top();
          final query = find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == '질환 검색',
          );
          await reveal(query);
          await tester.enterText(query, '고지혈증');
          await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
          await tester.pumpAndSettle();
          await tap(find.byKey(const ValueKey('condition-D018')));
          await capture('search');
          await tap(find.byTooltip('검색어 지우기'));
          expect(tester.widget<TextField>(query).controller!.text, isEmpty);
          expect(tester.widget<TextField>(query).focusNode!.hasFocus, isTrue);
          await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
          await tester.pumpAndSettle();
          await tap(find.text('목록에 없는 질환 직접 입력'));
          final custom = find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == '직접 입력한 질환',
          );
          await reveal(custom);
          await tester.enterText(custom, 'QA 직접 입력 질환');
          await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
          await tester.pumpAndSettle();
          await tap(find.text('직접 입력 질환 추가'));
          await tap(find.text('기저질환 저장'));
          expect(local.ids, containsAll(['D003', 'D001', 'D018']));
          expect(local.text, contains('QA 직접 입력 질환'));
          await tap(find.text('기저질환'));
          await reveal(find.byTooltip('QA 직접 입력 질환 제거'));
          await capture('selected');
          await tap(find.byTooltip('QA 직접 입력 질환 제거'));
          await reveal(
            find.byWidgetPredicate(
              (w) => w is MemberCopy && w.text == '기기에 저장됨 · 서버 동기화 대기 중',
            ),
          );
          await capture('pending');
          await top();
          await tap(find.text('기저질환 없음'));
          await tester.tap(find.widgetWithText(TextButton, '기록 지우기'));
          await tester.pumpAndSettle();
          await tap(find.text('기저질환 저장'));
          expect(local.status, 'NONE');
          expect(local.ids, isEmpty);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          container.dispose();
        }
      }
    },
  );
}
