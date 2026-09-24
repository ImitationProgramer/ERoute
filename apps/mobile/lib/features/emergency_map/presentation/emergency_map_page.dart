import '../../disease_personalization/personalization_category_button.dart';
import '../../member_ui/member_health_screens.dart';
import '../../../development/disease_review_preview.dart';
import '../../app_menu/app_session.dart';
import '../../../core/privacy_changes.dart';
import '../../disease_personalization/map_personalization_controller.dart';
import '../../disease_personalization/personalization_overlay.dart';
import '../../disease_personalization/personalization_presentation.dart';
import '../../disease_personalization/personalization_badge.dart';
import '../../member_ui/member_widgets.dart' show SensitiveDisplayScope;
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/router.dart';
import '../../../core/map/emergency_map_view.dart';
import '../../../core/map/naver_emergency_map_view.dart';
import '../../../core/map/map_scene.dart';
import '../../../core/map/map_camera_controller.dart';
import '../../../core/location/heading_service.dart';
import '../../../core/theme/eroute_tokens.dart';
import '../../app_menu/emergency_drawer.dart';
import '../../emergency_call/emergency_call_coordinator.dart';
import '../../emergency_call/emergency_call_state.dart';
import 'emergency_map_controller.dart';
import 'widgets/hospital_sheet.dart';
import 'widgets/map_controls.dart';

// Host/test adapter; ordinary routes keep the native map implementation.
final emergencyMapBuilderProvider = Provider<EmergencyMapBuilder?>(
  (ref) => null,
);

class EmergencyMapPage extends ConsumerStatefulWidget {
  final EmergencyMapBuilder? mapBuilder;
  const EmergencyMapPage({super.key, this.mapBuilder});
  @override
  ConsumerState<EmergencyMapPage> createState() => _EmergencyMapPageState();
}

class _EmergencyMapPageState extends ConsumerState<EmergencyMapPage>
    with WidgetsBindingObserver, RouteAware {
  final _sheet = DraggableScrollableController();
  final _header = GlobalKey();
  final _scaffold = GlobalKey<ScaffoldState>();
  MapCameraController? _map;
  StreamSubscription<HeadingReading>? _headingSubscription;
  Timer? _sheetSettled, _headingExpiry;
  final _headingClock = Stopwatch()..start();
  int _lastHeadingMs = -100, _fittedRevision = -1;
  double? _heading;
  double _headerBottom = 120;
  EdgeInsets _viewport = EdgeInsets.zero;
  bool _postFramePending = false;
  bool _routeVisible = true;
  bool _foreground = true;
  bool _reviewReasonOpen = false;
  Future<void>? _mapInitialization;
  EmergencyMapBuilder? _providedMap;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) appRouteObserver.subscribe(this, route);
  }

  @override
  void didPushNext() {
    if (_reviewReasonOpen) return;
    _routeVisible = false;
    ref.read(mapPersonalizationProvider.notifier).disable();
    if (reviewPreviewBuild) ref.read(reviewPreviewProvider.notifier).disable();
    _headingSubscription?.cancel();
    _headingSubscription = null;
    _headingExpiry?.cancel();
    if (mounted) setState(() => _heading = null);
  }

  @override
  void didPopNext() {
    if (_reviewReasonOpen) return;
    _routeVisible = true;
    _startHeading();
    _schedulePersonalization();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sheet.addListener(_sheetChanged);
    _providedMap = widget.mapBuilder ?? ref.read(emergencyMapBuilderProvider);
    if (_providedMap == null) {
      _mapInitialization = initializeNaverMap();
    }
    Future.microtask(() {
      ref.read(mapControllerProvider).initialize();
      _startHeading();
      _activatePersonalization();
    });
  }

  void _activatePersonalization() {
    if (!mounted || !_routeVisible || !_foreground) return;
    if (reviewPreviewBuild) {
      ref.read(mapPersonalizationProvider.notifier).disable();
    }
    final controller = reviewPreviewBuild
        ? ref.read(reviewPreviewProvider.notifier)
        : ref.read(mapPersonalizationProvider.notifier);
    controller.setSearch(ref.read(mapControllerProvider).snapshot);
    unawaited(controller.enable());
  }

  Future<void> _showPersonalizationContext() async {
    _reviewReasonOpen = true;
    var settings = false;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => Consumer(
          builder: (context, ref, _) {
            final current = reviewPreviewBuild
                ? ref.watch(reviewPreviewProvider)
                : ref.watch(mapPersonalizationProvider);
            return PersonalizationContextSheet(
              relations: current.contextRelations,
              onSettings: () {
                settings = true;
                Navigator.pop(context);
              },
            );
          },
        ),
      );
    } finally {
      _reviewReasonOpen = false;
    }
    if (settings && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              const MemberEmergencyScreen(hospitalUseSettings: true),
        ),
      );
    }
  }

  void _schedulePersonalization() {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _activatePersonalization(),
    );
  }

  void _startHeading() {
    if (!mounted || !_routeVisible) return;
    _headingSubscription?.cancel();
    try {
      _headingSubscription = ref
          .read(headingServiceProvider)
          .watch()
          .listen(
            (reading) {
              final heading = reading.usableDegrees;
              if (!mounted) return;
              // Invalid quality takes effect immediately, not after throttling.
              if (heading != null &&
                  _headingClock.elapsedMilliseconds - _lastHeadingMs < 100) {
                return;
              }
              _lastHeadingMs = _headingClock.elapsedMilliseconds;
              _headingExpiry?.cancel();
              setState(() => _heading = heading);
              _headingExpiry = Timer(const Duration(seconds: 10), () {
                if (mounted) setState(() => _heading = null);
              });
            },
            onError: (_) {
              if (mounted) setState(() => _heading = null);
            },
          );
    } catch (_) {
      _heading = null;
    }
  }

  void _sheetChanged() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
    _sheetSettled?.cancel();
    _sheetSettled = Timer(const Duration(milliseconds: 180), () {
      if (mounted) _map?.updateViewport(_viewport, settled: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    ref.read(mapPersonalizationProvider.notifier).disable();
    if (reviewPreviewBuild) ref.read(reviewPreviewProvider.notifier).disable();
    if (state == AppLifecycleState.resumed) {
      _startHeading();
      _activatePersonalization();
      final controller = ref.read(mapControllerProvider);
      if (!controller.loading &&
          !controller.locating &&
          controller.center != null) {
        controller.search();
      }
    } else {
      _headingSubscription?.cancel();
      _headingSubscription = null;
      _headingExpiry?.cancel();
      _heading = null;
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _sheetSettled?.cancel();
    _headingExpiry?.cancel();
    _headingSubscription?.cancel();
    _sheet.dispose();
    super.dispose();
  }

  void _afterLayout() {
    if (_postFramePending) return;
    _postFramePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _postFramePending = false;
      if (!mounted) return;
      final box = _header.currentContext?.findRenderObject() as RenderBox?;
      if (box != null) {
        final bottom = box.localToGlobal(Offset.zero).dy + box.size.height;
        if ((bottom - _headerBottom).abs() > 1) {
          setState(() => _headerBottom = bottom);
          return;
        }
      }
      final map = _map;
      if (map == null) return;
      await map.updateViewport(_viewport, settled: false);
      if (!mounted) return;
      final search = ref.read(mapControllerProvider).snapshot;
      if (search != null && _fittedRevision != search.revision) {
        _fittedRevision = search.revision;
        await map.fit(search);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(mapControllerProvider);
    final personal = ref.watch(mapPersonalizationProvider);
    final preview = reviewPreviewBuild
        ? ref.watch(reviewPreviewProvider)
        : const MapPersonalizationState();
    final visibleResults = {...personal.results, ...preview.results};
    final currentContext = reviewPreviewBuild ? preview : personal;
    ref.listen(sessionProvider, (old, next) {
      if (old?.userId != next.userId ||
          old?.generation != next.generation ||
          old?.authenticated != next.authenticated) {
        _schedulePersonalization();
      }
    });
    ref.listen(privacyChangeProvider, (_, next) => _schedulePersonalization());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(mapPersonalizationProvider.notifier)
            .setSearch(ref.read(mapControllerProvider).snapshot);
        if (reviewPreviewBuild) {
          ref
              .read(reviewPreviewProvider.notifier)
              .setSearch(ref.read(mapControllerProvider).snapshot);
        }
      }
    });
    final callStatus = ref.watch(emergencyCallStateProvider);
    final builder =
        _providedMap ??
        ({
          required scene,
          required onReady,
          required onCameraIdle,
          required onHospitalSelected,
        }) => FutureBuilder<void>(
          future: _mapInitialization,
          builder: (context, initialization) {
            if (initialization.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            return NaverEmergencyMapView(
              scene: scene,
              onReady: onReady,
              onCameraIdle: onCameraIdle,
              onHospitalSelected: onHospitalSelected,
            );
          },
        );
    return Scaffold(
      key: _scaffold,
      drawer: const EmergencyDrawer(),
      drawerScrimColor: const Color(0x55000000),
      body: SensitiveDisplayScope(
        enabled: personal.enabled || preview.enabled,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            final maxSize = math.min(
              .72,
              math.max(.10, (height - _headerBottom - 208) / height),
            );
            final minSize = math.min(.18, maxSize);
            final initialSize = .30.clamp(minSize, maxSize);
            final size = (_sheet.isAttached ? _sheet.size : initialSize).clamp(
              minSize,
              maxSize,
            );
            if (_sheet.isAttached && _sheet.size != size) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _sheet.isAttached) _sheet.jumpTo(size);
              });
            }
            final sheetHeight = size * height;
            _viewport = EdgeInsets.fromLTRB(
              76,
              _headerBottom + 8,
              76,
              sheetHeight + 8,
            );
            _afterLayout();
            return Stack(
              children: [
                Positioned.fill(
                  child: builder(
                    scene: MapScene(
                      search: c.snapshot,
                      initialCenter: c.center,
                      initialBounds: c.policy?.bounds,
                      user: c.userFix,
                      heading: _heading,
                      selectedHpid: c.selectedHpid,
                    ),
                    onReady: (map) {
                      _map = map;
                      _fittedRevision = -1;
                      _afterLayout();
                      setState(() {});
                    },
                    onCameraIdle: c.cameraMoved,
                    onHospitalSelected: c.select,
                  ),
                ),
                Positioned.fill(
                  child: PersonalizationOverlay(
                    controller: _map,
                    search: c.snapshot,
                    accents: const {},
                    ringIds: {
                      for (final e in visibleResults.entries)
                        if (personalizationRingEligible(
                          e.value,
                          previewAllowed: reviewPreviewBuild,
                        ))
                          e.key,
                    },
                    selectedHpid: c.selectedHpid,
                    insets: _viewport,
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Column(
                      key: _header,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Material(
                          color: Theme.of(context).colorScheme.surface,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 5,
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  tooltip: '메뉴 열기',
                                  onPressed: () =>
                                      _scaffold.currentState?.openDrawer(),
                                  icon: const Icon(Icons.menu),
                                ),
                                IconButton(
                                  tooltip: '뒤로 가기',
                                  onPressed: () => Navigator.maybePop(context),
                                  icon: const Icon(Icons.arrow_back_rounded),
                                ),
                                Expanded(
                                  child: Text(
                                    c.locating
                                        ? '현재 위치를 확인하고 있습니다'
                                        : c.loading
                                        ? '주변 응급의료기관을 검색하고 있습니다'
                                        : c.snapshot?.source == 'MANUAL'
                                        ? '선택한 위치에서 주변 병원 검색'
                                        : '현재 위치에서 주변 병원 검색',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: ERouteTypography.label.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: '병원 정보 새로고침',
                                  onPressed: c.loading
                                      ? null
                                      : (c.center == null
                                            ? c.initialize
                                            : c.search),
                                  icon: const Icon(Icons.refresh),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (c.policy != null)
                          Padding(
                            padding: const EdgeInsets.only(
                              top: ERouteSpacing.xs,
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: c.policy!.radii.map((radius) {
                                    final selected =
                                        c.requestedRadiusMeters == radius;
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        right: ERouteSpacing.xs,
                                      ),
                                      child: ChoiceChip(
                                        label: Text('${radius ~/ 1000}km'),
                                        selected: selected,
                                        onSelected: c.loading
                                            ? null
                                            : (_) => c.selectRadius(radius),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ),
                        if (currentContext.contextRelations.isNotEmpty)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: PersonalizationCategoryButton(
                              key: const ValueKey('personalization-context'),
                              diseaseIds: currentContext.contextRelations.map(
                                (r) => r.mapping.diseaseId,
                              ),
                              onPressed: _showPersonalizationContext,
                              label: personalizationContextLabel(
                                currentContext.contextRelations,
                              ),
                            ),
                          ),
                        if (c.snapshot != null &&
                            c.requestedRadiusMeters != null &&
                            c.snapshot!.result.radius !=
                                c.requestedRadiusMeters)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(
                                top: ERouteSpacing.xs,
                              ),
                              child: Material(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(
                                  ERouteRadius.control,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: ERouteSpacing.sm,
                                    vertical: ERouteSpacing.xs,
                                  ),
                                  child: Text(
                                    '실제 검색 반경 ${c.snapshot!.result.radius ~/ 1000}km · 검색 범위 확대',
                                    style: ERouteTypography.label,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (c.message != null || c.error != null)
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              c.error ?? c.message!,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        if (c.pendingCenter != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: FilledButton.icon(
                              onPressed: c.loading ? null : c.searchHere,
                              icon: const Icon(Icons.search, size: 18),
                              label: const Text('이 위치에서 검색'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                HospitalSheet(
                  state: c,
                  personalization: visibleResults,
                  onReviewReason: (hpid) async {
                    final isPreview = reviewPreviewBuild && preview.enabled;
                    _reviewReasonOpen = true;
                    try {
                      await showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        showDragHandle: true,
                        builder: (_) => Consumer(
                          builder: (context, ref, _) {
                            final current = isPreview && reviewPreviewBuild
                                ? ref.watch(reviewPreviewProvider)
                                : ref.watch(mapPersonalizationProvider);
                            return PersonalizationReasonSheet(
                              result: current.results[hpid],
                            );
                          },
                        ),
                      );
                    } finally {
                      _reviewReasonOpen = false;
                    }
                  },
                  controller: _sheet,
                  minSize: minSize,
                  maxSize: maxSize,
                  initialSize: initialSize,
                  onHospitalTap: (hpid) =>
                      pushAppRoute(context, AppRoutes.hospital(hpid)),
                ),
                Positioned(
                  right: 12,
                  bottom: sheetHeight + 12,
                  child: MapControls(
                    locating: c.locating,
                    locate: c.locate,
                    zoomIn: _map == null ? null : () => _map!.zoomBy(1),
                    zoomOut: _map == null ? null : () => _map!.zoomBy(-1),
                  ),
                ),
                Positioned(
                  left: 12,
                  bottom: sheetHeight + 12,
                  child: FloatingActionButton(
                    heroTag: 'emergency-119',
                    tooltip: '119 신고',
                    backgroundColor: context.eroute.emergency,
                    foregroundColor: context.eroute.onEmergency,
                    elevation: 0,
                    focusElevation: 0,
                    hoverElevation: 0,
                    highlightElevation: 0,
                    onPressed: callStatus == EmergencyCallStatus.idle
                        ? () => ref.read(emergencyCallProvider).confirm(context)
                        : null,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (MediaQuery.textScalerOf(context).scale(14) <= 21)
                          const Icon(Icons.call, size: 20),
                        const Text(
                          '119',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
