import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a WhatsApp link; true when something handled it. Injectable so tests
/// never open anything. The URI carries a code or password: never log it.
typedef WhatsappLauncher = Future<bool> Function(Uri uri);

final Provider<WhatsappLauncher> whatsappLauncherProvider = Provider<WhatsappLauncher>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);
