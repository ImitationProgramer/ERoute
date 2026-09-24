import 'package:flutter/material.dart';
import '../../core/theme/eroute_tokens.dart';
import '../member_ui/member_widgets.dart' show MemberTone, memberToneColors;
import 'disease_catalog.dart';

/// Recognition only: never determines membership, eligibility or clinical matches.
class DiseaseCategoryVisual {
  final IconData icon;
  final MemberTone? tone;
  final bool neutral;
  const DiseaseCategoryVisual(this.icon, this.tone, {this.neutral = false});

  (Color, Color) colors(BuildContext context) {
    if (tone != null) return memberToneColors(context, tone!);
    final scheme = Theme.of(context).colorScheme;
    return neutral
        ? (scheme.surfaceContainerHighest, scheme.onSurfaceVariant)
        : (context.eroute.softBlue, scheme.primary);
  }
}

/// The original fourteen condition-card visuals, shared without new assets.
abstract final class DiseaseCategoryVisualRegistry {
  static const unknown = DiseaseCategoryVisual(
    Icons.medical_services_outlined,
    null,
    neutral: true,
  );
  static const multiple = DiseaseCategoryVisual(
    Icons.health_and_safety_outlined,
    null,
    neutral: true,
  );

  static DiseaseCategoryVisual forCategory(String? categoryId) =>
      switch (categoryId) {
        'CAT_CARDIOVASCULAR' => const DiseaseCategoryVisual(
          Icons.favorite_border,
          MemberTone.allergy,
        ),
        'CAT_RESPIRATORY' => const DiseaseCategoryVisual(Icons.air, null),
        'CAT_ENDOCRINE_METABOLIC' => const DiseaseCategoryVisual(
          Icons.science_outlined,
          MemberTone.medication,
        ),
        'CAT_RENAL' => const DiseaseCategoryVisual(
          Icons.water_drop_outlined,
          MemberTone.note,
        ),
        'CAT_GI_LIVER' => const DiseaseCategoryVisual(
          Icons.restaurant_outlined,
          MemberTone.medication,
        ),
        'CAT_RHEUM_IMMUNE' => const DiseaseCategoryVisual(
          Icons.shield_outlined,
          MemberTone.condition,
        ),
        'CAT_NEURO' => const DiseaseCategoryVisual(
          Icons.psychology_outlined,
          MemberTone.condition,
        ),
        'CAT_MENTAL' => const DiseaseCategoryVisual(
          Icons.self_improvement,
          MemberTone.note,
        ),
        'CAT_DERM_ALLERGY' => const DiseaseCategoryVisual(
          Icons.healing_outlined,
          MemberTone.allergy,
        ),
        'CAT_ENT' => const DiseaseCategoryVisual(Icons.hearing_outlined, null),
        'CAT_OPHTHALMOLOGY' => const DiseaseCategoryVisual(
          Icons.visibility_outlined,
          null,
        ),
        'CAT_UROLOGY' => const DiseaseCategoryVisual(
          Icons.medical_services_outlined,
          MemberTone.note,
        ),
        'CAT_OBGYN' => const DiseaseCategoryVisual(
          Icons.female,
          MemberTone.allergy,
        ),
        'CAT_MSK_REHAB' => const DiseaseCategoryVisual(
          Icons.accessibility_new,
          MemberTone.medication,
        ),
        _ => unknown,
      };

  /// Call only with existing eligible STANDARD IDs. Unknown/incomplete metadata
  /// never borrows the first known disease's category. Inactive IDs can still be
  /// resolved; eligibility remains entirely with the existing personalization gate.
  static DiseaseCategoryVisual forDiseases(
    DiseaseCatalog? catalog,
    Iterable<String> diseaseIds,
  ) {
    final ids = diseaseIds.toSet();
    if (catalog == null || ids.isEmpty) return unknown;
    final categories = <String>{};
    for (final id in ids) {
      final category = catalog.byId(id)?.category;
      if (category == null) return unknown;
      categories.add(category);
    }
    return categories.length == 1 ? forCategory(categories.single) : multiple;
  }
}
