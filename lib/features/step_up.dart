import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_repository.dart';
import '../core/config/env.dart';
import '../core/net/api_exception.dart';
import '../core/providers.dart';

/// Runs [action]; if the server answers that a fresh proof is needed (`403 step_up_required`: roles, suspensions, wallet changes ask for
/// the password AND a recent authenticator code), asks for both, re-proves at the auth service, and runs [action] once more.
/// Cancelling the dialog rethrows the original refusal. With fidelia's own sign-in (no auth service) the refusal just propagates.
Future<T> withStepUp<T>(BuildContext context, WidgetRef ref, Future<T> Function() action, {bool? authMode}) async {
  try {
    return await action();
  } on ClientErrorException catch (e) {
    if (!(authMode ?? Env.authMode) || e.statusCode != 403 || e.detail != 'step_up_required' || !context.mounted) rethrow;
    final proof = await _ask(context);
    if (proof == null) rethrow;
    try {
      await ref.read(authRepositoryProvider).stepUp(password: proof.$1, totp: proof.$2);
    } on AccountActionException catch (a) {
      throw ClientErrorException(403, a.message, detail: 'step_up_failed');
    }
    return action();
  }
}

Future<(String, String)?> _ask(BuildContext context) {
  final password = TextEditingController();
  final totp = TextEditingController();
  return showDialog<(String, String)>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Confirmez que c’est bien vous'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(key: const Key('stepup-password'), controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Mot de passe')),
        const SizedBox(height: 8),
        TextField(
          key: const Key('stepup-totp'),
          controller: totp,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(labelText: 'Code d’authentification', counterText: ''),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        TextButton(
          key: const Key('stepup-confirm'),
          onPressed: () => Navigator.pop(context, (password.text, totp.text)),
          child: const Text('Confirmer'),
        ),
      ],
    ),
  );
}
