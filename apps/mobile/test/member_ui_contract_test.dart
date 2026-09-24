import 'package:flutter_test/flutter_test.dart';
import 'package:eroute_mobile/features/member_ui/member_contract.dart';
import 'package:eroute_mobile/preview/member_preview_repository.dart';

void main() {
  late PreviewMemberRepository repo;
  setUp(
    () => repo = PreviewMemberRepository(
      PreviewAuthRepository(),
      delay: Duration.zero,
    ),
  );
  test(
    'one edit preserves other raw strings, medication list and status',
    () async {
      final before = repo.data;
      final after = await repo.saveField(
        HealthFieldEdit(
          field: HealthField.conditions,
          baseVersion: before.version,
          consentEpoch: before.consentEpoch,
          entry: const HealthEntry(
            EntryStatus.recorded,
            '하나의 긴 문자열, 두 문자열로 분리하지 않음',
          ),
        ),
      );
      expect(after.allergies, same(before.allergies));
      expect(after.note, before.note);
      expect(after.medications, before.medications);
      expect(after.medicationsStatus, before.medicationsStatus);
      expect(after.conditions.text, '하나의 긴 문자열, 두 문자열로 분리하지 않음');
      expect(after.version, before.version + 1);
    },
  );
  test('stale baseVersion never merges or overwrites current values', () async {
    final before = repo.data;
    await repo.saveField(
      HealthFieldEdit(
        field: HealthField.note,
        baseVersion: before.version,
        consentEpoch: before.consentEpoch,
        note: '다른 화면에서 저장한 내용',
      ),
    );
    final current = repo.data;
    await expectLater(
      repo.saveField(
        HealthFieldEdit(
          field: HealthField.allergies,
          baseVersion: before.version,
          consentEpoch: before.consentEpoch,
          entry: const HealthEntry(EntryStatus.none),
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
    expect(repo.data, same(current));
  });
  test(
    'epoch change rejects even if data version matches and new consent is valid',
    () async {
      final before = repo.data;
      repo.epoch++;
      await expectLater(
        repo.saveField(
          HealthFieldEdit(
            field: HealthField.note,
            baseVersion: before.version,
            consentEpoch: before.consentEpoch,
            note: 'must not save',
          ),
        ),
        throwsA(
          isA<MemberFailure>().having(
            (e) => e.kind,
            'kind',
            MemberFailureKind.consent,
          ),
        ),
      );
      expect(repo.data, same(before));
    },
  );
  test(
    'preview reproduces version conflict then permits explicit fresh edit',
    () async {
      repo.reset(PreviewScenario.versionConflict);
      final before = repo.data;
      await expectLater(
        repo.saveField(
          HealthFieldEdit(
            field: HealthField.allergies,
            baseVersion: before.version,
            consentEpoch: before.consentEpoch,
            entry: const HealthEntry(EntryStatus.none),
          ),
        ),
        throwsA(isA<MemberFailure>()),
      );
      final latest = await repo.readHealth();
      expect(latest.note, '다른 기기에서 변경한 가상 메모입니다.');
      expect(latest.allergies.text, before.allergies.text);
      final after = await repo.saveField(
        HealthFieldEdit(
          field: HealthField.allergies,
          baseVersion: latest.version,
          consentEpoch: latest.consentEpoch,
          entry: const HealthEntry(EntryStatus.none),
        ),
      );
      expect(after.note, latest.note);
    },
  );
  test(
    'preview consent conflict revokes reads and never restores obsolete draft',
    () async {
      repo.reset(PreviewScenario.consentConflict);
      final before = repo.data;
      await expectLater(
        repo.saveField(
          HealthFieldEdit(
            field: HealthField.note,
            baseVersion: before.version,
            consentEpoch: before.consentEpoch,
            note: 'must not save',
          ),
        ),
        throwsA(isA<MemberFailure>()),
      );
      expect((await repo.access()).granted, false);
      await expectLater(repo.readHealth(), throwsA(isA<MemberFailure>()));
      expect(repo.data.note, before.note);
    },
  );
  test(
    'medication writes also protect profile version; last deletion is UNSET',
    () async {
      final before = repo.data;
      await repo.deleteMedication(
        before.medications.single,
        before.version,
        before.consentEpoch,
      );
      expect(repo.data.medications, isEmpty);
      expect(repo.data.medicationsStatus, EntryStatus.unset);
      expect(repo.data.allergies, before.allergies);
      await expectLater(
        repo.saveField(
          HealthFieldEdit(
            field: HealthField.note,
            baseVersion: before.version,
            consentEpoch: before.consentEpoch,
            note: 'stale',
          ),
        ),
        throwsA(isA<MemberFailure>()),
      );
    },
  );
  test('account switch during delayed save prevents write', () async {
    repo.delay = const Duration(milliseconds: 10);
    final before = repo.data;
    final save = repo.saveField(
      HealthFieldEdit(
        field: HealthField.note,
        baseVersion: before.version,
        consentEpoch: before.consentEpoch,
        note: 'stale',
      ),
    );
    repo.auth.generation++;
    await expectLater(save, throwsA(isA<MemberFailure>()));
    expect(repo.data, same(before));
  });
  test(
    'profile deletion preserves medications; withdrawal clears all and retains session',
    () async {
      final before = repo.data;
      await repo.deleteProfile(before.version, before.consentEpoch);
      expect(repo.data.medications, before.medications);
      expect(repo.data.allergies.status, EntryStatus.unset);
      await repo.withdrawConsent(repo.epoch, 'preview-request');
      expect(repo.auth.user, isNotNull);
      expect(repo.data.medications, isEmpty);
      expect((await repo.access()).granted, false);
      await repo.withdrawConsent(before.consentEpoch, 'preview-request');
      expect(repo.jobs.single.backupComplete, false);
    },
  );
  test(
    'preview sign-in is conditional, unverified and has no HTTP fallback',
    () async {
      await expectLater(
        repo.authenticate('01012345678', 'wrong', signup: false, terms: false),
        throwsA(isA<MemberFailure>()),
      );
      final user = await repo.authenticate(
        '01012345678',
        'preview-password-only',
        signup: false,
        terms: false,
      );
      expect(user['source'], 'UI_PREVIEW');
      expect(user.containsKey('verified'), false);
      await expectLater(
        repo.auth.request('POST', '/api/v1/me/emergency-profile'),
        throwsStateError,
      );
      await expectLater(
        repo.auth.start('01012345678', 'proof'),
        throwsA(anything),
      );
    },
  );
  test('timestamp omits seconds and fractions', () {
    expect(
      memberTime(DateTime(2026, 9, 15, 10, 2, 39, 123)),
      '2026.09.15 10:02',
    );
  });
}
