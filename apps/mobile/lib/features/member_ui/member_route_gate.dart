import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app_menu/app_session.dart';
import 'member_auth_screen.dart';
import 'member_widgets.dart';

class MemberRouteGate extends ConsumerWidget {
  final String destination;
  final Widget child;
  const MemberRouteGate({
    super.key,
    required this.destination,
    required this.child,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session.authenticated) {
      return KeyedSubtree(
        key: ValueKey('${session.userId}:${session.generation}'),
        child: child,
      );
    }
    if (session.phase == SessionPhase.restoring) {
      return const MemberScaffold(
        title: '로그인 상태 확인',
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return MemberAuthScreen(returnTo: destination);
  }
}
