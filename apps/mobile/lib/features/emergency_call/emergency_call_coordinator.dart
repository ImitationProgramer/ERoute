import '../emergency_sms/emergency_sms_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'emergency_dialer.dart';
import '../../core/theme/eroute_tokens.dart';
import 'emergency_call_state.dart';

final emergencyCallProvider = Provider(
  (ref) => EmergencyCallCoordinator(
    ref.watch(emergencyDialerProvider),
    smsOption: const EmergencySmsOption(),
    prepareSms: showEmergencySmsPreview,
    onStateChanged: (state) =>
        ref.read(emergencyCallStateProvider.notifier).state = state,
  ),
);

/// Owns call confirmation; optional SMS preparation never gates a call.
class EmergencyCallCoordinator {
  final EmergencyDialer dialer;
  final ValueChanged<EmergencyCallStatus>? onStateChanged;
  bool _busy = false;
  final Widget? smsOption;
  final Future<bool> Function(BuildContext)? prepareSms;
  EmergencyCallCoordinator(
    this.dialer, {
    this.onStateChanged,
    this.smsOption,
    this.prepareSms,
  });

  Future<void> confirm(BuildContext context) async {
    if (_busy) return;
    _busy = true;
    onStateChanged?.call(EmergencyCallStatus.confirming);
    try {
      final confirmed = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('119 신고'),
          scrollable: true,
          content: const Text('긴급 상황에서는 전화 연결을 우선하세요. 위치와 응급정보는 자동 전송되지 않습니다.'),
          actions: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: context.eroute.emergency,
                    foregroundColor: context.eroute.onEmergency,
                  ),
                  onPressed: () => Navigator.pop(context, 'call'),
                  child: const Text('119 전화 연결'),
                ),
                ?smsOption,
                TextButton(
                  autofocus: true,
                  onPressed: () => Navigator.pop(context, 'cancel'),
                  child: const Text('취소'),
                ),
              ],
            ),
          ],
        ),
      );
      if (!context.mounted) return;
      var callRequested = confirmed == 'call';
      if (confirmed == 'sms' && prepareSms != null) {
        callRequested = await prepareSms!(context);
      }
      if (!callRequested || !context.mounted) return;
      onStateChanged?.call(EmergencyCallStatus.handingOff);
      final result = await dialer.dial('119');
      if (!context.mounted || result == DialResult.handedToSystem) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result == DialResult.simulated
                ? '개발 모드: 실제 전화 연결을 실행하지 않았습니다.'
                : '전화 앱을 열 수 없습니다. 기기의 전화 기능에서 119로 연락해주세요.',
          ),
        ),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('전화 기능을 열 수 없습니다. 기기의 전화 기능을 이용해주세요.')),
        );
      }
    } finally {
      _busy = false;
      onStateChanged?.call(EmergencyCallStatus.idle);
    }
  }
}
