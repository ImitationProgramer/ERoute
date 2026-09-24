import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/eroute_scaffold.dart';
import '../app_menu/app_session.dart';
import '../auth/auth_page.dart';
import '../auth/auth_repository.dart';

class MemberProfilePage extends ConsumerWidget {
  const MemberProfilePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return ERouteScaffold(
      title: '내 정보',
      showBack: true,
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            session.userSummary ?? '',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text(
            session.user?['source'] == 'DEVELOPMENT'
                ? '개발 본인확인 · DEVELOPMENT'
                : '휴대폰 본인확인',
          ),
          if (session.user?['role'] == 'OPERATOR')
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('운영자 계정에는 회원 의료정보 접근 권한이 없습니다.'),
            ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const AuthPage(phoneChange: true),
              ),
            ),
            child: const Text('휴대폰 번호 변경'),
          ),
          OutlinedButton(
            onPressed: () async {
              try {
                await ref
                    .read(authRepositoryProvider)
                    .request('POST', '/api/v1/auth/logout-all');
                await ref.read(sessionControllerProvider.notifier).signOut();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(authError(e))));
                }
              }
            },
            child: const Text('모든 기기에서 로그아웃'),
          ),
          OutlinedButton(
            onPressed: () async {
              try {
                final complete = await ref
                    .read(authRepositoryProvider)
                    .retryLogout();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        complete
                            ? '서버 로그아웃 처리가 완료되었습니다.'
                            : '서버 폐기를 확인하지 못했습니다. 다시 시도해주세요.',
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(authError(e))));
                }
              }
            },
            child: const Text('미확인 로그아웃 처리 재시도'),
          ),
        ],
      ),
    );
  }
}
