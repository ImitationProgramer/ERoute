import 'dart:async';
import '../../../development/disease_review_preview.dart';
import '../../../core/privacy_changes.dart';
import '../../app_menu/app_session.dart';
import '../../disease_personalization/map_personalization_controller.dart';
import '../../disease_personalization/personalization_badge.dart';
import '../../emergency_map/presentation/emergency_map_controller.dart';
import '../../member_ui/member_widgets.dart' show SensitiveDisplayScope;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/router.dart';
import '../../../core/theme/eroute_tokens.dart';
import '../../../core/widgets/eroute_card.dart';
import '../../../core/widgets/eroute_feedback.dart';
import '../../../core/widgets/eroute_scaffold.dart';
import '../../../core/widgets/eroute_skeleton.dart';
import '../../emergency_map/presentation/widgets/realtime_summary.dart';
import '../../member_ui/member_widgets.dart' show memberConfirm, memberFeedback;
import '../domain/hospital_actions.dart';
import '../domain/hospital_detail_repository.dart';
import 'hospital_detail_state.dart';
import 'hospital_clinical_information.dart';

class HospitalDetailPage extends ConsumerStatefulWidget {
  final String hpid;
  const HospitalDetailPage({super.key, required this.hpid});

  @override
  ConsumerState<HospitalDetailPage> createState() => _HospitalDetailPageState();
}

class _HospitalDetailPageState extends ConsumerState<HospitalDetailPage>
    with WidgetsBindingObserver, RouteAware {
  bool _visible = true, _foreground = true, _reasonOpen = false;
  MapPersonalizationController get _personalization => reviewPreviewBuild
      ? ref.read(reviewPreviewProvider.notifier)
      : ref.read(mapPersonalizationProvider.notifier);
  void _activate() {
    if (!mounted || !_visible || !_foreground) return;
    final controller = _personalization;
    controller.setSearch(ref.read(mapControllerProvider).snapshot);
    unawaited(controller.enable());
  }

  void _scheduleActivation() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => _activate());
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleActivation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) appRouteObserver.subscribe(this, route);
  }

  @override
  void didPushNext() {
    if (_reasonOpen) return;
    _visible = false;
    _personalization.disable();
  }

  @override
  void didPopNext() {
    if (_reasonOpen) return;
    _visible = true;
    _scheduleActivation();
  }

  @override
  void didPop() {
    _visible = false;
    _personalization.disable();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _personalization.disable();
    if (_foreground) _scheduleActivation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  Future<void> _showReason() async {
    _reasonOpen = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => Consumer(
          builder: (context, ref, _) {
            final state = reviewPreviewBuild
                ? ref.watch(reviewPreviewProvider)
                : ref.watch(mapPersonalizationProvider);
            return PersonalizationReasonSheet(result: state.results[hpid]);
          },
        ),
      );
    } finally {
      _reasonOpen = false;
    }
  }

  bool _openingPhone = false;
  bool _openingNavigation = false;
  String get hpid => widget.hpid;

  @override
  Widget build(BuildContext context) {
    final personal = reviewPreviewBuild
        ? ref.watch(reviewPreviewProvider)
        : ref.watch(mapPersonalizationProvider);
    ref.listen(sessionProvider, (old, next) {
      if (old?.userId != next.userId ||
          old?.generation != next.generation ||
          old?.authenticated != next.authenticated) {
        _scheduleActivation();
      }
    });
    ref.listen(privacyChangeProvider, (_, _) => _scheduleActivation());
    final state = ref.watch(hospitalDetailProvider(hpid));
    final detail = state.loaded;
    final searchHospital = state.searchHospital;
    final realtime = state.realtime;
    if (detail == null &&
        searchHospital == null &&
        state.detail.hasError &&
        !state.detail.isLoading) {
      return ERouteScaffold(
        title: '병원 상세',
        showBack: true,
        body: state.detail.when(
          data: (_) => const SizedBox.shrink(),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: ERouteErrorState(
              title: error is HospitalDetailNotFound
                  ? '병원 정보를 찾을 수 없습니다'
                  : '병원 정보를 불러오지 못했습니다',
              message: error is HospitalDetailNotFound
                  ? '병원 목록으로 돌아가 다시 선택해주세요.'
                  : '연결 상태를 확인한 뒤 다시 시도해주세요.',
              actionLabel: error is HospitalDetailNotFound
                  ? '지도에서 찾기'
                  : '다시 시도',
              onAction: error is HospitalDetailNotFound
                  ? () {
                      var foundMap = false;
                      Navigator.of(context).popUntil((route) {
                        foundMap = route.settings.name == AppRoutes.map;
                        return foundMap || route.isFirst;
                      });
                      if (!foundMap) pushAppRoute(context, AppRoutes.map);
                    }
                  : () => ref.invalidate(hospitalDetailRequestProvider(hpid)),
            ),
          ),
        ),
      );
    }

    final name = detail?.name ?? searchHospital?.name;
    final classification =
        detail?.classification ?? searchHospital?.classification;
    final distance = searchHospital == null
        ? null
        : state.searchSource == 'MANUAL'
        ? searchHospital.centerDistance
        : (searchHospital.userDistance ?? searchHospital.centerDistance);
    final distanceLabel = distance == null
        ? null
        : distance < 1000
        ? '${distance}m'
        : '${(distance / 1000).toStringAsFixed(1)}km';
    final contactLauncher = ref.watch(hospitalContactLauncherProvider);
    final canCall =
        normalizeHospitalDialNumber(detail?.mainPhone?.rawValue ?? '') !=
            null &&
        !_openingPhone &&
        contactLauncher.availability == HospitalActionAvailability.available;

    final navigationLauncher = ref.watch(hospitalNavigationLauncherProvider);
    // Once detail has loaded, missing coordinates must not use an old search fix.
    final location = detail != null
        ? detail.location
        : searchHospital?.location;
    final validLocation = validHospitalNavigationLocation(
      location?.latitude,
      location?.longitude,
    );
    final canNavigate =
        validLocation &&
        name != null &&
        !_openingNavigation &&
        navigationLauncher.availability == HospitalActionAvailability.available;

    return ERouteScaffold(
      title: '병원 상세',
      opaqueTopBar: true,
      showBack: true,
      actions: [
        IconButton(
          tooltip: '즐겨찾기 준비 중',
          onPressed: null,
          icon: const Icon(Icons.favorite_border_rounded),
        ),
      ],
      body: SensitiveDisplayScope(
        enabled: personal.enabled,
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  ERouteSpacing.md,
                  ERouteSpacing.xs,
                  ERouteSpacing.md,
                  ERouteSpacing.xl,
                ),
                children: [
                  if (state.detail.isLoading && detail != null) ...[
                    const LinearProgressIndicator(minHeight: 2),
                    const SizedBox(height: ERouteSpacing.sm),
                  ],
                  if (state.detail.hasError && !state.detail.isLoading) ...[
                    ERouteCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              state.detail.error is HospitalDetailNotFound
                                  ? '병원 정보를 찾을 수 없습니다. 이전 정보를 표시합니다.'
                                  : detail == null
                                  ? '상세 정보를 불러오지 못했습니다.'
                                  : '상세 조회 실패 · 이전 정보를 표시합니다.',
                            ),
                          ),
                          TextButton(
                            onPressed: () => ref.invalidate(
                              hospitalDetailRequestProvider(hpid),
                            ),
                            child: const Text('다시 시도'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: ERouteSpacing.md),
                  ],
                  Semantics(
                    header: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (classification != null)
                          ERouteStatusBadge(classification)
                        else
                          const ERouteSkeleton(
                            width: 120,
                            label: '기관 분류 불러오는 중',
                          ),
                        const SizedBox(height: ERouteSpacing.sm),
                        if (name == null)
                          const ERouteSkeleton(height: 34, label: '병원명 불러오는 중')
                        else
                          Text(
                            name,
                            style: ERouteTypography.pageTitle.copyWith(
                              fontSize: 26,
                            ),
                          ),
                        if (distanceLabel != null) ...[
                          const SizedBox(height: ERouteSpacing.xs),
                          Text(
                            '$distanceLabel · ${state.searchSource == 'MANUAL' ? '검색 중심에서 직선거리' : '현재 위치에서 직선거리'}',
                            style: ERouteTypography.label.copyWith(
                              color: context.eroute.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: ERouteSpacing.lg),
                  ERouteCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: ERouteSpacing.sm),
                        Expanded(
                          child: _DetailField(
                            state: state,
                            value: detail?.address,
                            label: '주소',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: ERouteSpacing.md),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final phone = OutlinedButton.icon(
                        onPressed: canCall
                            ? () => _openDialScreen(
                                context,
                                contactLauncher,
                                detail!.mainPhone!.rawValue,
                              )
                            : null,
                        icon: const Icon(Icons.call_outlined),
                        label: const Text('전화하기'),
                      );
                      final navigation = OutlinedButton.icon(
                        onPressed: canNavigate
                            ? () => _openNavigation(
                                navigationLauncher,
                                location!.latitude,
                                location.longitude,
                                name,
                              )
                            : null,
                        icon: const Icon(Icons.directions_outlined),
                        label: const Text(
                          '네이버 지도에서 열기',
                          textAlign: TextAlign.center,
                        ),
                      );
                      // Same row-to-column treatment as the landing CTAs.
                      if (constraints.maxWidth < 360 ||
                          MediaQuery.textScalerOf(context).scale(16) >= 20) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            phone,
                            const SizedBox(height: ERouteSpacing.sm),
                            navigation,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: phone),
                          const SizedBox(width: ERouteSpacing.sm),
                          Expanded(flex: 2, child: navigation),
                        ],
                      );
                    },
                  ),
                  if (!validLocation) ...[
                    const SizedBox(height: ERouteSpacing.xs),
                    Text(
                      '병원 위치 정보가 없어 네이버 지도를 열 수 없습니다.',
                      style: ERouteTypography.label.copyWith(
                        color: context.eroute.muted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: ERouteSpacing.xs),
                  Text(
                    detail?.mainPhone != null && !canCall && !_openingPhone
                        ? '전화 연결이 가능한 대표번호가 아닙니다.'
                        : '전화하기를 누르면 전화 앱의 번호 입력 화면을 엽니다.',
                    style: ERouteTypography.label.copyWith(
                      color: context.eroute.muted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (realtime != null) ...[
                    const SizedBox(height: ERouteSpacing.lg),
                    ERouteCard(
                      child: RealtimeSummary(hospital: realtime, detail: true),
                    ),
                  ] else if (state.detail.isLoading) ...[
                    const SizedBox(height: ERouteSpacing.lg),
                    const ERouteCard(
                      child: ERouteSkeleton(
                        height: 100,
                        label: '실시간 정보 불러오는 중',
                      ),
                    ),
                  ],
                  const SizedBox(height: ERouteSpacing.lg),
                  SegmentedButton<HospitalDetailTab>(
                    segments: const [
                      ButtonSegment(
                        value: HospitalDetailTab.basic,
                        label: Text('기본 정보'),
                      ),
                      ButtonSegment(
                        value: HospitalDetailTab.clinical,
                        label: Text('진료 정보'),
                      ),
                    ],
                    selected: {state.tab},
                    onSelectionChanged: (selection) =>
                        ref
                                .read(hospitalDetailTabProvider(hpid).notifier)
                                .state =
                            selection.first,
                    showSelectedIcon: false,
                  ),
                  const SizedBox(height: ERouteSpacing.md),
                  AnimatedSwitcher(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    child: state.tab == HospitalDetailTab.basic
                        ? _BasicInformationCard(state: state)
                        : HospitalClinicalInformation(
                            state: state,
                            personalization: _visible && _foreground
                                ? personal.results[hpid]
                                : null,
                            onReviewReason: _showReason,
                          ),
                  ),
                  const SizedBox(height: ERouteSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.ios_share_outlined),
                          label: const Text('공유하기'),
                        ),
                      ),
                      const SizedBox(width: ERouteSpacing.sm),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.favorite_border_rounded),
                          label: const Text('즐겨찾기'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: ERouteSpacing.xs),
                  Text(
                    '공유와 즐겨찾기 기능을 준비하고 있습니다.',
                    style: ERouteTypography.label.copyWith(
                      color: context.eroute.muted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openNavigation(
    HospitalNavigationLauncher launcher,
    double latitude,
    double longitude,
    String hospitalName,
  ) async {
    if (_openingNavigation ||
        !validHospitalNavigationLocation(latitude, longitude)) {
      return;
    }
    setState(() => _openingNavigation = true);
    try {
      final result = await launcher.openNavigation(
        latitude,
        longitude,
        hospitalName,
      );
      if (!mounted) return;
      switch (result) {
        case HospitalNavigationResult.opened:
          break;
        case HospitalNavigationResult.notInstalled:
          final install = await memberConfirm(
            context,
            '네이버 지도가 필요합니다',
            '길 안내를 보려면 네이버 지도 앱이 필요합니다.',
            '설치하기',
          );
          if (!install || !mounted) return;
          final opened = await launcher.openStore();
          if (!opened && mounted) {
            memberFeedback(context, '앱 설치 페이지를 열 수 없습니다. 잠시 후 다시 시도해주세요.');
          }
        case HospitalNavigationResult.invalidLocation:
          memberFeedback(context, '병원 위치 정보가 없어 네이버 지도를 열 수 없습니다.');
        case HospitalNavigationResult.failed:
          memberFeedback(context, '네이버 지도를 열 수 없습니다. 잠시 후 다시 시도해주세요.');
      }
    } catch (_) {
      if (mounted) memberFeedback(context, '네이버 지도를 열 수 없습니다. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _openingNavigation = false);
    }
  }

  Future<void> _openDialScreen(
    BuildContext context,
    HospitalContactLauncher launcher,
    String number,
  ) async {
    if (_openingPhone || normalizeHospitalDialNumber(number) == null) return;
    setState(() => _openingPhone = true);
    var opened = false;
    try {
      opened = await launcher.openDialScreen(number);
    } catch (_) {
      opened = false;
    } finally {
      if (mounted) setState(() => _openingPhone = false);
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('전화 앱을 열 수 없습니다. 번호를 직접 입력해주세요.')),
      );
    }
  }
}

class _BasicInformationCard extends StatelessWidget {
  final HospitalDetailState state;
  const _BasicInformationCard({required this.state});
  @override
  Widget build(BuildContext context) {
    final detail = state.loaded;
    return ERouteCard(
      key: const ValueKey('basic'),
      child: Column(
        children: [
          _InfoRow(
            '기관 분류',
            state: state,
            value:
                detail?.classification ?? state.searchHospital?.classification,
          ),
          const Divider(height: 25),
          _InfoRow('주소', state: state, value: detail?.address),
          const Divider(height: 25),
          _InfoRow('대표전화', state: state, value: detail?.mainPhone?.rawValue),
          if (detail?.secondaryPhone != null) ...[
            const Divider(height: 25),
            _InfoRow(
              '추가 전화번호',
              state: state,
              value: detail!.secondaryPhone!.rawValue,
            ),
          ],

          if (detail?.catalogStale ?? false) ...[
            const Divider(height: 25),
            _InfoRow('기본정보 상태', state: state, value: '이전 정보'),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String? value;
  final HospitalDetailState state;
  const _InfoRow(this.label, {required this.state, this.value});
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 110,
        child: Text(
          label,
          style: ERouteTypography.label.copyWith(color: context.eroute.muted),
        ),
      ),
      Expanded(
        child: _DetailField(state: state, value: value, label: label),
      ),
    ],
  );
}

class _DetailField extends StatelessWidget {
  final HospitalDetailState state;
  final String? value;
  final String label;
  const _DetailField({
    required this.state,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) => switch (state.fieldStatus(value)) {
    DetailFieldStatus.loading => ERouteSkeleton(label: '$label 불러오는 중'),
    DetailFieldStatus.available => Text(value!),
    DetailFieldStatus.notProvided => const Text('정보 미제공'),
    DetailFieldStatus.requestFailed => const Text('정보를 불러오지 못했습니다'),
  };
}
