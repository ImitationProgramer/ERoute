import 'dart:math' as math;
import 'package:flutter/widgets.dart';

/// Selection changes touch at most two overlays. A new search updates its set.
Set<String> hospitalMarkersToUpdate({
  required Set<String> hospitalIds,
  required bool searchChanged,
  String? previous,
  String? selected,
}) => searchChanged
    ? hospitalIds
    : {?previous, ?selected}.intersection(hospitalIds);

class MarkerLabelLayout {
  final Rect? caption;
  final Rect? chip;
  const MarkerLabelLayout({this.caption, this.chip});
}

/// Pure screen geometry; never moves the camera or changes the selection.
MarkerLabelLayout layoutSelectedHospitalLabel({
  required Rect viewport,
  required Offset marker,
  required Size captionSize,
  double chipHeight = 48,
  List<Rect> obstacles = const [],
}) {
  final safe = viewport.deflate(8);
  if (safe.isEmpty) return const MarkerLabelLayout();
  bool fits(Rect rect) =>
      safe.contains(rect.topLeft) &&
      rect.right <= safe.right &&
      rect.bottom <= safe.bottom &&
      !obstacles.any((obstacle) => rect.overlaps(obstacle));
  // The selected marker is center-anchored, 48dp, with an 8dp caption gap.
  final caption = Rect.fromLTWH(
    marker.dx - captionSize.width / 2,
    marker.dy + 32,
    captionSize.width,
    captionSize.height,
  );
  if (fits(caption)) return MarkerLabelLayout(caption: caption);
  final width = math.min(260.0, safe.width);
  // Usually the first row fits; the next rows avoid the blue location marker.
  for (
    var top = safe.top;
    top + chipHeight <= safe.bottom;
    top += chipHeight + 8
  ) {
    final chip = Rect.fromLTWH(
      safe.center.dx - width / 2,
      top,
      width,
      chipHeight,
    );
    if (fits(chip)) return MarkerLabelLayout(chip: chip);
  }
  return const MarkerLabelLayout();
}
