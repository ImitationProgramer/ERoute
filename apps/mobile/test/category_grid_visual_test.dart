import 'dart:io';
import 'dart:ui' as ui;
import 'package:eroute_mobile/core/theme/eroute_theme.dart';
import 'package:eroute_mobile/features/disease_personalization/condition_catalog_widgets.dart';
import 'package:eroute_mobile/features/disease_personalization/disease_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/catalog_fixture.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'NotoSansKR',
    )..addFont(rootBundle.load('assets/fonts/NotoSansKR.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('all 14 category grid visuals 320dp dark=$dark scale=$scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final key = GlobalKey();
        final catalog = DiseaseCatalog.fromJson(catalogJson());
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? ERouteTheme.dark() : ERouteTheme.light(),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: RepaintBoundary(
                    key: key,
                    child: ColoredBox(
                      color: dark
                          ? ERouteTheme.dark().colorScheme.surface
                          : ERouteTheme.light().colorScheme.surface,
                      child: ConditionCategoryGrid(
                        catalog: catalog,
                        selectedId: 'CAT_RESPIRATORY',
                        onSelected: (_) {},
                        diseaseBuilder: (_) => const SizedBox(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final cards = find.byType(ConditionCategoryCard);
        expect(cards, findsNWidgets(14));
        expect(
          tester.getTopLeft(cards.at(1)).dy,
          scale == 1
              ? tester.getTopLeft(cards.first).dy
              : greaterThan(tester.getTopLeft(cards.first).dy),
        );
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          const phase = String.fromEnvironment(
            'CATEGORY_VISUAL_PHASE',
            defaultValue: 'after',
          );
          final file = File(
            'build/qa/category-visual/$phase/grid-${dark ? 'dark' : 'light'}-${scale}x.png',
          );
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      });
    }
  }
}
