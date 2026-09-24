import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import '../../features/emergency_map/domain/hospital_summary.dart';

/// Presentation distances are logical pixels, shared by grouping and hit targets.
abstract final class HospitalClusterGeometry {
  static const radius = 60.0;
  static const height = 48.0;
  static Size size(int count) =>
      Size(math.max(height, 24 + '$count'.length * 11), height);
}

@immutable
class MarkerCluster {
  final List<String> hospitalIds;
  final Offset anchor;
  MarkerCluster(Iterable<String> ids, this.anchor)
    : hospitalIds = List.unmodifiable(ids.toList()..sort());
  String get id => jsonEncode(hospitalIds);
  int get count => hospitalIds.length;
  Rect get rect => Rect.fromCenter(
    center: anchor,
    width: HospitalClusterGeometry.size(count).width,
    height: HospitalClusterGeometry.height,
  );
}

@immutable
class HospitalClusterPlan {
  final Set<String> individualIds;
  final List<MarkerCluster> clusters;
  const HospitalClusterPlan(this.individualIds, this.clusters);
  int get hospitalCount =>
      individualIds.length + clusters.fold(0, (n, c) => n + c.count);
}

/// Deterministic greedy seed grouping using a 60dp spatial hash. A seed absorbs
/// only points within its screen radius; chains cannot span the whole city.
/// Seed lookup inspects nine adjacent cells. All result IDs participate (also
/// offscreen); only native map clipping limits what is visible. No search policy.
class HospitalMarkerClusterer {
  const HospitalMarkerClusterer();
  HospitalClusterPlan group(
    Map<String, Offset> points, {
    String? selectedHpid,
  }) {
    final buckets = <(int, int), List<_Group>>{};
    final groups = <_Group>[];
    final individual = <String>{};
    final ids = points.keys.toList()..sort();
    const radius = HospitalClusterGeometry.radius;
    for (final id in ids) {
      final p = points[id]!;
      if (id == selectedHpid || !p.dx.isFinite || !p.dy.isFinite) {
        individual.add(id);
        continue;
      }
      final cell = ((p.dx / radius).floor(), (p.dy / radius).floor());
      _Group? nearest;
      var distance = radius * radius;
      for (var x = cell.$1 - 1; x <= cell.$1 + 1; x++) {
        for (var y = cell.$2 - 1; y <= cell.$2 + 1; y++) {
          for (final g in buckets[(x, y)] ?? <_Group>[]) {
            final d = (p - g.seed).distanceSquared;
            if (d < distance ||
                (d == distance &&
                    (nearest == null ||
                        g.ids.first.compareTo(nearest.ids.first) < 0))) {
              nearest = g;
              distance = d;
            }
          }
        }
      }
      if (nearest == null) {
        final g = _Group(id, p);
        groups.add(g);
        (buckets[cell] ??= []).add(g);
      } else {
        nearest.ids.add(id);
        nearest.sum += p;
      }
    }
    final clusters = <MarkerCluster>[];
    for (final g in groups) {
      if (g.ids.length == 1) {
        individual.add(g.ids.single);
      } else {
        clusters.add(MarkerCluster(g.ids, g.sum / g.ids.length.toDouble()));
      }
    }
    return HospitalClusterPlan(
      Set.unmodifiable(individual),
      List.unmodifiable(clusters),
    );
  }
}

class _Group {
  final Offset seed;
  Offset sum;
  final List<String> ids;
  _Group(String id, this.seed) : sum = seed, ids = [id];
}

/// Public member coordinates only. Bounds fitting never selects a hospital.
CoverageBounds clusterBounds(Iterable<GeoPoint> points) {
  final values = points.toList();
  assert(values.isNotEmpty);
  return CoverageBounds(
    GeoPoint(
      values.map((p) => p.latitude).reduce(math.min),
      values.map((p) => p.longitude).reduce(math.min),
    ),
    GeoPoint(
      values.map((p) => p.latitude).reduce(math.max),
      values.map((p) => p.longitude).reduce(math.max),
    ),
  );
}
