import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/eroute_theme.dart';
import '../core/theme/theme_controller.dart';
import 'router.dart';

class ERouteApp extends ConsumerWidget {
  const ERouteApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    title: 'ERoute',
    debugShowCheckedModeBanner: false,
    navigatorObservers: [appRouteObserver],
    theme: ERouteTheme.light(),
    darkTheme: ERouteTheme.dark(),
    themeMode: ref.watch(themeModeProvider),
    builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
      value: Theme.of(context).brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: child!,
    ),
    initialRoute: AppRoutes.landing,
    onGenerateRoute: buildAppRoute,
  );
}
