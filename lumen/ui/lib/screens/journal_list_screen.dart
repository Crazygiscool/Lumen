import 'package:flutter/material.dart';
import '../ffi_bridge.dart';

class JournalListScreen extends StatefulWidget {
  const JournalListScreen({super.key});

  @override
  State<JournalListScreen> createState() => _JournalListScreenState();
}

class _JournalListScreenState extends State<JournalListScreen> {
  final lumenCore = LumenCore();
  List<String> entries = [];

  @override
  void initState() {
    super.initState();
    _refreshEntries();
  }

  void _refreshEntries() {
    setState(() {
      entries = lumenCore.listEntries();
    });
  }

  void _addEntry() async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final textController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Journal Entry'),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(hintText: 'Write your entry...'),
        ),
        actions: [
          TextButton(
            onPressed: () {
              lumenCore.addEntry(id, textController.text, 'author', 'password');
              Navigator.of(context).pop();
              _refreshEntries();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lumen Journal'),
        centerTitle: true,
        backgroundColor: Colors.deepPurple,
      ),
      body: Container(
        color: Colors.grey[100],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Welcome to Lumen',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Reflect freely. Store safely. Extend endlessly.',
                    style: TextStyle(fontSize: 16, color: Colors.black54),
                  ),
                ],
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? const Center(child: Text('No journal entries yet. Tap + to add one!', style: TextStyle(fontSize: 16)))
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final id = entries[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          elevation: 2,
                          child: ListTile(
                            leading: const Icon(Icons.book, color: Colors.deepPurple),
                            title: Text('Entry #$id', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: const Text('Tap to view details (demo)'),
                            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                            onTap: () {
                              // TODO: Navigate to entry details
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addEntry,
        child: const Icon(Icons.add),
        backgroundColor: Colors.deepPurple,
        tooltip: 'New Entry',
      ),
    );
  }
}
