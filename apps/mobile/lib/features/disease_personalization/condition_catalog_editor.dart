import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../member_health/health_draft.dart';
import '../member_ui/member_contract.dart';
import '../member_ui/member_controller.dart';
import '../member_ui/member_widgets.dart';
import 'condition_local_store.dart';
import 'disease_catalog.dart';
import 'disease_selection_screen.dart';
import 'condition_catalog_widgets.dart';
import '../../core/theme/eroute_tokens.dart';
import 'emergency_condition.dart';

/// Record editing shares the member guard, draft lifetime and existing field controls.
class ConditionCatalogEditor extends ConsumerStatefulWidget {
  final MemberHealthSnapshot base;
  const ConditionCatalogEditor({super.key, required this.base});
  @override
  ConsumerState<ConditionCatalogEditor> createState() =>
      _ConditionCatalogEditorState();
}

class _ConditionCatalogEditorState
    extends ConsumerState<ConditionCatalogEditor> {
  final query = TextEditingController(), custom = TextEditingController();
  final entries = <EmergencyCondition>[];
  final queryFocus = FocusNode();
  String committedQuery = '';
  String? selectedCategory;

  void searchChanged() {
    setState(() {
      if (!query.value.composing.isValid || query.value.composing.isCollapsed) {
        committedQuery = query.text;
      }
    });
  }

  final watch = Stopwatch()..start();
  late final draft = HealthDraft(elapsed: () => watch.elapsed);
  late final String? owner;
  DiseaseCatalog? catalog;
  Timer? timer;
  String status = 'UNSET';
  String? error;
  bool loading = true,
      busy = false,
      dirty = false,
      leaving = false,
      customOpen = false;
  int request = 0;
  int? editBaseVersion;
  bool versionConflict = false;
  bool get authorized {
    final v = ref.read(memberControllerProvider);
    return v.access?.identity == owner &&
        v.access?.granted == true &&
        !v.covered;
  }

  @override
  void initState() {
    super.initState();
    query.addListener(searchChanged);
    owner = ref.read(memberControllerProvider).access?.identity;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) load();
    });
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (draft.expired && mounted) {
        entries.clear();
        custom.clear();
        query.clear();
        draft.clear();
        setState(() {
          dirty = false;
          error = '편집 초안 보존시간이 지나 제거했습니다. 화면을 다시 열어주세요.';
        });
      }
    });
  }

  Future<void> load() async {
    final ticket = ++request;
    setState(() {
      loading = true;
      error = null;
    });
    DiseaseCatalog? value;
    try {
      value = await ref.read(diseaseCatalogRepositoryProvider).catalog();
    } catch (_) {
      if (mounted && ticket == request) {
        setState(() => error = '질환 목록을 불러오지 못했습니다. 다시 시도하거나 직접 입력해주세요.');
      }
    }
    if (!mounted ||
        ticket != request ||
        ref.read(memberControllerProvider).access?.identity != owner) {
      return;
    }
    final local = ref.read(conditionLocalProvider);
    if (local == null) {
      try {
        await ref
            .read(conditionLocalProvider.notifier)
            .attach(ref.read(memberControllerProvider).access!, widget.base);
      } catch (_) {
        if (mounted) setState(() => error = '기기 저장소를 열지 못했습니다. 다시 시도해주세요.');
      }
    }
    if (!mounted ||
        ticket != request ||
        ref.read(memberControllerProvider).access?.identity != owner) {
      return;
    }
    final saved = ref.read(conditionLocalProvider);
    setState(() {
      catalog = value;
      loading = false;
      if (!dirty) {
        editBaseVersion = saved?.baseVersion ?? widget.base.version;
        versionConflict = false;
        entries
          ..clear()
          ..addAll(
            saved?.entries ??
                widget.base.conditionEntries ??
                migrateConditions(
                  widget.base.standardDiseaseSelection.diseaseIds,
                  widget.base.conditions.text,
                  value,
                ),
          );
        status =
            saved?.status ??
            (entries.isNotEmpty
                ? 'RECORDED'
                : widget.base.conditions.status.name.toUpperCase());
      }
    });
  }

  void edit() {
    if (!authorized) return;
    status = entries.isEmpty ? 'UNSET' : 'RECORDED';
    final access = ref.read(memberControllerProvider).access!;
    draft.edit(
      user: access.userId,
      session: access.sessionGeneration,
      epoch: access.consentEpoch,
      version: widget.base.version,
      data: {
        'entries': entries.map((e) => e.toJson()).toList(),
        'custom': custom.text,
      },
    );
    setState(() {
      dirty = true;
      error = null;
    });
  }

  void toggle(String id, bool select) {
    if (!authorized) return;
    entries.removeWhere((e) => e.diseaseId == id);
    if (select) {
      entries.add(EmergencyCondition.standard(id, catalog!.byId(id)!.name));
    }
    edit();
  }

  Future<void> reset(String next) async {
    if (entries.isNotEmpty || custom.text.isNotEmpty) {
      if (!await memberConfirm(
        context,
        '질환 기록을 지울까요?',
        '저장하면 등록한 질환과 지도 활용 선택이 제거됩니다.',
        '기록 지우기',
      )) {
        return;
      }
    }
    if (!mounted || !authorized) return;
    entries.clear();
    custom.clear();
    edit();
    setState(() => status = next);
  }

  Future<bool> save({bool stay = false}) async {
    if (busy || !authorized) return false;
    if (custom.text.trim().isNotEmpty) {
      setState(() => error = '직접 입력한 질환을 추가하거나 입력란을 지운 뒤 저장해주세요.');
      return false;
    }
    final ticket = ++request;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final controller = ref.read(conditionLocalProvider.notifier);
      await controller.save(
        entries,
        status == 'EDITING' ? 'UNSET' : status,
        catalog?.version ?? '',
        expectedBaseVersion: editBaseVersion,
      );
      if (!mounted || ticket != request || !authorized) return false;
      draft.clear();
      dirty = false;
      unawaited(controller.sync().catchError((Object _) {}));
      memberFeedback(context, '기기에 저장했습니다. 연결되면 서버에 반영합니다.');
      if (!stay) {
        setState(() => leaving = true);
        Navigator.of(context).pop();
      }
      return true;
    } catch (e) {
      if (mounted && ticket == request) {
        setState(() {
          error = memberError(e);
          versionConflict =
              e is MemberFailure && e.kind == MemberFailureKind.conflict;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
    return false;
  }

  Future<void> configureMapUse() async {
    if (busy || !authorized) return;
    if (dirty && !await save(stay: true)) return;
    if (!mounted || !authorized) return;
    setState(() => busy = true);
    try {
      await ref.read(conditionLocalProvider.notifier).sync();
      if (!mounted || !authorized) return;
      final local = ref.read(conditionLocalProvider);
      if (local?.pending == true || local?.conflict == true) {
        setState(() => error = '기저질환을 서버에 반영한 뒤 병원 탐색 활용을 설정할 수 있어요.');
        return;
      }
      await ref.read(memberControllerProvider.notifier).reload();
      if (!mounted || !authorized) return;
      final base = ref.read(memberControllerProvider).health;
      if (base == null) return;
      // This is the existing per-disease consent flow, using a freshly authorized
      // server version. Recording and consent remain separate commits.
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => DiseaseSelectionScreen(base: base)),
      );
      if (!mounted || !authorized) return;
      await load();
    } catch (e) {
      if (mounted && authorized) setState(() => error = memberError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
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
    if (mounted) {
      setState(() => leaving = true);
      Navigator.of(context).pop();
    }
  }

  Widget row(String id) {
    final d = catalog!.byId(id)!;
    return CheckboxListTile(
      key: ValueKey('condition-$id'),
      contentPadding: EdgeInsets.zero,
      title: Text(d.name),
      subtitle: d.aliases.isEmpty
          ? null
          : Text(
              d.aliases.join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
      controlAffinity: ListTileControlAffinity.leading,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ERouteRadius.control),
      ),
      selectedTileColor: context.eroute.softBlue,
      selected: entries.any((e) => e.diseaseId == id),
      value: entries.any((e) => e.diseaseId == id),
      onChanged: busy ? null : (v) => toggle(id, v == true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final local = ref.watch(conditionLocalProvider);
    ref.listen(memberControllerProvider, (old, next) {
      if (next.access?.identity != owner || next.access?.granted != true) {
        request++;
        entries.clear();
        query.clear();
        custom.clear();
        draft.clear();
        setState(() {
          dirty = false;
          error = '로그인 또는 동의 상태가 변경되었습니다. 화면을 다시 열어주세요.';
        });
      }
    });
    final results = catalog?.search(committedQuery) ?? [];
    return PopScope(
      canPop: leaving || (!dirty && !busy),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) leave();
      },
      child: MemberScaffold(
        title: '기저질환',
        child: MemberGuard(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (error != null) MemberNotice(error!, error: true),
              if (local?.conflict == true || versionConflict) ...[
                const MemberNotice('서버의 정보가 변경되었습니다. 기기에 저장한 내용은 유지 중입니다.'),
                OutlinedButton(
                  onPressed: () async {
                    if (!await memberConfirm(
                      context,
                      '최신 내용으로 다시 편집할까요?',
                      '기기에 저장한 변경을 버리고 서버 기록을 불러옵니다.',
                      '최신 내용 불러오기',
                    )) {
                      return;
                    }
                    if (!mounted || !authorized) return;
                    await ref.read(memberControllerProvider.notifier).reload();
                    if (!mounted || !authorized) return;
                    await ref.read(conditionLocalProvider.notifier).useServer();
                    dirty = false;
                    await load();
                  },
                  child: const Text('최신 내용 확인'),
                ),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('기저질환 없음'),
                    showCheckmark: true,
                    selectedColor: context.eroute.softBlue,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    selected: status == 'NONE',
                    onSelected: busy ? null : (_) => reset('NONE'),
                  ),
                  ChoiceChip(
                    label: const Text('기저질환 있음'),
                    showCheckmark: true,
                    selectedColor: context.eroute.softBlue,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    selected: status == 'RECORDED' || status == 'EDITING',
                    onSelected: busy
                        ? null
                        : (_) => setState(
                            () => status = entries.isEmpty
                                ? 'EDITING'
                                : 'RECORDED',
                          ),
                  ),
                ],
              ),
              if (status == 'UNSET') const Text('아직 입력하지 않았어요'),
              if (loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (!loading && status == 'NONE')
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('등록된 기저질환이 없습니다.'),
                ),
              if (!loading && status != 'NONE') ...[
                const SizedBox(height: 16),
                TextField(
                  controller: query,
                  focusNode: queryFocus,
                  enabled: !busy,
                  decoration: InputDecoration(
                    labelText: '질환 검색',
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    hintText: '질환명 또는 다른 이름',
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(ERouteRadius.control),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(ERouteRadius.control),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    suffixIcon: query.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '검색어 지우기',
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              query.clear();
                              queryFocus.requestFocus();
                            },
                          ),
                  ),
                ),
                if (catalog == null)
                  OutlinedButton(
                    onPressed: load,
                    child: const Text('목록 다시 불러오기'),
                  ),
                if (catalog != null && committedQuery.trim().isEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    '자주 찾는 질환',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final id in catalog!.quickPicks)
                        FilterChip(
                          label: Text(catalog!.byId(id)!.name),
                          showCheckmark: true,
                          selectedColor: context.eroute.softBlue,
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                          selected: entries.any((e) => e.diseaseId == id),
                          onSelected: busy ? null : (v) => toggle(id, v),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                    header: true,
                    child: Text(
                      '카테고리로 찾기',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ConditionCategoryGrid(
                    catalog: catalog!,
                    selectedId: selectedCategory,
                    onSelected: busy
                        ? null
                        : (id) => setState(() {
                            selectedCategory = selectedCategory == id
                                ? null
                                : id;
                          }),
                    diseaseBuilder: row,
                  ),
                ] else if (catalog != null) ...[
                  const SizedBox(height: 24),
                  Semantics(
                    header: true,
                    liveRegion: true,
                    child: Text(
                      '검색 결과 ${results.length}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (results.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('찾는 질환이 없나요? 아래에서 직접 입력할 수 있어요.'),
                    ),
                  for (final d in results) row(d.id),
                ],
                const SizedBox(height: 16),
                Semantics(
                  header: true,
                  child: Text(
                    '선택한 질환 ${entries.length}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 8),
                if (entries.isEmpty) const Text('선택한 질환이 없습니다.'),
                for (final e in entries)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: memberCardShape(context),
                    child: ListTile(
                      contentPadding: const EdgeInsets.only(left: 16, right: 4),
                      title: Text(
                        e.standard
                            ? catalog?.byId(e.diseaseId!)?.name ?? e.name
                            : e.name,
                      ),
                      subtitle: !e.standard
                          ? const Text('직접 입력 · 병원 자동 매칭 제외')
                          : catalog?.byId(e.diseaseId!)?.active == false
                          ? const Text('이전 등록 질환 · 신규 선택 종료')
                          : null,
                      trailing: IconButton(
                        tooltip: '${e.name} 제거',
                        icon: const Icon(Icons.close),
                        onPressed: busy
                            ? null
                            : () {
                                entries.remove(e);
                                edit();
                              },
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => setState(() => customOpen = !customOpen),
                  icon: const Icon(Icons.add),
                  label: const Text('목록에 없는 질환 직접 입력'),
                ),
                if (customOpen) ...[
                  TextField(
                    controller: custom,
                    enabled: !busy,
                    maxLength: 2000,
                    minLines: 1,
                    maxLines: 4,
                    onChanged: (_) => edit(),
                    decoration: const InputDecoration(
                      labelText: '직접 입력한 질환',
                      helperText: '응급정보에 보관하며 병원 자동 매칭에는 사용하지 않습니다.',
                      helperMaxLines: 3,
                    ),
                  ),
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () {
                            if (custom.text.trim().isEmpty) return;
                            entries.add(EmergencyCondition.custom(custom.text));
                            final unique = uniqueConditions(entries);
                            entries
                              ..clear()
                              ..addAll(unique);
                            custom.clear();
                            edit();
                          },
                    child: const Text('직접 입력 질환 추가'),
                  ),
                ],
              ],
              if (!loading) ...[
                const SizedBox(height: 16),
                if (local != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: MemberCopy(
                        local.conflict
                            ? '기기에 저장됨 · 서버 변경 내용 확인 필요'
                            : local.pending
                            ? '기기에 저장됨 · 서버 동기화 대기 중'
                            : '저장된 기록은 서버와 동기화되어 있어요.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                MemberBusyButton(
                  busy: busy,
                  onPressed: local?.conflict == true || versionConflict
                      ? null
                      : save,
                  label: '기저질환 저장',
                ),
                if (status != 'NONE') ...[
                  const SizedBox(height: 24),
                  MemberPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            '병원 탐색에 활용',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const MemberCopy(
                          '가까운 병원 찾기에서 관련 진료과가 있는 병원을 알아보기 쉽게 표시합니다.',
                        ),
                        const SizedBox(height: 8),
                        if (ref
                                .watch(memberControllerProvider)
                                .health
                                ?.mapDiseaseSelection
                                .state ==
                            'CONFIRMED')
                          const Text('선택한 질환의 병원 탐색 활용이 설정되어 있어요.')
                        else if (ref
                                .watch(memberControllerProvider)
                                .health
                                ?.mapDiseaseSelection
                                .state ==
                            'RECONFIRM_REQUIRED')
                          const Text('기존 활용 선택을 다시 확인해주세요.')
                        else
                          const Text('질환을 저장한 뒤 활용할 질환을 직접 선택할 수 있어요.'),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed:
                              busy ||
                                  versionConflict ||
                                  local?.conflict == true ||
                                  !entries.any((e) => e.standard)
                              ? null
                              : configureMapUse,
                          child: Text(
                            dirty ? '저장하고 병원 탐색 활용 설정' : '병원 탐색 활용 설정',
                          ),
                        ),
                        if (!entries.any((e) => e.standard))
                          const Text(
                            '목록에서 선택한 질환이 있어야 설정할 수 있어요. 직접 입력한 질환은 활용하지 않습니다.',
                          ),
                      ],
                    ),
                  ),
                ],
                TextButton(
                  onPressed: busy ? null : () => reset('UNSET'),
                  child: const Text('기저질환 전체 초기화'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    request++;
    timer?.cancel();
    query.removeListener(searchChanged);
    query.dispose();
    queryFocus.dispose();
    custom.dispose();
    draft.clear();
    watch.stop();
    super.dispose();
  }
}
