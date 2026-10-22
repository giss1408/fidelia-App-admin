import 'package:flutter/material.dart';

/// Placeholder until the "À traiter" list lands.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('À traiter')),
      body: const SizedBox.shrink(),
    );
  }
}
