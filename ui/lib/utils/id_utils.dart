import 'dart:math';

String generateLumenId() {
  final ts = DateTime.now().millisecondsSinceEpoch;
  final rand = Random().nextInt(0xFFFFFFFF);
  return '${ts}_${rand.toRadixString(16).padLeft(8, '0')}';
}
