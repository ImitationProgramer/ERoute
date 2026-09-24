import '../../../disease_personalization/department_matcher.dart';
import 'package:flutter/material.dart';
import '../emergency_map_controller.dart';
import 'hospital_list_tile.dart';
import '../../../../core/theme/eroute_tokens.dart';
import '../../../../core/widgets/eroute_feedback.dart';

class HospitalSheet extends StatelessWidget {
  final EmergencyMapController state;
  final Map<String, HospitalDiseaseMatchResult> personalization;
  final DraggableScrollableController controller;
  final double minSize, maxSize, initialSize;
  final ValueChanged<String>? onHospitalTap, onReviewReason;
  const HospitalSheet({
    super.key,
    required this.state,
    required this.controller,
    required this.minSize,
    required this.maxSize,
    required this.initialSize,
    this.onHospitalTap,
    this.onReviewReason,
    this.personalization = const {},
  });
  @override
  Widget build(BuildContext context) {
    final result = state.snapshot?.result;
    return DraggableScrollableSheet(
      controller: controller,
      initialChildSize: initialSize,
      minChildSize: minSize,
      maxChildSize: maxSize,
      builder: (context, scroll) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(ERouteRadius.sheet),
          ),
          boxShadow: ERouteShadows.sheet,
        ),
        child: CustomScrollView(
          controller: scroll,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xffc6d2cb),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '주변 응급의료기관',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (result != null) ...[
                          Text(
                            '${result.totalCount}',
                            style: TextStyle(
                              fontSize: 24,
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          IconButton(
                            tooltip:
                                controller.isAttached &&
                                    controller.size > initialSize + .05
                                ? '병원 목록 접기'
                                : '병원 목록 펼치기',
                            onPressed: () {
                              final expanded =
                                  controller.isAttached &&
                                  controller.size > initialSize + .05;
                              controller.animateTo(
                                expanded ? initialSize : maxSize,
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOut,
                              );
                            },
                            icon: Icon(
                              controller.isAttached &&
                                      controller.size > initialSize + .05
                                  ? Icons.keyboard_arrow_down_rounded
                                  : Icons.keyboard_arrow_up_rounded,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      result == null
                          ? '검색 위치를 선택해주세요'
                          : '반경 ${(result.radius / 1000).toStringAsFixed(0)}km${result.expanded ? ' · 검색 범위 확대' : ''} · ${state.snapshot!.source == 'GPS' ? '현재 위치' : '선택한 위치'} 기준',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.eroute.muted,
                      ),
                    ),
                    if (state.loading)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    if (result?.catalogStale ?? false)
                      const Text(
                        '병원 기본 목록이 이전 자료입니다. 병상정보 시각은 병원별로 확인하세요.',
                        style: TextStyle(fontSize: 12),
                      ),
                  ],
                ),
              ),
            ),
            if (result != null && result.hospitals.isEmpty)
              const SliverToBoxAdapter(
                child: ERouteEmptyState(
                  title: '주변 병원을 찾지 못했습니다',
                  message: '검색 위치나 반경을 변경해보세요.',
                ),
              ),
            SliverList.builder(
              itemCount: result?.hospitals.length ?? 0,
              itemBuilder: (context, index) {
                final hospital = result!.hospitals[index];
                return HospitalListTile(
                  key: ValueKey('hospital:${hospital.hpid}'),
                  hospital: hospital,
                  personalization: personalization[hospital.hpid],
                  onReviewReason: onReviewReason == null
                      ? null
                      : () => onReviewReason!(hospital.hpid),
                  manual: state.snapshot!.source == 'MANUAL',
                  selected: state.selectedHpid == hospital.hpid,
                  onTap: () {
                    state.select(hospital.hpid);
                    onHospitalTap?.call(hospital.hpid);
                  },
                );
              },
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: MediaQuery.paddingOf(context).bottom + 24,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
