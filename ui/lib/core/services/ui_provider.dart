import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum LumenSection {
  journal(Icons.article, 'Journal'),
  notes(Icons.note, 'Notes'),
  tasks(Icons.checklist, 'Tasks'),
  board(Icons.dashboard, 'Kanban'),
  mind(Icons.bubble_chart, 'Mind Map'),
  settings(Icons.settings, 'Settings');

  final IconData icon;
  final String label;
  const LumenSection(this.icon, this.label);
}

class SectionNotifier extends Notifier<LumenSection> {
  @override
  LumenSection build() => LumenSection.journal;

  void setSection(LumenSection section) => state = section;
}

final sectionProvider = NotifierProvider<SectionNotifier, LumenSection>(SectionNotifier.new);

class FocusModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final focusModeProvider = NotifierProvider<FocusModeNotifier, bool>(FocusModeNotifier.new);
