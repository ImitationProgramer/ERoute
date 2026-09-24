import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_repository.dart';

enum SessionPhase {
  restoring,
  signedOut,
  authenticated,
  temporarilyUnavailable,
}

class AppSession {
  final SessionPhase phase;
  final Map<String, dynamic>? user;
  final int generation;
  final String? error;
  const AppSession.signedOut()
    : phase = SessionPhase.signedOut,
      user = null,
      generation = 0,
      error = null;
  const AppSession({
    required this.phase,
    this.user,
    this.generation = 0,
    this.error,
  });
  bool get authenticated => phase == SessionPhase.authenticated && user != null;
  String? get userSummary => user?['phone'] as String?;
  String? get userId => user?['userId'] as String?;
}

typedef SessionState = AppSession;

abstract interface class SessionSource {
  Future<Map<String, dynamic>?> restore();
  Future<bool> signOut();
}

class RemoteSessionSource implements SessionSource {
  final AuthRepository repository;
  RemoteSessionSource(this.repository);
  @override
  Future<Map<String, dynamic>?> restore() => repository.restore();
  @override
  Future<bool> signOut() => repository.signOut();
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(),
);
final sessionSourceProvider = Provider<SessionSource>(
  (ref) => RemoteSessionSource(ref.watch(authRepositoryProvider)),
);
final sessionControllerProvider =
    AsyncNotifierProvider<SessionController, AppSession>(SessionController.new);
final sessionProvider = Provider<AppSession>(
  (ref) =>
      ref.watch(sessionControllerProvider).valueOrNull ??
      const AppSession(phase: SessionPhase.restoring),
);

class SessionController extends AsyncNotifier<AppSession> {
  AuthRepository get repository => ref.read(authRepositoryProvider);
  @override
  Future<AppSession> build() async {
    final repo = repository;
    repo.onExpired = () => state = const AsyncData(AppSession.signedOut());
    ref.onDispose(() => repo.onExpired = null);
    try {
      final user = await ref.read(sessionSourceProvider).restore();
      return user == null ? const AppSession.signedOut() : _signedIn(user);
    } catch (e) {
      return AppSession(
        phase: SessionPhase.temporarilyUnavailable,
        error: authError(e),
      );
    }
  }

  AppSession _signedIn(Map<String, dynamic> user) => AppSession(
    phase: SessionPhase.authenticated,
    user: user,
    generation: repository.generation,
  );
  Future<void> accept(Map<String, dynamic> serverUser) async {
    state = AsyncData(_signedIn(serverUser));
  }

  Future<Map<String, dynamic>> revalidate() async {
    final user = await repository.me();
    state = AsyncData(_signedIn(user));
    return user;
  }

  Future<bool> signOut() async {
    state = const AsyncData(AppSession.signedOut());
    return ref.read(sessionSourceProvider).signOut();
  }
}
