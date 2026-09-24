import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/eroute_scaffold.dart';
import '../app_menu/app_session.dart';
import '../auth/auth_repository.dart';
import 'health_draft.dart';

class MemberHealthPage extends ConsumerStatefulWidget {
  const MemberHealthPage({super.key});
  @override
  ConsumerState<MemberHealthPage> createState() => _MemberHealthPageState();
}

class _MemberHealthPageState extends ConsumerState<MemberHealthPage>
    with WidgetsBindingObserver {
  static const privacy = MethodChannel('eroute/privacy');
  final allergies = TextEditingController(),
      conditions = TextEditingController(),
      note = TextEditingController();
  final medicationName = TextEditingController(),
      medicationNote = TextEditingController();
  final watch = Stopwatch()..start();
  late final HealthDraft draft = HealthDraft(elapsed: () => watch.elapsed);
  Map<String, dynamic>? profile, editingMedication;
  List<Map<String, dynamic>> medications = [], jobs = [];
  String allergyStatus = 'UNSET',
      conditionStatus = 'UNSET',
      medicationStatus = 'UNSET',
      consentState = 'UNSET';
  int epoch = 0, version = 0, requestGeneration = 0;
  bool covered = true, busy = false, foreground = true, agreed = false;
  String? error, notice, withdrawalKey;
  bool conflict = false;
  Timer? timer;
  int ticks = 0;
  AuthRepository get repo => ref.read(authRepositoryProvider);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _native('setSensitive', true);
    WidgetsBinding.instance.addPostFrameCallback((_) => reload());
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (draft.expired) {
        purge();
        if (mounted) {
          setState(() {
            covered = true;
            notice = '편집 초안 보존시간이 지나 제거했습니다.';
          });
          if (foreground) reload();
        }
      }
      if (++ticks % 10 == 0 && foreground && !busy && !covered) checkConsent();
    });
  }

  Future<void> _native(String method, [Object? argument]) async {
    try {
      await privacy.invokeMethod<void>(method, argument);
    } on MissingPluginException {
      /* Unit tests have no native window. */
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _native('setSensitive', false);
    draft.clear();
    for (final c in [
      allergies,
      conditions,
      note,
      medicationName,
      medicationNote,
    ]) {
      c.clear();
      c.dispose();
    }
    watch.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) {
      requestGeneration++;
      profile = null;
      medications = [];
      editingMedication = null;
      for (final c in [
        allergies,
        conditions,
        note,
        medicationName,
        medicationNote,
      ]) {
        c.clear();
      }
      setState(() => covered = true);
    } else {
      setState(() => covered = true);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _native('allowDisplay'),
      );
      reload();
    }
  }

  void purge() {
    requestGeneration++;
    draft.clear();
    conflict = false;
    profile = null;
    medications = [];
    editingMedication = null;
    for (final c in [
      allergies,
      conditions,
      note,
      medicationName,
      medicationNote,
    ]) {
      c.clear();
    }
    allergyStatus = conditionStatus = medicationStatus = 'UNSET';
  }

  Future<void> checkConsent() async {
    final request = requestGeneration;
    try {
      final r = await repo.request('GET', '/api/v1/me/health-consent');
      if (!mounted || request != requestGeneration) return;
      if (r.data['epoch'] != epoch || r.data['state'] != consentState) {
        purge();
        setState(() {
          covered = true;
        });
        await reload();
      }
    } catch (_) {
      /* Connection loss is not withdrawal; request authorization remains authoritative. */
    }
  }

  Future<void> reload() async {
    final request = ++requestGeneration;
    setState(() {
      covered = true;
      busy = true;
      error = null;
    });
    try {
      final user = await ref
          .read(sessionControllerProvider.notifier)
          .revalidate();
      if (!mounted || request != requestGeneration || !foreground) return;
      final consent = Map<String, dynamic>.from(user['healthConsent'] as Map);
      final nextEpoch = consent['epoch'] as int,
          nextState = consent['state'] as String;
      if (epoch != nextEpoch || nextState != 'GRANTED') purge();
      // purge invalidates outstanding requests; this continuation owns the new state.
      final continuation = requestGeneration;
      epoch = nextEpoch;
      consentState = nextState;
      if (consentState == 'GRANTED') {
        final p = await repo.request('GET', '/api/v1/me/emergency-profile');
        final m = await repo.request('GET', '/api/v1/me/medications');
        final finalConsent = await repo.request(
          'GET',
          '/api/v1/me/health-consent',
        );
        if (!mounted || continuation != requestGeneration || !foreground) {
          return;
        }
        if (finalConsent.data['epoch'] != epoch ||
            finalConsent.data['state'] != 'GRANTED') {
          purge();
          await reload();
          return;
        }
        profile = Map<String, dynamic>.from(p.data as Map);
        version = profile!['version'] as int;
        medications = (m.data as List)
            .map((x) => Map<String, dynamic>.from(x as Map))
            .toList();
        final session = ref.read(sessionProvider);
        final saved = draft.restore(
          session.userId!,
          session.generation,
          epoch,
          version,
        );
        if (draft.values != null && saved == null) {
          setState(() {
            conflict = true;
            covered = true;
            busy = false;
            error = '다른 기기에서 정보가 변경되었습니다. 기존 초안을 자동으로 덮어쓰거나 복원하지 않습니다.';
          });
          return;
        }
        apply(saved ?? profile!);
      } else {
        final j = await repo.request(
          'GET',
          '/api/v1/me/health-consent/withdrawals',
        );
        if (!mounted || continuation != requestGeneration || !foreground) {
          return;
        }
        jobs = (j.data as List)
            .map((x) => Map<String, dynamic>.from(x as Map))
            .toList();
      }
      if (mounted && foreground) {
        setState(() {
          covered = false;
          busy = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (e is DioException && [401, 403].contains(e.response?.statusCode)) {
        purge();
      }
      setState(() {
        covered = true;
        busy = false;
        error = authError(e);
      });
    }
  }

  void apply(Map<String, dynamic> value) {
    allergyStatus = (value['allergies'] as Map)['status'] as String;
    allergies.text = (value['allergies'] as Map)['text'] as String;
    conditionStatus = (value['conditions'] as Map)['status'] as String;
    conditions.text = (value['conditions'] as Map)['text'] as String;
    note.text = value['note'] as String;
    medicationStatus = value['medicationsStatus'] as String;
    medicationName.text = value['draftMedicationName'] as String? ?? '';
    medicationNote.text = value['draftMedicationNote'] as String? ?? '';
    editingMedication =
        value['draftEditingMedication'] as Map<String, dynamic>?;
  }

  Map<String, dynamic> body() => {
    'consentEpoch': epoch,
    'version': version,
    'allergies': {'status': allergyStatus, 'text': allergies.text},
    'conditions': {'status': conditionStatus, 'text': conditions.text},
    'note': note.text,
    'medicationsStatus': medicationStatus,
  };
  void edited() {
    final session = ref.read(sessionProvider);
    if (!session.authenticated || covered) return;
    draft.edit(
      user: session.userId!,
      session: session.generation,
      epoch: epoch,
      version: version,
      data: {
        ...body(),
        'draftMedicationName': medicationName.text,
        'draftMedicationNote': medicationNote.text,
        'draftEditingMedication': editingMedication,
      },
    );
  }

  Future<bool> confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(c, false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> mutate(
    Future<void> Function() operation, {
    bool preserveDraft = false,
  }) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await operation();
      if (!mounted) return;
      if (!preserveDraft) draft.clear();
      notice = '서버에 반영되었습니다.';
      await reload();
    } catch (e) {
      if (mounted) {
        if (e is DioException && [401, 403].contains(e.response?.statusCode)) {
          purge();
          covered = true;
        }
        setState(() {
          error = authError(e);
          busy = false;
        });
      }
    }
  }

  Widget statusField(
    String label,
    String status,
    TextEditingController controller,
    void Function(String) change,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: Theme.of(context).textTheme.titleMedium),
      DropdownButtonFormField<String>(
        initialValue: status,
        key: ValueKey('$label:$status'),
        decoration: InputDecoration(labelText: '$label 입력 상태'),
        items: const [
          DropdownMenuItem(value: 'UNSET', child: Text('미입력')),
          DropdownMenuItem(value: 'NONE', child: Text('없음 (직접 확인)')),
          DropdownMenuItem(value: 'RECORDED', child: Text('내용 입력')),
        ],
        onChanged: busy
            ? null
            : (v) {
                setState(() {
                  change(v!);
                  if (v != 'RECORDED') controller.clear();
                });
                edited();
              },
      ),
      if (status == 'RECORDED')
        TextField(
          controller: controller,
          enabled: !busy,
          maxLength: 2000,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(labelText: '$label 내용'),
          onChanged: (_) => edited(),
        ),
      const SizedBox(height: 20),
    ],
  );
  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider, (previous, next) {
      if (!next.authenticated ||
          previous?.userId != next.userId ||
          previous?.generation != next.generation) {
        purge();
        if (mounted) setState(() => covered = true);
      }
    });
    final member = ref.watch(sessionProvider).user?['role'] == 'MEMBER';
    return PopScope(
      canPop: draft.values == null,
      onPopInvokedWithResult: (popped, _) async {
        if (!popped &&
            await confirm('편집 중인 내용', '저장하지 않은 메모리 초안을 버리고 나갈까요?', '버리고 나가기') &&
            mounted) {
          setState(() => draft.clear());
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.pop(context);
          });
        }
      },
      child: ERouteScaffold(
        title: '내 응급정보',
        showBack: true,
        body: SafeArea(
          child: !member
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      '일반 회원 본인의 정보만 관리할 수 있습니다. 운영자에게 의료정보 접근 권한은 부여되지 않습니다.',
                    ),
                  ),
                )
              : covered
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_outline, size: 40),
                        const SizedBox(height: 16),
                        Text(error ?? '건강정보를 보호하고 있습니다. 로그인과 동의 상태를 확인합니다.'),
                        if (notice != null) Text(notice!),
                        const SizedBox(height: 16),
                        if (conflict)
                          TextButton(
                            onPressed: busy
                                ? null
                                : () async {
                                    if (await confirm(
                                          '초안 버리기',
                                          '저장하지 않은 초안을 버리고 최신 정보를 확인합니다.',
                                          '초안 버리기',
                                        ) &&
                                        mounted) {
                                      draft.clear();
                                      conflict = false;
                                      await reload();
                                    }
                                  },
                            child: const Text('초안을 버리고 최신정보 보기'),
                          ),
                        FilledButton(
                          onPressed: busy ? null : reload,
                          child: Text(busy ? '확인 중…' : '다시 확인'),
                        ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (ref.watch(sessionProvider).user?['source'] ==
                              'DEVELOPMENT')
                            const Text('개발 계정 · 가상 건강정보만 입력하세요.'),
                          if (error != null)
                            Semantics(liveRegion: true, child: Text(error!)),
                          if (notice != null)
                            Semantics(liveRegion: true, child: Text(notice!)),
                          if (consentState != 'GRANTED') ...[
                            const SizedBox(height: 16),
                            const Text(
                              '건강정보 처리 동의',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              '목적: 본인의 응급정보와 복용약 저장·조회\n항목: 알레르기, 기저질환, 응급 메모, 약 이름·복용 메모\n입력은 선택 사항입니다. 동의 철회 시 서비스 데이터는 삭제하며 백업은 최대 30일의 별도 파기 확인 대상입니다.\n일반 회원 계정·병원 검색·119 전화 연결은 유지됩니다.\n개발 검증용 문서 health-v1',
                            ),
                            if (consentState == 'REVOKING')
                              const Text(
                                '동의 철회가 접수되어 건강정보 접근이 차단되었습니다. 삭제 작업을 확인해주세요.',
                              )
                            else ...[
                              CheckboxListTile(
                                value: agreed,
                                onChanged: busy
                                    ? null
                                    : (v) => setState(() => agreed = v!),
                                title: const Text('건강정보 처리에 별도로 동의합니다'),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                              ),
                              FilledButton(
                                onPressed: busy || !agreed
                                    ? null
                                    : () => mutate(() async {
                                        await repo.request(
                                          'POST',
                                          '/api/v1/me/health-consent',
                                          data: {
                                            'documentVersion': 'health-v1',
                                            'epoch': epoch,
                                          },
                                        );
                                      }),
                                child: const Text('동의하고 시작'),
                              ),
                            ],
                            for (final job in jobs)
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        job['state'] == 'COMPLETE'
                                            ? '서비스 건강정보 삭제 완료'
                                            : '삭제 처리 중 · 재처리 필요',
                                      ),
                                      Text(
                                        job['backupComplete'] == true
                                            ? '백업 파기 확인 완료'
                                            : '백업 파기는 별도 확인 중입니다.',
                                      ),
                                      if (job['state'] != 'COMPLETE')
                                        TextButton(
                                          onPressed: busy
                                              ? null
                                              : () => mutate(() async {
                                                  await repo.request(
                                                    'POST',
                                                    '/api/v1/me/health-consent/withdrawals/${job['id']}/retry',
                                                  );
                                                }),
                                          child: const Text('삭제 재시도'),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            TextButton(
                              onPressed: busy ? null : reload,
                              child: const Text('처리 상태 다시 확인'),
                            ),
                          ] else ...[
                            const SizedBox(height: 16),
                            const Text('사용자가 직접 입력한 정보입니다. 의료진이 검증한 기록이 아닙니다.'),
                            Text(
                              profile?['updatedAt'] == null
                                  ? '아직 저장된 응급정보가 없습니다.'
                                  : '마지막 수정: ${DateTime.parse(profile!['updatedAt'] as String).toLocal()}',
                            ),
                            const SizedBox(height: 24),
                            statusField(
                              '알레르기',
                              allergyStatus,
                              allergies,
                              (v) => allergyStatus = v,
                            ),
                            statusField(
                              '기저질환',
                              conditionStatus,
                              conditions,
                              (v) => conditionStatus = v,
                            ),
                            TextField(
                              controller: note,
                              enabled: !busy,
                              minLines: 3,
                              maxLines: 6,
                              maxLength: 2000,
                              decoration: const InputDecoration(
                                labelText: '응급 메모 (선택)',
                              ),
                              onChanged: (_) => edited(),
                            ),
                            FilledButton(
                              onPressed: busy
                                  ? null
                                  : () => mutate(() async {
                                      await repo.request(
                                        'PUT',
                                        '/api/v1/me/emergency-profile',
                                        data: body(),
                                      );
                                    }),
                              child: const Text('응급정보 저장'),
                            ),
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () async {
                                      if (await confirm(
                                        '응급 기록 삭제',
                                        '알레르기·기저질환·응급 메모를 삭제합니다. 복용약은 유지됩니다.',
                                        '삭제',
                                      )) {
                                        await mutate(() async {
                                          await repo.request(
                                            'DELETE',
                                            '/api/v1/me/emergency-profile',
                                            data: {
                                              'version': version,
                                              'consentEpoch': epoch,
                                            },
                                          );
                                        });
                                      }
                                    },
                              child: const Text('응급 기록 삭제'),
                            ),
                            const Divider(height: 40),
                            Text(
                              '복용약',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const Text(
                              '약 이름과 메모를 직접 입력합니다. 용량·횟수 추천이나 복약 안전 판정은 제공하지 않습니다.',
                            ),
                            if (medications.isEmpty)
                              DropdownButtonFormField<String>(
                                initialValue: medicationStatus == 'NONE'
                                    ? 'NONE'
                                    : 'UNSET',
                                key: ValueKey('med-status:$medicationStatus'),
                                decoration: const InputDecoration(
                                  labelText: '복용약 입력 상태',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'UNSET',
                                    child: Text('미입력'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'NONE',
                                    child: Text('없음 (직접 확인)'),
                                  ),
                                ],
                                onChanged: busy
                                    ? null
                                    : (v) {
                                        setState(() => medicationStatus = v!);
                                        edited();
                                      },
                              ),
                            for (final med in medications)
                              Card(
                                child: ListTile(
                                  title: Text(med['name'] as String),
                                  subtitle: Text(
                                    '${med['note']}\n직접 입력 · ${DateTime.parse(med['updatedAt'] as String).toLocal()}',
                                  ),
                                  trailing: Wrap(
                                    children: [
                                      IconButton(
                                        tooltip: '복용약 수정',
                                        onPressed: busy
                                            ? null
                                            : () {
                                                setState(() {
                                                  editingMedication = med;
                                                  medicationName.text =
                                                      med['name'] as String;
                                                  medicationNote.text =
                                                      med['note'] as String;
                                                });
                                                edited();
                                              },
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                      IconButton(
                                        tooltip: '복용약 삭제',
                                        onPressed: busy
                                            ? null
                                            : () async {
                                                if (await confirm(
                                                  '복용약 삭제',
                                                  '선택한 수동 복용약 기록을 삭제합니다.',
                                                  '삭제',
                                                )) {
                                                  await mutate(() async {
                                                    await repo.request(
                                                      'DELETE',
                                                      '/api/v1/me/medications/${med['id']}?consentEpoch=$epoch&version=${med['version']}',
                                                    );
                                                  });
                                                }
                                              },
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            const SizedBox(height: 16),
                            Text(
                              editingMedication == null
                                  ? '복용약 수동 등록'
                                  : '복용약 수정',
                            ),
                            TextField(
                              controller: medicationName,
                              enabled: !busy,
                              maxLength: 200,
                              decoration: const InputDecoration(
                                labelText: '약 이름',
                              ),
                              onChanged: (_) => edited(),
                            ),
                            TextField(
                              controller: medicationNote,
                              enabled: !busy,
                              maxLength: 2000,
                              minLines: 2,
                              maxLines: 4,
                              decoration: const InputDecoration(
                                labelText: '복용 메모 (선택)',
                              ),
                              onChanged: (_) => edited(),
                            ),
                            FilledButton.tonal(
                              onPressed: busy
                                  ? null
                                  : () => mutate(() async {
                                      if (medicationName.text.trim().isEmpty) {
                                        throw const AuthFailure(
                                          'NAME_REQUIRED',
                                          '약 이름을 입력해주세요.',
                                        );
                                      }
                                      await repo.request(
                                        editingMedication == null
                                            ? 'POST'
                                            : 'PUT',
                                        '/api/v1/me/medications${editingMedication == null ? '' : '/${editingMedication!['id']}'}',
                                        data: {
                                          'consentEpoch': epoch,
                                          if (editingMedication != null)
                                            'version':
                                                editingMedication!['version'],
                                          'name': medicationName.text,
                                          'note': medicationNote.text,
                                        },
                                      );
                                      editingMedication = null;
                                      medicationName.clear();
                                      medicationNote.clear();
                                    }),
                              child: Text(
                                editingMedication == null
                                    ? '복용약 등록'
                                    : '복용약 수정 저장',
                              ),
                            ),
                            const Divider(height: 40),
                            OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () async {
                                      if (!await confirm(
                                        '건강정보 동의 철회',
                                        '알레르기·기저질환·응급 메모·모든 복용약과 메모를 삭제합니다. 일반 계정과 로그인은 유지됩니다. 백업 파기는 별도로 확인합니다.',
                                        '동의 철회 및 삭제',
                                      )) {
                                        return;
                                      }
                                      final oldEpoch = epoch;
                                      withdrawalKey ??= authNonce();
                                      purge();
                                      setState(() => covered = true);
                                      await mutate(() async {
                                        await repo.request(
                                          'POST',
                                          '/api/v1/me/health-consent/withdrawals',
                                          data: {'epoch': oldEpoch},
                                          headers: {
                                            'Idempotency-Key': withdrawalKey,
                                          },
                                        );
                                        withdrawalKey = null;
                                      });
                                    },
                              child: const Text('동의 철회 및 삭제'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
