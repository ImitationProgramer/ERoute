import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../../features/emergency_map/domain/hospital_summary.dart';
import 'map_scene.dart';

enum CameraMoveOrigin {
  programmaticFit,
  programmaticCurrentLocation,
  programmaticLayout,
  userGesture,
  userZoomControl,
}

class MapCameraEvent {
  final GeoPoint center;
  final CameraMoveOrigin origin;
  const MapCameraEvent(this.center, this.origin);
  bool get userInitiated =>
      origin == CameraMoveOrigin.userGesture ||
      origin == CameraMoveOrigin.userZoomControl;
}

abstract interface class MapCameraController {
  Future<void> fit(SearchPresentationSnapshot snapshot);
  Future<void> moveToCurrentLocation(GeoPoint point);
  Future<void> zoomBy(double delta);
  Future<void> updateViewport(EdgeInsets insets, {required bool settled});

  /// Logical pixels in the map widget, without exposing SDK types.
  Future<Offset> project(GeoPoint point);
}

/// Optional public map geometry notifications. No personalization or member state.
abstract interface class MapProjectionEvents {
  ValueListenable<int> get projectionRevision;
  ValueListenable<bool> get cameraMoving;
}

/// Public marker/label readiness only; null means geometry is being recomputed.
abstract interface class MapOverlayGeometry {
  ValueListenable<List<Rect>?> get overlayExclusionRects;

  /// Individually installed hospital markers only (cluster members excluded).
  /// Null means synchronization is pending. No private match or selection policy.
  ValueListenable<Set<String>?> get renderedHospitalIds;
}

abstract final class HospitalMarkerGeometry {
  static const iconCanvasSize = 48.0;
  static const iconRadius = 21.0;
  static const normalSize = 38.0;
  static const selectedSize = 48.0;
  static double size(bool selected) => selected ? selectedSize : normalSize;
  static double visibleRadius(bool selected) =>
      size(selected) * iconRadius / iconCanvasSize;
}
