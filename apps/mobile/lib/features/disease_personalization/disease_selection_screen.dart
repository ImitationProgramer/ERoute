import 'condition_catalog_editor.dart';
import 'condition_local_store.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../member_health/health_draft.dart';
import '../member_ui/member_contract.dart';
import '../member_ui/member_controller.dart';
import '../member_ui/member_widgets.dart';
import 'disease_reference.dart';
import 'disease_repository.dart';

const mapUseExplanation =
    '선택한 질환과 관련된 진료과 정보가 있는 병원을 표시하는 데 사용합니다. 현재 진료 가능, 치료 가능, 응급환자 수용 가능을 의미하지 않으며 방문·이송 추천도 아닙니다. 선택 사항이며 일반 병원 검색은 그대로 사용할 수 있습니다.';
const mapReleaseHold = '승인된 관련 진료과 정보만 지도에 사용합니다. 일반 공개는 준비 중입니다.';

class DiseaseSelectionScreen extends ConsumerWidget {
  final MemberHealthSnapshot base;
  final bool recordMode;
  const DiseaseSelectionScreen({
    super.key,
    required this.base,
    this.recordMode = false,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) => recordMode
      ? ConditionCatalogEditor(base: base)
      : _MapDiseaseSelectionScreen(base: base);
}

class _MapDiseaseSelectionScreen extends ConsumerStatefulWidget {
  final MemberHealthSnapshot base;
  final bool recordMode = false;
  const _MapDiseaseSelectionScreen({required this.base});
  @override
  ConsumerState<_MapDiseaseSelectionScreen> createState() =>
      _DiseaseSelectionScreenState();
}

class _DiseaseSelectionScreenState
    extends ConsumerState<_MapDiseaseSelectionScreen> {
  final query = TextEditingController();
  late final freeText = TextEditingController(
    text: widget.base.conditions.text,
  );
  EntryStatus? explicitState;
  bool adding = false;
  List<Disease> choices(DiseaseReference value) => value
      .search(query.text)
      .where(
        (d) =>
            widget.recordMode ||
            widget.base.standardDiseaseSelection.diseaseIds.contains(d.id),
      )
      .toList();
  final selected = <String>{};
  final watch = Stopwatch()..start();
  late final HealthDraft draft = HealthDraft(elapsed: () => watch.elapsed);
  late final String? owner;
  DiseaseReference? reference;
  Timer? timer;
  int ticks = 0, request = 0;
  bool agreed = false,
      busy = false,
      loading = true,
      dirty = false,
      conflict = false,
      leaving = false,
      polling = false;
  String? error;
  bool get authorized {
    final v = ref.read(memberControllerProvider);
    return v.access?.identity == owner &&
        v.access?.granted == true &&
        !v.covered;
  }

  @override
  void initState() {
    super.initState();
    owner = ref.read(memberControllerProvider).access?.identity;
    if (widget.recordMode &&
        widget.base.standardDiseaseSelection.diseaseIds.isEmpty) {
      explicitState = widget.base.conditions.status;
    }
    selected.addAll(
      widget.recordMode
          ? widget.base.standardDiseaseSelection.diseaseIds
          : widget.base.mapDiseaseSelection.diseaseIds,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) load();
    });
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (draft.expired) {
        invalidate('편집 초안 보존시간이 지나 제거했습니다.', purge: true);
      }
      if (++ticks % 10 == 0) poll();
    });
  }

  Future<void> load() async {
    final ticket = ++request;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await ref.read(diseaseDataRepositoryProvider).reference();
      if (!mounted || ticket != request) return;
      setState(() {
        reference = value;
        final saved = widget.base.mapDiseaseSelection;
        agreed =
            !dirty &&
            saved.state == 'CONFIRMED' &&
            saved.referenceVersion == value.version &&
            saved.purposeVersion == value.purposeVersion &&
            saved.purpose == value.purpose;
      });
    } catch (e) {
      if (mounted && ticket == request) {
        if (e is MemberFailure &&
            (e.kind == MemberFailureKind.session ||
                e.kind == MemberFailureKind.consent)) {
          invalidate(memberError(e), purge: true);
        } else {
          setState(() => error = '질환 기준정보를 불러오지 못했습니다. 다시 시도해주세요.');
        }
      }
    } finally {
      if (mounted && ticket == request) setState(() => loading = false);
    }
  }

  void invalidate(String message, {bool purge = false}) {
    request++;
    if (purge) {
      selected.clear();
      query.clear();
      freeText.clear();
      draft.clear();
      dirty = false;
    }
    setState(() {
      agreed = false;
      conflict = true;
      loading = false;
      error = message;
    });
  }

  Future<void> poll() async {
    if (!authorized || busy || polling || conflict) return;
    polling = true;
    final ticket = request;
    try {
      final current = await ref.read(mapSelectionRepositoryProvider).read();
      if (!mounted || ticket != request || !authorized) return;
      if (current.version != widget.base.version ||
          current.consentEpoch != widget.base.consentEpoch ||
          current.selection.state != widget.base.mapDiseaseSelection.state) {
        invalidate('저장된 정보가 변경되었습니다. 최신 내용을 확인해주세요.');
      }
    } catch (e) {
      if (mounted &&
          ticket == request &&
          e is MemberFailure &&
          (e.kind == MemberFailureKind.session ||
              e.kind == MemberFailureKind.consent)) {
        invalidate(memberError(e), purge: true);
        final controller = ref.read(memberControllerProvider.notifier);
        controller.cover(clear: true);
        unawaited(controller.reload());
      }
    } finally {
      polling = false;
    }
  }

  void edit() {
    if (!authorized) return;
    explicitState = null;
    final a = ref.read(memberControllerProvider).access!;
    draft.edit(
      user: a.userId,
      session: a.sessionGeneration,
      epoch: widget.base.consentEpoch,
      version: widget.base.version,
      data: {
        'ids': selected.toList(),
        'agreed': agreed,
        'freeText': freeText.text,
      },
    );
    setState(() {
      dirty = true;
      error = null;
    });
  }

  Future<void> leave() async {
    if (busy) return;
    if (dirty &&
        !await memberConfirm(
          context,
          '변경사항을 버릴까요?',
          '아직 저장하지 않은 선택이 사라집니다.',
          '변경사항 버리기',
          cancel: '계속 편집',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => leaving = true);
    Navigator.of(context).pop();
  }

  Future<void> latest() async {
    if (dirty &&
        !await memberConfirm(
          context,
          '최신 내용 확인',
          '현재 초안을 버리고 선택 화면을 다시 열어주세요.',
          '초안 버리기',
          cancel: '초안 유지',
        )) {
      return;
    }
    if (!mounted) return;
    selected.clear();
    query.clear();
    draft.clear();
    await ref.read(memberControllerProvider.notifier).reload();
    if (!mounted) return;
    setState(() {
      dirty = false;
      leaving = true;
    });
    Navigator.of(context).pop();
  }

  Future<void> save({bool clear = false}) async {
    if (ref.read(conditionLocalProvider)?.pending == true ||
        ref.read(conditionLocalProvider)?.conflict == true) {
      setState(() => error = '기저질환을 서버에 반영한 뒤 지도 활용을 선택해주세요.');
      return;
    }
    if (busy ||
        conflict ||
        !authorized ||
        (!clear &&
            (reference == null ||
                (!widget.recordMode && (selected.isEmpty || !agreed))))) {
      return;
    }
    if (clear &&
        !await memberConfirm(
          context,
          '지도 활용 해제',
          '지도 활용 질환 선택을 제거합니다. 기저질환 원문은 유지됩니다.',
          '지도 활용 해제',
        )) {
      return;
    }
    if (!mounted || !authorized) return;
    final ticket = ++request;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final repo = ref.read(mapSelectionRepositoryProvider);
      if (widget.recordMode) {
        final state =
            explicitState ??
            (selected.isNotEmpty || freeText.text.trim().isNotEmpty
                ? EntryStatus.recorded
                : EntryStatus.unset);
        await ref
            .read(conditionsRepositoryProvider)
            .save(
              widget.base.version,
              widget.base.consentEpoch,
              state.name.toUpperCase(),
              freeText.text,
              selected.toList(),
              reference!.catalogVersion,
            );
      } else if (clear) {
        await repo.clear(widget.base.version, widget.base.consentEpoch);
      } else {
        await repo.save(
          widget.base.version,
          widget.base.consentEpoch,
          selected.toList(),
          reference!,
        );
      }
      if (!mounted || ticket != request || !authorized) return;
      draft.clear();
      dirty = false;
      await ref.read(memberControllerProvider.notifier).reload();
      if (!mounted || ticket != request || !authorized) return;
      setState(() => leaving = true);
      memberFeedback(
        context,
        widget.recordMode
            ? '기저질환을 저장했습니다.'
            : clear
            ? '지도 활용을 해제했습니다.'
            : '지도 활용 선택을 저장했습니다.',
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted || ticket != request) return;
      final lost =
          e is MemberFailure &&
          (e.kind == MemberFailureKind.session ||
              e.kind == MemberFailureKind.consent);
      if (lost) {
        invalidate(memberError(e), purge: true);
        final controller = ref.read(memberControllerProvider.notifier);
        controller.cover(clear: true);
        unawaited(controller.reload());
      } else {
        setState(() {
          error = memberError(e);
          conflict = e is MemberFailure && e.kind == MemberFailureKind.conflict;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resetConditions(EntryStatus status) async {
    if (!await memberConfirm(
      context,
      status == EntryStatus.none ? '기저질환이 없나요?' : '기저질환 전체 초기화',
      '등록 태그, 자유입력, 지도 활용 선택을 모두 제거합니다. 저장해야 반영됩니다.',
      '전체 기록 지우기',
    )) {
      return;
    }
    if (!mounted || !authorized) return;
    selected.clear();
    freeText.clear();
    edit();
    setState(() => explicitState = status);
  }

  @override
  void dispose() {
    request++;
    timer?.cancel();
    draft.clear();
    selected.clear();
    query.clear();
    query.dispose();
    freeText.clear();
    freeText.dispose();
    watch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep the public transport alive while this screen has pending reads.
    ref.watch(diseaseDataRepositoryProvider);
    ref.listen(memberControllerProvider, (old, next) {
      if (next.access?.identity != owner || next.access?.granted != true) {
        invalidate('로그인 또는 동의 상태가 바뀌어 선택 초안을 제거했습니다.', purge: true);
      } else if (!next.covered &&
          next.health != null &&
          next.health!.version != widget.base.version &&
          !busy) {
        invalidate('정보가 변경되었습니다. 최신 내용을 확인해주세요.');
      }
    });
    final value = reference;
    final canSelect =
        widget.recordMode ||
        widget.base.standardDiseaseSelection.diseaseIds.isNotEmpty;
    return PopScope(
      canPop: leaving || (!dirty && !busy),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) leave();
      },
      child: MemberScaffold(
        title: widget.recordMode ? '기저질환' : '병원 탐색에 활용',
        child: MemberGuard(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!widget.recordMode)
                Text(
                  '직접 입력한 질환',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              const SizedBox(height: 8),
              if (!widget.recordMode) Text(widget.base.conditions.summary),
              const SizedBox(height: 16),
              if (!widget.recordMode) const MemberNotice(mapReleaseHold),
              const SizedBox(height: 12),
              if (!widget.recordMode) const MemberCopy(mapUseExplanation),
              const SizedBox(height: 16),
              if (widget.base.mapDiseaseSelection.state ==
                      'RECONFIRM_REQUIRED' ||
                  value != null &&
                      widget.base.mapDiseaseSelection.referenceVersion !=
                          null &&
                      widget.base.mapDiseaseSelection.referenceVersion !=
                          value.version)
                const MemberNotice(
                  '기저질환 또는 기준정보가 변경되었습니다. 기존 선택을 계속 사용할지 다시 확인해주세요. 재확인 전에는 활용하지 않습니다.',
                ),
              if (!canSelect)
                const MemberNotice('표준 질환 태그를 먼저 등록한 뒤 지도 활용을 선택해주세요.'),
              if (error != null) MemberNotice(error!, error: true),
              if (conflict)
                OutlinedButton(onPressed: latest, child: const Text('최신 내용 확인'))
              else if (loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (value == null)
                OutlinedButton(onPressed: load, child: const Text('다시 시도'))
              else if (canSelect) ...[
                if (widget.recordMode) ...[
                  Text(
                    '등록된 질환',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (selected.isEmpty) const Text('등록한 표준 질환이 없습니다.'),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final id in selected)
                        InputChip(
                          deleteButtonTooltipMessage: '등록 질환에서 제거',
                          label: Text(
                            value.diseases
                                    .where((d) => d.id == id)
                                    .firstOrNull
                                    ?.name ??
                                '이전 등록 질환',
                          ),
                          onDeleted: busy
                              ? null
                              : () {
                                  selected.remove(id);
                                  edit();
                                },
                        ),
                    ],
                  ),
                  if (selected.any((id) => !value.supports(id)))
                    const Text('관련 진료과 정보 준비 중'),
                  if (widget.base.mapDiseaseSelection.diseaseIds.any(
                    (id) => !widget.base.standardDiseaseSelection.diseaseIds
                        .contains(id),
                  ))
                    TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              if (!await memberConfirm(
                                context,
                                '기존 선택을 태그로 등록할까요?',
                                '이전에 직접 선택한 질환만 등록합니다. 지도 활용은 다시 확인해야 합니다.',
                                '태그로 등록',
                              )) {
                                return;
                              }
                              if (!mounted || !authorized) return;
                              selected.addAll(
                                widget.base.mapDiseaseSelection.diseaseIds
                                    .where(
                                      (id) => value.diseases.any(
                                        (d) => d.id == id && d.active,
                                      ),
                                    ),
                              );
                              edit();
                            },
                      child: const Text('기존 지도 선택을 기록용 태그로 등록'),
                    ),
                  TextButton.icon(
                    onPressed: busy
                        ? null
                        : () => setState(() => adding = !adding),
                    icon: const Icon(Icons.add),
                    label: const Text('질환 추가'),
                  ),
                ],
                if (!widget.recordMode || adding) ...[
                  TextField(
                    controller: query,
                    enabled: !busy,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: '질환 검색',
                      hintText: '질환명 또는 다른 이름',
                      suffixIcon: query.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '검색어 지우기',
                              onPressed: () {
                                query.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.clear),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('직접 선택한 질환만 저장합니다. 기록한 문장에서 질환을 자동 판단하지 않습니다.'),
                  if (choices(value).isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('지원되는 질환을 찾지 못했습니다. 기저질환 원문은 그대로 유지됩니다.'),
                    ),
                  for (final d in choices(value))
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(d.name),
                      subtitle: Text(
                        [
                          if (d.aliases.isNotEmpty) d.aliases.join(' · '),
                          if (!value.supports(d.id)) '관련 진료과 정보 준비 중',
                        ].join('\n'),
                      ),
                      value: selected.contains(d.id),
                      onChanged: busy
                          ? null
                          : (v) {
                              v == true
                                  ? selected.add(d.id)
                                  : selected.remove(d.id);
                              agreed = false;
                              edit();
                            },
                    ),
                ],
                if (!widget.recordMode &&
                    selected.any(
                      (id) =>
                          !value.diseases.any((d) => d.id == id && d.active),
                    )) ...[
                  const MemberNotice('현재 지원되지 않는 기존 선택이 있습니다. 제거 후 다시 확인해주세요.'),
                  TextButton(
                    onPressed: () {
                      selected.removeWhere(
                        (id) =>
                            !value.diseases.any((d) => d.id == id && d.active),
                      );
                      agreed = false;
                      edit();
                    },
                    child: const Text('지원되지 않는 선택 제거'),
                  ),
                ],
                if (!widget.recordMode)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: agreed,
                    onChanged: busy
                        ? null
                        : (v) {
                            agreed = v == true;
                            edit();
                          },
                    title: const Text('선택한 질환의 지도 활용 목적과 한계를 확인했습니다.'),
                  ),
                if (widget.recordMode) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: freeText,
                    enabled: !busy,
                    maxLength: 2000,
                    minLines: 3,
                    maxLines: 6,
                    onChanged: (_) => edit(),
                    decoration: const InputDecoration(
                      labelText: '직접 입력한 질환',
                      helperText: '태그와 별도로 보관하며 자동 병원 매칭에 사용하지 않습니다.',
                      helperMaxLines: 3,
                    ),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () {
                            freeText.clear();
                            edit();
                          },
                    child: const Text('자유입력만 지우기 · 태그 유지'),
                  ),
                  Wrap(
                    children: [
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => resetConditions(EntryStatus.none),
                        child: const Text('기저질환 없음'),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => resetConditions(EntryStatus.unset),
                        child: const Text('기저질환 전체 초기화'),
                      ),
                    ],
                  ),
                  if (explicitState == EntryStatus.none)
                    const Text('기저질환 없음 · 저장하면 전체 기저질환 기록이 제거됩니다.'),
                ],
                MemberBusyButton(
                  busy: busy,
                  onPressed:
                      !widget.recordMode &&
                          (selected.isEmpty ||
                              !agreed ||
                              selected.any(
                                (id) => !value.diseases.any(
                                  (d) => d.id == id && d.active,
                                ),
                              ))
                      ? null
                      : () => save(),
                  label: widget.recordMode ? '기저질환 저장' : '선택한 질환 확인하고 저장',
                ),
              ],
              if (!widget.recordMode &&
                  widget.base.mapDiseaseSelection.state != 'NOT_SELECTED')
                TextButton(
                  onPressed: busy || conflict ? null : () => save(clear: true),
                  child: const Text('지도 활용 해제'),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
