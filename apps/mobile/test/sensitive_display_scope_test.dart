import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eroute_mobile/features/member_ui/member_widgets.dart';

class RecordingPrivacy implements MemberPrivacy {
  final calls = <bool>[];
  @override
  Future<void> sensitive(bool value) async {
    calls.add(value);
  }

  @override
  Future<void> allowDisplay() async {}
}

void main() {
  testWidgets(
    'second sensitive scope can release last without reading disposed ref',
    (tester) async {
      final privacy = RecordingPrivacy();
      Future<void> show(List<String> ids) => tester.pumpWidget(
        ProviderScope(
          overrides: [memberPrivacyProvider.overrideWithValue(privacy)],
          child: MaterialApp(
            home: Column(
              children: [
                for (final id in ids)
                  SensitiveDisplayScope(
                    key: ValueKey(id),
                    enabled: true,
                    child: Text(id),
                  ),
              ],
            ),
          ),
        ),
      );
      await show(['first', 'second']);
      expect(privacy.calls, [true]);
      await show(['second']);
      expect(privacy.calls, [true]);
      await show([]);
      expect(privacy.calls, [true, false]);
      expect(tester.takeException(), isNull);
    },
  );
}
