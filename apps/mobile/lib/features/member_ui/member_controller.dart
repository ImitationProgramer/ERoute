import '../disease_personalization/condition_local_store.dart';
import 'remote_member_repository.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'member_contract.dart';

class MemberView {
  final MemberAccess? access;
  final MemberHealthSnapshot? health;
  final bool covered, loading;
  final String? error;
  const MemberView({
    this.access,
    this.health,
    this.covered = true,
    this.loading = false,
    this.error,
  });
}

final memberControllerProvider =
    StateNotifierProvider.autoDispose<MemberController, MemberView>((ref) {
      final repository = ref.watch(memberUiRepositoryProvider);
      final controller = MemberController(
        repository,
        conditions: repository is RemoteMemberRepository
            ? ref.read(conditionLocalProvider.notifier)
            : null,
      );
      if (repository is RemoteMemberRepository) {
        ref.listen<LocalConditions?>(
          conditionLocalProvider,
          controller.conditionsChanged,
        );
      }
      return controller;
    });

class MemberController extends StateNotifier<MemberView> {
  final MemberUiRepository repository;
  final ConditionLocalController? conditions;
  int _request = 0;
  bool foreground = true, _polling = false;
  MemberController(this.repository, {this.conditions})
    : super(const MemberView());
  void conditionsChanged(LocalConditions? old, LocalConditions? next) {
    if (old?.pending == true &&
        next?.pending == false &&
        mounted &&
        foreground &&
        !state.covered &&
        state.access?.userId == next?.userId) {
      unawaited(reload());
    }
  }

  void cover({bool clear = false}) {
    _request++;
    if (clear) {
      unawaited(conditions?.purge());
    } else {
      conditions?.suspend();
    }
    state = MemberView(
      access: clear ? null : state.access,
      health: clear ? null : state.health,
    );
  }

  Future<void> reload() async {
    final offlineAccess = !state.covered && state.access?.granted == true
        ? state.access
        : null;
    final request = ++_request;
    state = MemberView(
      access: state.access,
      health: state.health,
      loading: true,
    );
    try {
      final a = await repository.access();
      if (!mounted || request != _request || !foreground) return;
      final h = a.granted ? await repository.readHealth() : null;
      if (!mounted || request != _request || !foreground) return;
      final finalAccess = await repository.access();
      if (!mounted || request != _request || !foreground) return;
      if (finalAccess.identity != a.identity ||
          finalAccess.consentState != a.consentState) {
        cover(clear: true);
        // Do not expose the stale health response while authority is changing.
        state = const MemberView(error: '건강정보 동의 상태가 변경되었습니다. 다시 확인해주세요.');
        return;
      }
      if (h != null) {
        try {
          await conditions?.attach(a, h);
        } catch (_) {
          /* Server view remains available if device storage fails. */
        }
        if (!mounted || request != _request || !foreground) return;
      } else {
        await conditions?.purge();
      }
      state = MemberView(access: a, health: h, covered: false);
      unawaited(conditions?.sync().catchError((Object _) {}));
    } catch (e) {
      if (!mounted || request != _request) return;
      final revoked =
          e is MemberFailure &&
          (e.kind == MemberFailureKind.session ||
              e.kind == MemberFailureKind.consent);
      if (revoked) unawaited(conditions?.purge());
      state = MemberView(
        access: revoked ? null : state.access,
        health: revoked ? null : state.health,
        covered: revoked || offlineAccess == null,
        error: memberError(e),
      );
    }
  }

  Future<void> pollConsent() async {
    if (!foreground || state.covered || state.loading || _polling) return;
    _polling = true;
    final request = _request;
    try {
      final current = await repository.access();
      if (!mounted || request != _request) return;
      if (current.identity != state.access?.identity ||
          current.consentState != state.access?.consentState) {
        cover(clear: true);
        await reload();
      }
    } catch (e) {
      if (mounted &&
          request == _request &&
          e is MemberFailure &&
          (e.kind == MemberFailureKind.consent ||
              e.kind == MemberFailureKind.session)) {
        cover(clear: true);
        await reload();
      }
      // A connection failure is not a withdrawal. Resume always revalidates.
    } finally {
      if (!state.covered && foreground) {
        unawaited(conditions?.sync().catchError((Object _) {}));
      }
      _polling = false;
    }
  }
}
