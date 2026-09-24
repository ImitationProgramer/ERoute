import 'package:flutter/material.dart';
import '../../features/app_menu/emergency_drawer.dart';
import '../theme/eroute_tokens.dart';

class ERouteTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final bool showBack;
  final bool opaqueTopBar;
  final List<Widget> actions;
  final VoidCallback? openDrawer;
  const ERouteTopBar({
    super.key,
    this.title,
    this.showBack = false,
    this.opaqueTopBar = false,
    this.actions = const [],
    this.openDrawer,
  });
  @override
  Size get preferredSize => const Size.fromHeight(68);
  @override
  Widget build(BuildContext context) => AppBar(
    toolbarHeight: 68,
    backgroundColor: opaqueTopBar
        ? Theme.of(context).colorScheme.surface
        : Colors.transparent,
    surfaceTintColor: Colors.transparent,
    automaticallyImplyLeading: false,
    leadingWidth: showBack ? 104 : 60,
    leading: Row(
      children: [
        const SizedBox(width: 4),
        IconButton(
          tooltip: '메뉴 열기',
          onPressed: openDrawer ?? () => Scaffold.of(context).openDrawer(),
          icon: const Icon(Icons.menu_rounded),
        ),
        if (showBack)
          IconButton(
            tooltip: '뒤로 가기',
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
      ],
    ),
    title: title == null
        ? null
        : Text(title!, style: ERouteTypography.pageTitle),
    actions: [...actions, const SizedBox(width: 8)],
  );
}

class ERouteScaffold extends StatefulWidget {
  final Widget body;
  final String? title;
  final bool showBack;
  final bool opaqueTopBar;
  final List<Widget> actions;
  final Color? backgroundColor;
  const ERouteScaffold({
    super.key,
    required this.body,
    this.title,
    this.showBack = false,
    this.opaqueTopBar = false,
    this.actions = const [],
    this.backgroundColor,
  });
  @override
  State<ERouteScaffold> createState() => _ERouteScaffoldState();
}

class _ERouteScaffoldState extends State<ERouteScaffold> {
  final key = GlobalKey<ScaffoldState>();
  @override
  Widget build(BuildContext context) => Scaffold(
    key: key,
    backgroundColor: widget.backgroundColor,
    drawer: const EmergencyDrawer(),
    drawerScrimColor: const Color(0x66081729),
    appBar: ERouteTopBar(
      title: widget.title,
      showBack: widget.showBack,
      opaqueTopBar: widget.opaqueTopBar,
      actions: widget.actions,
      openDrawer: () => key.currentState?.openDrawer(),
    ),
    body: widget.body,
  );
}
