import 'package:flutter/material.dart';
import 'department_matcher.dart';
import 'personalization_category_button.dart';
import '../../core/theme/eroute_tokens.dart';
import 'personalization_presentation.dart';

class PersonalizationBadge extends StatelessWidget {
  final HospitalDiseaseMatchResult result;
  final VoidCallback? onReviewReason;
  const PersonalizationBadge({
    super.key,
    required this.result,
    this.onReviewReason,
  });
  @override
  Widget build(BuildContext context) {
    if (!result.matched) return const SizedBox.shrink();
    return PersonalizationCategoryButton(
      diseaseIds: result.matchedDiseases,
      onPressed:
          onReviewReason ??
          () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => PersonalizationReasonSheet(result: result),
          ),
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ERouteRadius.control),
        ),
      ),
      label: compactPersonalizationLabel(result),
    );
  }
}

/// Both modes render the same fields. The caller owns the live private lifetime.
class PersonalizationReasons extends StatelessWidget {
  final HospitalDiseaseMatchResult result;
  const PersonalizationReasons({super.key, required this.result});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('내 질환 관련 진료과', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 16),
      const Text('이 정보는 실제 진료 가능 여부 또는 현재 환자 수용 가능 여부를 의미하지 않습니다.'),
      for (final reason in {
        for (final r in result.matches) r.mappingId: r,
      }.values) ...[
        const Divider(height: 24),
        Text('등록한 질환: ${reason.diseaseName}'),
        Text(
          '관련${result.reviewPreview ? ' 후보' : ''} 진료과: ${reason.canonicalDepartmentName}',
        ),
        Text(
          '병원에서 확인된 진료과: ${result.matches.where((r) => r.mappingId == reason.mappingId).map((r) => r.hospitalDepartmentName).toSet().join(', ')}',
        ),
        Text(
          '관계 범위: ${relationScopeLabel(reason, preview: result.reviewPreview)}',
        ),
        Text(
          result.reviewPreview
              ? '검수 상태: 개발 검수 중'
              : '관계 상태: ${reason.reviewStatus == 'APPROVED' ? '승인됨' : '검수 중'}',
        ),
      ],
      if (result.reviewPreview) ...[
        const Divider(height: 24),
        const Text('개발 미리보기 · 검수 중'),
        const Text('아직 공개되지 않은 질환-진료과 관계를 검증 중입니다.'),
      ],
    ],
  );
}

class PersonalizationReasonSheet extends StatelessWidget {
  final HospitalDiseaseMatchResult? result;
  const PersonalizationReasonSheet({super.key, required this.result});
  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: result?.matched == true
                  ? PersonalizationReasons(result: result!)
                  : const Text('표시가 해제되었거나 정보를 다시 확인 중입니다.'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('닫기'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Same sheet shell and live lifetime as hospital reasons; no consent mutation.
class PersonalizationContextSheet extends StatelessWidget {
  final List<PersonalizationContextRelation> relations;
  final VoidCallback onSettings;
  const PersonalizationContextSheet({
    super.key,
    required this.relations,
    required this.onSettings,
  });
  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '병원 탐색에 활용 중',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  const Text('병원 목록을 줄이거나 순서를 바꾸지 않습니다. 관련 없는 병원도 함께 표시합니다.'),
                  if (relations.isEmpty)
                    const Text('표시가 해제되었거나 정보를 다시 확인 중입니다.'),
                  for (final relation in relations) ...[
                    const Divider(height: 24),
                    Text(
                      relation.diseaseName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text('→ ${relation.departmentName}'),
                    Text(
                      '${relation.scopeLabel} · ${relation.mapping.reviewStatus == 'DRAFT' ? '검수 중' : '승인됨'}',
                    ),
                  ],
                  if (relations.any(
                    (r) => r.mapping.reviewStatus == 'DRAFT',
                  )) ...[
                    const Divider(height: 24),
                    const Text('개발 미리보기 · 검수 중'),
                    const Text('아직 공개되지 않은 질환-진료과 관계를 검증 중입니다.'),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                if (relations.isNotEmpty)
                  TextButton(
                    onPressed: onSettings,
                    child: const Text('병원 탐색 활용 설정'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('닫기'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
