import 'package:flutter_riverpod/flutter_riverpod.dart';

enum EmergencyCallStatus { idle, confirming, handingOff }

final emergencyCallStateProvider = StateProvider<EmergencyCallStatus>(
  (ref) => EmergencyCallStatus.idle,
);
