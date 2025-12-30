import 'package:flutter/material.dart';

class EntryCard extends StatelessWidget {
  final String title;
  final String preview;
  final VoidCallback onTap;

  const EntryCard({
    super.key,
    required this.title,
    required this.preview,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(preview, maxLines: 2, overflow: TextOverflow.ellipsis),
        onTap: onTap,
      ),
    );
  }
}
