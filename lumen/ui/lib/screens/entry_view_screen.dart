import 'package:flutter/material.dart';

class EntryViewScreen extends StatelessWidget {
  final String entryTitle;
  final String entryText;

  const EntryViewScreen({super.key, required this.entryTitle, required this.entryText});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(entryTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(entryText),
      ),
    );
  }
}
