import 'package:flutter/material.dart';

abstract final class ERouteColors {
  static const backgroundLight = Color(0xfffafbfc);
  static const surfaceLight = Color(0xffffffff);
  static const backgroundDark = Color(0xff101b2d);
  static const surfaceDark = Color(0xff1a2940);
  static const primaryLight = Color(0xff244e86);
  static const primaryDark = Color(0xff9bc2ff);
  static const onPrimaryLight = Colors.white;
  static const onPrimaryDark = Color(0xff10243c);
  static const emergencyLight = Color(0xffc93645);
  static const emergencyDark = Color(0xffff7a85);
  static const onEmergencyLight = Colors.white;
  static const onEmergencyDark = Color(0xff3f0811);
  static const textLight = Color(0xff14263d);
  static const textDark = Color(0xfff1f5fb);
  static const mutedLight = Color(0xff5b6b80);
  static const mutedDark = Color(0xffb3c1d4);
  static const outlineLight = Color(0xffdce3ec);
  static const outlineDark = Color(0xff40516a);
  static const softBlueLight = Color(0xffeaf2ff);
  static const softBlueDark = Color(0xff243b5c);
  static const personalizationGoldLight = Color(0xff946600);
  static const personalizationGoldDark = Color(0xffffd36e);
  static const warning = Color(0xffa26412);
}

abstract final class ERouteSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

abstract final class ERouteRadius {
  static const control = 12.0;
  static const card = 16.0;
  static const sheet = 24.0;
}

abstract final class ERouteTypography {
  static const hero = TextStyle(
    fontSize: 28,
    height: 1.28,
    fontWeight: FontWeight.w700,
  );
  static const pageTitle = TextStyle(
    fontSize: 22,
    height: 1.3,
    fontWeight: FontWeight.w700,
  );
  static const hospitalName = TextStyle(
    fontSize: 18,
    height: 1.35,
    fontWeight: FontWeight.w700,
  );
  static const body = TextStyle(
    fontSize: 16,
    height: 1.55,
    fontWeight: FontWeight.w400,
  );
  static const label = TextStyle(
    fontSize: 13,
    height: 1.4,
    fontWeight: FontWeight.w500,
  );
  static const metric = TextStyle(
    fontSize: 26,
    height: 1.15,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

abstract final class ERouteShadows {
  static const raised = [
    BoxShadow(color: Color(0x160b2442), blurRadius: 20, offset: Offset(0, 6)),
  ];
  static const sheet = [
    BoxShadow(color: Color(0x220b2442), blurRadius: 28, offset: Offset(0, -5)),
  ];
}

@immutable
class ERouteSemanticColors extends ThemeExtension<ERouteSemanticColors> {
  final Color emergency;
  final Color onEmergency;
  final Color muted;
  final Color softBlue;
  const ERouteSemanticColors({
    required this.emergency,
    required this.onEmergency,
    required this.muted,
    required this.softBlue,
  });
  @override
  ERouteSemanticColors copyWith({
    Color? emergency,
    Color? onEmergency,
    Color? muted,
    Color? softBlue,
  }) => ERouteSemanticColors(
    emergency: emergency ?? this.emergency,
    onEmergency: onEmergency ?? this.onEmergency,
    muted: muted ?? this.muted,
    softBlue: softBlue ?? this.softBlue,
  );
  @override
  ERouteSemanticColors lerp(covariant ERouteSemanticColors? other, double t) =>
      other == null
      ? this
      : ERouteSemanticColors(
          emergency: Color.lerp(emergency, other.emergency, t)!,
          onEmergency: Color.lerp(onEmergency, other.onEmergency, t)!,
          muted: Color.lerp(muted, other.muted, t)!,
          softBlue: Color.lerp(softBlue, other.softBlue, t)!,
        );
}

extension ERouteThemeContext on BuildContext {
  ERouteSemanticColors get eroute {
    final theme = Theme.of(this);
    final configured = theme.extension<ERouteSemanticColors>();
    if (configured != null) return configured;
    final dark = theme.brightness == Brightness.dark;
    return ERouteSemanticColors(
      emergency: dark
          ? ERouteColors.emergencyDark
          : ERouteColors.emergencyLight,
      onEmergency: dark
          ? ERouteColors.onEmergencyDark
          : ERouteColors.onEmergencyLight,
      muted: dark ? ERouteColors.mutedDark : ERouteColors.mutedLight,
      softBlue: dark ? ERouteColors.softBlueDark : ERouteColors.softBlueLight,
    );
  }
}
