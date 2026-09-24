import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../core/map/map_camera_controller.dart';
import '../../core/map/map_scene.dart';
import '../../core/theme/eroute_tokens.dart';
import 'personalization_presentation.dart';

Color personalizationGold(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? ERouteColors.personalizationGoldDark
    : ERouteColors.personalizationGoldLight;

/// Paint bounds use the icon's visible circle, excluding transparent image padding.
/// Equal-z overlapping markers have no guaranteed topmost owner: suppress their
/// badges conservatively. The selected marker has the SDK's explicit higher z.
Set<String> visibleHospitalMarkers({
  required Map<String, Offset> points,
  required String? selectedHpid,
  required Rect viewport,
  List<Rect> obstacles = const [],
  Set<String>? renderedIds,
}) {
  bool fits(Rect rect) =>
      viewport.contains(rect.topLeft) &&
      rect.right <= viewport.right &&
      rect.bottom <= viewport.bottom;
  return {
    for (final e in points.entries)
      if ((renderedIds == null || renderedIds.contains(e.key)) &&
          fits(
            Rect.fromCircle(
              center: e.value,
              radius: HospitalMarkerGeometry.visibleRadius(
                e.key == selectedHpid,
              ),
            ),
          ) &&
          !obstacles.any(
            (r) => r.overlaps(
              Rect.fromCircle(
                center: e.value,
                radius: HospitalMarkerGeometry.visibleRadius(
                  e.key == selectedHpid,
                ),
              ),
            ),
          ) &&
          (e.key == selectedHpid ||
              !points.entries.any(
                (other) =>
                    other.key != e.key &&
                    (renderedIds == null || renderedIds.contains(other.key)) &&
                    (other.value - e.value).distance <
                        HospitalMarkerGeometry.visibleRadius(
                              e.key == selectedHpid,
                            ) +
                            HospitalMarkerGeometry.visibleRadius(
                              other.key == selectedHpid,
                            ),
              )))
        e.key,
  };
}

/// Geometry only: one 8dp badge overlaps its owner's circular rim by 2dp at NE.
/// Never changes a match, marker order or selection to make room for a badge.
Map<String, Rect> layoutPersonalizationAccents({
  required Map<String, Offset> points,
  required Set<String> eligible,
  required String? selectedHpid,
  required Rect viewport,
  List<Rect> obstacles = const [],
  Set<String>? renderedIds,
}) {
  final visible = visibleHospitalMarkers(
    points: points,
    selectedHpid: selectedHpid,
    viewport: viewport,
    obstacles: obstacles,
    renderedIds: renderedIds,
  );
  final candidates = <String, Rect>{};
  for (final id in eligible.intersection(visible)) {
    final radius = HospitalMarkerGeometry.visibleRadius(id == selectedHpid);
    final offset = (radius + 2) / math.sqrt2;
    final dot = Rect.fromCircle(
      center: points[id]! + Offset(offset, -offset),
      radius: 4,
    );
    if (!viewport.contains(dot.topLeft) ||
        dot.right > viewport.right ||
        dot.bottom > viewport.bottom ||
        obstacles.any(dot.overlaps) ||
        points.entries.any(
          (other) =>
              other.key != id &&
              (renderedIds == null || renderedIds.contains(other.key)) &&
              // Keep the badge clear of every other visible marker footprint.
              dot.overlaps(
                Rect.fromCircle(
                  center: other.value,
                  radius: HospitalMarkerGeometry.visibleRadius(
                    other.key == selectedHpid,
                  ),
                ),
              ),
        )) {
      continue;
    }
    candidates[id] = dot;
  }
  return {
    for (final e in candidates.entries)
      if (!candidates.entries.any(
        (other) => other.key != e.key && e.value.overlaps(other.value),
      ))
        e.key: e.value,
  };
}

/// Secondary outline around the existing native circle; never covers its fill.
Map<String, Rect> layoutPersonalizationRings({
  required Map<String, Offset> points,
  required Set<String> eligible,
  required String? selectedHpid,
  required Rect viewport,
  List<Rect> obstacles = const [],
  Set<String>? renderedIds,
}) {
  final visible = visibleHospitalMarkers(
    points: points,
    selectedHpid: selectedHpid,
    viewport: viewport,
    obstacles: obstacles,
    renderedIds: renderedIds,
  );
  final rings = <String, Rect>{};
  for (final id in eligible.intersection(visible)) {
    final rect = Rect.fromCircle(
      center: points[id]!,
      radius: HospitalMarkerGeometry.visibleRadius(id == selectedHpid) + 5,
    );
    if (!viewport.contains(rect.topLeft) ||
        rect.right > viewport.right ||
        rect.bottom > viewport.bottom ||
        obstacles.any(rect.overlaps) ||
        points.entries.any(
          (other) =>
              other.key != id &&
              (renderedIds == null || renderedIds.contains(other.key)) &&
              rect.overlaps(
                Rect.fromCircle(
                  center: other.value,
                  radius: HospitalMarkerGeometry.visibleRadius(
                    other.key == selectedHpid,
                  ),
                ),
              ),
        )) {
      continue;
    }
    rings[id] = rect;
  }
  return {
    for (final e in rings.entries)
      if (!rings.entries.any(
        (other) => other.key != e.key && e.value.overlaps(other.value),
      ))
        e.key: e.value,
  };
}

/// Flutter-only paint. The SDK receives all public coordinates, never match flags.
class PersonalizationOverlay extends StatefulWidget {
  final MapCameraController? controller;
  final SearchPresentationSnapshot? search;
  final Map<String, PersonalizationAccent> accents;
  final String? selectedHpid;
  final Set<String> ringIds;
  final EdgeInsets insets;
  final List<Rect> obstacles;
  const PersonalizationOverlay({
    super.key,
    required this.controller,
    required this.search,
    required this.accents,
    required this.selectedHpid,
    required this.insets,
    this.obstacles = const [],
    this.ringIds = const {},
  });
  @override
  State<PersonalizationOverlay> createState() => _PersonalizationOverlayState();
}

class _PersonalizationOverlayState extends State<PersonalizationOverlay> {
  Map<String, Offset> points = {};
  int generation = 0;
  MapProjectionEvents? events;
  MapOverlayGeometry? geometry;
  bool get moving => events?.cameraMoving.value ?? false;
  void bind() {
    final c = widget.controller;
    events = c is MapProjectionEvents ? c as MapProjectionEvents : null;
    geometry = c is MapOverlayGeometry ? c as MapOverlayGeometry : null;
    events?.projectionRevision.addListener(changed);
    events?.cameraMoving.addListener(changed);
    geometry?.overlayExclusionRects.addListener(geometryChanged);
    geometry?.renderedHospitalIds.addListener(geometryChanged);
  }

  void unbind() {
    events?.projectionRevision.removeListener(changed);
    events?.cameraMoving.removeListener(changed);
    geometry?.overlayExclusionRects.removeListener(geometryChanged);
    geometry?.renderedHospitalIds.removeListener(geometryChanged);
  }

  void geometryChanged() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    bind();
    unawaited(project());
  }

  @override
  void didUpdateWidget(covariant PersonalizationOverlay old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      unbind();
      bind();
    }
    if (old.controller != widget.controller ||
        old.search?.revision != widget.search?.revision ||
        old.insets != widget.insets) {
      points = {};
      unawaited(project());
    }
  }

  void changed() {
    if (mounted) {
      setState(() => points = {});
      unawaited(project());
    }
  }

  Future<void> project() async {
    final ticket = ++generation, c = widget.controller, search = widget.search;
    if (c == null || search == null || moving) return;
    try {
      final values = await Future.wait(
        search.result.hospitals.map(
          (h) async => MapEntry(h.hpid, await c.project(h.location)),
        ),
      );
      if (mounted && ticket == generation && !moving) {
        setState(() => points = Map.fromEntries(values));
      }
    } catch (_) {
      if (mounted && ticket == generation) setState(() => points = {});
    }
  }

  @override
  void dispose() {
    generation++;
    unbind();
    points.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, size) {
          final rects =
              moving ||
                  (geometry != null &&
                      (geometry!.overlayExclusionRects.value == null ||
                          geometry!.renderedHospitalIds.value == null))
              ? <String, Rect>{}
              : layoutPersonalizationAccents(
                  points: points,
                  renderedIds: geometry?.renderedHospitalIds.value,
                  eligible: widget.accents.entries
                      .where((e) => e.value != PersonalizationAccent.none)
                      .map((e) => e.key)
                      .toSet(),
                  selectedHpid: widget.selectedHpid,
                  viewport: Rect.fromLTRB(
                    widget.insets.left,
                    widget.insets.top,
                    size.maxWidth - widget.insets.right,
                    size.maxHeight - widget.insets.bottom,
                  ),
                  obstacles: [
                    ...widget.obstacles,
                    ...?geometry?.overlayExclusionRects.value,
                  ],
                );
          final rings =
              moving ||
                  (geometry != null &&
                      (geometry!.overlayExclusionRects.value == null ||
                          geometry!.renderedHospitalIds.value == null))
              ? <String, Rect>{}
              : layoutPersonalizationRings(
                  points: points,
                  eligible: widget.ringIds,
                  selectedHpid: widget.selectedHpid,
                  renderedIds: geometry?.renderedHospitalIds.value,
                  viewport: Rect.fromLTRB(
                    widget.insets.left,
                    widget.insets.top,
                    size.maxWidth - widget.insets.right,
                    size.maxHeight - widget.insets.bottom,
                  ),
                  obstacles: [
                    ...widget.obstacles,
                    ...?geometry?.overlayExclusionRects.value,
                  ],
                );
          return Stack(
            children: [
              for (final e in rings.entries)
                Positioned.fromRect(
                  rect: e.value,
                  child: DecoratedBox(
                    key: ValueKey('personalization-ring:${e.key}'),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: .7),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              for (final e in rects.entries)
                Positioned.fromRect(
                  rect: e.value,
                  child: Container(
                    key: ValueKey('personalization-dot:${e.key}'),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          widget.accents[e.key] == PersonalizationAccent.filled
                          ? personalizationGold(context)
                          : Theme.of(context).colorScheme.surface,
                      border: Border.all(
                        color: personalizationGold(context),
                        width: 1.5,
                      ),
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
