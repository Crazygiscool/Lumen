import 'package:flutter/material.dart';

class LumenAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;

  const LumenAppBar({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title),
      elevation: 2,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
