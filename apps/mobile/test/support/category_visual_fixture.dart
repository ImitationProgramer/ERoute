import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:eroute_mobile/features/disease_personalization/disease_catalog.dart';
import 'catalog_fixture.dart';

Widget withVisualCatalog(Widget child) => ProviderScope(
  overrides: [
    diseaseCatalogRepositoryProvider.overrideWithValue(
      FixtureCatalogRepository(),
    ),
  ],
  child: child,
);
