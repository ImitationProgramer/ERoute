import 'dart:io';

/// Installed only by the isolated Preview entrypoint. Also blocks an accidental
/// new Dio/HttpClient path that bypasses the injected memory repositories.
class PreviewNetworkGuard extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('UI Preview forbids HTTP clients.');
}
