import 'dart:convert';
import 'password_policy.dart';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';

String authNonce() => base64UrlEncode(
  List<int>.generate(32, (_) => Random.secure().nextInt(256)),
).replaceAll('=', '');
String authChallenge(String proof) => base64UrlEncode(
  sha256.convert(utf8.encode(proof)).bytes,
).replaceAll('=', '');

class AuthFailure implements Exception {
  final String code, message;
  const AuthFailure(this.code, this.message);
  @override
  String toString() => message;
}

String authError(Object error) {
  if (error is AuthFailure) return error.message;
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['code'] == 'INVALID_CREDENTIALS') {
      return '휴대폰 번호 또는 비밀번호를 확인해주세요.';
    }
    if (data is Map && data['code'] == 'SIGNUP_UNAVAILABLE') {
      return '이 정보로 가입할 수 없습니다. 입력 내용을 확인하거나 로그인해주세요.';
    }
    if (data is Map && data['code'] == 'INVALID_PASSWORD') {
      return '비밀번호는 15~128자로 입력해주세요.';
    }
    if (data is Map && data['code'] == 'WEAK_PASSWORD') {
      return '흔하거나 알려진 취약 비밀번호입니다. 다른 비밀번호를 입력해주세요.';
    }
    if (data is Map && data['code'] == 'PRECONDITION_REQUIRED') {
      return '편집 버전 또는 동의 정보가 누락되었습니다. 화면을 다시 열어주세요.';
    }
    if (data is Map && data['code'] == 'AGE_RESTRICTED') {
      return '현재 회원가입은 만 14세 이상부터 가능합니다.\n119 전화 연결과 병원 검색은 가입 없이 이용할 수 있습니다.';
    }
    if (data is Map && data['code'] == 'DATA_VERSION_CONFLICT') {
      return '다른 기기에서 정보가 변경되었습니다. 최신 내용을 다시 확인해주세요.';
    }
    if (data is Map && data['code'] == 'ENCRYPTED_DATA_UNAVAILABLE') {
      return '저장된 정보를 안전하게 읽을 수 없습니다. 내용을 변경하지 않고 다시 시도해주세요.';
    }
    if (error.response?.statusCode == 401) {
      return '로그인 유지 기간이 끝났습니다. 다시 로그인해주세요.';
    }
    if (error.response?.statusCode == 403) {
      return '로그인 권한 또는 건강정보 동의 상태를 확인해주세요.';
    }
    if (error.response?.statusCode == 429) return '요청이 많습니다. 잠시 후 다시 시도해주세요.';
  }
  return '서버에서 상태를 확인하지 못했습니다. 연결을 확인하고 다시 시도해주세요.';
}

abstract interface class TokenVault {
  Future<String?> read();
  Future<void> write(String? value);
}

class SecureTokenVault implements TokenVault {
  final FlutterSecureStorage storage;
  SecureTokenVault({
    this.storage = const FlutterSecureStorage(
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.unlocked_this_device,
      ),
    ),
  });
  String get key =>
      'eroute.auth.${AppConfig.authEnvironment}.${sha256.convert(utf8.encode(AppConfig.apiBaseUrl))}';
  @override
  Future<String?> read() => storage.read(key: key);
  @override
  Future<void> write(String? value) => value == null
      ? storage.delete(key: key)
      : storage.write(key: key, value: value);
}

class AuthRepository {
  final Dio dio;
  final TokenVault vault;
  String? _access, _refresh, _logoutProof, _refreshRequest;
  final List<String> _pendingLogout = [];
  Future<void>? _refreshing;
  Future<void> _storage = Future.value();
  int generation = 0;
  void Function()? onExpired;
  AuthRepository({Dio? dio, TokenVault? vault})
    : dio = dio ?? createApiClient(),
      vault = vault ?? SecureTokenVault();
  Future<void> _persist(int expected) {
    _storage = _storage.catchError((_) {}).then((_) async {
      if (expected != generation) return;
      await vault.write(
        jsonEncode({
          'refresh': _refresh,
          'logout': _logoutProof,
          'refreshRequest': _refreshRequest,
          'pendingLogout': _pendingLogout,
        }),
      );
    });
    return _storage;
  }

  Future<Map<String, dynamic>?> restore() async {
    if (AppConfig.authEnvironment == 'disabled' &&
        dio.options.baseUrl.isEmpty) {
      return null;
    }
    final raw = await vault.read();
    if (raw == null) return null;
    final values = jsonDecode(raw) as Map<String, dynamic>;
    _refresh = values['refresh'] as String?;
    _logoutProof = values['logout'] as String?;
    _refreshRequest = values['refreshRequest'] as String?;
    _pendingLogout.addAll(
      (values['pendingLogout'] as List? ?? []).cast<String>(),
    );
    await retryLogout();
    if (_refresh == null) return null;
    await refresh();
    return me();
  }

  Future<Map<String, dynamic>> passwordLogin(
    String phone,
    String password, {
    bool signup = false,
    bool termsAccepted = false,
    bool age14OrOlder = false,
  }) async {
    final expected = generation;
    final r = await dio.post(
      '/api/v1/auth/${signup ? 'signup' : 'login'}',
      data: {
        'phone': normalizePhone(phone),
        'password': normalizePassword(password),
        if (signup) ...{
          'termsVersion': 'signup-password-v1',
          'termsAccepted': termsAccepted,
          'age14OrOlder': age14OrOlder,
        },
      },
    );
    if (expected != generation) {
      final proof = r.data['logoutProof'];
      if (proof is String) {
        _pendingLogout.add(proof);
        await retryLogout();
      }
      _checkGeneration(expected);
    }
    generation++;
    await _accept(Map<String, dynamic>.from(r.data as Map), generation);
    return me();
  }

  Future<void> reauthenticatePassword(String password) async {
    await request(
      'POST',
      '/api/v1/auth/reauth',
      data: {'password': normalizePassword(password)},
    );
  }

  Future<Map<String, dynamic>> start(
    String phone,
    String proof, {
    bool phoneChange = false,
  }) async {
    final data = {
      'phone': phone,
      'challenge': authChallenge(proof),
      'purpose': phoneChange ? 'PHONE_CHANGE' : 'LOGIN',
    };
    final response = phoneChange
        ? await request('POST', '/api/v1/auth/transactions', data: data)
        : await dio.post('/api/v1/auth/transactions', data: data);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> verifyDevelopment(
    String id,
    String proof,
    String credential,
  ) async {
    if (!AppConfig.developmentAuth ||
        !['local', 'test'].contains(AppConfig.authEnvironment)) {
      throw const AuthFailure(
        'DEVELOPMENT_DISABLED',
        '개발 본인확인이 허용되지 않은 구성입니다.',
      );
    }
    final r = await dio.post(
      '/api/v1/auth/development/transactions/$id/verify',
      data: {'credential': credential},
      options: Options(headers: {'X-Verification-Proof': proof}),
    );
    return Map<String, dynamic>.from(r.data as Map);
  }

  Future<Map<String, dynamic>> complete(
    String id,
    String proof,
    String key, {
    String? terms,
    bool phoneChange = false,
    bool boundSession = false,
  }) async {
    final expected = generation;
    final headers = {'X-Verification-Proof': proof, 'Idempotency-Key': key};
    if (boundSession) {
      await refresh();
      _checkGeneration(expected);
    }
    if (boundSession && _access != null) {
      headers['Authorization'] = 'Bearer $_access';
    }
    final r = await dio.post(
      '/api/v1/auth/transactions/$id/complete',
      data: {'termsVersion': terms, 'confirmPhoneChange': phoneChange},
      options: Options(headers: headers),
    );
    _checkGeneration(expected);
    generation++;
    await _accept(Map<String, dynamic>.from(r.data as Map), generation);
    return me();
  }

  Future<void> _accept(Map<String, dynamic> tokens, int expected) async {
    if (generation != expected) return;
    _access = tokens['accessToken'] as String;
    _refresh = tokens['refreshToken'] as String;
    _logoutProof = tokens['logoutProof'] as String? ?? _logoutProof;
    _refreshRequest = null;
    try {
      await _persist(expected);
    } catch (_) {
      try {
        await signOut();
      } catch (_) {
        /* Report the secure-storage failure below. */
      }
      onExpired?.call();
      throw const AuthFailure(
        'SECURE_STORAGE_FAILED',
        '안전한 로그인 저장소를 사용할 수 없습니다. 다시 시도해주세요.',
      );
    }
  }

  Future<void> refresh() =>
      _refreshing ??= _rotate().whenComplete(() => _refreshing = null);
  Future<void> _rotate() async {
    if (_refresh == null) {
      throw const AuthFailure('SESSION_EXPIRED', '다시 로그인해주세요.');
    }
    final expected = generation;
    _refreshRequest ??= authNonce();
    await _persist(expected);
    try {
      final r = await dio.post(
        '/api/v1/auth/refresh',
        data: {'refreshToken': _refresh},
        options: Options(headers: {'Idempotency-Key': _refreshRequest}),
      );
      if (generation == expected) {
        await _accept(Map<String, dynamic>.from(r.data as Map), expected);
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 && generation == expected) {
        try {
          await signOut();
        } finally {
          onExpired?.call();
        }
      }
      rethrow;
    }
  }

  Future<Response<dynamic>> request(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? headers,
  }) async {
    final expected = generation;
    if (_access == null) await refresh();
    Future<Response<dynamic>> send() => dio.request(
      path,
      data: data,
      options: Options(
        method: method,
        headers: {...?headers, 'Authorization': 'Bearer $_access'},
      ),
    );
    try {
      final r = await send();
      _checkGeneration(expected);
      return r;
    } on DioException catch (e) {
      if (e.response?.statusCode != 401) rethrow;
      await refresh();
      _checkGeneration(expected);
      final r = await send();
      _checkGeneration(expected);
      return r;
    }
  }

  void _checkGeneration(int expected) {
    if (expected != generation) {
      throw const AuthFailure('CANCELLED', '이전 계정의 요청이 취소되었습니다.');
    }
  }

  Future<Map<String, dynamic>> me() async {
    final r = await request('GET', '/api/v1/me');
    final value = Map<String, dynamic>.from(r.data as Map);
    if (value['environment'] != AppConfig.authEnvironment ||
        AppConfig.authEnvironment == 'production' &&
            value['source'] != 'PRODUCTION') {
      await signOut();
      throw const AuthFailure('ENVIRONMENT_MISMATCH', '인증 서버 환경이 일치하지 않습니다.');
    }
    return value;
  }

  Future<bool> signOut() async {
    generation++;
    if (_logoutProof != null) _pendingLogout.add(_logoutProof!);
    _access = null;
    _refresh = null;
    _logoutProof = null;
    _refreshRequest = null;
    bool storageFailed = false;
    try {
      await _persist(generation);
    } catch (_) {
      storageFailed = true;
    }
    final complete = await _sendPendingLogout();
    try {
      await _persist(generation);
    } catch (_) {
      storageFailed = true;
    }
    if (storageFailed) {
      throw const AuthFailure(
        'LOGOUT_STORAGE_FAILED',
        '안전한 저장소 삭제를 확인하지 못했습니다. 서버 로그아웃을 요청했으며 기기 저장소 상태를 다시 확인해야 합니다.',
      );
    }
    return complete;
  }

  Future<bool> _sendPendingLogout() async {
    for (final proof in List<String>.from(_pendingLogout)) {
      try {
        await dio.post('/api/v1/auth/logout', data: {'logoutProof': proof});
        _pendingLogout.remove(proof);
      } catch (_) {
        /* Revocation-only proof: never usable for data access. */
      }
    }
    return _pendingLogout.isEmpty;
  }

  Future<bool> retryLogout() async {
    final complete = await _sendPendingLogout();
    await _persist(generation);
    return complete;
  }

  Future<void> cancel(String id, String proof) async {
    try {
      await dio.delete(
        '/api/v1/auth/transactions/$id',
        options: Options(headers: {'X-Verification-Proof': proof}),
      );
    } catch (_) {}
  }
}
