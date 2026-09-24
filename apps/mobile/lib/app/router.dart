import '../features/disease_personalization/disease_review_screen.dart';
import 'package:flutter/material.dart';
import '../features/emergency_landing/presentation/emergency_landing_page.dart';
import '../features/emergency_map/presentation/emergency_map_page.dart';
import '../features/hospital_detail/presentation/hospital_detail_page.dart';
import '../features/app_menu/placeholder_page.dart';
import '../features/member_ui/member_auth_screen.dart';
import '../features/member_ui/member_profile_screen.dart';
import '../features/member_ui/member_health_screens.dart';
import '../features/member_ui/member_route_gate.dart';
import '../features/emergency_guides/data/asset_guide_repository.dart';
import '../features/emergency_guides/presentation/guide_pages.dart';

abstract final class AppRoutes {
  static const landing = '/';
  static const map = '/map';
  static const login = '/login';
  static const profile = '/profile';
  static const emergencyProfile = '/emergency-profile';
  static const settings = '/settings';
  static const about = '/about';
  static const emergencyTips = '/emergency-tips';
  static const firstAid = '/first-aid';
  static const guideReview = '/development/guides';
  static const diseaseReview = '/development/disease-matching';
  static String guide(String id, {bool review = false}) =>
      '${review ? guideReview : '/guides'}/article/${Uri.encodeComponent(id)}';
  static String hospital(String hpid) =>
      '/hospital/${Uri.encodeComponent(hpid)}';
}

final appRouteObserver = RouteObserver<ModalRoute<void>>();

Route<void> buildAppRoute(RouteSettings settings) {
  final name = settings.name ?? AppRoutes.landing;
  if (diseaseReviewAvailable && name == AppRoutes.diseaseReview) {
    return _page(settings, const DiseaseReviewScreen());
  }
  if (name == AppRoutes.landing) {
    return _page(settings, const EmergencyLandingPage());
  }
  if (name == AppRoutes.map) return _page(settings, const EmergencyMapPage());
  if (name == AppRoutes.emergencyTips) {
    return _page(settings, const GuideIndexPage(category: 'actions'));
  }
  if (name == AppRoutes.firstAid) {
    return _page(settings, const GuideIndexPage(category: 'firstAid'));
  }
  if (name.startsWith('/guides/article/')) {
    return _page(
      settings,
      GuideDetailPage(id: name.substring('/guides/article/'.length)),
    );
  }
  if (guideReviewAvailable) {
    if (name == AppRoutes.guideReview) {
      return _page(settings, const GuideReviewHome());
    }
    for (final category in ['actions', 'firstAid']) {
      if (name == '${AppRoutes.guideReview}/$category') {
        return _page(
          settings,
          GuideIndexPage(category: category, review: true),
        );
      }
    }
    if (name.startsWith('${AppRoutes.guideReview}/article/')) {
      return _page(
        settings,
        GuideDetailPage(
          id: name.substring('${AppRoutes.guideReview}/article/'.length),
          review: true,
        ),
      );
    }
  }
  if (name.startsWith('/hospital/')) {
    final hpid = Uri.decodeComponent(name.substring('/hospital/'.length));
    return _page(settings, HospitalDetailPage(hpid: hpid));
  }
  if (name == AppRoutes.login) return _page(settings, const MemberAuthScreen());
  if (name == AppRoutes.profile) {
    return _page(
      settings,
      const MemberRouteGate(
        destination: AppRoutes.profile,
        child: MemberAccountScreen(),
      ),
    );
  }
  if (name == AppRoutes.emergencyProfile) {
    return _page(
      settings,
      const MemberRouteGate(
        destination: AppRoutes.emergencyProfile,
        child: MemberEmergencyScreen(),
      ),
    );
  }
  final definition = switch (name) {
    AppRoutes.settings => const PlaceholderDefinition(
      '설정',
      '설정 기능을 준비하고 있습니다.',
    ),
    AppRoutes.about => const PlaceholderDefinition('앱 정보', '', about: true),
    _ => const PlaceholderDefinition(
      '페이지를 찾을 수 없습니다',
      '이전 화면으로 돌아가 다시 시도해주세요.',
    ),
  };
  return _page(settings, PlaceholderPage(definition: definition));
}

MaterialPageRoute<void> _page(RouteSettings settings, Widget child) =>
    MaterialPageRoute<void>(settings: settings, builder: (_) => child);

Future<void> pushAppRoute(BuildContext context, String name) {
  if (ModalRoute.of(context)?.settings.name == name) return Future.value();
  return Navigator.of(
    context,
  ).push<void>(buildAppRoute(RouteSettings(name: name)));
}
