import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/router.dart';
import '../../../core/theme/eroute_tokens.dart';
import '../../../core/widgets/eroute_card.dart';
import '../../../core/widgets/eroute_scaffold.dart';
import '../../emergency_call/emergency_call_coordinator.dart';
import '../../emergency_call/emergency_call_state.dart';
import '../data/asset_guide_repository.dart';
import '../data/guide_source_launcher.dart';
import '../domain/guide_article.dart';

class GuideIndexPage extends ConsumerStatefulWidget {
  final String category;
  final bool review;
  const GuideIndexPage({
    super.key,
    required this.category,
    this.review = false,
  });
  @override
  ConsumerState<GuideIndexPage> createState() => _GuideIndexPageState();
}

class _GuideIndexPageState extends ConsumerState<GuideIndexPage> {
  late Future<GuideCatalog> catalog;
  @override
  void initState() {
    super.initState();
    catalog = ref.read(guideRepositoryProvider).catalog();
  }

  @override
  Widget build(BuildContext context) {
    final actions = widget.category == 'actions';
    return _GuideShell(
      toolbar: widget.review ? '개발 검수' : '가이드',
      children: [
        if (widget.review) const _ReviewNotice(),
        _Heading(actions ? '응급상황 대처요령' : '응급처치 가이드'),
        Text(
          actions
              ? '신고할 때, 위치를 설명할 때, 구급차를 기다릴 때의 안내입니다.'
              : '주제와 적용 대상을 확인한 뒤 안내를 선택하세요.',
          style: ERouteTypography.body,
        ),
        const SizedBox(height: 16),
        const _GuideEmergencyAction(),
        const SizedBox(height: 24),
        FutureBuilder<GuideCatalog>(
          future: catalog,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _GuideError(
                onRetry: () => setState(() {
                  catalog = ref.read(guideRepositoryProvider).catalog();
                }),
              );
            }
            if (!snapshot.hasData) return const _LoadingGuide();
            final loaded = snapshot.data!;
            final entries = loaded.entries
                .where(
                  (e) =>
                      e.category ==
                      (actions ? 'EMERGENCY_ACTION' : 'FIRST_AID'),
                )
                .toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _GuideTopicCard(
                      entry: entry,
                      review: widget.review,
                      damaged: loaded.unavailableIds.contains(entry.id),
                    ),
                  ),
                const SizedBox(height: 4),
                const Text('목록과 안내 본문은 인터넷 없이 볼 수 있습니다.'),
              ],
            );
          },
        ),
      ],
    );
  }
}

class GuideDetailPage extends ConsumerStatefulWidget {
  final String id;
  final bool review;
  const GuideDetailPage({super.key, required this.id, this.review = false});
  @override
  ConsumerState<GuideDetailPage> createState() => _GuideDetailPageState();
}

class _GuideDetailPageState extends ConsumerState<GuideDetailPage> {
  late Future<(GuideCatalog, GuideArticle?)> detail;
  String toolbar = '응급가이드';
  @override
  void initState() {
    super.initState();
    detail = load();
  }

  Future<(GuideCatalog, GuideArticle?)> load() async {
    final repo = ref.read(guideRepositoryProvider);
    final catalog = await repo.catalog();
    final entry = catalog.find(widget.id);
    if (mounted) {
      setState(
        () =>
            toolbar = entry?.category == 'FIRST_AID' ? '응급처치 가이드' : '응급상황 대처요령',
      );
    }
    return (catalog, await repo.article(widget.id, review: widget.review));
  }

  @override
  Widget build(BuildContext context) => _GuideShell(
    toolbar: widget.review ? '개발 검토본' : toolbar,
    children: [
      if (widget.review) const _ReviewNotice(),
      FutureBuilder<(GuideCatalog, GuideArticle?)>(
        future: detail,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Column(
              children: [
                const _GuideEmergencyAction(),
                _GuideError(
                  onRetry: () => setState(() {
                    detail = load();
                  }),
                ),
              ],
            );
          }
          if (!snapshot.hasData) {
            return const Column(
              children: [_GuideEmergencyAction(), _LoadingGuide()],
            );
          }
          final (catalog, article) = snapshot.data!;
          final entry = catalog.find(widget.id);
          if (entry == null) {
            return const Column(
              children: [
                _Heading('안내를 찾을 수 없습니다'),
                Text('이전 화면에서 다른 항목을 선택해주세요.'),
                SizedBox(height: 16),
                _GuideEmergencyAction(),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _Heading(entry.title)),
                  const SizedBox(width: 12),
                  _GuideThumbnail(entry: entry, width: 64),
                ],
              ),
              Text(entry.categoryLabel, style: ERouteTypography.label),
              const SizedBox(height: 12),
              Text(entry.summary, style: ERouteTypography.body),
              const SizedBox(height: 16),
              const _GuideEmergencyAction(),
              const SizedBox(height: 24),
              if (entry.category == 'FIRST_AID') ...[
                GuideSafetyNotice(text: catalog.disclaimer),
                const SizedBox(height: 24),
              ],
              if (article == null)
                _GuideError(
                  onRetry: () => setState(() {
                    detail = load();
                  }),
                )
              else
                _GuideReader(article: article),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 16),
              const _Heading('공식 출처', small: true),
              _SourceCard(
                source: entry.source,
                latestValidation: entry.latestValidation,
              ),
            ],
          );
        },
      ),
    ],
  );
}

class GuideReviewHome extends StatelessWidget {
  const GuideReviewHome({super.key});
  @override
  Widget build(BuildContext context) => _GuideShell(
    toolbar: '개발 검수',
    children: [
      const _ReviewNotice(),
      const _Heading('응급 가이드 원고 검수'),
      const Text('일반 경로와 같은 출처 기반 초안을 확인합니다. 의료전문가 승인본이 아닙니다.'),
      const SizedBox(height: 16),
      for (final item in [('actions', '대처요령 4건'), ('firstAid', '응급처치 가이드 13건')])
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: OutlinedButton(
            onPressed: () =>
                pushAppRoute(context, '${AppRoutes.guideReview}/${item.$1}'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(item.$2),
            ),
          ),
        ),
    ],
  );
}

class _GuideShell extends StatelessWidget {
  final String toolbar;
  final List<Widget> children;
  const _GuideShell({required this.toolbar, required this.children});
  @override
  Widget build(BuildContext context) => Localizations.override(
    context: context,
    locale: const Locale('ko'),
    delegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    child: ERouteScaffold(
      title: toolbar,
      showBack: true,
      opaqueTopBar: true,
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SingleChildScrollView(
              key: const ValueKey('guide-scroll'),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _Heading extends StatelessWidget {
  final String text;
  final bool small;
  const _Heading(this.text, {this.small = false});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: ERouteTypography.pageTitle.copyWith(fontSize: small ? 18 : 22),
      ),
    ),
  );
}

class _Notice extends StatelessWidget {
  final String title, text;
  const _Notice(this.title, this.text);
  @override
  Widget build(BuildContext context) => ERouteCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(title, small: true),
        Text(text, style: ERouteTypography.body),
      ],
    ),
  );
}

class _ReviewNotice extends StatelessWidget {
  const _ReviewNotice();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(bottom: 20),
    child: _Notice('출처 기반 초안 · 의료승인 없음', '공식 자료를 근거로 한 초안이며 의료전문가 승인본이 아닙니다.'),
  );
}

class _GuideEmergencyAction extends ConsumerWidget {
  const _GuideEmergencyAction();
  @override
  Widget build(BuildContext context, WidgetRef ref) => OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 52),
      foregroundColor: context.eroute.emergency,
    ),
    onPressed: ref.watch(emergencyCallStateProvider) == EmergencyCallStatus.idle
        ? () => ref.read(emergencyCallProvider).confirm(context)
        : null,
    icon: const Icon(Icons.phone_outlined),
    label: const Text('119 전화 연결'),
  );
}

class _GuideThumbnail extends StatelessWidget {
  final GuideEntry entry;
  final double width;
  const _GuideThumbnail({required this.entry, required this.width});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: width,
        height: width * 10 / 16,
        child: entry.thumbnailAsset == null
            ? ColoredBox(
                color: context.eroute.softBlue,
                child: Icon(
                  Icons.article_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
              )
            : Image.asset(
                entry.thumbnailAsset!,
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                errorBuilder: (context, error, stack) => ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.article_outlined,
                    key: ValueKey('thumbnail-fallback-${entry.id}'),
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
      ),
    ),
  );
}

class _GuideTopicCard extends StatelessWidget {
  final GuideEntry entry;
  final bool review, damaged;
  const _GuideTopicCard({
    required this.entry,
    required this.review,
    required this.damaged,
  });
  @override
  Widget build(BuildContext context) {
    final status = damaged ? '본문을 읽지 못함' : '안내 읽기';
    void open() =>
        pushAppRoute(context, AppRoutes.guide(entry.id, review: review));
    return Semantics(
      container: true,
      button: true,
      label: '${entry.title}. ${entry.summary} $status',
      onTap: open,
      excludeSemantics: true,
      child: ERouteCard(
        key: ValueKey('guide-card-${entry.id}'),
        onTap: open,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked =
                constraints.maxWidth < 300 ||
                MediaQuery.textScalerOf(context).scale(16) >= 24;
            final information = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  style: ERouteTypography.body.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(entry.summary, style: ERouteTypography.body),
                const SizedBox(height: 8),
                Text(
                  status,
                  style: ERouteTypography.label.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            );
            if (stacked) {
              return Column(
                key: ValueKey('guide-stacked-${entry.id}'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _GuideThumbnail(
                    entry: entry,
                    width: constraints.maxWidth.clamp(0, 240).toDouble(),
                  ),
                  const SizedBox(height: 12),
                  information,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _GuideThumbnail(entry: entry, width: 112),
                const SizedBox(width: 16),
                Expanded(child: information),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One copy supplied by the canonical manifest, shared by every first-aid detail.
class GuideSafetyNotice extends StatelessWidget {
  final String text;
  const GuideSafetyNotice({super.key, required this.text});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _GuideReader extends StatelessWidget {
  final GuideArticle article;
  const _GuideReader({required this.article});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final section in article.sections) ...[
        _Heading(section.title, small: true),
        if (section.intro != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(section.intro!, style: ERouteTypography.body),
          ),
        for (var i = 0; i < section.items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Semantics(
              container: true,
              label: section.type == GuideSectionType.actionSteps
                  ? '${i + 1}단계. ${section.items[i]}'
                  : section.items[i],
              excludeSemantics: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: section.type == GuideSectionType.actionSteps
                        ? BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(24),
                          )
                        : null,
                    child: Text(
                      section.type == GuideSectionType.actionSteps
                          ? '${i + 1}'
                          : '•',
                      style: ERouteTypography.body.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      section.items[i],
                      style: ERouteTypography.body.copyWith(
                        height: 1.65,
                        fontWeight: section.type == GuideSectionType.actionSteps
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
      ],
    ],
  );
}

class _SourceCard extends ConsumerStatefulWidget {
  final GuideSource source;
  final GuideSource? latestValidation;
  const _SourceCard({required this.source, this.latestValidation});
  @override
  ConsumerState<_SourceCard> createState() => _SourceCardState();
}

class _SourceCardState extends ConsumerState<_SourceCard> {
  bool busy = false, failed = false;
  Future<void> open() async {
    if (busy) return;
    setState(() {
      busy = true;
      failed = false;
    });
    var success = false;
    try {
      final uri = Uri.tryParse(widget.source.url);
      if (uri != null && allowedGuideSource(uri)) {
        success = await ref
            .read(guideSourceLauncherProvider)
            .open(uri)
            .timeout(const Duration(seconds: 8), onTimeout: () => false);
      }
    } catch (_) {
      /* Keep the bundled article on screen. */
    }
    if (mounted) {
      setState(() {
        busy = false;
        failed = !success;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.source;
    final uri = Uri.tryParse(s.url);
    final validSource = uri != null && allowedGuideSource(uri);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ERouteCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${s.publisher} · ${s.title}',
              style: ERouteTypography.body.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              s.finalModifiedDate == null
                  ? '게시일 ${s.publishedAt?.replaceAll('-', '.') ?? '미표시'}'
                  : '최종수정 ${s.finalModifiedDate!.replaceAll('-', '.')}',
              style: ERouteTypography.body,
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: busy || !validSource ? null : open,
              icon: const Icon(Icons.open_in_new),
              label: Text(validSource ? '공식 자료 보기' : '공식 자료를 열 수 없습니다'),
            ),
            ExpansionTile(
              key: ValueKey('source-disclosure-${s.title}'),
              tilePadding: EdgeInsets.zero,
              title: const Text('출처 상세 정보'),
              children: [
                const Text('공식 자료 보기에는 인터넷 연결이 필요합니다.'),
                if (widget.latestValidation != null) ...[
                  const Text('최신 기준 확인'),
                  _SourceCard(source: widget.latestValidation!),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '출처 URL · ${Uri.tryParse(s.url)?.host ?? '확인 불가'}\n'
                    '출처 확인일 ${s.checkedAt.replaceAll('-', '.')}\n'
                    '이용조건 · ${_licenseLabel(s.license)}',
                    style: ERouteTypography.body,
                  ),
                ),
                TextButton.icon(
                  onPressed: validSource
                      ? () async {
                          await Clipboard.setData(ClipboardData(text: s.url));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('출처 URL을 복사했습니다.')),
                            );
                          }
                        }
                      : null,
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('출처 URL 복사'),
                ),
                const SizedBox(height: 12),
              ],
            ),
            if (failed)
              Semantics(
                liveRegion: true,
                child: Text(
                  '공식 자료를 열지 못했습니다. 인터넷 연결을 확인해주세요. 앱의 안내는 계속 읽을 수 있습니다.',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LoadingGuide extends StatelessWidget {
  const _LoadingGuide();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(24),
    child: Center(
      child: CircularProgressIndicator(semanticsLabel: '앱에 포함된 안내 읽는 중'),
    ),
  );
}

class _GuideError extends StatelessWidget {
  final VoidCallback onRetry;
  const _GuideError({required this.onRetry});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      children: [
        const Text('이 안내를 읽지 못했습니다. 이전 화면에서 다른 항목을 선택하거나 다시 시도해주세요.'),
        TextButton(onPressed: onRetry, child: const Text('다시 읽기')),
      ],
    ),
  );
}

String _licenseLabel(String license) => switch (license) {
  'KOGL_TYPE_1' => '공공누리 제1유형 · 출처표시',
  'KOGL_TYPE_4' => '공공누리 제4유형 · 출처표시·상업적 이용금지·변경금지',
  _ => '미확인 (UNCONFIRMED)',
};
