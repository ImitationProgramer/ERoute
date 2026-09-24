import '../features/member_ui/member_product.dart';
import '../features/member_ui/member_product_screens.dart';
import 'member_product_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/eroute_theme.dart';
import '../features/app_menu/app_session.dart';
import '../features/member_ui/member_contract.dart';
import '../features/member_ui/member_controller.dart';
import '../features/member_ui/member_widgets.dart';
import '../features/member_ui/member_auth_screen.dart';
import '../features/member_ui/member_health_screens.dart';
import '../features/member_ui/member_profile_screen.dart';
import 'member_preview_repository.dart';

const scenarioLabels = <PreviewScenario, String>{
  PreviewScenario.saved: '등록된 상태',
  PreviewScenario.empty: '빈 상태',
  PreviewScenario.loading: '로딩',
  PreviewScenario.readFailure: '조회 실패',
  PreviewScenario.saveFailure: '저장·인증 실패',
  PreviewScenario.consentRequired: '동의 필요',
  PreviewScenario.versionConflict: '저장 시 버전 충돌',
  PreviewScenario.consentConflict: '저장 시 동의 변경',
  PreviewScenario.unsaved: '미저장 변경사항',
  PreviewScenario.deletionFailed: '삭제 처리 실패',
  PreviewScenario.deletionComplete: '삭제 완료 · 백업 확인 중',
};

enum PreviewPage {
  health,
  account,
  login,
  signup,
  medications,
  consent,
  allergy,
  condition,
  note,
  medicationForm,
  productSearch,
}

const pageLabels = <PreviewPage, String>{
  PreviewPage.health: '내 응급정보',
  PreviewPage.account: '내 정보',
  PreviewPage.login: '로그인',
  PreviewPage.signup: '회원가입',
  PreviewPage.medications: '복용약 목록',
  PreviewPage.consent: '건강정보 관리',
  PreviewPage.allergy: '알레르기 편집',
  PreviewPage.condition: '기저질환 편집',
  PreviewPage.note: '응급 메모 편집',
  PreviewPage.medicationForm: '복용약 직접 입력',
  PreviewPage.productSearch: '약 검색',
};

class MemberPreviewHost extends StatefulWidget {
  const MemberPreviewHost({super.key});
  @override
  State<MemberPreviewHost> createState() => _MemberPreviewHostState();
}

class _MemberPreviewHostState extends State<MemberPreviewHost> {
  late final auth = PreviewAuthRepository();
  late final repository = PreviewMemberRepository(auth);
  late final products = PreviewProductRepository();
  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      memberUiRepositoryProvider.overrideWithValue(repository),
      conditionEditorBuilderProvider.overrideWithValue(
        (base) => MemberFieldEditor(field: HealthField.conditions, base: base),
      ),
      medicationProductRepositoryProvider.overrideWithValue(products),
      memberPrivacyProvider.overrideWithValue(PreviewPrivacy()),
      memberResultLabelProvider.overrideWithValue(
        '미리보기에서 반영됨 · 실제 서버는 변경되지 않습니다.',
      ),
    ],
    child: MemberPreviewApp(repository: repository, products: products),
  );
}

class MemberPreviewApp extends ConsumerStatefulWidget {
  final PreviewMemberRepository repository;
  final PreviewProductRepository products;
  const MemberPreviewApp({
    super.key,
    required this.repository,
    required this.products,
  });
  @override
  ConsumerState<MemberPreviewApp> createState() => _MemberPreviewAppState();
}

class _MemberPreviewAppState extends ConsumerState<MemberPreviewApp> {
  ThemeMode theme = ThemeMode.light;
  double scale = 1;
  bool changing = false, toolsExpanded = false;
  PreviewPage page = PreviewPage.health;
  GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
  Future<void> select(PreviewScenario scenario, PreviewPage next) async {
    if (changing) return;
    setState(() => changing = true);
    ref.read(memberControllerProvider.notifier).cover(clear: true);
    widget.repository.reset(scenario);
    await ref
        .read(sessionControllerProvider.notifier)
        .accept(widget.repository.user);
    // Let the session listener invalidate the old account before loading the new one.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final pending = ref.read(memberControllerProvider.notifier).reload();
    if (scenario != PreviewScenario.loading) await pending;
    if (!mounted) return;
    setState(() {
      page = next;
      changing = false;
      navigator = GlobalKey<NavigatorState>();
    });
  }

  Widget screen() => switch (page) {
    PreviewPage.health => const MemberEmergencyScreen(),
    PreviewPage.account => const MemberAccountScreen(),
    PreviewPage.login => const MemberAuthScreen(),
    PreviewPage.signup => const MemberAuthScreen(signup: true),
    PreviewPage.medications => const MemberMedicationScreen(),
    PreviewPage.consent => const MemberConsentScreen(),
    PreviewPage.allergy => MemberFieldEditor(
      field: HealthField.allergies,
      base: widget.repository.data,
      initialText: widget.repository.scenario == PreviewScenario.unsaved
          ? '아직 저장하지 않은 가상 알레르기 메모'
          : null,
    ),
    PreviewPage.condition => MemberFieldEditor(
      field: HealthField.conditions,
      base: widget.repository.data,
    ),
    PreviewPage.note => MemberFieldEditor(
      field: HealthField.note,
      base: widget.repository.data,
    ),
    PreviewPage.productSearch => MemberMedicationSearchScreen(
      base: widget.repository.data,
    ),
    PreviewPage.medicationForm => MemberFieldEditor(
      base: widget.repository.data,
    ),
  };
  void controls() {
    showDialog<void>(
      context: navigator.currentContext!,
      builder: (context) {
        var scenario = widget.repository.scenario;
        var next = page;
        var productScenario = widget.products.scenario;
        return StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: const Text('UI 미리보기 설정'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<PreviewPage>(
                      key: ValueKey(next),
                      initialValue: next,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '화면'),
                      items: PreviewPage.values
                          .map(
                            (p) => DropdownMenuItem(
                              value: p,
                              child: Text(pageLabels[p]!),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setDialog(() => next = v!),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<PreviewScenario>(
                      initialValue: scenario,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '상태'),
                      items: PreviewScenario.values
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(
                                scenarioLabels[s]!,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setDialog(() {
                        scenario = v!;
                        if (v == PreviewScenario.unsaved) {
                          next = PreviewPage.allergy;
                        }
                      }),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<PreviewProductScenario>(
                      initialValue: productScenario,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '가상 제품 검색 상태',
                      ),
                      items: PreviewProductScenario.values
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(switch (s) {
                                PreviewProductScenario.standard =>
                                  '함량·제형이 다른 제품',
                                PreviewProductScenario.noResults => '결과 없음',
                                PreviewProductScenario.failure => '검색 실패',
                                PreviewProductScenario.noDescription => '설명 없음',
                                PreviewProductScenario.noImage => '이미지 없음',
                                PreviewProductScenario.longName => '긴 제품명',
                              }),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setDialog(() => productScenario = v!),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '제품 검색어: 가상해봄\n모두 UI 검수용 가상 제품이며 실제 식약처 조회 결과가 아닙니다.',
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      '테스트 로그인\n010-1234-5678 / preview-password-only\n다른 비밀번호는 인증 실패를 재현합니다.',
                    ),
                    const SizedBox(height: 12),
                    const Text('가상 데이터만 사용합니다. 상태를 적용하면 현재 미리보기와 초안을 초기화합니다.'),
                    const SizedBox(height: 12),
                    const Text(
                      'Android preview · debug\ncom.eroute.eroute_mobile.preview\n0.1.0+1 · member-ui-v3',
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  widget.products.scenario = productScenario;
                  select(scenario, next);
                },
                child: const Text('상태 적용'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => MemberSecurityScope(
    child: MaterialApp(
      navigatorKey: navigator,
      title: 'ERoute UI Preview',
      debugShowCheckedModeBanner: false,
      theme: ERouteTheme.light(),
      darkTheme: ERouteTheme.dark(),
      themeMode: theme,
      home: screen(),
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: Theme.of(context).brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: Overlay.wrap(
            child: Material(
              child: Column(
                verticalDirection: VerticalDirection.up,
                children: [
                  Expanded(
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(scale),
                        padding: MediaQuery.of(
                          context,
                        ).padding.copyWith(top: 0),
                      ),
                      child: child!,
                    ),
                  ),
                  SafeArea(
                    bottom: false,
                    child: Container(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      padding: const EdgeInsets.only(left: 12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: MemberCopy(
                                  'UI 미리보기 · 가상 데이터',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                              IconButton(
                                tooltip: toolsExpanded
                                    ? '검수 도구 접기'
                                    : '검수 도구 펼치기',
                                onPressed: () => setState(
                                  () => toolsExpanded = !toolsExpanded,
                                ),
                                icon: Icon(
                                  toolsExpanded
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                ),
                              ),
                            ],
                          ),
                          if (toolsExpanded)
                            Wrap(
                              alignment: WrapAlignment.end,
                              children: [
                                IconButton(
                                  tooltip: '테마 전환',
                                  onPressed: () => setState(
                                    () => theme = theme == ThemeMode.dark
                                        ? ThemeMode.light
                                        : ThemeMode.dark,
                                  ),
                                  icon: const Icon(Icons.brightness_6_outlined),
                                ),
                                IconButton(
                                  tooltip: '글자 크기 전환',
                                  onPressed: () => setState(
                                    () => scale = scale == 1 ? 2 : 1,
                                  ),
                                  icon: const Icon(Icons.text_fields),
                                ),
                                IconButton(
                                  tooltip: '미리보기 설정',
                                  onPressed: changing ? null : controls,
                                  icon: changing
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.tune),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
