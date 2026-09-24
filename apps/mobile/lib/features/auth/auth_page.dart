import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/app_config.dart';
import '../../core/widgets/eroute_scaffold.dart';
import '../app_menu/app_session.dart';
import 'auth_repository.dart';

class AuthPage extends ConsumerStatefulWidget {
  final bool phoneChange;
  const AuthPage({super.key, this.phoneChange = false});
  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  late final AuthRepository repository;
  @override
  void initState() {
    super.initState();
    repository = ref.read(authRepositoryProvider);
  }

  final phone = TextEditingController(), credential = TextEditingController();
  String? transaction, proof, completionKey, error;
  bool busy = false,
      verified = false,
      newMember = false,
      changeRequired = false,
      terms = false,
      changeConfirmed = false;
  bool get development =>
      AppConfig.developmentAuth &&
      ['local', 'test'].contains(AppConfig.authEnvironment) &&
      (appFlavor == 'dev' || const bool.fromEnvironment('EROUTE_AUTOMATION'));
  @override
  void dispose() {
    if (transaction != null && proof != null) {
      repository.cancel(transaction!, proof!);
    }
    phone.dispose();
    credential.dispose();
    super.dispose();
  }

  Future<void> authenticate() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final repo = ref.read(authRepositoryProvider);
      proof = authNonce();
      final start = await repo.start(
        phone.text.trim(),
        proof!,
        phoneChange: widget.phoneChange,
      );
      transaction = start['transactionId'] as String;
      if (!development) {
        throw const AuthFailure(
          'PASS_PENDING',
          '휴대폰 본인확인 서비스 도입을 준비하고 있습니다. 병원 검색과 119 전화 연결은 이용할 수 있습니다.',
        );
      }
      final result = await repo.verifyDevelopment(
        transaction!,
        proof!,
        credential.text.trim(),
      );
      credential.clear();
      if (!mounted) return;
      setState(() {
        verified = true;
        newMember = result['newMember'] == true;
        changeRequired = result['phoneChangeRequired'] == true;
        completionKey = authNonce();
      });
      if (!newMember && !changeRequired && !widget.phoneChange) await finish();
    } catch (e) {
      if (mounted) setState(() => error = authError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> finish() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final user = await ref
          .read(authRepositoryProvider)
          .complete(
            transaction!,
            proof!,
            completionKey!,
            terms: terms ? 'signup-v1' : null,
            phoneChange: changeConfirmed,
            boundSession: widget.phoneChange,
          );
      transaction = null;
      proof = null;
      await ref.read(sessionControllerProvider.notifier).accept(user);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = authError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ERouteScaffold(
    title: widget.phoneChange ? '휴대폰 번호 변경' : '로그인 · 회원가입',
    showBack: true,
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '휴대폰 본인확인으로 시작하세요',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  '회원가입은 만 14세 이상부터 가능합니다. 병원 검색과 119 전화 연결은 가입 없이 이용할 수 있습니다.',
                ),
                const SizedBox(height: 24),
                if (development) ...[
                  const Text(
                    '개발 본인확인 · DEVELOPMENT\n실제 PASS 인증이 아닙니다. 로컬 bootstrap의 가상 계정만 사용하세요.',
                  ),
                  const SizedBox(height: 16),
                ],
                if (!verified) ...[
                  TextField(
                    controller: phone,
                    enabled: !busy,
                    keyboardType: development
                        ? TextInputType.text
                        : TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: development ? '가상 휴대폰 식별값' : '휴대폰 번호',
                      helperText: development
                          ? 'dev:member-a / dev:member-b / dev:operator'
                          : null,
                    ),
                  ),
                  if (development)
                    TextField(
                      controller: credential,
                      enabled: !busy,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: '로컬 개발 자격정보',
                        helperText: '비공개 credentials.json에서 확인한 값을 입력하세요.',
                      ),
                    ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: busy || !development ? null : authenticate,
                    child: Text(busy ? '본인확인 중…' : '휴대폰 본인확인'),
                  ),
                  if (!development)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        '본인확인 서비스 도입을 준비하고 있습니다. 현재 가입·로그인은 이용할 수 없습니다.',
                      ),
                    ),
                ] else ...[
                  const Text('서버에서 본인확인을 확인했습니다.'),
                  if (newMember) ...[
                    const SizedBox(height: 16),
                    const Text(
                      '가입 동의 (signup-v1)\n목적: 계정 식별 및 로그인 제공\n항목: 검증된 본인 식별키, 휴대폰 번호, 연령 통과 결과\n보유: 계정 이용 기간. 건강정보 동의는 별도로 받습니다.\n현재 문서는 개발 검증용이며 운영 동의 문안 확정 전에는 운영 가입이 제공되지 않습니다.',
                    ),
                    CheckboxListTile(
                      value: terms,
                      onChanged: busy
                          ? null
                          : (v) => setState(() => terms = v!),
                      title: const Text('가입 약관 및 개인정보 처리에 동의합니다 (필수)'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ],
                  if (changeRequired || widget.phoneChange)
                    CheckboxListTile(
                      value: changeConfirmed,
                      onChanged: busy
                          ? null
                          : (v) => setState(() => changeConfirmed = v!),
                      title: const Text('검증한 번호로 변경하고 기존 모든 로그인 세션을 종료합니다'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  FilledButton(
                    onPressed:
                        busy ||
                            newMember && !terms ||
                            (changeRequired || widget.phoneChange) &&
                                !changeConfirmed
                        ? null
                        : finish,
                    child: Text(
                      busy
                          ? '처리 중…'
                          : newMember
                          ? '동의하고 가입'
                          : '확인하고 로그인',
                    ),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () {
                            ref
                                .read(authRepositoryProvider)
                                .cancel(transaction!, proof!);
                            setState(() {
                              verified = false;
                              transaction = null;
                            });
                          },
                    child: const Text('본인확인 다시 하기'),
                  ),
                ],
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Semantics(liveRegion: true, child: Text(error!)),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class AuthGate extends ConsumerWidget {
  final Widget child;
  const AuthGate({super.key, required this.child});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session.authenticated) {
      return KeyedSubtree(
        key: ValueKey('${session.userId}:${session.generation}'),
        child: child,
      );
    }
    return ERouteScaffold(
      title: '로그인 안내',
      showBack: true,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                session.phase == SessionPhase.restoring
                    ? '로그인 상태를 확인하고 있습니다.'
                    : session.error ?? '로그인이 필요한 기능입니다.',
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const AuthPage()),
                ),
                child: const Text('로그인'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
