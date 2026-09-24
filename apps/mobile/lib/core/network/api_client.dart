import 'package:dio/dio.dart';
import '../config/app_config.dart';

Dio createApiClient() => Dio(
  BaseOptions(
    baseUrl: AppConfig.apiBaseUrl,
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 18),
    headers: {'Accept': 'application/json'},
  ),
);
