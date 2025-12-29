import 'package:flutter/material.dart';
import 'dart:ui';
import '../ffi_bridge.dart';

class JournalListScreen extends StatefulWidget {
  const JournalListScreen({super.key});

  @override
  State<JournalListScreen> createState() => _JournalListScreenState();
}

class _JournalListScreenState extends State<JournalListScreen> {
  final lumenCore = LumenCore();
  List<String> entries = [];
  int streak = 0;

  @override
  void initState() {
    super.initState();
    _refreshEntries();
    _calculateStreak();
  }

  void _refreshEntries() {
    setState(() {
      entries = lumenCore.listEntries();
      _calculateStreak();
    });
  }

  void _calculateStreak() {
    // Assume entry IDs are timestamps (ms since epoch)
    final today = DateTime.now();
    final dates = entries.map((id) {
      final dt = DateTime.fromMillisecondsSinceEpoch(int.tryParse(id) ?? 0);
      return DateTime(dt.year, dt.month, dt.day);
    }).toSet().toList();
    dates.sort((a, b) => b.compareTo(a));
    int streakCount = 0;
    DateTime? prev = today;
    for (final d in dates) {
      if (prev == null) break;
      if (d == DateTime(prev.year, prev.month, prev.day)) {
        streakCount++;
        prev = prev.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    setState(() {
      streak = streakCount;
    });
  }

  void _addEntry() async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final textController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey[900]
                : Colors.white,
            gradient: Theme.of(context).brightness == Brightness.dark
                ? null
                : const LinearGradient(
                    colors: [Color(0xFFFFF8E1), Color(0xFFFFD600)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            boxShadow: const [BoxShadow(color: Colors.orangeAccent, blurRadius: 12)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.edit, color: Colors.orange, size: 28),
                  const SizedBox(width: 8),
                  Text('Write a Journal Entry', style: Theme.of(context).textTheme.headlineMedium),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: textController,
                maxLines: 6,
                decoration: const InputDecoration(
                  hintText: 'Let your thoughts shine... 🌞',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFA726),
                      foregroundColor: Colors.white,
                      elevation: 8,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.save),
                    label: const Text('Save'),
                    onPressed: () {
                      lumenCore.addEntry(id, textController.text, 'author', 'password');
                      Navigator.of(context).pop();
                      _refreshEntries();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: null,
        centerTitle: true,
        backgroundColor: isDark ? Colors.black : null,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              color: Colors.black,
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.black
                  : Colors.grey[100],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: isDark ? Colors.grey[900]?.withOpacity(0.5) : Colors.white.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [BoxShadow(color: Colors.orangeAccent.withOpacity(0.2), blurRadius: 8)],
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Row(
                              children: [
                                Icon(Icons.local_fire_department, color: Colors.deepOrange, size: 28),
                                const SizedBox(width: 8),
                                Text('Streak: ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                                Text('$streak days', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.brown)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Reflect freely. Store safely. Extend endlessly.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: isDark ? Colors.white70 : null,
                            ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: entries.isEmpty
                      ? Center(child: Text('No journal entries yet. Tap + to add one!', style: TextStyle(fontSize: 16, color: isDark ? Colors.white70 : null)))
                      : ListView.builder(
                          itemCount: entries.length,
                          itemBuilder: (context, index) {
                            final id = entries[index];
                            final dt = DateTime.fromMillisecondsSinceEpoch(int.tryParse(id) ?? 0);
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                  child: Card(
                                    color: isDark ? Colors.grey[900]?.withOpacity(0.7) : Colors.white.withOpacity(0.6),
                                    elevation: 6,
                                    child: ListTile(
                                      leading: Icon(Icons.book_rounded, color: Colors.orangeAccent, size: 32),
                                      title: Text('Entry #$id', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : null)),
                                      subtitle: Text('Created: ${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}', style: TextStyle(color: isDark ? Colors.white70 : Colors.brown)),
                                      trailing: Icon(Icons.arrow_forward_ios, size: 18, color: Colors.deepOrange),
                                      onTap: () {
                                        // TODO: Navigate to entry details
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addEntry,
        child: const Icon(Icons.wb_sunny),
        tooltip: 'New Entry',
        backgroundColor: isDark ? Colors.deepOrange : null,
      ),
    );
  }
}
