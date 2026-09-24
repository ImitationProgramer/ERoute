import 'hospital_marker_clusterer.dart';
import 'hospital_cluster_marker.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import '../config/app_config.dart';
import '../../features/emergency_map/domain/hospital_summary.dart';
import 'map_scene.dart';
import 'map_camera_controller.dart';
import 'camera_fit_geometry.dart';
import 'map_marker_icons.dart';
import 'marker_label_layout.dart';
import 'selected_hospital_label.dart';

final mapAuthenticationError = ValueNotifier<bool>(false);
Future<void>? _initialization;
Future<void> initializeNaverMap() => _initialization ??= _initializeNaverMap();
Future<void> _initializeNaverMap() async {
  if (AppConfig.mapClientId.isEmpty) return;
  try {
    await FlutterNaverMap().init(
      clientId: AppConfig.mapClientId,
      onAuthFailed: (_) => mapAuthenticationError.value = true,
    );
  } catch (_) {
    mapAuthenticationError.value = true;
  }
}

class NaverEmergencyMapView extends StatefulWidget {
  final MapScene scene;
  final ValueChanged<MapCameraController> onReady;
  final ValueChanged<MapCameraEvent> onCameraIdle;
  final ValueChanged<String> onHospitalSelected;
  const NaverEmergencyMapView({
    super.key,
    required this.scene,
    required this.onReady,
    required this.onCameraIdle,
    required this.onHospitalSelected,
  });
  @override
  State<NaverEmergencyMapView> createState() => _NaverEmergencyMapViewState();
}

class _NaverEmergencyMapViewState extends State<NaverEmergencyMapView>
    implements MapCameraController, MapProjectionEvents, MapOverlayGeometry {
  @override
  final ValueNotifier<List<Rect>?> overlayExclusionRects = ValueNotifier(null);
  @override
  final ValueNotifier<Set<String>?> renderedHospitalIds = ValueNotifier(null);
  @override
  final ValueNotifier<int> projectionRevision = ValueNotifier<int>(0);
  @override
  final ValueNotifier<bool> cameraMoving = ValueNotifier<bool>(false);
  NaverMapController? _map;
  final Map<String, NMarker> _markers = {};
  final Map<String, NMarker> _clusterMarkers = {};
  HospitalClusterPlan _clusterPlan = const HospitalClusterPlan({}, []);
  Map<String, Offset> _projectedHospitals = {};
  Map<String, Rect> _clusterRects = {};
  List<Rect> _labelRects = [];
  bool _clusterDirty = true, _themeDirty = true;
  int _geometryGeneration = 0;
  @visibleForTesting
  HospitalClusterPlan get debugClusterPlan => _clusterPlan;
  @visibleForTesting
  Map<String, NMarker> get debugClusterMarkers =>
      Map.unmodifiable(_clusterMarkers);
  @visibleForTesting
  Future<void> debugExpandCluster(String id) => _expandCluster(id);

  NCircleOverlay? _circle;
  NMarker? _manual;
  EdgeInsets _insets = EdgeInsets.zero;
  CameraMoveOrigin _origin = CameraMoveOrigin.programmaticLayout;
  bool _exploring = false, _syncing = false, _dirty = false;
  int _command = 0;
  int? _renderedRevision;
  String? _renderedSelection;
  bool _rendered = false;
  int _labelGeneration = 0;
  Timer? _labelTimer;
  Rect? _chipRect;
  String? _chipHpid;
  final Map<String, HospitalSummary> _hospitals = {};
  @visibleForTesting
  Map<String, NMarker> get debugHospitalMarkers => Map.unmodifiable(_markers);
  @visibleForTesting
  EdgeInsets get debugViewportInsets => _insets;
  NLatLng _point(GeoPoint p) => NLatLng(p.latitude, p.longitude);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _themeDirty = true;
    unawaited(_sync());
    _scheduleLabel();
  }

  @override
  void didUpdateWidget(covariant NaverEmergencyMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scene.search?.revision != widget.scene.search?.revision &&
        widget.scene.search != null) {
      _exploring = false;
    }
    if (oldWidget.scene.selectedHpid != widget.scene.selectedHpid ||
        oldWidget.scene.search?.revision != widget.scene.search?.revision) {
      _geometryGeneration++;
      _clusterDirty = true;
    }
    _sync();
    if (oldWidget.scene.selectedHpid != widget.scene.selectedHpid ||
        oldWidget.scene.search?.revision != widget.scene.search?.revision ||
        oldWidget.scene.user?.point != widget.scene.user?.point) {
      _scheduleLabel();
    }
  }

  Future<void> _sync() async {
    _dirty = true;
    if (_syncing || _map == null) return;
    _syncing = true;
    try {
      while (_dirty && mounted) {
        _dirty = false;
        final scene = widget.scene;
        final map = _map!;
        final searchChanged =
            !_rendered || _renderedRevision != scene.search?.revision;
        if (searchChanged ||
            _renderedSelection != scene.selectedHpid ||
            (_clusterDirty && !cameraMoving.value) ||
            _themeDirty) {
          renderedHospitalIds.value = null;
          final hospitals =
              scene.search?.result.hospitals ?? <HospitalSummary>[];
          final allIds = hospitals.map((h) => h.hpid).toSet();
          final geometryGeneration = _geometryGeneration;
          if (searchChanged) _projectedHospitals = {};
          if (!cameraMoving.value && (_clusterDirty || searchChanged)) {
            final projected = await Future.wait(
              hospitals.map(
                (h) async => MapEntry(h.hpid, await project(h.location)),
              ),
            );
            if (!mounted) return;
            if (geometryGeneration != _geometryGeneration) {
              _dirty = !cameraMoving.value;
              continue;
            }
            _projectedHospitals = Map.fromEntries(projected);
            _clusterDirty = false;
          }
          // New results during camera motion initially render as individual
          // markers; the first idle groups them. Old-result clusters are removed.
          final plan = _projectedHospitals.keys.toSet().containsAll(allIds)
              ? const HospitalMarkerClusterer().group(
                  _projectedHospitals,
                  selectedHpid: scene.selectedHpid,
                )
              : HospitalClusterPlan(allIds, const []);
          final ids = plan.individualIds;
          final newIds = ids.difference(_markers.keys.toSet());
          if (searchChanged) {
            _hospitals
              ..clear()
              ..addEntries(hospitals.map((h) => MapEntry(h.hpid, h)));
          }
          for (final id
              in _markers.keys.where((id) => !ids.contains(id)).toList()) {
            await map.deleteOverlay(_markers.remove(id)!.info);
          }
          final changedIds = hospitalMarkersToUpdate(
            hospitalIds: ids,
            searchChanged: searchChanged,
            previous: _renderedSelection,
            selected: scene.selectedHpid,
          );
          for (final id in {...changedIds, ...newIds}) {
            final hospital = _hospitals[id]!;
            final selected = hospital.hpid == scene.selectedHpid;
            final icon = await MapMarkerIcons.get(
              selected ? 'selected' : 'hospital',
            );
            if (!mounted) return;
            final marker = _markers[hospital.hpid];
            if (marker == null) {
              final added = NMarker(
                id: 'hospital:${hospital.hpid}',
                position: _point(hospital.location),
                icon: icon,
                size: Size.square(HospitalMarkerGeometry.size(selected)),
                anchor: const NPoint(.5, .5),
                caption: const NOverlayCaption(text: ''),
                captionOffset: 8,
              );
              added.setOnTapListener(
                (_) => widget.onHospitalSelected(hospital.hpid),
              );
              added.setZIndex(selected ? 10 : 1);
              _markers[hospital.hpid] = added;
              await map.addOverlay(added);
            } else {
              if (marker.position != _point(hospital.location)) {
                marker.setPosition(_point(hospital.location));
              }
              if (marker.icon != icon) marker.setIcon(icon);
              final size = Size.square(HospitalMarkerGeometry.size(selected));
              if (marker.size != size) marker.setSize(size);
              marker.setZIndex(selected ? 10 : 1);
              // The layout pass installs only a safely placed selected caption.
              if (!selected || (marker.caption?.text.isNotEmpty ?? false)) {
                // 1.4.4's Android handler force-unwraps caption arguments even
                // though the Dart API accepts null. Empty text hides it safely.
                marker.setCaption(const NOverlayCaption(text: ''));
              }
            }
          }
          await _syncClusterMarkers(plan);
          if (!mounted) return;
          _clusterPlan = plan;
          _themeDirty = false;
          if (searchChanged) {
            final search = scene.search;
            if (search == null) {
              if (_circle != null) await map.deleteOverlay(_circle!.info);
              _circle = null;
            } else if (_circle == null) {
              _circle = NCircleOverlay(
                id: 'search:radius',
                center: _point(search.center),
                radius: search.result.radius.toDouble(),
                color: const Color(0x20244e86),
                outlineColor: const Color(0xbb244e86),
                outlineWidth: 1.5,
              );
              await map.addOverlay(_circle!);
            } else {
              _circle!.setCenter(_point(search.center));
              _circle!.setRadius(search.result.radius.toDouble());
            }
            if (search?.source == 'MANUAL') {
              if (_manual == null) {
                _manual = NMarker(
                  id: 'search:center',
                  position: _point(search!.center),
                  icon: await MapMarkerIcons.get('manual'),
                  size: const Size.square(34),
                  caption: const NOverlayCaption(text: '검색 중심'),
                );
                await map.addOverlay(_manual!);
              } else {
                _manual!.setPosition(_point(search!.center));
              }
            } else if (_manual != null) {
              await map.deleteOverlay(_manual!.info);
              _manual = null;
            }
          }
          _renderedRevision = scene.search?.revision;
          _renderedSelection = scene.selectedHpid;
          _rendered = true;
          if (geometryGeneration == _geometryGeneration) {
            renderedHospitalIds.value = Set.unmodifiable(_markers.keys);
          } else {
            _dirty = true;
          }
          _scheduleLabel();
        }
        final location = map.getLocationOverlay();
        location.setIsVisible(scene.user != null);
        if (scene.user != null) {
          location.setPosition(_point(scene.user!.point));
          location.setCircleRadius(scene.user!.accuracyMeters ?? 0);
          location.setCircleColor(const Color(0x242478e8));
          location.setIcon(
            await MapMarkerIcons.get(scene.heading == null ? 'dot' : 'arrow'),
          );
          location.setIconSize(const Size.square(32));
          location.setSubIcon(null);
          location.setBearing(scene.heading ?? 0);
        }
      }
    } catch (_) {
      // A disposed/unavailable native map must not affect search or emergency UI.
    } finally {
      _syncing = false;
    }
  }

  GeoPoint _clusterCenter(MarkerCluster cluster) {
    final points = cluster.hospitalIds
        .map((id) => _hospitals[id]!.location)
        .toList();
    return GeoPoint(
      points.fold(0.0, (v, p) => v + p.latitude) / points.length,
      points.fold(0.0, (v, p) => v + p.longitude) / points.length,
    );
  }

  Future<void> _syncClusterMarkers(HospitalClusterPlan plan) async {
    final map = _map!;
    final desired = {for (final c in plan.clusters) c.id: c};
    for (final id
        in _clusterMarkers.keys
            .where((id) => !desired.containsKey(id))
            .toList()) {
      await map.deleteOverlay(_clusterMarkers.remove(id)!.info);
    }
    for (final c in plan.clusters) {
      if (!mounted) return;
      final point = _point(_clusterCenter(c));
      final icon = await MapMarkerIcons.cluster(
        c.count,
        dark: Theme.of(context).brightness == Brightness.dark,
      );
      if (!mounted) return;
      final marker = _clusterMarkers[c.id];
      if (marker == null) {
        final added = NMarker(
          id: 'cluster:${c.id}',
          position: point,
          icon: icon,
          size: HospitalClusterGeometry.size(c.count),
          anchor: const NPoint(.5, .5),
        );
        added.setZIndex(0); // selected and individual hospital symbols win.
        added.setOnTapListener((_) => _expandCluster(c.id));
        _clusterMarkers[c.id] = added;
        await map.addOverlay(added);
      } else {
        if (marker.position != point) marker.setPosition(point);
        if (marker.icon != icon) marker.setIcon(icon);
      }
    }
  }

  Future<void> _expandCluster(String id) async {
    final matches = _clusterPlan.clusters.where((c) => c.id == id);
    if (matches.isEmpty || _map == null || cameraMoving.value || _syncing) {
      return;
    }
    final cluster = matches.single;
    final bounds = clusterBounds(
      cluster.hospitalIds.map((id) => _hospitals[id]!.location),
    );
    _exploring = true;
    if (bounds.southWest.latitude == bounds.northEast.latitude &&
        bounds.southWest.longitude == bounds.northEast.longitude) {
      // Identical coordinates have no extent to fit. They remain an honest count.
      await zoomBy(2);
    } else {
      await _camera(
        NCameraUpdate.fitBounds(
          NLatLngBounds(
            southWest: _point(bounds.southWest),
            northEast: _point(bounds.northEast),
          ),
          padding:
              _insets + const EdgeInsets.all(HospitalClusterGeometry.radius),
        ),
        CameraMoveOrigin.userZoomControl,
      );
    }
  }

  void _publishExclusions() {
    overlayExclusionRects.value = [..._labelRects, ..._clusterRects.values];
  }

  Future<void> _layoutClusters(int generation) async {
    if (cameraMoving.value) return;
    final rects = <String, Rect>{};
    for (final c in _clusterPlan.clusters) {
      final point = await project(_clusterCenter(c));
      if (!mounted || generation != _labelGeneration || cameraMoving.value) {
        return;
      }
      final size = HospitalClusterGeometry.size(c.count);
      rects[c.id] = Rect.fromCenter(
        center: point,
        width: size.width,
        height: size.height,
      );
    }
    if (mounted && generation == _labelGeneration) {
      setState(() => _clusterRects = rects);
    }
  }

  @override
  void dispose() {
    overlayExclusionRects.dispose();
    renderedHospitalIds.dispose();
    projectionRevision.dispose();
    cameraMoving.dispose();
    _labelGeneration++;
    _labelTimer?.cancel();
    super.dispose();
  }

  // Coalesce camera callbacks, but invalidate in-flight projection immediately.
  void _scheduleLabel() {
    overlayExclusionRects.value = null;
    _labelGeneration++;
    _labelTimer ??= Timer(const Duration(milliseconds: 50), () {
      _labelTimer = null;
      _layoutLabel();
    });
  }

  Future<void> _layoutLabel() async {
    if (!mounted || _map == null) return;
    final generation = _labelGeneration;
    try {
      await _layoutClusters(generation);
    } catch (_) {
      return;
    }
    if (!mounted || generation != _labelGeneration) return;
    final hpid = widget.scene.selectedHpid;
    final hospital = _hospitals[hpid];
    final marker = _markers[hpid];
    if (hospital == null || marker == null) {
      _labelRects = const [];
      _publishExclusions();
      if (_chipRect != null) {
        setState(() {
          _chipRect = null;
          _chipHpid = null;
        });
      }
      return;
    }
    try {
      final position = await project(hospital.location);
      final user = widget.scene.user;
      final userPosition = user == null ? null : await project(user.point);
      if (!mounted ||
          generation != _labelGeneration ||
          hpid != widget.scene.selectedHpid ||
          !identical(marker, _markers[hpid])) {
        return;
      }
      final size = context.size!;
      final viewport = Rect.fromLTRB(
        _insets.left,
        _insets.top,
        size.width - _insets.right,
        size.height - _insets.bottom,
      );
      // Native font metrics vary. Reserve halo/font slack; use the chip when
      // the whole single-line name cannot fit in the usable viewport.
      final textSize = MediaQuery.textScalerOf(context).scale(13);
      final painter = TextPainter(
        text: TextSpan(
          text: hospital.name,
          style: TextStyle(fontSize: textSize),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final captionSize = Size(painter.width + 24, painter.height + 16);
      painter.dispose();
      final layout = layoutSelectedHospitalLabel(
        viewport: viewport,
        marker: position,
        captionSize: captionSize,
        chipHeight: textSize + 24 > 48 ? textSize + 24 : 48,
        obstacles: [
          if (userPosition != null)
            Rect.fromCircle(center: userPosition, radius: 24),
        ],
      );
      final caption = layout.caption == null
          ? const NOverlayCaption(text: '')
          : NOverlayCaption(
              text: hospital.name,
              textSize: textSize,
              color: Theme.of(context).colorScheme.onSurface,
              haloColor: Theme.of(context).colorScheme.surface,
            );
      if ((marker.caption?.text ?? '') != caption.text ||
          (caption.text.isNotEmpty &&
              (marker.caption?.textSize != caption.textSize ||
                  marker.caption?.color != caption.color))) {
        marker.setCaption(caption);
      }
      _labelRects = [
        if (layout.caption != null) layout.caption!,
        if (layout.chip != null) layout.chip!,
      ];
      _publishExclusions();
      if (_chipRect != layout.chip || _chipHpid != hpid) {
        setState(() {
          _chipRect = layout.chip;
          _chipHpid = hpid;
        });
      }
    } catch (_) {
      // A native map may be disposed while an async projection is pending.
    }
  }

  Future<void> _camera(NCameraUpdate update, CameraMoveOrigin origin) async {
    if (_map == null || !mounted) return;
    _command++;
    _origin = origin;
    update.setAnimation(
      animation: NCameraAnimation.easing,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 300),
    );
    try {
      await _map!.updateCamera(update);
    } catch (_) {}
  }

  @override
  Future<void> fit(SearchPresentationSnapshot snapshot) async {
    if (!mounted || widget.scene.search?.revision != snapshot.revision) return;
    _exploring = false;
    final bounds = fitBoundsFor(snapshot);
    await _camera(
      NCameraUpdate.withParams(bearing: 0, tilt: 0),
      CameraMoveOrigin.programmaticFit,
    );
    if (!mounted ||
        _exploring ||
        widget.scene.search?.revision != snapshot.revision) {
      return;
    }
    // One padding application. Keeping native contentPadding zero prevents inset
    // changes from moving the camera while the user is exploring.
    await _camera(
      NCameraUpdate.fitBounds(
        NLatLngBounds(
          southWest: _point(bounds.southWest),
          northEast: _point(bounds.northEast),
        ),
        padding: _insets + const EdgeInsets.all(28),
      ),
      CameraMoveOrigin.programmaticFit,
    );
  }

  @override
  Future<void> moveToCurrentLocation(GeoPoint point) => _camera(
    NCameraUpdate.scrollAndZoomTo(target: _point(point)),
    CameraMoveOrigin.programmaticCurrentLocation,
  );
  @override
  Future<Offset> project(GeoPoint point) async {
    final projected = await _map!.latLngToScreenLocation(_point(point));
    return Offset(projected.x, projected.y);
  }

  @override
  Future<void> zoomBy(double delta) async {
    _exploring = true;
    final size = context.size!;
    final pivot = _viewportCenter(size);
    final update = NCameraUpdate.zoomBy(delta)
      ..setPivot(NPoint(pivot.dx / size.width, pivot.dy / size.height));
    await _camera(update, CameraMoveOrigin.userZoomControl);
  }

  Offset _viewportCenter(Size size) => Offset(
    (_insets.left + size.width - _insets.right) / 2,
    (_insets.top + size.height - _insets.bottom) / 2,
  );

  @override
  Future<void> updateViewport(
    EdgeInsets insets, {
    required bool settled,
  }) async {
    final changed = _insets != insets;
    _insets = insets;
    if (changed && mounted) {
      setState(
        () {},
      ); // Reposition SDK attribution, without altering native camera.
      _scheduleLabel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scene = widget.scene;
    if (AppConfig.mapClientId.isEmpty) {
      return const ColoredBox(
        color: Color(0xffe9efea),
        child: Center(
          child: Text(
            '지도를 연결할 수 없습니다.\n병원 목록과 119 기능을 이용해주세요.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final bounds = scene.initialBounds;
    final initial =
        scene.search?.center ??
        scene.initialCenter ??
        (bounds == null
            ? null
            : GeoPoint(
                (bounds.southWest.latitude + bounds.northEast.latitude) / 2,
                (bounds.southWest.longitude + bounds.northEast.longitude) / 2,
              ));
    if (initial == null) return const Center(child: Text('지도 정보를 준비하고 있습니다.'));
    return ValueListenableBuilder(
      valueListenable: mapAuthenticationError,
      builder: (context, failed, _) {
        if (failed) {
          return const Center(child: Text('지도를 불러오지 못했습니다. 병원 목록을 이용해주세요.'));
        }
        return Stack(
          children: [
            Positioned.fill(
              child: NaverMap(
                options: NaverMapViewOptions(
                  initialCameraPosition: NCameraPosition(
                    target: _point(initial),
                    zoom: 6,
                  ),
                  locationButtonEnable: false,
                  // SDK 1.4.4's fixed-height scale bar overflows large text.
                  // Radius and card distances remain fully scalable app text.
                  scaleBarEnable:
                      MediaQuery.textScalerOf(context).scale(12) <= 18,
                  indoorEnable: false,
                  nightModeEnable:
                      Theme.of(context).brightness == Brightness.dark,
                  logoMargin: EdgeInsets.only(
                    left: 8,
                    bottom: _insets.bottom + 8,
                  ),
                ),
                onMapReady: (map) async {
                  if (!identical(_map, map)) {
                    _labelGeneration++;
                    _markers.clear();
                    _clusterMarkers.clear();
                    _clusterPlan = const HospitalClusterPlan({}, []);
                    _clusterRects = {};
                    _projectedHospitals = {};
                    _clusterDirty = true;
                    _hospitals.clear();
                    _circle = null;
                    _manual = null;
                    _rendered = false;
                    _renderedSelection = null;
                    _chipRect = null;
                    _chipHpid = null;
                  }
                  _map = map;
                  widget.onReady(this);
                  await _sync();
                  if (mounted) projectionRevision.value++;
                  if (widget.scene.search == null && bounds != null) {
                    await _camera(
                      NCameraUpdate.fitBounds(
                        NLatLngBounds(
                          southWest: _point(bounds.southWest),
                          northEast: _point(bounds.northEast),
                        ),
                        padding: _insets + const EdgeInsets.all(28),
                      ),
                      CameraMoveOrigin.programmaticLayout,
                    );
                  }
                },
                onCameraChange: (reason, animated) {
                  _geometryGeneration++;
                  cameraMoving.value = true;
                  _scheduleLabel();
                  if (reason == NCameraUpdateReason.gesture ||
                      reason == NCameraUpdateReason.control) {
                    _command++;
                    _exploring = true;
                    _origin = CameraMoveOrigin.userGesture;
                  }
                },
                onCameraIdle: () async {
                  cameraMoving.value = false;
                  _clusterDirty = true;
                  unawaited(_sync());
                  projectionRevision.value++;
                  _scheduleLabel();
                  final command = _command;
                  final origin = _origin;
                  final midpoint = _viewportCenter(context.size!);
                  final position = await _map?.screenLocationToLatLng(
                    NPoint(midpoint.dx, midpoint.dy),
                  );
                  if (mounted && position != null && command == _command) {
                    widget.onCameraIdle(
                      MapCameraEvent(
                        GeoPoint(position.latitude, position.longitude),
                        origin,
                      ),
                    );
                  }
                },
              ),
            ),
            Positioned.fill(
              child: ValueListenableBuilder<bool>(
                valueListenable: cameraMoving,
                builder: (context, moving, _) => LayoutBuilder(
                  builder: (context, constraints) {
                    final viewport = Rect.fromLTRB(
                      _insets.left,
                      _insets.top,
                      constraints.maxWidth - _insets.right,
                      constraints.maxHeight - _insets.bottom,
                    );
                    return Stack(
                      children: [
                        if (!moving)
                          for (final c in _clusterPlan.clusters)
                            if (_clusterRects[c.id] case final Rect rect)
                              if (viewport.contains(rect.topLeft) &&
                                  viewport.contains(rect.bottomRight))
                                Positioned.fromRect(
                                  rect: rect,
                                  child: HospitalClusterTarget(
                                    key: ValueKey('hospital-cluster:${c.id}'),
                                    count: c.count,
                                    // Keep accessibility actions even where a
                                    // selected marker must receive touch first.
                                    pointerEnabled:
                                        !_labelRects.any(
                                          (r) => r.overlaps(rect),
                                        ) &&
                                        !_markers.keys.any(
                                          (id) =>
                                              _projectedHospitals[id] != null &&
                                              rect.overlaps(
                                                Rect.fromCircle(
                                                  center:
                                                      _projectedHospitals[id]!,
                                                  radius:
                                                      HospitalMarkerGeometry.visibleRadius(
                                                        id ==
                                                            scene.selectedHpid,
                                                      ),
                                                ),
                                              ),
                                        ),
                                    onTap: () => _expandCluster(c.id),
                                  ),
                                ),
                      ],
                    );
                  },
                ),
              ),
            ),
            if (_chipRect != null &&
                _chipHpid == scene.selectedHpid &&
                _hospitals[_chipHpid] != null)
              Positioned.fromRect(
                rect: _chipRect!,
                child: SelectedHospitalLabel(
                  name: _hospitals[_chipHpid]!.name,
                  onTap: () => widget.onHospitalSelected(_chipHpid!),
                ),
              ),
          ],
        );
      },
    );
  }
}
