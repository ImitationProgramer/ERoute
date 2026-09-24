import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'eroute_tokens.dart';

abstract final class ERouteTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final primary = dark ? ERouteColors.primaryDark : ERouteColors.primaryLight;
    final surface = dark ? ERouteColors.surfaceDark : ERouteColors.surfaceLight;
    final background = dark
        ? ERouteColors.backgroundDark
        : ERouteColors.backgroundLight;
    final text = dark ? ERouteColors.textDark : ERouteColors.textLight;
    final outline = dark ? ERouteColors.outlineDark : ERouteColors.outlineLight;
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      primary: primary,
      onPrimary: dark
          ? ERouteColors.onPrimaryDark
          : ERouteColors.onPrimaryLight,
      surface: surface,
      onSurface: text,
      outline: outline,
      error: dark ? ERouteColors.emergencyDark : ERouteColors.emergencyLight,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'NotoSansKR',
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
        fontFamily: 'NotoSansKR',
        bodyColor: text,
        displayColor: text,
      ),
      extensions: [
        ERouteSemanticColors(
          emergency: dark
              ? ERouteColors.emergencyDark
              : ERouteColors.emergencyLight,
          onEmergency: dark
              ? ERouteColors.onEmergencyDark
              : ERouteColors.onEmergencyLight,
          muted: dark ? ERouteColors.mutedDark : ERouteColors.mutedLight,
          softBlue: dark
              ? ERouteColors.softBlueDark
              : ERouteColors.softBlueLight,
        ),
      ],
      appBarTheme: AppBarTheme(
        systemOverlayStyle: dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      dividerTheme: DividerThemeData(color: outline),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ERouteRadius.card),
          side: BorderSide(color: outline),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ERouteRadius.control),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ERouteRadius.control),
          ),
        ),
      ),
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size.square(48)),
        ),
      ),
    );
  }
}
