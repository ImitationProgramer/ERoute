import 'package:flutter/material.dart';
import '../../core/theme/eroute_tokens.dart';
import '../member_ui/member_widgets.dart';
import 'disease_catalog.dart';

import 'disease_category_visual.dart';

class ConditionCategoryCard extends StatelessWidget {
  final DiseaseCategory category;
  final int count;
  final bool selected;
  final VoidCallback? onPressed;
  const ConditionCategoryCard({
    super.key,
    required this.category,
    required this.count,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visual = DiseaseCategoryVisualRegistry.forCategory(category.id);
    final (background, foreground) = visual.colors(context);
    final shape = (memberCardShape(context) as RoundedRectangleBorder).copyWith(
      side: BorderSide(
        color: selected ? theme.colorScheme.primary : theme.colorScheme.outline,
        width: selected ? 1.5 : 1,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      expanded: selected,
      label: '${category.name}, $count개 질환',
      child: Material(
        color: selected ? context.eroute.softBlue : theme.colorScheme.surface,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ERouteSpacing.sm,
              vertical: ERouteSpacing.xs,
            ),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: CircleAvatar(
                      radius: 21,
                      backgroundColor: background,
                      foregroundColor: foreground,
                      child: Icon(visual.icon, size: 23),
                    ),
                  ),
                  const SizedBox(height: ERouteSpacing.xxs),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          category.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: ERouteSpacing.xxs),
                      Icon(
                        selected ? Icons.expand_less : Icons.expand_more,
                        color: selected
                            ? theme.colorScheme.primary
                            : context.eroute.muted,
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: ERouteSpacing.xxs),
                  Text(
                    '$count개 질환',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.eroute.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Natural-height rows keep Korean names readable without a fixed aspect ratio.
/// A single detail is inserted next to its owning card row, in reading order.
class ConditionCategoryGrid extends StatelessWidget {
  final DiseaseCatalog catalog;
  final String? selectedId;
  final ValueChanged<String>? onSelected;
  final Widget Function(String) diseaseBuilder;
  const ConditionCategoryGrid({
    super.key,
    required this.catalog,
    required this.selectedId,
    required this.onSelected,
    required this.diseaseBuilder,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns =
          constraints.maxWidth < 300 ||
              MediaQuery.textScalerOf(context).scale(14) >= 21
          ? 1
          : 2;
      final categories = catalog.categories;
      return Column(
        children: [
          for (var i = 0; i < categories.length; i += columns) ...[
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = i; j < i + columns; j++) ...[
                    if (j > i) const SizedBox(width: ERouteSpacing.sm),
                    Expanded(
                      child: j >= categories.length
                          ? const SizedBox()
                          : ConditionCategoryCard(
                              key: ValueKey('category-${categories[j].id}'),
                              category: categories[j],
                              count: catalog.diseases
                                  .where(
                                    (d) =>
                                        d.active &&
                                        d.category == categories[j].id,
                                  )
                                  .length,
                              selected: selectedId == categories[j].id,
                              onPressed: onSelected == null
                                  ? null
                                  : () => onSelected!(categories[j].id),
                            ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: ERouteSpacing.sm),
            for (final category in categories.skip(i).take(columns))
              if (category.id == selectedId)
                Padding(
                  padding: const EdgeInsets.only(bottom: ERouteSpacing.sm),
                  child: MemberPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            category.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        const SizedBox(height: ERouteSpacing.xxs),
                        Text(
                          '해당하는 질환을 모두 선택하세요.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: ERouteSpacing.xs),
                        if (!catalog.diseases.any(
                          (d) => d.active && d.category == category.id,
                        ))
                          const Text('현재 선택할 수 있는 질환이 없습니다.'),
                        for (final disease in catalog.diseases.where(
                          (d) => d.active && d.category == category.id,
                        ))
                          diseaseBuilder(disease.id),
                      ],
                    ),
                  ),
                ),
          ],
        ],
      );
    },
  );
}
