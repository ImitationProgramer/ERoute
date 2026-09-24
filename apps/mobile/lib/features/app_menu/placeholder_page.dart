import '../disease_personalization/disease_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../app/router.dart';
import '../../core/theme/eroute_tokens.dart';
import '../../core/widgets/eroute_buttons.dart';
import '../../core/widgets/eroute_scaffold.dart';
import 'app_session.dart';
import '../emergency_guides/data/asset_guide_repository.dart';

class PlaceholderDefinition {
  final String title, message;
  final bool requiresLogin, about;
  const PlaceholderDefinition(
    this.title,
    this.message, {
    this.requiresLogin = false,
    this.about = false,
  });
}

class PlaceholderPage extends ConsumerWidget {
  final PlaceholderDefinition definition;
  const PlaceholderPage({super.key, required this.definition});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final loginRequired = definition.requiresLogin && !session.authenticated;
    return ERouteScaffold(
      title: definition.title,
      showBack: true,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(ERouteSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  loginRequired
                      ? Icons.lock_outline_rounded
                      : Icons.construction_rounded,
                  size: 52,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: ERouteSpacing.md),
                if (definition.about)
                  FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (_, snapshot) => Text(
                      snapshot.hasData
                          ? 'ERoute\n버전 ${snapshot.data!.version} (${snapshot.data!.buildNumber})'
                          : 'ERoute\n앱 버전을 확인하고 있습니다.',
                      textAlign: TextAlign.center,
                      style: ERouteTypography.body,
                    ),
                  )
                else ...[
                  Text(
                    loginRequired ? '로그인이 필요한 기능입니다.' : definition.message,
                    textAlign: TextAlign.center,
                    style: ERouteTypography.body,
                  ),
                  if (loginRequired) ...[
                    const SizedBox(height: ERouteSpacing.lg),
                    ERoutePrimaryButton(
                      onPressed: () => pushAppRoute(context, AppRoutes.login),
                      label: const Text('로그인 안내 보기'),
                      icon: Icons.login_rounded,
                    ),
                  ],
                ],
                if (definition.about && diseaseReviewAvailable) ...[
                  const SizedBox(height: 24),
                  OutlinedButton(
                    onPressed: () =>
                        pushAppRoute(context, AppRoutes.diseaseReview),
                    child: const Text('개발 검증 · 질환-진료과 매칭'),
                  ),
                ],
                if (definition.about && guideReviewAvailable) ...[
                  const SizedBox(height: 24),
                  OutlinedButton(
                    onPressed: () =>
                        pushAppRoute(context, AppRoutes.guideReview),
                    child: const Text('개발 검수 · 응급 가이드 원고'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
