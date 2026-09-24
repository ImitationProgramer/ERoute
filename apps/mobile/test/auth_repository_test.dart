import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eroute_mobile/features/auth/auth_repository.dart';

class Vault implements TokenVault {
  String? value;
  bool fails = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String? v) async {
    if (fails) throw StateError('synthetic storage failure');
    value = v;
  }
}

class Adapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions) handler;
  Adapter(this.handler);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody response(int status, Object value) => ResponseBody.fromString(
  jsonEncode(value),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);
void main() {
  test(
    'offline logout persists only revocation proof and retries without data credentials',
    () async {
      final vault = Vault();
      var offline = false, logoutCalls = 0;
      final dio = Dio(BaseOptions(baseUrl: 'http://local.test'));
      final access = authNonce(), refresh = authNonce(), logout = authNonce();
      dio.httpClientAdapter = Adapter((r) async {
        if (r.path.endsWith('/complete')) {
          return response(200, {
            'accessToken': access,
            'refreshToken': refresh,
            'logoutProof': logout,
          });
        }
        if (r.path.endsWith('/me')) {
          return response(200, {
            'environment': 'disabled',
            'source': 'DEVELOPMENT',
            'userId': 'test-A',
          });
        }
        if (r.path.endsWith('/logout')) {
          logoutCalls++;
          if (offline) {
            throw DioException(
              requestOptions: r,
              type: DioExceptionType.connectionError,
            );
          }
          return response(200, {});
        }
        throw StateError('Unexpected auth request');
      });
      final repo = AuthRepository(dio: dio, vault: vault);
      await repo.complete('transaction', authNonce(), authNonce());
      expect(vault.value!.contains(access), false);
      offline = true;
      expect(await repo.signOut(), false);
      final stored = jsonDecode(vault.value!) as Map;
      expect(stored['refresh'], isNull);
      expect(stored['logout'], isNull);
      expect(stored['pendingLogout'], [logout]);
      offline = false;
      expect(await repo.retryLogout(), true);
      expect(logoutCalls, 2);
      expect((jsonDecode(vault.value!) as Map)['pendingLogout'], isEmpty);
    },
  );
  test('secure-storage failure still requests server revocation', () async {
    final vault = Vault();
    final dio = Dio(BaseOptions(baseUrl: 'http://local.test'));
    var revoked = false;
    dio.httpClientAdapter = Adapter((r) async {
      if (r.path.endsWith('/complete')) {
        return response(200, {
          'accessToken': authNonce(),
          'refreshToken': authNonce(),
          'logoutProof': authNonce(),
        });
      }
      if (r.path.endsWith('/me')) {
        return response(200, {
          'environment': 'disabled',
          'source': 'DEVELOPMENT',
          'userId': 'test-A',
        });
      }
      if (r.path.endsWith('/logout')) {
        revoked = true;
        return response(200, {});
      }
      throw StateError('Unexpected auth request');
    });
    final repo = AuthRepository(dio: dio, vault: vault);
    await repo.complete('transaction', authNonce(), authNonce());
    vault.fails = true;
    await expectLater(repo.signOut(), throwsA(isA<AuthFailure>()));
    expect(revoked, true);
  });
  test('parallel unauthorized requests share one refresh', () async {
    final vault = Vault();
    final dio = Dio(BaseOptions(baseUrl: 'http://local.test'));
    final initial = authNonce(), next = authNonce();
    var refreshes = 0;
    dio.httpClientAdapter = Adapter((r) async {
      if (r.path.endsWith('/complete')) {
        return response(200, {
          'accessToken': initial,
          'refreshToken': authNonce(),
          'logoutProof': authNonce(),
        });
      }
      if (r.path.endsWith('/me')) {
        return response(200, {
          'environment': 'disabled',
          'source': 'DEVELOPMENT',
          'userId': 'test-A',
        });
      }
      if (r.path.endsWith('/refresh')) {
        refreshes++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return response(200, {
          'accessToken': next,
          'refreshToken': authNonce(),
          'logoutProof': null,
        });
      }
      if (r.path.endsWith('/protected')) {
        return response(
          r.headers['Authorization'] == 'Bearer $next' ? 200 : 401,
          {},
        );
      }
      throw StateError('Unexpected auth request');
    });
    final repo = AuthRepository(dio: dio, vault: vault);
    await repo.complete('transaction', authNonce(), authNonce());
    final results = await Future.wait([
      repo.request('GET', '/protected'),
      repo.request('GET', '/protected'),
    ]);
    expect(results.map((r) => r.statusCode), [200, 200]);
    expect(refreshes, 1);
  });
  test(
    'nonrenewable expiry clears session even when storage deletion fails',
    () async {
      final vault = Vault();
      final dio = Dio(BaseOptions(baseUrl: 'http://local.test'));
      var expired = false;
      dio.httpClientAdapter = Adapter((r) async {
        if (r.path.endsWith('/complete')) {
          return response(200, {
            'accessToken': authNonce(),
            'refreshToken': authNonce(),
            'logoutProof': authNonce(),
          });
        }
        if (r.path.endsWith('/me')) {
          return response(200, {
            'environment': 'disabled',
            'source': 'DEVELOPMENT',
            'userId': 'test-A',
          });
        }
        if (r.path.endsWith('/refresh')) {
          vault.fails = true;
          return response(401, {});
        }
        if (r.path.endsWith('/logout')) {
          return response(200, {});
        }
        throw StateError('Unexpected auth request');
      });
      final repo = AuthRepository(dio: dio, vault: vault);
      await repo.complete('transaction', authNonce(), authNonce());
      repo.onExpired = () {
        expired = true;
      };
      await expectLater(repo.refresh(), throwsA(isA<AuthFailure>()));
      expect(expired, true);
    },
  );
  test(
    'a health reply arriving after logout cannot reach the caller',
    () async {
      final vault = Vault();
      final dio = Dio(BaseOptions(baseUrl: 'http://local.test'));
      final started = Completer<void>(), reply = Completer<ResponseBody>();
      dio.httpClientAdapter = Adapter((r) async {
        if (r.path.endsWith('/complete')) {
          return response(200, {
            'accessToken': authNonce(),
            'refreshToken': authNonce(),
            'logoutProof': authNonce(),
          });
        }
        if (r.path.endsWith('/me')) {
          return response(200, {
            'environment': 'disabled',
            'source': 'DEVELOPMENT',
            'userId': 'test-A',
          });
        }
        if (r.path.endsWith('/protected')) {
          started.complete();
          return reply.future;
        }
        if (r.path.endsWith('/logout')) {
          return response(200, {});
        }
        throw StateError('Unexpected auth request');
      });
      final repo = AuthRepository(dio: dio, vault: vault);
      await repo.complete('transaction', authNonce(), authNonce());
      final pending = repo.request('GET', '/protected');
      final check = expectLater(pending, throwsA(isA<AuthFailure>()));
      await started.future;
      await repo.signOut();
      reply.complete(response(200, {'note': '가상 지연 응답'}));
      await check;
    },
  );
}
