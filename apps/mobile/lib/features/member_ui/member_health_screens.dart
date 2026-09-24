import '../emergency_guides/data/guide_source_launcher.dart';
import '../disease_personalization/condition_local_store.dart';
import '../disease_personalization/disease_selection_screen.dart';
import 'member_product.dart';
import 'member_product_screens.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../member_health/health_draft.dart';
import 'member_contract.dart';
import 'member_controller.dart';
import 'member_widgets.dart';
import 'member_profile_screen.dart';

void openMemberPage(BuildContext context, Widget page) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        settings: RouteSettings(
          name: page is MemberMedicationScreen ? 'member-medications' : null,
        ),
        builder: (_) => page,
      ),
    );

// Host adapter preserves the existing isolated preview without a network catalog.
final conditionEditorBuilderProvider =
    Provider<Widget Function(MemberHealthSnapshot)>(
      (ref) =>
          (base) => DiseaseSelectionScreen(base: base, recordMode: true),
    );

class MemberEmergencyScreen extends ConsumerStatefulWidget {
  final bool hospitalUseSettings;
  const MemberEmergencyScreen({super.key, this.hospitalUseSettings = false});
  @override
  ConsumerState<MemberEmergencyScreen> createState() =>
      _MemberEmergencyScreenState();
}

class _MemberEmergencyScreenState extends ConsumerState<MemberEmergencyScreen> {
  bool _openedHospitalSettings = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(memberControllerProvider.notifier).reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(memberControllerProvider);
    final data = state.health;
    final localConditions = ref.watch(conditionLocalProvider);
    if (widget.hospitalUseSettings &&
        !_openedHospitalSettings &&
        !state.covered &&
        !state.loading &&
        data != null &&
        state.access?.granted == true) {
      _openedHospitalSettings = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => DiseaseSelectionScreen(base: data)),
        );
        if (context.mounted) Navigator.of(context).pop();
      });
    }
    return MemberScaffold(
      title: '내 응급정보',
      actions: [
        IconButton(
          tooltip: '내 정보',
          onPressed: () => openMemberPage(context, const MemberAccountScreen()),
          icon: const Icon(Icons.person_outline),
        ),
      ],
      child: MemberGuard(
        healthRequired: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const MemberCopy('저장한 건강정보를 확인하고 수정하세요.'),
            const SizedBox(height: 8),
            if (state.access?.granted != true) ...[
              const MemberNotice('건강정보는 별도 동의 후 등록할 수 있어요.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () =>
                    openMemberPage(context, const MemberConsentScreen()),
                child: const Text('동의 내용 확인하고 시작하기'),
              ),
            ] else if (data != null) ...[
              Text(
                '마지막 저장 · ${memberTime(data.updatedAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              HealthSummaryCard(
                title: '알레르기',
                icon: Icons.local_hospital_outlined,
                tone: MemberTone.allergy,
                summary: data.allergies.status == EntryStatus.none
                    ? '알레르기 없음'
                    : data.allergies.summary,
                badge: entryLabel(data.allergies.status),
                onTap: () => openMemberPage(
                  context,
                  MemberFieldEditor(field: HealthField.allergies, base: data),
                ),
              ),
              HealthSummaryCard(
                title: '기저질환',
                icon: Icons.favorite_border,
                tone: MemberTone.condition,
                summary: localConditions != null
                    ? (localConditions.entries.isEmpty
                          ? (localConditions.status == 'NONE'
                                ? '없음 · 직접 확인'
                                : '아직 입력하지 않았어요')
                          : localConditions.entries
                                .map((e) => e.name)
                                .join(', '))
                    : [
                        if (data.standardDiseaseSelection.diseaseIds.isNotEmpty)
                          '표준 질환 ${data.standardDiseaseSelection.diseaseIds.length}개 등록',
                        if (data.conditions.text.isNotEmpty ||
                            data.standardDiseaseSelection.diseaseIds.isEmpty)
                          data.conditions.summary,
                      ].join('\n'),
                badge: localConditions != null
                    ? entryLabel(
                        EntryStatus.values.byName(
                          localConditions.status.toLowerCase(),
                        ),
                      )
                    : entryLabel(
                        data.standardDiseaseSelection.diseaseIds.isNotEmpty
                            ? EntryStatus.recorded
                            : data.conditions.status,
                      ),
                notice: localConditions?.pending == true
                    ? (localConditions!.conflict
                          ? '최신 내용 확인 필요'
                          : '기기 저장 · 서버 반영 대기')
                    : null,
                onTap: () => openMemberPage(
                  context,
                  ref.read(conditionEditorBuilderProvider)(data),
                ),
              ),
              HealthSummaryCard(
                title: '복용약',
                icon: Icons.medication_outlined,
                tone: MemberTone.medication,
                summary: data.medications.isEmpty
                    ? data.medicationsStatus == EntryStatus.none
                          ? '현재 복용 중인 약이 없어요.'
                          : '아직 입력하지 않았어요'
                    : data.medications.map((m) => m.name).join(', '),
                badge: entryLabel(data.medicationsStatus),
                onTap: () =>
                    openMemberPage(context, const MemberMedicationScreen()),
              ),
              HealthSummaryCard(
                title: '응급 메모',
                icon: Icons.notes_rounded,
                tone: MemberTone.note,
                summary: data.note.isEmpty ? '아직 입력하지 않았어요' : data.note,
                badge: data.note.isEmpty ? '미입력' : '등록됨',
                onTap: () => openMemberPage(
                  context,
                  MemberFieldEditor(field: HealthField.note, base: data),
                ),
              ),
              const SizedBox(height: 8),
              const MemberProvenance(),
            ],
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () async {
                final opened = await ref
                    .read(guideSourceLauncherProvider)
                    .open(
                      Uri.parse(
                        'https://www.nfa.go.kr/nfa/safetyinfo/emergencyservice/',
                      ),
                    );
                if (!opened && context.mounted) {
                  memberFeedback(context, '공식 페이지를 열지 못했습니다. 다시 시도해주세요.');
                }
              },
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('119 안심콜 서비스 알아보기'),
            ),
            const MemberCopy(
              '병력 등 정보를 소방청에 미리 등록하면 119 신고 시 출동대가 확인할 수 있는 공식 서비스입니다. ERoute 정보는 자동 등록되지 않습니다.',
            ),
          ],
        ),
      ),
    );
  }
}

String entryLabel(EntryStatus status) => switch (status) {
  EntryStatus.unset => '미입력',
  EntryStatus.none => '없음',
  EntryStatus.recorded => '등록됨',
};

class HealthSummaryCard extends StatelessWidget {
  final String title, summary, badge;
  final String? notice;
  final IconData icon;
  final MemberTone tone;
  final VoidCallback onTap;
  const HealthSummaryCard({
    super.key,
    required this.title,
    this.notice,
    required this.summary,
    required this.badge,
    required this.icon,
    required this.tone,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: .10),
      surfaceTintColor: Colors.transparent,
      shape: memberCardShape(context),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MemberCategoryIcon(tone: tone, icon: icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: memberToneColors(context, tone).$1,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            badge,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                      ],
                    ),
                    if (notice != null)
                      Text(
                        notice!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    const SizedBox(height: 8),
                    Text(
                      summary,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 22),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Same editor implements text sections and the two-field manual medication form.
class MemberFieldEditor extends ConsumerStatefulWidget {
  final HealthField? field;
  final MemberHealthSnapshot base;
  final MedicationEntry? medication;
  final MedicationProduct? selectedProduct;
  final String? initialText;
  const MemberFieldEditor({
    super.key,
    this.field,
    required this.base,
    this.medication,
    this.selectedProduct,
    this.initialText,
  });
  @override
  ConsumerState<MemberFieldEditor> createState() => _MemberFieldEditorState();
}

class _MemberFieldEditorState extends ConsumerState<MemberFieldEditor> {
  final value = TextEditingController(), note = TextEditingController();
  final form = GlobalKey<FormState>();
  final watch = Stopwatch()..start();
  late final HealthDraft draft = HealthDraft(elapsed: () => watch.elapsed);
  late final String? owner;
  late EntryStatus status;
  bool dirty = false, busy = false, conflict = false, leaving = false;
  String? error;
  Timer? timer;
  bool get medication => widget.field == null;
  MedicationProduct? get product =>
      widget.selectedProduct ?? widget.medication?.product;
  String get title => medication
      ? widget.medication == null
            ? '복용약 추가'
            : '복용약 편집'
      : switch (widget.field!) {
          HealthField.allergies => '알레르기',
          HealthField.conditions => '기저질환',
          HealthField.note => '응급 메모',
          HealthField.medicationsStatus => '복용약 상태',
        };
  @override
  void initState() {
    super.initState();
    owner = ref.read(memberControllerProvider).access?.identity;
    final entry = widget.field == HealthField.allergies
        ? widget.base.allergies
        : widget.base.conditions;
    status = entry.status;
    value.text = medication
        ? product?.name ?? widget.medication?.name ?? ''
        : widget.field == HealthField.note
        ? widget.base.note
        : entry.text;
    note.text = widget.medication?.note ?? '';
    if (widget.initialText != null) {
      value.text = widget.initialText!;
      status = EntryStatus.recorded;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) edited();
      });
    }
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (draft.expired) clearDraft('편집 초안 보존시간이 지나 제거했습니다. 최신 내용을 다시 확인해주세요.');
    });
  }

  void clearDraft(String message) {
    draft.clear();
    value.clear();
    note.clear();
    if (mounted) {
      setState(() {
        dirty = false;
        conflict = true;
        error = message;
      });
    }
  }

  void edited() {
    final a = ref.read(memberControllerProvider).access;
    if (a == null) return;
    draft.edit(
      user: a.userId,
      session: a.sessionGeneration,
      epoch: widget.base.consentEpoch,
      version: widget.base.version,
      data: {'value': value.text, 'note': note.text, 'status': status.name},
    );
    setState(() {
      dirty = true;
      error = null;
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    draft.clear();
    watch.stop();
    value.clear();
    note.clear();
    value.dispose();
    note.dispose();
    super.dispose();
  }

  void closeEditor({bool toOwner = false}) {
    if (medication && toOwner) {
      Navigator.of(context).popUntil(
        (route) => route.isFirst || route.settings.name == 'member-medications',
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'member-medications'),
          builder: (_) => const MemberMedicationScreen(),
        ),
      );
      return;
    }
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => medication
              ? const MemberMedicationScreen()
              : const MemberEmergencyScreen(),
        ),
      );
    }
  }

  Future<void> leave() async {
    if (busy || leaving) return;
    if (dirty &&
        !await memberConfirm(
          context,
          '변경사항을 버릴까요?',
          '아직 저장하지 않은 내용이 사라집니다.',
          '변경사항 버리기',
          cancel: '계속 편집',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => leaving = true);
    closeEditor();
  }

  Future<void> latest() async {
    if (dirty &&
        !await memberConfirm(
          context,
          '최신 내용으로 다시 편집',
          '현재 초안을 버리고 접근 권한과 최신 내용을 확인합니다.',
          '최신 내용 확인',
          cancel: '초안 유지',
        )) {
      return;
    }
    if (!mounted) return;
    clearDraft('최신 내용을 확인하고 있습니다.');
    await ref.read(memberControllerProvider.notifier).reload();
    if (!mounted) return;
    if (!ref.read(memberControllerProvider).covered) {
      setState(() => leaving = true);
      closeEditor(toOwner: true);
      memberFeedback(context, '현재 상태를 확인했습니다. 항목을 다시 열어 편집해주세요.');
    }
  }

  bool get currentOwner {
    final access = ref.read(memberControllerProvider).access;
    return access?.identity == owner && access?.granted == true && !conflict;
  }

  Future<void> save() async {
    if (busy || conflict || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final repo = ref.read(memberUiRepositoryProvider);
      if (medication) {
        await repo.saveMedication(
          original: widget.medication,
          product: product,
          name: value.text,
          note: note.text,
          baseVersion: widget.base.version,
          consentEpoch: widget.base.consentEpoch,
        );
      } else {
        await repo.saveField(
          HealthFieldEdit(
            field: widget.field!,
            baseVersion: widget.base.version,
            consentEpoch: widget.base.consentEpoch,
            entry: HealthEntry(
              status,
              status == EntryStatus.recorded ? value.text : '',
            ),
            note: value.text,
          ),
        );
      }
      if (!mounted) return;
      if (!currentOwner) return;
      draft.clear();
      dirty = false;
      await ref.read(memberControllerProvider.notifier).reload();
      if (!mounted ||
          !currentOwner ||
          ref.read(memberControllerProvider).covered) {
        return;
      }
      setState(() => leaving = true);
      memberFeedback(context, ref.read(memberResultLabelProvider));
      closeEditor(toOwner: true);
    } catch (e) {
      if (!mounted) return;
      final authorityLost =
          e is MemberFailure &&
          (e.kind == MemberFailureKind.consent ||
              e.kind == MemberFailureKind.session);
      if (authorityLost) {
        clearDraft(memberError(e));
        ref.read(memberControllerProvider.notifier).cover(clear: true);
        await ref.read(memberControllerProvider.notifier).reload();
      }
      if (mounted) {
        setState(() {
          error = memberError(e);
          conflict =
              authorityLost ||
              e is MemberFailure && e.kind == MemberFailureKind.conflict;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(memberControllerProvider, (previous, next) {
      if (next.access == null ||
          next.access!.identity != owner ||
          !next.access!.granted) {
        if (dirty || value.text.isNotEmpty || note.text.isNotEmpty) {
          clearDraft('로그인 또는 동의 상태가 바뀌어 초안을 제거했습니다.');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.of(context).canPop()) {
              setState(() => leaving = true);
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
          });
        }
      } else if (!next.covered &&
          next.health?.version != widget.base.version &&
          !busy) {
        setState(() {
          conflict = true;
          error = '저장된 정보가 변경되었습니다. 최신 내용을 확인한 뒤 다시 편집해주세요.';
        });
      }
    });
    return PopScope(
      canPop: leaving || !dirty && !busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) leave();
      },
      child: MemberScaffold(
        title: title,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: MemberBusyButton(
              busy: busy,
              onPressed:
                  conflict ||
                      ref.watch(memberControllerProvider).covered ||
                      ref.watch(memberControllerProvider).access?.granted !=
                          true
                  ? null
                  : save,
              label: medication && widget.medication == null ? '등록' : '저장',
            ),
          ),
        ],
        child: MemberGuard(
          child: Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!medication) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: memberToneColors(
                        context,
                        widget.field == HealthField.allergies
                            ? MemberTone.allergy
                            : widget.field == HealthField.conditions
                            ? MemberTone.condition
                            : MemberTone.note,
                      ).$1,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        MemberCategoryIcon(
                          tone: widget.field == HealthField.allergies
                              ? MemberTone.allergy
                              : widget.field == HealthField.conditions
                              ? MemberTone.condition
                              : MemberTone.note,
                          icon: widget.field == HealthField.allergies
                              ? Icons.local_hospital_outlined
                              : widget.field == HealthField.conditions
                              ? Icons.favorite_border
                              : Icons.notes_rounded,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: MemberCopy(
                            widget.field == HealthField.note
                                ? '구급대원이나 의료진에게 알려야 할 참고사항을 입력하세요.'
                                : '알고 있는 $title 정보를 기록해주세요.',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ] else if (product == null) ...[
                  const MemberCopy('검색으로 찾기 어려운 약은 직접 기록할 수 있어요.'),
                  const SizedBox(height: 24),
                ],
                if (!medication && widget.field != HealthField.note) ...[
                  Text(
                    '$title${widget.field == HealthField.allergies ? '가' : '이'} 있나요?',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final choice in [
                        EntryStatus.recorded,
                        EntryStatus.none,
                        EntryStatus.unset,
                      ])
                        ChoiceChip(
                          label: Text(switch (choice) {
                            EntryStatus.recorded => '있어요',
                            EntryStatus.none => '없어요',
                            EntryStatus.unset => '아직 입력 안 함',
                          }),
                          selected: status == choice,
                          onSelected: busy || conflict
                              ? null
                              : (_) {
                                  setState(() => status = choice);
                                  edited();
                                },
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  MemberCopy(switch (status) {
                    EntryStatus.unset => '아직 확인하지 않은 상태로 남깁니다.',
                    EntryStatus.none => '직접 확인한 결과, 없는 것으로 기록합니다.',
                    EntryStatus.recorded => '기억하는 내용을 아래에 자유롭게 적어주세요.',
                  }, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 24),
                ],
                if (product != null) ...[
                  Text('선택한 제품', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  MemberProductSummary(product: product!),
                  const SizedBox(height: 24),
                  Text(
                    '내 복용 기록',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const MemberCopy('메모는 내가 남기는 기록이며 제품 설명과 별도로 저장됩니다.'),
                ],
                if (medication && product == null ||
                    !medication &&
                        (widget.field == HealthField.note ||
                            status == EntryStatus.recorded))
                  TextFormField(
                    controller: value,
                    enabled: !busy && !conflict,
                    decoration: InputDecoration(
                      labelText: medication
                          ? '약 이름'
                          : widget.field == HealthField.note
                          ? '응급 메모 (선택)'
                          : '$title 내용',
                      hintText: widget.field == HealthField.note
                          ? '예: 의사소통에 필요한 참고사항'
                          : null,
                      alignLabelWithHint: true,
                      border: const OutlineInputBorder(),
                    ),
                    minLines: medication ? 1 : 5,
                    maxLines: medication ? 2 : 10,
                    maxLength: medication ? 200 : 2000,
                    onChanged: (_) => edited(),
                    validator: (text) =>
                        (medication || widget.field != HealthField.note) &&
                            (text ?? '').trim().isEmpty
                        ? '내용을 입력해주세요.'
                        : null,
                  ),
                if (medication) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: note,
                    enabled: !busy && !conflict,
                    minLines: 3,
                    maxLines: 8,
                    maxLength: 2000,
                    onChanged: (_) => edited(),
                    decoration: const InputDecoration(
                      labelText: '복용 메모 (선택)',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (!dirty && !medication)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      widget.field == HealthField.note &&
                              widget.base.note.isEmpty
                          ? '아직 저장한 응급 메모가 없어요. 빈 메모를 저장하면 내용이 지워지고 미입력으로 표시됩니다.'
                          : status == EntryStatus.unset &&
                                widget.field != HealthField.note
                          ? '아직 입력하지 않았어요.'
                          : '저장된 정보${widget.base.updatedAt == null ? '' : ' · ${memberTime(widget.base.updatedAt)}'}',
                    ),
                  ),
                if (dirty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('아직 저장하지 않은 변경사항이 있어요.'),
                  ),
                if (error != null) ...[
                  MemberNotice(error!, error: true),
                  const SizedBox(height: 16),
                ],
                if (conflict)
                  OutlinedButton(
                    onPressed: busy ? null : latest,
                    child: const Text('최신 내용 확인'),
                  ),
                const SizedBox(height: 16),
                const MemberProvenance(),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: busy ? null : leave,
                  child: const Text('취소'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MemberMedicationScreen extends ConsumerStatefulWidget {
  const MemberMedicationScreen({super.key});
  @override
  ConsumerState<MemberMedicationScreen> createState() =>
      _MemberMedicationScreenState();
}

class _MemberMedicationScreenState
    extends ConsumerState<MemberMedicationScreen> {
  bool busy = false;
  String? error;
  Future<void> change(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    final identity = ref.read(memberControllerProvider).access?.identity;
    try {
      await action();
      if (!mounted) return;
      await ref.read(memberControllerProvider.notifier).reload();
      if (!mounted ||
          ref.read(memberControllerProvider).covered ||
          ref.read(memberControllerProvider).access?.identity != identity) {
        return;
      }
      memberFeedback(context, ref.read(memberResultLabelProvider));
    } catch (e) {
      if (mounted) setState(() => error = memberError(e));
      if (e is MemberFailure &&
          (e.kind == MemberFailureKind.consent ||
              e.kind == MemberFailureKind.session)) {
        ref.read(memberControllerProvider.notifier).cover(clear: true);
        await ref.read(memberControllerProvider.notifier).reload();
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(memberControllerProvider).health;
    return MemberScaffold(
      title: '복용약',
      child: MemberGuard(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const MemberCopy('복용 중인 약과 내가 남긴 메모를 확인하세요.'),
            const SizedBox(height: 20),
            if (error != null) ...[
              MemberNotice(error!, error: true),
              TextButton(
                onPressed: () async {
                  await ref.read(memberControllerProvider.notifier).reload();
                  if (mounted) setState(() => error = null);
                },
                child: const Text('최신 목록 확인'),
              ),
            ],
            if (data != null) ...[
              Text(
                data.medications.isNotEmpty
                    ? '등록한 복용약'
                    : data.medicationsStatus == EntryStatus.none
                    ? '현재 복용 중인 약이 없어요.'
                    : '아직 복용약 정보를 입력하지 않았어요.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              for (final med in data.medications)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: MemberPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          med.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (med.product != null) ...[
                          const SizedBox(height: 4),
                          Text(med.product!.variant),
                          Text(
                            med.product!.sourceLabel,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        if (med.note.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(med.note),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          '${med.product == null ? '직접 입력' : '제품 선택 · 내 복용 기록'} · ${memberTime(med.updatedAt)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: busy
                                  ? null
                                  : () => openMemberPage(
                                      context,
                                      MemberFieldEditor(
                                        base: data,
                                        medication: med,
                                      ),
                                    ),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('편집'),
                            ),
                            TextButton.icon(
                              onPressed: busy
                                  ? null
                                  : () async {
                                      if (await memberConfirm(
                                        context,
                                        '복용약 삭제',
                                        '선택한 약 이름과 복용 메모를 삭제합니다. 다른 기록은 유지됩니다.',
                                        '삭제',
                                      )) {
                                        await change(
                                          () => ref
                                              .read(memberUiRepositoryProvider)
                                              .deleteMedication(
                                                med,
                                                data.version,
                                                data.consentEpoch,
                                              ),
                                        );
                                      }
                                    },
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('삭제'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              MemberBusyButton(
                busy: busy,
                onPressed: () => openMemberPage(
                  context,
                  MemberMedicationSearchScreen(base: data),
                ),
                label: data.medications.isEmpty ? '복용약 추가' : '+ 복용약 추가',
              ),
              if (data.medications.isEmpty &&
                  data.medicationsStatus == EntryStatus.unset)
                TextButton(
                  onPressed: busy
                      ? null
                      : () => change(() async {
                          await ref
                              .read(memberUiRepositoryProvider)
                              .saveField(
                                HealthFieldEdit(
                                  field: HealthField.medicationsStatus,
                                  baseVersion: data.version,
                                  consentEpoch: data.consentEpoch,
                                  medicationsStatus: EntryStatus.none,
                                ),
                              );
                        }),
                  child: const Text('복용약이 없어요'),
                ),
              const SizedBox(height: 16),
              const MemberProvenance(),
            ],
          ],
        ),
      ),
    );
  }
}
