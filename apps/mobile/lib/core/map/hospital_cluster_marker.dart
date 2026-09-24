import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../theme/eroute_tokens.dart';
import 'hospital_marker_clusterer.dart';

/// Shared paint owner for native cluster icons and synthetic visual QA.
class HospitalClusterPainter extends CustomPainter {
  final int count;
  final bool dark;
  const HospitalClusterPainter(this.count, {required this.dark});
  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(2),
      const Radius.circular(24),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..color = dark ? ERouteColors.surfaceDark : ERouteColors.surfaceLight,
    );
    canvas.drawRRect(
      body,
      Paint()
        ..color = dark ? ERouteColors.primaryDark : ERouteColors.primaryLight
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final label = TextPainter(
      text: TextSpan(
        text: '$count',
        style: TextStyle(
          fontFamily: 'NotoSansKR',
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: dark ? ERouteColors.primaryDark : ERouteColors.primaryLight,
          fontFeatures: const [ui.FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(
      canvas,
      Offset((size.width - label.width) / 2, (size.height - label.height) / 2),
    );
    label.dispose();
  }

  @override
  bool shouldRepaint(HospitalClusterPainter old) =>
      count != old.count || dark != old.dark;
}

/// Transparent interaction/semantics counterpart to the native number icon.
/// Flutter owns focus/pressed ink and clipping below the existing map controls.
class HospitalClusterTarget extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  final bool pointerEnabled;
  const HospitalClusterTarget({
    super.key,
    required this.count,
    required this.onTap,
    this.pointerEnabled = true,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    label: '병원 $count개 묶음',
    hint: '확대해서 병원 보기',
    onTap: onTap,
    button: true,
    child: ExcludeSemantics(
      child: IgnorePointer(
        ignoring: !pointerEnabled,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: SizedBox.fromSize(size: HospitalClusterGeometry.size(count)),
          ),
        ),
      ),
    ),
  );
}
