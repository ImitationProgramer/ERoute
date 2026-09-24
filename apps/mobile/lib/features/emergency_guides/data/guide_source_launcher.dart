import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

bool allowedGuideSource(Uri uri) =>
    uri.scheme == 'https' &&
    uri.userInfo.isEmpty &&
    (!uri.hasPort || uri.port == 443) &&
    const {
      'www.nfa.go.kr',
      'www.kdca.go.kr',
      'www.korea.kr',
      '119.gg.go.kr',
      'www.kogl.or.kr',
    }.contains(uri.host);

abstract interface class GuideSourceLauncher {
  Future<bool> open(Uri uri);
}

class HttpsGuideSourceLauncher implements GuideSourceLauncher {
  const HttpsGuideSourceLauncher();
  @override
  Future<bool> open(Uri uri) async {
    if (!allowedGuideSource(uri)) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}

final guideSourceLauncherProvider = Provider<GuideSourceLauncher>(
  (ref) => const HttpsGuideSourceLauncher(),
);
