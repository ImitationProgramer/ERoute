import '../../disease_personalization/department_matcher.dart';
import '../../disease_personalization/personalization_badge.dart';
import '../../disease_personalization/personalization_presentation.dart';
import 'package:flutter/material.dart';
import '../../../core/formatting/provider_time_formatter.dart';
import '../../../core/theme/eroute_tokens.dart';
import '../../../core/widgets/eroute_card.dart';
import '../../../core/widgets/eroute_skeleton.dart';
import '../domain/hospital_detail.dart';
import 'hospital_detail_state.dart';

class HospitalClinicalInformation extends StatelessWidget {
  final HospitalDetailState state;
  final HospitalDiseaseMatchResult? personalization;
  final VoidCallback? onReviewReason;
  final DateTime Function()? now;
  const HospitalClinicalInformation({
    super.key,
    required this.state,
    this.personalization,
    this.onReviewReason,
    this.now,
  });
  static const days = {
    'MON': '월요일',
    'TUE': '화요일',
    'WED': '수요일',
    'THU': '목요일',
    'FRI': '금요일',
    'SAT': '토요일',
    'SUN': '일요일',
    'HOLIDAY': '공휴일',
  };
  @override
  Widget build(BuildContext context) {
    final info = state.loaded?.basicInfo;
    final children = <Widget>[
      if (personalization?.matched == true) ...[
        Semantics(
          header: true,
          child: Text('내 질환 관련 진료과', style: ERouteTypography.hospitalName),
        ),
        const SizedBox(height: 8),
        PersonalizationBadge(
          result: personalization!,
          onReviewReason: onReviewReason,
        ),
        Text(
          personalization!.matches
              .map(
                (r) => relationScopeLabel(
                  r,
                  preview: personalization!.reviewPreview,
                ),
              )
              .toSet()
              .join(' · '),
        ),
        const SizedBox(height: 8),
        const Text('실제 진료 가능 여부 또는 현재 수용 가능을 의미하지 않습니다.'),
        const Divider(height: 32),
      ],
    ];
    if (info == null) {
      children.add(
        state.detail.isLoading
            ? const ERouteSkeleton(height: 160, label: '진료정보 불러오는 중')
            : const Text('병원 진료정보를 불러오지 못했습니다.'),
      );
    } else {
      final previous = info.dataStatus == 'PROVIDED';
      final failed =
          info.fetchStatus == 'ERROR' || info.refreshStatus == 'ERROR';
      if (failed) {
        children.add(Text(previous ? '갱신 실패 · 이전 정보' : '병원 진료정보를 수집하지 못했습니다.'));
      } else if (info.refreshStatus == 'BUDGET_DEFERRED') {
        children.add(Text(previous ? '갱신 대기 · 이전 정보' : '갱신 대기'));
      } else if (info.stale) {
        children.add(const Text('이전 정보'));
      } else if (info.refreshStatus == 'IN_PROGRESS') {
        children.add(const Text('진료정보 갱신 중'));
      }
      if (info.staleReasons.contains('SOURCE_RECORD_NOT_PROVIDED')) {
        children.add(const Text('제공기관의 최신 정보가 없어 이전 정보를 표시합니다.'));
      }
      if (info.dataStatus == 'NOT_COLLECTED') {
        if (!failed) children.add(const Text('병원 진료정보를 아직 수집하지 못했습니다.'));
      } else {
        children.addAll([
          const SizedBox(height: ERouteSpacing.sm),
          Semantics(
            header: true,
            child: Text(
              '진료과목 ${info.departments.where((d) => d.status == 'KNOWN' && d.name.isNotEmpty).length}개',
              style: ERouteTypography.hospitalName,
            ),
          ),
          const Divider(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final department in info.departments.where(
                (d) => d.status == 'KNOWN' && d.name.isNotEmpty,
              ))
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(ERouteRadius.control),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Text(department.name),
                ),
            ],
          ),
          if (info.departmentsStatus == 'UNVERIFIED' ||
              info.departmentsStatus == 'UNPARSEABLE')
            const Text('진료과목 정보 확인 필요')
          else if (info.departments.isEmpty)
            const Text('진료과목 정보 미제공'),
          const SizedBox(height: ERouteSpacing.lg),
          Semantics(
            header: true,
            child: Text('병원 진료시간', style: ERouteTypography.hospitalName),
          ),
          const Divider(height: 24),
          if (info.operatingHours.every(
            (h) => h.status == 'MISSING' || h.status == 'NOT_PROVIDED',
          ))
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('진료시간 정보 미제공'),
            ),
          Builder(
            builder: (context) {
              final dayKey = days.keys.elementAt(
                (now ?? localPresentationNow)().toLocal().weekday - 1,
              );
              final matches = info.operatingHours.where((h) => h.day == dayKey);
              final today = matches.length == 1
                  ? matches.single
                  : HospitalOperatingHours(
                      day: dayKey,
                      status: matches.isEmpty ? 'MISSING' : 'UNVERIFIED',
                    );
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.eroute.softBlue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '오늘 · ${days[dayKey]}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(today.display),
                    const SizedBox(height: 4),
                    const Text('요일 기준 · 공휴일에는 다를 수 있습니다.'),
                  ],
                ),
              );
            },
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('요일별 보기'),
            children: [
              ...days.entries.map((day) {
                final matches = info.operatingHours.where(
                  (h) => h.day == day.key,
                );
                final h = matches.length == 1
                    ? matches.single
                    : HospitalOperatingHours(
                        day: day.key,
                        status: matches.isEmpty ? 'MISSING' : 'UNVERIFIED',
                      );
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: Text(day.value)),
                      const SizedBox(width: 12),
                      Expanded(flex: 3, child: Text(h.display)),
                    ],
                  ),
                );
              }),
            ],
          ),
        ]);
      }
      final sources = info.departments.map((d) => d.source).toSet();
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(
            '진료정보 출처 · ${sources.contains('HIRA') ? '건강보험심사평가원' : '국립중앙의료원'}${sources.contains('HIRA') && sources.contains('NMC') ? ' · 국립중앙의료원' : ''}',
            style: ERouteTypography.label.copyWith(color: context.eroute.muted),
          ),
        ),
      );
      if (info.fetchedAt != null) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'ERoute 조회 ${formatFetchedTime(info.fetchedAt!)}',
              style: ERouteTypography.label.copyWith(
                color: context.eroute.muted,
              ),
            ),
          ),
        );
      }
    }
    children.addAll([
      const SizedBox(height: ERouteSpacing.md),
      Text(
        '공개된 병원 진료시간이며 진료과별 운영시간과 다를 수 있습니다. 응급실 운영시간을 의미하지 않습니다. 방문 전 병원에 확인해주세요.',
        style: ERouteTypography.label.copyWith(color: context.eroute.muted),
      ),
    ]);
    return ERouteCard(
      key: const ValueKey('clinical'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}
