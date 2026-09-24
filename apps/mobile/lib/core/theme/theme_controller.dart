import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

abstract interface class ThemePolicy {
  ThemeMode resolve();
}

class SystemThemePolicy implements ThemePolicy {
  const SystemThemePolicy();
  @override
  ThemeMode resolve() => ThemeMode.system;
}
