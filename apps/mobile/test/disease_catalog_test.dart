import 'package:eroute_mobile/features/app_menu/app_session.dart';
import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eroute_mobile/features/auth/auth_repository.dart';
import 'package:eroute_mobile/features/disease_personalization/disease_catalog.dart';
import 'package:eroute_mobile/features/disease_personalization/emergency_condition.dart';
import 'package:eroute_mobile/features/disease_personalization/condition_local_store.dart';
import 'package:eroute_mobile/features/member_ui/member_contract.dart';
import 'support/catalog_fixture.dart';
import 'auth_repository_test.dart' show Adapter, response;

class ConditionsAuth extends AuthRepository {
  int version = 0, puts = 0;
  bool offline = false, lostResponse = false, revoked = false;
  List<Map<String, Object>> entries = [];
  Completer<void>? gate;
  @override
  Future<Response<dynamic>> request(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? headers,
  }) async {
    if (offline) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.connectionError,
      );
    }
    if (revoked) throw const AuthFailure('EXPIRED', 'expired');
    if (method == 'PUT') {
      puts++;
      final input = data as Map;
      expect(input['version'], version);
      entries = List<Map<String, Object>>.from(
        input['conditionEntries'] as List,
      );
      version++;
      if (gate != null) await gate!.future;
      if (lostResponse) {
        lostResponse = false;
        throw DioException(
          requestOptions: RequestOptions(path: path),
          type: DioExceptionType.receiveTimeout,
        );
      }
    }
    return Response(
      requestOptions: RequestOptions(path: path),
      data: {
        'version': version,
        'consentEpoch': 1,
        'status': entries.isEmpty ? 'UNSET' : 'RECORDED',
        'conditionEntries': entries,
        'catalogVersion': 'eroute-disease-catalog-v1',
      },
    );
  }
}

const access = MemberAccess(
  userId: 'user-a',
  phone: 'synthetic',
  sessionGeneration: 1,
  consentEpoch: 1,
  consentState: 'GRANTED',
);
MemberHealthSnapshot health({
  int version = 0,
  List<EmergencyCondition>? entries,
}) => MemberHealthSnapshot(
  version: version,
  consentEpoch: 1,
  conditionEntries: entries ?? [],
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'server catalog identity, category, canonical and aliases, collision rejection',
    () {
      final j = catalogJson();
      final c = DiseaseCatalog.fromJson(j);
      expect(c.diseases.length, 46);
      expect(c.categories.length, 14);
      expect(c.search(' 고 지 혈 증 ').single.id, 'D018');
      expect(c.search('cOpD').single.id, 'D002');
      (j['diseases'][1]['aliases'] as List).add('천식');
      expect(() => DiseaseCatalog.fromJson(j), throwsFormatException);
    },
  );
  test(
    'D047 and new category arrive through real remote parsing without application list changes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final j = catalogJson();
      (j['categories'] as List).add({
        'id': 'CAT_FUTURE',
        'name': '미래 분류',
        'sortOrder': 999,
      });
      (j['diseases'] as List).add({
        'id': 'D047',
        'canonicalName': '테스트질환',
        'categoryId': 'CAT_FUTURE',
        'aliases': ['future'],
        'active': true,
      });
      var offline = false;
      final dio = Dio(BaseOptions(baseUrl: 'http://catalog.fixture'));
      dio.httpClientAdapter = Adapter((r) async {
        if (offline) {
          throw DioException(
            requestOptions: r,
            type: DioExceptionType.connectionError,
          );
        }
        return response(200, j);
      });
      final repo = RemoteDiseaseCatalogRepository(dio);
      final c = await repo.catalog();
      expect(c.search('FUTURE').single.id, 'D047');
      expect(c.byId('D047')!.category, 'CAT_FUTURE');
      offline = true;
      expect((await repo.catalog()).byId('D047')!.name, '테스트질환');
    },
  );
  test(
    'legacy migration preserves entire uncertain input, folds exact aliases and deduplicates',
    () {
      final c = DiseaseCatalog.fromJson(catalogJson());
      expect(migrateConditions(['D018'], '고지혈증', c).length, 1);
      for (final raw in ['심장이 좀 안좋음', '고혈압, 천식', '  혈압문제\n기관지가 약함  ']) {
        final e = migrateConditions([], raw, c).single;
        expect(e.standard, false);
        expect(e.name, raw);
      }
      expect(
        uniqueConditions([
          const EmergencyCondition.custom(' ABC  d '),
          const EmergencyCondition.custom('abc d'),
        ]).length,
        1,
      );
      expect(
        EmergencyCondition.fromJson(
          const EmergencyCondition.custom('고지혈증').toJson(),
        ).standard,
        false,
      );
    },
  );
  test(
    'local-first offline pending survives restart, hides until attach, server confirms',
    () async {
      final vault = MemoryConditionVault();
      final auth = ConditionsAuth()..offline = true;
      final c = ConditionLocalController(
        vault,
        auth,
        FixtureCatalogRepository(),
      );
      await c.attach(access, health());
      await c.save(
        [
          const EmergencyCondition.standard('D001', '천식'),
          const EmergencyCondition.custom('미등록'),
        ],
        'RECORDED',
        'eroute-disease-catalog-v1',
      );
      await c.sync();
      expect(c.state!.pending, true);
      expect(auth.puts, 0);
      expect(jsonDecode(vault.value!)['entries'].length, 2);
      c.suspend();
      expect(c.state, isNull);
      final restored = ConditionLocalController(
        vault,
        auth,
        FixtureCatalogRepository(),
      );
      expect(restored.state, isNull);
      await restored.attach(access, health());
      expect(restored.state!.entries.length, 2);
      auth.offline = false;
      await restored.sync();
      expect(auth.puts, 1);
      expect(restored.state!.pending, false);
      expect(restored.state!.baseVersion, 1);
      c.dispose();
      restored.dispose();
    },
  );
  test(
    'timeout retry verifies server and never repeats an already committed PUT',
    () async {
      final auth = ConditionsAuth()..lostResponse = true;
      final c = ConditionLocalController(
        MemoryConditionVault(),
        auth,
        FixtureCatalogRepository(),
      );
      await c.attach(access, health());
      await c.save(
        [const EmergencyCondition.custom('직접')],
        'RECORDED',
        'eroute-disease-catalog-v1',
      );
      await c.sync();
      expect(c.state!.pending, true);
      await c.sync();
      expect(c.state!.pending, false);
      expect(auth.puts, 1);
      c.dispose();
    },
  );
  test(
    'conflict retains local edit; account or epoch change cannot expose it',
    () async {
      final vault = MemoryConditionVault();
      final auth = ConditionsAuth();
      final c = ConditionLocalController(
        vault,
        auth,
        FixtureCatalogRepository(),
      );
      await c.attach(access, health());
      await c.save(
        [const EmergencyCondition.custom('원문')],
        'RECORDED',
        'eroute-disease-catalog-v1',
      );
      auth.version = 2;
      await c.sync();
      expect(c.state!.conflict, true);
      expect(c.state!.entries.single.name, '원문');
      expect(auth.puts, 0);
      await c.attach(
        const MemberAccess(
          userId: 'user-b',
          phone: 'synthetic',
          sessionGeneration: 2,
          consentEpoch: 1,
          consentState: 'GRANTED',
        ),
        health(),
      );
      expect(c.state!.entries, isEmpty);
      expect(vault.value, isNot(contains('원문')));
      await c.purge();
      expect(vault.value, isNull);
      c.dispose();
    },
  );
  test(
    'direct map entry after restart checks pending ownership without exposing records',
    () async {
      final vault = MemoryConditionVault();
      final c = ConditionLocalController(
        vault,
        ConditionsAuth(),
        FixtureCatalogRepository(),
      );
      await c.attach(access, health());
      await c.save(
        [const EmergencyCondition.custom('미반영')],
        'RECORDED',
        'eroute-disease-catalog-v1',
      );
      c.suspend();
      final session = AppSession(
        phase: SessionPhase.authenticated,
        user: {
          'userId': 'user-a',
          'healthConsent': {'state': 'GRANTED', 'epoch': 1},
        },
      );
      expect(await c.mapReady(session), false);
      expect(c.state, isNull);
      expect(await c.mapReady(const AppSession.signedOut()), false);
      await c.purge();
      expect(await c.mapReady(session), true);
      c.dispose();
    },
  );
  test('an open editor cannot silently adopt a newer server version', () async {
    final c = ConditionLocalController(
      MemoryConditionVault(),
      ConditionsAuth(),
      FixtureCatalogRepository(),
    );
    await c.attach(access, health());
    await c.attach(
      access,
      health(
        version: 2,
        entries: [const EmergencyCondition.custom('다른 곳에서 저장')],
      ),
    );
    await expectLater(
      c.save(
        [const EmergencyCondition.custom('이전 초안')],
        'RECORDED',
        'eroute-disease-catalog-v1',
        expectedBaseVersion: 0,
      ),
      throwsA(isA<MemberFailure>()),
    );
    expect(c.state!.entries.single.name, '다른 곳에서 저장');
    c.dispose();
  });
  test(
    'storage failure never reports a local commit; late response cannot restore after logout',
    () async {
      final vault = MemoryConditionVault();
      final auth = ConditionsAuth();
      final c = ConditionLocalController(
        vault,
        auth,
        FixtureCatalogRepository(),
      );
      await c.attach(access, health());
      vault.fail = true;
      await expectLater(
        c.save(
          [const EmergencyCondition.custom('입력')],
          'RECORDED',
          'eroute-disease-catalog-v1',
        ),
        throwsA(isA<MemberFailure>()),
      );
      expect(c.state!.entries, isEmpty);
      vault.fail = false;
      await c.save(
        [const EmergencyCondition.custom('입력')],
        'RECORDED',
        'eroute-disease-catalog-v1',
      );
      auth.gate = Completer<void>();
      final pending = c.sync();
      await Future<void>.delayed(Duration.zero);
      await c.purge();
      auth.gate!.complete();
      await pending;
      expect(c.state, isNull);
      expect(vault.value, isNull);
      c.dispose();
    },
  );
}
