import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/router.dart';

class EmergencyQuickAction {
  final String label, route;
  final IconData icon;
  const EmergencyQuickAction(this.label, this.route, this.icon);
}

class EmergencyLandingState {
  final List<EmergencyQuickAction> actions;
  const EmergencyLandingState(this.actions);
}

final emergencyLandingProvider = Provider<EmergencyLandingState>(
  (ref) => const EmergencyLandingState([
    EmergencyQuickAction(
      '응급상황 대처요령',
      AppRoutes.emergencyTips,
      Icons.health_and_safety_outlined,
    ),
    EmergencyQuickAction(
      '내 응급정보',
      AppRoutes.emergencyProfile,
      Icons.medical_information_outlined,
    ),
    EmergencyQuickAction(
      '가까운 병원 찾기',
      AppRoutes.map,
      Icons.location_on_outlined,
    ),
    EmergencyQuickAction(
      '응급처치 가이드',
      AppRoutes.firstAid,
      Icons.menu_book_outlined,
    ),
  ]),
);
