import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'preview/member_preview_app.dart';
import 'preview/preview_network_guard.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Runtime guard, not assert: cannot be removed in profile/release builds.
  if (!kDebugMode || appFlavor != 'preview') {
    throw StateError(
      'Member UI preview requires the preview flavor and debug mode.',
    );
  }
  HttpOverrides.global = PreviewNetworkGuard();
  runApp(const MemberPreviewHost());
}
