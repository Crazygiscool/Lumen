import 'package:flutter/material.dart';

class JournalListScreen extends StatelessWidget {
  const JournalListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lumen Journal')),
      body: ListView(
        children: const [
          ListTile(title: Text('Entry 1')),
          ListTile(title: Text('Entry 2')),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.add),
        tooltip: 'New Entry',
      ),
    );
  }
}
