import 'dart:ui' as ui;
import 'package:eroute_mobile/core/theme/eroute_theme.dart';
import 'package:eroute_mobile/features/disease_personalization/condition_catalog_widgets.dart';
import 'package:eroute_mobile/features/disease_personalization/disease_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/catalog_fixture.dart';

void main() {
  testWidgets(
    'server names/counts, inactive filtering, keyboard and selected semantics',
    (tester) async {
      final json = catalogJson();
      (json['categories'] as List).add({
        'id': 'FUTURE',
        'name': '서버의 새 분류',
        'sortOrder': 100,
      });
      (json['diseases'] as List).addAll([
        {
          'id': 'NEW',
          'canonicalName': '새 질환',
          'categoryId': 'FUTURE',
          'aliases': [],
          'active': true,
        },
        {
          'id': 'OLD',
          'canonicalName': '종료 질환',
          'categoryId': 'FUTURE',
          'aliases': [],
          'active': false,
        },
      ]);
      final catalog = DiseaseCatalog.fromJson(json);
      final semantics = tester.ensureSemantics();
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: ERouteTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) => ConditionCategoryGrid(
                  catalog: catalog,
                  selectedId: selected,
                  onSelected: (id) => setState(() => selected = id),
                  diseaseBuilder: (id) =>
                      Text(catalog.byId(id)!.name, key: ValueKey(id)),
                ),
              ),
            ),
          ),
        ),
      );
      final cards = find.byType(ConditionCategoryCard);
      expect(cards, findsNWidgets(catalog.categories.length));
      expect(
        tester.getTopLeft(cards.at(0)).dy,
        tester.getTopLeft(cards.at(1)).dy,
      );
      expect(tester.getSize(cards.first).height, greaterThanOrEqualTo(48));
      // Previous card was ~126dp at 100%; content-height target is ~102dp.
      expect(tester.getSize(cards.first).height, lessThanOrEqualTo(110));
      final firstName = find.text(catalog.categories.first.name).first;
      final chevron = find.descendant(
        of: cards.first,
        matching: find.byIcon(Icons.expand_more),
      );
      expect(
        (tester.getCenter(firstName).dy - tester.getCenter(chevron).dy).abs(),
        lessThan(2),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selected, catalog.categories.first.id);
      final data = tester.getSemantics(cards.first).getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isSelected, ui.Tristate.isTrue);
      final future = find.byKey(const ValueKey('category-FUTURE'));
      await tester.ensureVisible(future);
      await tester.tap(future);
      await tester.pumpAndSettle();
      expect(tester.widget<ConditionCategoryCard>(future).count, 1);
      expect(find.byKey(const ValueKey('NEW')), findsOneWidget);
      expect(find.byKey(const ValueKey('OLD')), findsNothing);
      expect(find.byKey(const ValueKey('D003')), findsNothing);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
}
