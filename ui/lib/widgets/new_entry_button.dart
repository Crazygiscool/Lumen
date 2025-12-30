import 'package:flutter/material.dart';

class NewEntryButton extends StatelessWidget {
  final VoidCallback onPressed;

  const NewEntryButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: onPressed,
      child: const Icon(Icons.add),
    );
  }
}
