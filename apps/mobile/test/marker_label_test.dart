import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eroute_mobile/core/map/marker_label_layout.dart';
import 'package:eroute_mobile/core/map/selected_hospital_label.dart';
import 'package:eroute_mobile/features/emergency_map/domain/hospital_summary.dart';
import 'hospital_detail_test.dart' show seededMap;
import 'emergency_map_test.dart' as fixtures;

void main() {
  test('selection touches at most old/new markers even in dense results', () {
    for (final count in [1, 10, 500]) {
      final ids = Set<String>.from(List.generate(count, (i) => 'H$i'));
      expect(
        hospitalMarkersToUpdate(hospitalIds: ids, searchChanged: true),
        ids,
      );
      expect(
        hospitalMarkersToUpdate(hospitalIds: ids, searchChanged: false),
        isEmpty,
      );
      expect(
        hospitalMarkersToUpdate(
          hospitalIds: ids,
          searchChanged: false,
          selected: 'H0',
        ),
        {'H0'},
      );
      if (count > 1) {
        expect(
          hospitalMarkersToUpdate(
            hospitalIds: ids,
            searchChanged: false,
            previous: 'H0',
            selected: 'H1',
          ),
          {'H0', 'H1'},
        );
      }
      expect(
        hospitalMarkersToUpdate(
          hospitalIds: ids,
          searchChanged: false,
          previous: 'H0',
        ),
        {'H0'},
      );
    }
  });

  test(
    'caption and chip are exclusive and use safe viewport without moving anything',
    () {
      const viewport = Rect.fromLTRB(76, 140, 354, 600);
      final clear = layoutSelectedHospitalLabel(
        viewport: viewport,
        marker: const Offset(200, 300),
        captionSize: const Size(120, 32),
      );
      expect(clear.caption, isNotNull);
      expect(clear.chip, isNull);
      for (final marker in [
        const Offset(200, 590),
        const Offset(200, 40),
        const Offset(800, 300),
        const Offset(80, 300),
      ]) {
        final hidden = layoutSelectedHospitalLabel(
          viewport: viewport,
          marker: marker,
          captionSize: const Size(120, 32),
        );
        expect(hidden.caption, isNull);
        expect(hidden.chip, isNotNull);
        expect(viewport.contains(hidden.chip!.topLeft), isTrue);
        expect(viewport.contains(hidden.chip!.bottomRight), isTrue);
      }
      final long = layoutSelectedHospitalLabel(
        viewport: viewport,
        marker: const Offset(200, 300),
        captionSize: const Size(800, 32),
      );
      expect(long.caption, isNull);
      expect(long.chip, isNotNull);
      final user = Rect.fromCircle(center: long.chip!.center, radius: 24);
      final moved = layoutSelectedHospitalLabel(
        viewport: viewport,
        marker: const Offset(200, 300),
        captionSize: const Size(800, 32),
        obstacles: [user],
      );
      expect(moved.chip!.overlaps(user), isFalse);
    },
  );

  test(
    'same valid selection survives new search; disappeared selection clears',
    () async {
      final map = seededMap();
      addTearDown(map.dispose);
      map.center = const GeoPoint(37, 127);
      var notifications = 0;
      map.addListener(() => notifications++);
      map.select('TEST_ONLY');
      map.select('TEST_ONLY');
      map.select('NOT_IN_RESULTS');
      expect(notifications, 1);
      expect(map.selectedHpid, 'TEST_ONLY');
      await map.search();
      expect(map.selectedHpid, 'TEST_ONLY');
      // A successful manual search also preserves a still-present HPID.
      map.pendingCenter = const GeoPoint(33, 126);
      await map.searchHere();
      expect(map.selectedHpid, 'TEST_ONLY');
      final repo = map.repository as fixtures.FakeRepository;
      repo.deferred = true;
      final next = map.search();
      repo.requests.single.complete(
        HospitalSearchResult([], 10000, false, false, []),
      );
      await next;
      expect(map.selectedHpid, isNull);
    },
  );

  testWidgets(
    'fallback chip ellipsizes with full accessible name and only selects',
    (tester) async {
      final name = List.filled(20, '긴 병원 이름').join();
      var selections = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 180,
              height: 48,
              child: SelectedHospitalLabel(
                name: name,
                onTap: () => selections++,
              ),
            ),
          ),
        ),
      );
      final text = tester.widget<Text>(find.text(name));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(find.bySemanticsLabel('선택한 병원: $name'), findsOneWidget);
      expect(selections, 0);
      await tester.tap(find.byType(SelectedHospitalLabel));
      expect(selections, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
