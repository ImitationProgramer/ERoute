import 'package:flutter/material.dart';
import '../../../../core/formatting/provider_time_formatter.dart';
import '../../../../core/theme/eroute_tokens.dart';
import '../../../../core/widgets/eroute_card.dart';
import '../../domain/hospital_summary.dart';

class RealtimeSummary extends StatelessWidget {
  final HospitalSummary hospital;
  final bool showMetrics, detail;
  const RealtimeSummary({
    super.key,
    required this.hospital,
    this.showMetrics = true,
    this.detail = false,
  });

  @override
  Widget build(BuildContext context) {
    final h = hospital;
    final hasMetrics = h.beds.known || h.reference.known;
    final fetchedText = h.fetchedAt == null
        ? null
        : formatFetchedTime(h.fetchedAt!);
    final providerText = formatProviderWallTime(h.parsedSourceTime);
    final warning =
        h.stale ||
        h.sourceFreshness == 'STALE' ||
        h.coverage == 'LIVE_ERROR' ||
        h.refresh == 'BUDGET_DEFERRED';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showMetrics && (hasMetrics || detail))
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Metric(
                  label: '응급실 가용병상',
                  value: h.beds.known ? '${h.beds.numericValue}' : '정보 미제공',
                  unit: h.beds.known ? '병상' : '',
                ),
              ),
              const SizedBox(width: ERouteSpacing.sm),
              Expanded(
                child: _Metric(
                  label: '일반 병상 기준',
                  value: h.reference.known
                      ? '${h.reference.numericValue}'
                      : '정보 미제공',
                ),
              ),
            ],
          ),
        if (showMetrics && (hasMetrics || detail))
          const SizedBox(height: ERouteSpacing.sm),
        ERouteStatusBadge(h.statusLabel, warning: warning),
        if (h.refreshGuidance != null) ...[
          const SizedBox(height: ERouteSpacing.xs),
          Text(
            h.refreshGuidance!,
            style: ERouteTypography.label.copyWith(color: context.eroute.muted),
          ),
        ],
        if (h.stale &&
            h.fetchedAt != null &&
            !h.statusLabel.contains('이전 정보')) ...[
          const SizedBox(height: ERouteSpacing.xxs),
          const ERouteStatusBadge('이전 정보', warning: true),
        ],
        if (h.freshnessGuidance != null) ...[
          const SizedBox(height: ERouteSpacing.xs),
          Text(
            h.freshnessGuidance!,
            style: ERouteTypography.label.copyWith(color: context.eroute.muted),
          ),
        ],
        if (detail) ...[
          const SizedBox(height: ERouteSpacing.md),
          Text(
            '최근 확인 · ${h.fetchedAt == null ? '정보 미제공' : formatCollectionAge(h.fetchedAt!, localPresentationNow())}',
          ),
          Text(
            '출처 · 국립중앙의료원',
            style: ERouteTypography.label.copyWith(color: context.eroute.muted),
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('출처·갱신 상세 정보'),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '최근 확인은 ERoute 수집시각 기준이며, 병원의 현재 수용 가능 여부를 보장하지 않습니다.',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '응급실 가용병상: hvec (일반·응급실일반병상). 일반 병상 기준: HVS01 (일반_기준). 일반 입원병상 수나 현재 가용병상으로 해석하지 않습니다.',
                    ),
                    if (h.rawSourceTime != null)
                      Text('원천 입력값 ${h.rawSourceTime}'),
                    if (h.sourceTimestampStatus != null)
                      Text(
                        '원천 시간대 상태: ${h.sourceTimestampStatus == 'VERIFIED' ? '확인됨' : '미확인'}',
                      ),
                    if (fetchedText != null) ...[
                      const SizedBox(height: ERouteSpacing.xs),
                      Text(
                        'ERoute 수집 $fetchedText',
                        style: ERouteTypography.label.copyWith(
                          color: context.eroute.muted,
                        ),
                      ),
                    ],
                    if (h.fetchedAt != null &&
                        h.coverage != 'LIVE_NOT_PROVIDED') ...[
                      const SizedBox(height: ERouteSpacing.xs),
                      Text(
                        providerText == null
                            ? '제공기관 입력시각 확인 불가'
                            : '제공기관 입력 $providerText${h.sourceTimestampStatus == 'TIMEZONE_UNVERIFIED' ? ' · 시간대 미확인' : ''}',
                        style: ERouteTypography.label.copyWith(
                          color: context.eroute.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ] else ...[
          if (fetchedText != null) ...[
            const SizedBox(height: ERouteSpacing.xs),
            Text(
              'ERoute 수집 $fetchedText',
              style: ERouteTypography.label.copyWith(
                color: context.eroute.muted,
              ),
            ),
          ],
          if (h.fetchedAt != null && h.coverage != 'LIVE_NOT_PROVIDED') ...[
            const SizedBox(height: ERouteSpacing.xs),
            Text(
              providerText == null
                  ? '제공기관 입력시각 확인 불가'
                  : '제공기관 입력 $providerText${h.sourceTimestampStatus == 'TIMEZONE_UNVERIFIED' ? ' · 시간대 미확인' : ''}',
              style: ERouteTypography.label.copyWith(
                color: context.eroute.muted,
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final String label, value, unit;
  const _Metric({required this.label, required this.value, this.unit = ''});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: ERouteTypography.label.copyWith(color: context.eroute.muted),
      ),
      const SizedBox(height: ERouteSpacing.xs),
      Text(
        value,
        style: int.tryParse(value) == null
            ? ERouteTypography.label.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              )
            : ERouteTypography.metric,
      ),
      if (unit.isNotEmpty) Text(unit, style: ERouteTypography.label),
    ],
  );
}
