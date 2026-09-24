import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app_menu/app_session.dart';
import '../auth/auth_repository.dart';
import 'member_contract.dart';
import 'member_controller.dart';
import 'member_widgets.dart';
import 'member_health_screens.dart';
import 'member_auth_screen.dart';
import '../../app/router.dart';

class MemberAccountScreen extends ConsumerStatefulWidget {
  const MemberAccountScreen({super.key});
  @override
  ConsumerState<MemberAccountScreen> createState() =>
      _MemberAccountScreenState();
}

class _MemberAccountScreenState extends ConsumerState<MemberAccountScreen> {
  bool busy = false;
  String? error;
  Future<void> logout(bool all) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final session = ref.read(sessionControllerProvider.notifier);
    final repository = ref.read(memberUiRepositoryProvider);
    final controller = ref.read(memberControllerProvider.notifier);
    try {
      if (all) await repository.logoutAll();
      controller.cover(clear: true);
      final done = await session.signOut();
      if (!navigator.mounted) return;
      if (!done) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('기기에서 로그아웃했습니다. 서버 폐기는 연결 복구 후 다시 확인합니다.'),
          ),
        );
      }
      navigator.pushAndRemoveUntil(
        buildAppRoute(const RouteSettings(name: AppRoutes.landing)),
        (_) => false,
      );
    } catch (e) {
      if (mounted) setState(() => error = memberError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget group(String name, List<Widget> rows) => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        MemberPanel(child: Column(children: rows)),
      ],
    ),
  );
  Widget row(
    IconData icon,
    String title, {
    VoidCallback? action,
    String? subtitle,
  }) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, size: 21, color: Theme.of(context).colorScheme.primary),
    title: Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    subtitle: subtitle == null ? null : Text(subtitle),
    trailing: action == null ? null : const Icon(Icons.chevron_right),
    onTap: busy ? null : action,
  );
  Widget shortcut(
    String title,
    IconData icon,
    MemberTone tone,
    VoidCallback action,
  ) => Card(
    margin: EdgeInsets.zero,
    shape: memberCardShape(context),
    elevation: 1,
    shadowColor: Colors.black.withValues(alpha: .10),
    surfaceTintColor: Colors.transparent,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: busy ? null : action,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            MemberCategoryIcon(tone: tone, icon: icon),
            const SizedBox(width: 10),
            Expanded(
              child: MemberCopy(
                title,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final a = ref.watch(memberControllerProvider).access;
    final color = Theme.of(context).colorScheme;
    return MemberScaffold(
      title: '내 정보',
      child: MemberGuard(
        healthRequired: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    color.primary,
                    Color.lerp(color.primary, color.secondary, .4)!,
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '안녕하세요',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: color.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '내 계정과 건강정보를 한곳에서',
                    style: TextStyle(color: color.onPrimary),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Icon(
                        Icons.phone_android,
                        size: 18,
                        color: color.onPrimary,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          a?.phone ?? '',
                          style: TextStyle(color: color.onPrimary),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = MediaQuery.textScalerOf(context).scale(16) > 24;
                final cards = [
                  shortcut(
                    '내 응급정보',
                    Icons.local_hospital_outlined,
                    MemberTone.allergy,
                    () =>
                        openMemberPage(context, const MemberEmergencyScreen()),
                  ),
                  shortcut(
                    '복용약',
                    Icons.medication_outlined,
                    MemberTone.medication,
                    () =>
                        openMemberPage(context, const MemberMedicationScreen()),
                  ),
                ];
                return stacked
                    ? Column(
                        children: [
                          cards[0],
                          const SizedBox(height: 12),
                          cards[1],
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: cards[0]),
                          const SizedBox(width: 12),
                          Expanded(child: cards[1]),
                        ],
                      );
              },
            ),
            group('건강정보 관리', [
              row(
                Icons.verified_user_outlined,
                '건강정보 동의 및 삭제',
                subtitle: a?.granted == true ? '동의한 상태 · 삭제 범위 확인' : '별도 동의 필요',
                action: () =>
                    openMemberPage(context, const MemberConsentScreen()),
              ),
            ]),
            group('계정 · 보안', [
              row(
                Icons.lock_outline,
                '비밀번호 재확인',
                action: () => openMemberPage(
                  context,
                  const MemberAuthScreen(reauthenticate: true),
                ),
              ),
              row(Icons.logout, '로그아웃', action: () => logout(false)),
              const Divider(height: 1),
              row(Icons.devices, '모든 기기에서 로그아웃', action: () => logout(true)),
            ]),
            const SizedBox(height: 20),
            MemberCopy(
              '현재 번호 변경과 비밀번호 찾기는 지원하지 않습니다.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (error != null) MemberNotice(error!, error: true),
          ],
        ),
      ),
    );
  }
}

class MemberConsentScreen extends ConsumerStatefulWidget {
  const MemberConsentScreen({super.key});
  @override
  ConsumerState<MemberConsentScreen> createState() =>
      _MemberConsentScreenState();
}

class _MemberConsentScreenState extends ConsumerState<MemberConsentScreen> {
  bool busy = false, agreed = false;
  String? error, withdrawalKey;
  Future<void> mutate(
    Future<void> Function() operation, {
    bool returnAfterGrant = false,
  }) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    final owner = ref.read(sessionProvider);
    try {
      await operation();
      if (!mounted) return;
      await ref.read(memberControllerProvider.notifier).reload();
      final current = ref.read(sessionProvider);
      if (!mounted ||
          !current.authenticated ||
          current.userId != owner.userId ||
          current.generation != owner.generation) {
        return;
      }
      final confirmed = ref.read(memberControllerProvider);
      if (returnAfterGrant && confirmed.access?.granted != true) return;
      memberFeedback(context, ref.read(memberResultLabelProvider));
      if (returnAfterGrant && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) setState(() => error = memberError(e));
      await ref.read(memberControllerProvider.notifier).reload();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = ref.watch(memberControllerProvider), a = v.access, h = v.health;
    return MemberScaffold(
      title: '건강정보 관리',
      child: MemberGuard(
        healthRequired: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const MemberNotice('건강정보 동의는 회원가입 동의와 별도로 관리합니다.'),
            const SizedBox(height: 20),
            if (a != null && !a.granted) ...[
              Text('건강정보 처리 동의', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              const MemberCopy(
                '알레르기·기저질환·응급 메모·복용약과 복용 메모를 직접 기록하고 조회하기 위한 동의입니다.',
              ),
              const SizedBox(height: 12),
              const MemberCopy(
                '동의를 철회하면 건강정보가 삭제되며 계정과 로그인은 유지됩니다. 현재 자동 전송되지 않습니다.',
              ),
              const SizedBox(height: 12),
              const Text('건강정보 처리 동의 · health-v1'),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: agreed,
                onChanged: busy
                    ? null
                    : (value) => setState(() => agreed = value!),
                title: const Text('건강정보 처리에 별도로 동의합니다'),
              ),
              MemberBusyButton(
                busy: busy,
                onPressed: !agreed || a.consentState == 'REVOKING'
                    ? null
                    : () => mutate(
                        () => ref
                            .read(memberUiRepositoryProvider)
                            .grantConsent(a.consentEpoch),
                        returnAfterGrant: true,
                      ),
                label: '동의하고 시작',
              ),
            ],
            if (a?.granted == true && h != null) ...[
              MemberPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '응급 기록 삭제',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const MemberCopy(
                      '알레르기·기저질환·응급 메모를 삭제합니다. 복용약·건강정보 동의·계정은 유지됩니다.',
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () async {
                              if (await memberConfirm(
                                context,
                                '응급 기록 삭제',
                                '알레르기·기저질환·응급 메모를 삭제합니다. 복용약·건강정보 동의·계정은 유지됩니다.',
                                '응급 기록 삭제',
                              )) {
                                await mutate(
                                  () => ref
                                      .read(memberUiRepositoryProvider)
                                      .deleteProfile(h.version, h.consentEpoch),
                                );
                              }
                            },
                      child: const Text('응급 기록 삭제'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              MemberPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '동의 철회 및 삭제',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const MemberCopy(
                      '모든 건강정보와 복용약을 삭제합니다. 회원 계정과 로그인은 유지됩니다. 백업 파기는 별도로 확인합니다.',
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () async {
                              if (await memberConfirm(
                                context,
                                '건강정보 동의 철회',
                                '알레르기·기저질환·응급 메모·모든 복용약과 메모를 삭제합니다. 계정과 로그인은 유지됩니다. 백업 파기는 별도 확인합니다.',
                                '동의 철회 및 삭제',
                              )) {
                                withdrawalKey ??= authNonce();
                                ref
                                    .read(memberControllerProvider.notifier)
                                    .cover(clear: true);
                                await mutate(
                                  () => ref
                                      .read(memberUiRepositoryProvider)
                                      .withdrawConsent(
                                        a!.consentEpoch,
                                        withdrawalKey!,
                                      ),
                                );
                              }
                            },
                      child: const Text('동의 철회 및 삭제'),
                    ),
                  ],
                ),
              ),
            ],
            for (final job in a?.deletions ?? <DeletionProgress>[]) ...[
              const SizedBox(height: 16),
              MemberPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.state == 'COMPLETE'
                          ? '서비스 건강정보 삭제 완료'
                          : job.state == 'FAILED'
                          ? '삭제 처리 실패'
                          : '삭제 처리 중',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      job.backupComplete ? '백업 파기 확인 완료' : '백업 파기는 별도 확인 중입니다.',
                    ),
                    if (job.state == 'FAILED')
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => mutate(
                                () => ref
                                    .read(memberUiRepositoryProvider)
                                    .retryDeletion(),
                              ),
                        child: const Text('삭제 재시도'),
                      ),
                  ],
                ),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 16),
              MemberNotice(error!, error: true),
            ],
            const SizedBox(height: 16),
            TextButton(
              onPressed: busy
                  ? null
                  : () => ref.read(memberControllerProvider.notifier).reload(),
              child: const Text('처리 상태 다시 확인'),
            ),
          ],
        ),
      ),
    );
  }
}
