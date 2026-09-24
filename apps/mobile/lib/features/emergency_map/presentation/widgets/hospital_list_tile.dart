import '../../../disease_personalization/department_matcher.dart';
import '../../../disease_personalization/personalization_badge.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/eroute_tokens.dart';
import '../../../../core/widgets/eroute_card.dart';
import '../../domain/hospital_summary.dart';
import 'realtime_summary.dart';

class HospitalListTile extends StatelessWidget {
  final HospitalSummary hospital;
  final HospitalDiseaseMatchResult? personalization;
  final bool manual, selected;
  final VoidCallback onTap;
  final VoidCallback? onReviewReason;
  const HospitalListTile({
    super.key,
    required this.hospital,
    this.personalization,
    this.onReviewReason,
    required this.manual,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final h = hospital;
    final distance = manual
        ? h.centerDistance
        : (h.userDistance ?? h.centerDistance);
    final textDistance = distance < 1000
        ? '${distance}m'
        : '${(distance / 1000).toStringAsFixed(1)}km';
    return Semantics(
      button: true,
      selected: selected,
      label: '${h.name}, ${h.classification}, $textDistance, ${h.statusLabel}',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          ERouteSpacing.md,
          0,
          ERouteSpacing.md,
          ERouteSpacing.sm,
        ),
        child: ERouteCard(
          selected: selected,
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: context.eroute.emergency,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.local_hospital_rounded,
                      color: context.eroute.onEmergency,
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: ERouteSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          h.classification,
                          style: ERouteTypography.label.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: ERouteSpacing.xxs),
                        Text(h.name, style: ERouteTypography.hospitalName),
                      ],
                    ),
                  ),
                  const SizedBox(width: ERouteSpacing.xs),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        textDistance,
                        style: ERouteTypography.hospitalName.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: ERouteSpacing.xxs),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: context.eroute.muted,
                      ),
                    ],
                  ),
                ],
              ),
              if (personalization?.matched == true)
                PersonalizationBadge(
                  result: personalization!,
                  onReviewReason: onReviewReason,
                ),
              const SizedBox(height: ERouteSpacing.sm),
              Text(
                manual ? '검색 중심에서 직선거리' : '현재 위치에서 직선거리',
                style: ERouteTypography.label.copyWith(
                  color: context.eroute.muted,
                ),
              ),
              const SizedBox(height: ERouteSpacing.sm),
              RealtimeSummary(hospital: h),
            ],
          ),
        ),
      ),
    );
  }
}
