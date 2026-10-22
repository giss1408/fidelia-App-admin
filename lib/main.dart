import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/env.dart';
import 'ui/theme.dart';

void main() {
  Env.assertHttpsInRelease();
  runApp(const ProviderScope(child: FideliaAdminApp()));
}

class FideliaAdminApp extends StatelessWidget {
  const FideliaAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fidelia Admin',
      debugShowCheckedModeBanner: false,
      theme: fideliaTheme(),
      home: const Scaffold(body: Center(child: Text('Fidelia Admin'))),
    );
  }
}
