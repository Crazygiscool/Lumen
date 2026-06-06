import 'package:flutter/material.dart';

class EntryCard extends StatelessWidget {
  final String title;
  final String preview;
  final String kind;
  final List<String> tags;
  final VoidCallback onTap;

  const EntryCard({
    super.key,
    required this.title,
    required this.preview,
    required this.kind,
    this.tags = const [],
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: ListTile(
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                kind,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(preview, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 4,
                  children: tags
                      .map((t) => Chip(
                            label: Text(t,
                                style:
                                    const TextStyle(fontSize: 10)),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ))
                      .toList(),
                ),
              ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
