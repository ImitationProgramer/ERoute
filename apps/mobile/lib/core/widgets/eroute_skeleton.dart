import 'package:flutter/material.dart';
import '../theme/eroute_tokens.dart';

/// Static, bounded placeholder: never implies progress after a request finishes.
class ERouteSkeleton extends StatelessWidget {
  final double width, height;
  final String label;
  const ERouteSkeleton({
    super.key,
    this.width = double.infinity,
    this.height = 20,
    this.label = '정보 불러오는 중',
  });

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.eroute.muted.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(ERouteSpacing.xxs),
          ),
        ),
      ),
    ),
  );
}
