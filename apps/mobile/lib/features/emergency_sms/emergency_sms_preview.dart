import '../disease_personalization/condition_local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/location/geolocator_location_service.dart';
import '../../core/location/location_fix.dart';
import '../../core/theme/eroute_tokens.dart';
import '../app_menu/app_session.dart';
import '../emergency_map/presentation/emergency_map_controller.dart';
import '../member_ui/member_contract.dart';
import '../member_ui/member_controller.dart';
import '../member_ui/member_widgets.dart';
import 'emergency_sms_formatter.dart';
import 'emergency_sms_launcher.dart';

/// Checks access only: no health read and no call dependency on this request.
final emergencySmsAccessProvider = FutureProvider.autoDispose<MemberAccess?>((
  ref,
) async {
  final session = ref.watch(sessionProvider);
  if (!session.authenticated) return null;
  try {
    final access = await ref.watch(memberUiRepositoryProvider).access();
    return access.granted &&
            access.userId == session.userId &&
            access.sessionGeneration == session.generation
        ? access
        : null;
  } catch (_) {
    return null;
  }
});

class EmergencySmsOption extends ConsumerWidget {
  const EmergencySmsOption({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(emergencySmsAccessProvider).valueOrNull;
    if (access == null) return const SizedBox.shrink();
    return TextButton.icon(
      onPressed: () => Navigator.pop(context, 'sms'),
      icon: const Icon(Icons.sms_outlined),
      label: const Text('응급정보 문자 준비'),
    );
  }
}

/// A snapshot from the existing location owner; no new permissions or geocoder.
final emergencySmsLocationProvider = FutureProvider.autoDispose<LocationFix?>((
  ref,
) async {
  final cached = ref.read(mapControllerProvider).userFix;
  if (cached != null &&
      DateTime.now().difference(cached.measuredAt).abs() <
          const Duration(minutes: 1)) {
    return cached;
  }
  final service = ref.read(locationServiceProvider);
  if (service is! GeolocatorLocationService) return null;
  return service.currentIfPermitted().timeout(
    const Duration(seconds: 3),
    onTimeout: () => null,
  );
});

Future<bool> showEmergencySmsPreview(BuildContext context) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const MemberSecurityScope(child: EmergencySmsPreview()),
    ) ??
    false;

class EmergencySmsPreview extends ConsumerStatefulWidget {
  const EmergencySmsPreview({super.key});
  @override
  ConsumerState<EmergencySmsPreview> createState() =>
      _EmergencySmsPreviewState();
}

class _EmergencySmsPreviewState extends ConsumerState<EmergencySmsPreview> {
  final excluded = <String>{};
  bool busy = false, leaving = false;
  void close(bool call) {
    leaving = true;
    Navigator.pop(context, call);
  }

  String? error;

  Future<void> compose(
    MemberHealthSnapshot health,
    Map<String, String> fields,
  ) async {
    if (busy) return;
    final initial = ref.read(memberControllerProvider);
    final session = ref.read(sessionProvider);
    if (!session.authenticated ||
        initial.covered ||
        initial.access?.granted != true) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final access = await ref.read(memberUiRepositoryProvider).access();
      if (!mounted || leaving || ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      final current = ref.read(memberControllerProvider);
      final nowSession = ref.read(sessionProvider);
      if (!nowSession.authenticated ||
          nowSession.userId != session.userId ||
          nowSession.generation != session.generation ||
          current.covered ||
          !access.granted ||
          access.identity != initial.access?.identity ||
          access.userId != nowSession.userId ||
          access.sessionGeneration != nowSession.generation ||
          access.consentEpoch != health.consentEpoch ||
          current.health?.version != health.version) {
        excluded.clear();
        ref.read(memberControllerProvider.notifier).cover(clear: true);
        return;
      }
      // Generated only after explicit preview confirmation. No stored URI/body.
      final opened = await ref
          .read(emergencySmsLauncherProvider)
          .compose(formatEmergencySms(fields));
      if (!mounted || leaving || ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      if (opened) {
        close(false);
      } else {
        setState(() => error = '문자 작성 화면을 열지 못했습니다. 다시 시도하거나 119에 전화하세요.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = '접근 상태를 확인하지 못했습니다. 다시 시도하거나 119에 전화하세요.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(memberControllerProvider);
    final session = ref.watch(sessionProvider);
    final location = ref.watch(emergencySmsLocationProvider).valueOrNull;
    final capability = ref.watch(emergencySmsCapabilityProvider);
    final health = state.health;
    final allowed =
        session.authenticated &&
        !state.covered &&
        state.access?.granted == true &&
        state.access?.userId == session.userId &&
        state.access?.sessionGeneration == session.generation &&
        health != null &&
        state.access?.consentEpoch == health.consentEpoch;
    final local = ref.watch(conditionLocalProvider);
    final ownLocal =
        local != null &&
            local.userId == state.access?.userId &&
            local.epoch == state.access?.consentEpoch &&
            !local.conflict
        ? local
        : null;
    final fields = allowed
        ? emergencySmsFields(
            health,
            location,
            conditions: ownLocal?.entries,
            conditionsStatus: ownLocal == null
                ? null
                : EntryStatus.values.byName(ownLocal.status.toLowerCase()),
          )
        : <String, String>{};
    final selected = Map<String, String>.from(fields)
      ..removeWhere((k, _) => excluded.contains(k));
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .85,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  MemberCopy(
                    '119에 보낼 응급정보',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const MemberCopy('긴급하면 문자 작성보다 119 통화를 우선하세요.'),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: context.eroute.emergency,
                      foregroundColor: context.eroute.onEmergency,
                    ),
                    onPressed: () => close(true),
                    icon: const Icon(Icons.call_outlined),
                    label: const Text('119 전화 연결'),
                  ),
                  const SizedBox(height: 16),
                  if (!allowed) ...[
                    if (state.loading)
                      const Center(child: CircularProgressIndicator()),
                    Text(state.error ?? '로그인과 건강정보 접근 상태를 확인하고 있습니다.'),
                    if (!state.loading)
                      TextButton(
                        onPressed: () => ref
                            .read(memberControllerProvider.notifier)
                            .reload(),
                        child: const Text('다시 확인'),
                      ),
                  ] else ...[
                    const MemberCopy('문자에 포함할 정보를 선택하세요. 미입력 항목은 생략합니다.'),
                    if (location == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('현재 위치를 확인하지 못했습니다.'),
                      ),
                    if (fields.isEmpty)
                      const Text('저장된 응급정보가 없습니다. 문자 앱에서 신고 내용을 직접 입력할 수 있어요.'),
                    if (fields.length == 1 && fields.containsKey('현재 위치'))
                      const Text('위치 문자 신고 · 저장된 건강정보는 없습니다.'),
                    for (final field in fields.entries)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        titleAlignment: ListTileTitleAlignment.top,
                        title: Text(field.key),
                        subtitle: Text(
                          field.value,
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                        ),
                        value: !excluded.contains(field.key),
                        onChanged: busy
                            ? null
                            : (include) => setState(() {
                                include == true
                                    ? excluded.remove(field.key)
                                    : excluded.add(field.key);
                              }),
                      ),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const MemberCopy('문자 본문 전체 확인'),
                      children: [Text(formatEmergencySms(selected))],
                    ),
                    const Text(
                      '문자 앱에서 수신자 119와 내용을 확인한 뒤 직접 전송하세요. 전화 신고와 자동으로 연결되거나 병합되지 않습니다.',
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Semantics(liveRegion: true, child: Text(error!)),
                      ),
                    const SizedBox(height: 16),
                    if (capability.valueOrNull == false || capability.hasError)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          '이 기기에서는 문자 작성 기능을 사용할 수 없습니다. 긴급 상황에서는 119에 전화하세요.',
                        ),
                      ),
                    OutlinedButton(
                      onPressed: busy || capability.valueOrNull != true
                          ? null
                          : () => compose(health, selected),
                      child: Text(
                        busy
                            ? '문자 작성 화면 여는 중…'
                            : capability.isLoading
                            ? '문자 기능 확인 중…'
                            : '문자 앱에서 확인하고 보내기',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            TextButton(onPressed: () => close(false), child: const Text('닫기')),
          ],
        ),
      ),
    );
  }
}
