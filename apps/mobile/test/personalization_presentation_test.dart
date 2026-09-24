import 'dart:convert';
import 'package:eroute_mobile/core/map/map_camera_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eroute_mobile/development/disease_review_preview.dart';
import 'package:eroute_mobile/features/disease_personalization/disease_reference.dart';
import 'package:eroute_mobile/features/disease_personalization/department_matcher.dart';
import 'package:eroute_mobile/features/disease_personalization/personalization_presentation.dart';
import 'package:eroute_mobile/features/disease_personalization/personalization_overlay.dart';
import 'support/synthetic_personalization.dart';
import 'support/disease_fixtures.dart';

void main() {
  HospitalDiseaseMatchResult result(
    List<DepartmentMatchReason> reasons, {
    bool preview = false,
  }) => HospitalDiseaseMatchResult(syntheticDepartmentSnapshot(), 'test', [
    DiseaseMatch('test', DepartmentMatchStatus.match, reasons, const []),
  ], reviewPreview: preview);
  DepartmentMatchReason reason({
    MappingScope? scope,
    String status = 'APPROVED',
    String relation = 'DIRECT',
    String? reviewClass,
    String id = 'm',
  }) => DepartmentMatchReason(
    diseaseId: id,
    diseaseName: 'synthetic',
    mappingId: id,
    canonicalDepartmentId: id,
    canonicalDepartmentName: id,
    hospitalDepartmentName: id,
    hospitalDepartmentRaw: id,
    hospitalSource: 'test',
    mappingScope: scope,
    reviewStatus: status,
    relationType: relation,
    reviewClass: reviewClass,
  );
  test(
    'production requires approved explicit EXACT without changing MATCH',
    () {
      for (final status in ['APPROVED', 'DRAFT', 'REJECTED', 'RETIRED']) {
        for (final scope in [null, ...MappingScope.values]) {
          final r = result([reason(scope: scope, status: status)]);
          expect(r.matched, isTrue);
          expect(
            approvedAccent(r),
            status == 'APPROVED' && scope == MappingScope.exactCanonical
                ? PersonalizationAccent.filled
                : PersonalizationAccent.none,
          );
        }
      }
    },
  );
  test('mixed preview reasons yield one style and never public approval', () {
    final broad = reason(
      status: 'DRAFT',
      reviewClass: 'BROAD_PARENT_REVIEW_REQUIRED',
    );
    final unknown = reason(
      id: 'u',
      status: 'DRAFT',
      reviewClass: 'REVIEW_REQUIRED',
    );
    final exact = reason(
      id: 'e',
      status: 'DRAFT',
      reviewClass: 'EXACT_CANONICAL_REVIEW_REQUIRED',
    );
    expect(
      reviewPreviewAccent(result([broad], preview: true)),
      PersonalizationAccent.none,
    );
    expect(
      reviewPreviewAccent(result([broad, unknown], preview: true)),
      PersonalizationAccent.hollow,
    );
    expect(
      reviewPreviewAccent(result([unknown, exact], preview: true)),
      PersonalizationAccent.filled,
    );
    expect(
      approvedAccent(result([exact], preview: true)),
      PersonalizationAccent.none,
    );
    expect(
      reviewPreviewAccent(
        result([reason(scope: MappingScope.exactCanonical)], preview: true),
      ),
      PersonalizationAccent.none,
    );
    expect(
      personalizationBadgeLabel(result([broad, unknown], preview: true)),
      '내 질환 관련 진료과 · 검수 중 · 관련 진료과 2개',
    );
  });
  test(
    'scope decoding does not infer missing values and rejects unknown enum',
    () {
      for (final value in [null, 'EXACT_CANONICAL', 'BROAD_PARENT']) {
        final data = syntheticReferenceData();
        for (final m in data['mappings']) {
          m['mappingScope'] = value;
        }
        expect(
          DiseaseReference.decode(
            referenceEnvelope(jsonEncode(data)),
          ).mappings.first.mappingScope,
          decodeMappingScope(value),
        );
      }
      final data = syntheticReferenceData();
      data['mappings'][0]['mappingScope'] = 'AUTO_EXACT';
      expect(
        () => DiseaseReference.decode(referenceEnvelope(jsonEncode(data))),
        throwsFormatException,
      );
    },
  );
  test('contextual relations never become marker accents', () {
    expect(
      approvedAccent(
        result([
          reason(scope: MappingScope.exactCanonical, relation: 'CONTEXTUAL'),
        ]),
      ),
      PersonalizationAccent.none,
    );
    expect(
      reviewPreviewAccent(
        result([
          reason(
            status: 'DRAFT',
            relation: 'CONTEXTUAL',
            reviewClass: 'EXACT_CANONICAL_REVIEW_REQUIRED',
          ),
        ], preview: true),
      ),
      PersonalizationAccent.none,
    );
  });
  test(
    'dot geometry avoids public markers, captions, controls, peers and edges',
    () {
      Map<String, Rect> layout(
        Map<String, Offset> points, {
        List<Rect> obstacles = const [],
        String? selected,
      }) => layoutPersonalizationAccents(
        points: points,
        eligible: {'a'},
        selectedHpid: selected,
        viewport: const Rect.fromLTWH(0, 0, 300, 300),
        obstacles: obstacles,
      );
      for (final selected in [null, 'a']) {
        final dot = layout({
          'a': const Offset(100, 100),
        }, selected: selected)['a']!;
        expect(dot.size, const Size(8, 8));
        final offset = dot.center - const Offset(100, 100);
        expect(offset.dx, closeTo(-offset.dy, .001));
        final radius = HospitalMarkerGeometry.visibleRadius(selected != null);
        expect(offset.distance - 4 - radius, closeTo(-2, .001));
        // Visible cross arms are [20,12,8,24] and [12,20,24,8] on 48px canvas.
        final scale = HospitalMarkerGeometry.size(selected != null) / 48;
        expect(
          dot.overlaps(
            Rect.fromCenter(
              center: const Offset(100, 100),
              width: 8 * scale,
              height: 24 * scale,
            ),
          ),
          isFalse,
        );
        expect(
          dot.overlaps(
            Rect.fromCenter(
              center: const Offset(100, 100),
              width: 24 * scale,
              height: 8 * scale,
            ),
          ),
          isFalse,
        );
      }
      expect(
        layout({
          'a': const Offset(100, 100),
          'unmatched': const Offset(125, 100),
        }),
        isEmpty,
      );
      expect(
        layout(
          {'a': const Offset(100, 100)},
          obstacles: [const Rect.fromLTWH(110, 80, 20, 20)],
        ),
        isEmpty,
      );
      expect(layout({'a': const Offset(290, 100)}), isEmpty);
      expect(
        layoutPersonalizationAccents(
          points: {'a': const Offset(100, 100), 'b': const Offset(101, 101)},
          eligible: {'a', 'b'},
          selectedHpid: null,
          viewport: const Rect.fromLTWH(0, 0, 300, 300),
        ),
        isEmpty,
      );
    },
  );
  test('ambiguous or absent marker cannot leave a floating badge', () {
    const viewport = Rect.fromLTWH(0, 0, 300, 300);
    const points = {'a': Offset(100, 100), 'cover': Offset(99, 100)};
    expect(
      visibleHospitalMarkers(
        points: points,
        selectedHpid: null,
        viewport: viewport,
      ),
      isEmpty,
    );
    // Existing selected z-index is known; no ordering is invented for other markers.
    expect(
      visibleHospitalMarkers(
        points: points,
        selectedHpid: 'a',
        viewport: viewport,
      ),
      {'a'},
    );
    expect(
      layoutPersonalizationAccents(
        points: {'a': const Offset(100, 100)},
        eligible: {'a'},
        selectedHpid: null,
        viewport: viewport,
        renderedIds: {},
      ),
      isEmpty,
    );
    // The old external dot would fit even though its owner's circle is clipped.
    expect(
      layoutPersonalizationAccents(
        points: {'a': const Offset(5, 100)},
        eligible: {'a'},
        selectedHpid: null,
        viewport: viewport,
      ),
      isEmpty,
    );
    expect(
      visibleHospitalMarkers(
        points: {'a': const Offset(100, 100)},
        selectedHpid: null,
        viewport: viewport,
        obstacles: [const Rect.fromLTWH(80, 80, 40, 40)],
      ),
      isEmpty,
    );
    expect(
      layoutPersonalizationAccents(
        points: points,
        eligible: {'cover'},
        selectedHpid: 'a',
        viewport: viewport,
      ),
      isEmpty,
    );
  });
}
