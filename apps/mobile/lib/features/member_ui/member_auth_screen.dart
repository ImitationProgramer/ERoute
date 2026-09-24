import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app_menu/app_session.dart';
import 'member_contract.dart';
import 'member_controller.dart';
import 'member_health_screens.dart';
import 'member_widgets.dart';
import '../auth/password_policy.dart';
import '../../app/router.dart';

class MemberAuthScreen extends ConsumerStatefulWidget {
  final bool signup, reauthenticate;
  final String? returnTo;
  const MemberAuthScreen({
    super.key,
    this.signup = false,
    this.reauthenticate = false,
    this.returnTo,
  });
  @override
  ConsumerState<MemberAuthScreen> createState() => _MemberAuthScreenState();
}

class _MemberAuthScreenState extends ConsumerState<MemberAuthScreen> {
  final form = GlobalKey<FormState>();
  final phone = TextEditingController(),
      password = TextEditingController(),
      confirmation = TextEditingController();
  bool visible = false,
      confirmVisible = false,
      terms = false,
      age14 = false,
      busy = false;
  String? error;
  @override
  void dispose() {
    for (final c in [phone, password, confirmation]) {
      c.clear();
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    if (widget.signup && (!terms || !age14)) {
      setState(() => error = '필수 가입 동의와 만 14세 이상 자기확인을 확인해주세요.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (widget.reauthenticate) {
        await ref
            .read(authRepositoryProvider)
            .reauthenticatePassword(password.text);
        password.clear();
        if (mounted) Navigator.of(context).pop();
        return;
      }
      final user = await ref
          .read(memberUiRepositoryProvider)
          .authenticate(
            phone.text,
            password.text,
            signup: widget.signup,
            terms: terms,
            age14OrOlder: age14,
          );
      if (!mounted) return;
      password.clear();
      confirmation.clear();
      await ref.read(sessionControllerProvider.notifier).accept(user);
      await ref.read(memberControllerProvider.notifier).reload();
      if (!mounted) return;
      memberFeedback(context, ref.read(memberResultLabelProvider));
      final destination = widget.returnTo ?? AppRoutes.emergencyProfile;
      Navigator.of(context).pushAndRemoveUntil(
        buildAppRoute(RouteSettings(name: destination)),
        (route) => route.isFirst,
      );
    } catch (e) {
      if (mounted) setState(() => error = memberError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget passwordField(bool confirm) => TextFormField(
    controller: confirm ? confirmation : password,
    enabled: !busy,
    obscureText: confirm ? !confirmVisible : !visible,
    autocorrect: false,
    enableSuggestions: false,
    autofillHints: [
      widget.signup ? AutofillHints.newPassword : AutofillHints.password,
    ],
    textInputAction: confirm || !widget.signup
        ? TextInputAction.done
        : TextInputAction.next,
    onFieldSubmitted: (_) {
      if (confirm || !widget.signup) submit();
    },
    decoration: InputDecoration(
      labelText: confirm ? '비밀번호 확인' : '비밀번호',
      border: const OutlineInputBorder(),
      suffixIcon: IconButton(
        tooltip: (confirm ? confirmVisible : visible) ? '비밀번호 숨기기' : '비밀번호 표시',
        onPressed: busy
            ? null
            : () => setState(() {
                if (confirm) {
                  confirmVisible = !confirmVisible;
                } else {
                  visible = !visible;
                }
              }),
        icon: Icon(
          (confirm ? confirmVisible : visible)
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
        ),
      ),
    ),
    validator: (v) =>
        passwordValidation(v) ??
        ((v ?? '').isEmpty
            ? '비밀번호를 입력해주세요.'
            : confirm &&
                  normalizePassword(v ?? '') != normalizePassword(password.text)
            ? '비밀번호가 일치하지 않습니다.'
            : null),
  );
  @override
  Widget build(BuildContext context) => MemberScaffold(
    title: widget.reauthenticate
        ? '비밀번호 재확인'
        : widget.signup
        ? '회원가입'
        : '로그인',
    child: AutofillGroup(
      child: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 16),
            Icon(
              Icons.person_outline,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 20),
            Text(
              widget.signup ? 'ERoute 시작하기' : '다시 만나 반가워요',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const MemberCopy('휴대폰 번호와 비밀번호로 계정을 이용하세요.'),
            const SizedBox(height: 28),
            if (!widget.reauthenticate)
              TextFormField(
                controller: phone,
                enabled: !busy,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '휴대폰 번호',
                  hintText: '010-0000-0000',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    RegExp(
                      r'^010\d{8}$',
                    ).hasMatch((v ?? '').replaceAll(RegExp(r'[ -]'), ''))
                    ? null
                    : '010으로 시작하는 휴대폰 번호 11자리를 입력해주세요.',
              ),
            const SizedBox(height: 20),
            passwordField(false),
            const SizedBox(height: 8),
            const MemberCopy('비밀번호 15~128자 · 한글과 공백을 사용할 수 있어요'),
            if (widget.signup) ...[
              const SizedBox(height: 20),
              passwordField(true),
              const SizedBox(height: 20),
              const MemberPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('가입 동의 · signup-password-v1'),
                    SizedBox(height: 8),
                    MemberCopy(
                      '휴대폰 번호와 비밀번호 자격정보를 계정 식별·로그인 제공에 사용합니다. 번호 소유·실명·연령을 확인하는 절차는 아닙니다.',
                    ),
                    SizedBox(height: 8),
                    MemberCopy('건강정보 처리 동의는 가입 후 별도로 받습니다.'),
                  ],
                ),
              ),
              CheckboxListTile(
                value: age14,
                onChanged: busy ? null : (v) => setState(() => age14 = v!),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('만 14세 이상입니다 (자기확인)'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: terms,
                onChanged: busy ? null : (v) => setState(() => terms = v!),
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('가입 약관 및 개인정보 처리에 동의합니다 (필수)'),
              ),
            ],
            const SizedBox(height: 20),
            if (error != null) ...[
              MemberNotice(error!, error: true),
              const SizedBox(height: 16),
            ],
            MemberBusyButton(
              busy: busy,
              onPressed: submit,
              label: widget.reauthenticate
                  ? '비밀번호 확인'
                  : widget.signup
                  ? '동의하고 가입'
                  : '로그인',
            ),
            const SizedBox(height: 12),
            if (!widget.reauthenticate)
              TextButton(
                onPressed: busy
                    ? null
                    : () => widget.signup
                          ? (Navigator.canPop(context)
                                ? Navigator.maybePop(context)
                                : Navigator.of(context).pushReplacement(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const MemberAuthScreen(),
                                    ),
                                  ))
                          : openMemberPage(
                              context,
                              MemberAuthScreen(
                                signup: true,
                                returnTo: widget.returnTo,
                              ),
                            ),
                child: Text(widget.signup ? '로그인으로 돌아가기' : '회원가입'),
              ),
            const SizedBox(height: 16),
            const MemberCopy('번호 입력만으로 번호 소유·실명·연령이 확인되지는 않습니다.'),
            const SizedBox(height: 12),
            const MemberCopy('현재 번호 변경과 비밀번호 찾기는 지원하지 않습니다.'),
          ],
        ),
      ),
    ),
  );
}
