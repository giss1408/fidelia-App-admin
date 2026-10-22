import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/auth_repository.dart';
import 'auth/token_store.dart';
import 'net/api_client.dart';

/// Wiring for the whole app. Nothing here holds UI state beyond the session.

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

/// The current access token, renewed first when it is past its hour.
final Provider<TokenProvider> freshTokenProvider = Provider<TokenProvider>((ref) {
  final tokenStore = ref.watch(tokenStoreProvider);
  // Read lazily: the auth repository itself talks through the API client.
  return () async {
    final token = await tokenStore.readToken();
    if (token == null || token.isEmpty || !isTokenExpired(token)) return token;
    return await ref.read(authRepositoryProvider).refresh() ? tokenStore.readToken() : token;
  };
});

final Provider<ApiClient> apiClientProvider = Provider<ApiClient>((ref) {
  final tokenStore = ref.watch(tokenStoreProvider);
  final client = ApiClient(
    tokenProvider: ref.watch(freshTokenProvider),
    // A 401 anyway (token revoked, clock skew): renew once and replay.
    onRefresh: () => ref.read(authRepositoryProvider).refresh(),
    // Renewal refused too: the session is over. Clear it once, here.
    onUnauthorized: () async {
      await tokenStore.clear();
      ref.read(sessionProvider.notifier).onTokenRejected();
    },
  );
  ref.onDispose(client.close);
  return client;
});

final Provider<AuthRepository> authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    client: ref.watch(apiClientProvider),
    tokenStore: ref.watch(tokenStoreProvider),
  );
});

/// Whether an admin is signed in, and whether they must pick a new password.
class SessionState {
  const SessionState({
    required this.signedIn,
    this.username,
    this.checked = false,
    this.mustChangePassword = false,
  });

  final bool signedIn;
  final String? username;
  final bool mustChangePassword;

  /// Whether the stored token has been inspected yet, so the app does not
  /// flash the sign-in screen at an admin who is already signed in.
  final bool checked;
}

class SessionNotifier extends Notifier<SessionState> {
  @override
  SessionState build() {
    Future.microtask(restore);
    return const SessionState(signedIn: false);
  }

  /// Reads the stored token at startup.
  Future<void> restore() async {
    final auth = ref.read(authRepositoryProvider);
    final valid = await auth.hasValidSession();
    state = SessionState(
      signedIn: valid,
      username: valid ? await auth.currentUsername() : null,
      checked: true,
      mustChangePassword: valid && await auth.mustChangePassword(),
    );
  }

  Future<SignInResult> signIn({required String phone, required String password}) async {
    final auth = ref.read(authRepositoryProvider);
    final result = await auth.signIn(phone: phone, password: password);
    if (result is SignedIn) {
      state = SessionState(
        signedIn: true,
        username: await auth.currentUsername(),
        checked: true,
        mustChangePassword: result.mustChangePassword,
      );
    }
    return result;
  }

  Future<void> changePassword({String? current, required String newPassword}) async {
    final auth = ref.read(authRepositoryProvider);
    await auth.changePassword(current: current, newPassword: newPassword);
    state = SessionState(
      signedIn: true,
      username: await auth.currentUsername(),
      checked: true,
      mustChangePassword: await auth.mustChangePassword(),
    );
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    state = const SessionState(signedIn: false, checked: true);
  }

  /// Called when the server rejects our token mid-session.
  void onTokenRejected() {
    state = const SessionState(signedIn: false, checked: true);
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);
