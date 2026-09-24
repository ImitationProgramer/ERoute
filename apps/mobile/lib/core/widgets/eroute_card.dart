import 'package:flutter/material.dart';
import '../theme/eroute_tokens.dart';

class ERouteCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool selected;
  const ERouteCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(ERouteSpacing.md),
    this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final decoration = BoxDecoration(
      color: selected ? context.eroute.softBlue : scheme.surface,
      borderRadius: BorderRadius.circular(ERouteRadius.card),
      border: Border.all(color: selected ? scheme.primary : scheme.outline),
    );
    final content = Padding(padding: padding, child: child);
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: decoration,
        child: onTap == null
            ? content
            : InkWell(
                borderRadius: BorderRadius.circular(ERouteRadius.card),
                onTap: onTap,
                child: content,
              ),
      ),
    );
  }
}

class ERouteSectionTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const ERouteSectionTitle(this.title, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(title, style: ERouteTypography.pageTitle)),
      ?trailing,
    ],
  );
}

class ERouteStatusBadge extends StatelessWidget {
  final String label;
  final bool warning;
  const ERouteStatusBadge(this.label, {super.key, this.warning = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: warning ? const Color(0xfffff3df) : context.eroute.softBlue,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: ERouteTypography.label.copyWith(
        color: warning
            ? ERouteColors.warning
            : Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
