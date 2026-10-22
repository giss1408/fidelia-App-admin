import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import 'change_password_screen.dart';
import 'home_screen.dart';
import 'sign_in_screen.dart';

/// Decides what the admin sees: sign-in, the forced password change, or home.
class SessionGate extends ConsumerWidget {
  const SessionGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (!session.checked) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!session.signedIn) return const SignInScreen();
    if (session.mustChangePassword) return const ChangePasswordScreen(forced: true);
    return const HomeScreen();
  }
}
