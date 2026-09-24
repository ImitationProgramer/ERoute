import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/eroute_tokens.dart';
import '../app_menu/app_session.dart';
import 'member_controller.dart';
import 'member_profile_screen.dart';
import 'member_auth_screen.dart';
import 'member_health_screens.dart' show openMemberPage;

abstract interface class MemberPrivacy {
  Future<void> sensitive(bool value);
  Future<void> allowDisplay();
}

class NativeMemberPrivacy implements MemberPrivacy {
  static const channel = MethodChannel('eroute/privacy');
  @override
  Future<void> sensitive(bool value) async {
    await channel.invokeMethod<void>('setSensitive', value);
  }

  @override
  Future<void> allowDisplay() async {
    await channel.invokeMethod<void>('allowDisplay');
  }
}

final memberPrivacyProvider = Provider<MemberPrivacy>(
  (ref) => NativeMemberPrivacy(),
);

class _PrivacyLeases {
  int count = 0;
}

final _privacyLeasesProvider = Provider((ref) => _PrivacyLeases());

/// One owner across every member route. Native protection is never disabled by
/// an editor disposing while another sensitive route is still visible.
class MemberSecurityScope extends ConsumerStatefulWidget {
  final Widget child;
  const MemberSecurityScope({super.key, required this.child});
  @override
  ConsumerState<MemberSecurityScope> createState() =>
      _MemberSecurityScopeState();
}

class _MemberSecurityScopeState extends ConsumerState<MemberSecurityScope>
    with WidgetsBindingObserver {
  Timer? timer;
  late MemberPrivacy privacy;
  late _PrivacyLeases leases;
  @override
  void initState() {
    super.initState();
    privacy = ref.read(memberPrivacyProvider);
    leases = ref.read(_privacyLeasesProvider);
    if (leases.count++ == 0) privacy.sensitive(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(sessionProvider).authenticated) {
        ref.read(memberControllerProvider.notifier).reload();
      }
    });
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(seconds: 10), (_) {
      ref.read(memberControllerProvider.notifier).pollConsent();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = ref.read(memberControllerProvider.notifier);
    c.foreground = state == AppLifecycleState.resumed;
    c.cover();
    if (c.foreground) {
      c.reload();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => privacy.allowDisplay(),
      );
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (--leases.count == 0) privacy.sensitive(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(memberControllerProvider);
    ref.listen(sessionProvider, (old, next) {
      if (old?.userId != next.userId ||
          old?.generation != next.generation ||
          !next.authenticated) {
        final controller = ref.read(memberControllerProvider.notifier);
        controller.cover(clear: true);
        if (next.authenticated) controller.reload();
      }
    });
    return widget.child;
  }
}

/// Wrap authored copy at spaces without changing stored medical text.
class MemberCopy extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const MemberCopy(this.text, {super.key, this.style});
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: text,
    child: ExcludeSemantics(
      child: Wrap(
        spacing: MediaQuery.textScalerOf(context).scale(4),
        runSpacing: 2,
        children: text
            .split(' ')
            .map((word) => Text(word, style: style))
            .toList(),
      ),
    ),
  );
}

class MemberScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget> actions;
  const MemberScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
  });
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return MemberSecurityScope(
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Theme.of(context).colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          systemOverlayStyle: dark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          actions: actions,
        ),
        body: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Decorative category colors only; never imply clinical severity or verification.
enum MemberTone { allergy, condition, medication, note }

(Color, Color) memberToneColors(BuildContext context, MemberTone tone) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (tone) {
    MemberTone.allergy =>
      dark
          ? (const Color(0xFF492C39), const Color(0xFFFFBBC4))
          : (const Color(0xFFFFEDF0), const Color(0xFFB63C54)),
    MemberTone.condition =>
      dark
          ? (const Color(0xFF373152), const Color(0xFFD0C4FF))
          : (const Color(0xFFF0EDFF), const Color(0xFF6550AF)),
    MemberTone.medication =>
      dark
          ? (const Color(0xFF44362C), const Color(0xFFFFCEA1))
          : (const Color(0xFFFFF2E5), const Color(0xFFA85B19)),
    MemberTone.note =>
      dark
          ? (const Color(0xFF223F45), const Color(0xFF99DDD8))
          : (const Color(0xFFE8F7F5), const Color(0xFF227973)),
  };
}

class MemberCategoryIcon extends StatelessWidget {
  final MemberTone tone;
  final IconData icon;
  const MemberCategoryIcon({super.key, required this.tone, required this.icon});
  @override
  Widget build(BuildContext context) {
    final (background, foreground) = memberToneColors(context, tone);
    return CircleAvatar(
      radius: 21,
      backgroundColor: background,
      foregroundColor: foreground,
      child: Icon(icon, size: 23),
    );
  }
}

ShapeBorder memberCardShape(BuildContext context) => RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(16),
  side: BorderSide(
    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .25),
  ),
);

/// A single quiet provenance line, instead of repeated large notices.
class MemberProvenance extends StatelessWidget {
  const MemberProvenance({super.key});
  @override
  Widget build(BuildContext context) => MemberCopy(
    '본인이 입력한 정보이며 현재 자동 전송되지 않습니다.',
    style: Theme.of(context).textTheme.bodySmall,
  );
}

class MemberPanel extends StatelessWidget {
  final Widget child;
  final Color? color;
  const MemberPanel({super.key, required this.child, this.color});
  @override
  Widget build(BuildContext context) => Card(
    color: color,
    elevation: 1,
    shadowColor: Colors.black.withValues(alpha: .10),
    surfaceTintColor: Colors.transparent,
    shape: memberCardShape(context),
    margin: EdgeInsets.zero,
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
}

class MemberNotice extends StatelessWidget {
  final String message;
  final bool error;
  const MemberNotice(this.message, {super.key, this.error = false});
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: MemberPanel(
      color: error
          ? Theme.of(context).colorScheme.errorContainer
          : context.eroute.softBlue,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(error ? Icons.info_outline : Icons.shield_outlined, size: 22),
          const SizedBox(width: 10),
          Expanded(child: MemberCopy(message)),
        ],
      ),
    ),
  );
}

class MemberBusyButton extends StatelessWidget {
  final bool busy;
  final VoidCallback? onPressed;
  final String label;
  const MemberBusyButton({
    super.key,
    required this.busy,
    required this.onPressed,
    required this.label,
  });
  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: busy ? null : onPressed,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Opacity(opacity: busy ? 0 : 1, child: Text(label)),
        if (busy)
          Semantics(
            label: '처리 중',
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
    ),
  );
}

Future<bool> memberConfirm(
  BuildContext context,
  String title,
  String text,
  String action, {
  String cancel = '취소',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(child: Text(text)),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

void memberFeedback(BuildContext context, String text) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));

/// Presentation feedback is supplied by the host; preview must label simulations.
final memberResultLabelProvider = Provider<String>((ref) => '저장되었습니다.');

class MemberGuard extends ConsumerWidget {
  final Widget child;
  final bool healthRequired;
  const MemberGuard({
    super.key,
    required this.child,
    this.healthRequired = true,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(memberControllerProvider);
    final visible =
        !v.covered && (!healthRequired || v.access?.granted == true);
    return Stack(
      children: [
        if (v.access != null && (!healthRequired || v.access!.granted))
          Offstage(
            offstage: !visible,
            child: ExcludeFocus(excluding: !visible, child: child),
          ),
        if (!visible)
          ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (v.loading) const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 16),
              MemberNotice(
                v.error ??
                    (v.access?.granted == false
                        ? '건강정보를 등록하려면 별도 동의가 필요합니다. 내 정보에서 건강정보 관리를 열어주세요.'
                        : '로그인과 건강정보 접근 상태를 확인해주세요.'),
                error: v.error != null,
              ),
              const SizedBox(height: 16),
              if (!v.loading)
                OutlinedButton(
                  onPressed: () =>
                      ref.read(memberControllerProvider.notifier).reload(),
                  child: const Text('다시 확인'),
                ),
              if (!v.loading && v.access?.granted == false)
                FilledButton(
                  onPressed: () =>
                      openMemberPage(context, const MemberConsentScreen()),
                  child: const Text('건강정보 동의 관리'),
                ),
              if (!v.loading && !ref.watch(sessionProvider).authenticated)
                FilledButton(
                  onPressed: () =>
                      openMemberPage(context, const MemberAuthScreen()),
                  child: const Text('로그인'),
                ),
            ],
          ),
      ],
    );
  }
}

/// Shares native privacy ownership without reading the member health snapshot.
class SensitiveDisplayScope extends ConsumerStatefulWidget {
  final bool enabled;
  final Widget child;
  const SensitiveDisplayScope({
    super.key,
    required this.enabled,
    required this.child,
  });
  @override
  ConsumerState<SensitiveDisplayScope> createState() =>
      _SensitiveDisplayScopeState();
}

class _SensitiveDisplayScopeState extends ConsumerState<SensitiveDisplayScope> {
  bool leased = false;
  late final _PrivacyLeases leases;
  late final MemberPrivacy privacy;
  void sync() {
    if (leased == widget.enabled) return;
    leased = widget.enabled;
    if (leased) {
      if (leases.count++ == 0) unawaited(privacy.sensitive(true));
    } else if (--leases.count == 0) {
      unawaited(privacy.sensitive(false));
    }
  }

  @override
  void initState() {
    super.initState();
    // A second scope may never call sensitive(true), but can be the last to
    // release. Resolve its owner now; WidgetRef is unavailable during dispose.
    leases = ref.read(_privacyLeasesProvider);
    privacy = ref.read(memberPrivacyProvider);
    sync();
  }

  @override
  void didUpdateWidget(covariant SensitiveDisplayScope old) {
    super.didUpdateWidget(old);
    sync();
  }

  @override
  void dispose() {
    if (leased && --leases.count == 0) unawaited(privacy.sensitive(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
