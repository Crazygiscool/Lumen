import 'package:flutter/material.dart';

Color statusColor(String status) {
  switch (status) {
    case 'done':
      return Colors.green;
    case 'in_progress':
      return Colors.blue;
    case 'todo':
      return Colors.grey;
    default:
      return Colors.grey;
  }
}

class StatusBadge extends StatelessWidget {
  final String status;
  final double size;

  const StatusBadge(this.status, {super.key, this.size = 8});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: statusColor(status),
        shape: BoxShape.circle,
      ),
    );
  }
}
