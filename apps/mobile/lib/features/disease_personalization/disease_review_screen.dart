import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/eroute_scaffold.dart';
import '../member_ui/member_widgets.dart';
import 'disease_reference.dart';
import 'disease_repository.dart';
import 'department_matcher.dart';
import 'map_disease_selection.dart';
import 'disease_selection_screen.dart' show mapReleaseHold;

const diseaseReviewAvailable = kDebugMode && appFlavor == 'dev';

/// Explicit synthetic selection. No member provider, health fetch, or map SDK.
class DiseaseReviewScreen extends ConsumerStatefulWidget {
  const DiseaseReviewScreen({super.key});
  @override
  ConsumerState<DiseaseReviewScreen> createState() =>
      _DiseaseReviewScreenState();
}

class _DiseaseReviewScreenState extends ConsumerState<DiseaseReviewScreen>
    with WidgetsBindingObserver {
  final hpids = TextEditingController();
  final selected = <String>{};
  final session = MatchSession();
  DiseaseReference? reference;
  String? error;
  bool enabled = false, loading = false;
  int revision = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (diseaseReviewAvailable) load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final value = await ref.read(diseaseDataRepositoryProvider).reference();
      if (mounted) setState(() => reference = value);
    } catch (_) {
      if (mounted) setState(() => error = '기준정보를 불러오지 못했습니다.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void invalidate() {
    revision++;
    session.clear();
    setState(() => error = null);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      hpids.clear();
      selected.clear();
      enabled = false;
      invalidate();
    }
  }

  Future<void> compare() async {
    if (reference == null || selected.isEmpty || !enabled || loading) return;
    final ids = hpids.text
        .split(RegExp(r'[,\s]+'))
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty || ids.length > 100 || ids.any((id) => id.length > 100)) {
      setState(() => error = '병원 HPID를 1~100개 입력해주세요.');
      return;
    }
    final referenceValue = reference!;
    final ticket = ++revision;
    final owner = MatchRequestIdentity(
      'synthetic-review',
      ticket,
      0,
      0,
      referenceValue.version,
      ticket,
    );
    final selection = MapDiseaseSelection(
      state: 'CONFIRMED',
      diseaseIds: selected,
      purpose: referenceValue.purpose,
      purposeVersion: referenceValue.purposeVersion,
      referenceVersion: referenceValue.version,
      confirmedAt: DateTime.now(),
    );
    setState(() => loading = true);
    try {
      await session.evaluate(owner, () async {
        final hospitals = await ref
            .read(diseaseDataRepositoryProvider)
            .departments(ids);
        return hospitals
            .map(
              (h) => matchDepartments(
                reference: referenceValue,
                selection: selection,
                hospital: h,
                now: DateTime.now(),
                enabled: true,
                allowDraft: true,
              ),
            )
            .whereType<HospitalDiseaseMatchResult>()
            .toList();
      });
    } catch (_) {
      if (mounted && ticket == revision) {
        setState(() => error = '저장된 진료과 자료를 불러오지 못했습니다.');
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    session.clear();
    selected.clear();
    hpids.clear();
    hpids.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep the public transport alive while this screen has pending reads.
    ref.watch(diseaseDataRepositoryProvider);
    if (!diseaseReviewAvailable) return const SizedBox.shrink();
    final data = reference;
    return ERouteScaffold(
      title: '개발 검증 · 질환 매칭',
      showBack: true,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const MemberNotice(
            '가상 선택으로 비교하는 개발 검증 화면입니다. DRAFT 관계에는 외부 원자료 조사·검토 evidence가 채워지지 않았습니다.',
          ),
          const SizedBox(height: 12),
          const MemberNotice(mapReleaseHold),
          if (error != null) MemberNotice(error!, error: true),
          if (data == null && !loading)
            OutlinedButton(onPressed: load, child: const Text('다시 시도')),
          if (data != null) ...[
            Text('기준정보 ${data.version} · ${data.status}'),
            for (final d in data.diseases.where((d) => d.active))
              CheckboxListTile(
                title: Text(d.name),
                value: selected.contains(d.id),
                onChanged: (v) {
                  v == true ? selected.add(d.id) : selected.remove(d.id);
                  invalidate();
                },
              ),
            TextField(
              controller: hpids,
              onChanged: (_) => invalidate(),
              decoration: const InputDecoration(
                labelText: '조회할 공개 병원 HPID',
                helperText: '쉼표 또는 공백으로 구분 · 최대 100개',
              ),
            ),
            SwitchListTile(
              title: const Text('가상 선택 비교 켜기'),
              value: enabled,
              onChanged: (v) {
                enabled = v;
                invalidate();
              },
            ),
            MemberBusyButton(
              busy: loading,
              onPressed: enabled && selected.isNotEmpty ? compare : null,
              label: '저장된 진료과와 비교',
            ),
            for (final result in session.results)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${result.hospital.hpid} · ${switch (result.status) {
                          DepartmentMatchStatus.match => 'MATCH',
                          DepartmentMatchStatus.unknown => 'UNKNOWN',
                          DepartmentMatchStatus.noMatch => 'NO_MATCH',
                        }}',
                      ),
                      for (final disease in result.perDiseaseResults) ...[
                        Text(
                          '${data.diseases.firstWhere((d) => d.id == disease.diseaseId).name} · ${disease.status.name}',
                        ),
                        for (final reason in disease.matches)
                          Text(
                            '${reason.diseaseName} → ${reason.canonicalDepartmentName} / DIRECT → 병원 표기 ${reason.hospitalDepartmentRaw} (${reason.hospitalSource})',
                          ),
                        if (disease.unknownReasons.isNotEmpty)
                          Text('확인 필요: ${disease.unknownReasons.join(', ')}'),
                      ],
                      const Text(
                        '현재 진료 여부나 응급환자 수용 가능 여부를 의미하지 않습니다. NO_MATCH도 진료 불가를 뜻하지 않습니다.',
                      ),
                    ],
                  ),
                ),
              ),
          ],
          if (loading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
