import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'member_contract.dart';
import 'member_controller.dart';
import 'member_health_screens.dart';
import 'member_product.dart';
import 'member_widgets.dart';

class MemberProductSummary extends StatelessWidget {
  final MedicationProduct product;
  final bool details;
  const MemberProductSummary({
    super.key,
    required this.product,
    this.details = false,
  });
  @override
  Widget build(BuildContext context) => MemberPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(product.sourceLabel, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const MemberCategoryIcon(
              tone: MemberTone.medication,
              icon: Icons.medication_outlined,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(product.variant),
                  if (details) ...[
                    const SizedBox(height: 4),
                    Text(
                      '업체: ${product.manufacturer ?? '정보 미제공'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (details) ...[
          const SizedBox(height: 20),
          if (product.imageAsset != null)
            Image.asset(
              product.imageAsset!,
              height: 120,
              semanticLabel: '${product.name} 제품 이미지',
              errorBuilder: (_, _, _) => const ProductImageMissing(),
            )
          else
            const ProductImageMissing(),
          const SizedBox(height: 20),
          Text('제품 설명', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          MemberCopy(
            product.description?.trim().isNotEmpty == true
                ? product.description!
                : '설명 미제공',
          ),
        ],
      ],
    ),
  );
}

class ProductImageMissing extends StatelessWidget {
  const ProductImageMissing({super.key});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        Icon(
          Icons.medication_outlined,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 8),
        const Text('제품 이미지 없음'),
      ],
    ),
  );
}

class MemberMedicationSearchScreen extends ConsumerStatefulWidget {
  final MemberHealthSnapshot base;
  const MemberMedicationSearchScreen({super.key, required this.base});
  @override
  ConsumerState<MemberMedicationSearchScreen> createState() =>
      _MemberMedicationSearchScreenState();
}

class _MemberMedicationSearchScreenState
    extends ConsumerState<MemberMedicationSearchScreen> {
  final query = TextEditingController();
  final queryFocus = FocusNode();
  late final String? owner;
  @override
  void initState() {
    super.initState();
    owner = ref.read(memberControllerProvider).access?.identity;
  }

  @override
  void dispose() {
    query.clear();
    query.dispose();
    queryFocus.dispose();
    super.dispose();
  }

  void search() {
    if (query.value.composing.isValid && !query.value.composing.isCollapsed) {
      return;
    }
    FocusScope.of(context).unfocus();
    ref.read(medicationSearchProvider.notifier).search(query.text);
  }

  Future<void> latest() async {
    query.clear();
    ref.read(medicationSearchProvider.notifier).clear();
    await ref.read(memberControllerProvider.notifier).reload();
    if (mounted && !ref.read(memberControllerProvider).covered) close();
  }

  void close() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      nav.pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const MemberMedicationScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(medicationProductRepositoryProvider).available) {
      return MemberScaffold(
        title: '약 검색',
        child: MemberGuard(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const MemberNotice(
                '약 검색 준비 중입니다. 복용약 이름과 메모를 직접 입력해 저장할 수 있습니다.',
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => openMemberPage(
                  context,
                  MemberFieldEditor(base: widget.base),
                ),
                child: const Text('직접 입력'),
              ),
            ],
          ),
        ),
      );
    }
    final state = ref.watch(medicationSearchProvider);
    final view = ref.watch(memberControllerProvider);
    final stale = view.health?.version != widget.base.version;
    ref.listen(memberControllerProvider, (_, next) {
      if (next.access == null ||
          next.access!.identity != owner ||
          !next.access!.granted) {
        query.clear();
        ref.read(medicationSearchProvider.notifier).clear();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).popUntil((r) => r.isFirst);
          }
        });
      }
    });
    return MemberScaffold(
      title: '약 검색',
      child: MemberGuard(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            MemberCopy(
              ref.watch(medicationProductRepositoryProvider).sourceLabel,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            const MemberCopy('약 이름으로 찾고 함량과 제형을 확인하세요.'),
            const SizedBox(height: 20),
            TextField(
              controller: query,
              focusNode: queryFocus,
              enabled: !stale,
              maxLength: 80,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: '약 이름 검색',
                hintText: '제품 이름 입력',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: '검색어 지우기',
                  onPressed: () {
                    query.clear();
                    queryFocus.requestFocus();
                    ref.read(medicationSearchProvider.notifier).clear();
                  },
                  icon: const Icon(Icons.close),
                ),
              ),
              onChanged: (_) =>
                  ref.read(medicationSearchProvider.notifier).clear(),
              onSubmitted: (_) => search(),
            ),
            const SizedBox(height: 8),
            MemberBusyButton(
              busy: state.busy,
              onPressed: stale ? null : search,
              label: '검색',
            ),
            const SizedBox(height: 20),
            if (stale) ...[
              const MemberNotice(
                '복용약 정보가 변경되었습니다. 최신 목록을 확인한 뒤 다시 등록해주세요.',
                error: true,
              ),
              TextButton(onPressed: latest, child: const Text('최신 목록 확인')),
            ] else if (state.busy)
              Semantics(liveRegion: true, child: const Text('제품을 검색하고 있어요.'))
            else if (state.error != null) ...[
              MemberNotice(state.error!, error: true),
              OutlinedButton(onPressed: search, child: const Text('다시 검색')),
            ] else if (state.attempted && state.products.isEmpty)
              const MemberPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('검색 결과가 없어요.'),
                    SizedBox(height: 8),
                    MemberCopy('제품 이름을 다시 확인하거나 직접 입력해주세요.'),
                  ],
                ),
              )
            else if (!state.attempted)
              const MemberCopy('제품 포장에 적힌 이름을 입력해주세요.'),
            if (!stale && !state.busy)
              for (final product in state.products)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    margin: EdgeInsets.zero,
                    shape: memberCardShape(context),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: const MemberCategoryIcon(
                        tone: MemberTone.medication,
                        icon: Icons.medication_outlined,
                      ),
                      title: Text(
                        product.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(product.variant),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => openMemberPage(
                        context,
                        MemberProductConfirmationScreen(
                          base: widget.base,
                          product: product,
                        ),
                      ),
                    ),
                  ),
                ),
            if (!stale &&
                !state.busy &&
                (state.error != null ||
                    state.attempted && state.products.isEmpty)) ...[
              const SizedBox(height: 16),
              const MemberCopy('찾는 약이 없나요? 직접 입력하기'),
              OutlinedButton.icon(
                onPressed: () => openMemberPage(
                  context,
                  MemberFieldEditor(base: widget.base),
                ),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('약 이름 직접 입력'),
              ),
            ],
            const SizedBox(height: 8),
            TextButton(onPressed: close, child: const Text('검색 취소')),
          ],
        ),
      ),
    );
  }
}

class MemberProductConfirmationScreen extends ConsumerWidget {
  final MemberHealthSnapshot base;
  final MedicationProduct product;
  const MemberProductConfirmationScreen({
    super.key,
    required this.base,
    required this.product,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(memberControllerProvider);
    final stale =
        view.health?.version != base.version ||
        view.access?.consentEpoch != base.consentEpoch;
    return MemberScaffold(
      title: '제품 확인',
      child: MemberGuard(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const MemberCopy('찾는 제품이 맞나요?'),
            const SizedBox(height: 16),
            MemberProductSummary(product: product, details: true),
            const SizedBox(height: 20),
            const MemberCopy(
              '제품정보를 확인한 뒤 내 복용 기록에 추가하세요. 복용 메모는 다음 화면에서 선택적으로 남길 수 있어요.',
            ),
            const SizedBox(height: 20),
            if (stale)
              const MemberNotice(
                '정보가 변경되었습니다. 검색 화면으로 돌아가 최신 목록을 확인해주세요.',
                error: true,
              ),
            FilledButton(
              onPressed: stale
                  ? null
                  : () => openMemberPage(
                      context,
                      MemberFieldEditor(base: base, selectedProduct: product),
                    ),
              child: const Text('복용 메모 · 등록으로'),
            ),
            TextButton(
              onPressed: stale
                  ? null
                  : () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(
                        builder: (_) => MemberFieldEditor(base: base),
                      ),
                    ),
              child: const Text('선택 대신 직접 입력'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('선택 취소 · 검색으로'),
            ),
          ],
        ),
      ),
    );
  }
}
