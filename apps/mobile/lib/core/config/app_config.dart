class AppConfig {
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const mapClientId = String.fromEnvironment('NAVER_MAP_CLIENT_ID');
  static const authEnvironment = String.fromEnvironment(
    'AUTH_ENVIRONMENT',
    defaultValue: 'disabled',
  );
  static const developmentAuth = bool.fromEnvironment(
    'ENABLE_DEVELOPMENT_AUTH',
  );
}
