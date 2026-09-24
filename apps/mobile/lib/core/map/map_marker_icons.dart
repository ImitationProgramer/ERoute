import 'hospital_cluster_marker.dart';
import 'hospital_marker_clusterer.dart';
import 'dart:ui' as ui;
import 'map_camera_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

/// Rasterized vector shapes, cached once. No map screenshots or network assets.
class MapMarkerIcons {
  static final Map<String, Future<NOverlayImage>> _cache = {};
  // Bounded cache: changing result membership does not allocate new count art.
  static final Map<String, Future<NOverlayImage>> _clusters = {};
  static Future<NOverlayImage> cluster(int count, {required bool dark}) {
    final key = '$count:$dark';
    if (_clusters.containsKey(key)) return _clusters[key]!;
    if (_clusters.length >= 64) _clusters.remove(_clusters.keys.first);
    return _clusters[key] = () async {
      final size = HospitalClusterGeometry.size(count);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..scale(2);
      HospitalClusterPainter(count, dark: dark).paint(canvas, size);
      final picture = recorder.endRecording();
      final image = await picture.toImage(
        (size.width * 2).ceil(),
        (size.height * 2).ceil(),
      );
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final icon = await NOverlayImage.fromByteArray(
        bytes!.buffer.asUint8List(),
        cacheKey: 'eroute-cluster-$key-v1',
      );
      image.dispose();
      picture.dispose();
      return icon;
    }();
  }

  static Future<NOverlayImage> get(String role) => _cache.putIfAbsent(
    role,
    () async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..scale(2);
      final selected = role == 'selected';
      final color = role == 'manual'
          ? const Color(0xffd47716)
          : role == 'arrow' || role == 'dot'
          ? const Color(0xff2478e8)
          : selected
          ? const Color(0xff244e86)
          : const Color(0xffc93645);
      final paint = Paint()..color = color;
      if (role == 'arrow') {
        final path = Path()
          ..moveTo(24, 3)
          ..lineTo(42, 43)
          ..lineTo(24, 34)
          ..lineTo(6, 43)
          ..close();
        canvas.drawPath(
          path,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4,
        );
        canvas.drawPath(path, paint);
      } else {
        canvas.drawCircle(
          const Offset(24, 24),
          role == 'dot' ? 12 : HospitalMarkerGeometry.iconRadius,
          Paint()..color = Colors.white,
        );
        canvas.drawCircle(const Offset(24, 24), role == 'dot' ? 9 : 18, paint);
        if (role == 'manual') {
          canvas.drawCircle(
            const Offset(24, 24),
            9,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3,
          );
          canvas.drawCircle(
            const Offset(24, 24),
            3,
            Paint()..color = Colors.white,
          );
        } else if (role != 'dot') {
          canvas.drawRect(
            const Rect.fromLTWH(20, 12, 8, 24),
            Paint()..color = Colors.white,
          );
          canvas.drawRect(
            const Rect.fromLTWH(12, 20, 24, 8),
            Paint()..color = Colors.white,
          );
        }
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(96, 96);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final icon = await NOverlayImage.fromByteArray(
        bytes!.buffer.asUint8List(),
        cacheKey: 'eroute-$role-v2',
      );
      image.dispose();
      picture.dispose();
      return icon;
    },
  );
}
