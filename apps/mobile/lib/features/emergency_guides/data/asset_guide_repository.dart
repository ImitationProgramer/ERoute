import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/guide_article.dart';

const guideReviewAvailable = kDebugMode && appFlavor == 'dev';
const guideAssetRoot = 'assets/content/emergency-guides/v1';

abstract interface class GuideRepository {
  Future<GuideCatalog> catalog();
  Future<GuideArticle?> article(String id, {bool review = false});
}

/// The bundle is the only content authority. No HTTP, session or health data.
class AssetGuideRepository implements GuideRepository {
  final AssetBundle bundle;
  final bool reviewEnabled;
  AssetGuideRepository(
    this.bundle, {
    this.reviewEnabled = guideReviewAvailable,
  });
  Future<GuideCatalog>? _catalog;
  @override
  Future<GuideCatalog> catalog() => _catalog ??= _loadCatalog();

  Future<GuideCatalog> _loadCatalog() async {
    try {
      final manifest =
          jsonDecode(await bundle.loadString('$guideAssetRoot/manifest.json'))
              as Map<String, dynamic>;
      if (manifest['schemaVersion'] != 1 ||
          jsonEncode(manifest['files']) !=
              jsonEncode(['emergency-actions.json', 'first-aid.json'])) {
        throw const FormatException('Invalid guide manifest');
      }
      final entries = <GuideEntry>[];
      final articles = <String, GuideArticle>{};
      final unavailable = <String>{};
      for (final file in manifest['files'] as List) {
        final rows =
            jsonDecode(await bundle.loadString('$guideAssetRoot/$file'))
                as List;
        for (final row in rows.cast<Map<String, dynamic>>()) {
          final entry = GuideEntry.fromJson(row);
          entries.add(entry);
          try {
            articles[entry.id] = GuideArticle.fromJson(row);
          } catch (_) {
            // Keep metadata/source/119 accessible; never render partial procedures.
            unavailable.add(entry.id);
          }
        }
      }
      for (final category in const {
        'EMERGENCY_ACTION': 4,
        'FIRST_AID': 13,
      }.entries) {
        if (entries.where((e) => e.category == category.key).length !=
                category.value ||
            (manifest['expectedCounts'] as Map)[category.key] !=
                category.value) {
          throw const FormatException('Invalid guide count');
        }
      }
      if (unavailable.isNotEmpty) _catalog = null;
      return GuideCatalog(
        entries: entries,
        articles: articles,
        unavailableIds: unavailable,
        disclaimer: manifest['commonDisclaimer'] as String,
      );
    } catch (_) {
      _catalog = null;
      rethrow;
    }
  }

  @override
  Future<GuideArticle?> article(String id, {bool review = false}) async {
    if (!validGuideId(id) || review && !reviewEnabled) {
      throw const FormatException('Guide unavailable');
    }
    final catalog = await this.catalog();
    final entry = catalog.find(id);
    return entry == null ? null : catalog.articles[entry.id];
  }
}

final guideRepositoryProvider = Provider<GuideRepository>(
  (ref) => AssetGuideRepository(rootBundle),
);
