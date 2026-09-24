import 'package:dio/dio.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:eroute_mobile/features/auth/password_policy.dart';
import 'package:eroute_mobile/features/auth/auth_repository.dart';
import 'package:eroute_mobile/features/member_ui/member_contract.dart';
import 'package:eroute_mobile/features/member_ui/remote_member_repository.dart';

Map<String, dynamic> snapshot(int version) => {
  'version': version,
  'consentEpoch': 3,
  'allergies': {'status': 'NONE', 'text': ''},
  'conditions': {'status': 'RECORDED', 'text': '가상 보존할 기저질환'},
  'note': '가상 기존 메모',
  'medicationsStatus': 'UNSET',
  'medications': [],
  'updatedAt': '2026-09-15T00:00:00Z',
};

class RecordingAuth extends AuthRepository {
  final calls = <(String, String, Object?)>[];
  String user = 'A';
  int version = 4;
  bool conflict = false, offline = false;
  @override
  Future<Map<String, dynamic>> me() async => {
    'userId': user,
    'phone': '*******0000',
    'role': 'MEMBER',
    'healthConsent': {'state': 'GRANTED', 'epoch': 3},
  };
  @override
  Future<Response<dynamic>> request(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? headers,
  }) async {
    calls.add((method, path, data));
    final options = RequestOptions(path: path);
    if (offline) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    if (method == 'PUT' && conflict) {
      throw DioException(
        requestOptions: options,
        response: Response(
          requestOptions: options,
          statusCode: 409,
          data: {'code': 'DATA_VERSION_CONFLICT'},
        ),
      );
    }
    return Response(
      requestOptions: options,
      data: path.endsWith('/withdrawals')
          ? []
          : path.endsWith('/health-snapshot')
          ? snapshot(version)
          : snapshot(version + 1),
    );
  }
}

void main() {
  test('shared Unicode 17 NFC conformance', () {
    final vectors =
        jsonDecode(
              File(
                '../../contracts/fixtures/password-nfc-unicode17.json',
              ).readAsStringSync(),
            )
            as List;
    for (final row in vectors) {
      expect(
        normalizePassword('xxxxxxxxxxxxxx ${row[0]}'),
        'xxxxxxxxxxxxxx ${row[1]}',
      );
    }
  });
  test('NFC codepoints and phone formatting match server policy', () {
    for (final length in [14, 129]) {
      expect(passwordValidation('😀' * length), isNotNull);
    }
    for (final length in [15, 128]) {
      expect(passwordValidation('😀' * length), isNull);
    }
    const raw = '  A 가 e\u0301 😀 가나다라마바 ';
    expect(normalizePassword(raw), '  A 가 é 😀 가나다라마바 ');
    expect(normalizePhone('010-1234 5678'), '01012345678');
  });
  test(
    'field PUT uses original snapshot even after newer GET and never auto retries conflict',
    () async {
      final auth = RecordingAuth();
      final repo = RemoteMemberRepository(auth);
      await repo.access();
      await repo.readHealth();
      auth.version = 5;
      await repo.readHealth();
      await repo.saveField(
        const HealthFieldEdit(
          field: HealthField.note,
          baseVersion: 4,
          consentEpoch: 3,
          note: '가상 수정 메모',
        ),
      );
      final sent = auth.calls.last.$3 as Map;
      expect(sent['version'], 4);
      expect(sent['consentEpoch'], 3);
      expect((sent['conditions'] as Map)['text'], '가상 보존할 기저질환');
      expect((sent['allergies'] as Map)['status'], 'NONE');
      auth.conflict = true;
      final before = auth.calls.length;
      await expectLater(
        repo.saveField(
          const HealthFieldEdit(
            field: HealthField.note,
            baseVersion: 4,
            consentEpoch: 3,
            note: '가상 충돌',
          ),
        ),
        throwsA(
          isA<MemberFailure>().having(
            (e) => e.kind,
            'kind',
            MemberFailureKind.conflict,
          ),
        ),
      );
      expect(auth.calls.length, before + 1);
    },
  );
  test(
    'medication DTO includes required preconditions; account switch clears old bases; network failure is not success',
    () async {
      final auth = RecordingAuth();
      final repo = RemoteMemberRepository(auth);
      await repo.access();
      await repo.readHealth();
      await repo.saveMedication(
        name: '가상약',
        note: '',
        baseVersion: 4,
        consentEpoch: 3,
      );
      final sent = auth.calls.last.$3 as Map;
      expect(sent['baseVersion'], 4);
      expect(sent['consentEpoch'], 3);
      expect(sent.containsKey('productCode'), false);
      auth.user = 'B';
      auth.generation++;
      await repo.access();
      await expectLater(
        repo.saveField(
          const HealthFieldEdit(
            field: HealthField.note,
            baseVersion: 4,
            consentEpoch: 3,
            note: '가상 이전 계정',
          ),
        ),
        throwsA(isA<MemberFailure>()),
      );
      auth.offline = true;
      await expectLater(
        repo.saveMedication(
          name: '가상약',
          note: '',
          baseVersion: 0,
          consentEpoch: 3,
        ),
        throwsA(isA<MemberFailure>()),
      );
    },
  );
}
