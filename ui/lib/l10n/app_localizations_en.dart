// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Lumen';

  @override
  String get journal => 'Journal';

  @override
  String get notes => 'Notes';

  @override
  String get tasks => 'Tasks';

  @override
  String get kanban => 'Kanban';

  @override
  String get mindMap => 'Mind Map';

  @override
  String get settings => 'Settings';

  @override
  String get lock => 'Lock';

  @override
  String get unlock => 'Unlock';

  @override
  String get search => 'Search';

  @override
  String get searchHint => 'Search entries...';

  @override
  String get all => 'All';

  @override
  String get addEntry => 'Add Entry';

  @override
  String get importStoic => 'Import from Stoic';

  @override
  String get selectStoicExport => 'Select Stoic Export (dir or .zip)';

  @override
  String get enterPassword => 'Enter Password';

  @override
  String get password => 'Password';

  @override
  String get startImport => 'Start Import';

  @override
  String get importComplete => 'Import Complete';

  @override
  String importedEntries(Object count) {
    return 'Imported $count entries';
  }

  @override
  String get done => 'Done';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get confirmDelete => 'Delete this entry?';

  @override
  String get typeQueryToSearch => 'Type a query to search';

  @override
  String get noResultsFound => 'No results found';

  @override
  String get untitled => '(untitled)';

  @override
  String get focusMode => 'Focus mode (Ctrl+.)';

  @override
  String get searchShortcut => 'Search (Ctrl+F)';

  @override
  String get newEntry => 'New Entry';

  @override
  String get selectKind => 'Select kind';

  @override
  String get entryBody => 'Entry body';

  @override
  String get author => 'Author';

  @override
  String get created => 'Created';

  @override
  String get statusTodo => 'todo';

  @override
  String get statusInProgress => 'in_progress';

  @override
  String get statusDone => 'done';

  @override
  String get enterPasswordToDecrypt =>
      'This entry is encrypted. Enter password to decrypt.';
}
