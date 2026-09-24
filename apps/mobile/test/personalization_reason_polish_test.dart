import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eroute_mobile/core/theme/eroute_theme.dart';
import 'package:eroute_mobile/features/disease_personalization/department_matcher.dart';
import 'package:eroute_mobile/features/disease_personalization/personalization_badge.dart';
import 'support/synthetic_personalization.dart';

HospitalDiseaseMatchResult reasons(bool preview) =>
    HospitalDiseaseMatchResult(syntheticDepartmentSnapshot(), 'synthetic', [
      for (final entry in {
        'exact': 'EXACT_CANONICAL_REVIEW_REQUIRED',
        'broad': 'BROAD_PARENT_REVIEW_REQUIRED',
        'unknown': 'REVIEW_REQUIRED',
      }.entries)
        DiseaseMatch(entry.key, DepartmentMatchStatus.match, [
          DepartmentMatchReason(
            diseaseId: entry.key,
            diseaseName: '가상 질환',
            mappingId: 'TEST_MAPPING_${entry.key}',
            canonicalDepartmentId: 'test',
            canonicalDepartmentName: '가상 진료과',
            hospitalDepartmentName: '가상 진료과',
            hospitalDepartmentRaw: '가상 진료과',
            hospitalSource: 'test',
            reviewStatus: preview ? 'DRAFT' : 'APPROVED',
            reviewClass: entry.value,
          ),
        ], const []),
    ], reviewPreview: preview);

void main() {
  testWidgets(
    'review codes stay absent and close is reachable at 200% in both themes',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final dark in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? ERouteTheme.dark() : ERouteTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  child: const Text('열기'),
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) =>
                        PersonalizationReasonSheet(result: reasons(true)),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('열기'));
        await tester.pumpAndSettle();
        expect(find.text('관계 범위: 직접 대응 후보'), findsOneWidget);
        expect(find.text('관계 범위: 상위 진료과 후보'), findsOneWidget);
        expect(find.text('관계 범위: 범위 미확정'), findsOneWidget);
        expect(find.text('검수 상태: 개발 검수 중'), findsNWidgets(3));
        expect(find.text('닫기').hitTestable(), findsOneWidget);
        expect(find.textContaining('REVIEW_REQUIRED'), findsNothing);
        expect(find.textContaining('TEST_MAPPING'), findsNothing);
        expect(find.text('개발 정보'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('닫기'));
        await tester.pumpAndSettle();
        expect(find.text('닫기').hitTestable(), findsOneWidget);
        await tester.tap(find.text('닫기'));
        await tester.pumpAndSettle();
        expect(find.byType(PersonalizationReasonSheet), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets(
    'approved reasons never expose development metadata even in debug',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PersonalizationReasons(result: reasons(false)),
            ),
          ),
        ),
      );
      expect(find.text('개발 정보'), findsNothing);
      expect(find.textContaining('REVIEW_REQUIRED'), findsNothing);
      expect(find.textContaining('TEST_MAPPING'), findsNothing);
    },
  );
}
