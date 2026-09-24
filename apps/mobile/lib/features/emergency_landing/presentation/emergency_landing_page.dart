import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/router.dart';
import '../../../core/theme/eroute_tokens.dart';
import '../../../core/widgets/eroute_buttons.dart';
import '../../../core/widgets/eroute_card.dart';
import '../../../core/widgets/eroute_scaffold.dart';
import '../../emergency_call/emergency_call_coordinator.dart';
import '../../emergency_call/emergency_call_state.dart';
import 'emergency_landing_state.dart';
import 'widgets/landing_illustration.dart';

class EmergencyLandingPage extends ConsumerWidget {
  const EmergencyLandingPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.watch(emergencyLandingProvider).actions;
    final callStatus = ref.watch(emergencyCallStateProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ERouteScaffold(
      actions: [
        TextButton.icon(
          onPressed: () => pushAppRoute(context, AppRoutes.map),
          icon: const Icon(Icons.map_outlined),
          label: const Text('지도 보기'),
        ),
      ],
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: dark
                ? [
                    ERouteColors.backgroundDark,
                    const Color(0xff281e31),
                    ERouteColors.backgroundDark,
                  ]
                : [
                    const Color(0xfffff1f1),
                    ERouteColors.backgroundLight,
                    ERouteColors.backgroundLight,
                  ],
          ),
        ),
        child: Stack(
          children: [
            const Positioned.fill(child: LandingIllustration()),
            Positioned.fill(
              child: SafeArea(
                top: false,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxHeight < 700;
                    final scaledBody = MediaQuery.textScalerOf(
                      context,
                    ).scale(16);
                    final textScale = scaledBody / 16;
                    final diameter =
                        (compact ? 166.0 : 202.0) +
                        110 * (textScale - 1).clamp(0, 1);
                    final singleColumn =
                        scaledBody >= 20 || constraints.maxWidth < 360;
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        ERouteSpacing.md,
                        ERouteSpacing.xs,
                        ERouteSpacing.md,
                        ERouteSpacing.lg,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '지금,\n도움이 필요하신가요?',
                                style: ERouteTypography.hero.copyWith(
                                  fontSize: compact ? 26 : 30,
                                ),
                              ),
                              const SizedBox(height: ERouteSpacing.sm),
                              Text(
                                '긴급한 순간에 119 전화 연결과 주변 응급의료기관 검색을 이용하세요.',
                                style: ERouteTypography.body.copyWith(
                                  color: context.eroute.muted,
                                ),
                              ),
                              SizedBox(height: compact ? 46 : 66),
                              Center(
                                child: ERouteEmergencyButton(
                                  diameter: diameter,
                                  onPressed:
                                      callStatus == EmergencyCallStatus.idle
                                      ? () => ref
                                            .read(emergencyCallProvider)
                                            .confirm(context)
                                      : null,
                                ),
                              ),
                              SizedBox(height: compact ? 52 : 72),
                              GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: singleColumn ? 1 : 2,
                                      mainAxisExtent:
                                          82 +
                                          (singleColumn
                                              ? 82 * (textScale - 1).clamp(0, 1)
                                              : 0),
                                      crossAxisSpacing: ERouteSpacing.sm,
                                      mainAxisSpacing: ERouteSpacing.sm,
                                    ),
                                itemCount: actions.length,
                                itemBuilder: (context, index) {
                                  final action = actions[index];
                                  return ERouteCard(
                                    onTap: () =>
                                        pushAppRoute(context, action.route),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: ERouteSpacing.md,
                                      vertical: ERouteSpacing.sm,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 42,
                                          height: 42,
                                          decoration: BoxDecoration(
                                            color: context.eroute.softBlue,
                                            borderRadius: BorderRadius.circular(
                                              ERouteRadius.control,
                                            ),
                                          ),
                                          child: Icon(
                                            action.icon,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                          ),
                                        ),
                                        const SizedBox(width: ERouteSpacing.sm),
                                        Expanded(
                                          child: Text(
                                            action.label
                                                .split(' ')
                                                .map(
                                                  (word) => word
                                                      .split('')
                                                      .join('\u2060'),
                                                )
                                                .join(' '),
                                            semanticsLabel: action.label,
                                            style: ERouteTypography.label
                                                .copyWith(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
