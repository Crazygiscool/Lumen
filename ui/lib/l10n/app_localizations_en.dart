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
  String importedEntries(int count) {
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

  @override
  String get currentUser => 'Current User';

  @override
  String get userManagement => 'User Management';

  @override
  String get switchUser => 'Switch User';

  @override
  String get registerNewUser => 'Register New User';

  @override
  String get admin => 'Admin';

  @override
  String get member => 'Member';

  @override
  String get vaultPassword => 'Vault Password';

  @override
  String get newUsername => 'New Username';

  @override
  String get register => 'Register';

  @override
  String get account => 'Account';

  @override
  String get security => 'Security';

  @override
  String get setPassword => 'Set Password';

  @override
  String get changePassword => 'Change Password';

  @override
  String get lockOnStart => 'Lock on Start';

  @override
  String get general => 'General';

  @override
  String get theme => 'Theme';

  @override
  String get notifications => 'Notifications';

  @override
  String get sync => 'Sync';

  @override
  String get syncSettings => 'Sync Settings';

  @override
  String get data => 'Data';

  @override
  String get exportImport => 'Export / Import';

  @override
  String get advanced => 'Advanced';

  @override
  String get developerMode => 'Developer Mode';

  @override
  String get resetApp => 'Reset App';

  @override
  String get welcomeToLumen => 'Welcome to Lumen';

  @override
  String get lumenDescription =>
      'A digital sanctuary for your thoughts. Private, encrypted, and offline-first.';

  @override
  String get discoverFeatures => 'Discover Features';

  @override
  String get whyLumen => 'Why Lumen?';

  @override
  String get aesEncryption => 'AES-256 Encryption';

  @override
  String get encryptionDesc =>
      'Your data is encrypted before it ever touches the disk.';

  @override
  String get expressiveJournaling => 'Expressive Journaling';

  @override
  String get journalingDesc =>
      'Capture moods, prompts, and rich text reflections.';

  @override
  String get deepProductivity => 'Deep Productivity';

  @override
  String get productivityDesc =>
      'Integrated Kanban boards, Mind Maps, and Task tracking.';

  @override
  String get modularExtensible => 'Modular & Extensible';

  @override
  String get modularDesc =>
      'A trait-based plugin system to build your own tools.';

  @override
  String get back => 'Back';

  @override
  String get getStarted => 'Get Started';

  @override
  String get secureYourVault => 'Secure Your Vault';

  @override
  String get setPasswordDesc =>
      'Set a master password. This cannot be recovered if lost.';

  @override
  String get preferredUsername => 'Preferred Username (Author)';

  @override
  String get confirmPassword => 'Confirm Password';

  @override
  String get createVault => 'Create Vault';

  @override
  String get passwordsDoNotMatch => 'Passwords do not match';

  @override
  String get passwordCannotBeEmpty => 'Password cannot be empty';

  @override
  String get failedToSetPassword => 'Failed to set password';
}
