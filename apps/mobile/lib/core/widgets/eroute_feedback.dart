import 'package:flutter/material.dart';
import '../theme/eroute_tokens.dart';
import 'eroute_buttons.dart';

class ERouteEmptyState extends StatelessWidget {
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  const ERouteEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(ERouteSpacing.lg),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.location_searching_rounded,
          size: 40,
          color: context.eroute.muted,
        ),
        const SizedBox(height: ERouteSpacing.sm),
        Text(
          title,
          style: ERouteTypography.hospitalName,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: ERouteSpacing.xs),
        Text(
          message,
          style: ERouteTypography.label.copyWith(color: context.eroute.muted),
          textAlign: TextAlign.center,
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: ERouteSpacing.md),
          ERoutePrimaryButton(onPressed: onAction, label: Text(actionLabel!)),
        ],
      ],
    ),
  );
}

class ERouteErrorState extends ERouteEmptyState {
  const ERouteErrorState({
    super.key,
    required super.title,
    required super.message,
    super.actionLabel,
    super.onAction,
  });
}
