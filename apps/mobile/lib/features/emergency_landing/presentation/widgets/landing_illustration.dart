import 'dart:math' as math;
import 'package:flutter/material.dart';

abstract final class LandingIllustrationAssets {
  static const light = 'assets/illustrations/emergency_landing_light.webp';
  static const dark = 'assets/illustrations/emergency_landing_dark.webp';
}

class LandingIllustration extends StatelessWidget {
  const LandingIllustration({super.key});

  static bool shouldShow({
    required double width,
    required double height,
    required Orientation orientation,
    required double textScale,
  }) =>
      width >= 360 &&
      height >= 600 &&
      orientation == Orientation.portrait &&
      textScale < 1.5;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final media = MediaQuery.of(context);
      final textScale = media.textScaler.scale(16) / 16;
      if (!shouldShow(
        width: constraints.maxWidth,
        height: constraints.maxHeight,
        orientation: media.orientation,
        textScale: textScale,
      )) {
        return const SizedBox.shrink();
      }
      final dark = Theme.of(context).brightness == Brightness.dark;
      final height = math.min(constraints.maxHeight * .18, 160.0);
      return Align(
        alignment: Alignment.bottomCenter,
        child: ExcludeSemantics(
          child: IgnorePointer(
            child: Opacity(
              key: const ValueKey('landing-illustration'),
              opacity: dark ? .22 : .30,
              child: Image.asset(
                dark
                    ? LandingIllustrationAssets.dark
                    : LandingIllustrationAssets.light,
                height: height,
                width: math.min(constraints.maxWidth, 720),
                fit: BoxFit.cover,
                alignment: Alignment.bottomCenter,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      );
    },
  );
}
