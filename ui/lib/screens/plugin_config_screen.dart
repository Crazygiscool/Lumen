import 'package:flutter/material.dart';

class PluginConfigScreen extends StatelessWidget {
  const PluginConfigScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plugin Config')),
      body: const Center(child: Text('Plugin configuration goes here.')),
    );
  }
}
