import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class EmergencySmsLauncher {
  Future<bool> canCompose();
  Future<bool> compose(String body);
}

/// Opens only the OS-owned composer. Never sends, logs, or retains the body.
class NativeEmergencySmsLauncher implements EmergencySmsLauncher {
  static const channel = MethodChannel('eroute/emergency_sms');
  const NativeEmergencySmsLauncher();
  @override
  Future<bool> canCompose() async {
    try {
      return await channel.invokeMethod<bool>('canCompose') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> compose(String body) async {
    try {
      return await channel.invokeMethod<bool>('compose', {
            'encodedBody': Uri.encodeComponent(body),
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }
}

final emergencySmsLauncherProvider = Provider<EmergencySmsLauncher>(
  (ref) => const NativeEmergencySmsLauncher(),
);

final emergencySmsCapabilityProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(emergencySmsLauncherProvider).canCompose(),
);
