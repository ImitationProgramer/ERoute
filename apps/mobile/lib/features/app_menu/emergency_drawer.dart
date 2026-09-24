import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/router.dart';
import '../../core/theme/eroute_tokens.dart';
import '../emergency_call/emergency_call_coordinator.dart';
import '../emergency_call/emergency_call_state.dart';
import 'app_session.dart';

class EmergencyDrawer extends ConsumerWidget {
  const EmergencyDrawer({super.key});

  void _open(BuildContext context, String route) {
    final navigatorContext = Navigator.of(context).context;
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigatorContext.mounted) pushAppRoute(navigatorContext, route);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final callStatus = ref.watch(emergencyCallStateProvider);
    final scheme = Theme.of(context).colorScheme;
    return Drawer(
      width: math.min(MediaQuery.sizeOf(context).width * .86, 340),
      backgroundColor: scheme.surface.withValues(alpha: .96),
      elevation: 18,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(
          right: Radius.circular(ERouteRadius.sheet),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  ERouteSpacing.md,
                  ERouteSpacing.xs,
                  ERouteSpacing.md,
                  ERouteSpacing.md,
                ),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'E',
                                    style: TextStyle(
                                      color: context.eroute.emergency,
                                    ),
                                  ),
                                  const TextSpan(text: 'Route'),
                                ],
                              ),
                              style: ERouteTypography.pageTitle.copyWith(
                                fontSize: 27,
                              ),
                            ),
                            const SizedBox(height: ERouteSpacing.xxs),
                            Text(
                              '언제 어디서나, 더 빠른 응급의료',
                              style: ERouteTypography.label.copyWith(
                                color: context.eroute.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '메뉴 닫기',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: ERouteSpacing.lg),
                  if (session.authenticated)
                    _MenuTile(
                      icon: Icons.account_circle_outlined,
                      label: session.userSummary!,
                      onTap: () => _open(context, AppRoutes.profile),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(ERouteSpacing.md),
                      decoration: BoxDecoration(
                        color: context.eroute.softBlue,
                        borderRadius: BorderRadius.circular(ERouteRadius.card),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '로그인이 필요합니다',
                            style: ERouteTypography.hospitalName.copyWith(
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: ERouteSpacing.xxs),
                          Text(
                            '내 정보와 내 응급정보는 로그인 후 이용할 수 있습니다.',
                            style: ERouteTypography.label.copyWith(
                              color: context.eroute.muted,
                            ),
                          ),
                          const SizedBox(height: ERouteSpacing.sm),
                          FilledButton(
                            onPressed: () => _open(context, AppRoutes.login),
                            child: const Text('로그인'),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: ERouteSpacing.md),
                  const Divider(),
                  _MenuTile(
                    icon: Icons.person_outline_rounded,
                    label: '내 정보',
                    onTap: () => _open(context, AppRoutes.profile),
                  ),
                  _MenuTile(
                    icon: Icons.medical_information_outlined,
                    label: '내 응급정보',
                    onTap: () => _open(context, AppRoutes.emergencyProfile),
                  ),
                  _MenuTile(
                    icon: Icons.settings_outlined,
                    label: '설정',
                    onTap: () => _open(context, AppRoutes.settings),
                  ),
                  _MenuTile(
                    icon: Icons.info_outline_rounded,
                    label: '앱 정보',
                    onTap: () => _open(context, AppRoutes.about),
                  ),
                  if (session.authenticated)
                    _MenuTile(
                      icon: Icons.logout_rounded,
                      label: '로그아웃',
                      onTap: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final navigator = Navigator.of(context);
                        final controller = ref.read(
                          sessionControllerProvider.notifier,
                        );
                        Navigator.pop(context);
                        try {
                          final complete = await controller.signOut();
                          if (navigator.mounted) {
                            navigator.popUntil((route) => route.isFirst);
                          }
                          if (messenger.mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  complete
                                      ? '로그아웃되었습니다.'
                                      : '기기의 로그인 정보는 삭제했습니다. 서버 로그아웃은 연결 후 다시 확인합니다.',
                                ),
                              ),
                            );
                          }
                        } catch (_) {
                          if (messenger.mounted) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  '로그아웃 처리를 확인하지 못했습니다. 다시 시도해주세요.',
                                ),
                              ),
                            );
                          }
                        }
                      },
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ERouteSpacing.md,
                ERouteSpacing.xs,
                ERouteSpacing.md,
                ERouteSpacing.md,
              ),
              child: Material(
                color: context.eroute.emergency.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(ERouteRadius.card),
                child: InkWell(
                  borderRadius: BorderRadius.circular(ERouteRadius.card),
                  onTap: callStatus == EmergencyCallStatus.idle
                      ? () {
                          final rootContext = Navigator.of(context).context;
                          Navigator.pop(context);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (rootContext.mounted) {
                              ref
                                  .read(emergencyCallProvider)
                                  .confirm(rootContext);
                            }
                          });
                        }
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.all(ERouteSpacing.md),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: context.eroute.emergency,
                            borderRadius: BorderRadius.circular(
                              ERouteRadius.control,
                            ),
                          ),
                          child: Icon(
                            Icons.call_rounded,
                            color: context.eroute.onEmergency,
                          ),
                        ),
                        const SizedBox(width: ERouteSpacing.sm),
                        const Expanded(
                          child: Text(
                            '긴급 상황 시\n119 전화 연결',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => ListTile(
    minTileHeight: 52,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(ERouteRadius.control),
    ),
    leading: Icon(icon),
    title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}
