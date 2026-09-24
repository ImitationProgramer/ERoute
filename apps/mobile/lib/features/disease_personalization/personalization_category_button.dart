import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'disease_catalog.dart';
import 'disease_category_visual.dart';

/// Public metadata only; shared by all visible tags, never keyed by private IDs.
/// A catalog failure changes decoration to neutral, not personalization authority.
final personalizationVisualCatalogProvider =
    FutureProvider.autoDispose<DiseaseCatalog>(
      (ref) => ref.watch(diseaseCatalogRepositoryProvider).catalog(),
    );

/// Shared category decoration for the existing context and hospital reason buttons.
/// The caller retains text, interaction and the lifetime of eligible STANDARD IDs.
class PersonalizationCategoryButton extends ConsumerWidget {
  final Iterable<String> diseaseIds;
  final String label;
  final VoidCallback onPressed;
  final ButtonStyle? style;
  const PersonalizationCategoryButton({
    super.key,
    required this.diseaseIds,
    required this.label,
    required this.onPressed,
    this.style,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(personalizationVisualCatalogProvider).valueOrNull;
    final visual = DiseaseCategoryVisualRegistry.forDiseases(
      catalog,
      diseaseIds,
    );
    final (background, foreground) = visual.colors(context);
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(visual.icon, size: 18),
      style: TextButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        minimumSize: const Size(48, 48),
      ).merge(style),
      label: Text(label),
    );
  }
}
